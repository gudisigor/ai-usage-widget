import AppKit
import Combine

struct ProviderState {
    var snapshot: ProviderSnapshot?
    var error: String?
}

@MainActor
final class UsageStore: ObservableObject {
    static var intervals: [(label: String, seconds: TimeInterval)] {
        [(t("everyMin"), 60), (t("every5"), 300), (t("every15"), 900), (t("every30"), 1800), (t("manual"), 0)]
    }

    @Published var states: [ServiceID: ProviderState] = [:]
    @Published var signedIn: [ServiceID: Bool] = [:]
    @Published var isRefreshing = false
    @Published var lastUpdated: Date?
    @Published var now = Date()          // ticks every 30s so countdowns stay fresh

    let prefs: Preferences
    private let demo: Bool
    private var refreshTimer: Timer?
    private var tickTimer: Timer?
    private var bag = Set<AnyCancellable>()

    init(prefs: Preferences, demo: Bool = false) {
        self.prefs = prefs
        self.demo = demo

        tickTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 3_000_000_000)   // let Wi-Fi come back
                await self?.refresh()
            }
        }
        prefs.$interval.sink { [weak self] _ in DispatchQueue.main.async { self?.schedule() } }.store(in: &bag)
        // Newly ticked services should show data right away.
        prefs.$selected.dropFirst().sink { [weak self] _ in DispatchQueue.main.async { Task { await self?.refresh(force: true) } } }.store(in: &bag)

        Task {
            await detectLogins()
            if prefs.isFirstRun {
                // First launch: pre-tick every service that is already signed in on this Mac.
                for s in Registry.all where signedIn[s.id] == true { prefs.set(s.id, on: true) }
                UserDefaults.standard.set(prefs.selected.map(\.rawValue), forKey: "selectedServices")
            }
            await refresh()
        }
    }

    func detectLogins() async {
        if demo { return }
        for s in Registry.all {
            guard let p = s.provider else { continue }
            signedIn[s.id] = await p.isAvailable()
        }
    }

    private func schedule() {
        refreshTimer?.invalidate()
        refreshTimer = nil
        guard prefs.interval > 0 else { return }
        let t = Timer(timeInterval: prefs.interval, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refresh() }
        }
        t.tolerance = prefs.interval * 0.1
        RunLoop.main.add(t, forMode: .common)
        refreshTimer = t
    }

    private func tick() {
        now = Date()
        // A window just reset → the numbers on screen are wrong; refresh early.
        let windows = states.values.compactMap { $0.snapshot }.flatMap { [$0.session, $0.weekly] }.compactMap { $0 }
        let expired = windows.contains { ($0.resetsAt ?? .distantFuture) < now }
        if expired, now.timeIntervalSince(lastUpdated ?? .distantPast) > 60 {
            Task { await refresh() }
        }
    }

    func refresh(force: Bool = false) async {
        if isRefreshing && !force { return }
        isRefreshing = true
        defer { isRefreshing = false }

        if demo {
            try? await Task.sleep(nanoseconds: 400_000_000)
            let d = Date()
            states[.chatgpt] = ProviderState(snapshot: ProviderSnapshot(
                session: .init(remaining: 64, resetsAt: d.addingTimeInterval(2 * 3600 + 18 * 60)),
                weekly: .init(remaining: 37, resetsAt: d.addingTimeInterval(3 * 86400 + 8 * 3600)),
                monthly: .init(remaining: 18, resetsAt: d.addingTimeInterval(12 * 86400), renewal: true)))
            states[.claude] = ProviderState(snapshot: ProviderSnapshot(
                session: .init(remaining: 82, resetsAt: d.addingTimeInterval(4 * 3600 + 52 * 60)),
                weekly: .init(remaining: 46, resetsAt: d.addingTimeInterval(5 * 86400 + 2 * 3600)),
                monthly: .init(remaining: 12, resetsAt: d.addingTimeInterval(9 * 86400), renewal: true)))
            lastUpdated = Date(); now = Date()
            return
        }

        let targets = prefs.selected.filter { signedIn[$0] != false }.compactMap { id in Registry.info(id).provider.map { (id, $0) } }
        await withTaskGroup(of: (ServiceID, Result<ProviderSnapshot, Error>).self) { group in
            for (id, provider) in targets {
                group.addTask {
                    do { return (id, .success(try await provider.fetch())) }
                    catch { return (id, .failure(error)) }
                }
            }
            for await (id, result) in group { apply(result, to: id) }
        }
        await detectLogins()
        lastUpdated = Date()
        now = Date()
    }

    /// On failure keep the last good numbers and just flag the error.
    private func apply(_ r: Result<ProviderSnapshot, Error>, to id: ServiceID) {
        switch r {
        case .success(let s): states[id] = ProviderState(snapshot: s, error: nil)
        case .failure(let e):
            var st = states[id] ?? ProviderState()
            st.error = e.localizedDescription
            states[id] = st
        }
    }
}
