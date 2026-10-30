use crate::model::*;
use std::process::Command;
use std::time::Instant;
use sysinfo::{Components, Disks, Networks, ProcessesToUpdate, System};

/// Oyun olarak tanınan süreç adları (küçük harf, uzantısız).
const GAMES: &[&str] = &[
    "gta5", "gta5_enhanced", "playgtav", "gtav", "rdr2", "fivem", "cs2", "valorant",
    "fortnite", "fortniteclient-win64-shipping", "r5apex", "eldenring", "cyberpunk2077",
    "minecraft", "javaw", "rocketleague", "leagueclient", "league of legends",
];

/// Yerel GPU'yu kullanan AI süreçleri (durdurma eylemi bunları hedefler).
pub const AI_GPU_PROCS: &[&str] = &["ollama", "ollama app", "llama-server", "ollama_llama_server", "lms", "lm studio"];
/// Gösterim için tanınan AI istemcileri.
const AI_CLIENTS: &[&str] = &["opencode", "claude", "codex", "aider", "cursor"];

pub struct Collector {
    sys: System,
    comps: Components,
    disks: Disks,
    nets: Networks,
    last_net: Instant,
    tick: u64,
}

pub fn cmd(program: &str, args: &[&str]) -> Option<String> {
    let mut c = Command::new(program);
    c.args(args);
    #[cfg(windows)]
    {
        use std::os::windows::process::CommandExt;
        c.creation_flags(0x0800_0000); // CREATE_NO_WINDOW
    }
    let out = c.output().ok()?;
    if !out.status.success() {
        return None;
    }
    Some(String::from_utf8_lossy(&out.stdout).into_owned())
}

fn stem(name: &str) -> String {
    let n = name.to_lowercase();
    n.strip_suffix(".exe").unwrap_or(&n).to_string()
}

fn num(s: &str) -> Option<f32> {
    let t = s.trim();
    if t.is_empty() || t.contains("N/A") || t.contains("Not Supported") || t.starts_with('[') {
        return None;
    }
    t.parse().ok()
}

impl Collector {
    pub fn new() -> Self {
        let mut sys = System::new_all();
        sys.refresh_all();
        Collector {
            sys,
            comps: Components::new_with_refreshed_list(),
            disks: Disks::new_with_refreshed_list(),
            nets: Networks::new_with_refreshed_list(),
            last_net: Instant::now(),
            tick: 0,
        }
    }

    /// Donanım durumunu toplar. AI ve guard alanlarını çağıran doldurur.
    pub fn sample(&mut self, st: &mut Status) {
        self.tick += 1;
        self.sys.refresh_cpu_usage();
        self.sys.refresh_memory();
        self.sys.refresh_processes(ProcessesToUpdate::All, true);
        self.comps.refresh(true);
        if self.tick % 15 == 1 {
            self.disks.refresh(true);
        }

        st.os = System::long_os_version().unwrap_or_default();
        st.host = System::host_name().unwrap_or_default();
        st.uptime_secs = System::uptime();
        st.time = chrono::Utc::now().timestamp();

        let cpus = self.sys.cpus();
        st.cpu.usage = self.sys.global_cpu_usage();
        st.cpu.cores = cpus.len();
        st.cpu.model = cpus.first().map(|c| c.brand().trim().to_string()).unwrap_or_default();
        st.cpu.load_avg = if cfg!(windows) {
            None
        } else {
            let l = System::load_average();
            Some([l.one, l.five, l.fifteen])
        };

        st.mem = Mem {
            used: self.sys.used_memory(),
            total: self.sys.total_memory(),
            swap_used: self.sys.used_swap(),
            swap_total: self.sys.total_swap(),
        };

        // Sıcaklıklar
        st.temps = self
            .comps
            .iter()
            .filter_map(|c| c.temperature().filter(|t| *t > 0.0 && *t < 130.0).map(|t| Reading { label: c.label().to_string(), value: t }))
            .collect();
        st.fans.clear();
        st.cpu.temp = pick_cpu_temp(&st.temps);

        #[cfg(target_os = "linux")]
        {
            st.fans = linux_fans();
            st.battery = linux_battery();
        }
        #[cfg(target_os = "macos")]
        {
            if self.tick % 5 == 1 || st.battery.is_none() {
                st.battery = mac_battery();
            }
        }
        #[cfg(windows)]
        {
            lhm(st);
        }

        // Diskler (yalnız gerçek, büyük olanlar)
        st.disks = self
            .disks
            .iter()
            .filter(|d| d.total_space() > 20_000_000_000)
            .map(|d| Disk { mount: d.mount_point().to_string_lossy().into_owned(), total: d.total_space(), free: d.available_space() })
            .filter(|d| !d.mount.starts_with("/boot") && !d.mount.starts_with("/System/Volumes/") || d.mount == "/System/Volumes/Data")
            .take(4)
            .collect();
        st.disks.dedup_by(|a, b| a.total == b.total && a.free / 1_000_000_000 == b.free / 1_000_000_000);

        // Ağ
        self.nets.refresh(true);
        let secs = self.last_net.elapsed().as_secs_f64().max(0.5);
        self.last_net = Instant::now();
        let (mut rx, mut tx) = (0u64, 0u64);
        for (name, n) in self.nets.iter() {
            let l = name.to_lowercase();
            if l.starts_with("lo") || l.contains("loopback") || l.starts_with("tailscale") || l.starts_with("utun") {
                continue;
            }
            rx += n.received();
            tx += n.transmitted();
        }
        st.net = Net { rx_bps: (rx as f64 / secs) as u64, tx_bps: (tx as f64 / secs) as u64 };

        // Süreçler
        let ncpu = st.cpu.cores.max(1) as f32;
        let mut procs: Vec<Proc> = self
            .sys
            .processes()
            .values()
            .map(|p| Proc { pid: p.pid().as_u32(), name: p.name().to_string_lossy().into_owned(), cpu: p.cpu_usage() / ncpu, mem: p.memory() })
            .filter(|p| p.pid != 0 && !p.name.eq_ignore_ascii_case("System Idle Process"))
            .collect();
        procs.sort_by(|a, b| b.cpu.partial_cmp(&a.cpu).unwrap_or(std::cmp::Ordering::Equal));

        st.game = procs.iter().find(|p| GAMES.contains(&stem(&p.name).as_str())).map(|p| p.name.clone());
        let mut ai: Vec<String> = procs
            .iter()
            .filter(|p| {
                let s = stem(&p.name);
                AI_GPU_PROCS.contains(&s.as_str()) || AI_CLIENTS.contains(&s.as_str())
            })
            .map(|p| stem(&p.name))
            .collect();
        ai.sort();
        ai.dedup();
        st.ai.procs = ai;
        procs.truncate(8);
        st.procs = procs;

        // NVIDIA
        nvidia(st, self.tick);
        if st.game.is_none() {
            // Bilinmeyen ama ekran kartını yoğun kullanan, AI olmayan bir grafik uygulaması oyundur.
            st.game = st
                .gpu_procs
                .iter()
                .filter(|g| g.sm.unwrap_or(0.0) >= 25.0 && !AI_GPU_PROCS.contains(&stem(&g.name).as_str()))
                .filter(|g| !["dwm", "explorer", "gnome-shell", "xorg", "kwin_wayland"].contains(&stem(&g.name).as_str()))
                .map(|g| g.name.clone())
                .next();
        }
    }
}

fn pick_cpu_temp(temps: &[Reading]) -> Option<f32> {
    let keys = ["tctl", "tdie", "package", "cpu", "k10temp", "coretemp", "pacc", "eacc", "soc"];
    let mut best: Option<f32> = None;
    for t in temps {
        let l = t.label.to_lowercase();
        if l.contains("gpu") || l.contains("nvme") || l.contains("battery") || l.contains("amdgpu") {
            continue;
        }
        if keys.iter().any(|k| l.contains(k)) {
            best = Some(best.map_or(t.value, |b: f32| b.max(t.value)));
        }
    }
    best
}

fn nvidia(st: &mut Status, tick: u64) {
    let q = "name,temperature.gpu,utilization.gpu,memory.used,memory.total,power.draw,power.limit,power.max_limit,fan.speed";
    st.gpus = match cmd("nvidia-smi", &[&format!("--query-gpu={q}"), "--format=csv,noheader,nounits"]) {
        Some(out) => out
            .lines()
            .filter(|l| !l.trim().is_empty())
            .map(|l| {
                let f: Vec<&str> = l.split(',').collect();
                let g = |i: usize| f.get(i).and_then(|s| num(s));
                Gpu {
                    name: f.first().map(|s| s.trim().to_string()).unwrap_or_default(),
                    temp: g(1),
                    util: g(2),
                    mem_used_mb: g(3),
                    mem_total_mb: g(4),
                    power_w: g(5),
                    power_limit_w: g(6),
                    power_max_w: g(7),
                    fan_pct: g(8),
                }
            })
            .collect(),
        None => Vec::new(),
    };
    if st.gpus.is_empty() {
        st.gpu_procs.clear();
        return;
    }
    // pmon biraz yavaş; her 2 örnekte bir yeterli.
    if tick % 2 == 1 {
        let mut procs = Vec::new();
        if let Some(out) = cmd("nvidia-smi", &["pmon", "-c", "1", "-s", "um"]) {
            for l in out.lines().filter(|l| !l.starts_with('#')) {
                let f: Vec<&str> = l.split_whitespace().collect();
                // gpu pid type sm mem enc dec jpg ofa fb ccpm command
                if f.len() < 5 {
                    continue;
                }
                let Ok(pid) = f[1].parse::<u32>() else { continue };
                let name = f.last().unwrap_or(&"").to_string();
                let fb = f.iter().rev().nth(2).and_then(|s| num(s));
                procs.push(GpuProc { pid, name, sm: num(f[3]), mem_mb: fb });
            }
        }
        procs.sort_by(|a, b| b.sm.unwrap_or(0.0).partial_cmp(&a.sm.unwrap_or(0.0)).unwrap_or(std::cmp::Ordering::Equal));
        procs.dedup_by_key(|p| p.pid);
        procs.truncate(6);
        st.gpu_procs = procs;
    }
}

#[cfg(target_os = "linux")]
fn read(p: &std::path::Path) -> Option<String> {
    std::fs::read_to_string(p).ok().map(|s| s.trim().to_string())
}

#[cfg(target_os = "linux")]
fn linux_fans() -> Vec<Reading> {
    let mut fans = Vec::new();
    let Ok(dirs) = std::fs::read_dir("/sys/class/hwmon") else { return fans };
    for d in dirs.flatten() {
        let p = d.path();
        let chip = read(&p.join("name")).unwrap_or_default();
        for i in 1..=4 {
            if let Some(v) = read(&p.join(format!("fan{i}_input"))).and_then(|s| s.parse::<f32>().ok()) {
                let label = read(&p.join(format!("fan{i}_label"))).unwrap_or_else(|| format!("{chip} fan{i}"));
                fans.push(Reading { label, value: v });
            }
        }
    }
    // Lenovo Legion'da yogafan tam yükte bile 0 okur; başka fan sensörü varsa onu gösterme.
    if fans.iter().any(|f| !f.label.starts_with("yogafan") && f.value > 0.0) {
        fans.retain(|f| !f.label.starts_with("yogafan"));
    }
    fans
}

#[cfg(target_os = "linux")]
fn linux_battery() -> Option<Battery> {
    let base = std::path::Path::new("/sys/class/power_supply");
    let mut bat = None;
    let mut plugged = false;
    for e in std::fs::read_dir(base).ok()?.flatten() {
        let p = e.path();
        match read(&p.join("type")).as_deref() {
            Some("Battery") if bat.is_none() => bat = Some(p),
            Some("Mains") => plugged |= read(&p.join("online")).as_deref() == Some("1"),
            _ => {}
        }
    }
    let p = bat?;
    let n = |f: &str| read(&p.join(f)).and_then(|s| s.parse::<f64>().ok());
    let percent = n("capacity")? as f32;
    let status = read(&p.join("status")).unwrap_or_default();
    let state = match status.as_str() {
        "Charging" => "charging",
        "Discharging" => "discharging",
        "Full" => "full",
        _ => "not_charging",
    };
    let health = match (n("energy_full"), n("energy_full_design")) {
        (Some(f), Some(d)) if d > 0.0 => Some((f / d * 100.0) as f32),
        _ => match (n("charge_full"), n("charge_full_design")) {
            (Some(f), Some(d)) if d > 0.0 => Some((f / d * 100.0) as f32),
            _ => None,
        },
    };
    let power_w = n("power_now").map(|v| (v / 1e6) as f32).or_else(|| match (n("current_now"), n("voltage_now")) {
        (Some(c), Some(v)) => Some((c * v / 1e12) as f32),
        _ => None,
    });
    let minutes_left = match (state, n("energy_now"), power_w) {
        ("discharging", Some(e), Some(w)) if w > 0.5 => Some((e / 1e6 / w as f64 * 60.0) as u32),
        _ => None,
    };
    Some(Battery {
        percent,
        state: state.into(),
        plugged: plugged || state == "charging",
        power_w,
        health_pct: health,
        cycles: n("cycle_count").map(|c| c as u32),
        minutes_left,
    })
}

#[cfg(target_os = "macos")]
fn mac_battery() -> Option<Battery> {
    let out = cmd("pmset", &["-g", "batt"])?;
    let plugged = out.contains("AC Power");
    let line = out.lines().find(|l| l.contains('%'))?;
    let percent: f32 = line.split('%').next()?.rsplit(|c: char| !c.is_ascii_digit()).next()?.parse().ok()?;
    let state = if line.contains("discharging") {
        "discharging"
    } else if line.contains("charged") {
        "full"
    } else if line.contains("charging") {
        "charging"
    } else {
        "not_charging"
    };
    let minutes_left = line.split_whitespace().find(|w| w.contains(':')).and_then(|t| {
        let (h, m) = t.split_once(':')?;
        Some(h.parse::<u32>().ok()? * 60 + m.parse::<u32>().ok()?)
    });
    let io = cmd("ioreg", &["-rn", "AppleSmartBattery"]).unwrap_or_default();
    let field = |k: &str| {
        io.lines()
            .find(|l| l.trim_start().starts_with(&format!("\"{k}\" =")))
            .and_then(|l| l.split('=').nth(1))
            .and_then(|v| v.trim().parse::<f64>().ok())
    };
    let health = match (field("AppleRawMaxCapacity").or(field("NominalChargeCapacity")), field("DesignCapacity")) {
        (Some(m), Some(d)) if d > 0.0 => Some((m / d * 100.0) as f32),
        _ => None,
    };
    let power_w = match (field("Amperage"), field("Voltage")) {
        (Some(a), Some(v)) => {
            let a = if a > 9.0e18 { a - 18_446_744_073_709_551_616.0 } else { a };
            Some((a.abs() * v / 1e6) as f32)
        }
        _ => None,
    };
    Some(Battery {
        percent,
        state: state.into(),
        plugged,
        power_w,
        health_pct: health,
        cycles: field("CycleCount").map(|c| c as u32),
        minutes_left: if state == "discharging" { minutes_left } else { None },
    })
}

/// LibreHardwareMonitor'ün yerel web sunucusundan işlemci ısısı ve fanlar (Windows).
#[cfg(windows)]
fn lhm(st: &mut Status) {
    let Ok(resp) = ureq::get("http://127.0.0.1:8085/data.json").timeout(std::time::Duration::from_millis(800)).call() else {
        if st.cpu.temp.is_none() {
            st.notes.push("İşlemci ısısı için LibreHardwareMonitor çalışmıyor".into());
        }
        return;
    };
    let Ok(v) = resp.into_json::<serde_json::Value>() else { return };
    let mut temps = Vec::new();
    let mut fans = Vec::new();
    fn walk(v: &serde_json::Value, temps: &mut Vec<Reading>, fans: &mut Vec<Reading>) {
        let id = v.get("SensorId").and_then(|s| s.as_str()).unwrap_or("");
        let text = v.get("Text").and_then(|s| s.as_str()).unwrap_or("");
        let value = v.get("Value").and_then(|s| s.as_str()).and_then(|s| s.split_whitespace().next()).and_then(|s| s.replace(',', ".").parse::<f32>().ok());
        if let Some(val) = value {
            if id.contains("/temperature/") && (id.contains("cpu") || id.contains("lpc") || id.contains("nvme")) {
                let chip = id.split('/').nth(1).unwrap_or("");
                temps.push(Reading { label: format!("{chip} {text}"), value: val });
            } else if id.contains("/fan/") && val > 0.0 {
                fans.push(Reading { label: text.to_string(), value: val });
            }
        }
        if let Some(children) = v.get("Children").and_then(|c| c.as_array()) {
            for c in children {
                walk(c, temps, fans);
            }
        }
    }
    walk(&v, &mut temps, &mut fans);
    if !temps.is_empty() {
        st.cpu.temp = temps
            .iter()
            .filter(|t| t.label.contains("cpu") && (t.label.contains("Tctl") || t.label.contains("Package") || t.label.contains("Core")))
            .map(|t| t.value)
            .fold(None, |a: Option<f32>, b| Some(a.map_or(b, |a| a.max(b))));
        st.temps = temps;
    }
    st.fans = fans;
}
