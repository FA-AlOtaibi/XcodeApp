import SwiftUI

struct OBDView: View {
    @EnvironmentObject private var app: AppState
    @State private var host = "192.168.0.10"
    @State private var port = "35000"

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    intro
                    connectionCard
                    if let result = app.obd.lastResult { resultCard(result) }
                    usbCard
                }
                .padding(18)
            }
            .navigationTitle("فحص السيارة")
        }
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("OBD + عَيْن", systemImage: "car.rear.road.lane")
                .font(.title2.bold())
                .foregroundStyle(.cyan)
            Text("اقرأ أكواد الأعطال والبيانات الحية من ELM327، وبعدها يقدر عَيْن يربط الأكواد مع الصورة أو الفيديو بدل التخمين من شكل السيارة فقط.")
                .foregroundStyle(.secondary)
            Text("لا تمسح أكواد الأعطال قبل حفظها وفهم سببها؛ المسح قد يخفي معلومات مهمة عن العطل.")
                .font(.footnote)
                .foregroundStyle(.orange)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(Color.cyan.opacity(0.08), in: RoundedRectangle(cornerRadius: 22))
    }

    private var connectionCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("ELM327 عبر Wi‑Fi").font(.headline)
            HStack {
                TextField("IP", text: $host)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .textFieldStyle(.roundedBorder)
                TextField("Port", text: $port)
                    .keyboardType(.numberPad)
                    .frame(width: 92)
                    .textFieldStyle(.roundedBorder)
            }
            Button {
                Task { await app.obd.scanWiFi(host: host, port: UInt16(port) ?? 35000) }
            } label: {
                HStack {
                    if app.obd.isBusy { ProgressView().tint(.black) }
                    Label(app.obd.isBusy ? "جاري الفحص…" : "فحص مرة واحدة", systemImage: "wave.3.right.circle.fill")
                }
                .font(.headline)
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .background(.cyan, in: RoundedRectangle(cornerRadius: 17))
                .foregroundStyle(.black)
            }
            .buttonStyle(.plain)
            .disabled(app.obd.isBusy)
            Text(app.obd.status).font(.footnote).foregroundStyle(.secondary)
        }
        .padding(18)
        .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 22))
    }

    private func resultCard(_ result: OBDScanResult) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("نتيجة الفحص").font(.title3.bold())
            if result.dtcs.isEmpty {
                Label("لا توجد أكواد DTC مخزنة", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("أكواد الأعطال").font(.headline)
                    ForEach(result.dtcs, id: \.self) { code in
                        Text(code).font(.system(.body, design: .monospaced).bold())
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(Color.orange.opacity(0.12), in: Capsule())
                    }
                }
            }
            Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 10) {
                if let v = result.live.rpm { GridRow { Text("RPM"); Text("\(Int(v))") } }
                if let v = result.live.speedKmh { GridRow { Text("السرعة"); Text("\(Int(v)) km/h") } }
                if let v = result.live.coolantC { GridRow { Text("حرارة الماء"); Text("\(Int(v))°C") } }
                if let v = result.live.engineLoadPercent { GridRow { Text("حمل المحرك"); Text(String(format: "%.1f%%", v)) } }
                if let v = result.live.throttlePercent { GridRow { Text("الثروتل"); Text(String(format: "%.1f%%", v)) } }
                if let v = result.live.voltage { GridRow { Text("الفولت"); Text(String(format: "%.2f V", v)) } }
            }
            .font(.subheadline)

            if app.selectedImageData != nil {
                Button {
                    Task { await app.reanalyzeWithOBD() }
                } label: {
                    Label("ادمج OBD مع آخر صورة", systemImage: "sparkles.rectangle.stack")
                        .frame(maxWidth: .infinity).frame(height: 50)
                }
                .buttonStyle(.borderedProminent)
                .tint(.cyan)
            }
        }
        .padding(18)
        .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 22))
    }

    private var usbCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("USB OBD", systemImage: "cable.connector")
                    .font(.headline)
                Spacer()
                Button("اكتشاف") { app.obd.scanUSBAccessories() }
            }
            Text("عَيْن يكتشف الملحقات التي يسمح iOS للتطبيق برؤيتها عبر ExternalAccessory. محول OBD USB‑Serial عادي قد لا يكون قابلًا للفتح من تطبيق iPhone حتى لو كان موصولًا فعليًا.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            ForEach(app.obd.usbAccessories, id: \.self) { item in
                Label(item, systemImage: "externaldrive.connected.to.line.below")
                    .font(.footnote)
            }
        }
        .padding(18)
        .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 22))
    }
}
