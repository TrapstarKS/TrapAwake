import AppKit

let destination = CommandLine.arguments[1]
try FileManager.default.createDirectory(atPath: destination, withIntermediateDirectories: true)
let sizes = [(16, "icon_16x16"), (32, "icon_16x16@2x"), (32, "icon_32x32"), (64, "icon_32x32@2x"), (128, "icon_128x128"), (256, "icon_128x128@2x"), (256, "icon_256x256"), (512, "icon_256x256@2x"), (512, "icon_512x512"), (1024, "icon_512x512@2x")]
for (size, name) in sizes {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    let scale = CGFloat(size) / 1024
    let transform = NSAffineTransform()
    transform.scale(by: scale)
    transform.concat()
    let tile = NSBezierPath(roundedRect: NSRect(x: 64, y: 64, width: 896, height: 896), xRadius: 200, yRadius: 200)
    NSGradient(starting: NSColor(srgbRed: 0.13, green: 0.22, blue: 0.31, alpha: 1), ending: NSColor(srgbRed: 0.03, green: 0.09, blue: 0.16, alpha: 1))!.draw(in: tile, angle: 270)
    let gold = NSColor(srgbRed: 1, green: 0.76, blue: 0.38, alpha: 1)
    gold.setFill()
    NSBezierPath(ovalIn: NSRect(x: 352, y: 342, width: 320, height: 320)).fill()
    gold.setStroke()
    for angle in stride(from: 0.0, to: 360.0, by: 45.0) {
        let radians = angle * .pi / 180
        let path = NSBezierPath()
        path.lineWidth = 44
        path.lineCapStyle = .round
        path.move(to: NSPoint(x: 512 + cos(radians) * 236, y: 502 + sin(radians) * 236))
        path.line(to: NSPoint(x: 512 + cos(radians) * 298, y: 502 + sin(radians) * 298))
        path.stroke()
    }
    NSGraphicsContext.restoreGraphicsState()
    try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: destination).appendingPathComponent(name + ".png"))
}
