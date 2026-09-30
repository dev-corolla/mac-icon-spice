import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Normalizes provider images and writes the multi-resolution format Finder expects.
/// No AppKit image objects cross the generator's concurrency boundary.
public struct IconImageCodec {
    private init() {}

    public static func normalizePNG(_ data: Data, size: Int = 1024) throws -> Data {
        guard (16...4096).contains(size) else {
            throw IconError.invalidArgument("The icon size must be between 16 and 4096 pixels.")
        }
        return try pngData(from: resized(decode(data), size: size))
    }

    public static func icnsData(fromPNG data: Data) throws -> Data {
        let source = try decode(data)
        let representations: [(String, Int)] = [
            ("icp4", 16), ("icp5", 32), ("icp6", 64),
            ("ic07", 128), ("ic08", 256), ("ic09", 512), ("ic10", 1024),
            ("ic11", 32), ("ic12", 64), ("ic13", 256), ("ic14", 512)
        ]
        var payload = Data()
        var encodedSizes: [Int: Data] = [:]
        for (type, size) in representations {
            let png: Data
            if let cached = encodedSizes[size] { png = cached }
            else {
                png = try pngData(from: resized(source, size: size))
                encodedSizes[size] = png
            }
            payload.append(contentsOf: type.utf8)
            payload.appendBigEndian(UInt32(png.count + 8))
            payload.append(png)
        }
        var result = Data("icns".utf8)
        result.appendBigEndian(UInt32(payload.count + 8))
        result.append(payload)
        return result
    }

    static func decode(_ data: Data) throws -> CGImage {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) > 0 else { throw IconError.invalidImage }
        // ICNS has multiple representations; prefer its largest artwork.
        var bestIndex = 0
        var bestArea = 0
        for index in 0..<CGImageSourceGetCount(source) {
            let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any]
            let width = (properties?[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue ?? 0
            let height = (properties?[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue ?? 0
            if width * height > bestArea { bestArea = width * height; bestIndex = index }
        }
        guard let image = CGImageSourceCreateImageAtIndex(source, bestIndex, nil) else {
            throw IconError.invalidImage
        }
        return image
    }

    static func pngData(from image: CGImage) throws -> Data {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else {
            throw IconError.invalidImage
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw IconError.invalidImage }
        return data as Data
    }

    static func resized(_ image: CGImage, size: Int) throws -> CGImage {
        let context = try bitmapContext(size: size)
        context.interpolationQuality = .high
        let scale = min(CGFloat(size) / CGFloat(image.width), CGFloat(size) / CGFloat(image.height))
        let width = CGFloat(image.width) * scale
        let height = CGFloat(image.height) * scale
        context.draw(image, in: CGRect(x: (CGFloat(size) - width) / 2,
                                     y: (CGFloat(size) - height) / 2,
                                     width: width, height: height))
        guard let result = context.makeImage() else { throw IconError.invalidImage }
        return result
    }

    static func bitmapContext(size: Int) throws -> CGContext {
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
                                      bytesPerRow: size * 4, space: colorSpace,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) else {
            throw IconError.invalidImage
        }
        return context
    }
}

private extension Data {
    mutating func appendBigEndian(_ value: UInt32) {
        var value = value.bigEndian
        Swift.withUnsafeBytes(of: &value) { append(contentsOf: $0) }
    }
}
