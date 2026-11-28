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

## 🔎 Tìm IP máy (dùng cho mọi máy)

**🐧 Ngay trên máy Ubuntu** (cắm màn hình): IP hiện sẵn lúc đăng nhập, ở dòng `IPv4 address for enp...: 192.168.1.x`. Hoặc gõ:
```
hostname -I
```
- MAC của máy (để khoá IP trên modem): `ip -br link | grep -E "^en"`
- IP mạng (IP công cộng): `curl -4 -s ifconfig.me; echo`
- Máy **đã cài Vast bằng script** thì màn hình đứng ở logo → dùng cách trên Windows bên dưới.

**🪟 Trên Windows (PowerShell), cắm cùng modem:**
- Kiểm tra 1 máy có trong mạng không: `ping 192.168.1.118`
- Liệt kê **mọi thiết bị** (IP + MAC) – dòng có MAC lạ là máy mới:
```
1..254 | % { (New-Object Net.NetworkInformation.Ping).SendPingAsync("192.168.1.$_",500) } | Out-Null; Start-Sleep 3; arp -a | Select-String "192.168.1."
```
- Quét **đầy đủ** (tên, card, PCIe, port, ID, máy đổi IP, máy Vast báo lỗi): xem mục *Quét mạng* bên dưới. Máy mới chưa cài SSH hiện `CHUA MO SSH`.
- Không thấy máy nào? Kiểm tra Windows cùng dải: `ipconfig | findstr IPv4` → phải là `192.168.1.x` (modem khác dải thì đổi `192.168.1` trong lệnh trên).
- IP mạng của xưởng: `(Invoke-WebRequest -UseBasicParsing https://api.ipify.org).Content`

## Theo dõi máy tự động (báo qua Discord)
Cài trên từng máy (xem chi tiết mục 5 trong [README_2060.md](README_2060.md)):
```
wget -O vast_monitor.sh https://raw.githubusercontent.com/chucn2005hn/vast-setup/main/vast_monitor.sh && sudo bash vast_monitor.sh install
```

## Quét mạng + xem máy LỖI: đã cài / chưa cài / đổi IP / lỗi port / bị ẩn (chạy trên Windows)
Mở **PowerShell** (dấu nhắc `PS C:\...>`). Lệnh có `sudo` **không** chạy ở đây – phải `ssh lehien@IP` vào máy Ubuntu trước.

Tải / cập nhật công cụ (làm lại mỗi khi GitHub có bản mới):
```
iwr https://raw.githubusercontent.com/chucn2005hn/vast-setup/main/vast_scan.ps1 -OutFile $env:USERPROFILE\vast_scan.ps1
```
Mỗi lần muốn xem:
```
powershell -ExecutionPolicy Bypass -File $env:USERPROFILE\vast_scan.ps1
```
Lần đầu hỏi **API key** (https://cloud.vast.ai/manage-keys/ → New). Key lưu ở `vast_apikey.txt` trong thư mục người dùng Windows – **không gửi file này cho ai**.

Kết quả có 3 phần:
| Phần | Xem gì |
|---|---|
| **MAY TRONG MANG LAN** | Tên · IP · MAC · đã cài Vast chưa · card · **PCIe** (`x8(LOI)` = cắm sai khe) · dải port · **ID** · IP mạng · ghi chú **DOI IP (cu: …)** / **DOI MAIN + DOI IP** (ổ chuyển sang main khác → MAC mới) / **VAST BAO LOI: …** |
| Cột **Card** đặc biệt | `DANG CHAY MAY AO (VM)` = có thể đang có khách thuê VM → **không** khởi động lại · `KET CHE DO VM` / `DRIVER LOI` → hết khách thì `sudo reboot` · `KHONG THAY CARD` → cắm lại card + dây nguồn |
| **TAT CA MAY TREN VAST.AI** | Mọi máy trong tài khoản (cả máy ở chỗ khác): TenWeb (dòng *Name* trên web) · IP LAN · IP mạng · có list không · độ tin cậy · **lỗi web đang báo** |
| **CO x MAY CAN XU LY** | Danh sách máy lỗi (chữ đỏ) + cách sửa |

Thêm vào cuối lệnh khi cần: `-DatTen` (đặt tên trên Windows) · `-DoiKey` (đổi API key) · `-KhongVast` (chỉ quét LAN) · `-ChiTiet 157941` (in **toàn bộ** thông tin Vast của 1 máy – để gửi hỗ trợ)

### ⭐ Để công cụ biết máy nào là ID nào: đặt tên KHÁC NHAU cho từng máy (1 lần/máy)
Mọi máy mặc định cùng tên `lehien` → nhiều máy chung 1 modem thì không phân biệt được (cột IPLan hiện `?`). SSH vào **từng máy** chạy:
```
wget -O vast_setup_rtx.sh https://raw.githubusercontent.com/chucn2005hn/vast-setup/main/vast_setup_rtx.sh && sudo bash vast_setup_rtx.sh ten
```
→ gõ tên, vd `3060-50` (card + đuôi IP) · tên này thành **tên máy Ubuntu** và hiện ở dòng **Name:** trên thẻ máy trên web (1–2 phút, F5) → lần quét sau tự ghép đúng ID ↔ IP. Tên toàn số (vd `665`) sẽ thành `may-665`.
(Máy GTX 1080 dùng `vast_setup.sh ten`.)

Xem lỗi ngay trên 1 máy Ubuntu bất kỳ (đã có API key):
```
sudo vastai show machines --raw | jq -r '(if type=="object" then .machines else . end)[] | "\(.id) \(.hostname) ip=\(.public_ipaddr) listed=\(.listed) " + ([to_entries[] | select(.key|test("err|issue|warn";"i")) | select(.key|test("interrupt";"i")|not) | select(.value|type=="string" and .!="") | .value] | join(" | "))'
```

### Sửa "Port Networking Issues" (máy bị ẩn)
Gần như luôn do **máy nhảy IP LAN** → modem vẫn mở port cho IP cũ.
1. Chạy lệnh quét → máy lỗi có ghi **DOI IP (cu: …)** → lấy **IP mới + MAC**
2. Modem: **DHCP Binding** sửa MAC đó → IP mới (hoặc ép về IP cũ) · **Port Forwarding** dải port của máy → đúng IP đó, TCP+UDP
3. Kiểm tra port – SSH vào máy, mở tạm 1 port (10 phút, thư mục rỗng – không lộ file):
   ```
   R=$(cat /var/lib/vastai_kaalia/host_port_range); P=${R#*-}; while ss -ltn | grep -q ":$P "; do P=$((P-1)); done; echo "Vao portchecker.co kiem tra port $P"; sudo timeout 600 python3 -m http.server $P --directory $(mktemp -d)
   ```
   → https://portchecker.co nhập **IP mạng** + port vừa hiện → phải **Open** → Ctrl+C
   (bản script mới gọn hơn: `sudo bash vast_setup_rtx.sh kiemtraport`)
4. `sudo bash vast_setup_rtx.sh web` → vài phút sau lỗi tự hết

> ⚠️ **Self-test báo `Port never reachable` dù portchecker báo Open?** Modem FPT thường **không hỗ trợ NAT loopback** (máy trong nhà không gọi vòng qua IP mạng được) → self-test chạy **từ chính máy đó** luôn báo nhầm. Kiểm tra: `for h in IP_LAN IP_MANG; do timeout 12 bash -c "echo > /dev/tcp/$h/PORT" && echo "$h MO" || echo "$h KHONG"; done` (LAN `MO`, IP mạng `KHONG` = đúng là do modem). Cách chạy self-test ngay trên máy đó (đã chạy **ĐẠT** trên máy 157941): tạm gắn IP mạng vào máy trong lúc test:
> ```
> sudo ip addr add IP_MANG/32 dev lo; sudo vastai self-test machine ID 2>&1 | tee /tmp/selftest.txt; sudo ip addr del IP_MANG/32 dev lo
> ```
> Bản script mới **tự làm việc này**: `sudo bash vast_setup_rtx.sh selftest`. Hoặc chạy self-test từ một máy ở mạng khác (khác modem).

### Sửa "GPU error, unable to start instance"
SSH vào máy:
```
nvidia-smi --query-gpu=name,pcie.link.width.current --format=csv; lspci -k | grep -A3 -i nvidia | grep -iE "nvidia|driver in use"
```
| Thấy | Làm |
|---|---|
| `RTX 3060, 16` + `driver in use: nvidia` | Card ổn → `sudo bash vast_setup_rtx.sh web`, theo dõi lỗi tự hết |
| `driver in use: vfio-pci` | Card kẹt chế độ máy ảo → **khi không có khách**: `sudo reboot` |
| Không có dòng NVIDIA nào | Máy không thấy card → tắt máy, cắm lại card khe x16, dây nguồn 8-pin |
| `Failed` / `No devices` / lỗi khác | `sudo reboot` → vẫn lỗi: gửi kết quả `sudo dmesg -T \| grep -iE "xid\|nvrm" \| tail` |
