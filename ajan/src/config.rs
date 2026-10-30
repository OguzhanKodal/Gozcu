use serde::{Deserialize, Serialize};
use std::path::PathBuf;

/// Ajan ayarları. Dosya yoksa varsayılanlarla çalışır.
#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(default)]
pub struct Config {
    /// Panoda görünen ad (varsayılan: bilgisayar adı).
    pub name: String,
    /// Dinlenecek adres. Mac'te 127.0.0.1, diğerlerinde 0.0.0.0 (yalnız Tailscale IP'leri kabul edilir).
    pub listen: String,
    /// Mac uygulamasının göndereceği gizli anahtar.
    pub token: String,
    /// Claude Code / opencode / Ollama verilerinin bulunduğu kullanıcı klasörü.
    /// Windows'ta ajan SYSTEM olarak çalıştığı için bunu açıkça vermek gerekir.
    pub user_home: Option<PathBuf>,
    pub ollama_url: String,
    pub thresholds: Thresholds,
    /// Tehlike bu kadar saniye sürerse alarm başlar.
    pub sustain_secs: u64,
    /// Alarmdan sonra kullanıcı müdahale etmezse AI bu kadar saniye sonra durdurulur.
    pub grace_secs: u64,
    /// false ise ajan hiçbir şeyi kendiliğinden durdurmaz, yalnız alarm verir.
    pub auto_stop_ai: bool,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(default)]
pub struct Thresholds {
    pub cpu_warn: f32,
    pub cpu_danger: f32,
    pub gpu_warn: f32,
    pub gpu_danger: f32,
    /// Bir seviyeden çıkmak için ısının eşiğin bu kadar derece altına inmesi gerekir.
    /// Eşik çevresinde gidip gelen ısının sürekli uyarı üretmesini önler.
    pub hysteresis: f32,
}

impl Default for Thresholds {
    fn default() -> Self {
        Thresholds { cpu_warn: 85.0, cpu_danger: 97.0, gpu_warn: 80.0, gpu_danger: 87.0, hysteresis: 5.0 }
    }
}

impl Default for Config {
    fn default() -> Self {
        Config {
            name: sysinfo::System::host_name().unwrap_or_else(|| "makine".into()),
            listen: "127.0.0.1:7420".into(),
            token: String::new(),
            user_home: None,
            ollama_url: "http://127.0.0.1:11434".into(),
            thresholds: Thresholds::default(),
            sustain_secs: 15,
            grace_secs: 180,
            auto_stop_ai: true,
        }
    }
}

impl Config {
    pub fn load(path: &PathBuf) -> Config {
        match std::fs::read_to_string(path) {
            Ok(text) => serde_json::from_str(&text).unwrap_or_else(|e| {
                eprintln!("ayar dosyası okunamadı ({}): {e}; varsayılanlar kullanılıyor", path.display());
                Config::default()
            }),
            Err(_) => Config::default(),
        }
    }

    pub fn home(&self) -> Option<PathBuf> {
        self.user_home.clone().or_else(|| {
            std::env::var_os("HOME").or_else(|| std::env::var_os("USERPROFILE")).map(PathBuf::from)
        })
    }
}

pub fn default_path() -> PathBuf {
    if cfg!(windows) {
        PathBuf::from(r"C:\ProgramData\Gozcu\ajan.json")
    } else if cfg!(target_os = "macos") {
        let home = std::env::var_os("HOME").map(PathBuf::from).unwrap_or_default();
        home.join("Library/Application Support/Gozcu/ajan.json")
    } else {
        let home = std::env::var_os("HOME").map(PathBuf::from).unwrap_or_default();
        home.join(".config/gozcu/ajan.json")
    }
}
