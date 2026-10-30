import SwiftUI

enum Theme {
    static let bg = LinearGradient(colors: [Color(red: 0.06, green: 0.07, blue: 0.10), Color(red: 0.09, green: 0.08, blue: 0.14)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
    static let card = Color.white.opacity(0.05)
    static let stroke = Color.white.opacity(0.08)
    static let cpu = Color(red: 0.36, green: 0.67, blue: 1.0)
    static let gpu = Color(red: 0.62, green: 0.45, blue: 1.0)
    static let good = Color(red: 0.30, green: 0.85, blue: 0.55)
    static let warn = Color(red: 1.0, green: 0.72, blue: 0.25)
    static let bad = Color(red: 1.0, green: 0.35, blue: 0.35)

    static func temp(_ t: Double?) -> Color {
        guard let t else { return .secondary }
        if t >= 87 { return bad }
        if t >= 78 { return warn }
        return good
    }

    static func load(_ v: Double?) -> Color {
        guard let v else { return .secondary }
        if v >= 90 { return bad }
        if v >= 70 { return warn }
        return cpu
    }

    static func health(_ h: Health) -> Color {
        switch h {
        case .ok: return good
        case .warn: return warn
        case .alarm: return bad
        case .offline: return .gray
        }
    }
}

enum Fmt {
    static func bytes(_ b: Double) -> String {
        let f = ByteCountFormatter()
        f.countStyle = .binary
        return f.string(fromByteCount: Int64(b))
    }
    static func rate(_ bps: Double) -> String { bytes(bps) + "/s" }
    static func tokens(_ n: Double) -> String {
        if n >= 1_000_000 { return String(format: "%.1f M", n / 1_000_000) }
        if n >= 1_000 { return String(format: "%.1f B", n / 1_000) }
        return "\(Int(n))"
    }
    static func uptime(_ s: Int) -> String {
        let d = s / 86400, h = (s % 86400) / 3600, m = (s % 3600) / 60
        if d > 0 { return "\(d) g \(h) sa" }
        if h > 0 { return "\(h) sa \(m) dk" }
        return "\(m) dk"
    }
    static func temp(_ t: Double?) -> String { t.map { "\(Int($0.rounded()))°" } ?? "—" }
    static func pct(_ v: Double?) -> String { v.map { "%\(Int($0.rounded()))" } ?? "—" }
}

struct Card<Content: View>: View {
    var padding: CGFloat = 16
    @ViewBuilder var content: Content
    var body: some View {
        content
            .padding(padding)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.card))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Theme.stroke))
    }
}

/// Halka gösterge: değer 0–max, ortada büyük sayı.
struct Ring: View {
    var value: Double?
    var max: Double = 100
    var label: String
    var text: String
    var color: Color
    var size: CGFloat = 86

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle().stroke(Color.white.opacity(0.07), lineWidth: 9)
                Circle()
                    .trim(from: 0, to: CGFloat(min(1, (value ?? 0) / max)))
                    .stroke(AngularGradient(colors: [color.opacity(0.55), color], center: .center),
                            style: StrokeStyle(lineWidth: 9, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .shadow(color: color.opacity(0.5), radius: 6)
                    .animation(.easeOut(duration: 0.6), value: value)
                Text(text)
                    .font(.system(size: size * 0.22, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }
            .frame(width: size, height: size)
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
    }
}

struct Pill: View {
    var icon: String
    var text: String
    var color: Color = .secondary
    var body: some View {
        Label(text, systemImage: icon)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 9).padding(.vertical, 4)
            .background(Capsule().fill(color.opacity(0.15)))
            .foregroundStyle(color)
    }
}

struct Bar: View {
    var value: Double
    var color: Color
    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.07))
                Capsule().fill(color).frame(width: g.size.width * CGFloat(min(1, max(0, value))))
                    .animation(.easeOut(duration: 0.5), value: value)
            }
        }
        .frame(height: 6)
    }
}

struct StatRow: View {
    var icon: String
    var title: String
    var value: String
    var color: Color = .primary
    var body: some View {
        HStack {
            Image(systemName: icon).foregroundStyle(.secondary).frame(width: 18)
            Text(title).foregroundStyle(.secondary)
            Spacer()
            Text(value).foregroundStyle(color).monospacedDigit().fontWeight(.medium)
        }
        .font(.callout)
    }
}

struct SectionTitle: View {
    var text: String
    var icon: String
    var body: some View {
        Label(text, systemImage: icon).font(.headline).foregroundStyle(.white.opacity(0.85))
    }
}
