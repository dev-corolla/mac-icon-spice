import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import IconSpiceCore

private func testPNG(width: Int = 1024, height: Int = 1024, draw: (CGContext) -> Void) throws -> Data {
    let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                            bytesPerRow: width * 4, space: colorSpace,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)!
    draw(context)
    return try IconImageCodec.pngData(from: context.makeImage()!)
}

private func rgbaPixel(_ data: Data, x: Int, y: Int) throws -> [UInt8] {
    let image = try IconImageCodec.decode(data)
    let context = try IconImageCodec.bitmapContext(size: image.width)
    context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    let offset = (y * image.width + x) * 4
    return Array(UnsafeBufferPointer(start: context.data!.assumingMemoryBound(to: UInt8.self) + offset, count: 4))
}

private let testApp = InstalledApp(bundleID: BundleID("org.example.Monochrome"), name: "Example", url: URL(fileURLWithPath: "/Applications/Example.app"))

@Test func stableHueUsesKnownHashAndStaysInRange() {
    #expect(AlgorithmicIconGenerator.stableHue(for: BundleID("")) == Double(UInt64(14_695_981_039_346_656_037) % 3600) / 3600)
    let first = AlgorithmicIconGenerator.stableHue(for: BundleID("org.example.Editor"))
    #expect(first == AlgorithmicIconGenerator.stableHue(for: BundleID("org.example.Editor")))
    #expect(first >= 0 && first < 1)
    #expect(first != AlgorithmicIconGenerator.stableHue(for: BundleID("org.example.Terminal")))
}

@Test func monochromeGenerationIsDeterministicAndHasTransparentCorners() async throws {
    let png = try testPNG { context in
        context.setFillColor(CGColor(gray: 0, alpha: 1))
        context.fillEllipse(in: CGRect(x: 320, y: 250, width: 380, height: 500))
    }
    let source = SourceIcon(pngData: png, hash: "original-hash")
    let generator = AlgorithmicIconGenerator()
    let first = try await generator.generate(source: source, for: testApp)
    let second = try await generator.generate(source: source, for: testApp)
    #expect(first.pngData == second.pngData)
    #expect(first.icnsData == second.icnsData)
    #expect(first.hue == AlgorithmicIconGenerator.stableHue(for: testApp.bundleID))
    #expect(first.sourceHash == "original-hash")
    #expect(first.kind == .algorithmic)
    let image = try IconImageCodec.decode(first.pngData)
    #expect(image.width == 1024 && image.height == 1024)
    #expect(try rgbaPixel(first.pngData, x: 0, y: 0)[3] == 0)
    let glyph = try rgbaPixel(first.pngData, x: 512, y: 512)
    #expect(glyph[0] > 220 && glyph[1] > 220 && glyph[2] > 220)
}

@Test func stripsOpaqueEnclosureWithoutCreatingAWhiteSquareOnTheNewIcon() async throws {
    let png = try testPNG { context in
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 1024, height: 1024))
        context.setFillColor(CGColor(gray: 0, alpha: 1))
        context.fillEllipse(in: CGRect(x: 320, y: 250, width: 380, height: 500))
    }
    let result = try await AlgorithmicIconGenerator().generate(source: SourceIcon(pngData: png, hash: "white-enclosure"), for: testApp, hueOverride: 0.6)
    let outsideGlyph = try rgbaPixel(result.pngData, x: 230, y: 512)
    #expect(outsideGlyph[0] < 180 && outsideGlyph[1] < 180 && outsideGlyph[2] < 210)
    let insideGlyph = try rgbaPixel(result.pngData, x: 512, y: 512)
    #expect(insideGlyph[0] > 220 && insideGlyph[1] > 220 && insideGlyph[2] > 220)
}

@Test func preservesColoredLogoAndChoosesItsDominantHue() async throws {
    let png = try testPNG { context in
        context.setFillColor(CGColor(srgbRed: 1, green: 0.03, blue: 0.03, alpha: 1))
        context.fillEllipse(in: CGRect(x: 280, y: 280, width: 460, height: 460))
    }
    let result = try await AlgorithmicIconGenerator().generate(source: SourceIcon(pngData: png, hash: "red-logo"), for: testApp)
    #expect(result.hue < 0.06 || result.hue > 0.94)
    let glyph = try rgbaPixel(result.pngData, x: 512, y: 512)
    #expect(glyph[0] > 240 && glyph[1] < 25 && glyph[2] < 25)
}

@Test func removesOldEnclosureFragmentsBeforeCenteringTheGlyph() async throws {
    func source(includeRim: Bool) throws -> SourceIcon {
        let png = try testPNG { context in
            context.setFillColor(CGColor(gray: 1, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: 1024, height: 1024))
            context.setFillColor(CGColor(gray: 0, alpha: 1))
            context.fillEllipse(in: CGRect(x: 320, y: 250, width: 380, height: 500))
            if includeRim {
                context.setStrokeColor(CGColor(gray: 0.4, alpha: 1))
                context.setLineWidth(4)
                context.move(to: CGPoint(x: 180, y: 220))
                context.addLine(to: CGPoint(x: 180, y: 700))
                context.strokePath()
            }
        }
        return SourceIcon(pngData: png, hash: "rim-test")
    }
    let generator = AlgorithmicIconGenerator()
    let clean = try await generator.generate(source: source(includeRim: false), for: testApp, hueOverride: 0.6)
    let withRim = try await generator.generate(source: source(includeRim: true), for: testApp, hueOverride: 0.6)
    #expect(clean.pngData == withRim.pngData)
}

@Test func hueOverrideWrapsAndRejectsNaN() async throws {
    let png = try testPNG { context in
        context.setFillColor(CGColor(gray: 0, alpha: 1))
        context.fill(CGRect(x: 350, y: 250, width: 320, height: 500))
    }
    let source = SourceIcon(pngData: png, hash: "override")
    let result = try await AlgorithmicIconGenerator().generate(source: source, for: testApp, hueOverride: -0.25)
    #expect(result.hue == 0.75)
    await #expect(throws: IconError.invalidArgument("The hue must be a finite number.")) {
        try await AlgorithmicIconGenerator().generate(source: source, for: testApp, hueOverride: .nan)
    }
}

@Test func monochromeTintPreservesFacetedArtworkShading() async throws {
    let png = try testPNG { context in
        context.setFillColor(CGColor(gray: 0.25, alpha: 1))
        context.fill(CGRect(x: 280, y: 280, width: 232, height: 464))
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 512, y: 280, width: 232, height: 464))
    }
    let result = try await AlgorithmicIconGenerator().generate(source: SourceIcon(pngData: png, hash: "faceted"), for: testApp)
    let darkerFacet = try rgbaPixel(result.pngData, x: 400, y: 512)
    let lighterFacet = try rgbaPixel(result.pngData, x: 620, y: 512)
    #expect(Int(lighterFacet[0]) - Int(darkerFacet[0]) > 60)
    #expect(darkerFacet[0] > 100)
}

@Test func icnsHasValidSizedPNGChunksAndRetinaRepresentations() throws {
    let png = try testPNG(width: 128, height: 128) { context in
        context.setFillColor(CGColor(srgbRed: 0.5, green: 0.2, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 128, height: 128))
    }
    let icns = try IconImageCodec.icnsData(fromPNG: png)
    func length(at offset: Int) -> Int {
        icns[offset..<(offset + 4)].reduce(0) { ($0 << 8) | Int($1) }
    }
    #expect(String(data: icns.prefix(4), encoding: .ascii) == "icns")
    #expect(length(at: 4) == icns.count)
    var offset = 8
    var sizes: [String: Int] = [:]
    while offset < icns.count {
        let type = String(data: icns[offset..<(offset + 4)], encoding: .ascii)!
        let chunkLength = length(at: offset + 4)
        #expect(chunkLength > 8 && offset + chunkLength <= icns.count)
        let image = try IconImageCodec.decode(icns.subdata(in: (offset + 8)..<(offset + chunkLength)))
        sizes[type] = image.width
        #expect(image.width == image.height)
        offset += chunkLength
    }
    #expect(sizes == ["icp4": 16, "icp5": 32, "icp6": 64, "ic07": 128, "ic08": 256,
                      "ic09": 512, "ic10": 1024, "ic11": 32, "ic12": 64, "ic13": 256, "ic14": 512])
    let source = try #require(CGImageSourceCreateWithData(icns as CFData, nil))
    #expect(CGImageSourceGetCount(source) > 0)
    #expect(try IconImageCodec.decode(icns).width == 1024)
}

@Test func normalizerPreservesAspectAndRejectsInvalidImages() throws {
    let png = try testPNG(width: 128, height: 64) { context in
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 128, height: 64))
    }
    let normalized = try IconImageCodec.normalizePNG(png)
    #expect(try rgbaPixel(normalized, x: 512, y: 0)[3] == 0)
    #expect(try rgbaPixel(normalized, x: 512, y: 512)[3] == 255)
    #expect(throws: IconError.invalidImage) { try IconImageCodec.normalizePNG(Data("invalid".utf8)) }
    #expect(throws: IconError.invalidArgument("The icon size must be between 16 and 4096 pixels.")) {
        try IconImageCodec.normalizePNG(png, size: 1)
    }
}

@Test @MainActor func sourceLoaderReadsOriginalBundleArtworkEvenWithCustomIcon() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let appURL = directory.appendingPathComponent("Example.app")
    let resources = appURL.appendingPathComponent("Contents/Resources")
    try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    var info: [String: String] = ["CFBundleIdentifier": "org.example.Loader", "CFBundleIconFile": "Original.png", "CFBundlePackageType": "APPL"]
    try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
        .write(to: appURL.appendingPathComponent("Contents/Info.plist"))
    let original = try testPNG { context in
        context.setFillColor(CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 1024, height: 1024))
    }
    try original.write(to: resources.appendingPathComponent("Original.png"))
    try Data("custom-generated-icon".utf8).write(to: appURL.appendingPathComponent("Icon\r"))
    let app = InstalledApp(bundleID: BundleID("org.example.Loader"), name: "Loader", url: appURL)
    let source = try SourceIconLoader().load(for: app, allowWorkspaceFallback: false)
    #expect(try rgbaPixel(source.pngData, x: 512, y: 512)[0] == 255)
    #expect(source.hash.count == 64)
    #expect(source.hash == (try SourceIconLoader().load(for: app)).hash)
    let replacement = try testPNG { context in
        context.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 1024, height: 1024))
    }
    try replacement.write(to: resources.appendingPathComponent("Replacement.png"))
    info["CFBundleIconFile"] = "Replacement.png"
    try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
        .write(to: appURL.appendingPathComponent("Contents/Info.plist"))
    let updatedSource = try SourceIconLoader().load(for: app, allowWorkspaceFallback: false)
    #expect(updatedSource.hash != source.hash)
    #expect(try rgbaPixel(updatedSource.pngData, x: 512, y: 512)[2] == 255)
    try FileManager.default.removeItem(at: resources.appendingPathComponent("Original.png"))
    try FileManager.default.removeItem(at: resources.appendingPathComponent("Replacement.png"))
    #expect(throws: IconError.self) { try SourceIconLoader().load(for: app, allowWorkspaceFallback: false) }
}
