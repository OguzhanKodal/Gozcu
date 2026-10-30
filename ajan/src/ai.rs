use crate::collect::{cmd, AI_GPU_PROCS};
use crate::config::Config;
use crate::model::{LoadedModel, TokenUsage};
use std::collections::{HashMap, HashSet};
use std::path::Path;
use std::time::{Duration, SystemTime};

fn agent() -> ureq::Agent {
    ureq::AgentBuilder::new().timeout(Duration::from_millis(1500)).build()
}

/// Ollama'da o an yüklü modeller. None = Ollama yanıt vermiyor.
pub fn ollama_models(cfg: &Config) -> Option<Vec<LoadedModel>> {
    let v: serde_json::Value = agent().get(&format!("{}/api/ps", cfg.ollama_url)).call().ok()?.into_json().ok()?;
    let models = v.get("models")?.as_array()?;
    Some(
        models
            .iter()
            .map(|m| LoadedModel {
                name: m.get("name").and_then(|s| s.as_str()).unwrap_or("").to_string(),
                vram_mb: m.get("size_vram").and_then(|s| s.as_f64()).unwrap_or(0.0) as f32 / 1_048_576.0,
                size_mb: m.get("size").and_then(|s| s.as_f64()).unwrap_or(0.0) as f32 / 1_048_576.0,
                context: m.get("context_length").and_then(|s| s.as_u64()),
            })
            .collect(),
    )
}

/// Yapay zekâyı durdurur: Ollama'daki modelleri boşaltır, yerel AI sunucularını
/// ve opencode istemcilerini kapatır. Oyunlara ve diğer programlara dokunmaz.
pub fn stop_ai(cfg: &Config) -> String {
    let mut done = Vec::new();
    if let Some(models) = ollama_models(cfg) {
        for m in &models {
            let body = serde_json::json!({ "model": m.name, "keep_alive": 0 });
            if agent().post(&format!("{}/api/generate", cfg.ollama_url)).send_json(body).is_ok() {
                done.push(format!("{} boşaltıldı", m.name));
            }
        }
    }
    let mut sys = sysinfo::System::new();
    sys.refresh_processes(sysinfo::ProcessesToUpdate::All, true);
    let mut killed = HashSet::new();
    for p in sys.processes().values() {
        let n = p.name().to_string_lossy().to_lowercase();
        let n = n.strip_suffix(".exe").unwrap_or(&n).to_string();
        // Linux'ta ollama servisi ayrı kullanıcıda çalışır; öldürülemezse modeller zaten boşaltıldı.
        if (AI_GPU_PROCS.contains(&n.as_str()) && cfg!(windows)) || n == "opencode" {
            if p.kill() {
                killed.insert(n);
            }
        }
    }
    if !killed.is_empty() {
        let mut k: Vec<_> = killed.into_iter().collect();
        k.sort();
        done.push(format!("kapatıldı: {}", k.join(", ")));
    }
    if done.is_empty() {
        "Çalışan yapay zekâ işi yoktu".into()
    } else {
        done.join("; ")
    }
}

/// Windows'ta durdurulan Ollama'yı kullanıcının model klasörüyle yeniden başlatır.
pub fn start_ai(cfg: &Config) -> String {
    if !cfg!(windows) {
        return "Bu makinede Ollama servis olarak çalışıyor; durdurulmadı, ek işlem gerekmez".into();
    }
    if ollama_models(cfg).is_some() {
        return "Ollama zaten çalışıyor".into();
    }
    let Some(home) = cfg.home() else { return "Kullanıcı klasörü bilinmiyor".into() };
    let exe = home.join(r"AppData\Local\Programs\Ollama\ollama.exe");
    let mut c = std::process::Command::new(&exe);
    c.arg("serve")
        .env("OLLAMA_HOST", "0.0.0.0:11434")
        .env("OLLAMA_MODELS", home.join(r".ollama\models"))
        .stdin(std::process::Stdio::null())
        .stdout(std::process::Stdio::null())
        .stderr(std::process::Stdio::null());
    #[cfg(windows)]
    {
        use std::os::windows::process::CommandExt;
        c.creation_flags(0x0800_0000 | 0x0000_0008); // CREATE_NO_WINDOW | DETACHED_PROCESS
    }
    match c.spawn() {
        Ok(_) => "Ollama başlatıldı".into(),
        Err(e) => format!("Ollama başlatılamadı: {e}"),
    }
}

pub fn gpu_power_limit(watts: u32) -> String {
    match cmd("nvidia-smi", &["-pl", &watts.to_string()]) {
        Some(out) => out.lines().next().unwrap_or("GPU güç sınırı ayarlandı").trim().to_string(),
        None => "GPU güç sınırı ayarlanamadı (bu kart/izin desteklemiyor olabilir)".into(),
    }
}

pub fn kill(pid: u32) -> String {
    let mut sys = sysinfo::System::new();
    sys.refresh_processes(sysinfo::ProcessesToUpdate::All, true);
    match sys.process(sysinfo::Pid::from_u32(pid)) {
        Some(p) => {
            let name = p.name().to_string_lossy().into_owned();
            if p.kill() {
                format!("{name} ({pid}) kapatıldı")
            } else {
                format!("{name} ({pid}) kapatılamadı")
            }
        }
        None => format!("{pid} numaralı süreç bulunamadı"),
    }
}

fn today_start() -> chrono::DateTime<chrono::Local> {
    let now = chrono::Local::now();
    now.date_naive().and_hms_opt(0, 0, 0).and_then(|d| d.and_local_timezone(chrono::Local).single()).unwrap_or(now)
}

fn modified_today(p: &Path, start: SystemTime) -> bool {
    p.metadata().and_then(|m| m.modified()).map(|t| t >= start).unwrap_or(false)
}

/// Claude Code'un bugünkü token kullanımı (~/.claude/projects/*/*.jsonl).
pub fn claude_tokens(home: &Path) -> Option<TokenUsage> {
    let root = home.join(".claude").join("projects");
    let start = today_start();
    let start_sys: SystemTime = start.into();
    let mut u = TokenUsage { tool: "Claude Code".into(), ..Default::default() };
    let mut seen = HashSet::new();
    let mut models: HashMap<String, u64> = HashMap::new();
    for proj in std::fs::read_dir(&root).ok()?.flatten() {
        let Ok(files) = std::fs::read_dir(proj.path()) else { continue };
        for f in files.flatten() {
            let p = f.path();
            if p.extension().and_then(|e| e.to_str()) != Some("jsonl") || !modified_today(&p, start_sys) {
                continue;
            }
            let Ok(text) = std::fs::read_to_string(&p) else { continue };
            for line in text.lines().filter(|l| l.contains("\"usage\"")) {
                let Ok(v) = serde_json::from_str::<serde_json::Value>(line) else { continue };
                let Some(ts) = v.get("timestamp").and_then(|t| t.as_str()).and_then(|t| chrono::DateTime::parse_from_rfc3339(t).ok()) else { continue };
                if ts < start {
                    continue;
                }
                let msg = &v["message"];
                let id = msg.get("id").and_then(|s| s.as_str()).unwrap_or("").to_string();
                if !id.is_empty() && !seen.insert(id) {
                    continue;
                }
                let us = &msg["usage"];
                let g = |k: &str| us.get(k).and_then(|x| x.as_u64()).unwrap_or(0);
                u.input += g("input_tokens");
                u.output += g("output_tokens");
                u.cache_read += g("cache_read_input_tokens");
                u.cache_write += g("cache_creation_input_tokens");
                u.messages += 1;
                if let Some(m) = msg.get("model").and_then(|s| s.as_str()) {
                    *models.entry(m.to_string()).or_default() += g("output_tokens") + g("input_tokens");
                }
            }
        }
    }
    u.top_model = models.into_iter().max_by_key(|(_, n)| *n).map(|(m, _)| m);
    Some(u)
}

/// opencode'un bugünkü token kullanımı (~/.local/share/opencode/opencode.db).
pub fn opencode_tokens(home: &Path) -> Option<TokenUsage> {
    let db = home.join(".local").join("share").join("opencode").join("opencode.db");
    if !db.exists() {
        return None;
    }
    let conn = rusqlite::Connection::open_with_flags(&db, rusqlite::OpenFlags::SQLITE_OPEN_READ_ONLY | rusqlite::OpenFlags::SQLITE_OPEN_NO_MUTEX).ok()?;
    let since = today_start().timestamp_millis();
    let mut stmt = conn.prepare("SELECT data FROM session_message WHERE type = 'assistant' AND time_created >= ?1").ok()?;
    let rows = stmt.query_map([since], |r| r.get::<_, String>(0)).ok()?;
    let mut u = TokenUsage { tool: "opencode".into(), ..Default::default() };
    let mut models: HashMap<String, u64> = HashMap::new();
    for data in rows.flatten() {
        let Ok(v) = serde_json::from_str::<serde_json::Value>(&data) else { continue };
        let t = &v["tokens"];
        let g = |x: &serde_json::Value| x.as_u64().unwrap_or(0);
        let (i, o) = (g(&t["input"]), g(&t["output"]) + g(&t["reasoning"]));
        u.input += i;
        u.output += o;
        u.cache_read += g(&t["cache"]["read"]);
        u.cache_write += g(&t["cache"]["write"]);
        u.messages += 1;
        if let Some(m) = v["model"]["id"].as_str() {
            *models.entry(m.to_string()).or_default() += i + o;
        }
    }
    u.top_model = models.into_iter().max_by_key(|(_, n)| *n).map(|(m, _)| m);
    Some(u)
}
