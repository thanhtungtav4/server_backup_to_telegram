# 🛡️ Server Security & Error Log Reporter với Biểu Đồ Telegram

![Shell Script](https://img.shields.io/badge/shell_script-%23121011.svg?style=for-the-badge&logo=gnu-bash&logoColor=white)
![Telegram](https://img.shields.io/badge/Telegram-2CA5E0?style=for-the-badge&logo=telegram&logoColor=white)
![QuickChart](https://img.shields.io/badge/QuickChart-API-orange?style=for-the-badge)
![Nginx](https://img.shields.io/badge/nginx-%23009639.svg?style=for-the-badge&logo=nginx&logoColor=white)

Script tự động phân tích log hệ thống (Nginx, SSH, Fail2ban), theo dõi tài nguyên VPS, tự động render **biểu đồ thống kê sắc nét (Retina PNG)** qua **QuickChart API** và gửi báo cáo an ninh định kỳ về Telegram.

---

## ✨ Điểm Nổi Bật

- 📊 **Gửi biểu đồ trực quan (Chart Image):** Tự động tạo biểu đồ cột Dark Mode hiển thị số lượng lỗi 5xx, 403, 404, brute-force SSH và Fail2ban bans.
- 🚀 **100% Bash thuần & Siêu nhẹ:** Chạy được trên **mọi Linux server / VPS** (Ubuntu, Debian, CentOS, AlmaLinux, WordOps, EasyEngine,...). **Không cần cài đặt Python, matplotlib hay Node.js đồ họa nặng nề**.
- ⚙️ **Tự động nạp cấu hình:** Tự động tìm kiếm và nạp các biến môi trường từ `backup.env` (tương thích hoàn hảo với hệ thống `backup.sh`), không cần sửa code script.
- 🔍 **Phân tích Web Server (Nginx):**
  - Thống kê phân bố mã HTTP (2xx, 3xx, 403, 404, 5xx).
  - Tương thích cả định dạng log Nginx Combined tiêu chuẩn lẫn cấu hình WordOps/EasyEngine.
  - Bắt các đợt quét lỗ hổng phổ biến (dò file `.env`, `wp-config.php`, `xmlrpc.php`, `phpmyadmin`, `setup.php`,...).
  - Top các địa chỉ IP gửi nhiều request lỗi/spam nhất.
- 🔐 **Giám sát an ninh SSH:**
  - Hỗ trợ cả file log truyền thống (`/var/log/auth.log`, `/var/log/secure`) lẫn `journalctl -u ssh` trên Ubuntu 24.04+ / systemd.
  - Đếm số lần brute-force thất bại & Top IP tấn công SSH.
  - Cảnh báo các phiên đăng nhập SSH thành công (kèm User, IP, thời gian).
- 🛡️ **Tích hợp Fail2ban:** Đếm số IP bị ban trong ngày và hiển thị các jail vừa kích hoạt.
- 💻 **Tài nguyên hệ thống:** Giám sát % RAM, % dung lượng ổ cứng (Disk) và CPU Load.
- 🔄 **Hỗ trợ Cloudflare Worker Proxy:** Vượt qua tình trạng một số nhà mạng chặn kết nối trực tiếp đến `api.telegram.org`.

---

## 📸 Xem Trước Báo Cáo Trên Telegram

### 1. Ảnh Biểu Đồ & Tóm Tắt (sendPhoto)
> **Biểu đồ cột Retina Dark Mode:**
>
> 📊 **BÁO CÁO AN NINH & SỰ CỐ MÁY CHỦ**  
> • **Server:** `vps-production`  
> • **Thời gian:** `2026-10-20 08:00:00`  
> • **Tài nguyên:** RAM: `42% (1680MB/4000MB)` | Disk: `35% (14G/40G)` | CPU: `0.15, 0.22, 0.18`  
> 
> ⚡ **Chỉ số giám sát (24h):**  
> • 🌐 Tổng HTTP Requests: **18,450** (2xx: 17200 | 3xx: 450)  
> • ⚠️ Lỗi máy chủ (5xx): **12**  
> • 🚫 Bị chặn (403): **85**  
> • 🔍 Quét/Dò file (404): **620**  
> • 🚨 SSH đăng nhập thất bại: **142**  
> • 🛡️ Fail2ban chặn IP: **16**  

### 2. Chi Tiết Phân Tích (sendMessage)
> 📋 **CHI TIẾT PHÂN TÍCH AN NINH & HỆ THỐNG**  
> 
> 🌐 **Top đường dẫn bị quét nhiều nhất (403/404):**  
> • `/.env`: **45** lần  
> • `/wp-login.php`: **32** lần  
> • `/xmlrpc.php`: **28** lần  
> • `/phpmyadmin/index.php`: **15** lần  
> 
> 🎯 **Top IP nghi vấn (Gây nhiều lỗi nhất):**  
> • `103.21.244.1`: **54** lỗi  
> • `194.38.20.10`: **38** lỗi  
> 
> 🔐 **Hoạt động đăng nhập SSH:**  
> • Thất bại (Brute-force): **142** lần  
>   ↳ `45.142.122.5`: **89** lần  
>   ↳ `185.220.101.4`: **32** lần  
> • Thành công: **2** lần  
> • `root@113.190.22.45` (Oct 20 07:15:02)  
> 
> 🛡️ **Hoạt động Fail2ban:**  
> • Tổng số IP đã khóa: **16**  
> • [sshd] -> `45.142.122.5` (03:12:45)  
> • [nginx-bad-request] -> `103.21.244.1` (05:20:10)  

---

## ⚙️ Cài Đặt & Sử Dụng

### 1. Tải script về máy chủ
```bash
cd /root
wget https://raw.githubusercontent.com/thanhtungtav4/server_backup_to_telegram/main/security-report.sh
chmod +x security-report.sh
```

### 2. Cấu hình thông tin Telegram
Bạn có thể cấu hình thông qua một trong các cách sau:

**Cách 1: Sử dụng chung file `backup.env` (Khuyến nghị)**
Script sẽ tự động tìm nạp các biến từ `backup.env` (ở cùng thư mục script hoặc `/root/backup.env`):
```bash
BOT_TOKEN="123456789:AAxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
CHAT_ID="123456789"
SITE_NAME="mywebsite.com"
```

**Cách 2: Sửa trực tiếp trong file `security-report.sh`**
Mở file `security-report.sh` bằng `nano` hoặc `vim`:
```bash
nano security-report.sh
```

Cập nhật các thông số ở phần đầu file:
```bash
BOT_TOKEN="123456789:AAxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
CHAT_ID="123456789"

# Nếu dùng Cloudflare Worker Proxy khi nhà mạng chặn Telegram:
# TELEGRAM_API="https://send-telegram-api.thanhtung74119.workers.dev"

SITE_NAME="mywebsite.com"
NGINX_ACCESS_LOG="/var/log/nginx/access.log"
NGINX_ERROR_LOG="/var/log/nginx/error.log"
```

### 3. Chạy thử nghiệm thủ công
```bash
./security-report.sh
```
Hoặc truyền tham số trực tiếp mà không cần sửa file:
```bash
./security-report.sh "My Website" "/var/log/nginx/mywebsite.com.access.log"
```

Hoặc qua biến môi trường:
```bash
BOT_TOKEN="xxx" CHAT_ID="yyy" ./security-report.sh "My Website"
```

---

## ⏰ Thiết Lập Tự Động Hóa Với Cronjob

Để nhận báo cáo tổng kết đều đặn mỗi ngày (ví dụ 08:00 sáng):

```bash
crontab -e
```

Thêm dòng sau vào cuối file crontab:
```bash
# Gửi báo cáo an ninh & sự cố hàng ngày lúc 08:00 AM
0 8 * * * /root/security-report.sh >> /root/security_report.log 2>&1
```

Nếu muốn theo dõi mỗi 6 tiếng một lần:
```bash
0 */6 * * * /root/security-report.sh >> /root/security_report.log 2>&1
```

---

## 🔧 Xử Lý Sự Cố (Troubleshooting)

1. **Telegram không nhận được ảnh hoặc báo lỗi mạng:**
   - Một số ISP tại Việt Nam chặn domain `api.telegram.org`. Hãy đổi sang proxy Cloudflare Worker trong cấu hình:
     ```bash
     TELEGRAM_API="https://send-telegram-api.thanhtung74119.workers.dev"
     ```
2. **Không thấy thông tin SSH trong báo cáo:**
   - Script tự động phát hiện `/var/log/auth.log` (Ubuntu/Debian cũ), `/var/log/secure` (CentOS/RHEL) hoặc `journalctl -u ssh` (Ubuntu 24.04+). Hãy đảm bảo script chạy dưới quyền `root` (hoặc user có quyền đọc log hệ thống).
3. **QuickChart không tạo được ảnh:**
   - Kiểm tra kết nối ra ngoài internet từ VPS: `curl -I https://quickchart.io`.
   - Nếu QuickChart không phản hồi, script sẽ **tự động chuyển sang chế độ văn bản thuần** nên không bao giờ làm gián đoạn thông báo.
