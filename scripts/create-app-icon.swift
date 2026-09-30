import AppKit

@main
struct CreateAppIcon {
    @MainActor static func main() throws {
        let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        for (points, scale) in [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2)] {
            let name = "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"
            try PepperArtwork.pngData(pixels: points * scale).write(to: output.appendingPathComponent(name))
        }
    }
}
