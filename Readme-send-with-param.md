# Backup Script for WordPress with Telegram Notifications

This script automates the backup process for a WordPress site, including database and theme files. It compresses the backups and sends them to Telegram using a Cloudflare Worker proxy for API requests.

---

## Features

- Automated backup for WordPress database and theme files
- Compresses backups for efficient storage
- Sends backup files to Telegram via a proxy to bypass restrictions
- Logs all operations for monitoring and debugging
- Splits large files to comply with Telegram's 50MB file limit
- Sends start/completion notifications with detailed metadata

---

## Requirements

### 1. Server Environment
- Linux-based server (Ubuntu/CentOS recommended)
- Bash shell

### 2. Required Tools
- `curl`: For sending requests to Telegram
- `jq`: For parsing JSON responses
- `tar`: For file compression
- `split`: To handle Telegram's file size limits

Install dependencies:
```bash

sudo apt-get update
sudo apt-get install curl jq tar -y

bash```
3. Telegram Setup
Create a bot via BotFather

Get your BOT_TOKEN from BotFather

Get your CHAT_ID using @userinfobot or group management bots

4. Cloudflare Worker Proxy
Deploy the cf-worker-telegram to bypass API restrictions:

Create Cloudflare account

Create new Worker

Copy worker code

Deploy worker and note the generated URL

Installation
1. Download the Script
bash
wget https://raw.githubusercontent.com/thanhtungtav4/server_backup_to_telegram/main/backup-with-param.sh
2. Make It Executable
bash
chmod +x backup-with-param.sh
3. Create Backup Directory
bash
sudo mkdir -p /root/backups
Configuration
Edit the script with your credentials:

bash
nano backup-with-param.sh
Update these values:

bash
# Telegram API Configuration
BOT_TOKEN="your_bot_token_here"
CHAT_ID="your_chat_id_here"
PROXY_URL="https://your-worker-name.workers.dev"

# Backup Configuration
BACKUP_DIR="/root/backups"        # Change if needed
LOG_FILE="/root/wo_auto_backup.log"
CHUNK_SIZE=49M                    # 49MB chunks for Telegram
Usage
Run the script with required parameters:

bash
./backup-with-param.sh <SITE_NAME> <DB_NAME> <DB_USER> <DB_PASS> <WEB_ROOT>
Parameters
Parameter	Description	Example
SITE_NAME	Website identifier	my_blog
DB_NAME	WordPress database name	wp_db
DB_USER	Database username	wp_admin
DB_PASS	Database password	secure_password123
WEB_ROOT	WordPress installation path	/var/www/example.com/htdocs
Example Command
bash
./backup-with-param.sh \
    "My Dental Clinic" \
    dental_wpdb \
    dental_admin \
    P@ssw0rd!2024 \
    /var/www/nhakhoaident.com/htdocs
Script Workflow
Initialization:

Creates backup directory if missing

Starts logging with timestamp

Sends Telegram start notification

Database Backup:

Diagram
Code





Theme Backup:

Diagram
Code




Completion:

Calculates backup duration

Sends success notification

Cleans up temporary files

Updates log file

Log File
Script logs all operations to:

/root/wo_auto_backup.log
View logs with:

bash
tail -f /root/wo_auto_backup.log
Sample log output:

[2025-06-01 10:30:45] 🚀 Initiating backup for: My Dental Clinic
[2025-06-01 10:31:02] 🔍 Creating database backup...
[2025-06-01 10:31:15] Sending backup part: dental_clinic_db_20250601-103045.tar.gz_part_aa
[2025-06-01 10:32:30] 🎨 Backing up theme files...
[2025-06-01 10:33:45] ✅ Backup completed successfully in 3m 0s!
Error Handling
Common Issues & Solutions
Database Connection Failed:

log
mysqldump: Got error: 1045: Access denied for user...
Verify DB credentials

Check MySQL user privileges

Test connection manually:

bash
mysql -u [user] -p[password] -e "SHOW DATABASES;"
File Permission Errors:

log
tar: wp-content/themes: Cannot open: Permission denied
Ensure script has read access:

bash
sudo chmod -R 755 /var/www
Telegram API Errors:

log
{"ok":false,"error_code":400,"description":"Bad Request: chat not found"}
Verify CHAT_ID is correct

Check bot was added to the group/channel

Test proxy connectivity:

bash
curl -I $PROXY_URL
File Size Too Large:

log
Request Entity Too Large
Reduce CHUNK_SIZE to 45M if needed

Verify split command is working

Advanced Customization
1. Adjust File Size Limit
Modify chunk size in the script:

bash
CHUNK_SIZE=45M  # For stricter networks
2. Include Additional Directories
Add more directories to backup by modifying the theme backup section:

bash
# Backup both themes and plugins
tar -czf "$THEME_ARCHIVE" -C "$WEB_ROOT/wp-content" themes/ plugins/
3. Cron Job Automation
Schedule daily backups at 2 AM:

bash
crontab -e
Add:

bash
0 2 * * * /path/to/backup-with-param.sh \
    "My Site" \
    db_name \
    db_user \
    db_pass \
    /var/www/mysite.com/htdocs
4. Retention Policy
Add this to the end of the script to keep backups for 7 days:

bash
# Cleanup old backups
find "$BACKUP_DIR" -name "${SITE_NAME}_*" -mtime +7 -exec rm {} \;
5. Email Notifications
Add email alerts on failure (requires mailutils):

bash
if [ $? -ne 0 ]; then
    echo "Backup failed for $SITE_NAME" | mail -s "Backup Failure" admin@example.com
fi
License
This project is licensed under the MIT License.

Support
For assistance, please open an issue on GitHub:

Script Repository

Proxy Worker Repository

Sample Telegram Notifications
Start Notification:
🔄 Backup Initiated
• Website: My Dental Clinic
• Server: server1
• Timestamp: 2025-06-01 10:30:45

Database Backup:
💾 Database Backup - My Dental Clinic (Part 1/3)

Completion Notification:
✅ Backup Completed Successfully!
• Website: My Dental Clinic
• Components: Database + Theme Files
• Duration: 3m 15s
All backup files have been transferred to Telegram.
