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
    let graphite = NSColor(calibratedRed: 0.075, green: 0.075, blue: 0.066, alpha: 1)
    let graphite2 = NSColor(calibratedRed: 0.14, green: 0.13, blue: 0.105, alpha: 1)
    let ivory = NSColor(calibratedRed: 0.95, green: 0.925, blue: 0.86, alpha: 1)
    let lime = NSColor(calibratedRed: 0.76, green: 0.88, blue: 0.30, alpha: 1)
    let clay = NSColor(calibratedRed: 0.82, green: 0.43, blue: 0.31, alpha: 1)

    let space = CGColorSpaceCreateDeviceRGB()
    let gradient = CGGradient(colorsSpace: space, colors: [graphite2.cgColor, graphite.cgColor, NSColor.black.cgColor] as CFArray, locations: [0, 0.62, 1])!
    ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: s), end: CGPoint(x: s, y: 0), options: [])

    // Warm offset glow for a less synthetic identity.
    let glowRect = CGRect(x: s * 0.52, y: s * 0.52, width: s * 0.55, height: s * 0.55)
    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: s * 0.08, color: clay.withAlphaComponent(0.18).cgColor)
    ctx.setFillColor(clay.withAlphaComponent(0.08).cgColor)
    ctx.fillEllipse(in: glowRect)
    ctx.restoreGState()

    let tileRect = rect.insetBy(dx: s * 0.18, dy: s * 0.18)
    let tile = CGPath(roundedRect: tileRect, cornerWidth: s * 0.22, cornerHeight: s * 0.22, transform: nil)
    ctx.saveGState()
    ctx.setFillColor(ivory.cgColor)
    ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.018), blur: s * 0.05, color: NSColor.black.withAlphaComponent(0.32).cgColor)
    ctx.addPath(tile)
    ctx.fillPath()
    ctx.restoreGState()

    let left = CGPoint(x: s * 0.30, y: s * 0.50)
    let right = CGPoint(x: s * 0.70, y: s * 0.50)
    let top1 = CGPoint(x: s * 0.39, y: s * 0.34)
    let top2 = CGPoint(x: s * 0.61, y: s * 0.34)
    let bottom1 = CGPoint(x: s * 0.61, y: s * 0.66)
    let bottom2 = CGPoint(x: s * 0.39, y: s * 0.66)

    let eye = CGMutablePath()
    eye.move(to: left)
    eye.addCurve(to: right, control1: top1, control2: top2)
    eye.addCurve(to: left, control1: bottom1, control2: bottom2)
    ctx.setStrokeColor(graphite.cgColor)
    ctx.setLineWidth(s * 0.048)
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    ctx.addPath(eye)
    ctx.strokePath()

    let pupilRect = CGRect(x: s * 0.425, y: s * 0.425, width: s * 0.15, height: s * 0.15)
    ctx.setFillColor(lime.cgColor)
    ctx.fillEllipse(in: pupilRect)
    ctx.setStrokeColor(graphite.withAlphaComponent(0.82).cgColor)
    ctx.setLineWidth(max(1, s * 0.012))
    ctx.strokeEllipse(in: pupilRect)

    image.unlockFocus()
    guard let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else { return nil }
    return png
}

let targets: [(String, Int)] = [
    ("icon-40.png", 40), ("icon-60.png", 60), ("icon-58.png", 58), ("icon-87.png", 87),
    ("icon-80.png", 80), ("icon-120-40.png", 120), ("icon-120.png", 120), ("icon-180.png", 180), ("icon-1024.png", 1024)
]

for (name, side) in targets {
    if let data = makeIcon(side: side) {
        let url = URL(fileURLWithPath: root).appendingPathComponent(name)
        try data.write(to: url)
        print("generated \(url.path)")
    }
}
