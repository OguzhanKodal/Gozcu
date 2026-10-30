import Foundation

// Ajanın /v1/status yanıtı. Alan adları snake_case'ten otomatik çevrilir.

struct Status: Codable {
    var name: String = ""
    var os: String = ""
    var host: String = ""
    var agentVersion: String = ""
    var time: Int = 0
    var uptimeSecs: Int = 0
    var cpu: Cpu = Cpu()
    var mem: Mem = Mem()
    var gpus: [Gpu] = []
    var temps: [Reading] = []
    var fans: [Reading] = []
    var battery: Battery?
    var disks: [Disk] = []
    var net: Net = Net()
    var procs: [Proc] = []
    var gpuProcs: [GpuProc] = []
    var game: String?
    var ai: Ai = Ai()
    var guard_: GuardView = GuardView()
    var notes: [String] = []

    enum CodingKeys: String, CodingKey {
        case name, os, host, agentVersion, time, uptimeSecs, cpu, mem, gpus, temps, fans, battery, disks, net, procs, gpuProcs, game, ai, notes
        case guard_ = "guard"
    }

    var gpu: Gpu? { gpus.first }
    var hottest: Double? { [cpu.temp, gpu?.temp].compactMap { $0 }.max() }
}

struct Cpu: Codable { var usage: Double = 0; var temp: Double?; var cores: Int = 0; var model: String = ""; var loadAvg: [Double]? }
struct Mem: Codable { var used: Double = 0; var total: Double = 1; var swapUsed: Double = 0; var swapTotal: Double = 0 }
struct Gpu: Codable {
    var name: String = ""
    var temp: Double?
    var util: Double?
    var memUsedMb: Double?
    var memTotalMb: Double?
    var powerW: Double?
    var powerLimitW: Double?
    var powerMaxW: Double?
    var fanPct: Double?
}
struct Reading: Codable, Hashable { var label: String; var value: Double }
struct Battery: Codable {
    var percent: Double
    var state: String
    var plugged: Bool
    var powerW: Double?
    var healthPct: Double?
    var cycles: Int?
    var minutesLeft: Int?
}
struct Disk: Codable, Hashable { var mount: String; var total: Double; var free: Double }
struct Net: Codable { var rxBps: Double = 0; var txBps: Double = 0 }
struct Proc: Codable, Hashable { var pid: Int; var name: String; var cpu: Double; var mem: Double }
struct GpuProc: Codable, Hashable { var pid: Int; var name: String; var sm: Double?; var memMb: Double? }
struct Ai: Codable {
    var ollamaUp: Bool = false
    var models: [LoadedModel] = []
    var procs: [String] = []
    var tokens: [TokenUsage] = []
}
struct LoadedModel: Codable, Hashable { var name: String; var vramMb: Double; var sizeMb: Double; var context: Int? }
struct TokenUsage: Codable, Hashable {
    var tool: String
    var input: Double
    var output: Double
    var cacheRead: Double
    var cacheWrite: Double
    var messages: Int
    var topModel: String?
    var total: Double { input + output + cacheRead + cacheWrite }
}
struct GuardView: Codable {
    var state: String = "ok"
    var reason: String?
    var since: Int?
    var deadline: Int?
    var snoozedUntil: Int?
    var actedAt: Int?
    var message: String?
    var autoStopAi: Bool = true
    var graceSecs: Int = 180
}

/// Uygulama ayarındaki bir makine.
struct MachineConfig: Codable, Identifiable, Hashable {
    var id: String { name }
    var name: String
    var url: String
    var token: String
    /// SF Symbol adı
    var icon: String
}

/// Grafik için bir örnek.
struct Sample: Identifiable {
    let id = UUID()
    let date: Date
    let cpu: Double
    let cpuTemp: Double?
    let gpu: Double?
    let gpuTemp: Double?
}

enum Health: Int, Comparable {
    case ok, warn, alarm, offline
    static func < (a: Health, b: Health) -> Bool { a.rawValue < b.rawValue }
}
