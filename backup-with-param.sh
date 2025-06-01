#!/bin/bash

# Check if all parameters are provided
if [ "$#" -ne 5 ]; then
    echo "Usage: $0 <SITE_NAME> <DB_NAME> <DB_USER> <DB_PASS> <WEB_ROOT>"
    exit 1
fi

# Telegram API Configuration
BOT_TOKEN="7308495824:AAFyQ9f5yu3f8hOhlE7--_O701iy0P1rdqU"
CHAT_ID="1334149635"

# Backup Configuration
BACKUP_DIR="/root/backups"
LOG_FILE="/root/wo_auto_backup.log"
CHUNK_SIZE=49M  # Telegram file limit with safety margin

# Parameters from command line
SITE_NAME="$1"
DB_NAME="$2"
DB_USER="$3"
DB_PASS="$4"
WEB_ROOT="$5"

# Track start time
START_TIME=$(date +%s)

# Ensure backup directory exists
mkdir -p "$BACKUP_DIR"

# Logging function
log() {
    timestamp=$(date +"%Y-%m-%d %H:%M:%S")
    echo "[$timestamp] $1" | tee -a "$LOG_FILE"
}

# Telegram notification functions
send_telegram_msg() {
    message="$1"
    response=$(curl -s -X POST "https://send-telegram-api.thanhtung74119.workers.dev/bot$BOT_TOKEN/sendMessage" \
        -d "chat_id=$CHAT_ID" \
        -d "text=$message" \
        -d "parse_mode=markdown")
    if [[ $(echo "$response" | jq -r '.ok') != "true" ]]; then
        log "❌ Failed to send message to Telegram. Response: $response"
    else
        log "✅ Message sent to Telegram successfully."
    fi
}

send_telegram_file() {
    file_path="$1"
    caption="$2"
    base_name=$(basename "$file_path")
    temp_dir=$(dirname "$file_path")
    split_prefix="${temp_dir}/${base_name}_part_"
    
    # Split file into chunks
    split -b "$CHUNK_SIZE" "$file_path" "$split_prefix"
    
    # Send each chunk
    for part in "${split_prefix}"*; do
        part_name=$(basename "$part")
        log "Sending backup part: $part_name"
        response=$(curl --progress-bar -F "chat_id=$CHAT_ID" \
            -F "document=@$part" \
            -F "caption=${caption} - Part $part_name" \
            "https://send-telegram-api.thanhtung74119.workers.dev/bot$BOT_TOKEN/sendDocument")
        
        if [[ $(echo "$response" | jq -r '.ok') != "true" ]]; then
            log "❌ Failed to send file part to Telegram. Response: $response"
        else
            log "✅ File part sent to Telegram successfully."
        fi
        
        rm -f "$part"
    done
}

# Start backup process
log "🚀 Initiating backup for: $SITE_NAME"
send_telegram_msg "🔄 *Backup Initiated*  
• Website: $SITE_NAME  
• Server: $(hostname)  
• Timestamp: $(date +'%Y-%m-%d %H:%M:%S')"

# Backup database
log "🔍 Creating database backup..."
DATE=$(date +"%Y%m%d-%H%M%S")
DB_BACKUP_FILE="$BACKUP_DIR/${SITE_NAME}_db_$DATE.sql"
mysqldump -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" > "$DB_BACKUP_FILE" 2>> "$LOG_FILE"

if [ $? -ne 0 ]; then
    log "❌ Database backup failed!"
    send_telegram_msg "❌ *Database Backup Failed!*  
• Site: $SITE_NAME  
• Check logs for details"
    exit 1
fi

# Compress database
DB_ARCHIVE="$BACKUP_DIR/${SITE_NAME}_db_$DATE.tar.gz"
tar -czf "$DB_ARCHIVE" -C "$BACKUP_DIR" "$(basename "$DB_BACKUP_FILE")" && rm -f "$DB_BACKUP_FILE"
send_telegram_file "$DB_ARCHIVE" "💾 Database Backup - $SITE_NAME"
rm -f "$DB_ARCHIVE"

# Backup themes
log "🎨 Backing up theme files..."
THEME_ARCHIVE="$BACKUP_DIR/${SITE_NAME}_themes_$DATE.tar.gz"
tar -czf "$THEME_ARCHIVE" -C "$WEB_ROOT/wp-content" themes/ 2>> "$LOG_FILE"

if [ $? -ne 0 ]; then
    log "❌ Theme backup failed!"
    send_telegram_msg "❌ *Theme Backup Failed!*  
• Site: $SITE_NAME  
• Check logs for details"
    exit 1
fi

send_telegram_file "$THEME_ARCHIVE" "🖼️ Theme Files - $SITE_NAME"
rm -f "$THEME_ARCHIVE"

# Calculate duration
END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))
MINUTES=$((DURATION / 60))
SECONDS=$((DURATION % 60))

# Final success notification
log "✅ Backup completed successfully in ${MINUTES}m ${SECONDS}s!"
send_telegram_msg "✅ *Backup Completed Successfully!*  
• Website: $SITE_NAME  
• Components: Database + Theme Files  
• Duration: ${MINUTES}m ${SECONDS}s  

All backup files have been transferred to Telegram."

log "✔️ All operations finished for $SITE_NAME"
