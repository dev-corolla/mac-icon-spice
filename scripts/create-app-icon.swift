import AppKit

let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
let size = 1024
let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
let graphics = NSGraphicsContext(bitmapImageRep: bitmap)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = graphics
let path = NSBezierPath()
for step in 0...240 {
    let angle = Double(step) / 240 * 2 * .pi
    let cosine = cos(angle), sine = sin(angle)
    let x = (cosine < 0 ? -1.0 : 1.0) * pow(abs(cosine), 0.5)
    let y = (sine < 0 ? -1.0 : 1.0) * pow(abs(sine), 0.5)
    let point = NSPoint(x: 512 + x * 448, y: 512 + y * 448)
    if step == 0 { path.move(to: point) } else { path.line(to: point) }
}
path.close()
let shadow = NSShadow()
shadow.shadowOffset = NSSize(width: 0, height: -12)
shadow.shadowBlurRadius = 28
shadow.shadowColor = .black.withAlphaComponent(0.25)
shadow.set()
NSColor.systemPurple.setFill()
path.fill()
NSShadow().set()
let gradient = NSGradient(colors: [NSColor(srgbRed: 1, green: 0.60, blue: 0.34, alpha: 1),
                                  NSColor(srgbRed: 0.90, green: 0.25, blue: 0.53, alpha: 1),
                                  NSColor(srgbRed: 0.39, green: 0.27, blue: 0.78, alpha: 1)])!
gradient.draw(in: path, angle: -70)
let symbol = NSImage(systemSymbolName: "paintpalette.fill", accessibilityDescription: nil)!
    .withSymbolConfiguration(NSImage.SymbolConfiguration(paletteColors: [.white]))!
symbol.draw(in: NSRect(x: 241, y: 264, width: 542, height: 496), from: .zero,
            operation: .sourceOver, fraction: 1, respectFlipped: false, hints: nil)
graphics.flushGraphics()
NSGraphicsContext.restoreGraphicsState()
let master = bitmap.cgImage!
for (points, scale) in [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2)] {
    let pixels = points * scale
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let context = NSGraphicsContext(bitmapImageRep: rep)!
    context.cgContext.interpolationQuality = .high
    context.cgContext.draw(master, in: CGRect(x: 0, y: 0, width: pixels, height: pixels))
    let name = "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"
    try rep.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent(name))
}
