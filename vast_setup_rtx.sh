#!/usr/bin/env bash
# ==================================================================
#  CAI MAY CHO THUE GPU TREN VAST.AI
#  >>> KICH BAN DANH CHO CARD RTX: RTX 3060 12GB, RTX 2060 12GB <<<
#  (cung dung duoc cho RTX 20xx / 30xx / 40xx khac)
#  GTX 1080 / 10xx -> dung file vast_setup.sh (KHONG dung file nay)
#
#  CHI CAN 1 LENH, chay lai dung lenh nay sau moi lan khoi dong lai:
#     sudo bash vast_setup_rtx.sh
#  Lenh phu:
#     sudo bash vast_setup_rtx.sh check    -> chi kiem tra cau hinh
#     sudo bash vast_setup_rtx.sh status   -> xem dang o buoc nao
#     sudo bash vast_setup_rtx.sh port     -> hien lai thong tin cai modem
#     sudo bash vast_setup_rtx.sh vm       -> bat lai VM (khi may KHONG co khach)
#     sudo bash vast_setup_rtx.sh selftest -> chay self-test (khi do tin cay > 90%)
#     sudo bash vast_setup_rtx.sh reset    -> lam lai tu dau
#
#  Kinh nghiem tu may that (RTX 2060 12GB, X99-T8D, 2 CPU, Ubuntu 22.04):
#   - Card RTX dung driver 580 cua Ubuntu (CUDA 13) -> NCCL test cua Vast chay tot.
#   - Vast tu choi cai neu SSH con cho dang nhap mat khau -> tat o moi noi.
#   - VM: can tham so 'initcall_blacklist=sysfb_init video=efifb:off' (neu khong
#     loi 'BAR 3: can't reserve' -> GPU khong vao duoc VM).
#   - Script bat VM cua Vast co the doi ten vastai.service -> .mask roi bo do
#     -> may Offline. Script nay tu khoi phuc.
#   - Doi khe card -> ten card mang doi -> netplan khop "en*".
#   - Khi dang co khach Docker, web hien VM: Disabled la binh thuong.
#   - Sau khi cai, neu web khong cho thue ("rentable": false) -> khoi dong lai may.
# ==================================================================
set -uo pipefail

GH_USER="chucn2005hn"                 # lay SSH key tu github.com/<ten>.keys
DRIVER_PKG="nvidia-driver-580"         # driver Ubuntu cho card RTX
STATE=/root/vast_stage
PORT_FILE=/root/vast_port_range
NO_FILE=/root/vast_machine_no
ID_FILE=/root/vast_machine_id
VASTAI=/usr/local/bin/vastai
SELF="$(readlink -f "$0")"

RED='\033[1;31m'; GRN='\033[1;32m'; YEL='\033[1;33m'; NC='\033[0m'
ok()   { echo -e "${GRN}[OK]${NC} $*"; }
warn() { echo -e "${YEL}[CHU Y]${NC} $*"; }
err()  { echo -e "${RED}[LOI]${NC} $*"; }
step() { echo; echo -e "${GRN}==== $* ====${NC}"; }
ask()  { local a; read -r -p "$1 [y/N]: " a; [[ "$a" =~ ^[Yy]$ ]]; }
box()  { echo; echo -e "${YEL}##########################################################${NC}";
         for l in "$@"; do echo -e "${YEL}#${NC}  $l"; done
         echo -e "${YEL}##########################################################${NC}"; echo; }

[[ $EUID -eq 0 ]] || { err "Hay chay bang sudo:  sudo bash $0 $*"; exit 1; }
REAL_USER="${SUDO_USER:-root}"
REAL_HOME="$(getent passwd "$REAL_USER" | cut -d: -f6)"
export DEBIAN_FRONTEND=noninteractive

# ------------------------------------------------------------------ GPU
pci_gpus()   { lspci 2>/dev/null | grep -i nvidia | grep -iE 'VGA|3D controller'; }
n_pci_gpus() { pci_gpus | wc -l; }
n_smi_gpus() { nvidia-smi -L 2>/dev/null | grep -c '^GPU' || true; }
is_pascal()  { pci_gpus | grep -qiE 'GP10[0-9]|GTX 10[5-8]0|TITAN X?p'; }
is_rtx()     { pci_gpus | grep -qiE 'RTX|TU10[0-9]|TU11[0-9]|GA10[0-9]|AD10[0-9]'; }
gpu_models() { pci_gpus | sed -E 's/.*\[(.*)\].*/\1/' | sort | uniq -c; }
cuda_ver()   { nvidia-smi 2>/dev/null | sed -nE 's/.*CUDA Version: ([0-9.]+).*/\1/p' | head -1; }

# ------------------------------------------------------------------ KIEM TRA
preflight() {
  local want="${1:-}" FAIL=0
  pass() { echo -e "  ${GRN}[DU]${NC}    $*"; }
  miss() { echo -e "  ${RED}[THIEU]${NC} $1"; echo -e "          -> Sua: $2"; FAIL=$((FAIL+1)); }
  note() { echo -e "  ${YEL}[CHU Y]${NC} $1"; echo -e "          -> $2"; }
  command -v lspci >/dev/null 2>&1 || apt-get install -y pciutils >/dev/null 2>&1

  step "KIEM TRA CAU HINH"
  . /etc/os-release 2>/dev/null
  [[ "${VERSION_ID:-}" == "22.04" ]] && pass "Ubuntu 22.04" \
    || note "He dieu hanh: ${PRETTY_NAME:-?}" "Kich ban da test tren Ubuntu 22.04"

  grep -qE 'vmx|svm' /proc/cpuinfo && pass "CPU bat ao hoa (VT-x)" \
    || miss "CPU chua bat ao hoa" "BIOS -> Intel Virtualization Technology = Enabled"
  echo -e "          CPU: $(lscpu | awk -F: '/Model name/{sub(/^ +/,"",$2);print $2;exit}') x $(lscpu | awk -F: '/^Socket/{gsub(/ /,"",$2);print $2}') | RAM: $(free -g | awk '/^Mem:/{print $2}')GB"

  if command -v mokutil >/dev/null 2>&1 && mokutil --sb-state 2>/dev/null | grep -qi enabled; then
    miss "Secure Boot dang BAT (driver NVIDIA se khong chay)" "BIOS -> tat Secure Boot"
  else pass "Secure Boot tat"; fi

  # GPU
  pci_gpus | sed 's/^/          /'
  local pci; pci="$(n_pci_gpus)"
  if [[ "$pci" -eq 0 ]]; then miss "Khong thay card NVIDIA nao" "Kiem tra card, day nguon"; fi
  if [[ "$pci" -gt 0 ]] && is_pascal; then
    miss "Co card GTX 10xx (Pascal)" "Card GTX 1080/10xx dung file vast_setup.sh, KHONG dung file RTX nay"
  elif [[ "$pci" -gt 0 ]] && ! is_rtx; then
    note "Khong nhan ra la card RTX" "Kich ban da test voi RTX 2060/3060"
  fi
  if [[ "$(gpu_models | wc -l)" -gt 1 ]]; then
    note "May co NHIEU LOAI card khac nhau:" "Nen moi may chi 1 loai card (vd may A: 3060, may B: 2060) de Vast liet ke dung"
    gpu_models | sed 's/^/            /'
  fi
  if [[ -z "$want" ]]; then read -r -p "  Ban da CAM bao nhieu card vao may? " want; fi
  [[ "$want" =~ ^[0-9]+$ ]] || want="$pci"
  if [[ "$pci" -lt "$want" ]]; then
    miss "Main chi thay $pci/$want card" "Day nguon 8-pin, cam lai/doi khe, BIOS bat 'Above 4G Decoding'. (Main 2 CPU: khe noi CPU2 chi chay khi lap du 2 CPU)"
  else pass "Main thay du $pci/$want card"; fi
  if command -v nvidia-smi >/dev/null 2>&1; then
    local smi; smi="$(n_smi_gpus)"
    [[ "$smi" -lt "$pci" ]] && miss "Driver chi nhan $smi/$pci card" "Card thieu nguon hoac loi"
    echo -e "          Driver hien tai: $(nvidia-smi --query-gpu=driver_version --format=csv,noheader 2>/dev/null | head -1)  CUDA $(cuda_ver)"
  fi

  # RAM / o dia
  local ram; ram="$(free -g | awk '/^Mem:/{print $2}')"
  [[ "$ram" -ge 16 ]] && pass "RAM ${ram}GB" || miss "RAM chi ${ram}GB" "Nen >= 16GB"
  lsblk -d -o NAME | grep -q '^nvme' && pass "Co o NVMe" \
    || note "Khong thay o NVMe" "O cham (HDD/USB) lam khach ne may"
  if mountpoint -q /var/lib/docker; then
    pass "/var/lib/docker da co phan vung rieng ($(df -h --output=size /var/lib/docker | tail -1 | xargs))"
  else
    local vg free_g=0; vg="$(vgs --noheadings -o vg_name 2>/dev/null | head -n1 | xargs)"
    [[ -n "$vg" ]] && free_g="$(vgs --noheadings --units g --nosuffix -o vg_free "$vg" | xargs | cut -d. -f1)"
    [[ "$free_g" -gt 120 ]] && pass "Con ${free_g}GB trong LVM cho Docker" \
      || miss "Khong du cho trong cho Docker (${free_g}GB)" "Cai lai Ubuntu, chua trong >150GB tren NVMe"
  fi
  lsblk -d -o NAME,TRAN | grep -qi usb && note "Co o USB cam vao may" "Khong de Vast dung o USB"

  # Mang
  local nics; nics="$(ip -4 -o addr show | awk '{print $2}' | grep -cE '^(en|eth)')"
  [[ "$nics" -le 1 ]] && pass "Chi 1 card mang co IP" \
    || note "$nics card mang co IP" "Chi cam 1 day LAN (tranh Vast nham IP)"
  curl -s --max-time 8 -o /dev/null https://console.vast.ai && pass "Internet OK" \
    || miss "Khong vao duoc Internet" "Kiem tra day mang / DNS"

  echo
  if [[ "$FAIL" -eq 0 ]]; then ok "CAU HINH DU"; return 0
  else err "THIEU $FAIL MUC - sua roi chay lai: sudo bash $SELF check"; return 1; fi
}

# ------------------------------------------------------------------ SSH
have_key() { [[ -s "$REAL_HOME/.ssh/authorized_keys" ]] && grep -qE '^(ssh-|ecdsa-)' "$REAL_HOME/.ssh/authorized_keys"; }
add_key_line() {
  local k="$1"
  echo "$k" | ssh-keygen -lf - >/dev/null 2>&1 || return 1
  mkdir -p "$REAL_HOME/.ssh"; touch "$REAL_HOME/.ssh/authorized_keys"
  grep -qxF "$k" "$REAL_HOME/.ssh/authorized_keys" || echo "$k" >> "$REAL_HOME/.ssh/authorized_keys"
  chmod 700 "$REAL_HOME/.ssh"; chmod 600 "$REAL_HOME/.ssh/authorized_keys"
  chown -R "$REAL_USER:" "$REAL_HOME/.ssh"
}
ensure_ssh_key() {
  if have_key; then ok "Da co SSH key cho $REAL_USER"; return 0; fi
  local gk; gk="$(curl -fsS --max-time 10 "https://github.com/$GH_USER.keys" 2>/dev/null || true)"
  if [[ -n "$gk" ]]; then
    while IFS= read -r line; do [[ -n "$line" ]] && add_key_line "$line"; done <<< "$gk"
    have_key && { ok "Da lay SSH key tu github.com/$GH_USER.keys"; return 0; }
  fi
  box "DEN LUOT BAN: DAN SSH KEY CUA MAY WINDOWS" \
      "Tren Windows mo CMD, go:   type %USERPROFILE%\\.ssh\\id_ed25519.pub" \
      "Copy NGUYEN dong hien ra (bat dau bang ssh-ed25519), dan vao day."
  local k
  while true; do
    read -r -p "Dan SSH key: " k; k="$(echo "$k" | xargs)"
    add_key_line "$k" && { ok "Da them SSH key"; return 0; }
    err "Key khong hop le (phai bat dau bang ssh-ed25519 / ssh-rsa). Thu lai."
  done
}
ssh_pw_off() { local o; o="$(sshd -T 2>/dev/null)"; grep -qi '^passwordauthentication no' <<<"$o"; }
disable_password_login() {
  have_key || { err "Chua co SSH key - KHONG tat mat khau."; return 1; }
  sed -i '/^\s*#\?\s*PasswordAuthentication/d;/^\s*KbdInteractiveAuthentication/d' \
    /etc/ssh/sshd_config /etc/ssh/sshd_config.d/*.conf 2>/dev/null || true
  printf 'PasswordAuthentication no\nKbdInteractiveAuthentication no\nPubkeyAuthentication yes\n' \
    > /etc/ssh/sshd_config.d/00-vast.conf
  echo 'PasswordAuthentication no' >> /etc/ssh/sshd_config
  mkdir -p /etc/cloud/cloud.cfg.d && echo 'ssh_pwauth: false' > /etc/cloud/cloud.cfg.d/99-vast-ssh.cfg
  mkdir -p /run/sshd; ssh-keygen -A >/dev/null 2>&1 || true
  local t_out; t_out="$(sshd -t 2>&1)" || { err "Loi cau hinh SSH: $t_out"; }
  systemctl restart ssh 2>/dev/null || systemctl restart sshd 2>/dev/null || true
  sleep 1
  if ssh_pw_off; then
    ok "Da tat dang nhap SSH bang mat khau (chi vao bang key)"
    warn "Dang nhap truc tiep tai may (ban phim + man hinh) van dung mat khau binh thuong."
  else
    err "Chua tat duoc mat khau:"; grep -rn -i PasswordAuthentication /etc/ssh/sshd_config /etc/ssh/sshd_config.d/
    sshd -T 2>&1 | grep -i -E 'passwordauth|error|fatal' | head -5
    systemctl --no-pager -l status ssh 2>&1 | tail -5
    return 1
  fi
}

# ------------------------------------------------------------------ PORT / MODEM
load_net_info() {
  PR="$(cat "$PORT_FILE" 2>/dev/null || echo 50000-50999)"
  MNO="$(cat "$NO_FILE" 2>/dev/null || echo 1)"
  NIC="$(ip route show default | awk '{print $5; exit}')"
  LAN_IP="$(ip -4 -o addr show "$NIC" | awk '{print $4}' | cut -d/ -f1 | head -n1)"
  MAC="$(cat /sys/class/net/"$NIC"/address 2>/dev/null)"
  GW="$(ip route show default | awk '{print $3; exit}')"
  PUB_IP="$(curl -4 -s --max-time 8 ifconfig.me || echo 'khong lay duoc')"
  P_START="${PR%-*}"; P_END="${PR#*-}"
}
print_port_box() {
  echo
  echo -e "${YEL}##########################################################${NC}"
  echo -e "${YEL}#   THONG TIN CAI PORT TREN MODEM (MANG NAY)             #${NC}"
  echo -e "${YEL}##########################################################${NC}"
  echo -e "  Trang modem          : ${GRN}http://$GW${NC}   (tai khoan: tem duoi day modem)"
  echo
  echo -e "  [0] KIEM TRA IP PUBLIC: modem -> Status -> 'WAN IP' phai = ${GRN}$PUB_IP${NC}"
  echo -e "      WAN IP dang 100.x / 10.x / 172.16-31.x => CGNAT -> goi nha mang xin IP public"
  echo
  if [[ "$MNO" == "1" ]]; then
    echo -e "  [1] MAY THU 1 TRONG MANG - chon 1 trong 2:"
    echo -e "      CACH A - DMZ (de nhat): bat DMZ -> IP ${GRN}$LAN_IP${NC}"
    echo -e "      CACH B - Port Forwarding / Virtual Server:"
  else
    echo -e "  [1] MAY THU $MNO TRONG MANG - BAT BUOC Port Forwarding (GIU nguyen DMZ cua may 1):"
  fi
  echo -e "        Ten             : ${GRN}vast-may$MNO${NC}"
  echo -e "        Cong ngoai (WAN): ${GRN}$PR${NC}"
  echo -e "        Cong trong (LAN): ${GRN}$PR${NC}   (modem chi cho 1 o -> dien ${GRN}$P_START${NC})"
  echo -e "        IP may nay      : ${GRN}$LAN_IP${NC}"
  echo -e "        Giao thuc       : ${GRN}TCP + UDP (Both)${NC}"
  echo
  echo -e "  [2] CO DINH IP (DHCP Reservation / IP MAC binding):"
  echo -e "      >>> MAC may nay  : ${GRN}$MAC${NC}   <<< (script tu lay)"
  echo -e "      >>> IP may nay   : ${GRN}$LAN_IP${NC}"
  echo
  echo -e "  [3] KIEM TRA: https://portchecker.co -> IP ${GRN}$PUB_IP${NC}, port ${GRN}$P_START${NC} -> phai Open"
  echo -e "${YEL}##########################################################${NC}"
}
port_step() {
  step "MO PORT TREN MODEM"
  echo "May nay la MAY THU MAY trong cung 1 modem?"
  echo "  - Moi may 1 mang rieng -> Enter (= 1)"
  echo "  - Nhieu may chung 1 modem -> may dau 1, may sau 2, 3 ..."
  echo "  - Muon tu chon dai port (vd modem bao trung) -> go dai, vd 40000-40999"
  local old no a b; old="$(cat "$NO_FILE" 2>/dev/null || echo 1)"
  while true; do
    read -r -p "May thu may? (Enter = $old): " no; no="${no:-$old}"; no="${no// /}"
    if [[ "$no" =~ ^([0-9]{4,5})-([0-9]{4,5})$ ]]; then
      a=${BASH_REMATCH[1]}; b=${BASH_REMATCH[2]}
      if (( a >= 1024 && b <= 65535 && b - a >= 99 )); then
        echo -n "$a-$b" > "$PORT_FILE"; echo -n 1 > "$NO_FILE"; break
      fi
      err "Dai port phai trong 1024-65535 va >= 100 port (vd 40000-40999)"; continue
    fi
    if [[ "$no" =~ ^[1-9][0-9]?$ ]]; then
      echo -n "$no" > "$NO_FILE"
      a=$((50000 + (no - 1) * 1000)); echo -n "${a}-$((a + 999))" > "$PORT_FILE"; break
    fi
    err "Nhap 1 so (1, 2, 3...) hoac 1 dai port (vd 40000-40999)"
  done
  load_net_info
  print_port_box
  python3 -m http.server "$P_START" --bind 0.0.0.0 >/dev/null 2>&1 &
  local hp=$!
  echo -e "Da mo tam port ${GRN}$P_START${NC} de kiem tra."
  echo "Cai modem theo khung tren, roi vao portchecker.co kiem tra:"
  echo "  Open   -> bam Enter de tiep tuc"
  echo "  Closed -> xem lai muc [0] va [1]; neu chua sua duoc van bam Enter, sua modem sau"
  read -r -p "Bam Enter khi xong... " _
  kill "$hp" 2>/dev/null || true
}

# ------------------------------------------------------------------ SELF-TEST
ensure_vastai_cli() {
  if [[ ! -x "$VASTAI" ]]; then
    apt-get install -y python3-pip >/dev/null 2>&1
    python3 -m pip install -q vastai || { err "Cai cong cu vastai loi"; return 1; }
  fi
  [[ -x "$VASTAI" ]] || VASTAI="$(command -v vastai)"
  if ! "$VASTAI" show user >/dev/null 2>&1; then
    box "DEN LUOT BAN: NHAP API KEY CUA VAST" \
        "1. Mo https://cloud.vast.ai/manage-keys/" \
        "2. Muc 'API Keys' -> + New -> dat ten (vd may-3060-<so>) -> copy key" \
        "3. Dan key vao day, Enter   (KHONG gui key cho ai)"
    local k
    while true; do
      read -r -p "Dan API key: " k; k="$(echo "$k" | xargs)"
      [[ -n "$k" ]] || continue
      "$VASTAI" set api-key "$k" >/dev/null && "$VASTAI" show user >/dev/null 2>&1 && break
      err "Key sai (luu y: day la API key, KHONG phai key trong lenh cai Vast). Thu lai."
    done
  fi
  ok "Cong cu vastai san sang"
}
find_machine_id() {
  local id; id="$(cat "$ID_FILE" 2>/dev/null)"
  if [[ -z "$id" ]]; then
    load_net_info
    id="$("$VASTAI" show machines --raw 2>/dev/null | python3 -c '
import sys, json
ip = sys.argv[1]
try:
    d = json.load(sys.stdin)
    ms = d.get("machines", d) if isinstance(d, dict) else d
    c = [m for m in ms if str(m.get("public_ipaddr","")).strip() == ip]
    c.sort(key=lambda m: m.get("id", 0))
    print(c[-1]["id"] if c else "")
except Exception:
    print("")
' "$PUB_IP")"
    if [[ -z "$id" ]]; then
      read -r -p "Khong tu tim duoc ID may. Nhap ID may (xem tren trang Machines): " id
    fi
    echo -n "$id" > "$ID_FILE"
  fi
  MACHINE_ID="$id"
}
run_selftest() {
  ensure_vastai_cli || return 1
  find_machine_id
  step "SELF-TEST MAY $MACHINE_ID"
  local out; out="$("$VASTAI" self-test machine "$MACHINE_ID" 2>&1)"; echo "$out" | tail -n 25
  if echo "$out" | grep -qi 'reliability'; then
    box "CHUA DU DO TIN CAY (can > 90%) - BINH THUONG VOI MAY MOI" \
        "Cu de may chay 24/7, 1-2 ngay sau chay lai:" \
        "    sudo bash $SELF selftest" \
        "Xem do tin cay: so % canh hinh ngon tay cai tren the may (web)."
  elif echo "$out" | grep -qi -e 'passed' -e 'success'; then
    ok "SELF-TEST DAT - may se duoc Verified sau it phut/gio"
  else
    warn "Xem ket qua o tren. Neu loi khac 'reliability', chup gui ho tro."
  fi
}

# ------------------------------------------------------------------ GIA GOI Y
suggest_price() {
  if pci_gpus | grep -qi '3060'; then PRICE="0.08"; MINBID="0.06"
  elif pci_gpus | grep -qi '2060'; then PRICE="0.06"; MINBID="0.05"
  else PRICE="0.08"; MINBID="0.06"; fi
}

# ------------------------------------------------------------------ VM
enable_vm() {
  step "BAT VM (cho khach thue may ao)"
  if [[ -n "$(docker ps -q 2>/dev/null)" ]]; then
    warn "Dang co container chay (khach / self-test). KHONG bat VM luc nay."
    warn "Khi may khong co khach, chay:  sudo bash $SELF vm"
    return 0
  fi
  python3 /var/lib/vastai_kaalia/enable_vms.py on -f 2>&1 \
    | grep -v -e Pulling -e Waiting -e Verifying -e complete -e 'Already exists' | tail -n 15
  # script cua Vast co the doi ten dich vu roi bo do -> khoi phuc
  if [[ -f /etc/systemd/system/vastai.service.mask ]]; then
    mv /etc/systemd/system/vastai.service.mask /etc/systemd/system/vastai.service
    warn "Da khoi phuc vastai.service"
  fi
  systemctl daemon-reload; systemctl enable vastai >/dev/null 2>&1; systemctl restart vastai
  local st; st="$(python3 /var/lib/vastai_kaalia/enable_vms.py check 2>/dev/null)"
  if [[ "$st" == "on" ]]; then ok "VM da bat (web cap nhat sau 15-30 phut)"
  else
    warn "VM chua bat ($st). May VAN cho thue Docker binh thuong."
    echo "  Loi BAR (phai = 0): $(dmesg | grep -c "can't reserve")"
    echo "  Gui ho tro: sudo tail -n 40 /var/lib/vastai_kaalia/enable_vms.log"
  fi
  echo "vastai : $(systemctl is-active vastai)"
}

# ------------------------------------------------------------------ BUOC 1
stage1() {
  step "BUOC 1/3 - KIEM TRA + CHUAN BI HE THONG"
  if ! preflight; then ask "Van tiep tuc du con thieu?" || exit 1; fi

  step "1.1 Goi co ban, tat cap nhat tu dong"
  apt-get update
  apt-get install -y openssh-server curl wget rsync xfsprogs lvm2 pciutils python3 \
                     ubuntu-drivers-common "linux-headers-$(uname -r)"
  systemctl enable --now ssh
  apt-get remove -y unattended-upgrades 2>/dev/null || true
  systemctl disable --now apt-daily.timer apt-daily-upgrade.timer 2>/dev/null || true
  ok "Xong"

  step "1.2 Mang: tu nhan moi card mang (doi khe card khong mat mang)"
  mkdir -p /etc/cloud/cloud.cfg.d
  echo 'network: {config: disabled}' > /etc/cloud/cloud.cfg.d/99-disable-network-config.cfg
  mkdir -p /root/netplan-backup && mv /etc/netplan/*.yaml /root/netplan-backup/ 2>/dev/null || true
  printf 'network:\n  version: 2\n  ethernets:\n    lan:\n      match:\n        name: "en*"\n      dhcp4: true\n' \
    > /etc/netplan/01-vast.yaml
  chmod 600 /etc/netplan/01-vast.yaml
  netplan generate && ok "Cau hinh mang moi se ap dung sau khi khoi dong lai"

  step "1.3 SSH key + tat dang nhap bang mat khau (Vast bat buoc)"
  ensure_ssh_key
  disable_password_login || { err "Dung lai - chup man hinh gui ho tro"; exit 1; }

  step "1.4 Tham so khoi dong (IOMMU + tat framebuffer, can cho VM)"
  local P="intel_iommu=on iommu=pt initcall_blacklist=sysfb_init video=efifb:off video=vesafb:off"
  grep -q AuthenticAMD /proc/cpuinfo && P="${P/intel_iommu/amd_iommu}"
  cp /etc/default/grub /root/grub.bak
  if grep -q '^GRUB_CMDLINE_LINUX=' /etc/default/grub; then
    sed -i "s|^GRUB_CMDLINE_LINUX=.*|GRUB_CMDLINE_LINUX=\"$P\"|" /etc/default/grub
  else echo "GRUB_CMDLINE_LINUX=\"$P\"" >> /etc/default/grub; fi
  update-grub >/dev/null 2>&1 && ok "Da them: $P"

  step "1.5 Driver NVIDIA ($DRIVER_PKG cua Ubuntu)"
  # may tung cai driver .run (kich ban GTX 1080) -> go truoc
  if command -v nvidia-uninstall >/dev/null 2>&1; then
    warn "Phat hien driver .run cu - dang go..."; nvidia-uninstall --silent || true
  fi
  rm -f /etc/modprobe.d/blacklist-nouveau.conf
  if dpkg -l | grep -q "^.i  $DRIVER_PKG "; then ok "$DRIVER_PKG da co"
  else
    apt-mark unhold $(dpkg -l | awk '$2 ~ /nvidia/ {print $2}') >/dev/null 2>&1 || true
    apt-get install -y "$DRIVER_PKG" || ubuntu-drivers install || { err "Cai driver loi"; exit 1; }
  fi
  apt-mark hold $(dpkg -l | awk '/^ii/ && $2 ~ /nvidia/ && $2 !~ /container/ {print $2}') >/dev/null 2>&1 || true
  ok "Da cai + khoa phien ban driver (khong bi tu cap nhat)"

  step "1.6 O dia cho Docker (XFS + pquota tren NVMe)"
  if mountpoint -q /var/lib/docker; then ok "Da co: $(findmnt -no SOURCE /var/lib/docker)"
  else
    local vg free_g=0; vg="$(vgs --noheadings -o vg_name 2>/dev/null | head -n1 | xargs)"
    [[ -n "$vg" ]] && free_g="$(vgs --noheadings --units g --nosuffix -o vg_free "$vg" | xargs | cut -d. -f1)"
    if [[ -n "$vg" && "$free_g" -gt 120 && -z "$(ls -A /var/lib/docker 2>/dev/null)" ]]; then
      local size=$((free_g - 20))
      lvcreate -y -L "${size}G" -n docker-lv "$vg" && mkfs.xfs -f "/dev/$vg/docker-lv" \
        && mkdir -p /var/lib/docker && cp /etc/fstab /root/fstab.bak \
        && echo "/dev/$vg/docker-lv /var/lib/docker xfs rw,auto,pquota 0 0" >> /etc/fstab \
        && systemctl daemon-reload && mount /var/lib/docker && ok "Da tao ${size}GB" && df -h /var/lib/docker
    else warn "Khong tao duoc phan vung Docker (VG trong ${free_g}GB). Xem README muc 'Gap loi'."; fi
  fi

  echo -n 2 > "$STATE"
  box "XONG BUOC 1/3 - CAN KHOI DONG LAI" \
      "Sau khi may len lai (2-3 phut), SSH vao va chay lai:" \
      "    sudo bash $SELF"
  ask "Khoi dong lai ngay?" && reboot
}

# ------------------------------------------------------------------ BUOC 2
stage2() {
  step "BUOC 2/3 - KIEM TRA DRIVER, MO PORT, HUONG DAN CAI VAST"
  nvidia-smi -L || { err "Driver chua chay. Lam lai buoc 1:  sudo bash $SELF reset; sudo bash $SELF"; exit 1; }
  echo "Driver: $(nvidia-smi --query-gpu=driver_version --format=csv,noheader | head -1)  CUDA $(cuda_ver)"
  local smi pci; smi="$(n_smi_gpus)"; pci="$(n_pci_gpus)"
  [[ "$smi" -eq "$pci" ]] && ok "Driver nhan du $smi card" || warn "Driver nhan $smi/$pci card"
  local ng; ng="$(ls /sys/kernel/iommu_groups 2>/dev/null | wc -l)"
  [[ "$ng" -gt 0 ]] && ok "IOMMU dang bat" || warn "IOMMU chua bat - BIOS bat VT-d (chi anh huong VM)"
  ssh_pw_off || disable_password_login

  port_step

  echo -n 3 > "$STATE"
  load_net_info
  box "DEN LUOT BAN: CAI VAST BANG TAY" \
      "1. Mo https://cloud.vast.ai/host/setup" \
      "2. Copy NGUYEN lenh cai dat (bat dau bang wget ...), dan vao day, Enter" \
      "3. Hoi 'starting open port' -> go ${P_START}" \
      "   Hoi 'ending open port'   -> go ${P_END}" \
      "4. Doi qua 'NCCL test ok' (neu nhieu card) va '=> Done!'" \
      "   Buoc 'Pulling default pytorch image' co the dung im 10-20 phut -> cu doi" \
      "5. Xong thi chay:   sudo bash $SELF"
}

# ------------------------------------------------------------------ BUOC 3
stage3() {
  step "BUOC 3/3 - HOAN TAT"
  load_net_info
  if [[ ! -d /var/lib/vastai_kaalia ]]; then
    err "Chua thay Vast. Cai Vast truoc:"
    box "1. https://cloud.vast.ai/host/setup -> copy lenh -> dan vao may" \
        "2. Port: ${P_START} / ${P_END}" "3. Xong: sudo bash $SELF"
    exit 1
  fi
  echo -n "$PR" > /var/lib/vastai_kaalia/host_port_range
  systemctl daemon-reload; systemctl enable vastai >/dev/null 2>&1; systemctl restart vastai

  enable_vm

  echo -n done > "$STATE"
  step "KET QUA"
  echo "vastai : $(systemctl is-active vastai)"
  echo "docker : $(systemctl is-active docker)"
  echo "Driver : $(nvidia-smi --query-gpu=driver_version --format=csv,noheader | head -1)  CUDA $(cuda_ver)"
  nvidia-smi -L
  echo "VM     : $(python3 /var/lib/vastai_kaalia/enable_vms.py check 2>/dev/null)"
  print_port_box
  suggest_price
  box "DEN LUOT BAN: LIST MAY TREN WEB" \
      "1. https://cloud.vast.ai/host/machines -> may moi -> Settings" \
      "2. On-demand Price ${PRICE}   (gia cho MOI card)" \
      "   Min bid ${MINBID} | Storage 0.15 | Upload 3 | Download 2" \
      "3. Ngay het han xa (vd 2 nam) -> Update Listing" \
      "4. The may phai hien gia \$${PRICE}/hr/GPU" \
      "   (Goi y: RTX 3060 12GB 0.08 | RTX 2060 12GB 0.06)"
  read -r -p "List xong thi bam Enter de chay self-test... " _
  run_selftest
  box "XONG HET" \
      "- Kiem tra cho thue duoc chua (10 phut sau khi list):" \
      "    $VASTAI search offers \"machine_id=\$(cat $ID_FILE) verified=any rentable=any\" --raw | grep -e dph_total -e rentable" \
      "  -> 'rentable': false thi khoi dong lai may (sudo reboot)" \
      "- Self-test bao 'reliability' -> doi 1-2 ngay roi: sudo bash $SELF selftest" \
      "- KHONG bam 'Test machine' tren web khi do tin cay < 90%" \
      "- KHONG chay 'apt upgrade' / 'do-release-upgrade'" \
      "- KHONG tat may / rut mang / doi khe card khi dang co khach"
}

# ------------------------------------------------------------------ MAIN
case "${1:-}" in
  check)  preflight "${2:-}" ;;
  port)   load_net_info; print_port_box ;;
  status) echo "Dang o buoc: $(cat "$STATE" 2>/dev/null || echo 1)" ;;
  reset)  rm -f "$STATE"; ok "Da reset - chay lai: sudo bash $SELF" ;;
  vm)     enable_vm ;;
  selftest) run_selftest ;;
  "")
    case "$(cat "$STATE" 2>/dev/null || echo 1)" in
      1) stage1 ;; 2) stage2 ;; 3) stage3 ;;
      done) ok "May nay da cai xong. Lenh huu ich: port | vm | selftest | status"; load_net_info; print_port_box ;;
      *) stage1 ;;
    esac ;;
  *) echo "Cach dung: sudo bash $SELF  [check|status|port|vm|selftest|reset]"; exit 1 ;;
esac
