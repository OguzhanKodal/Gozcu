import Charts
import SwiftUI

/// Genel bakıştaki makine kartı.
struct MachineSummaryCard: View {
    @ObservedObject var m: MachineState
    var onOpen: () -> Void

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                MachineHeader(m: m)
                if let s = m.status, m.online {
                    HStack(spacing: 18) {
                        Ring(value: s.cpu.usage, label: "İşlemci", text: Fmt.pct(s.cpu.usage), color: Theme.load(s.cpu.usage), size: 74)
                        Ring(value: s.cpu.temp, max: 105, label: "İşlemci ısısı", text: Fmt.temp(s.cpu.temp), color: Theme.temp(s.cpu.temp), size: 74)
                        if let g = s.gpu {
                            Ring(value: g.util, label: "Ekran kartı", text: Fmt.pct(g.util), color: Theme.gpu, size: 74)
                            Ring(value: g.temp, max: 100, label: "GPU ısısı", text: Fmt.temp(g.temp), color: Theme.temp(g.temp), size: 74)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    MiniChart(history: m.history)
                    HStack(spacing: 8) {
                        if let b = s.battery { BatteryPill(b: b) }
                        Pill(icon: "memorychip", text: "\(Fmt.bytes(s.mem.used)) / \(Fmt.bytes(s.mem.total))")
                        if !s.fans.isEmpty {
                            Pill(icon: "fan", text: s.fans.prefix(2).map { "\(Int($0.value))" }.joined(separator: " · ") + " rpm")
                        }
                    }
                } else {
                    OfflineView(m: m)
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onOpen)
    }
}

struct MachineHeader: View {
    @ObservedObject var m: MachineState
    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: m.config.icon)
                .font(.title2)
                .foregroundStyle(Theme.health(m.health))
                .frame(width: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(m.config.name).font(.title3.weight(.semibold))
                Text(m.online ? "\(m.status?.os ?? "") · açık \(Fmt.uptime(m.status?.uptimeSecs ?? 0))" : "Çevrimdışı")
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            if let s = m.status, m.online {
                if let game = s.game { Pill(icon: "gamecontroller.fill", text: game.replacingOccurrences(of: ".exe", with: ""), color: Theme.warn) }
                if let model = s.ai.models.first {
                    Pill(icon: "sparkles", text: model.name, color: Theme.gpu)
                }
            }
            Circle().fill(Theme.health(m.health)).frame(width: 10, height: 10)
                .shadow(color: Theme.health(m.health), radius: 4)
        }
    }
}

struct OfflineView: View {
    @ObservedObject var m: MachineState
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Bağlanılamıyor", systemImage: "wifi.slash").foregroundStyle(.secondary)
            if let e = m.error { Text(e).font(.caption).foregroundStyle(.tertiary).lineLimit(2) }
            if let seen = m.lastSeen { Text("Son görülme: \(seen.formatted(date: .omitted, time: .shortened))").font(.caption).foregroundStyle(.tertiary) }
        }
        .frame(maxWidth: .infinity, minHeight: 120, alignment: .leading)
    }
}

struct BatteryPill: View {
    var b: Battery
    var body: some View {
        let icon = b.state == "charging" ? "battery.100.bolt" : b.percent > 60 ? "battery.75" : b.percent > 25 ? "battery.50" : "battery.25"
        let color: Color = !b.plugged && b.percent < 20 ? Theme.bad : b.plugged ? Theme.good : Theme.warn
        let tail: String = {
            switch b.state {
            case "charging": return "şarj oluyor"
            case "full": return "dolu"
            case "discharging": return b.minutesLeft.map { "\($0 / 60) sa \($0 % 60) dk" } ?? "pilde"
            default: return b.plugged ? "fişte, şarj yok" : "pilde"
            }
        }()
        Pill(icon: icon, text: "%\(Int(b.percent)) · \(tail)", color: color)
    }
}

struct MiniChart: View {
    var history: [Sample]
    var body: some View {
        Chart {
            ForEach(history) { s in
                if let t = s.cpuTemp {
                    LineMark(x: .value("Zaman", s.date), y: .value("°C", t), series: .value("Seri", "İşlemci"))
                        .foregroundStyle(Theme.cpu)
                }
                if let t = s.gpuTemp {
                    LineMark(x: .value("Zaman", s.date), y: .value("°C", t), series: .value("Seri", "GPU"))
                        .foregroundStyle(Theme.gpu)
                }
            }
        }
        .chartYScale(domain: 20...105)
        .chartXAxis(.hidden)
        .chartYAxis { AxisMarks(position: .trailing, values: [40, 70, 100]) { _ in AxisGridLine().foregroundStyle(Color.white.opacity(0.06)); AxisValueLabel() } }
        .frame(height: 64)
    }
}

/// Bir makinenin ayrıntılı sayfası.
struct MachineDetail: View {
    @ObservedObject var m: MachineState
    @State private var killTarget: Proc?
    @State private var gpuLimit: Double = 0
    @State private var busy = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Card { MachineHeader(m: m) }
                if let s = m.status, m.online {
                    GuardBanner(m: m, s: s)
                    HStack(alignment: .top, spacing: 16) {
                        Card {
                            VStack(alignment: .leading, spacing: 12) {
                                SectionTitle(text: "Anlık", icon: "gauge.with.dots.needle.67percent")
                                HStack(spacing: 20) {
                                    Ring(value: s.cpu.usage, label: "İşlemci", text: Fmt.pct(s.cpu.usage), color: Theme.load(s.cpu.usage))
                                    Ring(value: s.cpu.temp, max: 105, label: "İşlemci ısısı", text: Fmt.temp(s.cpu.temp), color: Theme.temp(s.cpu.temp))
                                    if let g = s.gpu {
                                        Ring(value: g.util, label: "Ekran kartı", text: Fmt.pct(g.util), color: Theme.gpu)
                                        Ring(value: g.temp, max: 100, label: "GPU ısısı", text: Fmt.temp(g.temp), color: Theme.temp(g.temp))
                                    }
                                    Ring(value: s.mem.used / s.mem.total * 100, label: "Bellek", text: Fmt.pct(s.mem.used / s.mem.total * 100), color: Theme.load(s.mem.used / s.mem.total * 100))
                                }
                                .frame(maxWidth: .infinity)
                            }
                        }
                    }
                    Card {
                        VStack(alignment: .leading, spacing: 10) {
                            SectionTitle(text: "Son 15 dakika", icon: "chart.xyaxis.line")
                            HistoryChart(history: m.history)
                        }
                    }
                    HStack(alignment: .top, spacing: 16) {
                        hardware(s)
                        powerAndActions(s)
                    }
                    processes(s)
                    if !s.notes.isEmpty {
                        ForEach(s.notes, id: \.self) { Label($0, systemImage: "info.circle").font(.caption).foregroundStyle(.secondary) }
                    }
                } else {
                    Card { OfflineView(m: m) }
                }
            }
            .padding(20)
        }
        .confirmationDialog("\(killTarget?.name ?? "") kapatılsın mı?", isPresented: Binding(get: { killTarget != nil }, set: { if !$0 { killTarget = nil } })) {
            Button("Kapat", role: .destructive) {
                if let p = killTarget { Task { await Store.shared.action(m, ["action": "kill", "pid": p.pid]) } }
            }
        } message: {
            Text("Bu program o makinede hemen kapanır. Kaydedilmemiş iş kaybolabilir.")
        }
    }

    private func hardware(_ s: Status) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                SectionTitle(text: "Donanım", icon: "cpu")
                StatRow(icon: "cpu", title: s.cpu.model.isEmpty ? "İşlemci" : s.cpu.model, value: "\(s.cpu.cores) çekirdek")
                if let l = s.cpu.loadAvg { StatRow(icon: "chart.bar", title: "Yük ortalaması", value: l.map { String(format: "%.1f", $0) }.joined(separator: " · ")) }
                if let g = s.gpu {
                    Divider().opacity(0.3)
                    StatRow(icon: "rectangle.3.group", title: g.name, value: Fmt.temp(g.temp), color: Theme.temp(g.temp))
                    if let u = g.memUsedMb, let t = g.memTotalMb {
                        StatRow(icon: "memorychip", title: "GPU belleği", value: "\(Fmt.bytes(u * 1_048_576)) / \(Fmt.bytes(t * 1_048_576))")
                        Bar(value: u / t, color: Theme.gpu)
                    }
                    if let p = g.powerW { StatRow(icon: "bolt", title: "GPU gücü", value: String(format: "%.0f W", p) + (g.powerLimitW.map { String(format: " / %.0f W", $0) } ?? "")) }
                    if let f = g.fanPct { StatRow(icon: "fan", title: "GPU fanı", value: "%\(Int(f))") }
                }
                if !s.fans.isEmpty {
                    Divider().opacity(0.3)
                    ForEach(s.fans, id: \.self) { f in StatRow(icon: "fan", title: f.label, value: "\(Int(f.value)) rpm") }
                }
                Divider().opacity(0.3)
                ForEach(s.disks, id: \.self) { d in
                    StatRow(icon: "internaldrive", title: d.mount, value: "\(Fmt.bytes(d.free)) boş")
                    Bar(value: 1 - d.free / max(d.total, 1), color: d.free / max(d.total, 1) < 0.1 ? Theme.bad : Theme.cpu)
                }
                StatRow(icon: "arrow.down.arrow.up", title: "Ağ", value: "↓ \(Fmt.rate(s.net.rxBps))  ↑ \(Fmt.rate(s.net.txBps))")
            }
        }
    }

    private func powerAndActions(_ s: Status) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                if let b = s.battery {
                    SectionTitle(text: "Güç", icon: "bolt.batteryblock")
                    HStack {
                        Ring(value: b.percent, label: b.plugged ? "Fişte" : "Pilde", text: "%\(Int(b.percent))", color: b.plugged ? Theme.good : (b.percent < 20 ? Theme.bad : Theme.warn), size: 78)
                        VStack(alignment: .leading, spacing: 6) {
                            BatteryPill(b: b)
                            if let h = b.healthPct { StatRow(icon: "heart", title: "Pil sağlığı", value: "%\(Int(h))") }
                            if let c = b.cycles { StatRow(icon: "arrow.triangle.2.circlepath", title: "Döngü", value: "\(c)") }
                            if let p = b.powerW, p > 0.5 { StatRow(icon: "bolt", title: "Güç akışı", value: String(format: "%.1f W", p)) }
                        }
                    }
                    Divider().opacity(0.3)
                }
                SectionTitle(text: "Müdahale", icon: "hand.raised")
                HStack {
                    Button { run(["action": "stop_ai"]) } label: { Label("AI'yı durdur", systemImage: "stop.circle") }
                        .buttonStyle(.borderedProminent).tint(Theme.bad)
                    if s.os.lowercased().contains("windows") {
                        Button { run(["action": "start_ai"]) } label: { Label("AI'yı başlat", systemImage: "play.circle") }
                    }
                    Button { run(["action": "snooze", "minutes": 15]) } label: { Label("15 dk ertele", systemImage: "bell.slash") }
                }
                .disabled(busy)
                if let g = s.gpu, let maxW = g.powerMaxW, maxW > 60, s.os.lowercased().contains("windows") {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("GPU güç sınırı: \(Int(gpuLimit == 0 ? (g.powerLimitW ?? maxW) : gpuLimit)) W").font(.callout)
                        HStack {
                            Slider(value: $gpuLimit, in: (maxW * 0.4).rounded()...maxW, step: 5)
                            Button("Uygula") { run(["action": "gpu_power_limit", "watts": Int(gpuLimit)]) }.disabled(gpuLimit == 0)
                        }
                        Text("Düşük sınır ısıyı azaltır, oyunda kare hızı biraz düşer. Yeniden başlatınca sıfırlanır.").font(.caption2).foregroundStyle(.tertiary)
                    }
                    .onAppear { gpuLimit = g.powerLimitW ?? maxW }
                }
                if let a = m.lastAction { Text(a).font(.caption).foregroundStyle(.secondary) }
            }
        }
    }

    private func processes(_ s: Status) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                SectionTitle(text: "En çok yük bindiren programlar", icon: "list.bullet.rectangle")
                ForEach(s.procs, id: \.pid) { p in
                    HStack {
                        Text(p.name).lineLimit(1)
                        if s.game == p.name { Image(systemName: "gamecontroller.fill").foregroundStyle(Theme.warn) }
                        Spacer()
                        Text(String(format: "%%%.1f", p.cpu)).monospacedDigit().foregroundStyle(Theme.load(p.cpu))
                            .frame(width: 60, alignment: .trailing)
                        Text(Fmt.bytes(p.mem)).monospacedDigit().foregroundStyle(.secondary).frame(width: 80, alignment: .trailing)
                        Button { killTarget = p } label: { Image(systemName: "xmark.circle") }.buttonStyle(.borderless).help("Kapat")
                    }
                    .font(.callout)
                }
                if !s.gpuProcs.isEmpty {
                    Divider().opacity(0.3)
                    Text("Ekran kartını kullananlar").font(.caption).foregroundStyle(.secondary)
                    ForEach(s.gpuProcs, id: \.pid) { g in
                        HStack {
                            Text(g.name).lineLimit(1)
                            Spacer()
                            Text(g.sm.map { "%\(Int($0))" } ?? "—").monospacedDigit().foregroundStyle(Theme.gpu)
                        }
                        .font(.callout)
                    }
                }
            }
        }
    }

    private func run(_ body: [String: Any]) {
        busy = true
        Task {
            await Store.shared.action(m, body)
            busy = false
        }
    }
}

struct GuardBanner: View {
    @ObservedObject var m: MachineState
    var s: Status

    var body: some View {
        let g = s.guard_
        if g.state != "ok" {
            let color: Color = g.state == "alarm" || g.state == "acted" ? Theme.bad : Theme.warn
            HStack(spacing: 12) {
                Image(systemName: g.state == "acted" ? "stop.circle.fill" : "flame.fill").font(.title2).foregroundStyle(color)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title(g)).font(.headline)
                    if let msg = g.message { Text(msg).font(.callout).foregroundStyle(.secondary) }
                }
                Spacer()
                if g.state == "alarm" {
                    if let d = g.deadline {
                        Text(Date(timeIntervalSince1970: TimeInterval(d)), style: .timer)
                            .font(.title3.monospacedDigit().weight(.bold)).foregroundStyle(color)
                    }
                    Button("15 dk ertele") { Task { await Store.shared.action(m, ["action": "snooze", "minutes": 15]) } }
                    Button("Şimdi durdur") { Task { await Store.shared.action(m, ["action": "stop_ai"]) } }
                        .buttonStyle(.borderedProminent).tint(Theme.bad)
                }
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 16).fill(color.opacity(0.13)))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(color.opacity(0.4)))
        }
    }

    private func title(_ g: GuardView) -> String {
        let r = g.reason ?? "Isı yüksek"
        switch g.state {
        case "alarm": return "Tehlikeli ısı: \(r) — geri sayım başladı"
        case "acted": return "Yapay zekâ durduruldu"
        case "snoozed": return "Ertelendi: \(r)"
        default: return "Isınıyor: \(r)"
        }
    }
}

struct HistoryChart: View {
    var history: [Sample]
    var body: some View {
        Chart {
            ForEach(history) { s in
                if let t = s.cpuTemp {
                    LineMark(x: .value("Zaman", s.date), y: .value("Değer", t), series: .value("Seri", "İşlemci °C"))
                        .foregroundStyle(by: .value("Seri", "İşlemci °C"))
                }
                if let t = s.gpuTemp {
                    LineMark(x: .value("Zaman", s.date), y: .value("Değer", t), series: .value("Seri", "GPU °C"))
                        .foregroundStyle(by: .value("Seri", "GPU °C"))
                }
                AreaMark(x: .value("Zaman", s.date), y: .value("Değer", s.cpu), series: .value("Seri", "İşlemci %"))
                    .foregroundStyle(by: .value("Seri", "İşlemci %")).opacity(0.25)
                if let g = s.gpu {
                    AreaMark(x: .value("Zaman", s.date), y: .value("Değer", g), series: .value("Seri", "GPU %"))
                        .foregroundStyle(by: .value("Seri", "GPU %")).opacity(0.25)
                }
            }
        }
        .chartForegroundStyleScale(["İşlemci °C": Theme.cpu, "GPU °C": Theme.gpu, "İşlemci %": Theme.cpu.opacity(0.6), "GPU %": Theme.gpu.opacity(0.6)])
        .chartYScale(domain: 0...105)
        .chartYAxis { AxisMarks(position: .trailing) { _ in AxisGridLine().foregroundStyle(Color.white.opacity(0.06)); AxisValueLabel() } }
        .chartXAxis { AxisMarks(values: .stride(by: .minute, count: 3)) { _ in AxisValueLabel(format: .dateTime.hour().minute()) } }
        .frame(height: 180)
    }
}
