#!/usr/bin/env bash
# ==================================================================
#  VAST MONITOR - tu kiem tra may Vast moi 5 phut, bao loi qua Discord
#  Cai:      sudo bash vast_monitor.sh install
#  Thu bao:  sudo vast-monitor test
#  Xem:      sudo vast-monitor status
#  Go bo:    sudo vast-monitor uninstall
# ==================================================================
set -uo pipefail
CONF=/etc/vast-monitor.conf
STATE=/var/lib/vast-monitor
BIN=/usr/local/bin/vast-monitor
VASTAI=/usr/local/bin/vastai
GRN='\e[32m'; YEL='\e[33m'; RED='\e[31m'; NC='\e[0m'

[[ $EUID -eq 0 ]] || { echo "Chay bang sudo: sudo bash $0 ${1:-}"; exit 1; }
mkdir -p "$STATE"

# ---------------------------------------------------------------- cau hinh
DISCORD_URL=""; NAME="$(hostname)"; EXPECTED_GPUS=""; TEMP_MAX=85; DISK_MAX=90; HB_HOUR=8
[[ -f "$CONF" ]] && . "$CONF"
MID="$(cat /root/vast_machine_id 2>/dev/null)"
[[ "$MID" =~ ^[0-9]+$ ]] || MID=""
LABEL="$NAME${MID:+ (ID $MID)}"

# ---------------------------------------------------------------- gui tin
send() {
  local msg="[$LABEL] $*"
  echo "$(date '+%F %T') $msg" >> "$STATE/log"
  [[ -n "$DISCORD_URL" ]] || return 0
  local payload
  payload="$(python3 -c 'import json,sys; print(json.dumps({"content": sys.argv[1][:1900]}))' "$msg")"
  curl -s -m 15 -H "Content-Type: application/json" -d "$payload" "$DISCORD_URL" >/dev/null 2>&1
}
getv() { cat "$STATE/$1" 2>/dev/null; }
setv() { printf '%s' "$2" > "$STATE/$1"; }

# loi bat/tat: chi bao khi trang thai THAY DOI (khong spam)
issue() { # issue <ten> <0|1 dang loi> <tin khi loi> <tin khi het loi>
  local key="iss_$1" now="$2" prev; prev="$(getv "$key")"
  if [[ "$now" == 1 && "$prev" != 1 ]]; then send "⚠️ $3"
  elif [[ "$now" != 1 && "$prev" == 1 ]]; then send "✅ $4"; fi
  setv "$key" "$now"
}

# ---------------------------------------------------------------- kiem tra
run_checks() {
  local summary=()

  # 1. Khoi dong lai
  local boot; boot="$(cat /proc/sys/kernel/random/boot_id)"
  if [[ -n "$(getv boot_id)" && "$(getv boot_id)" != "$boot" ]]; then
    send "🔄 May vua khoi dong lai (luc $(uptime -s))"
  fi
  setv boot_id "$boot"

  # 2. IP noi bo (doi IP -> phai sua Port Forwarding tren modem)
  local lip; lip="$(ip -4 route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="src"){print $(i+1); exit}}')"
  local old_lip; old_lip="$(getv local_ip)"
  if [[ -n "$lip" && -n "$old_lip" && "$lip" != "$old_lip" ]]; then
    send "🚨 DOI IP NOI BO: $old_lip -> $lip. Sua Port Forwarding tren modem ve $lip va khoa IP theo MAC $(cat /sys/class/net/$(ip route show default | awk '{print $5; exit}')/address 2>/dev/null)"
  fi
  [[ -n "$lip" ]] && setv local_ip "$lip"
  summary+=("IP noi bo: ${lip:-?}")

  # 3. Internet + IP public
  local pip; pip="$(curl -4 -s -m 10 ifconfig.me 2>/dev/null || true)"
  [[ "$pip" =~ ^[0-9.]+$ ]] || pip="$(curl -4 -s -m 10 api.ipify.org 2>/dev/null || true)"
  [[ "$pip" =~ ^[0-9.]+$ ]] || pip=""
  if [[ -z "$pip" ]]; then
    [[ -z "$(getv net_down_since)" ]] && setv net_down_since "$(date '+%F %T')"
  else
    if [[ -n "$(getv net_down_since)" ]]; then
      send "🌐 Mang da co lai (mat mang tu $(getv net_down_since))"; rm -f "$STATE/net_down_since"
    fi
    local old_pip; old_pip="$(getv public_ip)"
    [[ -n "$old_pip" && "$pip" != "$old_pip" ]] && send "🌐 Doi IP public: $old_pip -> $pip (mo lai port tren modem neu doi mang)"
    setv public_ip "$pip"
  fi
  summary+=("IP public: ${pip:-MAT MANG}")

  # 4. Dich vu Vast
  local va; va="$(systemctl is-active vastai 2>/dev/null)"
  if [[ "$va" != active ]]; then
    systemctl restart vastai 2>/dev/null; sleep 5; va="$(systemctl is-active vastai 2>/dev/null)"
  fi
  issue vastai "$([[ "$va" == active ]] && echo 0 || echo 1)" \
    "Dich vu vastai KHONG chay (da thu khoi dong lai). SSH vao: sudo systemctl status vastai" \
    "Dich vu vastai da chay lai"
  summary+=("vastai: $va")

  # 5. Card
  local n; n="$(nvidia-smi -L 2>/dev/null | grep -c '^GPU')"
  [[ -n "$EXPECTED_GPUS" ]] || EXPECTED_GPUS="$n"
  issue gpu "$([[ "$n" -lt "$EXPECTED_GPUS" ]] && echo 1 || echo 0)" \
    "Chi thay $n/$EXPECTED_GPUS card! Kiem tra day nguon/khe card (nvidia-smi -L)" \
    "Da thay du $n/$EXPECTED_GPUS card"
  local tmax; tmax="$(nvidia-smi --query-gpu=temperature.gpu --format=csv,noheader,nounits 2>/dev/null | sort -n | tail -1)"
  tmax="${tmax:-0}"
  issue temp "$([[ "$tmax" -ge "$TEMP_MAX" ]] && echo 1 || echo 0)" \
    "Card qua nong: ${tmax}°C (nguong $TEMP_MAX). Tang quat / ve sinh may" \
    "Nhiet do card on lai: ${tmax}°C"
  summary+=("Card: $n/$EXPECTED_GPUS, nong nhat ${tmax}°C")

  # 6. Loi PCIe (Vast se an may neu loi nhieu)
  local pe old_pe; pe="$(dmesg 2>/dev/null | grep -c 'PCIe Bus Error')"
  old_pe="$(getv pcie_err)"
  if [[ -n "$old_pe" && "$pe" -gt "$old_pe" ]]; then
    local last; last="$(getv pcie_alert_ts)"; last="${last:-0}"
    if (( $(date +%s) - last > 3600 )); then
      send "⚠️ Loi PCIe moi: +$((pe - old_pe)) (tong $pe tu luc khoi dong). Vast co the bao 'GPU PCIE issue'. Kiem tra: sudo dmesg | grep 'PCIe Bus Error' | tail"
      setv pcie_alert_ts "$(date +%s)"
    fi
  fi
  setv pcie_err "$pe"
  summary+=("Loi PCIe: $pe")

  # 7. O Docker
  local du; du="$(df --output=pcent /var/lib/docker 2>/dev/null | tail -1 | tr -dc 0-9)"
  du="${du:-0}"
  issue disk "$([[ "$du" -ge "$DISK_MAX" ]] && echo 1 || echo 0)" \
    "O Docker day ${du}% - khach co the khong chay duoc" \
    "O Docker con trong (${du}%)"
  summary+=("O Docker: ${du}%")

  # 8. Khach thue (container ten C.xxxx)
  local nr old_nr; nr="$(docker ps --format '{{.Names}}' 2>/dev/null | grep -c '^C\.')"
  old_nr="$(getv renters)"
  if [[ -n "$old_nr" && "$nr" != "$old_nr" ]]; then
    if (( nr > old_nr )); then send "💰 Co khach moi! Dang chay $nr may cho khach"
    else send "👋 Khach vua dung/tra may. Con $nr may dang chay"; fi
  fi
  setv renters "$nr"
  summary+=("Khach dang chay: $nr")

  # 9. Tren cho Vast co bi an khong (can vastai + API key + ID may)
  if [[ -x "$VASTAI" && -n "$MID" ]]; then
    local js hidden=0 why=""
    js="$("$VASTAI" search offers "machine_id=$MID verified=any rentable=any rented=any" --raw 2>/dev/null)"
    if [[ "$js" == \[* ]]; then
      read -r hidden why < <(python3 -c '
import json,sys
o=json.loads(sys.argv[1])
if not o: print(1, "khong_thay_tren_cho"); sys.exit()
bad=[x for x in o if not x.get("rentable") and not x.get("rented")]
print(1 if bad else 0, "goi_"+",".join(str(x.get("id")) for x in bad) if bad else "ok")' "$js" 2>/dev/null || echo "0 ?")
      issue listing "$hidden" \
        "May KHONG cho thue duoc tren Vast ($why). Xem web: co bao loi do (GPU PCIE issue...) hoac chua list?" \
        "May da hien lai tren cho Vast"
      summary+=("Tren cho: $([[ "$hidden" == 1 ]] && echo "BI AN ($why)" || echo ok)")
    fi
  fi

  # 10. Bao cao hang ngay (biet cong cu van song)
  if [[ "$(date +%H)" == "$(printf '%02d' "$HB_HOUR")" && "$(getv hb_day)" != "$(date +%F)" ]]; then
    send "📋 Bao cao hang ngay: $(IFS=' | '; echo "${summary[*]}")"
    setv hb_day "$(date +%F)"
  fi
  printf '%s\n' "${summary[@]}" > "$STATE/last_summary"
}

# ---------------------------------------------------------------- cai dat
do_install() {
  echo -e "${YEL}=== CAI VAST MONITOR ===${NC}"
  echo "Can 1 link Discord webhook (lam 1 lan, dung chung cho moi may):"
  echo "  Discord -> server cua ban -> kenh (vd #vast) -> banh rang 'Edit Channel'"
  echo "  -> Integrations -> Webhooks -> New Webhook -> Copy Webhook URL"
  local url name exp
  while true; do
    read -r -p "Dan link webhook (https://discord.com/api/webhooks/...): " url; url="$(echo "$url" | xargs)"
    [[ "$url" =~ ^https://(discord|discordapp)\.com/api/webhooks/ ]] && break
    echo -e "${RED}Link khong dung dang${NC}"
  done
  read -r -p "Ten may de nhan biet (vd may-3060, Enter = $(hostname)): " name; name="${name:-$(hostname)}"
  local n; n="$(nvidia-smi -L 2>/dev/null | grep -c '^GPU')"
  read -r -p "So card may nay phai co (Enter = $n): " exp; exp="${exp:-$n}"
  umask 077
  cat > "$CONF" <<EOF
DISCORD_URL="$url"
NAME="$name"
EXPECTED_GPUS="$exp"
TEMP_MAX=85
DISK_MAX=90
HB_HOUR=8
EOF
  chmod 600 "$CONF"
  install -m 755 "$0" "$BIN"
  cat > /etc/systemd/system/vast-monitor.service <<EOF
[Unit]
Description=Vast monitor
After=network-online.target
[Service]
Type=oneshot
ExecStart=$BIN run
EOF
  cat > /etc/systemd/system/vast-monitor.timer <<EOF
[Unit]
Description=Vast monitor moi 5 phut
[Timer]
OnBootSec=2min
OnUnitActiveSec=5min
[Install]
WantedBy=timers.target
EOF
  systemctl daemon-reload
  systemctl enable --now vast-monitor.timer >/dev/null 2>&1
  . "$CONF"; LABEL="$NAME${MID:+ (ID $MID)}"
  "$BIN" run
  send "✅ Da cai Vast monitor. Kiem tra moi 5 phut, bao cao hang ngay luc ${HB_HOUR}h."
  echo -e "${GRN}[OK] Da cai. Mo Discord xem tin nhan thu.${NC}"
  echo "Lenh: sudo vast-monitor status | test | uninstall"
}

case "${1:-}" in
  install)   do_install ;;
  run)       run_checks ;;
  test)      send "🔔 Tin nhan thu - Vast monitor dang hoat dong"; echo "Da gui - xem Discord" ;;
  status)    echo "--- Lan kiem tra gan nhat ---"; cat "$STATE/last_summary" 2>/dev/null
             echo "--- 10 thong bao gan nhat ---"; tail -n 10 "$STATE/log" 2>/dev/null
             systemctl list-timers vast-monitor.timer --no-pager | head -3 ;;
  uninstall) systemctl disable --now vast-monitor.timer >/dev/null 2>&1
             rm -f /etc/systemd/system/vast-monitor.{service,timer} "$BIN" "$CONF"; rm -rf "$STATE"
             systemctl daemon-reload; echo "Da go Vast monitor" ;;
  *) echo "Cach dung: sudo bash $0 install | sudo vast-monitor [status|test|run|uninstall]" ;;
esac
