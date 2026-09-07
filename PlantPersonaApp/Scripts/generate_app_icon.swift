import AppKit

let root = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "PlantPersona/Assets.xcassets/AppIcon.appiconset"
let fm = FileManager.default
try? fm.createDirectory(atPath: root, withIntermediateDirectories: true)

func makeIcon(side: Int) -> Data? {
    let s = CGFloat(side)
    let image = NSImage(size: NSSize(width: s, height: s))
    image.lockFocus()

    guard let ctx = NSGraphicsContext.current?.cgContext else { image.unlockFocus(); return nil }
    ctx.setAllowsAntialiasing(true)
    ctx.setShouldAntialias(true)

    let rect = CGRect(x: 0, y: 0, width: s, height: s)
    let bgColors = [
        NSColor(calibratedRed: 0.015, green: 0.025, blue: 0.05, alpha: 1).cgColor,
        NSColor(calibratedRed: 0.02, green: 0.18, blue: 0.24, alpha: 1).cgColor,
        NSColor(calibratedRed: 0.18, green: 0.42, blue: 0.56, alpha: 1).cgColor
    ] as CFArray
    let space = CGColorSpaceCreateDeviceRGB()
    let gradient = CGGradient(colorsSpace: space, colors: bgColors, locations: [0, 0.58, 1])!
    ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: 0), end: CGPoint(x: s, y: s), options: [])

    // Soft glass halo
    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: s * 0.08, color: NSColor.cyan.withAlphaComponent(0.45).cgColor)
    ctx.setFillColor(NSColor.white.withAlphaComponent(0.10).cgColor)
    let inset = s * 0.17
    let panel = CGPath(roundedRect: rect.insetBy(dx: inset, dy: inset), cornerWidth: s * 0.22, cornerHeight: s * 0.22, transform: nil)
    ctx.addPath(panel)
    ctx.fillPath()
    ctx.restoreGState()

    // Eye mark
    let left = CGPoint(x: s * 0.27, y: s * 0.50)
    let right = CGPoint(x: s * 0.73, y: s * 0.50)
    let top1 = CGPoint(x: s * 0.38, y: s * 0.31)
    let top2 = CGPoint(x: s * 0.62, y: s * 0.31)
    let bottom1 = CGPoint(x: s * 0.62, y: s * 0.69)
    let bottom2 = CGPoint(x: s * 0.38, y: s * 0.69)

    let path = CGMutablePath()
    path.move(to: left)
    path.addCurve(to: right, control1: top1, control2: top2)
    path.addCurve(to: left, control1: bottom1, control2: bottom2)

    ctx.saveGState()
    ctx.setLineWidth(s * 0.055)
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.95).cgColor)
    ctx.setShadow(offset: .zero, blur: s * 0.025, color: NSColor.cyan.withAlphaComponent(0.55).cgColor)
    ctx.addPath(path)
    ctx.strokePath()
    ctx.restoreGState()

    let pupilRect = CGRect(x: s * 0.425, y: s * 0.425, width: s * 0.15, height: s * 0.15)
    ctx.saveGState()
    ctx.setFillColor(NSColor(calibratedRed: 0.26, green: 0.96, blue: 1.0, alpha: 1).cgColor)
    ctx.setShadow(offset: .zero, blur: s * 0.035, color: NSColor.cyan.withAlphaComponent(0.8).cgColor)
    ctx.fillEllipse(in: pupilRect)
    ctx.restoreGState()

    // Glass highlight
    ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.20).cgColor)
    ctx.setLineWidth(max(1, s * 0.008))
    let highlightRect = rect.insetBy(dx: s * 0.18, dy: s * 0.18)
    ctx.addPath(CGPath(roundedRect: highlightRect, cornerWidth: s * 0.21, cornerHeight: s * 0.21, transform: nil))
    ctx.strokePath()

    image.unlockFocus()
    guard let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else { return nil }
    return png
}

let targets: [(String, Int)] = [
    ("icon-40.png", 40),
    ("icon-60.png", 60),
    ("icon-58.png", 58),
    ("icon-87.png", 87),
    ("icon-80.png", 80),
    ("icon-120-40.png", 120),
    ("icon-120.png", 120),
    ("icon-180.png", 180),
    ("icon-1024.png", 1024)
]

for (name, side) in targets {
    if let data = makeIcon(side: side) {
        let url = URL(fileURLWithPath: root).appendingPathComponent(name)
        try data.write(to: url)
        print("generated \(url.path)")
    }
}
