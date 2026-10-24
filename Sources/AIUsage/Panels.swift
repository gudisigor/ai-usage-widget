import AppKit
import SwiftUI

/// Borderless, non-activating floating window that hosts the widget card.
final class CardPanel: NSPanel {
    var contextMenuProvider: (() -> NSMenu)?
    override var canBecomeKey: Bool { false }
    // Allow the card to sit over the menu bar, right under the notch.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
    override func rightMouseDown(with event: NSEvent) {
        if let menu = contextMenuProvider?(), let view = contentView {
            NSMenu.popUpContextMenu(menu, with: event, for: view)
        }
    }
}

/// Forwards mouse enter/exit of a view's area.
private final class HoverTracker: NSObject {
    var onChange: ((Bool) -> Void)?
    @objc func mouseEntered(with event: NSEvent) { onChange?(true) }
    @objc func mouseExited(with event: NSEvent) { onChange?(false) }
}

/// A card window that fades and slides in/out. Used for the menu-bar and notch pop-ups.
@MainActor
final class CardController {
    let panel: CardPanel
    let hosting: NSHostingView<AnyView>
    private let tracker = HoverTracker()
    var onHoverChange: ((Bool) -> Void)?
    private(set) var isShown = false
    private var topCenter = NSPoint.zero
    private let slide: CGFloat
    private let reveal: RevealState?

    /// With `reveal`, the card appears in place and the SwiftUI content animates itself (notch pour-out).
    init<V: View>(content: V, slide: CGFloat = 8, reveal: RevealState? = nil) {
        self.slide = slide
        self.reveal = reveal
        hosting = NSHostingView(rootView: AnyView(content))
        panel = CardPanel(contentRect: NSRect(origin: .zero, size: hosting.fittingSize),
                          styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.contentView = hosting
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .statusBar
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.alphaValue = 0

        tracker.onChange = { [weak self] inside in self?.onHoverChange?(inside) }
        hosting.addTrackingArea(NSTrackingArea(rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: tracker, userInfo: nil))
    }

    private func frame(for size: NSSize) -> NSRect {
        NSRect(x: topCenter.x - size.width / 2, y: topCenter.y - size.height, width: size.width, height: size.height)
    }

    func present(topCenter point: NSPoint) {
        topCenter = point
        let size = hosting.fittingSize
        let target = frame(for: size)
        if isShown { panel.setFrame(target, display: true); return }
        isShown = true
        if let reveal {
            panel.setFrame(target, display: true)
            panel.alphaValue = 1
            panel.orderFrontRegardless()
            DispatchQueue.main.async { reveal.revealed = true }
            return
        }
        panel.setFrame(target.offsetBy(dx: 0, dy: slide), display: false)
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.22
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.3, 1)
            panel.animator().setFrame(target, display: true)
            panel.animator().alphaValue = 1
        }
    }

    /// Re-fit after the content changed size (e.g. services were ticked).
    func refit() {
        guard isShown else { return }
        panel.setFrame(frame(for: hosting.fittingSize), display: true, animate: true)
    }

    func dismiss() {
        guard isShown else { return }
        isShown = false
        if let reveal {
            reveal.revealed = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                guard let self, !self.isShown else { return }
                self.panel.orderOut(nil)
            }
            return
        }
        let target = panel.frame.offsetBy(dx: 0, dy: slide)
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.16
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().setFrame(target, display: true)
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            guard let self, !self.isShown else { return }
            self.panel.orderOut(nil)
        })
    }
}

/// Decides when a hover-driven card shows and hides: shown while the cursor is on the trigger or the card.
@MainActor
final class HoverPresenter {
    let card: CardController
    let anchor: () -> NSPoint?
    var pinned = false { didSet { update() } }
    var enabled = true { didSet { if !enabled { hideNow() } } }
    private var inTrigger = false
    private var inCard = false
    private var hideWork: DispatchWorkItem?
    private var showWork: DispatchWorkItem?

    init(card: CardController, anchor: @escaping () -> NSPoint?) {
        self.card = card
        self.anchor = anchor
        card.onHoverChange = { [weak self] inside in self?.inCard = inside; self?.update() }
    }

    func triggerChanged(_ inside: Bool) {
        guard enabled || pinned else { return }
        inTrigger = inside
        update()
    }

    func hideNow() {
        pinned = false
        inTrigger = false
        inCard = false
        hideWork?.cancel(); showWork?.cancel()
        card.dismiss()
    }

    private func update() {
        hideWork?.cancel()
        if inTrigger || inCard || pinned {
            guard !card.isShown else { return }
            showWork?.cancel()
            // Short dwell so a cursor sweeping past the corner doesn't flash the card.
            let w = DispatchWorkItem { [weak self] in
                guard let self, let p = self.anchor() else { return }
                self.card.present(topCenter: p)
            }
            showWork = w
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.04, execute: w)
        } else {
            showWork?.cancel()
            let w = DispatchWorkItem { [weak self] in self?.card.dismiss() }
            hideWork = w
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: w)
        }
    }
}

/// Hot zone at the top-centre of the screen (the notch on notched MacBooks).
@MainActor
final class NotchTrigger {
    var onChange: ((Bool) -> Void)?
    private var monitors: [Any] = []
    private var inside = false

    func start() {
        guard monitors.isEmpty else { return }
        let handler: (NSEvent) -> Void = { [weak self] _ in self?.check() }
        if let g = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved, handler: handler) { monitors.append(g) }
        if let l = NSEvent.addLocalMonitorForEvents(matching: .mouseMoved, handler: { [weak self] e in self?.check(); return e }) { monitors.append(l) }
    }

    func stop() {
        monitors.forEach { NSEvent.removeMonitor($0) }
        monitors = []
        if inside { inside = false; onChange?(false) }
    }

    static func hasNotch(_ screen: NSScreen) -> Bool { screen.safeAreaInsets.top > 0 }
    static var anyNotch: Bool { NSScreen.screens.contains(where: hasNotch) }

    static func screen(at point: NSPoint) -> NSScreen? {
        NSScreen.screens.first { $0.frame.contains(point) }
    }

    static func notchWidth(_ screen: NSScreen) -> CGFloat {
        guard let l = screen.auxiliaryTopLeftArea, let r = screen.auxiliaryTopRightArea else { return 200 }
        return screen.frame.width - l.width - r.width
    }

    /// Hot zone: the notch plus a little margin, as tall as the notch.
    static func zone(_ screen: NSScreen) -> NSRect {
        let w = notchWidth(screen) + 120      // generous: the notch plus 60 pt each side, so it's easy to hit
        let h = screen.safeAreaInsets.top
        return NSRect(x: screen.frame.midX - w / 2, y: screen.frame.maxY - h, width: w, height: h + 1)
    }

    private func check() {
        let p = NSEvent.mouseLocation
        guard let screen = Self.screen(at: p), Self.hasNotch(screen) else {
            if inside { inside = false; onChange?(false) }
            return
        }
        let now = Self.zone(screen).contains(p)
        if now != inside { inside = now; onChange?(now) }
    }
}
