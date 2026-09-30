import Darwin
import Foundation
import IconSpiceCore

@main
struct IconSpiceCLI {
    @MainActor
    static func main() async {
        do {
            let command = try Command.parse(Array(CommandLine.arguments.dropFirst()))
            try await run(command)
        } catch let error as UsageError {
            writeError(error.message + "\nRun iconspice --help for usage.")
            exit(2)
        } catch {
            writeError(error.localizedDescription)
            exit(1)
        }
    }

    @MainActor
    private static func run(_ command: Command) async throws {
        let scanner = AppScanner()
        switch command {
        case .help:
            print(usage)
        case .scan(let json):
            let apps = scanner.scan()
            if json { try printJSON(apps) }
            else {
                for app in apps {
                    print("\(app.bundleID)\t\(app.name)\t\(app.isProtected ? "protected" : "available")\t\(app.url.path)")
                }
                print("\(apps.count) apps")
            }
        case .generate(let bundleID, let directory, let hue):
            let app = try scanner.resolve(bundleID: BundleID(bundleID))
            let workflow = IconWorkflow()
            let (_, icon) = try await workflow.generate(for: app, hueOverride: hue)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let stem = safeFilename(app.bundleID.rawValue)
            let pngURL = directory.appendingPathComponent(stem).appendingPathExtension("png")
            let icnsURL = directory.appendingPathComponent(stem).appendingPathExtension("icns")
            try icon.pngData.write(to: pngURL, options: .atomic)
            try icon.icnsData.write(to: icnsURL, options: .atomic)
            print("\(pngURL.path)\n\(icnsURL.path)")
        case .apply(let bundleID, let hue, let refreshDock):
            let app = try scanner.resolve(bundleID: BundleID(bundleID))
            let workflow = IconWorkflow()
            let (source, icon) = try await workflow.generate(for: app, hueOverride: hue)
            let result = await workflow.apply(icon, source: source, to: app, hueOverride: hue)
            try requireSuccess(result, appName: app.name)
            print("Applied \(app.name).")
            if refreshDock { try IconApplier().refreshDock() }
        case .revert(let bundleID, let all, let refreshDock):
            let workflow = IconWorkflow()
            var failures = 0
            var changed = false
            if all {
                let records = try await workflow.store.records()
                for record in records {
                    let app = InstalledApp(bundleID: record.bundleID, name: record.appName, url: record.appURL)
                    let result = await workflow.revert(app)
                    if result.succeeded { print("Reverted \(app.name)."); changed = true }
                    else { writeError("\(app.name): \(result.message)"); failures += 1 }
                }
                if records.isEmpty { print("No tracked icons to revert.") }
            } else if let bundleID {
                let app = try scanner.resolve(bundleID: BundleID(bundleID))
                let result = await workflow.revert(app)
                try requireSuccess(result, appName: app.name)
                print("Reverted \(app.name).")
                changed = true
            }
            if refreshDock && changed { try IconApplier().refreshDock() }
            if failures > 0 { throw IconError.fileOperation("\(failures) icons could not be reverted.") }
        case .status(let json):
            let records = try await IconStore().records()
            let applier = IconApplier()
            let status = records.map { record in
                TrackedStatus(bundleID: record.bundleID, appName: record.appName, appURL: record.appURL,
                              generator: record.generator, hue: record.hue,
                              installed: FileManager.default.fileExists(atPath: record.appURL.path),
                              hasCustomIcon: applier.hasCustomIcon(at: record.appURL), appliedAt: record.appliedAt)
            }
            if json { try printJSON(status) }
            else {
                for entry in status {
                    let state = !entry.installed ? "missing app" : entry.hasCustomIcon ? "custom icon present" : "needs reapply"
                    print("\(entry.bundleID)\t\(entry.appName)\t\(state)\t\(entry.generator.rawValue)\t\(entry.appURL.path)")
                }
                print("\(records.count) tracked icons")
            }
        case .reapply(let refreshDock):
            let outcomes = await IconWorkflow().reapplyTracked()
            var failures = 0
            var changed = false
            for outcome in outcomes {
                print("\(outcome.appName): \(outcome.action.rawValue) — \(outcome.result.message)")
                if !outcome.result.succeeded { failures += 1 }
                if outcome.result.succeeded && (outcome.action == .reapplied || outcome.action == .regenerated) {
                    changed = true
                }
            }
            if outcomes.isEmpty { print("No tracked icons to reapply.") }
            if refreshDock && changed { try IconApplier().refreshDock() }
            if failures > 0 { throw IconError.fileOperation("\(failures) icons could not be reapplied.") }
        }
    }

    private static func requireSuccess(_ result: ApplyResult, appName: String) throws {
        guard result.succeeded else { throw IconError.fileOperation("\(appName): \(result.message)") }
    }

    private static func printJSON<T: Encodable>(_ value: T) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(value)
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data("\n".utf8))
    }

    private static func safeFilename(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
        let name = String(value.unicodeScalars.map { allowed.contains($0) ? Character($0) : "_" })
        return name.isEmpty || name == "." || name == ".." ? "icon" : name
    }

    private static func writeError(_ message: String) {
        FileHandle.standardError.write(Data("iconspice: \(message)\n".utf8))
    }

    static let usage = """
    Icon Spice — generate and manage vivid macOS app icons

    Usage:
      iconspice scan [--json]
      iconspice generate BUNDLE_ID --output DIRECTORY [--hue 0...360]
      iconspice apply BUNDLE_ID [--hue 0...360] [--refresh-dock]
      iconspice revert BUNDLE_ID [--refresh-dock]
      iconspice revert --all [--refresh-dock]
      iconspice status [--json]
      iconspice reapply [--refresh-dock]

    Generate exports a PNG and ICNS without applying them. Apply stores the
    previous custom icon so revert can restore it. Revert --all affects tracked
    icons only. Dock refresh restarts the Dock and is opt-in.
    """
}

private enum Command {
    case help
    case scan(json: Bool)
    case generate(bundleID: String, directory: URL, hue: Double?)
    case apply(bundleID: String, hue: Double?, refreshDock: Bool)
    case revert(bundleID: String?, all: Bool, refreshDock: Bool)
    case status(json: Bool)
    case reapply(refreshDock: Bool)

    static func parse(_ arguments: [String]) throws -> Command {
        guard let verb = arguments.first else { return .help }
        if verb == "--help" || verb == "-h" || verb == "help" {
            guard arguments.count == 1 else { throw UsageError("Unexpected arguments after help.") }
            return .help
        }
        let allowed: Set<String>
        switch verb {
        case "scan", "status": allowed = ["--json"]
        case "generate": allowed = ["--output", "--hue"]
        case "apply": allowed = ["--hue", "--refresh-dock"]
        case "revert": allowed = ["--all", "--refresh-dock"]
        case "reapply": allowed = ["--refresh-dock"]
        default: throw UsageError("Unknown command: \(verb).")
        }
        if arguments.dropFirst().contains("--help") || arguments.dropFirst().contains("-h") { return .help }
        var options: [String: String] = [:]
        var positional: [String] = []
        var index = 1
        while index < arguments.count {
            let argument = arguments[index]
            if argument.hasPrefix("-") {
                guard allowed.contains(argument) else { throw UsageError("Unknown option for \(verb): \(argument).") }
                guard options[argument] == nil else { throw UsageError("Option \(argument) was provided more than once.") }
                if argument == "--output" || argument == "--hue" {
                    index += 1
                    guard index < arguments.count, !arguments[index].hasPrefix("--") else {
                        throw UsageError("Option \(argument) requires a value.")
                    }
                    options[argument] = arguments[index]
                } else { options[argument] = "true" }
            } else { positional.append(argument) }
            index += 1
        }
        let hue: Double?
        if let value = options["--hue"] {
            guard let number = Double(value), number.isFinite, (0...360).contains(number) else {
                throw UsageError("Hue must be a number between 0 and 360.")
            }
            hue = number / 360
        } else { hue = nil }
        let refreshDock = options["--refresh-dock"] != nil
        switch verb {
        case "scan", "status":
            guard positional.isEmpty else { throw UsageError("\(verb) takes no bundle ID.") }
            return verb == "scan" ? .scan(json: options["--json"] != nil) : .status(json: options["--json"] != nil)
        case "generate":
            guard positional.count == 1 else { throw UsageError("generate requires one bundle ID.") }
            guard let output = options["--output"], !output.isEmpty else { throw UsageError("generate requires --output DIRECTORY.") }
            let directory = URL(fileURLWithPath: NSString(string: output).expandingTildeInPath, isDirectory: true)
            return .generate(bundleID: positional[0], directory: directory, hue: hue)
        case "apply":
            guard positional.count == 1 else { throw UsageError("apply requires one bundle ID.") }
            return .apply(bundleID: positional[0], hue: hue, refreshDock: refreshDock)
        case "revert":
            let all = options["--all"] != nil
            guard all ? positional.isEmpty : positional.count == 1 else {
                throw UsageError("revert requires one bundle ID or --all.")
            }
            return .revert(bundleID: positional.first, all: all, refreshDock: refreshDock)
        default:
            guard positional.isEmpty else { throw UsageError("reapply takes no bundle ID.") }
            return .reapply(refreshDock: refreshDock)
        }
    }
}

private struct UsageError: Error {
    let message: String
    init(_ message: String) { self.message = message }
}

private struct TrackedStatus: Encodable {
    let bundleID: BundleID
    let appName: String
    let appURL: URL
    let generator: GeneratorKind
    let hue: Double
    let installed: Bool
    let hasCustomIcon: Bool
    let appliedAt: Date
}
