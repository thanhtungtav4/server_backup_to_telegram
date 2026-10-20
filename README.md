# WordPress Backup & Server Security Monitoring to Telegram

![Shell Script](https://img.shields.io/badge/shell_script-%23121011.svg?style=for-the-badge&logo=gnu-bash&logoColor=white)
![Telegram](https://img.shields.io/badge/Telegram-2CA5E0?style=for-the-badge&logo=telegram&logoColor=white)
![MySQL](https://img.shields.io/badge/mysql-%2300f.svg?style=for-the-badge&logo=mysql&logoColor=white)
![QuickChart](https://img.shields.io/badge/QuickChart-API-orange?style=for-the-badge)

A robust automation suite for WordPress & Linux server management:
1. **Automated Backups:** Databases and theme files backup to Telegram with auto-chunking.
2. **Security & Error Monitoring:** Daily log analysis (Nginx, SSH, Fail2ban) with visual **QuickChart** graphs sent directly to Telegram.

## Scripts in this Repository

| Script | Description | Documentation |
| :--- | :--- | :--- |
| `backup.sh` | Backup database & themes with hardcoded config | [README.md](#setup-️) |
| `backup-with-param.sh` | Parameterized backup with Cloudflare proxy | [Readme-send-with-param.md](Readme-send-with-param.md) |
| `security-report.sh` | Log analyzer & security reporter with charts | [README-security-report.md](README-security-report.md) |

---

## 1. WordPress Backup Script

### Features ✨

- 🔐 **Secure database backups** with mysqldump
- 🗂️ **Theme directory compression** into tar.gz archives
- 📤 **Chunked file delivery** via Telegram (auto-split large files)
- 📊 **Detailed logging** with timestamps and status indicators
- 📱 **Real-time notifications** on backup start/success/failure
- ⏱️ **Duration tracking** for performance monitoring
- ❌ **Error handling** with specific failure notifications
- 🧹 **Automatic cleanup** of temporary files

### Prerequisites 📋

- Linux server with Bash
- `mysqldump` utility
- `curl` for Telegram API communication
- Telegram bot ([create one via @BotFather](https://core.telegram.org/bots#6-botfather))
- MySQL/MariaDB database credentials

### Setup ⚙️

1. **Clone the repository:**
   ```bash
   git clone https://github.com/thanhtungtav4/server_backup_to_telegram.git
   cd server_backup_to_telegram
   chmod +x backup.sh security-report.sh
   ```

2. **Configure credentials:**
   Edit `backup.sh`:
   ```bash
   # Telegram API
   BOT_TOKEN="your_telegram_bot_token"
   CHAT_ID="your_telegram_chat_id"

   # Site Configuration
   SITE_NAME="yourdomain.com"
   DB_NAME="wordpress_db_name"
   DB_USER="db_username"
   DB_PASS="db_password"
   WEB_ROOT="/path/to/wordpress"
   ```

3. **Run or schedule with Cron:**
   ```bash
   0 2 * * * /root/backup.sh >> /root/wo_auto_backup.log 2>&1
   ```

---

## 2. Server Security & Error Log Reporter (with Visual Chart) 📊

`security-report.sh` reads your Nginx access/error logs, SSH auth logs, Fail2ban bans, and VPS resource metrics, renders a clean dark-mode bar chart using **QuickChart API**, and sends it to Telegram.

👉 **See detailed instructions & configuration in [README-security-report.md](README-security-report.md).**

```bash
# Run security reporter
./security-report.sh "My Website" "/var/log/nginx/access.log"

# Schedule daily digest at 08:00 AM via cron
0 8 * * * /root/security-report.sh >> /root/security_report.log 2>&1
```

---

Detail posts & tutorials:  
- https://nttung.dev/backup-du-lieu-voi-telegram-cho-server-website/  
- https://nttung.dev/

