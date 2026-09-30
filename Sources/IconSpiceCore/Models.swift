import Foundation

public struct BundleID: RawRepresentable, Codable, Hashable, Sendable, CustomStringConvertible {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(_ value: String) { self.rawValue = value }
    public var description: String { rawValue }
}

public struct InstalledApp: Identifiable, Codable, Hashable, Sendable {
    public var id: String { url.path }
    public let bundleID: BundleID
    public let name: String
    public let url: URL
    public let version: String
    public let isProtected: Bool
    public init(bundleID: BundleID, name: String, url: URL, version: String = "", isProtected: Bool = false) {
        self.bundleID = bundleID
        self.name = name
        self.url = url
        self.version = version
        self.isProtected = isProtected
    }
}

public struct SourceIcon: Sendable {
    public let pngData: Data
    public let hash: String
    public init(pngData: Data, hash: String) { self.pngData = pngData; self.hash = hash }
}

public enum GeneratorKind: String, Codable, Sendable { case algorithmic, ai, imported }

public struct GeneratedIcon: Sendable {
    public let pngData: Data
    public let icnsData: Data
    /// Hue is a unit fraction, from 0 to 1. CLI degrees are converted at its boundary.
    public let hue: Double
    public let sourceHash: String
    public let kind: GeneratorKind
    public init(pngData: Data, icnsData: Data, hue: Double, sourceHash: String, kind: GeneratorKind = .algorithmic) {
        self.pngData = pngData; self.icnsData = icnsData; self.hue = hue
        self.sourceHash = sourceHash; self.kind = kind
    }
}

public protocol IconGenerating: Sendable {
    func generate(source: SourceIcon, for app: InstalledApp, hueOverride: Double?) async throws -> GeneratedIcon
}

public enum IconError: Error, Sendable, LocalizedError, Equatable {
    case invalidImage
    case sourceUnavailable(String)
    case fileOperation(String)
    case appNotFound(String)
    case invalidArgument(String)
    public var errorDescription: String? {
        switch self {
        case .invalidImage: "The icon image could not be decoded."
        case .sourceUnavailable(let message), .fileOperation(let message), .invalidArgument(let message): message
        case .appNotFound(let id): "No installed app was found for \(id)."
        }
    }
}

public enum ApplyResult: Sendable, Equatable {
    case success
    case permissionDenied
    case protectedApp
    case failed(String)
    public var succeeded: Bool { self == .success }
    public var message: String {
        switch self {
        case .success: "Done"
        case .permissionDenied: "Allow Icon Spice in System Settings → Privacy & Security → App Management, then try again."
        case .protectedApp: "This app is protected by macOS and cannot be changed."
        case .failed(let reason): reason
        }
    }
}

public struct IconRecord: Codable, Sendable, Equatable, Identifiable {
    public var id: String { appURL.path }
    public let bundleID: BundleID
    public let appURL: URL
    public let appName: String
    public let generatedIconURL: URL
    public let sourceIconURL: URL
    public let originalCustomIconURL: URL?
    public let sourceHash: String
    public let hue: Double
    public let hueOverride: Double?
    public let generator: GeneratorKind
    public let appliedAt: Date
    public init(bundleID: BundleID, appURL: URL, appName: String, generatedIconURL: URL,
                sourceIconURL: URL, originalCustomIconURL: URL?, sourceHash: String,
                hue: Double, hueOverride: Double?, generator: GeneratorKind, appliedAt: Date = Date()) {
        self.bundleID = bundleID; self.appURL = appURL; self.appName = appName
        self.generatedIconURL = generatedIconURL; self.sourceIconURL = sourceIconURL
        self.originalCustomIconURL = originalCustomIconURL; self.sourceHash = sourceHash
        self.hue = hue; self.hueOverride = hueOverride; self.generator = generator; self.appliedAt = appliedAt
    }
}
