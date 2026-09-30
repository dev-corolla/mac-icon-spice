import AppKit

/// Shared vector artwork for the packaged app, sidebar, and menu-bar template.
@MainActor
enum PepperArtwork {
    static func image(pixels: Int, tile: Bool = true) -> NSImage {
        NSImage(data: pngData(pixels: pixels, tile: tile))!
    }

    static var menuIcon: NSImage {
        let icon = image(pixels: 36, tile: false)
        icon.size = NSSize(width: 18, height: 18)
        icon.isTemplate = true
        return icon
    }

    static func pngData(pixels: Int, tile: Bool = true) -> Data {
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        let graphics = NSGraphicsContext(bitmapImageRep: bitmap)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = graphics
        graphics.cgContext.scaleBy(x: Double(pixels) / 1024, y: Double(pixels) / 1024)
        graphics.cgContext.setShouldAntialias(true)

        if tile {
            let background = NSBezierPath()
            for step in 0...240 {
                let angle = Double(step) / 240 * 2 * .pi
                let c = cos(angle), s = sin(angle)
                let x = (c < 0 ? -1.0 : 1.0) * pow(abs(c), 0.5)
                let y = (s < 0 ? -1.0 : 1.0) * pow(abs(s), 0.5)
                let point = NSPoint(x: 512 + x * 448, y: 512 + y * 448)
                if step == 0 { background.move(to: point) } else { background.line(to: point) }
            }
            background.close()
            let shadow = NSShadow()
            shadow.shadowOffset = NSSize(width: 0, height: -8)
            shadow.shadowBlurRadius = 16
            shadow.shadowColor = .black.withAlphaComponent(0.12)
            shadow.set()
            NSColor(srgbRed: 0.98, green: 0.95, blue: 0.87, alpha: 1).setFill()
            background.fill()
            NSShadow().set()
            NSGradient(colors: [NSColor(srgbRed: 1, green: 0.97, blue: 0.89, alpha: 1),
                                NSColor(srgbRed: 0.96, green: 0.90, blue: 0.79, alpha: 1)])!
                .draw(in: background, angle: -80)
        } else {
            // Fill the small status-item footprint while retaining a clear silhouette.
            graphics.cgContext.translateBy(x: -135, y: -195)
            graphics.cgContext.scaleBy(x: 1.27, y: 1.27)
        }

        let body = NSBezierPath()
        body.move(to: NSPoint(x: 600, y: 727))
        body.curve(to: NSPoint(x: 702, y: 430), controlPoint1: NSPoint(x: 757, y: 752), controlPoint2: NSPoint(x: 803, y: 573))
        body.curve(to: NSPoint(x: 215, y: 268), controlPoint1: NSPoint(x: 593, y: 265), controlPoint2: NSPoint(x: 390, y: 232))
        body.curve(to: NSPoint(x: 500, y: 520), controlPoint1: NSPoint(x: 396, y: 305), controlPoint2: NSPoint(x: 470, y: 404))
        body.curve(to: NSPoint(x: 600, y: 727), controlPoint1: NSPoint(x: 524, y: 644), controlPoint2: NSPoint(x: 525, y: 715))
        body.close()
        NSColor(srgbRed: 0.87, green: 0.18, blue: 0.16, alpha: 1).setFill()
        body.fill()

        let stem = NSBezierPath()
        stem.move(to: NSPoint(x: 613, y: 723))
        stem.curve(to: NSPoint(x: 782, y: 831), controlPoint1: NSPoint(x: 638, y: 811), controlPoint2: NSPoint(x: 706, y: 859))
        stem.lineWidth = 43
        stem.lineCapStyle = .round
        NSColor(srgbRed: 0.19, green: 0.40, blue: 0.25, alpha: 1).setStroke()
        stem.stroke()

        let cap = NSBezierPath()
        cap.move(to: NSPoint(x: 554, y: 705))
        cap.curve(to: NSPoint(x: 683, y: 718), controlPoint1: NSPoint(x: 600, y: 682), controlPoint2: NSPoint(x: 648, y: 684))
        cap.curve(to: NSPoint(x: 554, y: 705), controlPoint1: NSPoint(x: 640, y: 760), controlPoint2: NSPoint(x: 588, y: 752))
        cap.close()
        NSColor(srgbRed: 0.23, green: 0.47, blue: 0.28, alpha: 1).setFill()
        cap.fill()

        if tile {
            let highlight = NSBezierPath()
            highlight.move(to: NSPoint(x: 633, y: 649))
            highlight.curve(to: NSPoint(x: 636, y: 529), controlPoint1: NSPoint(x: 665, y: 621), controlPoint2: NSPoint(x: 660, y: 573))
            highlight.lineWidth = 22
            highlight.lineCapStyle = .round
            NSColor(srgbRed: 1, green: 0.68, blue: 0.46, alpha: 0.65).setStroke()
            highlight.stroke()
        }
        graphics.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()
        return bitmap.representation(using: .png, properties: [:])!
    }
}
