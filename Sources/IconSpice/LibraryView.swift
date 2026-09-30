import AppKit
import IconSpiceCore
import SwiftUI

enum SpiceStyle {
    static let accent = Color(red: 0.43, green: 0.32, blue: 0.77)
    static let canvas = Color(nsColor: .controlBackgroundColor)
    static let card = Color(nsColor: .windowBackgroundColor)
}

struct LibraryView: View {
    @Bindable var model: AppModel
    @State private var confirmRevertAll = false
    @AppStorage("hasDismissedPermissionGuide") private var hasDismissedPermissionGuide = false

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            VStack(spacing: 0) {
                header
                Divider()
                if let notice = model.notice { noticeView(notice) }
                if !hasDismissedPermissionGuide && model.notice == nil { permissionGuide }
                content
                Divider()
                selectionBar
            }
        }
        .frame(minWidth: 840, minHeight: 560)
        .tint(SpiceStyle.accent)
        .background(SpiceStyle.canvas)
        .sheet(isPresented: $model.showingSettings) { SettingsView(model: model) }
        .sheet(isPresented: $model.showingAIConsent) { AIConsentView(model: model) }
        .confirmationDialog("Restore every changed icon?", isPresented: $confirmRevertAll, titleVisibility: .visible) {
            Button("Restore all icons", role: .destructive) { model.revertAll() }
            Button("Cancel", role: .cancel) { }
        } message: { Text("Icon Spice will restore the icons each app had before its first change. Apps that cannot be restored will keep their restore points.") }
        .onExitCommand { model.cancel() }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 9) {
                Image(systemName: "paintpalette.fill")
                    .font(.system(size: 23)).foregroundStyle(SpiceStyle.accent)
                Text("Icon Spice").font(.system(size: 19, weight: .bold, design: .rounded))
            }
            .padding(.top, 28).padding(.bottom, 34).padding(.horizontal, 20)

            Text("LIBRARY").font(.system(size: 10, weight: .semibold)).tracking(1.1)
                .foregroundStyle(.secondary).padding(.horizontal, 22).padding(.bottom, 9)
            ForEach(LibraryFilter.allCases) { filter in
                Button { model.filter = filter } label: {
                    HStack(spacing: 10) {
                        Image(systemName: filter.symbol).frame(width: 17)
                        Text(filter.rawValue).font(.system(size: 12, weight: model.filter == filter ? .semibold : .regular)).lineLimit(1)
                        Spacer(minLength: 2)
                        Text(count(for: filter).formatted()).font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    .foregroundStyle(model.filter == filter ? SpiceStyle.accent : .primary)
                    .padding(.horizontal, 12).padding(.vertical, 11)
                    .background(model.filter == filter ? SpiceStyle.accent.opacity(0.10) : .clear, in: RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain).padding(.horizontal, 10).padding(.bottom, 3)
            }
            Spacer()
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Circle().fill(model.autoRestore ? .green : .secondary.opacity(0.5)).frame(width: 6, height: 6)
                    Text(model.autoRestore ? "Keeping your color" : "Auto-restore is off")
                        .font(.system(size: 11, weight: .medium))
                }
                Text(model.autoRestore ? "Saved icons are restored when your apps update." : "Turn it on in Settings to keep your icons after updates.")
                    .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            .padding(16).background(SpiceStyle.accent.opacity(0.045), in: RoundedRectangle(cornerRadius: 10))
            .padding(12)
            Divider().padding(.horizontal, 18)
            Button { model.showingSettings = true } label: {
                Label("Settings", systemImage: "gearshape").font(.system(size: 12)).frame(maxWidth: .infinity, alignment: .leading)
                    .padding(20)
            }.buttonStyle(.plain)
            Button { NSApp.terminate(nil) } label: {
                Label("Quit Icon Spice", systemImage: "power").font(.system(size: 12))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20).padding(.bottom, 20)
            }.buttonStyle(.plain).keyboardShortcut("q")
        }
        .frame(width: 206)
        .background(SpiceStyle.card)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(title).font(.system(size: 28, weight: .bold, design: .rounded)).tracking(-0.7)
                    Text(subtitle).font(.system(size: 12)).foregroundStyle(.secondary)
                }
                Spacer()
                Button { Task { await model.scan() } } label: { Image(systemName: "arrow.clockwise").font(.system(size: 13, weight: .medium)) }
                    .buttonStyle(.borderless).padding(.top, 7).disabled(model.isBusy)
                    .help("Rescan installed apps")
                    .accessibilityLabel("Rescan installed apps")
            }
            HStack(spacing: 12) {
                HStack(spacing: 7) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Search apps", text: $model.query).textFieldStyle(.plain)
                        .accessibilityLabel("Search apps")
                    if !model.query.isEmpty {
                        Button { model.query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                            .buttonStyle(.plain).accessibilityLabel("Clear search")
                    }
                }.padding(.horizontal, 11).padding(.vertical, 9)
                    .background(SpiceStyle.canvas, in: RoundedRectangle(cornerRadius: 7))
                    .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(.primary.opacity(0.08)))
                    .frame(maxWidth: 330)
                Spacer()
                Text("\(model.visibleEntries.count) apps").font(.system(size: 11)).foregroundStyle(.secondary)
                Button { model.generatePreviews(ids: Set(model.visibleEntries.map(\.id))) } label: {
                    Label("Generate previews", systemImage: "sparkles")
                }.buttonStyle(.bordered).controlSize(.regular).disabled(model.isBusy || model.visibleEntries.isEmpty)
            }
        }.padding(.horizontal, 28).padding(.top, 25).padding(.bottom, 22)
            .background(SpiceStyle.card)
    }

    @ViewBuilder private var content: some View {
        if model.entries.isEmpty && model.isBusy {
            VStack(spacing: 14) { ProgressView(); Text("Finding your apps…").font(.system(size: 13)).foregroundStyle(.secondary) }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if model.visibleEntries.isEmpty {
            ContentUnavailableView(emptyTitle, systemImage: model.query.isEmpty ? model.filter.symbol : "magnifyingglass",
                description: Text(emptyDescription))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 225, maximum: 320), spacing: 16)], spacing: 16) {
                    ForEach(model.visibleEntries) { entry in
                        IconCard(entry: entry, selected: model.selected.contains(entry.id), isBusy: model.isBusy,
                            select: { model.toggleSelection(entry.id) }, generate: { model.generatePreviews(ids: [entry.id]) },
                            customizeAI: { model.requestAI(ids: [entry.id]) },
                            setHue: { model.setHue($0, for: entry.id) }, revert: { model.revert(ids: [entry.id]) },
                            export: { model.export(entry.id) }, importIcon: { model.importIcon(entry.id) })
                    }
                }.padding(24)
            }
        }
    }

    private var selectionBar: some View {
        VStack(spacing: 0) {
            if model.isBusy {
                HStack(spacing: 10) {
                    ProgressView(value: model.progress).frame(width: 90)
                    Text(model.progressText).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                    Spacer()
                    Button("Stop after this app") { model.cancel() }.font(.system(size: 11)).buttonStyle(.borderless)
                }.padding(.horizontal, 24).padding(.top, 12)
            }
            HStack(spacing: 12) {
                Button(model.selected.isEmpty ? "Select all" : "Toggle all") { model.selectVisible() }
                    .buttonStyle(.borderless).disabled(model.isBusy)
                Text(model.selected.isEmpty ? "Preview first. Apply when you like it." : "\(model.selected.count) selected")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                Spacer(minLength: 8)
                Menu {
                    Button("Generate selected previews") { model.generatePreviews(ids: model.selected) }
                        .disabled(model.selected.isEmpty || model.isBusy)
                    Button("Generate selected with AI…") { model.requestAI() }
                        .disabled(model.selected.isEmpty || model.isBusy)
                    Divider()
                    Button("Restore selected icons") { model.revert(ids: model.selected) }
                        .disabled(!model.selectedEntries.contains { $0.record != nil } || model.isBusy)
                    Button("Restore all changed icons…", role: .destructive) { confirmRevertAll = true }
                        .disabled(model.trackedCount == 0 || model.isBusy)
                    Button("Refresh Dock") { model.refreshDock() }.disabled(model.isBusy)
                } label: { Image(systemName: "ellipsis").frame(width: 16) }
                .menuStyle(.borderlessButton).frame(width: 32).accessibilityLabel("More icon actions")
                Button("Apply selected\(model.applicableCount > 0 ? " (\(model.applicableCount))" : "")") { model.applySelected() }
                    .buttonStyle(.borderedProminent).controlSize(.large)
                    .disabled(model.applicableCount == 0 || model.isBusy)
            }.padding(.horizontal, 24).padding(.vertical, 16)
        }.background(SpiceStyle.card)
    }

    private func noticeView(_ notice: OperationNotice) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: notice.isError ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
                .foregroundStyle(notice.isError ? .orange : SpiceStyle.accent)
            VStack(alignment: .leading, spacing: 3) {
                Text(notice.title).font(.system(size: 12, weight: .semibold))
                Text(notice.detail).font(.system(size: 11)).foregroundStyle(.secondary)
                    .lineLimit(4).textSelection(.enabled)
            }
            Spacer()
            if notice.isError {
                Button("Permissions") { model.showingSettings = true }.buttonStyle(.borderless).font(.system(size: 11))
            }
            Button { model.notice = nil } label: { Image(systemName: "xmark").font(.system(size: 10, weight: .medium)) }
                .buttonStyle(.plain).foregroundStyle(.secondary).accessibilityLabel("Dismiss message")
        }.padding(14).background(notice.isError ? Color.orange.opacity(0.07) : SpiceStyle.accent.opacity(0.06))
    }

    private var permissionGuide: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "hand.raised").foregroundStyle(SpiceStyle.accent)
            VStack(alignment: .leading, spacing: 3) {
                Text("A quick note before you start").font(.system(size: 12, weight: .semibold))
                Text("Generate previews freely. Applying may ask for App Management access; system apps are protected.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Permission guide") { model.showingSettings = true }.buttonStyle(.borderless).font(.system(size: 11))
            Button { hasDismissedPermissionGuide = true } label: { Image(systemName: "xmark").font(.system(size: 10)) }
                .buttonStyle(.plain).foregroundStyle(.secondary).accessibilityLabel("Dismiss permission guide")
        }.padding(14).background(SpiceStyle.accent.opacity(0.05))
    }

    private func count(for filter: LibraryFilter) -> Int {
        switch filter { case .all: model.entries.count; case .changed: model.trackedCount; case .attention: model.errorCount }
    }
    private var title: String {
        switch model.filter { case .all: "Your apps, in full color."; case .changed: "A little spice, saved."; case .attention: "Let’s fix these icons." }
    }
    private var subtitle: String {
        switch model.filter {
        case .all: "One consistent shape. A color for every app. Always reversible."
        case .changed: "Your changed icons and their original restore points."
        case .attention: "Review the message on each app and try again."
        }
    }
    private var emptyTitle: String {
        if !model.query.isEmpty { return "No apps match “\(model.query)”" }
        switch model.filter { case .all: return "No apps found"; case .changed: return "Your originals are still intact"; case .attention: return "Everything looks good" }
    }
    private var emptyDescription: String {
        if !model.query.isEmpty { return "Try an app name or bundle ID." }
        switch model.filter {
        case .all: return "Install an app in Applications, then rescan."
        case .changed: return "Generate previews in All apps, then apply your favorites."
        case .attention: return "Apps with permission or generation errors will appear here."
        }
    }
}
