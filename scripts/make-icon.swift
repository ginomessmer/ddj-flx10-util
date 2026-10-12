// Renders Resources/AppIcon.icns: a jog wheel with a lit ring on a graphite squircle.
// Usage: swift scripts/make-icon.swift
import AppKit

func render(_ side: CGFloat) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(side), pixelsHigh: Int(side),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = side / 1024
    let ctx = NSGraphicsContext.current!.cgContext

    // macOS icon grid: 824pt body inset in a 1024 canvas.
    let body = CGRect(x: 100 * s, y: 100 * s, width: 824 * s, height: 824 * s)
    let squircle = NSBezierPath(roundedRect: body, xRadius: 185 * s, yRadius: 185 * s)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -10 * s), blur: 24 * s, color: NSColor.black.withAlphaComponent(0.35).cgColor)
    NSColor.black.setFill()
    squircle.fill()
    ctx.restoreGState()
    NSGradient(colors: [NSColor(white: 0.24, alpha: 1), NSColor(white: 0.07, alpha: 1)])!.draw(in: squircle, angle: -90)

    let center = CGPoint(x: 512 * s, y: 512 * s)
    func circle(_ r: CGFloat) -> NSBezierPath {
        NSBezierPath(ovalIn: CGRect(x: center.x - r * s, y: center.y - r * s, width: 2 * r * s, height: 2 * r * s))
    }

    // Platter.
    NSGradient(colors: [NSColor(white: 0.32, alpha: 1), NSColor(white: 0.12, alpha: 1)])!.draw(in: circle(330), angle: -90)
    // Grip ridges.
    NSColor(white: 1, alpha: 0.06).setStroke()
    for i in 0..<72 {
        let a = CGFloat(i) / 72 * 2 * .pi
        let p = NSBezierPath()
        p.move(to: CGPoint(x: center.x + cos(a) * 300 * s, y: center.y + sin(a) * 300 * s))
        p.line(to: CGPoint(x: center.x + cos(a) * 326 * s, y: center.y + sin(a) * 326 * s))
        p.lineWidth = 6 * s
        p.stroke()
    }
    // Lit jog ring.
    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: 40 * s, color: NSColor.systemOrange.cgColor)
    let ring = circle(262)
    ring.lineWidth = 26 * s
    NSColor(calibratedRed: 1, green: 0.55, blue: 0.12, alpha: 1).setStroke()
    ring.stroke()
    ctx.restoreGState()
    // Centre display.
    NSGradient(colors: [NSColor(calibratedRed: 0.10, green: 0.16, blue: 0.30, alpha: 1),
                        NSColor(calibratedRed: 0.02, green: 0.03, blue: 0.08, alpha: 1)])!.draw(in: circle(190), angle: -90)
    NSColor(white: 1, alpha: 0.12).setStroke()
    let bezel = circle(190); bezel.lineWidth = 6 * s; bezel.stroke()
    // Playhead marker.
    let marker = NSBezierPath(roundedRect: CGRect(x: center.x - 10 * s, y: center.y + 110 * s, width: 20 * s, height: 56 * s), xRadius: 10 * s, yRadius: 10 * s)
    NSColor.white.setFill()
    marker.fill()

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let root = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().deletingLastPathComponent()
let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try! FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
        let png = render(CGFloat(base * scale)).representation(using: .png, properties: [:])!
        try! png.write(to: iconset.appendingPathComponent(name))
    }
}
let output = root.appendingPathComponent("Resources/AppIcon.icns")
let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", iconset.path, "-o", output.path]
try! task.run()
task.waitUntilExit()
print("Wrote \(output.path)")
