import Foundation

/// One rate-limit window. `remaining` is a percentage 0...100.
struct UsageWindow: Equatable {
    var remaining: Double
    var resetsAt: Date?
    var renewal = false      // caption reads "Renews in" instead of "Resets in"
}

struct ProviderSnapshot: Equatable {
    var session: UsageWindow?   // shown as "Daily"
    var weekly: UsageWindow?
    var monthly: UsageWindow?
}

protocol UsageProvider {
    func fetch() async throws -> ProviderSnapshot
    /// True when a local login for this service exists on the Mac.
    func isAvailable() async -> Bool
}

enum UsageError: LocalizedError {
    case message(String)
    case http(Int)

    var errorDescription: String? {
        switch self {
        case .message(let m): return m
        case .http(let c): return L10n.t("errHTTP", c)
        }
    }
}
