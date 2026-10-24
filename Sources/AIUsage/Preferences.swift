import Foundation
import Combine

@MainActor
final class Preferences: ObservableObject {
    private let d = UserDefaults.standard
    private let persist: Bool

    @Published var selected: [ServiceID] { didSet { if persist { d.set(selected.map(\.rawValue), forKey: "selectedServices") } } }
    @Published var showDesktop: Bool { didSet { if persist { d.set(showDesktop, forKey: "showDesktop") } } }
    @Published var alwaysOnTop: Bool { didSet { if persist { d.set(alwaysOnTop, forKey: "alwaysOnTop") } } }
    @Published var hoverMenuBar: Bool { didSet { if persist { d.set(hoverMenuBar, forKey: "hoverMenuBar") } } }
    @Published var hoverNotch: Bool { didSet { if persist { d.set(hoverNotch, forKey: "hoverNotch") } } }
    @Published var language: Lang { didSet { L10n.current = language; if persist { d.set(language.rawValue, forKey: "language") } } }
    @Published var interval: TimeInterval { didSet { if persist { d.set(interval, forKey: "refreshInterval") } } }

    /// True until the user (or auto-detect) has chosen services once.
    let isFirstRun: Bool

    init(demo: Bool = false) {
        persist = !demo
        let saved = d.array(forKey: "selectedServices") as? [String]
        isFirstRun = saved == nil && !demo
        selected = demo ? [.chatgpt, .claude] : (saved ?? []).compactMap(ServiceID.init(rawValue:))
        showDesktop = d.object(forKey: "showDesktop") as? Bool ?? true
        alwaysOnTop = d.object(forKey: "alwaysOnTop") as? Bool ?? false
        hoverMenuBar = d.object(forKey: "hoverMenuBar") as? Bool ?? true
        hoverNotch = d.object(forKey: "hoverNotch") as? Bool ?? true
        interval = d.object(forKey: "refreshInterval") as? Double ?? 300
        language = d.string(forKey: "language").flatMap(Lang.init(rawValue:)) ?? Lang.systemDefault()
        L10n.current = language
    }

    func isSelected(_ id: ServiceID) -> Bool { selected.contains(id) }

    func set(_ id: ServiceID, on: Bool) {
        if on, !selected.contains(id) { selected.append(id) }
        if !on { selected.removeAll { $0 == id } }
        // Keep the registry order so columns don't jump around.
        selected.sort { a, b in
            (ServiceID.allCases.firstIndex(of: a) ?? 0) < (ServiceID.allCases.firstIndex(of: b) ?? 0)
        }
    }
}
