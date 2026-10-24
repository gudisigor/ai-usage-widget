import SwiftUI

private let lowThreshold = 20.0
private let alertRed = Color(red: 1.0, green: 0.42, blue: 0.42)
private let claudeOrange = Color(red: 0.95, green: 0.45, blue: 0.27)

func formatReset(_ date: Date?, now: Date, renewal: Bool = false) -> String {
    guard let date else { return t("resetUnknown") }
    let secs = Int(date.timeIntervalSince(now))
    if secs <= 0 { return renewal ? t("payDue") : t("resetting") }
    let d = secs / 86400, h = (secs % 86400) / 3600, m = (secs % 3600) / 60
    return L10n.t(renewal ? "payIn" : "resetIn", L10n.duration(days: d, hours: h, minutes: m))
}

struct WidgetActions {
    var openSettings: () -> Void = {}
    var quit: () -> Void = {}
}

enum WidgetMode: Equatable { case desktop, popup, notch(inset: CGFloat) }

/// Drives the "pours out of the notch" reveal.
@MainActor final class RevealState: ObservableObject { @Published var revealed = false }

/// Flat top (it hangs from the screen edge), rounded bottom.
struct NotchShape: Shape {
    var radius: CGFloat = 26
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - radius))
        p.addArc(center: CGPoint(x: rect.maxX - radius, y: rect.maxY - radius), radius: radius,
                 startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
        p.addLine(to: CGPoint(x: rect.minX + radius, y: rect.maxY))
        p.addArc(center: CGPoint(x: rect.minX + radius, y: rect.maxY - radius), radius: radius,
                 startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
        p.closeSubpath()
        return p
    }
}

/// Wraps a card so it expands out of the top edge with a springy, blurred-to-sharp reveal.
struct NotchReveal<Content: View>: View {
    @ObservedObject var reveal: RevealState
    let content: Content
    var body: some View {
        content
            .scaleEffect(x: reveal.revealed ? 1 : 0.45, y: reveal.revealed ? 1 : 0.08, anchor: .top)
            .blur(radius: reveal.revealed ? 0 : 10)
            .opacity(reveal.revealed ? 1 : 0)
            .animation(.interpolatingSpring(stiffness: 150, damping: 15), value: reveal.revealed)
    }
}

/// Dark glass: pure black where it meets the notch, then fading to see-through tinted glass below.
@ViewBuilder private func glassBackground<S: Shape>(_ shape: S) -> some View {
    ZStack {
        if #available(macOS 26.0, *) {
            Color.clear.glassEffect(.regular.tint(.black.opacity(0.45)), in: shape)
        } else {
            shape.fill(.ultraThinMaterial)
        }
        shape.fill(LinearGradient(stops: [.init(color: .black, location: 0),
                                          .init(color: .black, location: 0.16),
                                          .init(color: .black.opacity(0.55), location: 0.42),
                                          .init(color: .black.opacity(0.38), location: 1)],
                                  startPoint: .top, endPoint: .bottom))
    }
}

struct WidgetView: View {
    @ObservedObject var store: UsageStore
    @ObservedObject var prefs: Preferences
    var mode: WidgetMode = .desktop
    var actions = WidgetActions()

    /// Ticked services, minus any that aren't signed in on this Mac (they reappear once the login is back).
    private var services: [ServiceInfo] { prefs.selected.filter { store.signedIn[$0] != false }.map(Registry.info) }

    var body: some View {
        VStack(spacing: 0) {
            if case .notch(let inset) = mode { Color.clear.frame(height: inset) }   // keep content below the physical notch
            if !isNotch {
                header
                line
            }
            content
                .padding(.horizontal, 12)
                .padding(.top, isNotch ? 8 : 6)
                .padding(.bottom, isNotch ? 12 : 6)
            if mode == .popup {
                line
                footer
            }
        }
        .frame(minWidth: 250)
        .fixedSize()
        .background(backdrop)
        .clipShape(cardShape)
        .overlay(cardShape.stroke(isNotch
            ? AnyShapeStyle(LinearGradient(stops: [.init(color: .clear, location: 0.2), .init(color: Color.white.opacity(0.34), location: 1)], startPoint: .top, endPoint: .bottom))
            : AnyShapeStyle(Color.white.opacity(0.13)), lineWidth: 1))
        .preferredColorScheme(.dark)
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: prefs.selected)
    }

    private var isNotch: Bool { if case .notch = mode { return true } else { return false } }
    private var cardShape: AnyShape { isNotch ? AnyShape(NotchShape()) : AnyShape(RoundedRectangle(cornerRadius: 12, style: .continuous)) }

    @ViewBuilder private var backdrop: some View {
        if isNotch {
            glassBackground(NotchShape())
        } else {
            LinearGradient(colors: [Color(red: 0.075, green: 0.09, blue: 0.12), Color(red: 0.05, green: 0.06, blue: 0.085)],
                           startPoint: .top, endPoint: .bottom)
        }
    }

    private var line: some View { Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1) }

    @ViewBuilder private var content: some View {
        if services.isEmpty {
            VStack(spacing: 8) {
                Text(t("noServices")).font(.system(size: 12, weight: .medium)).foregroundColor(.white.opacity(0.8))
                Button(t("chooseServices")) { actions.openSettings() }.controlSize(.small)
            }
            .frame(width: 252, height: 90)
        } else {
            VStack(spacing: 8) {
                ForEach(Array(stride(from: 0, to: services.count, by: 3)), id: \.self) { start in
                    HStack(alignment: .top, spacing: 0) {
                        ForEach(Array(services[start..<min(start + 3, services.count)].enumerated()), id: \.element.id) { i, info in
                            if i > 0 { Rectangle().fill(Color.white.opacity(0.08)).frame(width: 1).padding(.horizontal, 10) }
                            ProviderColumn(info: info, state: store.states[info.id] ?? ProviderState(), now: store.now)
                        }
                    }
                }
            }
            .transition(.opacity)
        }
    }

    private var header: some View {
        HStack {
            Text(t("title")).font(.system(size: 11, weight: .medium)).foregroundColor(.white.opacity(0.8))
            Spacer()
            Button { Task { await store.refresh() } } label: {
                HStack(spacing: 7) {
                    if store.isRefreshing {
                        ProgressView().controlSize(.mini).scaleEffect(0.7).frame(width: 10, height: 10)
                    } else {
                        Circle().fill(Color.white.opacity(0.55)).frame(width: 6, height: 6)
                    }
                    Text(updatedText).font(.system(size: 10.5)).foregroundColor(.white.opacity(0.6))
                }
            }
            .buttonStyle(.plain)
            .help(t("helpRefresh"))
        }
        .padding(.horizontal, 12)
        .frame(height: 26)
    }

    private var footer: some View {
        HStack {
            Button { actions.openSettings() } label: { Label(t("settings"), systemImage: "gearshape") }
            Spacer()
            Button { actions.quit() } label: { Text(t("quit")) }
        }
        .buttonStyle(.plain)
        .font(.system(size: 10.5))
        .foregroundColor(.white.opacity(0.55))
        .padding(.horizontal, 12)
        .frame(height: 24)
    }

    private var updatedText: String {
        if store.isRefreshing { return t("updating") }
        guard let stamp = store.lastUpdated else { return t("notUpdated") }
        let s = Int(store.now.timeIntervalSince(stamp))
        if s < 60 { return t("updatedNow") }
        if s < 3600 { return L10n.t("updatedMin", s / 60) }
        return L10n.t("updatedHour", s / 3600)
    }
}

struct ProviderColumn: View {
    let info: ServiceInfo
    let state: ProviderState
    let now: Date

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                ServiceLogo(info: info).frame(width: 16, height: 16)
                Text(info.name).font(.system(size: 13, weight: .medium)).foregroundColor(.white)
                if state.error != nil, state.snapshot != nil {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 11)).foregroundColor(alertRed).help(state.error ?? "")
                }
                Spacer()
                Text(t("remaining")).font(.system(size: 9.5)).foregroundColor(.white.opacity(0.45))
            }
            .padding(.bottom, 5)
            Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1)

            if let snap = state.snapshot {
                UsageRow(label: t("day"), window: snap.session, now: now)
                Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1)
                UsageRow(label: t("week"), window: snap.weekly, now: now)
                Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1)
                UsageRow(label: t("sub"), window: snap.monthly, now: now)
            } else {
                Text(state.error ?? t("loading"))
                    .font(.system(size: 10.5)).foregroundColor(.white.opacity(0.55))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, minHeight: 90)
            }
        }
        .frame(width: 232)
    }
}

struct UsageRow: View {
    let label: String
    let window: UsageWindow?
    let now: Date

    private var low: Bool { (window?.remaining ?? 100).rounded() <= lowThreshold }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label).font(.system(size: 11)).foregroundColor(.white.opacity(0.85)).lineLimit(1).minimumScaleFactor(0.8)
                .frame(width: 64, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.14))
                        Capsule()
                            .fill(low ? alertRed : Color.white.opacity(0.88))
                            .frame(width: geo.size.width * CGFloat((window?.remaining ?? 0) / 100))
                    }
                }
                .frame(height: 4)
                .padding(.top, 4)
                Text(window == nil ? (label == t("sub") ? t("dateUnknown") : t("notAvailable")) : formatReset(window?.resetsAt, now: now, renewal: window?.renewal ?? false))
                    .font(.system(size: 9.5)).foregroundColor(.white.opacity(0.5)).lineLimit(1).minimumScaleFactor(0.8)
            }
            Text(window.map { "\(Int($0.remaining.rounded()))%" } ?? "—")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(window == nil ? .white.opacity(0.4) : (low ? alertRed : .white))
                .frame(width: 34, alignment: .trailing)
        }
        .padding(.vertical, 4)
    }
}

