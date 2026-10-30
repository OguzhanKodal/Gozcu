use crate::config::Config;
use crate::model::{GuardView, Status};

/// Isı bekçisi. Tehlike `sustain_secs` sürerse alarm verir; kullanıcı
/// `grace_secs` içinde ertelemez ya da kapatmazsa yapay zekâyı durdurur.
/// Oyunlara ve diğer programlara dokunmaz.
#[derive(Debug, Default)]
pub struct Guard {
    gpu_level: u8,
    cpu_level: u8,
    danger_since: Option<i64>,
    calm_since: Option<i64>,
    alarm: Option<(i64, i64)>, // (başlangıç, son tarih)
    snoozed_until: Option<i64>,
    acted_at: Option<i64>,
    reason: Option<String>,
    message: Option<String>,
}

pub enum Decision {
    None,
    StopAi,
}

/// Isının seviyesi (0 normal, 1 uyarı, 2 tehlike). Seviyeden çıkmak için ısının
/// eşiğin `hysteresis` derece altına inmesi gerekir; eşikte gidip gelme seviyeyi oynatmaz.
fn sensor_level(temp: f32, prev: u8, warn: f32, danger: f32, hyst: f32) -> u8 {
    if temp >= danger || (prev >= 2 && temp > danger - hyst) {
        2
    } else if temp >= warn || (prev >= 1 && temp > warn - hyst) {
        1
    } else {
        0
    }
}

impl Guard {
    fn level(&mut self, st: &Status, cfg: &Config) -> (u8, Option<String>) {
        let t = &cfg.thresholds;
        let gpu = st.gpus.iter().filter_map(|g| g.temp).fold(None, |a: Option<f32>, b| Some(a.map_or(b, |a| a.max(b))));
        self.gpu_level = gpu.map_or(0, |g| sensor_level(g, self.gpu_level, t.gpu_warn, t.gpu_danger, t.hysteresis));
        self.cpu_level = st.cpu.temp.map_or(0, |c| sensor_level(c, self.cpu_level, t.cpu_warn, t.cpu_danger, t.hysteresis));
        let lvl = self.gpu_level.max(self.cpu_level);
        let why = if lvl == 0 {
            None
        } else if self.gpu_level >= self.cpu_level {
            gpu.map(|g| format!("Ekran kartı {g:.0}°C"))
        } else {
            st.cpu.temp.map(|c| format!("İşlemci {c:.0}°C"))
        };
        (lvl, why)
    }

    pub fn update(&mut self, st: &Status, cfg: &Config) -> Decision {
        let now = st.time;
        let (lvl, why) = self.level(st, cfg);
        if let Some(u) = self.snoozed_until {
            if now >= u {
                self.snoozed_until = None;
            }
        }

        if lvl == 2 {
            self.calm_since = None;
            let since = *self.danger_since.get_or_insert(now);
            self.reason = why;
            if self.alarm.is_none() && self.acted_at.is_none() && self.snoozed_until.is_none() && now - since >= cfg.sustain_secs as i64 {
                self.alarm = Some((now, now + cfg.grace_secs as i64));
                self.message = Some("Müdahale etmezsen yapay zekâ işleri durdurulacak".into());
            }
        } else {
            self.danger_since = None;
            if self.alarm.is_some() {
                self.alarm = None;
                self.message = Some("Isı düştü, alarm kapandı".into());
            }
            if lvl == 0 {
                let calm = *self.calm_since.get_or_insert(now);
                if self.acted_at.is_some() && now - calm >= 60 {
                    self.acted_at = None;
                    self.message = None;
                }
            } else {
                self.calm_since = None;
            }
            self.reason = why;
        }

        if let Some((_, deadline)) = self.alarm {
            if now >= deadline && cfg.auto_stop_ai {
                self.alarm = None;
                self.acted_at = Some(now);
                return Decision::StopAi;
            }
        }
        Decision::None
    }

    pub fn acted(&mut self, msg: String) {
        self.message = Some(msg);
    }

    pub fn snooze(&mut self, now: i64, minutes: i64) {
        self.alarm = None;
        self.snoozed_until = Some(now + minutes * 60);
        self.message = Some(format!("{minutes} dakika ertelendi"));
    }

    pub fn manual_stop(&mut self, now: i64, msg: String) {
        self.alarm = None;
        self.acted_at = Some(now);
        self.message = Some(msg);
    }

    pub fn view(&self, cfg: &Config) -> GuardView {
        let lvl = self.gpu_level.max(self.cpu_level);
        let state = if self.alarm.is_some() {
            "alarm"
        } else if self.acted_at.is_some() {
            "acted"
        } else if self.snoozed_until.is_some() && lvl > 0 {
            "snoozed"
        } else if lvl > 0 {
            "warn"
        } else {
            "ok"
        };
        GuardView {
            state: state.into(),
            reason: self.reason.clone(),
            since: self.alarm.map(|a| a.0),
            deadline: self.alarm.map(|a| a.1),
            snoozed_until: self.snoozed_until,
            acted_at: self.acted_at,
            message: self.message.clone(),
            auto_stop_ai: cfg.auto_stop_ai,
            grace_secs: cfg.grace_secs,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::sensor_level;

    #[test]
    fn eşikte_gidip_gelme_seviyeyi_oynatmaz() {
        let mut lvl = 0;
        let mut changes = 0;
        for t in [79.0, 80.0, 79.0, 81.0, 78.0, 80.0, 76.0, 79.5, 74.0, 80.0] {
            let n = sensor_level(t, lvl, 80.0, 87.0, 5.0);
            if n != lvl {
                changes += 1;
            }
            lvl = n;
        }
        // 80'de uyarıya girer, 74'te çıkar, 80'de tekrar girer.
        assert_eq!(changes, 3);
        assert_eq!(sensor_level(83.0, 2, 80.0, 87.0, 5.0), 2);
        assert_eq!(sensor_level(82.0, 2, 80.0, 87.0, 5.0), 1);
    }
}
