import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @ObservedObject var prefs: Preferences
    @ObservedObject var store: UsageStore
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?

    var body: some View {
        Form {
            Section {
                ForEach(Registry.all.filter(\.isLive)) { info in
                    HStack(spacing: 10) {
                        ServiceLogo(info: info).frame(width: 18, height: 18)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(info.name)
                            if let sub = subtitle(info) {
                                Text(sub.text).font(.caption).foregroundColor(sub.warn ? .orange : .secondary)
                            }
                        }
                        Spacer()
                        Toggle("", isOn: Binding(get: { prefs.isSelected(info.id) },
                                                 set: { prefs.set(info.id, on: $0) }))
                            .labelsHidden()
                            .disabled(store.signedIn[info.id] == false)
                    }
                    .opacity(store.signedIn[info.id] == false ? 0.6 : 1)
                }
            } header: {
                Text(t("servicesHeader"))
            } footer: {
                Text(t("servicesFooter"))
            }

            Section {
                Toggle(t("desktop"), isOn: $prefs.showDesktop)
                Toggle(t("onTop"), isOn: $prefs.alwaysOnTop).disabled(!prefs.showDesktop)
                if NotchTrigger.anyNotch {
                    Toggle(t("notch"), isOn: $prefs.hoverNotch)
                }
            } header: {
                Text(t("where"))
            } footer: {
                Text(t("menuNote"))
            }

            Section(t("updatesHeader")) {
                Picker(t("frequency"), selection: $prefs.interval) {
                    ForEach(UsageStore.intervals, id: \.seconds) { Text($0.label).tag($0.seconds) }
                }
                HStack {
                    Text(lastUpdatedText).foregroundColor(.secondary)
                    Spacer()
                    Button(t("refreshNow")) { Task { await store.refresh() } }
                        .disabled(store.isRefreshing)
                }
            }

            Section {
                Picker(t("language"), selection: $prefs.language) {
                    ForEach(Lang.allCases) { Text($0.nativeName).tag($0) }
                }
                Toggle(t("launchAtLogin"), isOn: Binding(get: { launchAtLogin }, set: setLaunch))
                if let loginError { Text(loginError).font(.caption).foregroundColor(.orange) }
            } header: { Text(t("general")) }
        }
        .formStyle(.grouped)
        .frame(width: 440, height: 420)
        .onAppear { Task { await store.detectLogins() } }
    }

    private func subtitle(_ info: ServiceInfo) -> (text: String, warn: Bool)? {
        guard info.isLive else { return ("Coming soon", false) }
        if store.signedIn[info.id] == true { return (t("signedIn"), false) }
        if store.signedIn[info.id] == false { return (t(info.signInHint), true) }
        return nil
    }

    private var lastUpdatedText: String {
        guard let stamp = store.lastUpdated else { return t("notUpdatedYet") }
        let f = DateFormatter(); f.timeStyle = .short
        return L10n.t("lastUpdated", f.string(from: stamp))
    }

    private func setLaunch(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginError = nil
        } catch {
            loginError = t("moveToApps")
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }
}
