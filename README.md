# Bộ cài máy cho thuê GPU trên Vast.ai

Chọn đúng loại card đang cắm trong máy rồi bấm vào hướng dẫn tương ứng:

| Card trong máy | Hướng dẫn | Script |
|---|---|---|
| **1× RTX 2060 12GB** (lối tắt, đủ kinh nghiệm thực tế) | 👉 [README_2060.md](README_2060.md) | `vast_setup_rtx.sh` |
| **RTX 3060 12GB, RTX 2060 12GB** (và RTX khác, nhiều card) | 👉 [README_RTX.md](README_RTX.md) | `vast_setup_rtx.sh` |
| **GTX 1080 / GTX 10xx** | 👉 [README_1080.md](README_1080.md) | `vast_setup.sh` |

## Lệnh cài nhanh (dán trên máy Ubuntu 22.04 mới)

**Máy RTX 3060 / 2060:**
```
sudo apt update && sudo apt install -y openssh-server wget && wget -O vast_setup_rtx.sh https://raw.githubusercontent.com/chucn2005hn/vast-setup/main/vast_setup_rtx.sh && sudo bash vast_setup_rtx.sh
```

**Máy GTX 1080:**
```
sudo apt update && sudo apt install -y openssh-server wget && wget -O vast_setup.sh https://raw.githubusercontent.com/chucn2005hn/vast-setup/main/vast_setup.sh && sudo bash vast_setup.sh
```

> ⚠️ Mỗi máy chỉ cắm **một loại card**. Không dán lệnh cài của Vast, API key hay mật khẩu lên GitHub.

## Theo dõi máy tự động (báo qua Discord)
Cài trên từng máy (xem chi tiết mục 5 trong [README_2060.md](README_2060.md)):
```
wget -O vast_monitor.sh https://raw.githubusercontent.com/chucn2005hn/vast-setup/main/vast_monitor.sh && sudo bash vast_monitor.sh install
```

## Quét mạng: máy nào đã cài / chưa cài / đổi IP (chạy trên Windows)
Tải 1 lần (CMD):
```
powershell -Command "iwr https://raw.githubusercontent.com/chucn2005hn/vast-setup/main/vast_scan.ps1 -OutFile $env:USERPROFILE\vast_scan.ps1"
```
Mỗi lần muốn xem (CMD):
```
powershell -ExecutionPolicy Bypass -File %USERPROFILE%\vast_scan.ps1
```
Đặt / sửa tên máy ngay trên Windows (hỏi từng máy, Enter = giữ):
```
powershell -ExecutionPolicy Bypass -File %USERPROFILE%\vast_scan.ps1 -DatTen
```
Bảng: **Tên** · IP · MAC · **DA CAI VAST / CHUA cai Vast / khong vao duoc bang key** · card · dải port · ID máy · IP mạng · **DOI IP (cu: …)**. Máy tắt/mất mạng hiện ở mục **KHONG THAY TREN MANG**.

### 🆕 Xem máy nào Vast báo LỖI (lỗi port / bị ẩn / đổi IP mạng)
Lần đầu chạy lệnh quét sẽ hỏi **API key** (https://cloud.vast.ai/manage-keys/ → New). Key lưu ở `%USERPROFILE%\vast_apikey.txt` trên máy Windows của bạn – **không gửi file này cho ai**.
Sau đó cuối bảng có thêm:
- **TAT CA MAY TREN VAST.AI** – mọi máy trong tài khoản (cả máy ở chỗ khác): IP mạng, có list không, độ tin cậy, **lỗi web đang báo**
- **CO x MAY CAN XU LY** – danh sách máy lỗi màu đỏ + cách sửa

Đổi key: thêm `-DoiKey` · Chỉ quét LAN, không hỏi Vast: thêm `-KhongVast`

Xem lỗi ngay trên 1 máy Ubuntu bất kỳ (đã có API key):
```
sudo vastai show machines --raw | jq -r '(if type=="object" then .machines else . end)[] | "\(.id) ip=\(.public_ipaddr) listed=\(.listed) " + ([to_entries[] | select(.key|test("err|issue|warn";"i")) | select(.value!=null and .value!="" and .value!=false and .value!=0 and .value!=[]) | "\(.key)=\(.value|tostring)"] | join(" "))'
```

### Sửa "Port Networking Issues" (máy bị ẩn)
Gần như luôn do **máy nhảy IP LAN** → modem vẫn mở port cho IP cũ.
1. Chạy lệnh quét → máy lỗi có ghi **DOI IP (cu: …)** → lấy **IP mới + MAC**
2. Modem: **DHCP Binding** sửa MAC đó → IP mới (hoặc ép về IP cũ) · **Port Forwarding** dải port của máy → đúng IP đó, TCP+UDP
3. https://portchecker.co → nhập **IP mạng** + 1 port trong dải → phải **Open**
4. SSH vào máy: `sudo bash vast_setup_rtx.sh web` → vài phút sau lỗi tự hết

**Đặt tên lưu trên chính máy Ubuntu** (máy mới: script tự hỏi ở lần chạy 1; máy cũ: tải script mới rồi chạy 1 lần):
```
wget -O vast_setup_rtx.sh https://raw.githubusercontent.com/chucn2005hn/vast-setup/main/vast_setup_rtx.sh && sudo bash vast_setup_rtx.sh ten
```
(lệnh này cũng ghi ID + dải port để công cụ quét hiện đủ)
