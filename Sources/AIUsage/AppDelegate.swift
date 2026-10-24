import AppKit
import SwiftUI
import Combine

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let demo = CommandLine.arguments.contains("--demo")
    private lazy var prefs = Preferences(demo: demo)
    private lazy var store = UsageStore(prefs: prefs, demo: demo)
    private lazy var actions = WidgetActions(openSettings: { [weak self] in self?.openSettings() },
                                             quit: { NSApp.terminate(nil) })

    private var desktopPanel: CardPanel!
    private var desktopHosting: NSHostingView<WidgetView>!
    private var statusItem: NSStatusItem!
    private var menuBarCard: HoverPresenter!
    private var notchCard: HoverPresenter!
    private let notchTrigger = NotchTrigger()
    private var settingsWindow: NSWindow?
    private var outsideClickMonitor: Any?
    private var bag = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        buildDesktopPanel()
        buildMenuBar()
        buildNotch()
        applyPrefs()

        store.$signedIn
            .sink { [weak self] _ in DispatchQueue.main.async { self?.applyPrefs() } }
            .store(in: &bag)
        prefs.$language.dropFirst()
            .sink { [weak self] _ in
                DispatchQueue.main.async {
                    self?.settingsWindow?.title = t("title")
                    Task { await self?.store.refresh(force: true) }
                }
            }
            .store(in: &bag)
        prefs.objectWillChange
            .sink { [weak self] in DispatchQueue.main.async { self?.applyPrefs() } }
            .store(in: &bag)

        if prefs.isFirstRun {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in self?.openSettings() }
        }
        installSnapshotHook()
    }

    // MARK: Desktop widget

    private func buildDesktopPanel() {
        desktopHosting = NSHostingView(rootView: WidgetView(store: store, prefs: prefs, mode: .desktop, actions: actions))
        let size = desktopHosting.fittingSize
        desktopPanel = CardPanel(contentRect: NSRect(origin: .zero, size: size),
                                 styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        desktopPanel.contentView = desktopHosting
        desktopPanel.isOpaque = false
        desktopPanel.backgroundColor = .clear
        desktopPanel.hasShadow = true
        desktopPanel.isMovableByWindowBackground = true
        desktopPanel.isReleasedWhenClosed = false
        desktopPanel.alphaValue = 0.92
        desktopPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        desktopPanel.contextMenuProvider = { [weak self] in self?.makeMenu() ?? NSMenu() }

        if !desktopPanel.setFrameUsingName("AIUsageWidget"), let screen = NSScreen.main {
            let f = screen.visibleFrame
            desktopPanel.setFrameOrigin(NSPoint(x: f.maxX - size.width - 24, y: f.maxY - size.height - 24))
        }
        desktopPanel.setFrameAutosaveName("AIUsageWidget")
    }

    private func refitDesktop() {
        let size = desktopHosting.fittingSize
        var f = desktopPanel.frame
        guard abs(f.width - size.width) > 0.5 || abs(f.height - size.height) > 0.5 else { return }
        f.origin.y += f.height - size.height     // keep the top edge fixed
        f.size = size
        desktopPanel.setFrame(f, display: true, animate: true)
    }

    // MARK: Menu bar icon (hover or click)

    private func buildMenuBar() {
        let card = CardController(content: WidgetView(store: store, prefs: prefs, mode: .popup, actions: actions))
        menuBarCard = HoverPresenter(card: card) { [weak self] in
            guard let w = self?.statusItem.button?.window else { return nil }
            return NSPoint(x: w.frame.midX, y: w.frame.minY - 6)
        }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "gauge.with.dots.needle.50percent", accessibilityDescription: "AI usage")
            button.target = self
            button.action = #selector(statusClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
    }

    @objc private func statusClicked() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            menuBarCard.hideNow()
            statusItem.menu = makeMenu()
            statusItem.button?.performClick(nil)
            statusItem.menu = nil
            return
        }
        // Click pins the card open until the next click elsewhere.
        if menuBarCard.pinned { unpinMenuBar() } else { pinMenuBar() }
    }

    private func pinMenuBar() {
        menuBarCard.pinned = true
        if let p = menuBarCard.anchor() { menuBarCard.card.present(topCenter: p) }
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in self?.unpinMenuBar() }
        }
    }

    private func unpinMenuBar() {
        if let m = outsideClickMonitor { NSEvent.removeMonitor(m); outsideClickMonitor = nil }
        menuBarCard.hideNow()
    }

    // MARK: Notch

    private func buildNotch() {
        let inset = NSScreen.screens.first(where: NotchTrigger.hasNotch)?.safeAreaInsets.top ?? 32
        let reveal = RevealState()
        let view = NotchReveal(reveal: reveal,
                               content: WidgetView(store: store, prefs: prefs, mode: .notch(inset: inset), actions: actions))
        let card = CardController(content: view, reveal: reveal)
        notchCard = HoverPresenter(card: card) {
            // The card hangs from the very top edge, so it appears to pour out of the notch.
            guard let screen = NotchTrigger.screen(at: NSEvent.mouseLocation), NotchTrigger.hasNotch(screen) else { return nil }
            return NSPoint(x: screen.frame.midX, y: screen.frame.maxY)
        }
        notchTrigger.onChange = { [weak self] inside in self?.notchCard.triggerChanged(inside) }
    }

    // MARK: Preferences → windows

    private func applyPrefs() {
        if prefs.showDesktop { desktopPanel.orderFrontRegardless() } else { desktopPanel.orderOut(nil) }
        desktopPanel.level = prefs.alwaysOnTop ? .floating : NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
        menuBarCard.enabled = false      // the menu bar icon opens on click only
        notchCard.enabled = prefs.hoverNotch && NotchTrigger.anyNotch
        if prefs.hoverNotch && NotchTrigger.anyNotch { notchTrigger.start() } else { notchTrigger.stop() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            self?.refitDesktop()
            self?.menuBarCard.card.refit()
            self?.notchCard.card.refit()
        }
    }

    // MARK: Settings & menu

    private func openSettings() {
        menuBarCard.hideNow()
        notchCard.hideNow()
        if settingsWindow == nil {
            let w = NSWindow(contentRect: .zero, styleMask: [.titled, .closable],
                             backing: .buffered, defer: false)
            w.title = t("title")
            w.isReleasedWhenClosed = false
            w.contentView = NSHostingView(rootView: SettingsView(prefs: prefs, store: store))
            w.center()
            settingsWindow = w
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    /// Compact native menu: grey header, icons, sub-menus, shortcuts on the right.
    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false

        let header = NSMenuItem(title: "\(t("title")) · \(statusLine())", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(.separator())

        menu.addItem(item(t("refreshNow"), #selector(refreshNow), key: "r", symbol: "arrow.clockwise"))

        let freq = NSMenuItem(title: t("frequency"), action: nil, keyEquivalent: "")
        freq.image = symbol("clock")
        let freqMenu = NSMenu()
        for opt in UsageStore.intervals {
            let it = item(opt.label, #selector(setInterval(_:)))
            it.representedObject = opt.seconds
            it.state = prefs.interval == opt.seconds ? .on : .off
            freqMenu.addItem(it)
        }
        freq.submenu = freqMenu
        menu.addItem(freq)

        let lang = NSMenuItem(title: t("language"), action: nil, keyEquivalent: "")
        lang.image = symbol("globe")
        let langMenu = NSMenu()
        for l in Lang.allCases {
            let it = item(l.nativeName, #selector(setLanguage(_:)))
            it.representedObject = l.rawValue
            it.state = prefs.language == l ? .on : .off
            langMenu.addItem(it)
        }
        lang.submenu = langMenu
        menu.addItem(lang)

        menu.addItem(item(prefs.showDesktop ? t("hideWidget") : t("showWidget"), #selector(toggleDesktop),
                          symbol: prefs.showDesktop ? "eye.slash" : "eye"))
        menu.addItem(.separator())
        menu.addItem(item(t("settingsMenu"), #selector(settingsAction), key: ",", symbol: "gearshape"))
        menu.addItem(.separator())
        menu.addItem(item(t("quit"), #selector(quit), key: "q", symbol: "power"))
        return menu
    }

    private func symbol(_ name: String) -> NSImage? {
        NSImage(systemSymbolName: name, accessibilityDescription: nil)
    }

    private func item(_ title: String, _ action: Selector, key: String = "", symbol name: String? = nil) -> NSMenuItem {
        let it = NSMenuItem(title: title, action: action, keyEquivalent: key)
        it.target = self
        if let name { it.image = symbol(name) }
        return it
    }

    private func statusLine() -> String {
        guard let stamp = store.lastUpdated else { return t("notUpdatedYet") }
        let f = DateFormatter(); f.timeStyle = .short
        return L10n.t("lastUpdated", f.string(from: stamp))
    }

    @objc private func setInterval(_ s: NSMenuItem) { prefs.interval = (s.representedObject as? TimeInterval) ?? 300 }
    @objc private func setLanguage(_ s: NSMenuItem) {
        if let raw = s.representedObject as? String, let l = Lang(rawValue: raw) { prefs.language = l }
    }
    @objc private func refreshNow() { Task { await store.refresh() } }
    @objc private func settingsAction() { openSettings() }
    @objc private func toggleDesktop() { prefs.showDesktop.toggle() }
    @objc private func quit() { NSApp.terminate(nil) }

    // MARK: Dev aid

    /// `--snapshot=/path.png` renders the widget to a PNG and quits.
    private func installSnapshotHook() {
        guard let arg = CommandLine.arguments.first(where: { $0.hasPrefix("--snapshot=") }) else { return }
        if let l = CommandLine.arguments.first(where: { $0.hasPrefix("--lang=") }), let lang = Lang(rawValue: String(l.dropFirst(7))) { prefs.language = lang }
        let path = String(arg.dropFirst("--snapshot=".count))
        DispatchQueue.main.asyncAfter(deadline: .now() + (demo ? 1.5 : 8)) {
            if CommandLine.arguments.contains("--settings") {
                let host = NSHostingView(rootView: SettingsView(prefs: self.prefs, store: self.store))
                host.frame = NSRect(x: 0, y: 0, width: 440, height: 600)
                let win = NSWindow(contentRect: host.frame, styleMask: [.titled], backing: .buffered, defer: false)
                win.contentView = host
                win.orderFrontRegardless()
                host.layoutSubtreeIfNeeded()
                if let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
                    host.cacheDisplay(in: host.bounds, to: rep)
                    try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
                }
                NSApp.terminate(nil)
                return
            }
            let mode: WidgetMode = CommandLine.arguments.contains("--notch") ? .notch(inset: 32) : .popup
            let view = WidgetView(store: self.store, prefs: self.prefs, mode: mode, actions: self.actions)
                .padding(24).background(Color(white: 0.04))
            let img = ImageRenderer(content: view)
            img.scale = 2
            if let cg = img.cgImage {
                try? NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
            }
            NSApp.terminate(nil)
        }
    }
}
