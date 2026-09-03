import AppKit

// Clip for Mac icon: deep blue tile, a white clipboard with a clip, three text lines, and a small
// shield in the corner because refusing to capture secrets is the point.
func draw(_ s: CGFloat) -> NSImage {
    let img = NSImage(size: NSSize(width: s, height: s))
    img.lockFocus()
    let inset = s * 0.06
    let tile = NSBezierPath(roundedRect: NSRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset), xRadius: s * 0.22, yRadius: s * 0.22)
    NSGradient(colors: [NSColor(calibratedRed: 0.32, green: 0.56, blue: 0.98, alpha: 1),
                        NSColor(calibratedRed: 0.12, green: 0.30, blue: 0.78, alpha: 1)])!.draw(in: tile, angle: -70)
    // board
    let board = NSRect(x: s * 0.27, y: s * 0.18, width: s * 0.46, height: s * 0.58)
    NSColor.white.withAlphaComponent(0.96).setFill()
    NSBezierPath(roundedRect: board, xRadius: s * 0.06, yRadius: s * 0.06).fill()
    // clip
    let clip = NSRect(x: s * 0.40, y: s * 0.70, width: s * 0.20, height: s * 0.10)
    NSColor(calibratedRed: 0.10, green: 0.24, blue: 0.62, alpha: 1).setFill()
    NSBezierPath(roundedRect: clip, xRadius: s * 0.03, yRadius: s * 0.03).fill()
    // lines
    NSColor(calibratedRed: 0.20, green: 0.42, blue: 0.90, alpha: 1).setFill()
    for (i, w) in [0.30, 0.24, 0.18].enumerated() {
        let y = s * (0.58 - CGFloat(i) * 0.11)
        NSBezierPath(roundedRect: NSRect(x: s * 0.35, y: y, width: s * w, height: s * 0.045), xRadius: s * 0.02, yRadius: s * 0.02).fill()
    }
    // shield
    let sh = NSBezierPath()
    let cx = s * 0.72, cy = s * 0.26, r = s * 0.11
    sh.move(to: NSPoint(x: cx, y: cy + r))
    sh.line(to: NSPoint(x: cx + r * 0.9, y: cy + r * 0.6))
    sh.curve(to: NSPoint(x: cx, y: cy - r), controlPoint1: NSPoint(x: cx + r * 0.9, y: cy - r * 0.2), controlPoint2: NSPoint(x: cx + r * 0.5, y: cy - r * 0.8))
    sh.curve(to: NSPoint(x: cx - r * 0.9, y: cy + r * 0.6), controlPoint1: NSPoint(x: cx - r * 0.5, y: cy - r * 0.8), controlPoint2: NSPoint(x: cx - r * 0.9, y: cy - r * 0.2))
    sh.close()
    NSColor(calibratedRed: 0.98, green: 0.80, blue: 0.25, alpha: 1).setFill(); sh.fill()
    NSColor.white.setStroke(); sh.lineWidth = s * 0.015; sh.stroke()
    img.unlockFocus()
    return img
}

let out = "icon/ClipMac.iconset"
try? FileManager.default.removeItem(atPath: out)
try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)
for (name, px) in [("16x16",16),("16x16@2x",32),("32x32",32),("32x32@2x",64),("128x128",128),("128x128@2x",256),
                   ("256x256",256),("256x256@2x",512),("512x512",512),("512x512@2x",1024)] {
    let img = draw(CGFloat(px))
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    img.draw(in: NSRect(x: 0, y: 0, width: px, height: px))
    NSGraphicsContext.restoreGraphicsState()
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(out)/icon_\(name).png"))
}
print("iconset written")
