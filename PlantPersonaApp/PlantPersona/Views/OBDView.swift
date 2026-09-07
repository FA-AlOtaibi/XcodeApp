import SwiftUI

struct OBDView: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var host = "192.168.0.10"
    @State private var port = "35000"
    @State private var isLive = false
    @State private var liveTask: Task<Void, Never>?
    @State private var samples = 0

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                intro
                connectionCard
                if let result = app.obd.lastResult { resultCard(result) }
                usbCard
            }.padding(18)
        }
        .navigationTitle("فحص السيارة")
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("تم") { stopLive(); dismiss() } } }
        .onDisappear { stopLive() }
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("OBD + عَيْن", systemImage: "car.rear.road.lane").font(.title2.bold()).foregroundStyle(.cyan)
            Text("فحص مرة واحدة للأكواد، أو مراقبة حية للـRPM والحرارة والحمل والثروتل والفولت. بعدها ادمج البيانات مع الصورة أو الفيديو.").foregroundStyle(.secondary)
            Text("لا تمسح أكواد الأعطال قبل حفظها وفهم سببها.").font(.footnote).foregroundStyle(.orange)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(18).background(Color.cyan.opacity(0.08), in: RoundedRectangle(cornerRadius: 22))
    }

    private var connectionCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("ELM327 عبر Wi‑Fi").font(.headline)
            HStack {
                TextField("IP", text: $host).textInputAutocapitalization(.never).autocorrectionDisabled().textFieldStyle(.roundedBorder)
                TextField("Port", text: $port).keyboardType(.numberPad).frame(width: 92).textFieldStyle(.roundedBorder)
            }
            HStack(spacing: 10) {
                Button { Task { await app.obd.scanWiFi(host: host, port: UInt16(port) ?? 35000) } } label: {
                    Label(app.obd.isBusy ? "جاري الفحص…" : "فحص مرة", systemImage: "wave.3.right.circle.fill").font(.subheadline.bold()).frame(maxWidth: .infinity).frame(height: 52).background(.cyan, in: RoundedRectangle(cornerRadius: 16)).foregroundStyle(.black)
                }.buttonStyle(.plain).disabled(app.obd.isBusy || isLive)

                Button { isLive ? stopLive() : startLive() } label: {
                    Label(isLive ? "إيقاف" : "مراقبة حية", systemImage: isLive ? "stop.fill" : "chart.xyaxis.line").font(.subheadline.bold()).frame(maxWidth: .infinity).frame(height: 52).background(isLive ? Color.red.opacity(0.18) : Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 16)).foregroundStyle(isLive ? .red : .white)
                }.buttonStyle(.plain)
            }
            if isLive { Label("LIVE • \(samples) عينات", systemImage: "dot.radiowaves.left.and.right").font(.caption.bold().monospacedDigit()).foregroundStyle(.green) }
            Text(app.obd.status).font(.footnote).foregroundStyle(.secondary)
        }.padding(18).background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 22))
    }

    private func resultCard(_ result: OBDScanResult) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack { Text(isLive ? "بيانات حية" : "نتيجة الفحص").font(.title3.bold()); Spacer(); if isLive { Circle().fill(.green).frame(width: 9, height: 9) } }
            if result.dtcs.isEmpty { Label("لا توجد أكواد DTC مخزنة", systemImage: "checkmark.circle.fill").foregroundStyle(.green) }
            else { VStack(alignment: .leading, spacing: 8) { Text("أكواد الأعطال").font(.headline); ForEach(result.dtcs, id: \.self) { code in Text(code).font(.system(.body, design: .monospaced).bold()).padding(.horizontal, 10).padding(.vertical, 6).background(Color.orange.opacity(0.12), in: Capsule()) } } }
            Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 10) {
                if let v = result.live.rpm { GridRow { Text("RPM"); Text("\(Int(v))") } }
                if let v = result.live.speedKmh { GridRow { Text("السرعة"); Text("\(Int(v)) km/h") } }
                if let v = result.live.coolantC { GridRow { Text("حرارة الماء"); Text("\(Int(v))°C").foregroundStyle(v > 110 ? .red : .primary) } }
                if let v = result.live.engineLoadPercent { GridRow { Text("حمل المحرك"); Text(String(format: "%.1f%%", v)) } }
                if let v = result.live.throttlePercent { GridRow { Text("الثروتل"); Text(String(format: "%.1f%%", v)) } }
                if let v = result.live.voltage { GridRow { Text("الفولت"); Text(String(format: "%.2f V", v)).foregroundStyle(v < 11.8 ? .orange : .primary) } }
            }.font(.subheadline)
            if app.selectedImageData != nil {
                Button { Task { await app.reanalyzeWithOBD() } } label: { Label("ادمج OBD مع آخر صورة", systemImage: "sparkles.rectangle.stack").frame(maxWidth: .infinity).frame(height: 50) }.buttonStyle(.borderedProminent).tint(.cyan)
            }
        }.padding(18).background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 22))
    }

    private var usbCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack { Label("USB OBD", systemImage: "cable.connector").font(.headline); Spacer(); Button("اكتشاف") { app.obd.scanUSBAccessories() } }
            Text("يكتشف عَيْن الملحقات التي يسمح iOS للتطبيق برؤيتها. محول USB‑Serial عادي قد لا يكون قابلًا للفتح من تطبيق iPhone حتى لو كان موصولًا.").font(.footnote).foregroundStyle(.secondary)
            ForEach(app.obd.usbAccessories, id: \.self) { item in Label(item, systemImage: "externaldrive.connected.to.line.below").font(.footnote) }
        }.padding(18).background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 22))
    }

    private func startLive() {
        isLive = true; samples = 0
        liveTask?.cancel()
        liveTask = Task {
            while !Task.isCancelled && isLive {
                await app.obd.scanWiFi(host: host, port: UInt16(port) ?? 35000)
                if !Task.isCancelled { samples += 1 }
                try? await Task.sleep(nanoseconds: 3_000_000_000)
            }
        }
    }

    private func stopLive() { isLive = false; liveTask?.cancel(); liveTask = nil }
}
