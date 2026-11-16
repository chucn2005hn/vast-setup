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
Hiện bảng: IP · MAC · **DA CAI VAST / CHUA cai Vast / khong vao duoc bang key** · card · dải port · ID máy · **DOI IP (cu: …)**.
Máy cài trước ngày 16/11 chưa có ID → chạy 1 lần trên máy đó:
```
printf 'ID=%s PORTS=%s\n' "$(sudo cat /root/vast_machine_id)" "$(sudo cat /var/lib/vastai_kaalia/host_port_range)" | sudo tee /etc/vast-info
```
