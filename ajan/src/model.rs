use serde::Serialize;

/// Mac uygulamasına giden anlık durum.
#[derive(Clone, Debug, Default, Serialize)]
pub struct Status {
    pub name: String,
    pub os: String,
    pub host: String,
    pub agent_version: String,
    pub time: i64,
    pub uptime_secs: u64,
    pub cpu: Cpu,
    pub mem: Mem,
    pub gpus: Vec<Gpu>,
    pub temps: Vec<Reading>,
    pub fans: Vec<Reading>,
    pub battery: Option<Battery>,
    pub disks: Vec<Disk>,
    pub net: Net,
    pub procs: Vec<Proc>,
    pub gpu_procs: Vec<GpuProc>,
    pub game: Option<String>,
    pub ai: Ai,
    pub guard: GuardView,
    pub notes: Vec<String>,
}

#[derive(Clone, Debug, Default, Serialize)]
pub struct Cpu {
    pub usage: f32,
    pub temp: Option<f32>,
    pub cores: usize,
    pub model: String,
    pub load_avg: Option<[f64; 3]>,
}

#[derive(Clone, Debug, Default, Serialize)]
pub struct Mem {
    pub used: u64,
    pub total: u64,
    pub swap_used: u64,
    pub swap_total: u64,
}

#[derive(Clone, Debug, Default, Serialize)]
pub struct Gpu {
    pub name: String,
    pub temp: Option<f32>,
    pub util: Option<f32>,
    pub mem_used_mb: Option<f32>,
    pub mem_total_mb: Option<f32>,
    pub power_w: Option<f32>,
    pub power_limit_w: Option<f32>,
    pub power_max_w: Option<f32>,
    pub fan_pct: Option<f32>,
}

#[derive(Clone, Debug, Default, Serialize)]
pub struct Reading {
    pub label: String,
    pub value: f32,
}

#[derive(Clone, Debug, Default, Serialize)]
pub struct Battery {
    pub percent: f32,
    /// "charging" | "discharging" | "full" | "not_charging"
    pub state: String,
    pub plugged: bool,
    pub power_w: Option<f32>,
    pub health_pct: Option<f32>,
    pub cycles: Option<u32>,
    pub minutes_left: Option<u32>,
}

#[derive(Clone, Debug, Default, Serialize)]
pub struct Disk {
    pub mount: String,
    pub total: u64,
    pub free: u64,
}

#[derive(Clone, Debug, Default, Serialize)]
pub struct Net {
    pub rx_bps: u64,
    pub tx_bps: u64,
}

#[derive(Clone, Debug, Default, Serialize)]
pub struct Proc {
    pub pid: u32,
    pub name: String,
    pub cpu: f32,
    pub mem: u64,
}

#[derive(Clone, Debug, Default, Serialize)]
pub struct GpuProc {
    pub pid: u32,
    pub name: String,
    pub sm: Option<f32>,
    pub mem_mb: Option<f32>,
}

#[derive(Clone, Debug, Default, Serialize)]
pub struct Ai {
    pub ollama_up: bool,
    pub models: Vec<LoadedModel>,
    pub procs: Vec<String>,
    pub tokens: Vec<TokenUsage>,
}

#[derive(Clone, Debug, Default, Serialize)]
pub struct LoadedModel {
    pub name: String,
    pub vram_mb: f32,
    pub size_mb: f32,
    pub context: Option<u64>,
}

/// Bugünkü token kullanımı (yerel gün).
#[derive(Clone, Debug, Default, Serialize)]
pub struct TokenUsage {
    pub tool: String,
    pub input: u64,
    pub output: u64,
    pub cache_read: u64,
    pub cache_write: u64,
    pub messages: u64,
    pub top_model: Option<String>,
}

#[derive(Clone, Debug, Default, Serialize)]
pub struct GuardView {
    /// "ok" | "warn" | "alarm" | "snoozed" | "acted"
    pub state: String,
    pub reason: Option<String>,
    pub since: Option<i64>,
    pub deadline: Option<i64>,
    pub snoozed_until: Option<i64>,
    pub acted_at: Option<i64>,
    pub message: Option<String>,
    pub auto_stop_ai: bool,
    pub grace_secs: u64,
}
