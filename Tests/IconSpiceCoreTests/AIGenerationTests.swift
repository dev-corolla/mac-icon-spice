import CoreGraphics
import Foundation
import XCTest
@testable import IconSpiceCore

final class AIGenerationTests: XCTestCase, @unchecked Sendable {
    func testSuccessfulResultIsCachedAcrossGeneratorInstances() async throws {
        let fixture = try makePNG()
        let stub = ResponseStub(status: 200, data: try imageResponse(fixture))
        let directory = temporaryCache()
        defer { try? FileManager.default.removeItem(at: directory) }
        let session = makeSession(stub)
        defer { session.invalidateAndCancel() }
        let source = SourceIcon(pngData: fixture, hash: "original-artwork")
        let app = fixtureApp()
        let generator = OpenAIIconGenerator(apiKey: "test-placeholder", cacheURL: directory, session: session)
        let first = try await generator.generate(source: source, for: app, hueOverride: 160.0 / 360)
        let second = try await OpenAIIconGenerator(apiKey: "another-placeholder", cacheURL: directory, session: session)
            .generate(source: source, for: app, hueOverride: 160.0 / 360)

        XCTAssertEqual(first.pngData, second.pngData)
        XCTAssertEqual(first.kind, .ai)
        XCTAssertEqual(first.sourceHash, source.hash)
        XCTAssertEqual(first.hue, 160.0 / 360)
        XCTAssertEqual(String(data: first.icnsData.prefix(4), encoding: .utf8), "icns")
        XCTAssertEqual(stub.requestCount, 1)
        let request = try XCTUnwrap(stub.lastRequest)
        XCTAssertEqual(request.url?.host, "api.openai.com")
        XCTAssertEqual(request.httpMethod, "POST")
        let requestBody = String(decoding: try XCTUnwrap(stub.lastBody), as: UTF8.self)
        XCTAssertTrue(requestBody.contains(OpenAIIconGenerator.model))
        XCTAssertTrue(requestBody.contains("name=\"image[]\""))
        XCTAssertTrue(requestBody.contains("background hue 160"))
        let cacheFiles = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        XCTAssertEqual(cacheFiles.count, 1)
        XCTAssertFalse(String(decoding: try Data(contentsOf: cacheFiles[0]), as: UTF8.self).contains("test-placeholder"))
    }

    func testArtworkAndHueChangesInvalidateCache() async throws {
        let fixture = try makePNG()
        let stub = ResponseStub(status: 200, data: try imageResponse(fixture))
        let directory = temporaryCache()
        defer { try? FileManager.default.removeItem(at: directory) }
        let session = makeSession(stub)
        defer { session.invalidateAndCancel() }
        let generator = OpenAIIconGenerator(apiKey: "test-placeholder", cacheURL: directory, session: session)
        let app = fixtureApp()
        let source = SourceIcon(pngData: fixture, hash: "original")
        _ = try await generator.generate(source: source, for: app, hueOverride: 160.0 / 360)
        _ = try await generator.generate(source: SourceIcon(pngData: fixture, hash: "updated"), for: app, hueOverride: 160.0 / 360)
        _ = try await generator.generate(source: source, for: app, hueOverride: 200.0 / 360)
        XCTAssertEqual(stub.requestCount, 3)
    }

    func testCustomizationPreservesMultilineUnicodeInstructionsAndOutputFormat() async throws {
        let fixture = try makePNG()
        let stub = ResponseStub(status: 200, data: try imageResponse(fixture))
        let directory = temporaryCache()
        defer { try? FileManager.default.removeItem(at: directory) }
        let session = makeSession(stub)
        defer { session.invalidateAndCancel() }
        let instructions = "Make the background sunset orange.\nRemove the glow and add a tiny étoile ✨."
        let source = SourceIcon(pngData: fixture, hash: "canonical-original")
        let generator = OpenAIIconGenerator(apiKey: "test-placeholder", instructions: instructions,
                                            cacheURL: directory, session: session)
        let icon = try await generator.generate(source: source, for: fixtureApp(), hueOverride: 160.0 / 360)

        XCTAssertEqual(icon.sourceHash, source.hash)
        XCTAssertEqual(icon.kind, .ai)
        let body = String(decoding: try XCTUnwrap(stub.lastBody), as: UTF8.self)
        XCTAssertTrue(body.contains("User's requested changes:\n" + instructions))
        XCTAssertTrue(body.contains("take precedence over the default visual styling"))
        XCTAssertTrue(body.contains("The color selected in Icon Spice is background hue 160"))
        XCTAssertTrue(body.contains("unless the user's instructions specify a different color"))
        XCTAssertTrue(body.contains("name=\"size\"\r\n\r\n1024x1024\r\n"))
        XCTAssertTrue(body.contains("name=\"background\"\r\n\r\ntransparent\r\n"))
    }

    func testDifferentInstructionsInvalidateCache() async throws {
        let fixture = try makePNG()
        let stub = ResponseStub(status: 200, data: try imageResponse(fixture))
        let directory = temporaryCache()
        defer { try? FileManager.default.removeItem(at: directory) }
        let session = makeSession(stub)
        defer { session.invalidateAndCancel() }
        let source = SourceIcon(pngData: fixture, hash: "original")
        for instructions in ["Use orange and remove the glow.", "Use violet and add a soft glow."] {
            let generator = OpenAIIconGenerator(apiKey: "test-placeholder", instructions: instructions,
                                                cacheURL: directory, session: session)
            _ = try await generator.generate(source: source, for: fixtureApp(), hueOverride: nil)
        }

        XCTAssertEqual(stub.requestCount, 2)
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        XCTAssertEqual(files.count, 2)
    }

    func testDefaultCustomizationUsesCrispArtworkWithoutForcedGlow() async throws {
        let fixture = try makePNG()
        let stub = ResponseStub(status: 200, data: try imageResponse(fixture))
        let directory = temporaryCache()
        defer { try? FileManager.default.removeItem(at: directory) }
        let session = makeSession(stub)
        defer { session.invalidateAndCancel() }
        let instructions = OpenAIIconGenerator.defaultCustomizationInstructions
        let generator = OpenAIIconGenerator(apiKey: "test-placeholder", instructions: instructions,
                                            cacheURL: directory, session: session)
        _ = try await generator.generate(source: SourceIcon(pngData: fixture, hash: "original"),
                                          for: fixtureApp(), hueOverride: nil)

        XCTAssertEqual(stub.requestCount, 1)
        let body = String(decoding: try XCTUnwrap(stub.lastBody), as: UTF8.self)
        XCTAssertTrue(body.contains("User's requested changes:\n" + instructions))
        XCTAssertTrue(body.contains("Preserve the logo’s exact silhouette, proportions, spacing, original colors"))
        XCTAssertTrue(body.contains("Apply subtle gradients only to selected background areas"))
        XCTAssertTrue(body.contains("remove strong glow, bloom, neon halos, glossy bevels, and clutter"))
        XCTAssertTrue(body.contains("name=\"background\"\r\n\r\ntransparent\r\n"))
        XCTAssertFalse(body.contains("luminous glyph"))
        XCTAssertFalse(body.contains("restrained inner glow"))
        XCTAssertFalse(body.contains("No text, labels, frames, scenery, or extra symbols"))
    }

    func testIdenticalTrimmedInstructionsReuseCacheAcrossInstances() async throws {
        let fixture = try makePNG()
        let stub = ResponseStub(status: 200, data: try imageResponse(fixture))
        let directory = temporaryCache()
        defer { try? FileManager.default.removeItem(at: directory) }
        let session = makeSession(stub)
        defer { session.invalidateAndCancel() }
        let source = SourceIcon(pngData: fixture, hash: "original")
        let instructions = "Use burnt orange.\nKeep the symbol white."
        let first = try await OpenAIIconGenerator(apiKey: "test-placeholder", instructions: instructions,
                                                 cacheURL: directory, session: session)
            .generate(source: source, for: fixtureApp(), hueOverride: nil)
        let second = try await OpenAIIconGenerator(apiKey: "another-placeholder", instructions: "\n  \(instructions) \t\n",
                                                  cacheURL: directory, session: session)
            .generate(source: source, for: fixtureApp(), hueOverride: nil)

        XCTAssertEqual(first.pngData, second.pngData)
        XCTAssertEqual(stub.requestCount, 1)
    }

    func testWhitespaceInstructionsReuseDefaultCacheAndKeepOriginalPrompt() async throws {
        let fixture = try makePNG()
        let stub = ResponseStub(status: 200, data: try imageResponse(fixture))
        let directory = temporaryCache()
        defer { try? FileManager.default.removeItem(at: directory) }
        let session = makeSession(stub)
        defer { session.invalidateAndCancel() }
        let source = SourceIcon(pngData: fixture, hash: "original")
        let first = try await OpenAIIconGenerator(apiKey: "test-placeholder", cacheURL: directory, session: session)
            .generate(source: source, for: fixtureApp(), hueOverride: 160.0 / 360)
        let second = try await OpenAIIconGenerator(apiKey: "test-placeholder", instructions: " \n\t ",
                                                  cacheURL: directory, session: session)
            .generate(source: source, for: fixtureApp(), hueOverride: 160.0 / 360)

        XCTAssertEqual(first.pngData, second.pngData)
        XCTAssertEqual(stub.requestCount, 1)
        let body = String(decoding: try XCTUnwrap(stub.lastBody), as: UTF8.self)
        let originalPrompt = OpenAIIconGenerator.stylePrompt + "\nUse background hue 160 degrees in the HSV color wheel."
        XCTAssertTrue(body.contains("name=\"prompt\"\r\n\r\n" + originalPrompt + "\r\n"))
        XCTAssertFalse(body.contains("User's requested changes:"))
    }

    func testPromptDistinguishesDefaultPaletteFromExplicitHueSelection() async throws {
        let fixture = try makePNG()
        let stub = ResponseStub(status: 200, data: try imageResponse(fixture))
        let directory = temporaryCache()
        defer { try? FileManager.default.removeItem(at: directory) }
        let session = makeSession(stub)
        defer { session.invalidateAndCancel() }
        let source = SourceIcon(pngData: fixture, hash: "original")
        let app = fixtureApp()
        let generator = OpenAIIconGenerator(apiKey: "test-placeholder", instructions: "Remove the glow.",
                                            cacheURL: directory, session: session)
        _ = try await generator.generate(source: source, for: app, hueOverride: nil)
        let defaultBody = String(decoding: try XCTUnwrap(stub.lastBody), as: UTF8.self)
        XCTAssertTrue(defaultBody.contains("The default palette preference is background hue"))
        XCTAssertTrue(defaultBody.contains("only when the user's instructions do not specify a color"))

        _ = try await generator.generate(source: source, for: app,
                                         hueOverride: AlgorithmicIconGenerator.stableHue(for: app.bundleID))
        let selectedBody = String(decoding: try XCTUnwrap(stub.lastBody), as: UTF8.self)
        XCTAssertTrue(selectedBody.contains("The color selected in Icon Spice is background hue"))
        XCTAssertEqual(stub.requestCount, 2)
    }

    func testRefinedArtworkInvalidatesCacheWithUnchangedCanonicalSourceHash() async throws {
        let fixture = try makePNG()
        let preview = try makePNG(color: CGColor(red: 0.8, green: 0.3, blue: 0.1, alpha: 1))
        let stub = ResponseStub(status: 200, data: try imageResponse(fixture))
        let directory = temporaryCache()
        defer { try? FileManager.default.removeItem(at: directory) }
        let session = makeSession(stub)
        defer { session.invalidateAndCancel() }
        let generator = OpenAIIconGenerator(apiKey: "test-placeholder", instructions: "Remove the glow.",
                                            preserveInputStyle: true,
                                            cacheURL: directory, session: session)
        for png in [fixture, preview] {
            let icon = try await generator.generate(source: SourceIcon(pngData: png, hash: "canonical-original"),
                                                     for: fixtureApp(), hueOverride: nil)
            XCTAssertEqual(icon.sourceHash, "canonical-original")
        }

        XCTAssertEqual(stub.requestCount, 2)
    }

    func testRefinementPreservesUnspecifiedStyleAndUsesItsOwnCache() async throws {
        let fixture = try makePNG()
        let stub = ResponseStub(status: 200, data: try imageResponse(fixture))
        let directory = temporaryCache()
        defer { try? FileManager.default.removeItem(at: directory) }
        let session = makeSession(stub)
        defer { session.invalidateAndCancel() }
        let source = SourceIcon(pngData: fixture, hash: "original")
        let instructions = "Remove the glow."
        let restyle = OpenAIIconGenerator(apiKey: "test-placeholder", instructions: instructions,
                                         cacheURL: directory, session: session)
        _ = try await restyle.generate(source: source, for: fixtureApp(), hueOverride: 160.0 / 360)
        let refine = OpenAIIconGenerator(apiKey: "test-placeholder", instructions: instructions,
                                        preserveInputStyle: true, cacheURL: directory, session: session)
        _ = try await refine.generate(source: source, for: fixtureApp(), hueOverride: 160.0 / 360)

        XCTAssertEqual(stub.requestCount, 2)
        let body = String(decoding: try XCTUnwrap(stub.lastBody), as: UTF8.self)
        XCTAssertTrue(body.contains("applying only the user's requested changes"))
        XCTAssertTrue(body.contains("Preserve all unspecified visual details"))
        XCTAssertTrue(body.contains("User's requested changes:\n" + instructions))
        XCTAssertFalse(body.contains("Restyle the supplied application icon"))
        XCTAssertFalse(body.contains("background hue"))
        let repeated = OpenAIIconGenerator(apiKey: "test-placeholder", instructions: "  \(instructions)\n",
                                          preserveInputStyle: true, cacheURL: directory, session: session)
        _ = try await repeated.generate(source: source, for: fixtureApp(), hueOverride: 160.0 / 360)
        XCTAssertEqual(stub.requestCount, 2)
    }

    func testEmptyRefinementInstructionsDoNotReuseDefaultRestyleCache() async throws {
        let fixture = try makePNG()
        let stub = ResponseStub(status: 200, data: try imageResponse(fixture))
        let directory = temporaryCache()
        defer { try? FileManager.default.removeItem(at: directory) }
        let session = makeSession(stub)
        defer { session.invalidateAndCancel() }
        let source = SourceIcon(pngData: fixture, hash: "original")
        _ = try await OpenAIIconGenerator(apiKey: "test-placeholder", cacheURL: directory, session: session)
            .generate(source: source, for: fixtureApp(), hueOverride: nil)
        _ = try await OpenAIIconGenerator(apiKey: "test-placeholder", preserveInputStyle: true,
                                          cacheURL: directory, session: session)
            .generate(source: source, for: fixtureApp(), hueOverride: nil)

        XCTAssertEqual(stub.requestCount, 2)
        let body = String(decoding: try XCTUnwrap(stub.lastBody), as: UTF8.self)
        XCTAssertTrue(body.contains("preserve the supplied preview unchanged"))
    }

    func testTooLongInstructionsFailBeforeRequestOrCacheCreation() async throws {
        let stub = ResponseStub(status: 200, data: Data())
        let directory = temporaryCache()
        defer { try? FileManager.default.removeItem(at: directory) }
        let session = makeSession(stub)
        defer { session.invalidateAndCancel() }
        let generator = OpenAIIconGenerator(apiKey: "test-placeholder",
                                            instructions: String(repeating: "a", count: OpenAIIconGenerator.maxInstructionLength + 1),
                                            cacheURL: directory, session: session)
        do {
            _ = try await generator.generate(source: SourceIcon(pngData: makePNG(), hash: "original"),
                                              for: fixtureApp(), hueOverride: nil)
            XCTFail("An overlong prompt must be rejected.")
        } catch let error as IconError {
            XCTAssertEqual(error, .invalidArgument("Describe your changes in \(OpenAIIconGenerator.maxInstructionLength) characters or fewer."))
        }

        XCTAssertEqual(stub.requestCount, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
    }

    func testMaximumInstructionLengthIsAcceptedAfterTrimming() async throws {
        let fixture = try makePNG()
        let stub = ResponseStub(status: 200, data: try imageResponse(fixture))
        let directory = temporaryCache()
        defer { try? FileManager.default.removeItem(at: directory) }
        let session = makeSession(stub)
        defer { session.invalidateAndCancel() }
        let instructions = String(repeating: "é", count: OpenAIIconGenerator.maxInstructionLength)
        let generator = OpenAIIconGenerator(apiKey: "test-placeholder", instructions: "\n \(instructions) \n",
                                            cacheURL: directory, session: session)
        _ = try await generator.generate(source: SourceIcon(pngData: fixture, hash: "original"),
                                          for: fixtureApp(), hueOverride: nil)

        XCTAssertEqual(stub.requestCount, 1)
        let body = String(decoding: try XCTUnwrap(stub.lastBody), as: UTF8.self)
        XCTAssertTrue(body.contains("User's requested changes:\n" + instructions + "\r\n"))
    }

    func testUnauthorizedReturnsTypedErrorWithoutCaching() async throws {
        try await assertFailure(status: 401, response: Data("{}".utf8), expected: .badKey)
    }

    func testRateLimitPreservesRetryDelay() async throws {
        try await assertFailure(status: 429, response: Data("{}".utf8), headers: ["Retry-After": "12"],
                                expected: .rateLimit(retryAfterSeconds: 12))
    }

    func testMalformedResponseReturnsTypedError() async throws {
        try await assertFailure(status: 200, response: Data("{\"data\":[{\"b64_json\":\"not base64\"}]}".utf8),
                                expected: .invalidResult)
    }

    func testWrongSizeProviderImageIsRejected() async throws {
        try await assertFailure(status: 200, response: try imageResponse(makePNG(size: 32)), expected: .invalidResult)
    }

    func testEmptyKeyDoesNotMakeARequest() async throws {
        let stub = ResponseStub(status: 200, data: Data())
        let directory = temporaryCache()
        defer { try? FileManager.default.removeItem(at: directory) }
        let session = makeSession(stub)
        defer { session.invalidateAndCancel() }
        let generator = OpenAIIconGenerator(apiKey: "\n ", cacheURL: directory, session: session)
        do {
            _ = try await generator.generate(source: SourceIcon(pngData: makePNG(), hash: "test"), for: fixtureApp(), hueOverride: nil)
            XCTFail("An empty key must be rejected.")
        } catch let error as AIGenerationError {
            XCTAssertEqual(error, .badKey)
        }
        XCTAssertEqual(stub.requestCount, 0)
    }

    private func assertFailure(status: Int, response: Data, headers: [String: String] = [:],
                               expected: AIGenerationError) async throws {
        let stub = ResponseStub(status: status, data: response, headers: headers)
        let directory = temporaryCache()
        defer { try? FileManager.default.removeItem(at: directory) }
        let session = makeSession(stub)
        defer { session.invalidateAndCancel() }
        let generator = OpenAIIconGenerator(apiKey: "test-placeholder", cacheURL: directory, session: session)
        do {
            _ = try await generator.generate(source: SourceIcon(pngData: makePNG(), hash: "test"), for: fixtureApp(), hueOverride: nil)
            XCTFail("Expected \(expected).")
        } catch let error as AIGenerationError { XCTAssertEqual(error, expected) }
        XCTAssertEqual(stub.requestCount, 1)
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        XCTAssertTrue(files.isEmpty)
    }

    private func temporaryCache() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("iconspice-ai-tests-\(UUID().uuidString)", isDirectory: true)
    }

    private func fixtureApp() -> InstalledApp {
        InstalledApp(bundleID: BundleID("test.iconspice.fixture"), name: "Fixture", url: URL(fileURLWithPath: "/fixture/Example.app"))
    }

    private func makePNG(size: Int = 1024, color: CGColor? = nil) throws -> Data {
        let context = try IconImageCodec.bitmapContext(size: size)
        context.setFillColor(color ?? CGColor(red: 0.2, green: 0.5, blue: 0.8, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: size, height: size))
        return try IconImageCodec.pngData(from: XCTUnwrap(context.makeImage()))
    }

    private func imageResponse(_ png: Data) throws -> Data {
        try JSONEncoder().encode(FixtureResponse(data: [FixtureResult(base64PNG: png.base64EncodedString())]))
    }

    private func makeSession(_ stub: ResponseStub) -> URLSession {
        StubURLProtocol.register(stub)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        configuration.httpAdditionalHeaders = ["X-IconSpice-Test": stub.id]
        return URLSession(configuration: configuration)
    }
}

private struct FixtureResponse: Encodable { let data: [FixtureResult] }
private struct FixtureResult: Encodable {
    let base64PNG: String
    enum CodingKeys: String, CodingKey { case base64PNG = "b64_json" }
}

private final class ResponseStub: @unchecked Sendable {
    let id = UUID().uuidString
    let status: Int
    let data: Data
    let headers: [String: String]
    private let lock = NSLock()
    private var requests: [URLRequest] = []
    private var bodies: [Data?] = []
    var requestCount: Int { lock.withLock { requests.count } }
    var lastRequest: URLRequest? { lock.withLock { requests.last } }
    var lastBody: Data? { lock.withLock { bodies.last ?? nil } }
    init(status: Int, data: Data, headers: [String: String] = [:]) {
        self.status = status; self.data = data; self.headers = headers
    }
    func record(_ request: URLRequest) {
        var body = request.httpBody
        if body == nil, let stream = request.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var bytes = [UInt8](repeating: 0, count: 4096)
            var data = Data()
            while stream.hasBytesAvailable {
                let count = stream.read(&bytes, maxLength: bytes.count)
                guard count > 0 else { break }
                data.append(contentsOf: bytes.prefix(count))
            }
            body = data
        }
        lock.withLock { requests.append(request); bodies.append(body) }
    }
}

private final class StubRegistry: @unchecked Sendable {
    private let lock = NSLock()
    private var stubs: [String: ResponseStub] = [:]
    func register(_ stub: ResponseStub) { lock.withLock { stubs[stub.id] = stub } }
    func stub(for id: String) -> ResponseStub? { lock.withLock { stubs[id] } }
}

private final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    private static let registry = StubRegistry()
    static func register(_ stub: ResponseStub) { registry.register(stub) }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let id = request.value(forHTTPHeaderField: "X-IconSpice-Test"),
              let stub = Self.registry.stub(for: id), let url = request.url,
              let response = HTTPURLResponse(url: url, statusCode: stub.status, httpVersion: "HTTP/1.1", headerFields: stub.headers) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        stub.record(request)
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: stub.data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
