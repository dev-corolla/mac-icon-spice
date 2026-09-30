import AppKit
import IconSpiceCore
import SwiftUI

struct SettingsView: View {
    @Bindable var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var apiKey = ""
    @State private var keyMessage: String?
    @State private var keyError = false
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Make yourself at home.").font(.system(size: 23, weight: .bold, design: .rounded))
                Spacer()
                Button("Done") { apiKey = ""; dismiss() }.keyboardShortcut(.defaultAction)
            }.padding(24)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Keep your color").font(.system(size: 14, weight: .semibold))
                        Toggle("Restore saved icons after app updates", isOn: $model.autoRestore)
                        Text("Icon Spice watches Applications while it’s running. It reuses saved icons and only regenerates local icons when the original artwork changes.")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                        Toggle("Launch Icon Spice at login", isOn: Binding(get: { model.launchAtLogin }, set: { enabled in model.setLaunchAtLogin(enabled) }))
                    }
                    Divider()
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Permission to change app icons", systemImage: "hand.raised").font(.system(size: 14, weight: .semibold))
                        Text("If macOS asks, allow Icon Spice to manage apps. If applying an icon fails, open App Management and enable Icon Spice, then try again.")
                            .font(.system(size: 12)).foregroundStyle(.secondary)
                        HStack {
                            Button("Open App Management") { openSettings("Privacy_AppBundles") }
                            Button("Open Full Disk Access") { openSettings("Privacy_AllFiles") }
                        }
                        Text("Full Disk Access may be needed for apps in restricted locations. System apps are protected and skipped. You don’t need to turn off SIP.")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                        Text("If the Dock shows a tinted or clear style, use Default in macOS appearance settings to see custom colors. Refresh the Dock from Icon Spice’s menu if it shows old icons.")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    Divider()
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Optional AI generation").font(.system(size: 14, weight: .semibold))
                            Spacer()
                            if model.keyIsSaved { Label("Key saved", systemImage: "checkmark.shield.fill").font(.system(size: 10)).foregroundStyle(SpiceStyle.accent) }
                        }
                        Text("Use your own OpenAI API key. Your instruction and chosen icons are sent only when you choose Generate with AI. Your provider may charge for each new image.")
                            .font(.system(size: 12)).foregroundStyle(.secondary)
                        SecureField(model.keyIsSaved ? "Paste a new key to replace the saved one" : "OpenAI API key", text: $apiKey).textFieldStyle(.roundedBorder)
                            .onSubmit { saveKey() }
                        HStack {
                            Button("Save in Keychain") { saveKey() }.disabled(apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            if model.keyIsSaved {
                                Button("Remove saved key", role: .destructive) {
                                    do { try model.deleteKey(); keyMessage = "API key removed from Keychain."; keyError = false }
                                    catch { keyMessage = error.localizedDescription; keyError = true }
                                }
                            }
                        }
                        if let keyMessage { Text(keyMessage).font(.system(size: 11)).foregroundStyle(keyError ? .orange : SpiceStyle.accent) }
                        Text("Keys stay in macOS Keychain. Generated images are cached locally. Automatic restore never calls the AI provider.")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                        Link("Get an OpenAI API key", destination: URL(string: "https://platform.openai.com/api-keys")!).font(.system(size: 11))
                    }
                    Divider()
                    HStack {
                        Text("Icon Spice · 0.1.0").font(.system(size: 11, weight: .medium))
                        Spacer()
                        Text("Made for a more colorful Mac.").font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                }.padding(24)
            }
        }.frame(width: 560, height: 650).tint(SpiceStyle.accent)
    }
    private func saveKey() {
        do { try model.saveKey(apiKey); apiKey = ""; keyMessage = "API key saved in Keychain."; keyError = false }
        catch { keyMessage = error.localizedDescription; keyError = true }
    }
    private func openSettings(_ pane: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") { NSWorkspace.shared.open(url) }
    }
}

struct AIConsentView: View {
    @Bindable var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @FocusState private var instructionFocused: Bool

    private var instructionCount: Int { model.aiInstructions.trimmingCharacters(in: .whitespacesAndNewlines).count }
    private var instructionTooLong: Bool { instructionCount > OpenAIIconGenerator.maxInstructionLength }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("Make it your own.").font(.system(size: 24, weight: .bold, design: .rounded))
                Spacer()
                Label("OpenAI", systemImage: "sparkles").font(.system(size: 11, weight: .medium)).foregroundStyle(SpiceStyle.accent)
            }
            Text("Describe the changes you want. The same instruction applies to every app below.")
                .font(.system(size: 12)).foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 9) {
                HStack {
                    Text("What would you like to change?").font(.system(size: 12, weight: .semibold))
                    Spacer()
                    Text(model.aiInputChoice == .preview ? "Required" : "Optional").font(.system(size: 10)).foregroundStyle(.secondary)
                }
                ZStack(alignment: .topLeading) {
                    TextEditor(text: $model.aiInstructions)
                        .font(.system(size: 13)).scrollContentBackground(.hidden)
                        .focused($instructionFocused).padding(7)
                        .accessibilityLabel("Requested icon changes")
                    if model.aiInstructions.isEmpty {
                        Text("Use a teal background and a brighter white glyph. Keep the logo’s shape.")
                            .font(.system(size: 13)).foregroundStyle(.tertiary)
                            .padding(.horizontal, 12).padding(.vertical, 15).allowsHitTesting(false)
                    }
                }
                .frame(height: 160)
                .background(SpiceStyle.canvas, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(instructionTooLong ? Color.orange : .primary.opacity(0.10)))
                HStack {
                    Text(instructionTooLong ? "Shorten your instruction before generating." : "Be specific about what to change and what to keep.")
                        .foregroundStyle(instructionTooLong ? .orange : .secondary)
                    Spacer()
                    Text("\(instructionCount)/\(OpenAIIconGenerator.maxInstructionLength)")
                        .font(.system(size: 10, design: .monospaced)).foregroundStyle(instructionTooLong ? .orange : .secondary)
                }.font(.system(size: 10))
                HStack(spacing: 8) {
                    Button("Default style") { model.aiInstructions = OpenAIIconGenerator.defaultCustomizationInstructions }
                    Button("Softer glow") { model.aiInstructions = "Make the glow softer and more subtle. Keep the logo, background color, and proportions the same." }
                    Button("Teal background") { model.aiInstructions = "Use a deep teal background. Keep the logo’s shape and original colors." }
                    Button("Brighter glyph") { model.aiInstructions = "Make the glyph brighter and easier to see. Keep its shape and the background unchanged." }
                }.buttonStyle(.bordered).controlSize(.small)
            }

            VStack(alignment: .leading, spacing: 8) {
                Picker("Start from", selection: $model.aiInputChoice) {
                    Text("Original icon").tag(AIInputChoice.original)
                    Text("Current preview").tag(AIInputChoice.preview).disabled(!model.canEditAIPreviews)
                }.pickerStyle(.segmented)
                Text(model.aiInputChoice == .preview ? "Refine the previews shown below with your requested changes." : "Create a new icon from each app’s original artwork. Without an instruction, the shared Icon Spice style is used.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(model.pendingAIApps) { app in
                        HStack {
                            RasterIcon(data: model.aiInputPNG(for: app), size: 32)
                            Text(app.name).font(.system(size: 12, weight: .medium))
                            Spacer()
                            Text(app.bundleID.rawValue).font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                }.padding(14)
            }.frame(height: min(CGFloat(model.pendingAIApps.count) * 42 + 28, 140))
                .background(SpiceStyle.canvas, in: RoundedRectangle(cornerRadius: 8))
            Text("Your instruction and these icons will be sent to OpenAI. Cached results are reused; new images may incur API charges. Results are previews until you apply them.")
                .font(.system(size: 11)).foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                Button("Generate AI previews") { model.generateWithAI() }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                    .disabled(instructionTooLong || model.isBusy || model.pendingAIApps.isEmpty || (model.aiInputChoice == .preview && (!model.canEditAIPreviews || instructionCount == 0)))
            }
        }.padding(26).frame(width: 560).tint(SpiceStyle.accent)
            .onAppear { instructionFocused = true }
    }
}
