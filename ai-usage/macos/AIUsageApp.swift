import AppKit
import ServiceManagement
import SwiftUI

struct UsageProvider: Identifiable {
    let id: String
    let name: String
    var placeholder: String? = nil

    static let all = [
        UsageProvider(id: "codex", name: "Codex"),
        UsageProvider(id: "claude", name: "Claude Code"),
        UsageProvider(id: "grok", name: "Grok"),
        UsageProvider(id: "antigravity", name: "Antigravity",
                      placeholder: "Waiting for Antigravity to report usage over ACP."),
    ]
    static let polledIDs = all.filter { $0.placeholder == nil }.map(\.id)
}

@MainActor
final class UsageModel: ObservableObject {
    @Published var displayDate = Date()
    @Published var report: UsageReport?
    @Published var busy = false
    @Published var helperError: String?
    @Published var loginError: String?
    // Preserve choices from the previous "Show in menu bar" settings menu.
    @Published private(set) var menuBarProviders: [String] {
        didSet { defaults.set(menuBarProviders, forKey: "providers") }
    }
    @Published var launchAtLogin = SMAppService.mainApp.status == .enabled
    private var timer: Timer?
    private var queuedForcedRefresh = false
    private let defaults: UserDefaults
    private let reader: @Sendable (URL, [String], Bool) throws -> UsageReport

    init(startPolling: Bool = true, defaults: UserDefaults = .standard,
         reader: @escaping @Sendable (URL, [String], Bool) throws -> UsageReport = {
             try readUsage(resources: $0, providers: $1, refresh: $2)
         }) {
        self.defaults = defaults
        self.reader = reader
        let saved = defaults.stringArray(forKey: "providers") ?? UsageProvider.polledIDs
        menuBarProviders = UsageProvider.all.map(\.id).filter { saved.contains($0) }
        syncLogin()
        guard startPolling else { return }
        refresh()
        // Poll at a minute so expired windows disappear promptly; helper TTL is five minutes.
        let timer = Timer(timeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.displayDate = Date()
                self?.refresh()
            }
        }
        timer.tolerance = 5
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in Task { @MainActor in self?.refresh() } }
    }

    func setMenuBarVisibility(_ shown: Bool, for id: String) {
        guard UsageProvider.all.contains(where: { $0.id == id }),
              menuBarProviders.contains(id) != shown else { return }
        if shown { menuBarProviders.append(id) }
        else { menuBarProviders.removeAll { $0 == id } }
    }

    func refresh(force: Bool = false) {
        guard !busy else {
            if force { queuedForcedRefresh = true }
            return
        }
        displayDate = Date()
        busy = true
        guard let resources = Bundle.main.resourceURL else {
            busy = false
            helperError = "App resources are missing. Reinstall AI Usage."
            return
        }
        let reader = self.reader
        DispatchQueue.global(qos: .utility).async {
            let result = Result { try reader(resources, UsageProvider.polledIDs, force) }
            DispatchQueue.main.async {
                self.busy = false
                switch result {
                case .success(let report):
                    self.report = report
                    self.helperError = nil
                case .failure(let error): self.helperError = error.localizedDescription
                }
                if self.queuedForcedRefresh {
                    self.queuedForcedRefresh = false
                    self.refresh(force: true)
                }
            }
        }
    }

    func syncLogin() {
        let status = SMAppService.mainApp.status
        launchAtLogin = status == .enabled
        if status == .requiresApproval {
            loginError = "Approve AI Usage in System Settings > General > Login Items."
        } else if defaults.bool(forKey: "launchAtLogin") && !launchAtLogin {
            loginError = "Launch at login is off in macOS. Enable it again here or in System Settings."
        } else { loginError = nil }
    }

    func setLogin(_ value: Bool) {
        do {
            if value { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            defaults.set(value, forKey: "launchAtLogin")
            loginError = SMAppService.mainApp.status == .requiresApproval
                ? "Approve AI Usage in System Settings > General > Login Items." : nil
        } catch { loginError = error.localizedDescription }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    /// Keep selected providers in a fixed order so failures never shift the other slots.
    func menuEntries(at date: Date) -> [MenuEntry] {
        UsageProvider.all.filter { menuBarProviders.contains($0.id) }.map { option in
            let provider = option.placeholder == nil
                ? report?.providers.first { $0.id == option.id } : nil
            let primary = provider?.primary(at: date)
            return MenuEntry(
                id: option.id, name: option.name, usedPercent: primary?.usedPercent,
                nearLimit: provider?.nearLimit(at: date) == true,
                // A failed refresh leaves the previous reading on screen; say so.
                stale: primary != nil && (provider?.stale == true || helperError != nil),
                pending: option.placeholder == nil && provider == nil && busy,
                placeholder: option.placeholder
            )
        }
    }

    func accessibilitySummary(at date: Date) -> String {
        let entries = menuEntries(at: date)
        guard !entries.isEmpty else { return "AI Usage. No providers shown in the menu bar." }
        return "AI Usage. " + entries.map(\.spokenSummary).joined(separator: ". ") + "."
    }
}

struct MenuEntry: Equatable {
    let id: String
    let name: String
    let usedPercent: Double?
    let nearLimit: Bool
    let stale: Bool
    let pending: Bool
    let placeholder: String?

    var percentText: String {
        if let usedPercent { return "\(Int(usedPercent.rounded()))%" }
        return pending ? "…" : "–"
    }

    var spokenSummary: String {
        if let placeholder { return placeholder }
        guard let usedPercent else { return "\(name) " + (pending ? "loading" : "unavailable") }
        return "\(name) \(Int(usedPercent.rounded())) percent used"
            + (nearLimit ? ", a limit is at or above 85 percent" : "")
            + (stale ? ", last reading" : "")
    }
}

#if !TESTING
@main
struct AIUsageApp: App {
    @StateObject private var model = UsageModel()

    var body: some Scene {
        MenuBarExtra {
            UsagePanel(model: model)
        } label: {
            Image(nsImage: menuBarImage(for: model.menuEntries(at: model.displayDate)))
                .accessibilityLabel(model.accessibilitySummary(at: model.displayDate))
        }.menuBarExtraStyle(.window)
    }
}

#endif
