# Bộ cài máy cho thuê GPU trên Vast.ai

Chọn đúng loại card đang cắm trong máy rồi bấm vào hướng dẫn tương ứng:

| Card trong máy | Hướng dẫn | Script |
|---|---|---|
| **RTX 3060 12GB, RTX 2060 12GB** (và RTX khác) | 👉 [README_RTX.md](README_RTX.md) | `vast_setup_rtx.sh` |
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
