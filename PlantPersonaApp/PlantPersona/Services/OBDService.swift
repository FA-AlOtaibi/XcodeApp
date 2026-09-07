import Foundation
import Network
import ExternalAccessory

@MainActor
final class OBDService: ObservableObject {
    @Published var status = "غير متصل"
    @Published var isBusy = false
    @Published var lastResult: OBDScanResult?
    @Published var usbAccessories: [String] = []

    private var connection: NWConnection?

    func scanUSBAccessories() {
        let accessories = EAAccessoryManager.shared().connectedAccessories
        usbAccessories = accessories.map { accessory in
            let protocols = accessory.protocolStrings.isEmpty ? "بدون بروتوكول تطبيق معلن" : accessory.protocolStrings.joined(separator: ", ")
            return "\(accessory.name) — \(accessory.manufacturer) — \(protocols)"
        }
        status = usbAccessories.isEmpty
            ? "ما لقيت OBD USB متوافقًا مع ExternalAccessory. محولات USB-Serial العادية لا يفتحها iOS كتطبيق عام."
            : "تم اكتشاف \(usbAccessories.count) ملحق USB/Accessory. يلزم أن يسمح بروتوكوله للتطبيق بالتواصل."
    }

    func scanWiFi(host: String, port: UInt16) async {
        guard !isBusy else { return }
        isBusy = true
        status = "جاري الاتصال بـ OBD…"
        defer { isBusy = false }
        do {
            let conn = NWConnection(host: NWEndpoint.Host(host), port: NWEndpoint.Port(rawValue: port)!, using: .tcp)
            connection = conn
            try await start(conn)
            status = "متصل — تهيئة ELM327"
            _ = try await command("ATZ", wait: 1.2)
            _ = try await command("ATE0")
            _ = try await command("ATL0")
            _ = try await command("ATS0")
            _ = try await command("ATH0")
            _ = try await command("ATSP0", wait: 0.6)

            status = "قراءة أكواد الأعطال والبيانات الحية…"
            let dtcRaw = try await command("03", wait: 1.2)
            let rpmRaw = try await command("010C")
            let speedRaw = try await command("010D")
            let coolantRaw = try await command("0105")
            let throttleRaw = try await command("0111")
            let loadRaw = try await command("0104")
            let voltageRaw = try await command("ATRV")

            let result = OBDScanResult(
                dtcs: parseDTCs(dtcRaw),
                live: OBDLiveData(
                    rpm: parsePID(rpmRaw, pid: "0C").flatMap { bytes in bytes.count >= 2 ? Double(bytes[0] * 256 + bytes[1]) / 4.0 : nil },
                    speedKmh: parsePID(speedRaw, pid: "0D").flatMap { $0.first.map(Double.init) },
                    coolantC: parsePID(coolantRaw, pid: "05").flatMap { $0.first.map { Double($0) - 40 } },
                    throttlePercent: parsePID(throttleRaw, pid: "11").flatMap { $0.first.map { Double($0) * 100.0 / 255.0 } },
                    engineLoadPercent: parsePID(loadRaw, pid: "04").flatMap { $0.first.map { Double($0) * 100.0 / 255.0 } },
                    voltage: parseVoltage(voltageRaw)
                ),
                rawSummary: "DTC: \(clean(dtcRaw))"
            )
            lastResult = result
            status = result.dtcs.isEmpty ? "اكتمل الفحص — لا توجد أكواد مخزنة" : "اكتمل الفحص — \(result.dtcs.count) كود أعطال"
            conn.cancel()
        } catch {
            connection?.cancel()
            status = "فشل الاتصال: \(error.localizedDescription)"
        }
    }

    func contextText() -> String? {
        guard let r = lastResult else { return nil }
        var parts = [String]()
        parts.append("DTCs: \(r.dtcs.isEmpty ? "لا يوجد" : r.dtcs.joined(separator: ", "))")
        if let v = r.live.rpm { parts.append("RPM: \(Int(v))") }
        if let v = r.live.speedKmh { parts.append("Speed: \(Int(v)) km/h") }
        if let v = r.live.coolantC { parts.append("Coolant: \(Int(v)) C") }
        if let v = r.live.throttlePercent { parts.append(String(format: "Throttle: %.1f%%", v)) }
        if let v = r.live.engineLoadPercent { parts.append(String(format: "Engine load: %.1f%%", v)) }
        if let v = r.live.voltage { parts.append(String(format: "Voltage: %.2fV", v)) }
        return parts.joined(separator: "\n")
    }

    private func start(_ conn: NWConnection) async throws {
        try await withCheckedThrowingContinuation { continuation in
            var resumed = false
            conn.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    if !resumed { resumed = true; continuation.resume() }
                case .failed(let error):
                    if !resumed { resumed = true; continuation.resume(throwing: error) }
                default: break
                }
            }
            conn.start(queue: DispatchQueue(label: "ayn.obd.socket"))
        }
    }

    private func command(_ text: String, wait: Double = 0.35) async throws -> String {
        guard let connection else { throw URLError(.notConnectedToInternet) }
        let data = Data((text + "\r").utf8)
        try await withCheckedThrowingContinuation { continuation in
            connection.send(content: data, completion: .contentProcessed { error in
                if let error { continuation.resume(throwing: error) } else { continuation.resume() }
            })
        }
        try await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
        return try await receiveUntilPrompt(connection)
    }

    private func receiveUntilPrompt(_ conn: NWConnection) async throws -> String {
        var collected = Data()
        for _ in 0..<8 {
            let chunk: Data = try await withCheckedThrowingContinuation { continuation in
                conn.receive(minimumIncompleteLength: 1, maximumLength: 4096) { data, _, _, error in
                    if let error { continuation.resume(throwing: error) }
                    else { continuation.resume(returning: data ?? Data()) }
                }
            }
            collected.append(chunk)
            if String(data: collected, encoding: .utf8)?.contains(">") == true { break }
        }
        return String(data: collected, encoding: .utf8) ?? ""
    }

    private func clean(_ raw: String) -> String {
        raw.replacingOccurrences(of: "\r", with: " ").replacingOccurrences(of: "\n", with: " ").replacingOccurrences(of: ">", with: " ").replacingOccurrences(of: "  ", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func hexBytes(_ raw: String) -> [Int] {
        let chars = clean(raw).uppercased().filter { $0.isHexDigit }
        var result = [Int]()
        var index = chars.startIndex
        while index < chars.endIndex {
            let next = chars.index(index, offsetBy: 2, limitedBy: chars.endIndex) ?? chars.endIndex
            if next > index, let byte = Int(String(chars[index..<next]), radix: 16) { result.append(byte) }
            index = next
        }
        return result
    }

    private func parsePID(_ raw: String, pid: String) -> [Int]? {
        let bytes = hexBytes(raw)
        guard let pidValue = Int(pid, radix: 16) else { return nil }
        for i in 0..<max(0, bytes.count - 1) where bytes[i] == 0x41 && bytes[i + 1] == pidValue {
            return Array(bytes.dropFirst(i + 2))
        }
        return nil
    }

    private func parseDTCs(_ raw: String) -> [String] {
        let bytes = hexBytes(raw)
        guard let start = bytes.firstIndex(of: 0x43) else { return [] }
        var result = [String]()
        var i = start + 1
        let prefixes = ["P", "C", "B", "U"]
        while i + 1 < bytes.count {
            let a = bytes[i], b = bytes[i + 1]
            if a == 0 && b == 0 { break }
            let prefix = prefixes[(a >> 6) & 0x03]
            let d1 = (a >> 4) & 0x03
            let d2 = a & 0x0F
            let d3 = (b >> 4) & 0x0F
            let d4 = b & 0x0F
            result.append(String(format: "%@%X%X%X%X", prefix, d1, d2, d3, d4))
            i += 2
        }
        return Array(Set(result)).sorted()
    }

    private func parseVoltage(_ raw: String) -> Double? {
        let cleaned = clean(raw).uppercased().replacingOccurrences(of: "V", with: "")
        return cleaned.split(separator: " ").compactMap { Double($0) }.first
    }
}
