import AppKit

/// Checks GitHub Releases for a newer version. It never installs anything: it tells the user and opens the download page.
@MainActor
final class Updater: ObservableObject {
    static let repo = "gudisigor/ai-usage-widget"

    @Published private(set) var available: (version: String, url: URL)?
    @Published private(set) var isChecking = false

    static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
    }

    /// Silent check, at most once a day.
    func checkIfDue() {
        let last = UserDefaults.standard.object(forKey: "lastUpdateCheck") as? Date ?? .distantPast
        guard Date().timeIntervalSince(last) > 86_400 else { return }
        Task { _ = await check() }
    }

    /// Manual check from the menu or Settings: always answers with a dialog.
    func checkManually() {
        Task {
            let result = await check()
            let alert = NSAlert()
            switch result {
            case .newer(let v, let url):
                alert.messageText = L10n.t("updateAvailable", v)
                alert.informativeText = L10n.t("updateCurrent", Self.currentVersion)
                alert.addButton(withTitle: t("download"))
                alert.addButton(withTitle: t("later"))
                NSApp.activate(ignoringOtherApps: true)
                if alert.runModal() == .alertFirstButtonReturn { NSWorkspace.shared.open(url) }
            case .upToDate:
                alert.messageText = L10n.t("upToDate", Self.currentVersion)
                NSApp.activate(ignoringOtherApps: true)
                alert.runModal()
            case .failed:
                alert.messageText = t("updateFailed")
                NSApp.activate(ignoringOtherApps: true)
                alert.runModal()
            }
        }
    }

    func openDownload() { if let url = available?.url { NSWorkspace.shared.open(url) } }

    enum Result { case newer(String, URL), upToDate, failed }

    private func check() async -> Result {
        isChecking = true
        defer { isChecking = false }
        var req = URLRequest(url: URL(string: "https://api.github.com/repos/\(Self.repo)/releases/latest")!, timeoutInterval: 15)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("AIUsage/\(Self.currentVersion)", forHTTPHeaderField: "User-Agent")
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 200,
              let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let tag = json["tag_name"] as? String,
              let page = (json["html_url"] as? String).flatMap(URL.init(string:)) else { return .failed }
        UserDefaults.standard.set(Date(), forKey: "lastUpdateCheck")
        let latest = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
        if Self.isNewer(latest, than: Self.currentVersion) {
            available = (latest, page)
            return .newer(latest, page)
        }
        available = nil
        return .upToDate
    }

    static func isNewer(_ a: String, than b: String) -> Bool {
        let x = a.split(separator: ".").map { Int($0) ?? 0 }, y = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(x.count, y.count) {
            let p = i < x.count ? x[i] : 0, q = i < y.count ? y[i] : 0
            if p != q { return p > q }
        }
        return false
    }
}
