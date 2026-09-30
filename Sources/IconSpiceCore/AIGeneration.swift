import CryptoKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

public enum AIGenerationError: Error, Sendable, LocalizedError, Equatable {
    case badKey
    case rateLimit(retryAfterSeconds: Int?)
    case invalidResult
    case transport
    case provider(statusCode: Int)
    case cacheUnavailable

    public var errorDescription: String? {
        switch self {
        case .badKey: "OpenAI rejected the API key. Update it in Settings."
        case .rateLimit: "OpenAI's rate or usage limit was reached. Try again later or check your account billing."
        case .invalidResult: "OpenAI did not return a usable square icon."
        case .transport: "The connection to OpenAI failed. Check your connection and try again."
        case .provider(let status): "OpenAI could not generate the icon (HTTP \(status))."
        case .cacheUnavailable: "The AI icon cache could not be saved. Check available disk space and folder access."
        }
    }
}

/// Opt-in image editing. Calling this generator sends the source artwork to OpenAI.
/// Credentials are used only in the Authorization header and are never included in cache files.
public actor OpenAIIconGenerator: IconGenerating {
    public static let model = "gpt-image-2.5-sunburst-2026-09-08"
    public static let styleVersion = "icon-spice-v1"
    public static let maxInstructionLength = 2_000
    public static let defaultCustomizationInstructions = "Give this app icon more personality with clean vector shapes and tasteful color. Preserve the logo’s exact silhouette, proportions, spacing, original colors, and recognizable details; keep edges sharp and precise. Use a clean macOS squircle with mostly flat color and one or two simple geometric accents in the background. Apply subtle gradients only to selected background areas. Keep depth and shadows minimal, and remove strong glow, bloom, neon halos, glossy bevels, and clutter. Keep the logo prominent, the composition balanced, and everything clear at small Dock sizes. Leave the space outside the icon transparent."
    public static let stylePrompt = """
    Restyle the supplied application icon as a consistent macOS app icon. Preserve the original
    recognizable symbol, proportions, and brand identity. Use one centered, crisp, bright glyph
    on a vivid saturated squircle with smooth continuous rounded corners, a subtle top-to-bottom
    gradient, restrained inner glow, and a small soft shadow. The squircle occupies 88 percent
    of the square canvas. Keep the surrounding canvas fully transparent, with clean antialiased
    edges. Use a dark saturated background and a luminous glyph, clear at small Dock sizes.
    No text, labels, frames, scenery, or extra symbols. Return exactly one square icon.
    """

    private static let customizationPrompt = """
    Customize the supplied application icon according to the user's requested changes.
    Preserve its recognizable application identity and the logo's silhouette, proportions,
    spacing, and original colors unless the user specifically requests a change to them.
    Use clean, sharply defined artwork in a balanced macOS squircle with smooth continuous
    rounded corners, occupying 88 percent of the square canvas by default. Keep the space
    outside the icon fully transparent, with clean antialiased edges. Keep the logo clear
    at small Dock sizes. Return exactly one square icon.
    """

    private let apiKey: String
    private let instructions: String
    private let preserveInputStyle: Bool
    private let cacheURL: URL
    private let session: URLSession
    private var inFlight: [String: Task<GeneratedIcon, Error>] = [:]

    /// Set `preserveInputStyle` when refining a preview so unspecified details keep their current appearance.
    /// Instructions are trimmed, sent with the source image, and represented only by a hash in the cache identity.
    public init(apiKey: String, instructions: String = "", preserveInputStyle: Bool = false,
                cacheURL: URL? = nil, session: URLSession = .shared) {
        self.apiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        self.instructions = instructions.trimmingCharacters(in: .whitespacesAndNewlines)
        self.preserveInputStyle = preserveInputStyle
        self.cacheURL = cacheURL ?? Self.defaultCacheURL
        self.session = session
    }

    public func generate(source: SourceIcon, for app: InstalledApp, hueOverride: Double?) async throws -> GeneratedIcon {
        try Task.checkCancellation()
        guard instructions.count <= Self.maxInstructionLength else {
            throw IconError.invalidArgument("Describe your changes in \(Self.maxInstructionLength) characters or fewer.")
        }
        guard !apiKey.isEmpty,
              !apiKey.unicodeScalars.contains(where: { CharacterSet.whitespacesAndNewlines.union(.controlCharacters).contains($0) }) else {
            throw AIGenerationError.badKey
        }
        if let hueOverride, !hueOverride.isFinite || !(0...1).contains(hueOverride) {
            throw IconError.invalidArgument("The hue must be a number between 0 and 1.")
        }
        let hue = hueOverride.map { $0.truncatingRemainder(dividingBy: 1) }
            ?? AlgorithmicIconGenerator.stableHue(for: app.bundleID)
        let prompt = composedPrompt(hue: hue, hasHueOverride: hueOverride != nil)
        let key = try cacheKey(source: source, app: app, hue: hue, prompt: prompt)
        let cachedURL = cacheURL.appendingPathComponent(key).appendingPathExtension("png")
        if let cached = try? Data(contentsOf: cachedURL), let icon = try? makeIcon(png: cached, source: source, hue: hue) {
            return icon
        }
        if let task = inFlight[key] { return try await task.value }

        // Fail before any paid request if the cache cannot be created.
        do {
            try FileManager.default.createDirectory(at: cacheURL, withIntermediateDirectories: true,
                                                    attributes: [.posixPermissions: 0o700])
            let probeURL = cacheURL.appendingPathComponent(".write-check-\(UUID().uuidString)")
            try Data().write(to: probeURL, options: .atomic)
            try FileManager.default.removeItem(at: probeURL)
        } catch { throw AIGenerationError.cacheUnavailable }
        let task = Task { try await requestIcon(source: source, hue: hue, prompt: prompt, cachedURL: cachedURL) }
        inFlight[key] = task
        defer { inFlight[key] = nil }
        return try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
    }

    private func composedPrompt(hue: Double, hasHueOverride: Bool) -> String {
        if preserveInputStyle {
            return """
            Edit the supplied application icon preview by applying only the user's requested changes.
            Preserve all unspecified visual details from this image, including its palette, glyph,
            artwork, proportions, background, gradients, glow, shadow, and rounded-corner geometry.
            The user's instructions take precedence for the details they specifically ask to change.
            Keep the application recognizable unless the user specifically asks to change its symbol.
            Always return one 1024x1024 square icon with a fully transparent surrounding canvas.
            If the user has not requested any changes, preserve the supplied preview unchanged.

            User's requested changes:
            \(instructions)
            """
        }
        let degrees = Int((hue * 360).rounded())
        // Keep the original request and cache identity for the default style.
        guard !instructions.isEmpty else {
            return Self.stylePrompt + "\nUse background hue \(degrees) degrees in the HSV color wheel."
        }
        let colorPreference = hasHueOverride
            ? "The color selected in Icon Spice is background hue \(degrees) degrees in the HSV color wheel. Use it unless the user's instructions specify a different color."
            : "The default palette preference is background hue \(degrees) degrees in the HSV color wheel. Use it only when the user's instructions do not specify a color."
        return Self.customizationPrompt + "\n" + colorPreference + "\n" + """
        The user's instructions below take precedence over the default visual styling above
        wherever they overlap, including color, glow, background, and artwork details.
        Keep the application recognizable unless the user specifically asks to change its symbol.
        Always return one 1024x1024 square icon with a fully transparent surrounding canvas.

        User's requested changes:
        \(instructions)
        """
    }

    private func requestIcon(source: SourceIcon, hue: Double, prompt: String, cachedURL: URL) async throws -> GeneratedIcon {
        try Task.checkCancellation()
        guard source.pngData.count < 50 * 1024 * 1024,
              CGImageSourceCreateWithData(source.pngData as CFData, nil) != nil else {
            throw IconError.invalidImage
        }
        let boundary = "IconSpice-\(UUID().uuidString)"
        let fields = ["model": Self.model, "prompt": prompt, "n": "1", "size": "1024x1024",
                      "quality": "medium", "background": "transparent", "output_format": "png"]
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/images/edits")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 240
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.multipart(fields: fields, png: source.pngData, boundary: boundary)

        let data: Data
        let response: URLResponse
        do { (data, response) = try await session.data(for: request) }
        catch is CancellationError { throw CancellationError() }
        catch let error as URLError where error.code == .cancelled { throw CancellationError() }
        catch { throw AIGenerationError.transport }
        try Task.checkCancellation()
        guard let response = response as? HTTPURLResponse else { throw AIGenerationError.transport }
        switch response.statusCode {
        case 200...299: break
        case 401: throw AIGenerationError.badKey
        case 429:
            throw AIGenerationError.rateLimit(retryAfterSeconds: response.value(forHTTPHeaderField: "Retry-After").flatMap(Int.init))
        default: throw AIGenerationError.provider(statusCode: response.statusCode)
        }
        guard data.count < 100 * 1024 * 1024,
              let result = try? JSONDecoder().decode(ImageEditResponse.self, from: data),
              result.data.count == 1,
              let png = Data(base64Encoded: result.data[0].base64PNG) else {
            throw AIGenerationError.invalidResult
        }
        let icon = try makeIcon(png: png, source: source, hue: hue)
        do {
            try icon.pngData.write(to: cachedURL, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: cachedURL.path)
        } catch { throw AIGenerationError.cacheUnavailable }
        return icon
    }

    private func makeIcon(png: Data, source: SourceIcon, hue: Double) throws -> GeneratedIcon {
        guard png.count < 50 * 1024 * 1024,
              let imageSource = CGImageSourceCreateWithData(png as CFData, nil),
              CGImageSourceGetType(imageSource) == UTType.png.identifier as CFString,
              CGImageSourceGetCount(imageSource) == 1,
              let image = CGImageSourceCreateImageAtIndex(imageSource, 0, nil),
              image.width == 1024, image.height == 1024 else {
            throw AIGenerationError.invalidResult
        }
        do {
            let normalized = try IconImageCodec.normalizePNG(png)
            return GeneratedIcon(pngData: normalized, icnsData: try IconImageCodec.icnsData(fromPNG: normalized),
                                 hue: hue, sourceHash: source.hash, kind: .ai)
        } catch { throw AIGenerationError.invalidResult }
    }

    private func cacheKey(source: SourceIcon, app: InstalledApp, hue: Double, prompt: String) throws -> String {
        let identity = CacheIdentity(bundleID: app.bundleID, sourceHash: source.hash,
                                     pngHash: Self.digest(source.pngData), hue: hue,
                                     model: Self.model, styleVersion: Self.styleVersion,
                                     prompt: instructions.isEmpty && !preserveInputStyle ? Self.stylePrompt : prompt)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return Self.digest(try encoder.encode(identity))
    }

    private static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static var defaultCacheURL: URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("com.iconspice", isDirectory: true).appendingPathComponent("AI", isDirectory: true)
    }

    private static func multipart(fields: [String: String], png: Data, boundary: String) -> Data {
        var body = Data()
        for name in fields.keys.sorted() {
            body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(fields[name]!)\r\n".utf8))
        }
        body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"image[]\"; filename=\"source.png\"\r\nContent-Type: image/png\r\n\r\n".utf8))
        body.append(png)
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))
        return body
    }
}

private struct ImageEditResponse: Decodable {
    let data: [ImageResult]
    struct ImageResult: Decodable {
        let base64PNG: String
        enum CodingKeys: String, CodingKey { case base64PNG = "b64_json" }
    }
}

private struct CacheIdentity: Encodable {
    let bundleID: BundleID
    let sourceHash: String
    let pngHash: String
    let hue: Double
    let model: String
    let styleVersion: String
    let prompt: String
}
