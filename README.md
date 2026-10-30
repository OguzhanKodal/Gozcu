# Gözcü

Mac'in menü çubuğundan evdeki bilgisayarlarını canlı izle: ısı, fanlar, GPU/CPU kullanımı,
şarj, çalışan yapay zekâ modelleri ve günlük token kullanımı. Bir makine tehlikeli ısıya
çıkarsa Gözcü önce bildirim verir; belirli süre içinde müdahale etmezsen **yapay zekâ
işlerini durdurur, oyun açıksa oyuna dokunmaz**.

> *English summary below.*

## Nasıl çalışır

```
 Mac (menü çubuğu + pano)  ──Tailscale──▶  gozcu-ajan  (Windows / Linux / Mac)
                                            • donanım + ısı örnekleme (2 sn)
                                            • Ollama, Claude Code, opencode takibi
                                            • ısı bekçisi (Mac uyusa da çalışır)
```

- **Ajan** (Rust): her izlenen makinede çalışır, `GET /v1/status` ile JSON verir, `POST /v1/action`
  ile komut alır (AI durdur/başlat, ertele, GPU güç sınırı, süreç kapat).
- **Mac uygulaması** (SwiftUI): menü çubuğunda durur; çift tıklayınca panoyu açar.
- **Güvenlik:** ajan yalnız Tailscale ağından (100.64.0.0/10) ve aynı makineden gelen isteklere
  cevap verir; her istek gizli bir token ister.

## Gereksinimler

- Mac: macOS 14 veya üstü
- İzlenen makineler: Windows 10/11 (x64) ya da Linux (x64)
- Tüm makinelerde [Tailscale](https://tailscale.com) (ücretsiz) ve aynı hesapla oturum açılmış olmalı

## Kurulum

En son sürümü [Releases](../../releases) sayfasından indir.

### 1. İzlenecek Windows makine

1. `gozcu-ajan-windows-x86_64.zip` dosyasını indir ve aç.
2. Klasörde PowerShell'i **yönetici olarak** aç ve çalıştır:
   ```powershell
   powershell -ExecutionPolicy Bypass -File .\windows-kur.ps1
   ```
3. Sonunda ekrana **Ad, Adres ve Token** yazılır. Bunları not et (3. adımda lazım).

İşlemci ısısı ve fan devirleri için isteğe bağlı olarak
[LibreHardwareMonitor](https://github.com/LibreHardwareMonitor/LibreHardwareMonitor/releases)'ı
indirip klasörünü verebilirsin: `-LhmDir C:\İndirilenler\LibreHardwareMonitor`.
NVIDIA ekran kartı ısısı bunsuz da görünür.

### 2. İzlenecek Linux makine

```bash
tar xzf gozcu-ajan-linux-x86_64.tar.gz
cd gozcu-ajan-linux-x86_64
bash linux-kur.sh
```

Sonunda ekrana **Ad, Adres ve Token** yazılır.

### 3. Mac

1. `Gozcu-mac.zip` dosyasını indir, aç ve `Gözcü.app`'i **Uygulamalar** klasörüne sürükle.
2. Uygulama Apple tarafından imzalı olmadığı için ilk açılışta uyarı verir. Terminal'de bir kez:
   ```bash
   xattr -dr com.apple.quarantine /Applications/Gözcü.app
   ```
3. Gözcü'yü aç → menü çubuğundaki simge → **Ayarlar** (⌘,) → **Makine ekle** → 1. ve 2.
   adımda yazılan Ad / Adres / Token'ı gir → **Kaydet**.

Mac'in kendisini de izlemek istersen kaynak koddan kurulum (aşağıda) Mac ajanını da kurar ve
listeye ekler.

## Kaynak koddan kurulum

Gerekenler: Xcode komut satırı araçları (`xcode-select --install`) ve [Rust](https://rustup.rs).

```bash
git clone https://github.com/OguzhanKodal/Gozcu.git
cd gozcu
bash kurulum/mac-kur.sh          # Mac uygulaması + Mac ajanı
```

Linux'ta: `cd ajan && cargo build --release && bash ../kurulum/linux-kur.sh`.

## Ayarlar

Ajan ayarları JSON dosyasındadır:

| Sistem  | Dosya                                              |
|---------|----------------------------------------------------|
| Windows | `C:\ProgramData\Gozcu\ajan.json`                   |
| Linux   | `~/.config/gozcu/ajan.json`                        |
| Mac     | `~/Library/Application Support/Gozcu/ajan.json`    |

| Alan | Anlamı |
|------|--------|
| `thresholds.gpu_warn` / `gpu_danger` | GPU uyarı / tehlike ısısı (°C) |
| `thresholds.cpu_warn` / `cpu_danger` | İşlemci uyarı / tehlike ısısı (°C) |
| `thresholds.hysteresis` | Seviyeden çıkmak için ısının eşiğin kaç derece altına inmesi gerektiği (varsayılan 5) |
| `sustain_secs` | Tehlike kaç saniye sürerse alarm başlar |
| `grace_secs` | Alarmdan sonra kaç saniye içinde müdahale edilmezse AI durdurulur |
| `auto_stop_ai` | `false` ise ajan hiçbir şeyi kendiliğinden durdurmaz, yalnız alarm verir |

Değiştirdikten sonra ajanı yeniden başlat (Windows: Görev Zamanlayıcı → `Gozcu\Ajan`;
Linux: `systemctl --user restart gozcu-ajan`).

## Kaldırma

- **Windows** (yönetici PowerShell):
  `Unregister-ScheduledTask -TaskPath \Gozcu\ -TaskName Ajan -Confirm:$false; Remove-Item -Recurse C:\ProgramData\Gozcu`
- **Linux:** `systemctl --user disable --now gozcu-ajan && rm -rf ~/.local/bin/gozcu-ajan ~/.config/gozcu ~/.config/systemd/user/gozcu-ajan.service`
- **Mac:** `launchctl bootout gui/$(id -u)/com.oguzhankodal.gozcu.ajan; rm -rf /Applications/Gözcü.app ~/Library/Application\ Support/Gozcu ~/Library/LaunchAgents/com.oguzhankodal.gozcu.ajan.plist`

---

## English

**Gözcü** ("watchman") is a macOS menu-bar dashboard for monitoring your other machines over
[Tailscale](https://tailscale.com): temperatures, fans, GPU/CPU load, battery, running AI models
(Ollama) and daily token usage (Claude Code, opencode). If a machine stays at a dangerous
temperature it alerts you, and if you don't respond it stops the AI workloads while leaving games
running.

- Download the latest build from [Releases](../../releases).
- Windows: run `windows-kur.ps1` as Administrator. Linux: run `linux-kur.sh`.
  Each prints a name, address and token — add them in the Mac app under **Settings → Makine ekle**.
- The agent only answers requests from Tailscale (100.64.0.0/10) or localhost and requires a bearer token.
- The UI is currently in Turkish.

License: MIT
