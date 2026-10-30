import Charts
import SwiftUI

enum Page: Hashable {
    case overview, ai, machine(String)
}

struct Dashboard: View {
    @ObservedObject var store = Store.shared
    @State private var page: Page? = .overview

    var body: some View {
        NavigationSplitView {
            List(selection: $page) {
                Label("Genel bakış", systemImage: "square.grid.2x2").tag(Page.overview)
                Label("Yapay zekâ", systemImage: "sparkles").tag(Page.ai)
                Section("Makineler") {
                    ForEach(store.machines) { m in
                        SidebarRow(m: m).tag(Page.machine(m.config.name))
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 190, ideal: 210)
        } detail: {
            ZStack {
                Theme.bg.ignoresSafeArea()
                switch page ?? .overview {
                case .overview: Overview(page: $page)
                case .ai: AIView()
                case .machine(let name):
                    if let m = store.machine(named: name) { MachineDetail(m: m).id(name) }
                }
            }
        }
        .preferredColorScheme(.dark)
        .frame(minWidth: 980, minHeight: 680)
    }
}

struct SidebarRow: View {
    @ObservedObject var m: MachineState
    var body: some View {
        HStack {
            Label(m.config.name, systemImage: m.config.icon)
            Spacer()
            if let t = m.status?.hottest, m.online {
                Text(Fmt.temp(t)).font(.caption.monospacedDigit()).foregroundStyle(Theme.temp(t))
            }
            Circle().fill(Theme.health(m.health)).frame(width: 8, height: 8)
        }
    }
}

struct Overview: View {
    @ObservedObject var store = Store.shared
    @Binding var page: Page?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Gözcü").font(.largeTitle.weight(.bold))
                        Text(subtitle).foregroundStyle(.secondary)
                    }
                    Spacer()
                    TokenTotal()
                }
                ForEach(store.machines.filter { $0.status?.guard_.state == "alarm" }) { m in
                    if let s = m.status { GuardBanner(m: m, s: s) }
                }
                if store.machines.isEmpty {
                    Card { Text("Makine eklenmemiş. Ayarlar'dan (⌘,) ekleyebilirsin.").foregroundStyle(.secondary) }
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 430), spacing: 16)], spacing: 16) {
                    ForEach(store.machines) { m in
                        MachineSummaryCard(m: m) { page = .machine(m.config.name) }
                    }
                }
            }
            .padding(24)
        }
    }

    private var subtitle: String {
        let online = store.machines.filter(\.online).count
        let games = store.machines.compactMap { $0.status?.game }.count
        var s = "\(online)/\(store.machines.count) makine çevrimiçi"
        if games > 0 { s += " · 🎮 oyun açık" }
        switch store.worst {
        case .alarm: s += " · 🔥 alarm var"
        case .warn: s += " · dikkat"
        default: break
        }
        return s
    }
}

struct TokenTotal: View {
    @ObservedObject var store = Store.shared
    var body: some View {
        let all = store.machines.compactMap { $0.status?.ai.tokens }.flatMap { $0 }
        let total = all.reduce(0) { $0 + $1.total }
        VStack(alignment: .trailing, spacing: 2) {
            Text(Fmt.tokens(total)).font(.title.weight(.bold).monospacedDigit())
            Text("bugünkü token").font(.caption).foregroundStyle(.secondary)
        }
    }
}

struct AIView: View {
    @ObservedObject var store = Store.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Yapay zekâ").font(.largeTitle.weight(.bold))
                Card {
                    VStack(alignment: .leading, spacing: 12) {
                        SectionTitle(text: "Bugünkü token kullanımı", icon: "number")
                        let rows = tokenRows
                        if rows.isEmpty {
                            Text("Bugün henüz kullanım yok.").foregroundStyle(.secondary)
                        } else {
                            Chart(rows, id: \.id) { r in
                                BarMark(x: .value("Token", r.value), y: .value("Kaynak", r.label))
                                    .foregroundStyle(by: .value("Tür", r.kind))
                            }
                            .chartForegroundStyleScale(["Girdi": Theme.cpu, "Çıktı": Theme.good, "Önbellek okuma": Theme.gpu.opacity(0.6), "Önbellek yazma": Theme.warn])
                            .chartXAxis { AxisMarks { v in AxisGridLine().foregroundStyle(Color.white.opacity(0.06)); AxisValueLabel { if let d = v.as(Double.self) { Text(Fmt.tokens(d)) } } } }
                            .frame(height: CGFloat(max(1, Set(rows.map(\.label)).count)) * 44 + 30)
                            Divider().opacity(0.3)
                            ForEach(store.machines) { m in
                                ForEach(m.status?.ai.tokens ?? [], id: \.tool) { t in
                                    HStack {
                                        Text("\(m.config.name) · \(t.tool)").fontWeight(.medium)
                                        if let model = t.topModel { Text(model).font(.caption).foregroundStyle(.secondary) }
                                        Spacer()
                                        Text("\(t.messages) yanıt").foregroundStyle(.secondary)
                                        Text("çıktı \(Fmt.tokens(t.output))").monospacedDigit().foregroundStyle(Theme.good)
                                        Text("toplam \(Fmt.tokens(t.total))").monospacedDigit().frame(width: 110, alignment: .trailing)
                                    }
                                    .font(.callout)
                                }
                            }
                        }
                    }
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 16)], spacing: 16) {
                    ForEach(store.machines) { m in AIMachineCard(m: m) }
                }
                Text("Token sayıları her dakika güncellenir. Claude Code ve opencode yerel kayıtlarından okunur; Ollama'nın doğrudan kullanımı sayılmaz.")
                    .font(.caption).foregroundStyle(.tertiary)
            }
            .padding(24)
        }
    }

    struct Row { let id = UUID(); let label: String; let kind: String; let value: Double }

    private var tokenRows: [Row] {
        store.machines.flatMap { m in
            (m.status?.ai.tokens ?? []).flatMap { t -> [Row] in
                let label = "\(m.config.name) · \(t.tool)"
                return [Row(label: label, kind: "Girdi", value: t.input), Row(label: label, kind: "Çıktı", value: t.output),
                        Row(label: label, kind: "Önbellek okuma", value: t.cacheRead), Row(label: label, kind: "Önbellek yazma", value: t.cacheWrite)]
            }
        }
    }
}

struct AIMachineCard: View {
    @ObservedObject var m: MachineState
    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label(m.config.name, systemImage: m.config.icon).font(.headline)
                    Spacer()
                    if let s = m.status, m.online {
                        Pill(icon: s.ai.ollamaUp ? "checkmark.circle" : "xmark.circle", text: s.ai.ollamaUp ? "Ollama açık" : "Ollama kapalı",
                             color: s.ai.ollamaUp ? Theme.good : .secondary)
                    }
                }
                if let s = m.status, m.online {
                    if s.ai.models.isEmpty {
                        Text("Yüklü model yok").foregroundStyle(.secondary).font(.callout)
                    }
                    ForEach(s.ai.models, id: \.name) { model in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Image(systemName: "cube.fill").foregroundStyle(Theme.gpu)
                                Text(model.name).fontWeight(.medium)
                                Spacer()
                                Text("\(Fmt.bytes(model.vramMb * 1_048_576)) VRAM").monospacedDigit().foregroundStyle(.secondary)
                            }
                            Bar(value: model.sizeMb > 0 ? model.vramMb / model.sizeMb : 0, color: Theme.gpu)
                            Text(model.vramMb >= model.sizeMb * 0.99 ? "Tamamen ekran kartında" : "Kısmen işlemcide (yavaş)")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    if !s.ai.procs.isEmpty {
                        HStack { ForEach(s.ai.procs, id: \.self) { Pill(icon: "terminal", text: $0) } }
                    }
                    if let g = s.gpu, let u = g.memUsedMb, let t = g.memTotalMb {
                        StatRow(icon: "memorychip", title: "Ekran kartı belleği", value: "\(Int(u / t * 100))%")
                        Bar(value: u / t, color: Theme.gpu)
                    }
                    if m.config.name != "Mac" {
                        Button { Task { await Store.shared.action(m, ["action": "stop_ai"]) } } label: { Label("AI'yı durdur", systemImage: "stop.circle") }
                    }
                } else {
                    Text("Çevrimdışı").foregroundStyle(.secondary)
                }
            }
        }
    }
}
