#!/usr/bin/env bash
# ==========================================================
#  Vast.ai host setup - Ubuntu 22.04 / 24.04 + NVIDIA GPU
#  Cach dung:
#    sudo bash vast_setup.sh phase1   (chuan bi he thong, xong thi reboot)
#    sudo bash vast_setup.sh phase2   (sau reboot: kiem tra, port, bat VM)
# ==========================================================
set -uo pipefail

RED='\033[1;31m'; GRN='\033[1;32m'; YEL='\033[1;33m'; NC='\033[0m'
ok()   { echo -e "${GRN}[OK]${NC} $*"; }
warn() { echo -e "${YEL}[CHU Y]${NC} $*"; }
err()  { echo -e "${RED}[LOI]${NC} $*"; }
step() { echo; echo -e "${GRN}==== $* ====${NC}"; }
ask()  { local a; read -r -p "$1 [y/N]: " a; [[ "$a" =~ ^[Yy]$ ]]; }

[[ $EUID -eq 0 ]] || { err "Hay chay bang sudo: sudo bash $0 $*"; exit 1; }
REAL_USER="${SUDO_USER:-root}"
REAL_HOME="$(getent passwd "$REAL_USER" | cut -d: -f6)"

# Tai khoan GitHub chua SSH public key (https://github.com/<ten>.keys)
GH_USER="chucn2005hn"

# ---------------------------------------------------------- SSH KEY
# Vast BAT BUOC tat dang nhap SSH bang mat khau truoc khi cai.
have_key() { [[ -s "$REAL_HOME/.ssh/authorized_keys" ]] && grep -qE '^(ssh-|ecdsa-)' "$REAL_HOME/.ssh/authorized_keys"; }

add_key_line() {
  local k="$1"
  echo "$k" | ssh-keygen -lf - >/dev/null 2>&1 || return 1
  mkdir -p "$REAL_HOME/.ssh"
  touch "$REAL_HOME/.ssh/authorized_keys"
  grep -qxF "$k" "$REAL_HOME/.ssh/authorized_keys" || echo "$k" >> "$REAL_HOME/.ssh/authorized_keys"
  chmod 700 "$REAL_HOME/.ssh"; chmod 600 "$REAL_HOME/.ssh/authorized_keys"
  chown -R "$REAL_USER:" "$REAL_HOME/.ssh"
}

ensure_ssh_key() {
  if have_key; then ok "Da co SSH key cho $REAL_USER"; return 0; fi

  # Cach 1: lay key tu GitHub (neu da them key vao tai khoan GitHub)
  local gk; gk="$(curl -fsS --max-time 10 "https://github.com/$GH_USER.keys" 2>/dev/null || true)"
  if [[ -n "$gk" ]]; then
    while IFS= read -r line; do [[ -n "$line" ]] && add_key_line "$line"; done <<< "$gk"
    have_key && { ok "Da lay SSH key tu github.com/$GH_USER.keys"; return 0; }
  fi

  # Cach 2: dan key bang tay
  echo
  echo -e "${YEL}##########################################################${NC}"
  echo -e "${YEL}#   DEN LUOT BAN: DAN SSH KEY CUA MAY WINDOWS            #${NC}"
  echo -e "${YEL}#                                                        #${NC}"
  echo -e "${YEL}#   Tren may Windows, mo CMD va go:                      #${NC}"
  echo -e "${YEL}#     type %USERPROFILE%\\.ssh\\id_ed25519.pub             #${NC}"
  echo -e "${YEL}#   Copy NGUYEN dong hien ra (bat dau bang ssh-ed25519)  #${NC}"
  echo -e "${YEL}#   roi dan vao day, bam Enter.                          #${NC}"
  echo -e "${YEL}##########################################################${NC}"
  local k
  while true; do
    read -r -p "Dan SSH key vao day: " k
    k="$(echo "$k" | xargs)"
    if add_key_line "$k"; then ok "Da them SSH key"; return 0; fi
    err "Key khong hop le - phai bat dau bang 'ssh-ed25519' hoac 'ssh-rsa'. Thu lai."
  done
}

disable_password_login() {
  have_key || { err "Chua co SSH key - KHONG tat mat khau."; return 1; }
  sed -i '/^\s*PasswordAuthentication/d;/^\s*KbdInteractiveAuthentication/d' \
    /etc/ssh/sshd_config /etc/ssh/sshd_config.d/*.conf 2>/dev/null || true
  printf 'PasswordAuthentication no\nKbdInteractiveAuthentication no\nPubkeyAuthentication yes\n' \
    > /etc/ssh/sshd_config.d/00-vast.conf
  if sshd -t; then
    systemctl restart ssh
    ok "Da tat dang nhap bang mat khau: $(sshd -T | grep -i '^passwordauthentication')"
    warn "Tu gio chi SSH bang key. Phien SSH dang mo van giu nguyen."
  else
    rm -f /etc/ssh/sshd_config.d/00-vast.conf
    err "Cau hinh SSH loi - da huy thay doi."
    return 1
  fi
}

# ---------------------------------------------------------- PHASE 1
phase1() {
  export DEBIAN_FRONTEND=noninteractive

  step "1. Cai goi co ban"
  apt-get update
  apt-get install -y openssh-server curl wget rsync xfsprogs lvm2 pciutils python3-pip
  systemctl enable --now ssh && ok "SSH dang chay"

  step "2. Tat cap nhat tu dong (tranh driver NVIDIA bi doi khi co khach)"
  apt-get remove -y unattended-upgrades 2>/dev/null || true
  systemctl disable --now apt-daily.timer apt-daily-upgrade.timer 2>/dev/null || true
  ok "Da tat cap nhat tu dong"

  step "3. Kiem tra card mang (chi nen dung 1 day LAN)"
  PRIMARY="$(ip route show default | awk '{print $5; exit}')"
  OTHERS="$(ip -4 -o addr show | awk '{print $2}' | grep -E '^(en|eth)' | grep -vx "$PRIMARY" | sort -u || true)"
  echo "Card chinh: $PRIMARY ($(ip -4 -o addr show "$PRIMARY" | awk '{print $4}'))"
  if [[ -n "$OTHERS" ]]; then
    warn "Co them card mang dang co IP: $OTHERS"
    warn "Hay chac chan ban dang SSH qua IP cua card chinh $PRIMARY truoc khi tat."
    if ask "Tat IP tren cac card phu va chi giu $PRIMARY?"; then
      echo 'network: {config: disabled}' > /etc/cloud/cloud.cfg.d/99-disable-network-config.cfg
      mkdir -p /root/netplan-backup && cp /etc/netplan/*.yaml /root/netplan-backup/ 2>/dev/null || true
      rm -f /etc/netplan/*.yaml
      {
        echo "network:"; echo "    version: 2"; echo "    ethernets:"
        echo "        $PRIMARY:"; echo "            dhcp4: true"
        for n in $OTHERS; do
          echo "        $n:"; echo "            dhcp4: false"; echo "            optional: true"
        done
      } > /etc/netplan/50-vast.yaml
      chmod 600 /etc/netplan/50-vast.yaml
      echo "Bam ENTER khi duoc hoi de giu cau hinh (sau 120s se tu quay lai neu mat ket noi)."
      netplan try || warn "netplan try khong xac nhan - cau hinh cu duoc giu"
    fi
  else
    ok "Chi co 1 card mang dang dung"
  fi

  step "4. Tham so khoi dong: IOMMU + tat framebuffer (de GPU vao duoc VM)"
  if grep -q AuthenticAMD /proc/cpuinfo; then IOMMU="amd_iommu=on"; else IOMMU="intel_iommu=on"; fi
  PARAMS="$IOMMU iommu=pt initcall_blacklist=sysfb_init video=efifb:off video=vesafb:off"
  cp /etc/default/grub /root/grub.bak
  if grep -q '^GRUB_CMDLINE_LINUX=' /etc/default/grub; then
    sed -i "s|^GRUB_CMDLINE_LINUX=.*|GRUB_CMDLINE_LINUX=\"$PARAMS\"|" /etc/default/grub
  else
    echo "GRUB_CMDLINE_LINUX=\"$PARAMS\"" >> /etc/default/grub
  fi
  update-grub && grep -q sysfb_init /boot/grub/grub.cfg && ok "Da them: $PARAMS"

  step "5. Driver NVIDIA"
  if nvidia-smi -L >/dev/null 2>&1; then
    ok "Driver da co san:"; nvidia-smi -L
  else
    # GTX 10xx (Pascal) chi duoc ho tro den nhanh driver 580 -> uu tien 580
    DRV=""
    for v in 580 570 550 535; do
      if apt-cache show "nvidia-driver-$v" >/dev/null 2>&1; then DRV="nvidia-driver-$v"; break; fi
    done
    if [[ -n "$DRV" ]]; then
      apt-get install -y "$DRV" && ok "Da cai $DRV"
    else
      ubuntu-drivers install || ubuntu-drivers autoinstall
    fi
    ok "Da cai driver (can reboot moi chay)"
  fi
  apt-mark hold $(dpkg -l | awk '/^ii/ && $2 ~ /nvidia/ {print $2}') >/dev/null 2>&1 || true
  ok "Da khoa phien ban driver NVIDIA"

  step "6. O dia cho Docker (XFS + pquota tren NVMe/LVM)"
  if mountpoint -q /var/lib/docker; then
    ok "/var/lib/docker da duoc gan san:"; findmnt /var/lib/docker
  else
    VG="$(vgs --noheadings -o vg_name 2>/dev/null | head -n1 | xargs || true)"
    FREE_G=0
    [[ -n "$VG" ]] && FREE_G="$(vgs --noheadings --units g --nosuffix -o vg_free "$VG" | xargs | cut -d. -f1)"
    if [[ -n "$VG" && "$FREE_G" -gt 120 ]]; then
      SIZE=$((FREE_G - 20))
      echo "Volume group '$VG' con trong ${FREE_G}GB."
      lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT,MODEL,TRAN
      if ask "Tao phan vung ${SIZE}GB (XFS) cho /var/lib/docker trong '$VG'?"; then
        if [[ -d /var/lib/docker && -n "$(ls -A /var/lib/docker 2>/dev/null)" ]]; then
          err "/var/lib/docker da co du lieu - bo qua de an toan."
        else
          lvcreate -y -L "${SIZE}G" -n docker-lv "$VG" \
          && mkfs.xfs -f "/dev/$VG/docker-lv" \
          && mkdir -p /var/lib/docker \
          && cp /etc/fstab /root/fstab.bak \
          && echo "/dev/$VG/docker-lv /var/lib/docker xfs rw,auto,pquota 0 0" >> /etc/fstab \
          && systemctl daemon-reload && mount /var/lib/docker \
          && ok "Da gan:" && df -h /var/lib/docker
        fi
      fi
    else
      warn "Khong tim thay vung LVM trong du lon (>120GB)."
      warn "Hay de san vung trong tren o NVMe - trinh cai Vast se tu tao XFS."
      warn "KHONG de Vast dung o USB/HDD cham."
    fi
  fi

  step "7. Cai san qemu/libvirt (cho VM)"
  if ! apt-get install -y libvirt-daemon-system qemu-kvm psmisc; then
    warn "Lech phien ban qemu - cai dong bo cung 1 phien ban..."
    V="$(apt-cache policy qemu-system-x86 | awk '/Candidate:/{print $2}')"
    apt-get install -y --allow-downgrades \
      "qemu-system-x86=$V" "qemu-system-common=$V" "qemu-system-data=$V" \
      "qemu-block-extra=$V" "qemu-utils=$V" "qemu-system-gui=$V" \
      libvirt-daemon-system psmisc && ok "Da cai qemu $V"
  fi

  step "8. SSH key + tat dang nhap bang mat khau (Vast bat buoc)"
  ensure_ssh_key
  disable_password_login

  step "XONG PHASE 1"
  echo "Tiep theo: reboot, roi chay:  sudo bash $0 phase2"
  if ask "Khoi dong lai ngay bay gio?"; then reboot; fi
}

# ---------------------------------------------------------- PHASE 2
phase2() {
  step "1. Kiem tra sau reboot"
  grep -qE '(intel|amd)_iommu=on' /proc/cmdline && ok "Tham so IOMMU da nap" || err "Thieu tham so IOMMU"
  dmesg | grep -qi -e "IOMMU enabled" -e "AMD-Vi" && ok "IOMMU dang bat" || warn "Khong thay 'IOMMU enabled' - kiem tra VT-d trong BIOS"
  if nvidia-smi -L; then ok "GPU hoat dong"; else err "nvidia-smi loi - kiem tra driver"; exit 1; fi
  if findmnt -no FSTYPE,OPTIONS /var/lib/docker | grep -q 'xfs.*prjquota'; then
    ok "/var/lib/docker la XFS + quota"; df -h /var/lib/docker
  else
    warn "/var/lib/docker chua phai XFS+quota (trinh cai Vast se tu xu ly neu co vung trong)"
  fi

  step "2. Cai daemon Vast"
  if [[ -d /var/lib/vastai_kaalia ]]; then
    ok "Daemon Vast da duoc cai"
  else
    # Vast tu choi cai neu SSH con cho dang nhap bang mat khau
    if sshd -T 2>/dev/null | grep -qi '^passwordauthentication yes'; then
      warn "SSH van cho dang nhap bang mat khau - Vast se tu choi cai. Dang xu ly..."
      ensure_ssh_key
      disable_password_login || { err "Khong tat duoc mat khau SSH - dung lai."; exit 1; }
    fi
    echo
    echo -e "${YEL}##########################################################${NC}"
    echo -e "${YEL}#   DEN LUOT BAN: NHAP LENH CAI DAT VAST                 #${NC}"
    echo -e "${YEL}#                                                        #${NC}"
    echo -e "${YEL}#   1. Mo trang: https://cloud.vast.ai/host/setup        #${NC}"
    echo -e "${YEL}#   2. Copy NGUYEN lenh cai dat (lenh co key, co han)    #${NC}"
    echo -e "${YEL}#      Hoac chi copy rieng doan KEY cung duoc            #${NC}"
    echo -e "${YEL}#   3. Dan vao day roi bam Enter                         #${NC}"
    echo -e "${YEL}##########################################################${NC}"
    echo
    VCMD=""
    while [[ -z "$VCMD" ]]; do
      read -r -p "Dan lenh (hoac key) Vast vao day: " VCMD
      VCMD="$(echo "$VCMD" | xargs)"
    done
    if [[ "$VCMD" =~ ^[0-9a-fA-F]{32,}$ ]]; then
      # chi dan key -> tu ghep lenh cai dat
      VCMD="wget https://console.vast.ai/install -O install; python3 install $VCMD --interactive"
    fi
    VCMD="${VCMD//sudo /}"                         # dang chay bang root san
    VCMD="$(echo "$VCMD" | sed 's/history -d[^;]*;\{0,1\}//g')"
    cd /root || true
    echo "Dang cai daemon Vast... (lam theo cac cau hoi neu co)"
    bash -c "$VCMD"
    rm -f /root/install
    if [[ -d /var/lib/vastai_kaalia ]]; then
      ok "Da cai daemon Vast"
      sleep 20
    else
      err "Cai daemon Vast that bai. Kiem tra lai lenh/key (co the da het han) roi chay lai:"
      err "  sudo bash $0 phase2"
      exit 1
    fi
  fi

  step "3. Dai port cho may nay"
  CUR="$(cat /var/lib/vastai_kaalia/host_port_range 2>/dev/null || true)"
  echo "Dai port hien tai: ${CUR:-chua dat}"
  echo "Moi may trong CUNG mot mang (cung modem) phai dung dai port KHAC nhau."
  echo "  May thu 1: 50000-50999   May thu 2: 51000-51999   May thu 3: 52000-52999 ..."
  read -r -p "Nhap dai port (Enter = giu '${CUR:-50000-50999}'): " PR
  PR="${PR:-${CUR:-50000-50999}}"
  echo -n "$PR" > /var/lib/vastai_kaalia/host_port_range

  NIC="$(ip route show default | awk '{print $5; exit}')"
  LAN_IP="$(ip -4 -o addr show "$NIC" | awk '{print $4}' | cut -d/ -f1 | head -n1)"
  MAC="$(cat /sys/class/net/"$NIC"/address 2>/dev/null)"
  GW="$(ip route show default | awk '{print $3; exit}')"
  PUB_IP="$(curl -4 -s --max-time 8 ifconfig.me || echo 'khong lay duoc')"
  P_START="${PR%-*}"

  print_port_box() {
    echo
    echo -e "${YEL}##########################################################${NC}"
    echo -e "${YEL}#   DEN LUOT BAN: CAI PORT TREN MODEM                    #${NC}"
    echo -e "${YEL}##########################################################${NC}"
    echo -e "  Vao trang modem      : ${GRN}http://$GW${NC}"
    echo
    echo -e "  [1] NAT -> Virtual Server (hoac Port Forwarding):"
    echo -e "      Cong ngoai       : ${GRN}$PR${NC}"
    echo -e "      Cong trong       : ${GRN}$PR${NC}"
    echo -e "      IP may nay       : ${GRN}$LAN_IP${NC}"
    echo -e "      Giao thuc        : ${GRN}TCP + UDP (Both)${NC}"
    echo -e "      (Neu day la MAY DUY NHAT o mang nay: co the dung DMZ -> $LAN_IP)"
    echo
    echo -e "  [2] LAN -> DHCP Reservation (co dinh IP):"
    echo -e "      IP               : ${GRN}$LAN_IP${NC}"
    echo -e "      MAC              : ${GRN}$MAC${NC}"
    echo
    echo -e "  [3] Kiem tra tren portchecker.co:"
    echo -e "      IP public        : ${GRN}$PUB_IP${NC}"
    echo -e "      Port             : ${GRN}$P_START${NC}"
    echo -e "${YEL}##########################################################${NC}"
  }
  print_port_box
  ok "Da luu dai port $PR"

  # Mo tam 1 port de ban kiem tra tu ngoai vao
  echo
  if ask "Mo tam port $P_START de kiem tra bang portchecker.co sau khi cai modem?"; then
    python3 -m http.server "$P_START" --bind 0.0.0.0 >/dev/null 2>&1 &
    HTTP_PID=$!
    echo "Dang mo port $P_START. Vao portchecker.co: IP $PUB_IP, port $P_START."
    read -r -p "Bam Enter sau khi kiem tra xong (Open = dung, Closed = xem lai modem)... " _
    kill "$HTTP_PID" 2>/dev/null || true
  else
    read -r -p "Cai modem xong thi bam Enter de tiep tuc... " _
  fi

  step "4. Bat VM"
  if [[ -n "$(docker ps -q 2>/dev/null)" ]]; then
    warn "Dang co container chay (self-test/khach). Bo qua buoc bat VM, chay lai phase2 sau."
  else
    python3 /var/lib/vastai_kaalia/enable_vms.py on -f 2>&1 | tee /root/vm_log.txt
  fi
  # an toan: script bat VM co the doi ten dich vu vastai roi bo do
  if [[ -f /etc/systemd/system/vastai.service.mask ]]; then
    mv /etc/systemd/system/vastai.service.mask /etc/systemd/system/vastai.service
    warn "Da khoi phuc vastai.service"
  fi
  systemctl daemon-reload
  systemctl enable --now vastai 2>/dev/null || true

  step "KET QUA"
  echo "VM check : $(python3 /var/lib/vastai_kaalia/enable_vms.py check 2>/dev/null)"
  echo "vastai   : $(systemctl is-active vastai 2>/dev/null)"
  echo "docker   : $(systemctl is-active docker 2>/dev/null)"
  echo "Loi BAR  : $(dmesg | grep -c "can't reserve")  (0 la tot)"
  nvidia-smi -L
  print_port_box
  echo "Viec con lai: vao cloud.vast.ai -> Machines -> Settings -> List (gia, ngay het han)."
}

case "${1:-}" in
  phase1) phase1 ;;
  phase2) phase2 ;;
  *) echo "Cach dung: sudo bash $0 phase1   |   sudo bash $0 phase2"; exit 1 ;;
esac
