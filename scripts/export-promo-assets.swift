// Read-only presentation assets. No installed icons are changed and no AI requests are made.
import AppKit
import Foundation
import IconSpiceCore

@main
struct ExportPromoAssets {
    @MainActor static func main() async throws {
        guard CommandLine.arguments.count == 2 else {
            print("Usage: export-promo-assets OUTPUT_DIRECTORY")
            return
        }
        let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let apps = AppScanner().scan()
        let chosen = [("linear", "com.linear"), ("t3", "com.t3tools.t3code"),
                      ("cursor", "com.todesktop.230313mzl4w4u92"), ("zed", "dev.zed.Zed"),
                      ("chatgpt", "com.openai.codex"), ("figma", "com.figma.Desktop")]
        for (slug, bundleID) in chosen {
            guard let app = apps.first(where: { $0.bundleID.rawValue == bundleID }) else {
                throw IconError.invalidArgument("Install \(slug) before exporting its presentation artwork.")
            }
            let source = try SourceIconLoader().load(for: app)
            let preview = try await AlgorithmicIconGenerator().generate(source: source, for: app, hueOverride: nil)
            try source.pngData.write(to: output.appendingPathComponent("\(slug)-original.png"))
            try preview.pngData.write(to: output.appendingPathComponent("\(slug)-preview.png"))
            print("Exported original artwork and local preview: \(app.name)")
        }
    }
}
