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

- Hỏi dải port: **máy đầu tiên** ở mạng đó → Enter. Máy thứ 2 cùng mạng → `51000-51999`, thứ 3 → `52000-52999`...
- Khung **THÔNG TIN CÀI PORT** hiện ra → vào modem cài **Virtual Server** + **DHCP Reservation** theo đúng số trong khung.
- Kiểm tra trên https://portchecker.co → **Open** thì bấm Enter.
- Khung **CÀI VAST BẰNG TAY** hiện ra → làm theo:
  1. Mở https://cloud.vast.ai/host/setup
  2. Copy **nguyên lệnh** cài đặt (bắt đầu bằng `wget ...`)
  3. Dán vào máy, Enter, trả lời các câu hỏi của trình cài

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
