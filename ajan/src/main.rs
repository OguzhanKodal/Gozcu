#![cfg_attr(windows, windows_subsystem = "windows")]

mod ai;
mod collect;
mod config;
mod guard;
mod model;

use config::Config;
use guard::{Decision, Guard};
use model::Status;
use std::io::Read;
use std::net::IpAddr;
use std::sync::{Arc, Mutex};
use std::time::Duration;
use tiny_http::{Header, Method, Request, Response, Server};

struct Shared {
    status: Status,
    guard: Guard,
}

fn main() {
    let args: Vec<String> = std::env::args().collect();
    if args.iter().any(|a| a == "--version") {
        println!("gozcu-ajan {}", env!("CARGO_PKG_VERSION"));
        return;
    }
    let path = args
        .windows(2)
        .find(|w| w[0] == "--config")
        .map(|w| w[1].clone().into())
        .unwrap_or_else(config::default_path);
    let cfg = Arc::new(Config::load(&path));
    if args.iter().any(|a| a == "--once") {
        let mut c = collect::Collector::new();
        let mut st = Status::default();
        std::thread::sleep(Duration::from_millis(800));
        c.sample(&mut st);
        fill_ai(&cfg, &mut st, true);
        println!("{}", serde_json::to_string_pretty(&st).unwrap());
        return;
    }
    if cfg.token.len() < 16 {
        eprintln!("ajan.json içinde en az 16 karakterlik bir token gerekli: {}", path.display());
        std::process::exit(2);
    }

    let shared = Arc::new(Mutex::new(Shared { status: Status::default(), guard: Guard::default() }));

    // Örnekleyici: 2 saniyede bir donanım, 60 saniyede bir token sayımı.
    {
        let shared = shared.clone();
        let cfg = cfg.clone();
        std::thread::spawn(move || {
            let mut c = collect::Collector::new();
            let mut tick: u64 = 0;
            loop {
                let mut st = shared.lock().unwrap().status.clone();
                st.notes.clear();
                c.sample(&mut st);
                fill_ai(&cfg, &mut st, tick % 30 == 0);
                st.name = cfg.name.clone();
                st.agent_version = env!("CARGO_PKG_VERSION").into();
                let decision = {
                    let mut s = shared.lock().unwrap();
                    let d = s.guard.update(&st, &cfg);
                    st.guard = s.guard.view(&cfg);
                    s.status = st;
                    d
                };
                if let Decision::StopAi = decision {
                    let msg = format!("Isı tehlikeliydi, müdahale gelmedi: {}", ai::stop_ai(&cfg));
                    eprintln!("{msg}");
                    shared.lock().unwrap().guard.acted(msg);
                }
                tick += 1;
                std::thread::sleep(Duration::from_secs(2));
            }
        });
    }

    let server = match Server::http(&cfg.listen) {
        Ok(s) => s,
        Err(e) => {
            eprintln!("{} dinlenemedi: {e}", cfg.listen);
            std::process::exit(1);
        }
    };
    eprintln!("gozcu-ajan {} dinliyor: {}", env!("CARGO_PKG_VERSION"), cfg.listen);
    for req in server.incoming_requests() {
        let shared = shared.clone();
        let cfg = cfg.clone();
        std::thread::spawn(move || handle(req, &shared, &cfg));
    }
}

fn fill_ai(cfg: &Config, st: &mut Status, tokens: bool) {
    match ai::ollama_models(cfg) {
        Some(m) => {
            st.ai.ollama_up = true;
            st.ai.models = m;
        }
        None => {
            st.ai.ollama_up = false;
            st.ai.models.clear();
        }
    }
    if tokens {
        if let Some(home) = cfg.home() {
            st.ai.tokens = [ai::claude_tokens(&home), ai::opencode_tokens(&home)].into_iter().flatten().filter(|t| t.messages > 0).collect();
        }
    }
}

/// Yalnız bu makine, Tailscale (100.64.0.0/10, fd7a:115c:a1e0::/48) ve loopback kabul edilir.
fn allowed(ip: IpAddr) -> bool {
    match ip {
        IpAddr::V4(v) => v.is_loopback() || (v.octets()[0] == 100 && (v.octets()[1] & 0xC0) == 64),
        IpAddr::V6(v) => {
            v.is_loopback()
                || v.to_ipv4_mapped().map(|m| allowed(IpAddr::V4(m))).unwrap_or(false)
                || v.segments()[..3] == [0xfd7a, 0x115c, 0xa1e0]
        }
    }
}

fn json(code: u16, body: serde_json::Value) -> Response<std::io::Cursor<Vec<u8>>> {
    Response::from_string(body.to_string())
        .with_status_code(code)
        .with_header(Header::from_bytes("Content-Type", "application/json; charset=utf-8").unwrap())
}

fn handle(mut req: Request, shared: &Mutex<Shared>, cfg: &Config) {
    let ip = req.remote_addr().map(|a| a.ip());
    if !ip.map(allowed).unwrap_or(false) {
        let _ = req.respond(json(403, serde_json::json!({"error": "yalnız Tailscale ağı"})));
        return;
    }
    let auth = req.headers().iter().find(|h| h.field.equiv("Authorization")).map(|h| h.value.as_str().to_string());
    if auth.as_deref() != Some(&format!("Bearer {}", cfg.token)) {
        let _ = req.respond(json(401, serde_json::json!({"error": "yetkisiz"})));
        return;
    }
    let url = req.url().to_string();
    let resp = match (req.method(), url.as_str()) {
        (Method::Get, "/v1/status") => {
            let s = shared.lock().unwrap();
            json(200, serde_json::to_value(&s.status).unwrap())
        }
        (Method::Post, "/v1/action") => {
            let mut body = String::new();
            let _ = req.as_reader().take(64 * 1024).read_to_string(&mut body);
            let v: serde_json::Value = serde_json::from_str(&body).unwrap_or_default();
            let now = chrono::Utc::now().timestamp();
            let msg = match v["action"].as_str().unwrap_or("") {
                "stop_ai" => {
                    let m = ai::stop_ai(cfg);
                    shared.lock().unwrap().guard.manual_stop(now, format!("Elle durduruldu: {m}"));
                    m
                }
                "start_ai" => ai::start_ai(cfg),
                "snooze" => {
                    let min = v["minutes"].as_i64().unwrap_or(15).clamp(1, 240);
                    shared.lock().unwrap().guard.snooze(now, min);
                    format!("{min} dakika ertelendi")
                }
                "gpu_power_limit" => match v["watts"].as_u64() {
                    Some(w) if (30..=600).contains(&w) => ai::gpu_power_limit(w as u32),
                    _ => "geçersiz watt".into(),
                },
                "kill" => match v["pid"].as_u64() {
                    Some(p) if p > 4 => ai::kill(p as u32),
                    _ => "geçersiz pid".into(),
                },
                other => {
                    let _ = req.respond(json(400, serde_json::json!({"error": format!("bilinmeyen eylem: {other}")})));
                    return;
                }
            };
            json(200, serde_json::json!({"ok": true, "message": msg}))
        }
        _ => json(404, serde_json::json!({"error": "yok"})),
    };
    let _ = req.respond(resp);
}
