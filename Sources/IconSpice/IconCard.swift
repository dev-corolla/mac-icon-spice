import AppKit
import IconSpiceCore
import SwiftUI

struct IconCard: View {
    let entry: AppEntry
    let selected: Bool
    let isBusy: Bool
    let select: () -> Void
    let generate: () -> Void
    let customizeAI: () -> Void
    let setHue: (Double?) -> Void
    let revert: () -> Void
    let export: () -> Void
    let importIcon: () -> Void
    @State private var showingColor = false
    @State private var hue = 0.0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Button(action: select) {
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 16)).foregroundStyle(selected ? SpiceStyle.accent : .secondary.opacity(0.4))
                }.buttonStyle(.plain).disabled(isBusy || entry.app.isProtected)
                    .accessibilityLabel("\(selected ? "Deselect" : "Select") \(entry.app.name)")
                Text(entry.app.name).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                    .help("\(entry.app.name)\n\(entry.app.bundleID.rawValue)\n\(entry.app.url.path)")
                Spacer(minLength: 2)
                Menu {
                    Button("Generate preview", action: generate).disabled(isBusy || entry.app.isProtected)
                    Button("Customize with AI…", action: customizeAI).disabled(isBusy || entry.app.isProtected)
                    Button("Choose a color…") { openColor() }.disabled(isBusy || entry.app.isProtected)
                    Button("Export preview as PNG…", action: export).disabled(entry.preview == nil)
                    Button("Import an icon…", action: importIcon).disabled(isBusy || entry.app.isProtected)
                    Button("Find an icon on macOSicons.com") {
                        let base = URL(string: "https://macosicons.com/#/")!
                        NSWorkspace.shared.open(base)
                    }
                    Divider()
                    Button("Restore original icon", action: revert).disabled(entry.record == nil || isBusy)
                    Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([entry.app.url]) }
                } label: { Image(systemName: "ellipsis").foregroundStyle(.secondary) }
                .menuStyle(.borderlessButton).frame(width: 18)
                    .accessibilityLabel("Actions for \(entry.app.name)")
            }.padding(.horizontal, 14).padding(.top, 14)

            HStack(spacing: 17) {
                VStack(spacing: 9) {
                    RasterIcon(data: entry.currentPNG ?? entry.source?.pngData, size: 64)
                    Text("CURRENT").font(.system(size: 8, weight: .semibold)).tracking(0.8).foregroundStyle(.tertiary)
                }
                Image(systemName: "arrow.right").font(.system(size: 11)).foregroundStyle(.quaternary)
                VStack(spacing: 9) {
                    if entry.isGenerating {
                        ProgressView().frame(width: 64, height: 64)
                    } else if let preview = entry.preview {
                        RasterIcon(data: preview.pngData, size: 64)
                    } else {
                        Button(action: generate) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 15, style: .continuous)
                                    .fill(SpiceStyle.accent.opacity(0.06))
                                RoundedRectangle(cornerRadius: 15, style: .continuous)
                                    .strokeBorder(SpiceStyle.accent.opacity(0.20), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                                Image(systemName: entry.app.isProtected ? "lock" : "sparkles")
                                    .font(.system(size: 22, weight: .light)).foregroundStyle(SpiceStyle.accent.opacity(0.7))
                            }.frame(width: 64, height: 64)
                        }.buttonStyle(.plain).disabled(isBusy || entry.app.isProtected)
                            .accessibilityLabel("Generate preview for \(entry.app.name)")
                    }
                    Text(entry.preview?.kind == .ai ? "AI PREVIEW" : "SPICED")
                        .font(.system(size: 8, weight: .semibold)).tracking(0.8).foregroundStyle(.tertiary)
                }
            }.frame(maxWidth: .infinity).padding(.top, 21).padding(.bottom, 19)
            Divider().padding(.horizontal, 14)
            HStack(spacing: 6) {
                if entry.app.isProtected {
                    Label("Protected by macOS", systemImage: "lock.fill").foregroundStyle(.secondary)
                } else if let error = entry.error {
                    Label("Needs attention", systemImage: "exclamationmark.circle.fill").foregroundStyle(.orange).help(error)
                } else if entry.record != nil, let preview = entry.preview, entry.appliedPNG != preview.pngData {
                    Text("New preview").foregroundStyle(.secondary)
                } else if entry.record != nil {
                    Label("Applied", systemImage: "checkmark.circle.fill").foregroundStyle(SpiceStyle.accent)
                } else if entry.preview != nil {
                    Text("Ready to apply").foregroundStyle(.secondary)
                } else {
                    Text("Original icon").foregroundStyle(.secondary)
                }
                Spacer(minLength: 4)
                if let preview = entry.preview {
                    Button { openColor() } label: {
                        HStack(spacing: 4) {
                            Circle().fill(Color(hue: preview.hue, saturation: 0.78, brightness: 0.9)).frame(width: 10, height: 10)
                            Text("Color").foregroundStyle(.secondary)
                        }
                    }.buttonStyle(.plain).disabled(isBusy).accessibilityLabel("Change color for \(entry.app.name)")
                }
            }.font(.system(size: 10)).padding(.horizontal, 14).padding(.vertical, 12)
            if let error = entry.error {
                Text(error).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(3)
                    .textSelection(.enabled).padding(.horizontal, 14).padding(.bottom, 12)
            }
        }
        .background(SpiceStyle.card, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(selected ? SpiceStyle.accent.opacity(0.65) : .primary.opacity(0.07), lineWidth: selected ? 1.5 : 1))
        .popover(isPresented: $showingColor) {
            VStack(alignment: .leading, spacing: 16) {
                Text("A color for \(entry.app.name)").font(.system(size: 14, weight: .semibold))
                HStack {
                    ForEach(Array([0.01, 0.08, 0.16, 0.37, 0.53, 0.64, 0.77, 0.92].enumerated()), id: \.offset) { _, value in
                        Button { hue = value } label: {
                            Circle().fill(Color(hue: value, saturation: 0.8, brightness: 0.87)).frame(width: 23, height: 23)
                                .overlay(Circle().strokeBorder(.white, lineWidth: abs(value - hue) < 0.015 ? 3 : 0))
                        }.buttonStyle(.plain).accessibilityLabel("Hue \(Int(value * 360)) degrees")
                    }
                }
                Slider(value: $hue, in: 0...1) { Text("Hue") }
                HStack {
                    Circle().fill(Color(hue: hue, saturation: 0.8, brightness: 0.9)).frame(width: 18, height: 18)
                    Text("\(Int(hue * 360))°").font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
                    Spacer()
                    Button("Automatic") { showingColor = false; setHue(nil) }.buttonStyle(.borderless)
                    Button("Preview") { showingColor = false; setHue(hue) }.buttonStyle(.borderedProminent)
                }
                Text("Changing color generates a local preview. Apply it when you’re ready.")
                    .font(.system(size: 10)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }.padding(20).frame(width: 280).tint(SpiceStyle.accent)
        }
    }
    private func openColor() { hue = entry.hueOverride ?? entry.preview?.hue ?? 0.7; showingColor = true }
}

struct RasterIcon: View {
    let data: Data?
    let size: CGFloat
    var body: some View {
        Group {
            if let data, let image = NSImage(data: data) {
                Image(nsImage: image).resizable().interpolation(.high).aspectRatio(contentMode: .fit)
            } else {
                Image(systemName: "app.dashed").resizable().scaledToFit().foregroundStyle(.tertiary).padding(8)
            }
        }.frame(width: size, height: size)
    }
}
