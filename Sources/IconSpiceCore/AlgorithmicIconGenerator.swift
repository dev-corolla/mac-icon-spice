import CoreGraphics
import Foundation

/// A local, deterministic generator. Source analysis and raster composition use
/// Core Graphics, so generation is safe away from the main actor.
public struct AlgorithmicIconGenerator: IconGenerating {
    public init() {}

    public func generate(source: SourceIcon, for app: InstalledApp, hueOverride: Double? = nil) async throws -> GeneratedIcon {
        guard hueOverride?.isFinite != false else {
            throw IconError.invalidArgument("The hue must be a finite number.")
        }
        var artwork = try IconRaster(image: IconImageCodec.decode(source.pngData), size: 1024)
        artwork.removeEnclosingBackground()
        let analysis = artwork.analyzeColor()
        let hue = hueOverride.map(Self.normalizedHue) ?? analysis.hue ?? Self.stableHue(for: app.bundleID)
        if analysis.isMonochrome { artwork.tintMonochrome(hue: hue) }
        let image = try compose(artwork: artwork, hue: hue)
        let png = try IconImageCodec.pngData(from: image)
        return GeneratedIcon(pngData: png, icnsData: try IconImageCodec.icnsData(fromPNG: png),
                             hue: hue, sourceHash: source.hash)
    }

    /// FNV-1a avoids Swift's process-randomized Hasher and stays stable across runs.
    public static func stableHue(for bundleID: BundleID) -> Double {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in bundleID.rawValue.utf8 { hash = (hash ^ UInt64(byte)) &* 1_099_511_628_211 }
        return Double(hash % 3600) / 3600
    }

    private static func normalizedHue(_ hue: Double) -> Double {
        let value = hue.truncatingRemainder(dividingBy: 1)
        return value < 0 ? value + 1 : value
    }

    private func compose(artwork: IconRaster, hue: Double) throws -> CGImage {
        let context = try IconImageCodec.bitmapContext(size: 1024)
        let shape = squircle(in: CGRect(x: 62, y: 62, width: 900, height: 900))
        context.saveGState()
        context.setShadow(offset: CGSize(width: 0, height: -12), blur: 28,
                          color: CGColor(gray: 0, alpha: 0.28))
        context.addPath(shape)
        context.setFillColor(IconColor(h: hue, s: 0.82, v: 0.46).cgColor())
        context.fillPath()
        context.restoreGState()

        context.saveGState()
        context.addPath(shape)
        context.clip()
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        let colors = [IconColor(h: hue + 0.025, s: 0.70, v: 0.82).cgColor(),
                      IconColor(h: hue, s: 0.88, v: 0.48).cgColor(),
                      IconColor(h: hue - 0.025, s: 0.90, v: 0.27).cgColor()]
        guard let gradient = CGGradient(colorsSpace: colorSpace, colors: colors as CFArray, locations: [0, 0.54, 1]) else {
            throw IconError.invalidImage
        }
        context.drawLinearGradient(gradient, start: CGPoint(x: 420, y: 962),
                                   end: CGPoint(x: 590, y: 62),
                                   options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        let glowColors = [IconColor(h: hue + 0.05, s: 0.30, v: 1).cgColor(alpha: 0.21),
                          IconColor(h: hue, s: 0.30, v: 1).cgColor(alpha: 0)]
        if let glow = CGGradient(colorsSpace: colorSpace, colors: glowColors as CFArray, locations: [0, 1]) {
            context.drawRadialGradient(glow, startCenter: CGPoint(x: 390, y: 850), startRadius: 0,
                                       endCenter: CGPoint(x: 390, y: 850), endRadius: 640, options: [])
        }
        context.restoreGState()

        // A subtle edge keeps the dark shape legible against dark desktops.
        context.addPath(shape)
        context.setStrokeColor(CGColor(gray: 1, alpha: 0.12))
        context.setLineWidth(2)
        context.strokePath()

        guard let bounds = artwork.bounds(),
              let glyph = try artwork.cgImage().cropping(to: bounds.cgRect) else { throw IconError.invalidImage }
        let maximum: CGFloat = 618
        let scale = min(maximum / CGFloat(glyph.width), maximum / CGFloat(glyph.height))
        let rect = CGRect(x: (1024 - CGFloat(glyph.width) * scale) / 2,
                          y: (1024 - CGFloat(glyph.height) * scale) / 2 + 5,
                          width: CGFloat(glyph.width) * scale, height: CGFloat(glyph.height) * scale)
        context.interpolationQuality = .high
        context.setShadow(offset: CGSize(width: 0, height: -7), blur: 24,
                          color: IconColor(h: hue, s: 0.60, v: 0.12).cgColor(alpha: 0.65))
        context.draw(glyph, in: rect)
        guard let image = context.makeImage() else { throw IconError.invalidImage }
        return image
    }

    private func squircle(in rect: CGRect) -> CGPath {
        let path = CGMutablePath()
        // A superellipse gives continuous corners without platform-specific UI APIs.
        for index in 0...240 {
            let angle = Double(index) / 240 * 2 * .pi
            let cosine = cos(angle), sine = sin(angle)
            let x = (cosine < 0 ? -1.0 : 1.0) * pow(abs(cosine), 0.5)
            let y = (sine < 0 ? -1.0 : 1.0) * pow(abs(sine), 0.5)
            let point = CGPoint(x: rect.midX + CGFloat(x) * rect.width / 2,
                                y: rect.midY + CGFloat(y) * rect.height / 2)
            if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        path.closeSubpath()
        return path
    }
}

private struct IconColor {
    let r: Double
    let g: Double
    let b: Double
    let h: Double
    let s: Double
    let v: Double

    init(r: Double, g: Double, b: Double) {
        self.r = r; self.g = g; self.b = b
        let maximum = max(r, g, b), minimum = min(r, g, b), delta = maximum - minimum
        v = maximum; s = maximum > 0 ? delta / maximum : 0
        var hue = 0.0
        if delta > 0 {
            if maximum == r { hue = (g - b) / delta }
            else if maximum == g { hue = 2 + (b - r) / delta }
            else { hue = 4 + (r - g) / delta }
            hue /= 6
            if hue < 0 { hue += 1 }
        }
        h = hue
    }

    init(h: Double, s: Double, v: Double) {
        let hue = h - floor(h)
        let sector = hue * 6, index = Int(sector), fraction = sector - Double(index)
        let p = v * (1 - s), q = v * (1 - s * fraction), t = v * (1 - s * (1 - fraction))
        let rgb: (Double, Double, Double)
        switch index {
        case 0: rgb = (v, t, p)
        case 1: rgb = (q, v, p)
        case 2: rgb = (p, v, t)
        case 3: rgb = (p, q, v)
        case 4: rgb = (t, p, v)
        default: rgb = (v, p, q)
        }
        self.init(r: rgb.0, g: rgb.1, b: rgb.2)
    }

    func cgColor(alpha: Double = 1) -> CGColor {
        CGColor(srgbRed: r, green: g, blue: b, alpha: alpha)
    }

    func hueDistance(to other: IconColor) -> Double {
        let distance = abs(h - other.h)
        return min(distance, 1 - distance)
    }

    func matchesBackground(_ other: IconColor) -> Bool {
        // Hue is unstable around black; dark icon backdrops often drift between
        // gray, brown, and purple while still reading as the same enclosure.
        if v < 0.16 { return other.v < 0.22 }
        if s < 0.16 { return other.s < 0.23 && abs(v - other.v) < 0.32 }
        return hueDistance(to: other) < 0.095 && other.s > max(0.22, s - 0.35) && abs(v - other.v) < 0.35
    }
}

private struct PixelBounds {
    var left: Int
    var top: Int
    var right: Int
    var bottom: Int
    var width: Int { right - left + 1 }
    var height: Int { bottom - top + 1 }
    var cgRect: CGRect { CGRect(x: left, y: top, width: width, height: height) }
}

private struct IconRaster {
    let size: Int
    var bytes: [UInt8]

    init(image: CGImage, size: Int) throws {
        self.size = size
        let normalized = try IconImageCodec.resized(image, size: size)
        let context = try IconImageCodec.bitmapContext(size: size)
        context.draw(normalized, in: CGRect(x: 0, y: 0, width: size, height: size))
        guard let data = context.data else { throw IconError.invalidImage }
        bytes = Array(UnsafeBufferPointer(start: data.assumingMemoryBound(to: UInt8.self), count: size * size * 4))
    }

    func color(at pixel: Int) -> IconColor {
        let offset = pixel * 4, alpha = max(1, Double(bytes[offset + 3]))
        return IconColor(r: min(1, Double(bytes[offset]) / alpha),
                         g: min(1, Double(bytes[offset + 1]) / alpha),
                         b: min(1, Double(bytes[offset + 2]) / alpha))
    }

    func bounds(alphaThreshold: UInt8 = 24) -> PixelBounds? {
        var result = PixelBounds(left: size, top: size, right: -1, bottom: -1)
        for pixel in 0..<(size * size) where bytes[pixel * 4 + 3] > alphaThreshold {
            let x = pixel % size, y = pixel / size
            result.left = min(result.left, x); result.right = max(result.right, x)
            result.top = min(result.top, y); result.bottom = max(result.bottom, y)
        }
        return result.right < 0 ? nil : result
    }

    /// Remove only a uniform or gently graded, edge-connected enclosure. Disjoint
    /// colors and internal areas of the logo remain untouched. If segmentation
    /// would erase the artwork, keep the source instead.
    mutating func removeEnclosingBackground() {
        guard let bounds = bounds(alphaThreshold: 96),
              bounds.width > size / 2, bounds.height > size / 2 else { return }
        var probes: [IconColor] = []
        for position in [0.32, 0.50, 0.68] {
            let x = bounds.left + Int(Double(bounds.width) * position)
            let y = bounds.top + Int(Double(bounds.height) * position)
            let insetX = max(2, bounds.width / 40), insetY = max(2, bounds.height / 40)
            for pixel in [(bounds.top + insetY) * size + x, (bounds.bottom - insetY) * size + x,
                          y * size + bounds.left + insetX, y * size + bounds.right - insetX] {
                if bytes[pixel * 4 + 3] > 220 { probes.append(color(at: pixel)) }
            }
        }
        guard probes.count >= 8 else { return }
        let candidate = probes.max { left, right in
            probes.filter { left.matchesBackground($0) }.count < probes.filter { right.matchesBackground($0) }.count
        }!
        guard probes.filter({ candidate.matchesBackground($0) }).count >= Int(ceil(Double(probes.count) * 0.75)) else { return }

        let count = size * size
        var visited = [Bool](repeating: false, count: count)
        var queue: [Int] = []
        queue.reserveCapacity(count)
        func canRemove(_ pixel: Int) -> Bool {
            if bytes[pixel * 4 + 3] < 32 { return true }
            let color = color(at: pixel)
            let x = pixel % size, y = pixel / size
            let frameWidth = max(2, bounds.width / 14), frameHeight = max(2, bounds.height / 14)
            let isFrame = x < bounds.left + frameWidth || x > bounds.right - frameWidth ||
                y < bounds.top + frameHeight || y > bounds.bottom - frameHeight
            // A neutral border or baked shadow belongs to the old enclosure.
            // Limit this extra tolerance to its outside rim, away from the logo.
            return candidate.matchesBackground(color) || (isFrame && color.s < 0.20)
        }
        // Flood from all four outer edges through transparency into the enclosure.
        for coordinate in 0..<size {
            for pixel in [coordinate, (size - 1) * size + coordinate, coordinate * size, coordinate * size + size - 1] {
                if !visited[pixel] && canRemove(pixel) { visited[pixel] = true; queue.append(pixel) }
            }
        }
        var head = 0
        while head < queue.count {
            let pixel = queue[head]; head += 1
            let x = pixel % size, y = pixel / size
            let neighbors = [x > 0 ? pixel - 1 : -1, x < size - 1 ? pixel + 1 : -1,
                             y > 0 ? pixel - size : -1, y < size - 1 ? pixel + size : -1]
            for next in neighbors where next >= 0 && !visited[next] {
                if canRemove(next) { visited[next] = true; queue.append(next) }
            }
        }
        var originalMass = 0.0, remainingMass = 0.0
        for pixel in 0..<count {
            let alpha = Double(bytes[pixel * 4 + 3])
            originalMass += alpha
            if !visited[pixel] { remainingMass += alpha }
        }
        guard remainingMass > originalMass * 0.035, remainingMass < originalMass * 0.82 else { return }
        for pixel in queue {
            let offset = pixel * 4
            bytes[offset] = 0; bytes[offset + 1] = 0; bytes[offset + 2] = 0; bytes[offset + 3] = 0
        }
        removeResidualFrame()
    }

    /// Baked enclosure highlights can survive the color flood as disconnected,
    /// very thin arcs. Discard only sparse components that occupy a large area
    /// and account for a minority of the remaining artwork.
    private mutating func removeResidualFrame() {
        let count = size * size
        let opaqueCount = (0..<count).reduce(0) { $0 + (bytes[$1 * 4 + 3] > 32 ? 1 : 0) }
        var visited = [Bool](repeating: false, count: count)
        var coreBounds: PixelBounds?
        for start in 0..<count where !visited[start] && bytes[start * 4 + 3] > 32 {
            var component = [start]
            visited[start] = true
            var head = 0
            var bounds = PixelBounds(left: start % size, top: start / size, right: start % size, bottom: start / size)
            while head < component.count {
                let pixel = component[head]; head += 1
                let x = pixel % size, y = pixel / size
                bounds.left = min(bounds.left, x); bounds.right = max(bounds.right, x)
                bounds.top = min(bounds.top, y); bounds.bottom = max(bounds.bottom, y)
                let neighbors = [x > 0 ? pixel - 1 : -1, x < size - 1 ? pixel + 1 : -1,
                                 y > 0 ? pixel - size : -1, y < size - 1 ? pixel + size : -1]
                for next in neighbors where next >= 0 && !visited[next] && bytes[next * 4 + 3] > 32 {
                    visited[next] = true; component.append(next)
                }
            }
            let area = bounds.width * bounds.height
            let density = Double(component.count) / Double(area)
            if density > 0.22 && component.count > opaqueCount / 25 {
                if var core = coreBounds {
                    core.left = min(core.left, bounds.left); core.right = max(core.right, bounds.right)
                    core.top = min(core.top, bounds.top); core.bottom = max(core.bottom, bounds.bottom)
                    coreBounds = core
                } else { coreBounds = bounds }
            }
            let isSparseRim = max(bounds.width, bounds.height) > size / 6 && density < 0.14 &&
                component.count < opaqueCount / 3
            let isSpeck = component.count < max(4, opaqueCount / 1000)
            guard isSparseRim || isSpeck else { continue }
            for pixel in component {
                let offset = pixel * 4
                bytes[offset] = 0; bytes[offset + 1] = 0; bytes[offset + 2] = 0; bytes[offset + 3] = 0
            }
        }
        // Faint fragments need not be connected after the flood. Keep bright or
        // colorful details, but remove isolated dark enclosure debris outside
        // the substantial logo components.
        if let core = coreBounds {
            let padding = max(12, max(core.width, core.height) / 20)
            for pixel in 0..<count where bytes[pixel * 4 + 3] > 0 {
                let x = pixel % size, y = pixel / size
                guard x < core.left - padding || x > core.right + padding ||
                        y < core.top - padding || y > core.bottom + padding else { continue }
                let color = color(at: pixel)
                if color.v < 0.45 || color.s < 0.20 {
                    let offset = pixel * 4
                    bytes[offset] = 0; bytes[offset + 1] = 0; bytes[offset + 2] = 0; bytes[offset + 3] = 0
                }
            }
        }
    }

    func analyzeColor() -> (hue: Double?, isMonochrome: Bool) {
        var bins = [Double](repeating: 0, count: 36)
        var totalWeight = 0.0, colorfulWeight = 0.0
        for y in stride(from: 0, to: size, by: 4) {
            for x in stride(from: 0, to: size, by: 4) {
                let pixel = y * size + x, alpha = Double(bytes[pixel * 4 + 3]) / 255
                guard alpha > 0.15 else { continue }
                totalWeight += alpha
                let color = color(at: pixel)
                guard color.s > 0.18, color.v > 0.15 else { continue }
                colorfulWeight += alpha
                bins[min(35, Int(color.h * 36))] += alpha * color.s * color.v
            }
        }
        guard totalWeight > 0, colorfulWeight / totalWeight > 0.10,
              let peak = bins.indices.max(by: { bins[$0] < bins[$1] }), bins[peak] > 0 else {
            return (nil, true)
        }
        // Circular averaging keeps red hues near zero rather than turning cyan.
        var sine = 0.0, cosine = 0.0
        for delta in -2...2 {
            let index = (peak + delta + 36) % 36
            let angle = (Double(index) + 0.5) / 36 * 2 * Double.pi
            sine += sin(angle) * bins[index]; cosine += cos(angle) * bins[index]
        }
        var hue = atan2(sine, cosine) / (2 * .pi)
        if hue < 0 { hue += 1 }
        return (hue, false)
    }

    mutating func tintMonochrome(hue: Double) {
        let tint = IconColor(h: hue + 0.035, s: 0.10, v: 1)
        var darkSamples = 0, lightSamples = 0, samples = 0
        for pixel in stride(from: 0, to: size * size, by: 16) where bytes[pixel * 4 + 3] > 160 {
            let color = color(at: pixel)
            let luminance = color.r * 0.2126 + color.g * 0.7152 + color.b * 0.0722
            samples += 1
            if luminance < 0.65 { darkSamples += 1 }
            if luminance > 0.80 { lightSamples += 1 }
        }
        // Keep faceted and shaded monochrome logos recognizable. A solid dark
        // glyph receives the full bright tint rather than remaining dark.
        let hasShading = samples > 0 && Double(darkSamples) / Double(samples) > 0.12 &&
            Double(lightSamples) / Double(samples) > 0.12
        for pixel in 0..<(size * size) {
            let offset = pixel * 4, alpha = Double(bytes[offset + 3])
            let brightness: Double
            if hasShading {
                let color = color(at: pixel)
                brightness = 0.42 + 0.58 * (color.r * 0.2126 + color.g * 0.7152 + color.b * 0.0722)
            } else { brightness = 1 }
            bytes[offset] = UInt8((tint.r * alpha * brightness).rounded())
            bytes[offset + 1] = UInt8((tint.g * alpha * brightness).rounded())
            bytes[offset + 2] = UInt8((tint.b * alpha * brightness).rounded())
        }
    }

    func cgImage() throws -> CGImage {
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let provider = CGDataProvider(data: Data(bytes) as CFData),
              let image = CGImage(width: size, height: size, bitsPerComponent: 8, bitsPerPixel: 32,
                                  bytesPerRow: size * 4, space: colorSpace,
                                  bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue),
                                  provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent) else {
            throw IconError.invalidImage
        }
        return image
    }
}
