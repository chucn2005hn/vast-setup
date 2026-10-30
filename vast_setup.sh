#!/usr/bin/env bash
# ==================================================================
#  CAI MAY CHO THUE GPU TREN VAST.AI
#  >>> KICH BAN DANH CHO GTX 1080 / GTX 10xx (doi Pascal) <<<
#  (Card khac -> dung kich ban khac, KHONG dung file nay)
#
#  CHI CAN 1 LENH, chay lai dung lenh nay sau moi lan khoi dong lai:
#     sudo bash vast_setup.sh
#  Lenh phu:
#     sudo bash vast_setup.sh check    -> chi kiem tra cau hinh
#     sudo bash vast_setup.sh status   -> xem dang o buoc nao
#     sudo bash vast_setup.sh port     -> hien lai thong tin cai modem
#     sudo bash vast_setup.sh selftest -> chay self-test (khi do tin cay > 90%)
#     sudo bash vast_setup.sh reset    -> lam lai tu dau
#
#  Nhung gi da kiem chung tren may that (2x GTX 1080, X99-T8D, 2 CPU):
#   - Driver Ubuntu (535/550/570) gio deu tro ve 580 (CUDA 13) -> trinh cai
#     Vast cai PyTorch moi, KHONG chay tren Pascal -> NCCL test fail.
#     => Cai driver 550 truc tiep tu NVIDIA (.run), CUDA 12.4.
#   - Anh pytorch:latest (2.6+) can CUDA >= 12.6 -> dung 2.5.1-cuda12.4
#     va gan nhan 'latest' de NCCL test cua Vast chay duoc.
#   - Vast tu choi cai neu SSH con cho dang nhap mat khau
#     (file 50-cloud-init.conf bat 'yes') -> tat o moi noi.
#   - Doi khe card -> ten card mang doi -> mat mang -> netplan khop "en*".
#   - 2 card o 2 CPU khac nhau (topo SYS) van chay NCCL binh thuong.
#   - VM cua Vast KHONG chay voi Pascal -> chi cho thue Docker
#     (support Vast da xac nhan).
#   - Self-test can do tin cay > 90%: may moi ~60%, doi 1-2 ngay roi chay
#     sudo bash vast_setup.sh selftest
# ==================================================================
set -uo pipefail

GH_USER="chucn2005hn"                 # lay SSH key tu github.com/<ten>.keys
DRIVER_VER="550.163.01"
DRIVER_RUN="/root/NVIDIA-${DRIVER_VER}.run"
DRIVER_URL="https://us.download.nvidia.com/XFree86/Linux-x86_64/${DRIVER_VER}/NVIDIA-Linux-x86_64-${DRIVER_VER}.run"
TEST_IMAGE="pytorch/pytorch:2.5.1-cuda12.4-cudnn9-runtime"
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
  if [[ "$pci" -gt 0 ]] && ! is_pascal; then
    miss "Card KHONG phai GTX 10xx" "File nay chi danh cho GTX 1080/10xx - dung kich ban cho card khac"
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
disable_password_login() {
  have_key || { err "Chua co SSH key - KHONG tat mat khau."; return 1; }
  sed -i '/^\s*#\?\s*PasswordAuthentication/d;/^\s*KbdInteractiveAuthentication/d' \
    /etc/ssh/sshd_config /etc/ssh/sshd_config.d/*.conf 2>/dev/null || true
  printf 'PasswordAuthentication no\nKbdInteractiveAuthentication no\nPubkeyAuthentication yes\n' \
    > /etc/ssh/sshd_config.d/00-vast.conf
  echo 'PasswordAuthentication no' >> /etc/ssh/sshd_config
  mkdir -p /etc/cloud/cloud.cfg.d && echo 'ssh_pwauth: false' > /etc/cloud/cloud.cfg.d/99-vast-ssh.cfg
  if sshd -t && systemctl restart ssh && sshd -T | grep -qi '^passwordauthentication no'; then
    ok "Da tat dang nhap SSH bang mat khau (chi vao bang key)"
    warn "Dang nhap truc tiep tai may (ban phim + man hinh) van dung mat khau binh thuong."
  else
    err "Chua tat duoc mat khau:"; grep -rn -i PasswordAuthentication /etc/ssh/sshd_config /etc/ssh/sshd_config.d/
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
  local old no; old="$(cat "$NO_FILE" 2>/dev/null || echo 1)"
  while true; do
    read -r -p "May thu may? (Enter = $old): " no; no="${no:-$old}"
    [[ "$no" =~ ^[1-9][0-9]?$ ]] && break; err "Nhap so 1-99"
  done
  echo -n "$no" > "$NO_FILE"
  local p0=$((50000 + (no - 1) * 1000))
  echo -n "${p0}-$((p0 + 999))" > "$PORT_FILE"
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
        "2. Muc 'API Keys' -> + New -> dat ten (vd may-1080-<so>) -> copy key" \
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

# ------------------------------------------------------------------ BUOC 1
stage1() {
  step "BUOC 1/4 - KIEM TRA + CHUAN BI HE THONG"
  if ! preflight; then ask "Van tiep tuc du con thieu?" || exit 1; fi

  step "1.1 Goi co ban, tat cap nhat tu dong"
  apt-get update
  apt-get install -y openssh-server curl wget rsync xfsprogs lvm2 pciutils python3 \
                     build-essential dkms "linux-headers-$(uname -r)"
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

  step "1.4 Tham so khoi dong (IOMMU + tat framebuffer)"
  local P="intel_iommu=on iommu=pt initcall_blacklist=sysfb_init video=efifb:off video=vesafb:off"
  grep -q AuthenticAMD /proc/cpuinfo && P="${P/intel_iommu/amd_iommu}"
  cp /etc/default/grub /root/grub.bak
  if grep -q '^GRUB_CMDLINE_LINUX=' /etc/default/grub; then
    sed -i "s|^GRUB_CMDLINE_LINUX=.*|GRUB_CMDLINE_LINUX=\"$P\"|" /etc/default/grub
  else echo "GRUB_CMDLINE_LINUX=\"$P\"" >> /etc/default/grub; fi
  update-grub >/dev/null 2>&1 && ok "Da them: $P"

  step "1.5 Go driver Ubuntu (ban 580 khong hop GTX 1080), chan nouveau, tai driver 550"
  apt-mark unhold $(dpkg -l | awk '$2 ~ /nvidia/ {print $2}') >/dev/null 2>&1 || true
  local pk; pk="$(dpkg -l | awk '/^(ii|hi|rc)/ && $2 ~ /nvidia/ && $2 !~ /container/ {print $2}')"
  [[ -n "$pk" ]] && apt-get purge -y $pk
  printf 'blacklist nouveau\noptions nouveau modeset=0\n' > /etc/modprobe.d/blacklist-nouveau.conf
  update-initramfs -u >/dev/null 2>&1
  [[ -s "$DRIVER_RUN" ]] || wget -O "$DRIVER_RUN" "$DRIVER_URL" || { err "Khong tai duoc driver"; exit 1; }
  ok "Da tai driver $DRIVER_VER"

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
  box "XONG BUOC 1/4 - CAN KHOI DONG LAI" \
      "Sau khi may len lai (2-3 phut), SSH vao va chay lai:" \
      "    sudo bash $SELF"
  ask "Khoi dong lai ngay?" && reboot
}

# ------------------------------------------------------------------ BUOC 2
stage2() {
  step "BUOC 2/4 - CAI DRIVER NVIDIA $DRIVER_VER"
  if nvidia-smi --query-gpu=driver_version --format=csv,noheader 2>/dev/null | grep -q "$DRIVER_VER"; then
    ok "Driver $DRIVER_VER da co"
  else
    [[ -s "$DRIVER_RUN" ]] || wget -O "$DRIVER_RUN" "$DRIVER_URL"
    apt-get install -y build-essential dkms "linux-headers-$(uname -r)" >/dev/null
    sh "$DRIVER_RUN" --silent --dkms --disable-nouveau \
      || { err "Cai driver loi - xem /var/log/nvidia-installer.log"; exit 1; }
    ok "Da cai driver"
  fi
  echo -n 3 > "$STATE"
  box "XONG BUOC 2/4 - CAN KHOI DONG LAI" "May len lai thi chay:   sudo bash $SELF"
  ask "Khoi dong lai ngay?" && reboot
}

# ------------------------------------------------------------------ BUOC 3
stage3() {
  step "BUOC 3/4 - KIEM TRA DRIVER, CHUAN BI DOCKER, MO PORT"
  nvidia-smi -L || { err "Driver chua chay. Lam lai buoc 2:  echo -n 2 | sudo tee $STATE; sudo bash $SELF"; exit 1; }
  local cv; cv="$(cuda_ver)"
  if awk "BEGIN{exit !($cv < 12.8)}"; then ok "CUDA $cv (< 12.8, dung cho GTX 1080)"
  else err "CUDA $cv >= 12.8 - driver sai, NCCL test cua Vast se fail"; exit 1; fi
  local smi pci; smi="$(n_smi_gpus)"; pci="$(n_pci_gpus)"
  [[ "$smi" -eq "$pci" ]] && ok "Driver nhan du $smi card" || warn "Driver nhan $smi/$pci card"
  sshd -T | grep -qi '^passwordauthentication no' || disable_password_login

  step "3.1 Cai Docker + anh test NCCL hop voi GTX 1080"
  if ! command -v docker >/dev/null 2>&1; then
    curl -fsSL https://get.docker.com | sh || { err "Cai Docker loi"; exit 1; }
  fi
  systemctl enable --now docker
  docker pull "$TEST_IMAGE" && docker tag "$TEST_IMAGE" pytorch/pytorch:latest \
    && ok "pytorch:latest -> $TEST_IMAGE (de NCCL test cua Vast chay duoc)"

  port_step

  echo -n 4 > "$STATE"
  load_net_info
  box "DEN LUOT BAN: CAI VAST BANG TAY" \
      "1. Mo https://cloud.vast.ai/host/setup" \
      "2. Copy NGUYEN lenh cai dat (bat dau bang wget ...), dan vao day, Enter" \
      "3. Hoi 'starting open port' -> go ${P_START}" \
      "   Hoi 'ending open port'   -> go ${P_END}" \
      "4. Doi qua 'NCCL test ok' va '=> Done!' (buoc tai image cuoi co the lau, cu doi)" \
      "5. Xong thi chay:   sudo bash $SELF"
}

# ------------------------------------------------------------------ BUOC 4
stage4() {
  step "BUOC 4/4 - HOAN TAT"
  load_net_info
  if [[ ! -d /var/lib/vastai_kaalia ]]; then
    err "Chua thay Vast. Cai Vast truoc:"
    box "1. https://cloud.vast.ai/host/setup -> copy lenh -> dan vao may" \
        "2. Port: ${P_START} / ${P_END}" "3. Xong: sudo bash $SELF"
    exit 1
  fi
  echo -n "$PR" > /var/lib/vastai_kaalia/host_port_range
  if [[ -f /etc/systemd/system/vastai.service.mask ]]; then
    mv /etc/systemd/system/vastai.service.mask /etc/systemd/system/vastai.service
    warn "Da khoi phuc vastai.service"
  fi
  systemctl daemon-reload; systemctl enable vastai >/dev/null 2>&1; systemctl restart vastai
  echo -n done > "$STATE"

  step "KET QUA"
  echo "vastai : $(systemctl is-active vastai)"
  echo "docker : $(systemctl is-active docker)"
  echo "Driver : $(nvidia-smi --query-gpu=driver_version --format=csv,noheader | head -1)  CUDA $(cuda_ver)"
  nvidia-smi -L
  echo "VM     : KHONG ho tro voi GTX 1080 (anh VM cua Vast khong chay tren Pascal) -> chi cho thue Docker"
  print_port_box
  box "DEN LUOT BAN: LIST MAY TREN WEB" \
      "1. https://cloud.vast.ai/host/machines -> may moi (2x GTX 1080) -> Settings" \
      "2. On-demand Price 0.05  (KHONG nhap nham 0.15 vao o nay)" \
      "   Min bid 0.04 | Storage 0.15 | Upload 3 | Download 2" \
      "3. Ngay het han xa (vd 2 nam) -> Update Listing" \
      "4. The may phai hien gia \$0.050/hr/GPU"
  read -r -p "List xong thi bam Enter de chay self-test... " _
  run_selftest
  box "XONG HET" \
      "- Self-test bao 'reliability' -> doi 1-2 ngay roi: sudo bash $SELF selftest" \
      "- Xem lai thong tin modem:   sudo bash $SELF port" \
      "- KHONG chay 'apt upgrade' / 'do-release-upgrade'" \
      "- KHONG tat may / rut mang / doi khe card khi dang co khach" \
      "- Earnings -> Payout Account: ket noi PayPal/Wise (tra tien thu Sau, du \$20)"
}

# ------------------------------------------------------------------ MAIN
case "${1:-}" in
  check)  preflight "${2:-}" ;;
  port)   load_net_info; print_port_box ;;
  status) echo "Dang o buoc: $(cat "$STATE" 2>/dev/null || echo 1)" ;;
  reset)  rm -f "$STATE"; ok "Da reset - chay lai: sudo bash $SELF" ;;
  selftest) run_selftest ;;
  "")
    case "$(cat "$STATE" 2>/dev/null || echo 1)" in
      1) stage1 ;; 2) stage2 ;; 3) stage3 ;; 4) stage4 ;;
      done) ok "May nay da cai xong. Lenh huu ich: port | selftest | status"; load_net_info; print_port_box ;;
      *) stage1 ;;
    esac ;;
  *) echo "Cach dung: sudo bash $SELF  [check|status|port|selftest|reset]"; exit 1 ;;
esac
