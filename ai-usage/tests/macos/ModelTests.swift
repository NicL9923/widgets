import Foundation

/// Reader calls run on a background queue; record them behind a lock.
final class Recorder<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [Value] = []

    /// Appends and returns the new count.
    func append(_ value: Value) -> Int {
        lock.lock(); defer { lock.unlock() }
        values.append(value)
        return values.count
    }

    var all: [Value] { lock.lock(); defer { lock.unlock() }; return values }
}

@main
struct ModelTests {
    @MainActor static func main() throws {
        let name = "ai-usage-model-test-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let gate = DispatchSemaphore(value: 0)
        let calls = Recorder<([String], Bool)>()
        let report = try UsageReport.decode(Data("{\"version\":1,\"providers\":[]}".utf8))
        let model = UsageModel(startPolling: false, defaults: defaults) { _, ids, force in
            if calls.append((ids, force)) == 1 { _ = gate.wait(timeout: .now() + 3) }
            return report
        }
        let supported = ["codex", "claude", "grok"]
        precondition(model.menuEntries(at: Date()).map(\.id) == supported,
                     "Show live providers by default and leave the placeholder off")
        model.refresh()
        model.refresh(force: true)
        model.refresh(force: true)
        model.setMenuBarVisibility(false, for: "claude")
        gate.signal()
        let deadline = Date().addingTimeInterval(5)
        while model.busy && Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.01))
        }
        precondition(!model.busy, "Refreshes did not complete")
        let captured = calls.all
        precondition(captured.count == 2, "Coalesce repeated forced refreshes into one follow-up")
        precondition(!captured[0].1 && captured[1].1, "Retain the forced refresh while busy")
        precondition(captured.allSatisfy { $0.0 == supported },
                     "Keep polling hidden providers and exclude Antigravity from helper requests")
        let entries = model.menuEntries(at: Date())
        precondition(entries.map(\.id) == ["codex", "grok"] && entries.allSatisfy { $0.percentText == "–" },
                     "Keep unavailable providers in place without a number")
        precondition(model.accessibilitySummary(at: Date()).contains("Codex unavailable"))
        for provider in UsageProvider.all {
            precondition(ProviderMark.image(provider.id) != nil, "Bundle a mark for \(provider.id)")
        }
        model.setMenuBarVisibility(false, for: "codex")
        model.setMenuBarVisibility(false, for: "grok")
        precondition(!model.busy && model.menuEntries(at: Date()).isEmpty,
                     "Hiding all providers neither starts a probe nor leaves a menu bar slot")
        model.setMenuBarVisibility(true, for: "antigravity")
        model.setMenuBarVisibility(true, for: "antigravity")
        let reopened = UsageModel(startPolling: false, defaults: defaults)
        let placeholders = reopened.menuEntries(at: Date())
        precondition(placeholders.map(\.id) == ["antigravity"] && placeholders[0].percentText == "–",
                     "Restore the visibility choice and show Antigravity without an invented usage reading")
        precondition(reopened.accessibilitySummary(at: Date()).contains("report usage over ACP"))
        model.refresh()
        let end = Date().addingTimeInterval(5)
        while model.busy && Date() < end {
            RunLoop.main.run(until: Date().addingTimeInterval(0.01))
        }
        precondition(!model.busy && calls.all.count == 3 && calls.all.last?.0 == supported,
                     "A placeholder-only menu bar still refreshes the live providers")
        model.setMenuBarVisibility(false, for: "antigravity")
        precondition(UsageModel(startPolling: false, defaults: defaults).menuEntries(at: Date()).isEmpty,
                     "An empty saved selection retains the app's fallback menu bar button")
        let reading = try UsageReport.decode(Data("""
        {"version":1,"providers":[{"id":"codex","displayName":"Codex","checkedAt":"","stale":false,"windows":[{"label":"Weekly","usedPercent":25}]}]}
        """.utf8))
        let retryGate = DispatchSemaphore(value: 0)
        let attempts = Recorder<Void>()
        let retryModel = UsageModel(startPolling: false, defaults: defaults) { _, _, _ in
            if attempts.append(()) == 1 { throw ReportError.helper("Failed to refresh") }
            _ = retryGate.wait(timeout: .now() + 3)
            return reading
        }
        retryModel.setMenuBarVisibility(true, for: "codex")
        retryModel.report = reading
        retryModel.refresh()
        let failedDeadline = Date().addingTimeInterval(5)
        while retryModel.busy && Date() < failedDeadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.01))
        }
        precondition(retryModel.helperError != nil && retryModel.menuEntries(at: Date())[0].stale)
        retryModel.refresh()
        precondition(retryModel.busy && retryModel.menuEntries(at: Date())[0].stale,
                     "Keep the stale marker while retrying a failed refresh")
        retryGate.signal()
        let retryDeadline = Date().addingTimeInterval(5)
        while retryModel.busy && Date() < retryDeadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.01))
        }
        precondition(!retryModel.busy && retryModel.helperError == nil)
        let fresh = retryModel.menuEntries(at: Date())[0]
        precondition(!fresh.stale && fresh.percentText == "25%", "Clear stale only after success")
        print("macOS refresh scheduling tests passed")
    }
}
