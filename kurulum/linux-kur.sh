#!/usr/bin/env bash
# Gözcü ajanını Linux'a kullanıcı servisi olarak kurar.
# Kullanım: bash linux-kur.sh [token-dosyası] [ad]
# Token verilmezse yenisi üretilir ve sonunda ekrana yazılır; ad verilmezse bilgisayar adı kullanılır.
# İkili dosya: betiğin yanındaki gozcu-ajan (sürüm paketi) ya da ajan/target/release/gozcu-ajan.
set -euo pipefail
TOKEN_FILE="${1:-}"
NAME="${2:-$(hostname)}"
HERE="$(cd "$(dirname "$0")" && pwd)"
BIN="$HOME/.local/bin/gozcu-ajan"
CFG_DIR="$HOME/.config/gozcu"

SRC="$HERE/gozcu-ajan"
[ -f "$SRC" ] || SRC="$HERE/../ajan/target/release/gozcu-ajan"
install -Dm755 "$SRC" "$BIN"
mkdir -p "$CFG_DIR"
umask 077
python3 - "$TOKEN_FILE" "$NAME" "$HOME" > "$CFG_DIR/ajan.json" <<'PY'
import json, secrets, sys
token = open(sys.argv[1]).read().strip() if sys.argv[1] else secrets.token_hex(24)
print(json.dumps({
    "name": sys.argv[2], "listen": "0.0.0.0:7420", "token": token, "user_home": sys.argv[3],
    "ollama_url": "http://127.0.0.1:11434", "sustain_secs": 15, "grace_secs": 180, "auto_stop_ai": True,
    "thresholds": {"cpu_warn": 90, "cpu_danger": 98, "gpu_warn": 80, "gpu_danger": 87},
}, ensure_ascii=False, indent=2))
PY
[ -n "$TOKEN_FILE" ] && rm -f "$TOKEN_FILE"

mkdir -p "$HOME/.config/systemd/user"
cat > "$HOME/.config/systemd/user/gozcu-ajan.service" <<EOF
[Unit]
Description=Gözcü ajanı (donanım ve AI takibi)
After=network-online.target

[Service]
ExecStart=$BIN --config $CFG_DIR/ajan.json
Restart=always
RestartSec=5

[Install]
WantedBy=default.target
EOF
systemctl --user daemon-reload
systemctl --user enable --now gozcu-ajan.service
systemctl --user restart gozcu-ajan.service
sleep 2
systemctl --user --no-pager --lines=3 status gozcu-ajan.service | head -5

TOKEN="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["token"])' "$CFG_DIR/ajan.json")"
IP="$(tailscale ip -4 2>/dev/null | head -1 || true)"
echo
echo "Kuruldu. Mac'te Gözcü → Ayarlar → Makine ekle:"
echo "  Ad:     $NAME"
echo "  Adres:  http://${IP:-<tailscale-ip>}:7420"
echo "  Token:  $TOKEN"
