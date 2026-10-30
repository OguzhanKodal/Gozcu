import ServiceManagement
import SwiftUI

@main
struct GozcuApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @ObservedObject var store = Store.shared

    var body: some Scene {
        MenuBarExtra {
            MenuPanel()
        } label: {
            MenuLabel()
        }
        .menuBarExtraStyle(.window)

        Window("Gözcü", id: "pano") {
            Dashboard()
        }
        .defaultSize(width: 1180, height: 820)

        Settings {
            SettingsView()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        Notifier.setup()
        _ = Store.shared
    }

    /// Uygulama zaten açıkken Finder'dan ya da Spotlight'tan yeniden açılınca panoyu göster.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        PanoOpener.open()
        return true
    }
}

/// Pano penceresini SwiftUI dışından (AppDelegate) açabilmek için menü etiketinin
/// ortamındaki `openWindow` eylemini saklar.
@MainActor
enum PanoOpener {
    static var action: OpenWindowAction?

    static func open() {
        action?(id: "pano")
        NSApp.activate(ignoringOtherApps: true)
    }
}

/// Menü çubuğundaki etiket: her makine için bir nokta, en sıcak değer.
struct MenuLabel: View {
    @ObservedObject var store = Store.shared
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        let dots = store.machines.map { m -> String in
            switch m.health {
            case .ok: return "🟢"
            case .warn: return "🟠"
            case .alarm: return "🔴"
            case .offline: return "⚫️"
            }
        }.joined()
        let hottest = store.machines.compactMap { $0.online ? $0.status?.hottest : nil }.max()
        Text(dots.isEmpty ? "Gözcü" : dots + (hottest.map { " \(Int($0))°" } ?? ""))
            .onAppear { PanoOpener.action = openWindow }
    }
}

struct MenuPanel: View {
    @ObservedObject var store = Store.shared
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Gözcü").font(.headline)
                Spacer()
                TokenMini()
            }
            ForEach(store.machines) { m in MenuMachineRow(m: m) }
            Divider()
            HStack {
                Button("Panoyu aç") {
                    openWindow(id: "pano")
                    NSApp.activate(ignoringOtherApps: true)
                }
                .keyboardShortcut("o")
                Spacer()
                SettingsLink { Text("Ayarlar") }
                Button("Çık") { NSApp.terminate(nil) }
            }
        }
        .padding(14)
        .frame(width: 360)
    }
}

struct TokenMini: View {
    @ObservedObject var store = Store.shared
    var body: some View {
        let total = store.machines.compactMap { $0.status?.ai.tokens }.flatMap { $0 }.reduce(0) { $0 + $1.total }
        Label(Fmt.tokens(total), systemImage: "number").font(.caption).foregroundStyle(.secondary)
    }
}

struct MenuMachineRow: View {
    @ObservedObject var m: MachineState
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Circle().fill(Theme.health(m.health)).frame(width: 8, height: 8)
                Image(systemName: m.config.icon)
                Text(m.config.name).fontWeight(.semibold)
                Spacer()
                if let s = m.status, m.online {
                    if s.game != nil { Image(systemName: "gamecontroller.fill").foregroundStyle(Theme.warn) }
                    if !s.ai.models.isEmpty { Image(systemName: "sparkles").foregroundStyle(Theme.gpu) }
                    if let b = s.battery {
                        Image(systemName: b.plugged ? "powerplug.fill" : "battery.50").foregroundStyle(b.plugged ? Theme.good : Theme.warn)
                        Text("%\(Int(b.percent))").monospacedDigit()
                    }
                } else {
                    Text("çevrimdışı").foregroundStyle(.secondary)
                }
            }
            if let s = m.status, m.online {
                HStack(spacing: 12) {
                    metric("CPU", Fmt.pct(s.cpu.usage), Fmt.temp(s.cpu.temp), Theme.temp(s.cpu.temp))
                    if let g = s.gpu { metric("GPU", Fmt.pct(g.util), Fmt.temp(g.temp), Theme.temp(g.temp)) }
                    if let f = s.fans.first { metric("Fan", "\(Int(f.value))", "rpm", .secondary) }
                }
                if s.guard_.state == "alarm" {
                    HStack {
                        Image(systemName: "flame.fill").foregroundStyle(Theme.bad)
                        Text(s.guard_.reason ?? "Isı yüksek").font(.caption)
                        if let d = s.guard_.deadline {
                            Text(Date(timeIntervalSince1970: TimeInterval(d)), style: .timer).font(.caption.monospacedDigit()).foregroundStyle(Theme.bad)
                        }
                        Spacer()
                        Button("Ertele") { Task { await Store.shared.action(m, ["action": "snooze", "minutes": 15]) } }.controlSize(.small)
                        Button("Durdur") { Task { await Store.shared.action(m, ["action": "stop_ai"]) } }.controlSize(.small)
                    }
                }
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.05)))
    }

    private func metric(_ title: String, _ a: String, _ b: String, _ color: Color) -> some View {
        HStack(spacing: 4) {
            Text(title).foregroundStyle(.secondary)
            Text(a).monospacedDigit()
            Text(b).monospacedDigit().foregroundStyle(color)
        }
        .font(.callout)
    }
}

struct SettingsView: View {
    @ObservedObject var store = Store.shared
    @State private var configs: [MachineConfig] = []
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        Form {
            Section("Makineler") {
                ForEach($configs) { $c in
                    VStack(alignment: .leading) {
                        HStack {
                            TextField("Ad", text: $c.name)
                            TextField("Simge", text: $c.icon).frame(width: 140)
                        }
                        TextField("Adres", text: $c.url)
                        SecureField("Token", text: $c.token)
                    }
                    .padding(.vertical, 4)
                }
                .onDelete { configs.remove(atOffsets: $0) }
                Button("Makine ekle") { configs.append(MachineConfig(name: "Yeni", url: "http://100.x.x.x:7420", token: "", icon: "desktopcomputer")) }
            }
            Section("Genel") {
                Toggle("Oturum açılınca başlat", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, on in
                        do { if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() } } catch { launchAtLogin.toggle() }
                    }
                Toggle("Oyun açılıp kapanınca bildir", isOn: $store.notifyGames)
            }
            HStack {
                Spacer()
                Button("Kaydet") { store.save(configs) }.keyboardShortcut(.defaultAction)
            }
        }
        .formStyle(.grouped)
        .frame(width: 520, height: 520)
        .onAppear { configs = store.machines.map(\.config) }
    }
}
