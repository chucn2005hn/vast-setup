# Cài máy cho thuê trên Vast.ai – **1× RTX 2060 12GB**

> Dùng chung script **`vast_setup_rtx.sh`** (bản RTX). File này là **lối tắt cho máy 1 card 2060 12GB**, gom mọi kinh nghiệm đã chạy thật (máy 155486 – 2060, máy 155963 – 3060).
> Máy nhiều card / card 3060 → xem [README_RTX.md](README_RTX.md). GTX 1080 → [README_1080.md](README_1080.md).

---

## 0. Chuẩn bị phần cứng (làm TRƯỚC khi cài)

| Mục | Yêu cầu | Vì sao |
|---|---|---|
| Card | 1× RTX 2060 **12GB**, dây PCIe 8-pin riêng | 6GB ít khách |
| Nguồn | **650W** đủ cho 1 card (+2 Xeon). 2 card → **850W** | Nguồn yếu → máy sập, bị phạt |
| **RAM** | ≥ 32GB, **chia đều cho CẢ 2 CPU** (main 2 CPU) | CPU không có RAM → card cắm bên đó bị lỗi NCCL / "GPU PCIE issue" |
| Khe card | Ưu tiên khe **x16 thuộc CPU1** | Ít lỗi PCIe nhất |
| Ổ | **NVMe**, cài Ubuntu chừa trống **>150GB** (chọn LVM) | Script tạo ổ riêng cho Docker |
| BIOS | **VT-x, VT-d bật** · **Above 4G Decoding bật** · **Secure Boot tắt** | VM + nhận card |
| Mạng | 1 dây LAN, gói có **upload cao** | Vast đo upload, < 100 Mbps ít khách |
| Hệ điều hành | **Ubuntu Server 22.04** | Đã test |

---

## ⭐ SAO CHÉP THEO THỨ TỰ

🪟 = CMD Windows (`C:\Users\...>`) · 🐧 = máy Ubuntu (`lehien@lehien:~$`)

**Chỉ 1 lần trên Windows (đã có key thì bỏ qua):**
```
ssh-keygen -t ed25519
```
```
type %USERPROFILE%\.ssh\id_ed25519.pub
```
→ copy dòng `ssh-ed25519 AAAA...` (CẢ chữ `ssh-ed25519`) → dán vào https://github.com/settings/ssh/new

**🐧 Lệnh 1 – ngồi ở máy, lần chạy 1:**
```
sudo apt update && sudo apt install -y openssh-server wget && wget -O vast_setup_rtx.sh https://raw.githubusercontent.com/chucn2005hn/vast-setup/main/vast_setup_rtx.sh && sudo bash vast_setup_rtx.sh
```
- Hỏi số card → `1` · hỏi `[y/N]` → `y` · cuối → `y` khởi động lại
- Bảng kiểm tra phải toàn **[DU]**, nhất là dòng **"Ca 2 CPU deu co RAM"**

**🪟 Lệnh 2 – sau 3 phút:**
```
ssh lehien@IP_MAY
```
**🐧 Lệnh 3 – lần chạy 2:**
```
sudo bash vast_setup_rtx.sh
```
- *"May thu may?"* → **Enter** (mạng riêng) · chung modem → `2`, `3`… · modem báo trùng port → gõ dải, vd `40000-40999`
- **Khung vàng port** → vào modem: **DMZ** (mạng riêng) hoặc **Port Forwarding** dải port → IP máy, TCP+UDP · **khoá IP theo MAC** (DHCP Binding / IP MAC binding) → portchecker.co **Open** → Enter
- **Khung vàng cài Vast** → https://cloud.vast.ai/host/setup → copy lệnh `wget ...` → dán → port **đúng dải trong khung vàng** → đợi `Done!` + hết *Pulling pytorch* (về lại `$`)

**🐧 Lệnh 3 lại – lần chạy 3:**
- Script tự bật **VM**, gửi thông tin lên web
- **List máy trên web** (giá dưới) → Enter
- **API key**: https://cloud.vast.ai/manage-keys/ → New → **dán vào máy** (KHÔNG gửi cho ai)

### Giá gợi ý RTX 2060 12GB
| On-demand | Min bid | Storage | Upload | Download | Volume |
|---|---|---|---|---|---|
| **0.06** | 0.05 | 0.15 | 3 | 2 | ~⅓ ổ (vd 100–115 GB) |

Xem giá chợ trước khi đặt (cột *gia* = khách trả, đã gồm phí ~25%):
```
sudo vastai search offers "gpu_name=RTX_2060 num_gpus=1 verified=any rentable=true" -o dph --raw | jq -r '.[] | "\(.machine_id)  gia=\(.dph_total*1000|round/1000)  tincay=\((.reliability2 // .reliability)*100|round)%  up=\(.inet_up|round)Mbps  \(.geolocation)"' | head -20
```

---

## 1. Sau khi list – kiểm tra

```
sudo vastai search offers "machine_id=$(sudo cat /root/vast_machine_id) verified=any rentable=any rented=any" --raw | jq -r '.[] | "goi \(.id): \(.num_gpus) card, rentable=\(.rentable), rented=\(.rented)"'
```
- `rentable=true` → đang chờ khách ✅ · `rented=true` → đang có khách ✅
- `rentable=false, rented=false` → xem mục 3

**Báo ngay lên web** (VM / mạng mới / card mới) – lệnh hỗ trợ Vast hướng dẫn:
```
sudo systemctl restart vastai.service && sudo python3 /var/lib/vastai_kaalia/send_mach_info.py --speedtest
```
hoặc gọn: `sudo bash vast_setup_rtx.sh web`

Web vẫn **VM: Disabled** → kiểm tra trên máy (phải `on`), chưa `on` thì bật rồi báo lại:
```
sudo python3 /var/lib/vastai_kaalia/enable_vms.py check
sudo bash vast_setup_rtx.sh vm
```
Self-test (khi độ tin cậy > 90% và **không có khách**):
```
sudo bash vast_setup_rtx.sh selftest
```

---

## 2. Kiểm tra sức khoẻ máy (chỉ đọc, chạy lúc có khách cũng được)

```
nvidia-smi --query-gpu=index,pci.bus_id,pcie.link.width.current,pcie.link.gen.max,temperature.gpu,power.draw --format=csv
sudo dmesg | grep -c "PCIe Bus Error"
for n in /sys/devices/system/node/node*; do echo "$(basename $n): $(awk '/MemTotal/{print int($4/1024/1024)}' $n/meminfo) GB"; done
```
- Độ rộng khe phải **16** · lỗi PCIe nên = **0** · mỗi node (CPU) đều có RAM · nhiệt < 80°C
- `gen.current = 1` lúc card nghỉ là **bình thường** (tiết kiệm điện)

Gom log PCIe gửi hỗ trợ: xem lệnh "pcie_log" trong [README_RTX.md](README_RTX.md) mục lỗi.

---

## 3. Gặp lỗi (đã gặp thật)

| Lỗi | Nguyên nhân | Sửa |
|---|---|---|
| Web: **"GPU PCIE issue"**, máy bị ẩn | Card cắm bên **CPU không có RAM**, hoặc khe tiếp xúc kém | Kiểm tra node RAM (mục 2). Khi **hết khách**: chia RAM cho cả 2 CPU / lau chân card, cắm lại. Sửa xong Vast **tự** gỡ cờ (vài giờ) |
| Self-test: **NCCL ... SIGSEGV** | Như trên (node RAM = 0GB) | Như trên |
| Self-test: **0 offers / No on-demand offer** | Máy chưa list hoặc đang bị ẩn | List máy; đợi gỡ cờ |
| Self-test: **HTTP 403** | API key sai / đã xoá | `sudo vastai set api-key KEY_MOI` |
| Thêm/đổi card → **mất SSH** | Máy đổi IP | `arp -a` (Windows) tìm MAC máy → **khoá IP theo MAC** trên modem → sửa Port Forwarding |
| Màn hình **đứng ở logo** BIOS | Bình thường (script tắt màn hình cho VM) | SSH vào bằng IP |
| **VM: Disabled** dù máy báo `on` | Web chưa cập nhật | `sudo systemctl restart vastai && sudo python3 /var/lib/vastai_kaalia/send_mach_info.py` |
| VM: `IOMMU groups not set up` | Driver bật modeset | `sudo bash vast_setup_rtx.sh vm` (bản mới tự sửa) |
| VM: lỗi qemu 6.30/6.31 | Gói lệch phiên bản | `sudo bash vast_setup_rtx.sh vm` (bản mới tự sửa) |
| Web hiện **mạng cũ** | Vast chưa đo lại | Lệnh `--speedtest` ở mục 1 |
| `"rentable": false` lâu | Bị cờ lỗi / cần làm mới | Settings → Update Listing; vẫn vậy → nhắn hỗ trợ kèm **offer id** |
| `Waiting for cache lock` | Vast đang cài gói ngầm | Chờ ≤10 phút, không Ctrl+C |

---

## 4. KHÔNG làm
- `apt upgrade`, `do-release-upgrade`
- Tắt máy / rút mạng / đổi khe / chuyển RAM **khi đang có khách**
- Bấm "Test machine" trên web khi độ tin cậy < 90%
- Gửi **API key, lệnh cài Vast, mật khẩu** cho bất kỳ ai / lên GitHub
- Dán lại **kết quả** (output) vào terminal – chỉ dán **lệnh**

---

## 5. Tự động theo dõi máy, báo về Discord (nên cài cho MỌI máy)

Cứ 5 phút kiểm tra: **đổi IP**, mất mạng, máy khởi động lại, dịch vụ Vast tắt, **thiếu card**, card quá nóng, **lỗi PCIe**, ổ đầy, **máy bị ẩn trên chợ**, **có khách mới / khách trả máy**. Mỗi sáng 8h gửi báo cáo tổng.

1. Discord → kênh (vd `#vast`) → ⚙️ Edit Channel → Integrations → Webhooks → New Webhook → **Copy Webhook URL** (làm 1 lần, dùng chung mọi máy)
2. Trên từng máy:
```
wget -O vast_monitor.sh https://raw.githubusercontent.com/chucn2005hn/vast-setup/main/vast_monitor.sh && sudo bash vast_monitor.sh install
```
→ dán link webhook, đặt tên máy (vd `may-2060-156128`), Enter
3. Lệnh: `sudo vast-monitor status` (xem) · `sudo vast-monitor test` (gửi thử) · `sudo vast-monitor uninstall` (gỡ)

> Máy **tắt hẳn / mất điện** thì không tự báo được → nếu **sáng không thấy báo cáo 8h** của máy nào là máy đó có vấn đề.
> **Không** đưa link webhook lên GitHub hay gửi cho người khác.
