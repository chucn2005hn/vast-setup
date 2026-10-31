# Cài máy cho thuê GPU trên Vast.ai – **kịch bản CARD RTX** (RTX 3060 12GB, RTX 2060 12GB)

> ✅ Dùng cho **RTX 3060 12GB, RTX 2060 12GB** (và RTX 20xx / 30xx / 40xx khác).
> ❌ **GTX 1080 / GTX 10xx → dùng `vast_setup.sh`** ([README_1080.md](README_1080.md)), KHÔNG dùng file này.
>
> Khác bản GTX 1080: dùng **driver 580 của Ubuntu** (không cần cài driver tay), **không cần mẹo ảnh PyTorch**, **bật được VM**, chỉ **3 lần chạy**.
>
> 💡 **Mỗi máy nên chỉ 1 loại card** (máy A toàn 3060, máy B toàn 2060). Script sẽ cảnh báo nếu trộn.

---

## ⭐ SAO CHÉP THEO THỨ TỰ (chỉ cần làm theo mục này)

Thay `IP_MAY` bằng IP máy mới (gõ `ip -4 -br addr` trên máy, dạng `192.168.1.x`). Thay `lehien` nếu tên user khác.
🪟 = **CMD máy Windows** (dòng `C:\Users\...>`) · 🐧 = **máy Ubuntu** (dòng `...@...:~$`)

**Chỉ làm 1 lần trên máy Windows (đã có key thì bỏ qua):**

🪟 **Lệnh A** – tạo SSH key (Enter 3 lần):
```
ssh-keygen -t ed25519
```
🪟 **Lệnh B** – hiện key → copy dòng hiện ra → dán vào https://github.com/settings/ssh/new (Title `may-windows`) → **Add SSH key**:
```
type %USERPROFILE%\.ssh\id_ed25519.pub
```

**Mỗi máy mới:**

🐧 **Lệnh 1** – ngồi trực tiếp ở máy, đăng nhập rồi dán (**lần chạy 1**):
```
sudo apt update && sudo apt install -y openssh-server wget && wget -O vast_setup_rtx.sh https://raw.githubusercontent.com/chucn2005hn/vast-setup/main/vast_setup_rtx.sh && sudo bash vast_setup_rtx.sh
```
→ Hỏi số card: gõ số card đã cắm · hỏi `[y/N]`: gõ `y` · cuối cùng `y` để khởi động lại.

🪟 **Lệnh 2** – đợi 2–3 phút, SSH vào máy:
```
ssh lehien@IP_MAY
```
🐧 **Lệnh 3** – **lần chạy 2**:
```
sudo bash vast_setup_rtx.sh
```
- Hỏi *"Máy thứ mấy"* → **Enter** (mỗi máy 1 mạng riêng). Nhiều máy chung 1 modem → máy đầu `1`, máy sau `2`, `3`…
- **Khung vàng cài port** → vào modem làm theo (mục 2) → kiểm tra https://portchecker.co → **Enter**
- **Khung vàng CÀI VAST** → mở https://cloud.vast.ai/host/setup → copy nguyên lệnh `wget ...` → dán vào máy → Enter
  → `starting open port`: **50000** · `ending open port`: **50999** (máy 2 cùng modem: 51000 / 51999) → đợi `=> Done!`

🐧 **Lệnh 3** lại – **lần chạy 3**:
- Script tự **bật VM**, tổng kết.
- **Khung vàng LIST MÁY** → web Settings:

| Card | On-demand (mỗi card) | Min bid | Storage | Upload | Download |
|---|---|---|---|---|---|
| **RTX 3060 12GB** | **0.08** | 0.06 | 0.15 | 3 | 2 |
| **RTX 2060 12GB** | **0.06** | 0.05 | 0.15 | 3 | 2 |

  Ngày hết hạn xa → **Update Listing** → **Enter**
- **Khung vàng API KEY** → https://cloud.vast.ai/manage-keys/ → **+ New** → copy → dán vào máy → Enter
- Self-test báo `Reliability ... > 0.9` → **bình thường**, xong.

🐧 **10 phút sau khi list** – kiểm tra khách thuê được chưa (thay `<ID_MAY>`):
```
~/.local/bin/vastai search offers "machine_id=<ID_MAY> verified=any rentable=any" --raw | grep -e '"dph_total"' -e '"rentable"'
```
hoặc (script cài sẵn):
```
sudo vastai search offers "machine_id=$(sudo cat /root/vast_machine_id) verified=any rentable=any" --raw | grep -e '"dph_total"' -e '"rentable"'
```
→ `"rentable": true` là xong. `false` → `sudo reboot`, 10 phút sau kiểm tra lại.

🐧 **Lệnh 4** – 1–2 ngày sau, khi độ tin cậy > 90% (và máy **không có khách**):
```
sudo bash vast_setup_rtx.sh selftest
```

**Lệnh hữu ích khác (🐧):**
```
sudo bash vast_setup_rtx.sh check      # kiem tra cau hinh (khong thay doi gi)
sudo bash vast_setup_rtx.sh port       # xem lai IP, MAC, port de cai modem
sudo bash vast_setup_rtx.sh vm         # bat lai VM (chi khi KHONG co khach)
sudo bash vast_setup_rtx.sh status     # dang o buoc nao
```

---

## 0. Chuẩn bị máy mới

- Cài **Ubuntu Server 22.04** lên ổ **NVMe**, **chừa trống > 150GB** (chọn LVM, không mở rộng hết ổ).
- Chỉ cắm **1 dây mạng**.
- BIOS: bật **VT-x**, **VT-d**, **Above 4G Decoding**; **tắt Secure Boot**.
- Nguồn: mỗi RTX 3060 ~170W, RTX 2060 ~160–185W, mỗi card **1 dây PCIe 8-pin riêng**. 2 card + 1 CPU → nguồn **750W** Gold; 2 CPU → **850–1000W**.
- Main 2 CPU: khe nối CPU2 chỉ chạy khi lắp đủ 2 CPU. 2 card ở 2 CPU khác nhau vẫn chạy bình thường. Đổi khe card **có thể làm mất ổ NVMe** (khe dùng chung đường) → thử khe khác.

## 1. Script làm gì ở mỗi lần chạy

| Lần | Script làm | Bạn làm |
|---|---|---|
| **1** | Kiểm tra cấu hình, cài gói, mạng tự nhận card, SSH key + tắt mật khẩu, IOMMU + tắt framebuffer, **driver 580**, ổ Docker NVMe | Nhập số card, `y`, khởi động lại |
| **2** | Kiểm tra driver/IOMMU, **hiện IP/MAC/port**, mở port test | Cài modem, kiểm tra port, **cài Vast bằng tay** |
| **3** | Ghi port, **bật VM**, tổng kết, cài `vastai`, tìm ID máy, self-test | List máy trên web, dán API key |

## 2. Mở port trên modem (giống bản GTX 1080)

Script in sẵn **IP máy, MAC, IP public, dải port** – chỉ cần chép vào modem.

**Bước 0 – Mạng có IP public không?** Modem → Status → **WAN IP** phải **trùng** IP public script in ra.
Nếu WAN IP dạng `100.x` / `10.x` / `172.16–31.x` → bị **CGNAT** → gọi nhà mạng xin **IP public** (thường miễn phí).

**Bước 1 – Mở port:**
- **Mỗi máy 1 mạng riêng** → dùng **DMZ** → IP máy (dễ nhất).
- **Nhiều máy chung 1 modem:**

| Máy | Nhập khi script hỏi | Dải port | Cách mở |
|---|---|---|---|
| Máy 1 | `1` | 50000-50999 | **DMZ** → IP máy 1 |
| Máy 2 | `2` | 51000-51999 | **Port Forwarding** riêng → IP máy 2 |
| Máy 3 | `3` | 52000-52999 | **Port Forwarding** riêng → IP máy 3 |

**Bước 2 – Cố định IP:** DHCP Reservation / IP MAC binding → MAC + IP trong khung vàng.

**Bước 3 – Kiểm tra:** https://portchecker.co → IP public + port đầu dải → **Open**. (Kiểm tra bằng điện thoại **4G**, không dùng wifi cùng mạng.)

### Đường dẫn trong modem

| Modem | Xem WAN IP | Cố định IP | DMZ | Port Forwarding |
|---|---|---|---|---|
| **FPT – giao diện "Home Gateway"** (thanh xanh có ổ khoá) | Gateway Status → *IPv4 Addressing* | Advanced Setup → **LAN Basic** → *3. IP MAC binding* → Add | **Security Setup → DMZ Hosting** → Enable → IP → Apply | **Security Setup → Port Forwarding**: IP máy, *TCP/UDP Port* = `50000`, Protocol **Both**, WAN `50000`–`50999` → Add |
| **FPT – đời mới** (menu Network/Access) | Status | Network → LAN → DHCP Reservation | Network → NAT → *IPv4 NAT Type* = **DMZ** | Network → NAT → **Virtual Server** |
| **Viettel** | Status | LAN → DHCP | Advance → NAT → **DMZ** | Advance → NAT → **Port Forwarding** |
| **VNPT** | Status | LAN → DHCP | Advanced → NAT → **DMZ Host** | Advanced → NAT → **Virtual Servers** |

Không tìm thấy → gọi tổng đài: *"mở port 50000–50999 TCP và UDP về IP 192.168.1.x"*.

---

## 3. Gặp lỗi (card RTX)

| Lỗi | Cách sửa |
|---|---|
| Cài Vast: `SSH password login is enabled` | `sudo bash vast_setup_rtx.sh` (lần 2 tự sửa SSH), rồi cài Vast lại |
| VM: `VM Nvidia use count failure ... in use by monitor` / `vm_test ... nvidia-smi` lỗi | Kiểm tra `cat /proc/cmdline` có `initcall_blacklist=sysfb_init`, `dmesg \| grep -c "can't reserve"` = 0. Rồi `sudo bash vast_setup_rtx.sh vm` khi **không có khách** |
| Máy **Offline** sau khi bật VM | `sudo mv /etc/systemd/system/vastai.service.mask /etc/systemd/system/vastai.service; sudo systemctl daemon-reload; sudo systemctl restart vastai` |
| Web hiện **VM: Disabled** khi đang có khách | Bình thường – khách trả máy sẽ tự hiện lại |
| Đã list nhưng `"rentable": false` | `sudo reboot`, 10 phút sau kiểm tra lại |
| Bấm **Test machine** trên web báo *No such container* | Hủy bài kiểm tra → `sudo vastai show instances` → còn suất thì `sudo vastai destroy instance <ID>`. Không bấm trước khi đủ 90% |
| Self-test: `Reliability ... > 0.9` | Đợi 1–2 ngày → `sudo bash vast_setup_rtx.sh selftest` |
| Đổi khe card **mất mạng** | Script đã cấu hình tự nhận. Ra máy: `ip -br link` → `sudo dhclient <tên en...>` |
| `lspci` thiếu card | Dây nguồn 8-pin, cắm lại/đổi khe, *Above 4G Decoding*, lắp đủ 2 CPU |
| portchecker **Closed** | Xem mục 2: CGNAT? DMZ/Port Forwarding đúng IP chưa? Thử thêm Port Forwarding song song DMZ |

**Không được làm:** `apt upgrade`, `do-release-upgrade`, tắt máy / rút mạng / đổi khe card khi có khách, sửa DMZ/Port Forwarding, chạy `vm` khi đang có khách.

> **Không đưa lên GitHub:** lệnh cài Vast (có key riêng), API key, mật khẩu.
