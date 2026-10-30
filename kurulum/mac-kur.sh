#!/usr/bin/env bash
# Gözcü Mac uygulamasını derler, /Applications'a kurar ve Mac'in kendi ajanını başlatır.
# Kullanım: bash kurulum/mac-kur.sh [mac-token-dosyası]
# Token verilmezse ve ajan.json yoksa yenisi üretilir; Mac kendiliğinden makine listesine eklenir.
# GOZCU_PAKETLE=1 ile yalnız GOZCU_APP yoluna .app paketi üretilir (sürüm derlemesi için).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="${GOZCU_APP:-/Applications/Gözcü.app}"
SUPPORT="$HOME/Library/Application Support/Gozcu"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "1/4 Derleniyor…"
(cd "$ROOT/ajan" && cargo build --release -q)
(cd "$ROOT/mac" && swift build -c release -q)

echo "2/4 Simge çiziliyor…"
swift "$ROOT/kurulum/simge.swift" "$WORK/icon.png"
mkdir -p "$WORK/AppIcon.iconset"
for s in 16 32 128 256 512; do
  sips -z $s $s "$WORK/icon.png" --out "$WORK/AppIcon.iconset/icon_${s}x${s}.png" >/dev/null
  sips -z $((s * 2)) $((s * 2)) "$WORK/icon.png" --out "$WORK/AppIcon.iconset/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$WORK/AppIcon.iconset" -o "$WORK/AppIcon.icns"

echo "3/4 Uygulama paketleniyor…"
[ "${GOZCU_PAKETLE:-}" = 1 ] || pkill -x Gozcu 2>/dev/null || true
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$ROOT/mac/.build/release/Gozcu" "$APP/Contents/MacOS/Gozcu"
cp "$ROOT/ajan/target/release/gozcu-ajan" "$APP/Contents/Resources/gozcu-ajan"
cp "$WORK/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Gözcü</string>
  <key>CFBundleDisplayName</key><string>Gözcü</string>
  <key>CFBundleIdentifier</key><string>com.oguzhankodal.gozcu</string>
  <key>CFBundleExecutable</key><string>Gozcu</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSAppTransportSecurity</key>
  <dict><key>NSAllowsArbitraryLoads</key><true/></dict>
</dict>
</plist>
PLIST
codesign --force --deep --sign - "$APP" >/dev/null
[ "${GOZCU_PAKETLE:-}" = 1 ] && { echo "Paket: $APP"; exit 0; }

echo "4/4 Mac ajanı kuruluyor…"
mkdir -p "$SUPPORT"
cp "$APP/Contents/Resources/gozcu-ajan" "$SUPPORT/gozcu-ajan"
if { [ -n "${1:-}" ] && [ -f "$1" ]; } || [ ! -f "$SUPPORT/ajan.json" ]; then
  umask 077
  python3 - "${1:-}" "$HOME" > "$SUPPORT/ajan.json.yeni" <<'PY'
import json, secrets, sys
token = open(sys.argv[1]).read().strip() if sys.argv[1] else secrets.token_hex(24)
print(json.dumps({
    "name": "Mac", "listen": "127.0.0.1:7420", "token": token, "user_home": sys.argv[2],
    "auto_stop_ai": False, "sustain_secs": 30, "grace_secs": 180,
    "thresholds": {"cpu_warn": 95, "cpu_danger": 110, "gpu_warn": 200, "gpu_danger": 200},
}, ensure_ascii=False, indent=2))
PY
  mv "$SUPPORT/ajan.json.yeni" "$SUPPORT/ajan.json"
fi
# Mac'in kendisi makine listesinde yoksa ekle
python3 - "$SUPPORT" <<'PY'
import json, os, sys
d = sys.argv[1]
path = os.path.join(d, "makineler.json")
token = json.load(open(os.path.join(d, "ajan.json")))["token"]
try:
    machines = json.load(open(path))
except (OSError, ValueError):
    machines = []
if not any(m.get("url", "").startswith(("http://127.0.0.1:7420", "http://localhost:7420")) for m in machines):
    machines.insert(0, {"name": "Mac", "url": "http://127.0.0.1:7420", "token": token, "icon": "laptopcomputer"})
    with open(os.open(path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600), "w") as f:
        json.dump(machines, f)
PY
PL="$HOME/Library/LaunchAgents/com.oguzhankodal.gozcu.ajan.plist"
cat > "$PL" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>com.oguzhankodal.gozcu.ajan</string>
  <key>ProgramArguments</key>
  <array><string>$SUPPORT/gozcu-ajan</string><string>--config</string><string>$SUPPORT/ajan.json</string></array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>ProcessType</key><string>Background</string>
  <key>StandardErrorPath</key><string>$SUPPORT/ajan.log</string>
</dict>
</plist>
EOF
launchctl bootout "gui/$(id -u)/com.oguzhankodal.gozcu.ajan" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$PL"
open "$APP"
echo "Tamam: $APP"
