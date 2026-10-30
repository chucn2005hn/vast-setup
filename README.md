# Cài máy cho thuê GPU trên Vast.ai – **kịch bản GTX 1080 / GTX 10xx**

> ⚠️ **Kịch bản này CHỈ dành cho card GTX 1080 / GTX 10xx (đời Pascal).**
> Card khác (RTX 2060, 3060, 3090...) cách cài khác – **không dùng file này**.
>
> Đã chạy thành công trên: 2× GTX 1080, main X99-T8D, 2× Xeon E5-2686 v4, Ubuntu 22.04, modem FPT.

---

## 0. Chuẩn bị (làm 1 lần)

**Máy Windows:**
1. Nếu chưa có SSH key: mở **CMD**, gõ `ssh-keygen -t ed25519`, Enter 3 lần.
2. Thêm key vào GitHub để máy mới **tự lấy key**, khỏi phải dán:
   - CMD: `type %USERPROFILE%\.ssh\id_ed25519.pub` → copy dòng hiện ra
   - Mở https://github.com/settings/ssh/new → Title `may-windows` → dán vào ô Key → **Add SSH key**

**Máy mới:**
- Cài **Ubuntu Server 22.04** lên ổ **NVMe**, **chừa trống > 150GB** (khi cài chọn LVM, không mở rộng hết ổ).
- Chỉ cắm **1 dây mạng**.
- BIOS: bật **Intel Virtualization Technology (VT-x)**, **VT-d**, **Above 4G Decoding**; **tắt Secure Boot**.
- Main 2 CPU: khe nối với CPU2 chỉ chạy khi **lắp đủ 2 CPU**. 2 card ở 2 CPU khác nhau **vẫn chạy bình thường**.

---

## 1. Lệnh duy nhất

Ngồi trực tiếp ở máy mới (lần đầu), đăng nhập rồi dán:

```
sudo apt update && sudo apt install -y openssh-server wget && wget -O vast_setup.sh https://raw.githubusercontent.com/chucn2005hn/vast-setup/main/vast_setup.sh && sudo bash vast_setup.sh
```

Sau **mỗi lần khởi động lại**, SSH vào (`ssh <user>@<IP máy>`) và chạy lại **đúng lệnh**:

```
sudo bash vast_setup.sh
```

Script tự biết đang ở bước nào. Chỗ nào cần bạn làm tay sẽ hiện **khung vàng**.

| Lần chạy | Script làm gì | Bạn làm gì |
|---|---|---|
| **1** | Kiểm tra cấu hình, cài gói, cấu hình mạng, SSH key + tắt mật khẩu, IOMMU, gỡ driver Ubuntu, tải driver 550, tạo ổ Docker NVMe | Nhập số card đã cắm. Gõ `y` → khởi động lại |
| **2** | Cài **driver NVIDIA 550** (CUDA 12.4) | Gõ `y` → khởi động lại |
| **3** | Kiểm tra driver, cài Docker, chuẩn bị ảnh PyTorch hợp GTX 1080, **hiện thông tin mở port** | **Cài modem** theo khung vàng → kiểm tra portchecker → Enter. Rồi **cài Vast bằng tay** (khung vàng) |
| **4** | Ghi dải port, tổng kết, cài công cụ `vastai`, tự tìm ID máy, **chạy self-test** | **List máy** trên web, **dán API key** khi được hỏi |

### Cài Vast bằng tay (sau lần chạy 3)
1. Mở https://cloud.vast.ai/host/setup → copy **nguyên lệnh** (bắt đầu bằng `wget ...`) → dán vào máy → Enter
2. `starting open port` → **50000**, `ending open port` → **50999** (máy thứ 2 cùng modem: 51000 / 51999 …)
3. Đợi thấy **`NCCL test ok`** và **`=> Done!`**. Bước *"Pulling default pytorch image"* có thể đứng im 10–20 phút – **cứ đợi**.
4. Chạy `sudo bash vast_setup.sh` (lần 4)

### Lệnh phụ
| Lệnh | Tác dụng |
|---|---|
| `sudo bash vast_setup.sh check` | Chỉ kiểm tra cấu hình, không thay đổi gì |
| `sudo bash vast_setup.sh port` | Hiện lại IP, MAC, dải port để cài modem |
| `sudo bash vast_setup.sh selftest` | Chạy lại self-test (khi độ tin cậy > 90%) |
| `sudo bash vast_setup.sh status` | Xem đang ở bước nào |
| `sudo bash vast_setup.sh reset` | Làm lại từ đầu |

---

## 2. Mở port trên modem

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

## 3. Sau khi cài xong

**List máy** (script lần 4 sẽ nhắc): https://cloud.vast.ai/host/machines → máy mới → **Settings**:
**On-demand `0.05`** (đừng nhập nhầm 0.15 vào ô này) · **Min bid `0.04`** · **Storage `0.15`** · **Upload `3`** · **Download `2`** · ngày hết hạn xa → **Update Listing**

**API key** (script hỏi để chạy self-test): https://cloud.vast.ai/manage-keys/ → *API Keys* → **+ New** → copy → dán vào máy.
⚠️ API key **khác** key trong lệnh cài Vast. Không gửi key cho ai.

**Self-test để được Verified:** máy mới độ tin cậy ~**60%**, self-test đòi **> 90%** → sẽ báo `Reliability ... required > 0.9` – **bình thường**.
Để máy chạy 24/7, **1–2 ngày** sau (xem số % cạnh hình 👍 trên thẻ máy) chạy lại:
```
sudo bash vast_setup.sh selftest
```
Dòng *"Direct port count advisory"* chỉ là khuyến nghị, bỏ qua.

**Nhận tiền:** Earnings → **Payout Account** → kết nối PayPal / Wise. Vast trả thứ Sáu khi đủ **$20**.

**Không được làm:** `apt upgrade`, `do-release-upgrade`, tắt máy/rút mạng/đổi khe card khi đang có khách, sửa DMZ/Port Forwarding.

> **VM:** GTX 1080 **không chạy được VM** của Vast (ảnh VM của Vast không hỗ trợ Pascal). Máy chỉ cho thuê **Docker** – không ảnh hưởng nhiều, đa số khách dùng Docker.

---

## 4. Gặp lỗi

| Lỗi | Nguyên nhân | Cách sửa |
|---|---|---|
| Cài Vast: `SSH password login is enabled` | File `50-cloud-init.conf` bật mật khẩu | `sudo bash vast_setup.sh` (bước 3 tự sửa) hoặc xem mục SSH bên dưới |
| Cài Vast: `Install failed` ngay sau *Testing 2 gpus for NCCL* | Driver CUDA ≥ 12.8 → Vast cài PyTorch mới không chạy trên GTX 1080 | `nvidia-smi` phải ra **CUDA 12.4**. Nếu không: `echo -n 2 \| sudo tee /root/vast_stage` rồi chạy lại script |
| NCCL lỗi `cuda>=12.6, please update your driver` | Ảnh `pytorch:latest` mới | `sudo docker pull pytorch/pytorch:2.5.1-cuda12.4-cudnn9-runtime && sudo docker tag pytorch/pytorch:2.5.1-cuda12.4-cudnn9-runtime pytorch/pytorch:latest` |
| Đổi khe card xong **mất mạng** (đèn mạng tắt) | Tên card mạng đổi | Script đã cấu hình tự nhận. Máy cũ: ra máy gõ `ip -br link` → `sudo dhclient <tên en...>` |
| Đổi khe card xong **không nhận ổ / không boot** | Khe đó dùng chung đường với NVMe | Trả card về khe cũ, chọn khe khác |
| `lspci` chỉ thấy 1 card | Thiếu nguồn 8-pin / khe không chạy | Cắm lại nguồn, đổi khe, bật *Above 4G Decoding*, lắp đủ 2 CPU |
| SSH `Connection timed out` | Máy tắt / khác mạng / mất mạng | Kiểm tra máy, cùng mạng chưa |
| SSH `Connection refused` | Máy chưa khởi động xong | Đợi 2–3 phút |
| SSH `Permission denied (publickey)` | Key chưa đúng | Ra máy (mật khẩu vẫn dùng được tại chỗ), thêm key vào `~/.ssh/authorized_keys` |
| portchecker **Closed** | Modem chưa mở / CGNAT | Xem lại mục 2; thử thêm Port Forwarding song song DMZ |
| Máy **Offline** trên web | Daemon tắt | `sudo systemctl restart vastai` |
| Self-test: `Reliability ... required > 0.9` | Máy mới, chưa đủ lịch sử | Đợi 1–2 ngày rồi `sudo bash vast_setup.sh selftest` |
| `vastai set api-key` báo key sai | Dán nhầm key cài Vast | Lấy **API key** ở trang manage-keys |

> **Không đưa lên GitHub:** lệnh cài Vast (có key riêng), API key, mật khẩu.
