import Foundation
import SwiftUI

/// Bir makinenin canlı durumu ve geçmişi.
@MainActor
final class MachineState: ObservableObject, Identifiable {
    let config: MachineConfig
    nonisolated var id: String { config.name }
    @Published var status: Status?
    @Published var lastSeen: Date?
    @Published var error: String?
    @Published var history: [Sample] = []
    @Published var lastAction: String?

    init(config: MachineConfig) { self.config = config }

    var online: Bool { lastSeen.map { Date().timeIntervalSince($0) < 10 } ?? false }

    var health: Health {
        guard online, let s = status else { return .offline }
        switch s.guard_.state {
        case "alarm", "acted": return .alarm
        case "warn", "snoozed": return .warn
        default:
            if let b = s.battery, !b.plugged, b.percent < 20 { return .warn }
            return .ok
        }
    }
}

@MainActor
final class Store: ObservableObject {
    static let shared = Store()

    @Published var machines: [MachineState] = []
    @Published var notifyGames = true
    private var timer: Timer?
    private var prev: [String: Status] = [:]
    private var offlineNotified: Set<String> = []
    private var warnNotifiedAt: [String: Date] = [:]
    private let warnCooldown: TimeInterval = 30 * 60
    private let maxSamples = 450 // 2 sn aralıkla 15 dakika

    static var supportDir: URL {
        let u = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Gozcu")
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }
    static var configURL: URL { supportDir.appendingPathComponent("makineler.json") }

    init() {
        load()
        start()
    }

    func load() {
        let decoded = (try? Data(contentsOf: Self.configURL)).flatMap { try? JSONDecoder().decode([MachineConfig].self, from: $0) } ?? []
        machines = decoded.map { MachineState(config: $0) }
    }

    func save(_ configs: [MachineConfig]) {
        if let data = try? JSONEncoder().encode(configs) {
            try? data.write(to: Self.configURL, options: .atomic)
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: Self.configURL.path)
        }
        load()
    }

    func start() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.pollAll() }
        }
        pollAll()
    }

    var worst: Health { machines.map(\.health).max() ?? .ok }

    private func pollAll() {
        for m in machines { Task { await poll(m) } }
    }

    private func request(_ m: MachineState, path: String, method: String = "GET", body: [String: Any]? = nil) -> URLRequest? {
        guard let url = URL(string: m.config.url + path) else { return nil }
        var r = URLRequest(url: url, timeoutInterval: method == "GET" ? 4 : 20)
        r.httpMethod = method
        r.setValue("Bearer \(m.config.token)", forHTTPHeaderField: "Authorization")
        if let body {
            r.httpBody = try? JSONSerialization.data(withJSONObject: body)
            r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        return r
    }

    private func poll(_ m: MachineState) async {
        guard let req = request(m, path: "/v1/status") else { return }
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard (resp as? HTTPURLResponse)?.statusCode == 200 else {
                m.error = "Ajan yanıtı: \((resp as? HTTPURLResponse)?.statusCode ?? 0)"
                return
            }
            let dec = JSONDecoder()
            dec.keyDecodingStrategy = .convertFromSnakeCase
            let s = try dec.decode(Status.self, from: data)
            m.status = s
            m.lastSeen = Date()
            m.error = nil
            offlineNotified.remove(m.id)
            m.history.append(Sample(date: Date(), cpu: s.cpu.usage, cpuTemp: s.cpu.temp, gpu: s.gpu?.util, gpuTemp: s.gpu?.temp))
            if m.history.count > maxSamples { m.history.removeFirst(m.history.count - maxSamples) }
            react(m, s)
            prev[m.id] = s
        } catch {
            m.error = error.localizedDescription
            if let seen = m.lastSeen, Date().timeIntervalSince(seen) > 60, !offlineNotified.contains(m.id) {
                offlineNotified.insert(m.id)
                Notifier.send(id: "offline-\(m.id)", title: "\(m.config.name) çevrimdışı", body: "1 dakikadır yanıt vermiyor (kapalı, uykuda ya da Tailscale bağlı değil).")
            }
        }
    }

    /// Durum değişikliklerine göre bildirim gönderir.
    private func react(_ m: MachineState, _ s: Status) {
        let old = prev[m.id]
        let name = m.config.name
        let g = s.guard_
        if g.state == "alarm", old?.guard_.state != "alarm" {
            let mins = max(1, ((g.deadline ?? 0) - s.time) / 60)
            Notifier.alarm(machine: name, title: "🔥 \(name): \(g.reason ?? "Aşırı ısınma")",
                           body: g.autoStopAi ? "\(mins) dk içinde müdahale etmezsen yapay zekâ işleri durdurulacak. Oyun ve diğer programlar etkilenmez." : "Isı tehlikeli seviyede.")
        }
        if g.state == "acted", old?.guard_.state != "acted", let msg = g.message {
            Notifier.send(id: "acted-\(name)", title: "🛑 \(name): yapay zekâ durduruldu", body: msg)
        }
        // Oyunda ısınma beklenir; uyarı yalnız oyun yokken ve 30 dakikada en fazla bir kez gider.
        // Tehlike alarmı bundan etkilenmez.
        if g.state == "warn", old?.guard_.state == "ok", s.game == nil,
           warnNotifiedAt[m.id].map({ Date().timeIntervalSince($0) > warnCooldown }) ?? true {
            warnNotifiedAt[m.id] = Date()
            Notifier.send(id: "warn-\(name)", title: "🌡️ \(name) ısınıyor", body: g.reason ?? "")
        }
        if let b = s.battery, let ob = old?.battery {
            if ob.plugged && !b.plugged {
                Notifier.send(id: "unplug-\(name)", title: "🔌 \(name) fişten çıktı", body: "Pil %\(Int(b.percent)), artık pilden çalışıyor.")
            } else if !ob.plugged && b.plugged {
                Notifier.send(id: "plug-\(name)", title: "🔌 \(name) fişe takıldı", body: "Pil %\(Int(b.percent)).")
            }
            if !b.plugged && b.percent <= 15 && ob.percent > 15 {
                Notifier.send(id: "lowbat-\(name)", title: "🪫 \(name) pili azaldı", body: "%\(Int(b.percent)) kaldı, fişe tak.")
            }
        }
        if notifyGames, old != nil, s.game != old?.game {
            if let game = s.game {
                Notifier.send(id: "game-\(name)", title: "🎮 \(name): oyun açıldı", body: "\(game) çalışıyor. Ağır AI işleri ısıyı artırabilir.")
            } else if let og = old?.game {
                Notifier.send(id: "game-\(name)", title: "🎮 \(name): oyun kapandı", body: "\(og) kapandı.")
            }
        }
        for d in s.disks where d.total > 0 && d.free / d.total < 0.07 {
            if !(old?.disks.contains { $0.mount == d.mount && $0.free / $0.total < 0.07 } ?? false) {
                Notifier.send(id: "disk-\(name)-\(d.mount)", title: "💾 \(name) diski doluyor", body: "\(d.mount) üzerinde %\(Int(d.free / d.total * 100)) boş yer kaldı.")
            }
        }
    }

    // MARK: - Eylemler

    func machine(named name: String) -> MachineState? { machines.first { $0.config.name == name } }

    @discardableResult
    func action(_ m: MachineState, _ body: [String: Any]) async -> String {
        guard let req = request(m, path: "/v1/action", method: "POST", body: body) else { return "Geçersiz adres" }
        do {
            let (data, _) = try await URLSession.shared.data(for: req)
            let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            let msg = (obj?["message"] as? String) ?? (obj?["error"] as? String) ?? "Tamam"
            m.lastAction = msg
            await poll(m)
            return msg
        } catch {
            m.lastAction = "Hata: \(error.localizedDescription)"
            return m.lastAction!
        }
    }
}
