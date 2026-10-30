# Cài máy cho thuê GPU trên Vast.ai

Script `vast_setup.sh` cài một máy Ubuntu mới để cho thuê GPU trên Vast.ai.
Chạy làm 3 phần. Mỗi khi cần bạn làm tay, script sẽ hiện **khung vàng** hướng dẫn.

---

## Chuẩn bị (làm 1 lần)

1. **SSH key trên máy Windows** (nếu chưa có): mở CMD, gõ `ssh-keygen -t ed25519`, Enter 3 lần.
2. **Thêm SSH key vào GitHub** để máy mới tự lấy key, khỏi phải dán:
   - CMD Windows: `type %USERPROFILE%\.ssh\id_ed25519.pub` → copy dòng hiện ra
   - Mở https://github.com/settings/ssh/new → Title: `may-windows` → dán vào ô Key → **Add SSH key**

## Chuẩn bị máy mới

- Cài **Ubuntu 22.04** lên ổ **NVMe** (chừa trống phần lớn ổ, script sẽ dùng cho Docker).
- Chỉ cắm **1 dây mạng**.
- BIOS: bật **VT-x** và **VT-d** (Intel VT for Directed I/O).

---

## Phần 1 – Chuẩn bị hệ thống (ngồi trực tiếp ở máy mới)

```
sudo apt update && sudo apt install -y openssh-server wget && wget -O vast_setup.sh https://raw.githubusercontent.com/chucn2005hn/vast-setup/main/vast_setup.sh && sudo bash vast_setup.sh phase1
```

- Hỏi `[y/N]` → gõ `y`.
- Nếu hiện khung **DÁN SSH KEY** → làm theo khung.
- Cuối cùng chọn `y` để khởi động lại.

## Phần 2 – SSH, mở port, hướng dẫn cài Vast

Sau khi máy khởi động lại (đợi 2 phút), từ Windows: `ssh <user>@<IP máy mới>` rồi:

```
sudo bash vast_setup.sh phase2
```

- Hỏi **"máy thứ mấy"** trong mạng đó:
  - Mỗi máy **1 mạng riêng** → **Enter** (= máy 1, port `50000-50999`)
  - **Nhiều máy chung 1 modem** → máy đầu nhập `1`, máy sau `2`, `3`... (script tự chọn port `51000-51999`, `52000-52999`...)
- Khung **THÔNG TIN CÀI PORT** hiện ra → làm theo mục **Mở port** bên dưới.
- Kiểm tra trên https://portchecker.co → **Open** thì bấm Enter.
- Khung **CÀI VAST BẰNG TAY** hiện ra → làm theo:
  1. Mở https://cloud.vast.ai/host/setup
  2. Copy **nguyên lệnh** cài đặt (bắt đầu bằng `wget ...`)
  3. Dán vào máy, Enter, trả lời các câu hỏi của trình cài

## Mở port (mỗi mạng/modem làm 1 lần)

Script in sẵn **IP máy, MAC, IP public, dải port** trong khung vàng – chỉ cần chép vào modem.

**Bước 0 – Mạng có IP public không?**
Vào trang modem (thường `http://192.168.1.1`, tài khoản/mật khẩu in ở tem dưới đáy modem) → **Status / Trạng thái** → xem **WAN IP**.
- **Trùng** với IP public script in ra → OK, làm tiếp.
- Dạng `100.x.x.x`, `10.x.x.x`, `172.16–31.x.x` → bị **CGNAT**, mở port vô ích. Gọi tổng đài nhà mạng: *"cho tôi xin IP public động"* (thường miễn phí).

**Bước 1 – Mở port (chọn 1 trong 2):**
- **Cách A – DMZ (dễ nhất, nên dùng):** NAT → **DMZ** → Bật → IP = IP máy → Lưu.
- **Cách B – Virtual Server / Port Forwarding:** cổng ngoài & trong = dải port (vd `50000-50999`), IP = IP máy, giao thức **TCP+UDP**.

**Nhiều máy chung 1 modem:**

| Máy | Nhập khi script hỏi | Dải port | Cách mở port |
|---|---|---|---|
| Máy 1 | `1` | 50000-50999 | **DMZ** → IP máy 1 (hoặc Virtual Server) |
| Máy 2 | `2` | 51000-51999 | **Virtual Server** mới → IP máy 2 |
| Máy 3 | `3` | 52000-52999 | **Virtual Server** mới → IP máy 3 |

- DMZ chỉ trỏ được **1 máy** → giữ DMZ cho máy 1, **không sửa**.
- Mỗi máy sau thêm **1 dòng Virtual Server riêng**, đúng dải port + IP trong khung vàng.
- Mỗi máy đều phải **cố định IP** (bước 2).

**Bước 2 – Cố định IP máy:** LAN → **DHCP Reservation / Static IP** → nhập IP + MAC.

**Bước 3 – Kiểm tra:** https://portchecker.co → IP public + port đầu dải → phải **Open**.
Kiểm tra bằng máy/điện thoại **dùng 4G**, không dùng wifi cùng mạng.

| Nhà mạng | Đường dẫn thường gặp trong modem |
|---|---|
| **FPT** | Network → NAT → *IPv4 NAT Type*: chọn **DMZ** hoặc **Virtual Server**. Cố định IP: Network → LAN → DHCP Reservation. Hoặc app **Hi FPT** → Modem → Mở port |
| **Viettel** | Advance Setup / Nâng cao → NAT → **DMZ** hoặc **Port Forwarding**. Hoặc app **My Viettel** |
| **VNPT** | Advanced / Nâng cao → NAT → **DMZ Host** hoặc **Virtual Servers** |

Không tìm thấy mục nào → gọi tổng đài: *"mở port 50000–50999 TCP và UDP về IP 192.168.1.x"* (IP máy trong khung vàng).

## Phần 3 – Bật VM, tổng kết

```
sudo bash vast_setup.sh phase3
```

Cuối cùng vào https://cloud.vast.ai/host/machines → **Settings** → đặt giá, ngày hết hạn → **Update Listing**.

---

## Gặp lỗi

| Lỗi | Cách xử lý |
|---|---|
| `SSH password login is enabled` khi cài Vast | Chạy lại `sudo bash vast_setup.sh phase2` (script tự tắt mật khẩu) |
| portchecker báo **Closed** | Xem lại IP/port trên modem; thử dùng **DMZ** nếu chỉ có 1 máy ở mạng đó |
| `nvidia-smi` lỗi | Driver chưa cài xong → chạy lại phase1 rồi khởi động lại |
| Máy hiện **Offline** sau khi bật VM | `sudo systemctl restart vastai` |

> Không đưa lên đây: lệnh cài Vast (có key riêng), API key, mật khẩu.
