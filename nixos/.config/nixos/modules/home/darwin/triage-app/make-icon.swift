// Renders Triage.icns: a green squircle with a white speech bubble.
// Run once when the icon should change; the .icns is checked in.
//   swift make-icon.swift && iconutil -c icns Triage.iconset && rm -r Triage.iconset
import AppKit

func render(_ px: Int) -> Data {
    let s = CGFloat(px)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    // macOS icon grid: the shape is 824/1024 of the canvas, centred.
    let inset = s * 100 / 1024
    let rect = NSRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
    let shape = NSBezierPath(roundedRect: rect, xRadius: rect.width * 0.225, yRadius: rect.width * 0.225)
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.25)
    shadow.shadowBlurRadius = s * 10 / 1024
    shadow.shadowOffset = NSSize(width: 0, height: -s * 6 / 1024)
    NSGraphicsContext.saveGraphicsState()
    shadow.set()
    NSColor(srgbRed: 0.18, green: 0.44, blue: 0.37, alpha: 1).setFill()
    shape.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGradient(starting: NSColor(srgbRed: 0.30, green: 0.60, blue: 0.51, alpha: 1),
               ending: NSColor(srgbRed: 0.16, green: 0.40, blue: 0.33, alpha: 1))!.draw(in: shape, angle: -90)
    let cfg = NSImage.SymbolConfiguration(pointSize: s * 0.40, weight: .semibold)
        .applying(NSImage.SymbolConfiguration(paletteColors: [.white]))
    if let sym = NSImage(systemSymbolName: "bubble.left.fill", accessibilityDescription: nil)?
        .withSymbolConfiguration(cfg) {
        let sz = sym.size
        sym.draw(in: NSRect(x: (s - sz.width) / 2, y: (s - sz.height) / 2 - s * 0.01, width: sz.width, height: sz.height))
    }
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let dir = URL(fileURLWithPath: "Triage.iconset")
try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    try! render(base).write(to: dir.appendingPathComponent("icon_\(base)x\(base).png"))
    try! render(base * 2).write(to: dir.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
