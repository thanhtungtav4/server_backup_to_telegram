# server_backup_to_telegram

# WordPress Backup Automation Script

![Shell Script](https://img.shields.io/badge/shell_script-%23121011.svg?style=for-the-badge&logo=gnu-bash&logoColor=white)
![Telegram](https://img.shields.io/badge/Telegram-2CA5E0?style=for-the-badge&logo=telegram&logoColor=white)
![MySQL](https://img.shields.io/badge/mysql-%2300f.svg?style=for-the-badge&logo=mysql&logoColor=white)

A robust automation script for backing up WordPress databases and themes, with Telegram notifications and chunked file delivery.

## Features ✨

- 🔐 **Secure database backups** with mysqldump
- 🗂️ **Theme directory compression** into tar.gz archives
- 📤 **Chunked file delivery** via Telegram (auto-split large files)
- 📊 **Detailed logging** with timestamps and status indicators
- 📱 **Real-time notifications** on backup start/success/failure
- ⏱️ **Duration tracking** for performance monitoring
- ❌ **Error handling** with specific failure notifications
- 🧹 **Automatic cleanup** of temporary files

## Prerequisites 📋

- Linux server with Bash
- `mysqldump` utility
- `curl` for Telegram API communication
- Telegram bot ([create one via @BotFather](https://core.telegram.org/bots#6-botfather))
- MySQL/MariaDB database credentials

## Setup ⚙️

1. **Clone the repository:**
   ```bash
   git clone https://github.com/yourusername/wordpress-backup-script.git
   cd wordpress-backup-script

chmod +x backup_script.sh

# Telegram API
BOT_TOKEN="your_telegram_bot_token"
CHAT_ID="your_telegram_chat_id"

# Site Configuration
SITE_NAME="yourdomain.com"
DB_NAME="wordpress_db_name"
DB_USER="db_username"
DB_PASS="db_password"
WEB_ROOT="/path/to/wordpress"

# Backup Settings
BACKUP_DIR="/path/to/backups"
LOG_FILE="/path/to/backup.log"