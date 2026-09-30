import Foundation

public enum ReapplyAction: String, Codable, Sendable { case unchanged, reapplied, regenerated, missing }

public struct ReapplyOutcome: Sendable {
    public let appURL: URL
    public let bundleID: BundleID
    public let appName: String
    public let result: ApplyResult
    public let action: ReapplyAction
}

/// Shared orchestration for the app and CLI. Persistent state is committed only after a successful change.
@MainActor
public final class IconWorkflow {
    public let store: IconStore
    private let loader = SourceIconLoader()
    private let applier = IconApplier()
    private let generator = AlgorithmicIconGenerator()

    public init(store: IconStore = IconStore()) { self.store = store }

    public func source(for app: InstalledApp) async throws -> SourceIcon {
        let record = try await store.record(for: app)
        if let record, record.bundleID != app.bundleID {
            throw IconError.fileOperation("This path has a restore point for another app (\(record.bundleID)). The restore point has been kept. Move the new app to a different path before changing its icon.")
        }
        do {
            return try loader.load(for: app, allowWorkspaceFallback: record == nil || !applier.hasCustomIcon(at: app.url))
        } catch IconError.sourceUnavailable {
            guard let record else { throw IconError.sourceUnavailable("No original icon is available for \(app.name).") }
            return try await store.source(for: record)
        }
    }

    public func generate(for app: InstalledApp, hueOverride: Double? = nil) async throws -> (SourceIcon, GeneratedIcon) {
        let source = try await source(for: app)
        return (source, try await generator.generate(source: source, for: app, hueOverride: hueOverride))
    }

    public func apply(_ icon: GeneratedIcon, source: SourceIcon, to app: InstalledApp, hueOverride: Double? = nil) async -> ApplyResult {
        await applyChecked(icon, source: source, to: app, hueOverride: hueOverride, expectedRecord: nil).result
    }

    private func applyChecked(_ icon: GeneratedIcon, source: SourceIcon, to app: InstalledApp,
                              hueOverride: Double?, expectedRecord: IconRecord?) async -> (result: ApplyResult, didApply: Bool) {
        if app.isProtected { return (.protectedApp, false) }
        do {
            let lease = try await store.acquireMutationLock()
            defer { lease.release() }
            // A concurrent CLI revert must not be undone by an old watcher snapshot.
            if let expectedRecord, try await store.record(for: app) != expectedRecord { return (.success, false) }
            if let existing = try await store.record(for: app), existing.bundleID != app.bundleID {
                return (.failed("This path has a restore point for another app. It has been kept, and this app was left unchanged."), false)
            }
            guard let currentApp = AppScanner().readApp(at: app.url), currentApp.bundleID == app.bundleID else {
                return (.failed("This app was removed or replaced since the preview. Rescan before applying."), false)
            }
            if currentApp.isProtected { return (.protectedApp, false) }
            let previous = applier.hasCustomIcon(at: app.url) ? try applier.currentIconPNG(for: app) : nil
            let record = try await store.prepare(icon: icon, source: source, app: app, hueOverride: hueOverride, originalCustomIcon: previous)
            let result = applier.apply(icon, to: app)
            guard result.succeeded else {
                // A refused Cocoa call may have partially changed file metadata.
                let rollback = restore(app, png: previous)
                if rollback.succeeded {
                    try? await store.discardPrepared(record)
                    return (result, false)
                }
                return (.failed("\(result.message) The previous icon could not be restored automatically. Its saved artwork remains at \(record.originalCustomIconURL?.path ?? record.sourceIconURL.path)."), false)
            }
            do {
                try await store.commit(record)
                return (.success, true)
            } catch {
                let rollback = restore(app, png: previous)
                if rollback.succeeded { try? await store.discardPrepared(record) }
                return (.failed("The icon changed, but its restore record could not be saved: \(error.localizedDescription). \(rollback.succeeded ? "The previous icon was restored." : "The backup remains at \(record.originalCustomIconURL?.path ?? record.sourceIconURL.path).")"), false)
            }
        } catch { return (.failed(error.localizedDescription), false) }
    }

    public func revert(_ app: InstalledApp) async -> ApplyResult {
        do {
            let lease = try await store.acquireMutationLock()
            defer { lease.release() }
            guard let record = try await store.record(for: app) else {
                return .failed("This app has no Icon Spice restore record.")
            }
            guard record.bundleID == app.bundleID,
                  let currentApp = AppScanner().readApp(at: app.url), currentApp.bundleID == record.bundleID else {
                return .failed("The app at this path has changed identity. Its restore point has been kept, and the app was left unchanged.")
            }
            let previous = applier.hasCustomIcon(at: app.url) ? try applier.currentIconPNG(for: app) : nil
            let result = applier.revert(app, originalCustomIconURL: record.originalCustomIconURL)
            guard result.succeeded else { return result }
            do {
                try await store.remove(record: record)
                return .success
            } catch {
                let rollback = restore(app, png: previous)
                return .failed("The restore record could not be removed: \(error.localizedDescription). \(rollback.succeeded ? "The change was rolled back." : "The watcher should be turned off until the record can be removed.")")
            }
        } catch { return .failed(error.localizedDescription) }
    }

    /// No network calls: AI icons reuse their saved result until the user explicitly generates again.
    public func reapplyTracked() async -> [ReapplyOutcome] {
        var outcomes: [ReapplyOutcome] = []
        do {
            let records = try await store.records()
            for record in records {
                if Task.isCancelled { break }
                guard FileManager.default.fileExists(atPath: record.appURL.path) else {
                    outcomes.append(outcome(record, .success, .missing))
                    continue
                }
                guard let app = AppScanner().readApp(at: record.appURL), app.bundleID == record.bundleID else {
                    outcomes.append(outcome(record, .failed("The app at this path has a different identity. It was left unchanged."), .unchanged))
                    continue
                }
                do {
                    let source = try await source(for: app)
                    if source.hash != record.sourceHash && record.generator == .algorithmic {
                        let icon = try await generator.generate(source: source, for: app, hueOverride: record.hueOverride)
                        let change = await applyChecked(icon, source: source, to: app, hueOverride: record.hueOverride, expectedRecord: record)
                        outcomes.append(outcome(record, change.result, change.didApply ? .regenerated : .unchanged))
                    } else if !applier.hasCustomIcon(at: app.url) {
                        let icon = try await store.generated(for: record)
                        // Keep the original source and hash for AI/manual icons so an explicit preview sees changed artwork.
                        let savedSource = try await store.source(for: record)
                        let change = await applyChecked(icon, source: savedSource, to: app, hueOverride: record.hueOverride, expectedRecord: record)
                        outcomes.append(outcome(record, change.result, change.didApply ? .reapplied : .unchanged))
                    } else {
                        outcomes.append(outcome(record, .success, .unchanged))
                    }
                } catch { outcomes.append(outcome(record, .failed(error.localizedDescription), .unchanged)) }
                await Task.yield()
            }
        } catch {
            outcomes.append(ReapplyOutcome(appURL: URL(fileURLWithPath: "/"), bundleID: BundleID(""),
                appName: "Saved icons", result: .failed(error.localizedDescription), action: .unchanged))
        }
        return outcomes
    }

    private func restore(_ app: InstalledApp, png: Data?) -> ApplyResult {
        guard let png else { return applier.revert(app) }
        return applier.apply(GeneratedIcon(pngData: png, icnsData: Data(), hue: 0, sourceHash: "rollback"), to: app)
    }

    private func outcome(_ record: IconRecord, _ result: ApplyResult, _ action: ReapplyAction) -> ReapplyOutcome {
        ReapplyOutcome(appURL: record.appURL, bundleID: record.bundleID, appName: record.appName, result: result, action: action)
    }
}
