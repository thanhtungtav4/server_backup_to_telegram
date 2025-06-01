# WordPress Backup Script with Telegram Notifications

![Backup Automation](https://img.shields.io/badge/Backup-Automated-success)
![Telegram Integration](https://img.shields.io/badge/Telegram-Integrated-blue)
![Cloudflare Proxy](https://img.shields.io/badge/Cloudflare-Proxy-orange)

Automated backup solution for WordPress sites that compresses database and theme files, then sends them to Telegram via Cloudflare Worker proxy.

## Features

- 🗄️ Database backup with mysqldump
- 🎨 Theme files compression
- ✈️ Telegram notifications with progress updates
- 🔄 Cloudflare Worker proxy support
- 📁 File splitting for large backups
- 📝 Detailed logging
- ⏱️ Backup duration tracking
- 🔒 Parameterized execution

## Requirements

### Server Environment
- Linux server (Ubuntu/CentOS recommended)
- Bash shell
- MySQL/MariaDB
- WordPress installation

### Tools
- `curl`
- `jq`
- `tar`
- `split`
- `mysqldump`

### Install dependencies:
```bash
sudo apt-get update && sudo apt-get install curl jq tar -y
```
### Telegram Setup

Create bot with @BotFather

Note your BOT_TOKEN

Get CHAT_ID using @userinfobot

Cloudflare Worker
Deploy proxy from:

```bash
https://github.com/tuanpb99/cf-worker-telegram
```
# Download script
wget https://raw.githubusercontent.com/thanhtungtav4/server_backup_to_telegram/main/backup-with-param.sh

# Make executable
chmod +x backup-with-param.sh

# Create backup directory
```bash
sudo mkdir -p /root/backups
```
Configuration
Edit script with your credentials:

```bash
nano backup-with-param.sh
```
Update these values:

```bash
BOT_TOKEN="123456:ABC-DEF1234ghIkl-zyx57W2v1u123ew11"
CHAT_ID="-1001234567890"
PROXY_URL="https://your-worker-name.workers.dev"
BACKUP_DIR="/root/backups"
LOG_FILE="/root/wo_auto_backup.log"
```
### Usage
Basic Command
```bash
./backup-with-param.sh  "My Site Name" database_name db_user db_password /var/www/example.com/htdocs
```

### Parameters
Parameter	Description	Example
SITE_NAME	Website identifier	My Blog
DB_NAME	WordPress database name	wp_db
DB_USER	Database username	wp_admin
DB_PASS	Database password	P@ssw0rd!
WEB_ROOT	WordPress root path	/var/www/site.com/htdocs
### Sample Output
```text
[2025-06-01 10:30:45] 🚀 Initiating backup for: My Dental Clinic
[2025-06-01 10:31:02] 🔍 Creating database backup...
[2025-06-01 10:31:15] Sending backup part: dental_db_20250601-103045.tar.gz_part_aa
[2025-06-01 10:32:30] 🎨 Backing up theme files...
[2025-06-01 10:33:45] ✅ Backup completed successfully in 3m 0s!
```
### Telegram Notifications
```text
Start Notification
🔄 Backup Initiated
• Website: My Dental Clinic
• Server: server1.example.com
• Timestamp: 2025-06-01 10:30:45

File Transfer
📤 Sending database backup (Part 1/3)
📤 Sending theme files (Part 1/2)

Completion Alert
✅ Backup Completed Successfully!
• Website: My Dental Clinic
• Components: Database + Theme Files
• Duration: 3m 15s
```

### Automation with Cron
Schedule daily backups at 2 AM:

```bash
crontab -e
```
Add:

```bash
0 2 * * * /root/backup-with-param.sh \
    "My Site" \
    wp_db \
    wp_admin \
    "secure_password" \
    /var/www/mysite.com/htdocs
```
### Error Handling
Common issues and solutions:

Database Connection Failed:

```log
mysqldump: Got error: 1045: Access denied...
Verify MySQL credentials

Check user privileges

File Permission Errors:
```
```log
tar: themes: Cannot open: Permission denied
Adjust permissions: chmod -R 755 /var/www

Telegram API Errors:
```
```log
{"ok":false,"error_code":400,"description":"Bad Request"}
Verify BOT_TOKEN and CHAT_ID

Check proxy connectivity

File Size Too Large:
```
```log
Request Entity Too Large
Reduce CHUNK_SIZE in script (default: 49M)

Advanced Configuration
Include Plugins Directory
Modify theme backup section:
```
```bash
tar -czf "$THEME_ARCHIVE" -C "$WEB_ROOT/wp-content" themes/ plugins/
```

### Backup Retention Policy
Add to end of script:

```bash
# Keep backups for 7 days
find "$BACKUP_DIR" -name "${SITE_NAME}_*" -mtime +7 -exec rm {} \;
Email Notifications
Add after error checks (requires mailutils):
```

```bash
echo "Backup failed for $SITE_NAME" | mail -s "Backup Failure" admin@example.com
License
MIT License

Support
Script Issues

Proxy Worker
```

### Key features of this documentation:
```text
1. **Clear Structure**:
   - Organized sections with emoji headers
   - Requirements checklist
   - Step-by-step installation
   - Parameter reference table

2. **Visual Elements**:
   - Status badges for key features
   - Sample command/output blocks
   - Notification previews

3. **Troubleshooting Guide**:
   - Common errors with solutions
   - Permission fixes
   - API error resolution

4. **Automation Instructions**:
   - Cron job setup
   - Retention policy example
   - Email notification integration

5. **Advanced Configuration**:
   - Plugin backup instructions
   - Custom retention periods
   - Size limit adjustments

6. **Support Resources**:
   - License information
   - GitHub issue links
   - Related project references

The document uses:
- Clear section headers
- Code blocks for commands/configs
- Tables for parameter documentation
- Emoji visual cues
- Error handling scenarios
- Concise instructions
- External links for reference
```
