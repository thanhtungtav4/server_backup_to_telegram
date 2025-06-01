# Backup Script for WordPress with Telegram Notifications

This script automates the process of backing up a WordPress site's database and theme files, then sends the backup files to Telegram using a proxy service (Cloudflare Worker).

## Features

- Backs up the WordPress database and theme files.
- Compresses the backups for efficient storage and transfer.
- Sends backups to Telegram as messages and files.
- Utilizes a proxy service to bypass API restrictions (e.g., in Vietnam).

---

## Prerequisites

1. **Linux Environment**: The script is designed for Linux-based servers.
2. **Installed Dependencies**:
   - `curl`: For interacting with the Telegram API.
   - `jq`: For parsing JSON responses.
   - `tar`: For compressing backups.
3. **Cloudflare Worker Proxy**: Set up a proxy for Telegram API using [cf-worker-telegram](https://github.com/tuanpb99/cf-worker-telegram).
4. **Access Credentials**:
   - Telegram Bot Token: Obtain from [BotFather](https://t.me/botfather).
   - Chat ID: Your Telegram chat or group ID.

---

## Installation

1. **Download the Script**  
   Clone the repository or download the script file:
   ```bash
   wget https://raw.githubusercontent.com/thanhtungtav4/server_backup_to_telegram/main/backup-with-param.sh
