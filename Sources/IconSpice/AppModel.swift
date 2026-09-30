import AppKit
import IconSpiceCore
import Observation
import ServiceManagement

enum LibraryFilter: String, CaseIterable, Identifiable {
    case all = "All apps", changed = "Changed icons", attention = "Needs attention"
    var id: String { rawValue }
    var symbol: String {
        switch self { case .all: "square.grid.2x2"; case .changed: "sparkles"; case .attention: "exclamationmark.circle" }
    }
}

enum AIInputChoice: String, CaseIterable, Identifiable {
    case original = "Original icon", preview = "Current preview"
    var id: String { rawValue }
}

struct AppEntry: Identifiable {
    var id: String { app.id }
    let app: InstalledApp
    var source: SourceIcon?
    var currentPNG: Data?
    var preview: GeneratedIcon?
    var appliedPNG: Data?
    var record: IconRecord?
    var hueOverride: Double?
    var error: String?
    var isGenerating = false
}

struct OperationNotice: Identifiable {
    let id = UUID()
    let title: String
    let detail: String
    let isError: Bool
}

@MainActor @Observable
final class AppModel {
    static let shared = AppModel()
    var entries: [AppEntry] = []
    var selected: Set<String> = []
    var query = ""
    var filter = LibraryFilter.all
    var isBusy = false
    var progressText = "Scanning your apps…"
    var progress: Double = 0
    var notice: OperationNotice?
    var showingSettings = false
    var showingAIConsent = false
    var pendingAIApps: [InstalledApp] = []
    var aiInstructions = OpenAIIconGenerator.defaultCustomizationInstructions
    var aiInputChoice = AIInputChoice.original
    var hasLoaded = false
    var keyIsSaved = false
    var launchAtLogin = false
    var autoRestore: Bool {
        didSet {
            UserDefaults.standard.set(autoRestore, forKey: "autoRestore")
            if autoRestore { watcher?.start(); if hasLoaded { scheduleMaintenance() } } else { watcher?.stop() }
        }
    }

    private let workflow = IconWorkflow()
    private let applier = IconApplier()
    private let keychain = KeychainStore()
    private var watcher: ApplicationWatcher?
    private var operation: Task<Void, Never>?
    private var maintenancePending = false
    private var cancellationRequested = false
    private var isStarting = false
    private var undoApps: [InstalledApp] = []

    init() {
        autoRestore = UserDefaults.standard.object(forKey: "autoRestore") as? Bool ?? false
        launchAtLogin = SMAppService.mainApp.status == .enabled
        do { keyIsSaved = try keychain.hasAPIKey() } catch { keyIsSaved = false }
    }

    var visibleEntries: [AppEntry] {
        entries.filter { entry in
            let matches = query.isEmpty || entry.app.name.localizedCaseInsensitiveContains(query) || entry.app.bundleID.rawValue.localizedCaseInsensitiveContains(query)
            let included: Bool
            switch filter {
            case .all: included = true
            case .changed: included = entry.record != nil
            case .attention: included = entry.error != nil
            }
            return matches && included
        }
    }
    var trackedCount: Int { entries.filter { $0.record != nil }.count }
    var errorCount: Int { entries.filter { $0.error != nil }.count }
    var selectedEntries: [AppEntry] { entries.filter { selected.contains($0.id) } }
    var applicableCount: Int { selectedEntries.filter { $0.preview != nil && !$0.app.isProtected }.count }
    var canUndo: Bool { !undoApps.isEmpty && !isBusy }
    var generatedCount: Int { entries.filter { $0.preview != nil }.count }
    var canEditAIPreviews: Bool {
        !pendingAIApps.isEmpty && pendingAIApps.allSatisfy { app in entries.contains { $0.id == app.id && $0.preview != nil } }
    }

    func aiInputPNG(for app: InstalledApp) -> Data? {
        guard let entry = entries.first(where: { $0.id == app.id }) else { return nil }
        return aiInputChoice == .preview ? entry.preview?.pngData : entry.source?.pngData
    }

    func start() async {
        guard !hasLoaded && !isStarting else { return }
        isStarting = true
        defer { isStarting = false }
        watcher = ApplicationWatcher { [weak self] in self?.scheduleMaintenance() }
        if autoRestore { watcher?.start() }
        await scan()
        hasLoaded = true
        if autoRestore { scheduleMaintenance() }
    }

    func scan() async {
        guard !isBusy else { return }
        isBusy = true
        progressText = "Scanning your apps…"
        progress = 0
        defer { finishOperation() }
        do {
            let records = try await workflow.store.records()
            let apps = await Task.detached(priority: .userInitiated) { AppScanner().scan() }.value
            let oldEntries = Dictionary(uniqueKeysWithValues: entries.map { ($0.id, $0) })
            entries = apps.map { app in
                var entry = oldEntries[app.id] ?? AppEntry(app: app)
                // Use fresh metadata after updates.
                entry = AppEntry(app: app, source: entry.source, currentPNG: entry.currentPNG, preview: entry.preview,
                    record: records.first { $0.appURL.standardizedFileURL == app.url.standardizedFileURL },
                    hueOverride: entry.hueOverride, error: entry.error)
                if let record = entry.record { entry.hueOverride = record.hueOverride }
                return entry
            }
            selected.formIntersection(Set(entries.map(\.id)))
            for index in entries.indices {
                if Task.isCancelled || cancellationRequested { break }
                let app = entries[index].app
                entries[index].currentPNG = try? applier.currentIconPNG(for: app)
                do {
                    let source = try await workflow.source(for: app)
                    entries[index].source = source
                    if let record = entries[index].record {
                        let savedIcon = try await workflow.store.generated(for: record)
                        entries[index].appliedPNG = savedIcon.pngData
                        if let previous = oldEntries[app.id], let preview = previous.preview,
                           preview.pngData != previous.appliedPNG, preview.sourceHash == source.hash {
                            // Keep a user's unapplied preview through unrelated filesystem rescans.
                            entries[index].preview = preview
                            entries[index].hueOverride = previous.hueOverride
                        } else {
                            entries[index].preview = savedIcon
                            entries[index].source = try await workflow.store.source(for: record)
                        }
                    } else if entries[index].preview?.sourceHash != source.hash {
                        entries[index].preview = nil
                    }
                    if entries[index].record == nil { entries[index].appliedPNG = nil }
                } catch { entries[index].preview = nil; entries[index].error = error.localizedDescription }
                progress = Double(index + 1) / Double(max(entries.count, 1))
                if index % 5 == 0 { await Task.yield() }
            }
        } catch { report("Could not load your apps", error.localizedDescription, isError: true) }
    }

    func selectVisible() {
        let available = Set(visibleEntries.filter { !$0.app.isProtected }.map(\.id))
        if available.isSubset(of: selected) { selected.subtract(available) } else { selected.formUnion(available) }
    }

    func toggleSelection(_ id: String) {
        if selected.contains(id) { selected.remove(id) } else { selected.insert(id) }
    }

    func generatePreviews(ids: Set<String>? = nil) {
        let targets = entries.filter { (ids?.contains($0.id) ?? true) && !$0.app.isProtected }.map(\.id)
        guard !isBusy && !targets.isEmpty else { return }
        isBusy = true
        operation = Task { [weak self] in
            guard let self else { return }
            self.isBusy = true
            self.progress = 0
            defer { self.finishOperation() }
            var failed = 0
            for (offset, id) in targets.enumerated() {
                if Task.isCancelled || self.cancellationRequested { break }
                guard let index = self.entries.firstIndex(where: { $0.id == id }) else { continue }
                let app = self.entries[index].app
                self.progressText = "Generating \(app.name)…"
                self.entries[index].isGenerating = true
                self.entries[index].error = nil
                do {
                    let (source, preview) = try await self.workflow.generate(for: app, hueOverride: self.entries[index].hueOverride)
                    self.entries[index].source = source
                    self.entries[index].preview = preview
                } catch { self.entries[index].error = error.localizedDescription; failed += 1 }
                self.entries[index].isGenerating = false
                self.progress = Double(offset + 1) / Double(targets.count)
                await Task.yield()
            }
            if failed > 0 { self.report("Some previews need attention", "\(failed) icons could not be generated. See Needs attention for details.", isError: true) }
        }
    }

    func setHue(_ hue: Double?, for id: String) {
        guard let index = entries.firstIndex(where: { $0.id == id }), !isBusy else { return }
        entries[index].hueOverride = hue
        generatePreviews(ids: [id])
    }

    func applySelected() {
        let targets = selectedEntries.filter { $0.preview != nil && $0.source != nil && !$0.app.isProtected }
        guard !isBusy && !targets.isEmpty else { return }
        isBusy = true
        operation = Task { [weak self] in
            guard let self else { return }
            self.isBusy = true
            self.progress = 0
            defer { self.finishOperation() }
            var succeeded: [InstalledApp] = []
            var failed = 0
            for (offset, entry) in targets.enumerated() {
                if Task.isCancelled || self.cancellationRequested { break }
                self.progressText = "Applying \(entry.app.name)…"
                guard let icon = entry.preview, let source = entry.source else { continue }
                let result = await self.workflow.apply(icon, source: source, to: entry.app, hueOverride: entry.hueOverride)
                if let index = self.entries.firstIndex(where: { $0.id == entry.id }) {
                    if result.succeeded {
                        succeeded.append(entry.app)
                        self.entries[index].record = try? await self.workflow.store.record(for: entry.app)
                        self.entries[index].currentPNG = icon.pngData
                        self.entries[index].appliedPNG = icon.pngData
                        self.entries[index].error = nil
                    } else { self.entries[index].error = result.message; failed += 1 }
                }
                self.progress = Double(offset + 1) / Double(targets.count)
                await Task.yield()
            }
            self.undoApps = succeeded
            self.report("\(succeeded.count) icons applied", failed > 0 ? "\(failed) apps need attention. Your successful changes are saved." : "Your restore points are saved. You can revert any time.", isError: failed > 0)
        }
    }

    func revert(ids: Set<String>) {
        let targets = entries.filter { ids.contains($0.id) && $0.record != nil }.map(\.app)
        runRevert(targets)
    }

    func revertAll() {
        guard !isBusy else { return }
        isBusy = true
        // Include tracked apps outside the current scan (custom roots or old CLI records).
        operation = Task { [weak self] in
            guard let self else { return }
            do {
                let records = try await self.workflow.store.records()
                self.operation = nil
                self.isBusy = false
                self.runRevert(records.map { InstalledApp(bundleID: $0.bundleID, name: $0.appName, url: $0.appURL) })
            } catch { self.finishOperation(); self.report("Could not load restore points", error.localizedDescription, isError: true) }
        }
    }

    func undoLastApply() { runRevert(undoApps) }

    private func runRevert(_ apps: [InstalledApp]) {
        guard !isBusy && !apps.isEmpty else { return }
        isBusy = true
        operation = Task { [weak self] in
            guard let self else { return }
            self.isBusy = true
            self.progress = 0
            defer { self.finishOperation() }
            var succeeded = 0
            var errors: [String] = []
            for (offset, app) in apps.enumerated() {
                if Task.isCancelled || self.cancellationRequested { break }
                self.progressText = "Restoring \(app.name)…"
                let result = await self.workflow.revert(app)
                if result.succeeded { succeeded += 1 }
                else { errors.append("\(app.name): \(result.message)") }
                if let index = self.entries.firstIndex(where: { $0.id == app.id }) {
                    if result.succeeded {
                        self.entries[index].record = nil
                        self.entries[index].appliedPNG = nil
                        self.entries[index].currentPNG = try? self.applier.currentIconPNG(for: app)
                        self.entries[index].error = nil
                    } else { self.entries[index].error = result.message }
                }
                self.progress = Double(offset + 1) / Double(apps.count)
            }
            self.undoApps = []
            let stopped = Task.isCancelled || self.cancellationRequested
            self.report(stopped ? "Stopped after restoring \(succeeded) icons" : "\(succeeded) icons restored",
                errors.isEmpty ? (stopped ? "Remaining apps keep their restore points. You can continue whenever you’re ready." : "Your previous icons are back.") : errors.joined(separator: "\n"), isError: !errors.isEmpty)
        }
    }

    func requestAI(ids: Set<String>? = nil) {
        guard !isBusy else { return }
        pendingAIApps = entries.filter { (ids ?? selected).contains($0.id) && !$0.app.isProtected }.map(\.app)
        guard !pendingAIApps.isEmpty else { return }
        aiInputChoice = ids != nil && canEditAIPreviews ? .preview : .original
        if !keyIsSaved { showingSettings = true; report("Add your API key first", "Save your OpenAI API key in Settings, then choose Generate with AI.", isError: false) }
        else { showingAIConsent = true }
    }

    func generateWithAI() {
        let targets = pendingAIApps
        guard !isBusy && !targets.isEmpty else { return }
        let instructions = aiInstructions.trimmingCharacters(in: .whitespacesAndNewlines)
        guard instructions.count <= OpenAIIconGenerator.maxInstructionLength else {
            report("Shorten your instruction", "Use at most \(OpenAIIconGenerator.maxInstructionLength) characters for the requested changes.", isError: true)
            return
        }
        let inputChoice = aiInputChoice
        guard inputChoice != .preview || !instructions.isEmpty else {
            report("Describe your change", "Enter an instruction to refine the current preview.", isError: true)
            return
        }
        guard inputChoice != .preview || canEditAIPreviews else {
            report("The preview is no longer available", "Choose Original icon or generate a local preview first.", isError: true)
            return
        }
        let previewInputs = Dictionary(uniqueKeysWithValues: entries.compactMap { entry -> (String, GeneratedIcon)? in
            guard targets.contains(where: { $0.id == entry.id }), let preview = entry.preview else { return nil }
            return (entry.id, preview)
        })
        showingAIConsent = false
        isBusy = true
        operation = Task { [weak self] in
            guard let self else { return }
            self.isBusy = true
            self.progress = 0
            defer { self.finishOperation() }
            do {
                guard let key = try self.keychain.apiKey(), !key.isEmpty else { throw IconError.invalidArgument("Save an OpenAI API key in Settings first.") }
                let generator = OpenAIIconGenerator(apiKey: key, instructions: instructions,
                                                   preserveInputStyle: inputChoice == .preview)
                var fallbackCount = 0
                var completed = 0
                var failures: [String] = []
                for (offset, app) in targets.enumerated() {
                    if Task.isCancelled || self.cancellationRequested { break }
                    guard let index = self.entries.firstIndex(where: { $0.id == app.id }) else { continue }
                    self.progressText = "Generating \(app.name) with AI…"
                    self.entries[index].isGenerating = true
                    do {
                        let source = try await self.workflow.source(for: app)
                        let input: SourceIcon
                        let hue: Double?
                        if inputChoice == .preview, let previous = previewInputs[app.id] {
                            // The edit uses the current preview, while the restore store keeps original artwork.
                            input = SourceIcon(pngData: previous.pngData, hash: source.hash)
                            hue = self.entries[index].hueOverride ?? previous.hue
                        } else {
                            input = source
                            hue = self.entries[index].hueOverride
                        }
                        do {
                            let icon = try await generator.generate(source: input, for: app, hueOverride: hue)
                            try Task.checkCancellation()
                            self.entries[index].source = source
                            self.entries[index].preview = icon
                            self.entries[index].error = nil
                            completed += 1
                        } catch is CancellationError { break }
                        catch {
                            if inputChoice == .preview {
                                self.entries[index].error = "AI could not make your changes; your previous preview is kept. \(error.localizedDescription)"
                                failures.append("\(app.name): \(error.localizedDescription)")
                            } else {
                                try Task.checkCancellation()
                                let (fallbackSource, icon) = try await self.workflow.generate(for: app, hueOverride: self.entries[index].hueOverride)
                                try Task.checkCancellation()
                                self.entries[index].source = fallbackSource
                                self.entries[index].preview = icon
                                self.entries[index].error = "AI unavailable; a local preview was generated without your requested changes. \(error.localizedDescription)"
                                fallbackCount += 1
                                completed += 1
                            }
                        }
                    } catch is CancellationError { break }
                    catch {
                        self.entries[index].error = error.localizedDescription
                        failures.append("\(app.name): \(error.localizedDescription)")
                    }
                    self.entries[index].isGenerating = false
                    self.progress = Double(offset + 1) / Double(targets.count)
                    await Task.yield()
                }
                if Task.isCancelled || self.cancellationRequested {
                    self.report("AI generation stopped", "\(completed) of \(targets.count) apps finished. Completed previews are ready to review.", isError: false)
                } else {
                    var details: [String] = []
                    if fallbackCount > 0 { details.append("\(fallbackCount) apps used the local generator without your requested changes after an AI error.") }
                    details.append(contentsOf: failures)
                    self.report(completed == 0 ? "AI changes could not be generated" : "\(completed) previews ready",
                        details.isEmpty ? "Review your new icons, then apply the ones you like." : details.joined(separator: "\n"),
                        isError: fallbackCount > 0 || !failures.isEmpty)
                }
            } catch { self.report("AI generation could not start", error.localizedDescription, isError: true) }
        }
    }

    func saveKey(_ key: String) throws {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw IconError.invalidArgument("Enter an API key to save it.") }
        try keychain.saveAPIKey(trimmed)
        keyIsSaved = true
    }
    func deleteKey() throws { try keychain.deleteAPIKey(); keyIsSaved = false }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            launchAtLogin = SMAppService.mainApp.status == .enabled
            if enabled && !launchAtLogin { report("Allow launch at login", "Enable Icon Spice in System Settings → General → Login Items.", isError: false) }
        } catch { launchAtLogin = SMAppService.mainApp.status == .enabled; report("Could not change launch at login", error.localizedDescription, isError: true) }
    }

    func refreshDock() {
        do { try applier.refreshDock(); report("Dock refreshed", "Your Dock will reopen with the current icons.", isError: false) }
        catch { report("Could not refresh the Dock", error.localizedDescription, isError: true) }
    }

    func export(_ id: String) {
        guard let entry = entries.first(where: { $0.id == id }), let icon = entry.preview else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(entry.app.name)-spiced.png"
        panel.allowedContentTypes = [.png]
        panel.canCreateDirectories = true
        if panel.runModal() == .OK, let url = panel.url {
            do { try icon.pngData.write(to: url, options: .atomic) }
            catch { report("Could not export the icon", error.localizedDescription, isError: true) }
        }
    }

    func importIcon(_ id: String) {
        guard !isBusy, entries.contains(where: { $0.id == id }) else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .icns, .tiff]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard !isBusy, let index = entries.firstIndex(where: { $0.id == id }) else { return }
        do {
            let png = try IconImageCodec.normalizePNG(Data(contentsOf: url))
            guard let source = entries[index].source else { throw IconError.sourceUnavailable("Generate a preview to load the source icon first.") }
            entries[index].preview = GeneratedIcon(pngData: png, icnsData: try IconImageCodec.icnsData(fromPNG: png),
                hue: entries[index].preview?.hue ?? 0, sourceHash: source.hash, kind: .imported)
            entries[index].error = nil
        } catch { report("Could not import that icon", error.localizedDescription, isError: true) }
    }

    func cancel() { cancellationRequested = true; operation?.cancel() }

    private func scheduleMaintenance() {
        guard autoRestore else { return }
        if isBusy { maintenancePending = true; return }
        isBusy = true
        operation = Task { [weak self] in
            guard let self else { return }
            self.isBusy = true
            self.progressText = "Checking saved icons…"
            self.progress = 0
            let outcomes = await self.workflow.reapplyTracked()
            let changed = outcomes.filter { $0.result.succeeded && ($0.action == .reapplied || $0.action == .regenerated) }
            let failed = outcomes.filter { !$0.result.succeeded }
            if !failed.isEmpty {
                for outcome in failed {
                    if let index = self.entries.firstIndex(where: { $0.id == outcome.appURL.path }) { self.entries[index].error = outcome.result.message }
                }
                self.report("Some saved icons need attention", failed.map { "\($0.appName): \($0.result.message)" }.joined(separator: "\n"), isError: true)
            }
            self.finishOperation()
            // A scan also adds newly installed apps and updates current artwork.
            if !changed.isEmpty || outcomes.isEmpty || failed.isEmpty { await self.scan() }
        }
    }

    private func finishOperation() {
        isBusy = false
        cancellationRequested = false
        progressText = ""
        progress = 0
        for index in entries.indices { entries[index].isGenerating = false }
        operation = nil
        if maintenancePending { maintenancePending = false; scheduleMaintenance() }
    }

    private func report(_ title: String, _ detail: String, isError: Bool) {
        notice = OperationNotice(title: title, detail: detail, isError: isError)
    }
}
