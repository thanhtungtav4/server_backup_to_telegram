#!/usr/bin/env bash

# ==============================================================================
# Telegram Server Security & Error Log Reporter with QuickChart
# ==============================================================================
# Script tự động phân tích log hệ thống (Nginx, SSH, Fail2ban), tài nguyên
# máy chủ, vẽ biểu đồ qua QuickChart API và gửi báo cáo bảo mật về Telegram.
# ==============================================================================

# ---------------------------- CẤU HÌNH CƠ BẢN ---------------------------------
# 1. Telegram Bot Token & Chat ID
BOT_TOKEN="${BOT_TOKEN:-""}"
CHAT_ID="${CHAT_ID:-""}"

# Telegram API endpoint (Đổi sang Cloudflare Worker proxy nếu nhà mạng chặn Telegram)
# Mặc định: https://api.telegram.org
# Proxy ví dụ: https://send-telegram-api.thanhtung74119.workers.dev
TELEGRAM_API="${TELEGRAM_API:-"https://api.telegram.org"}"

# 2. Tên máy chủ / Website nhận diện
SITE_NAME="${1:-${SITE_NAME:-"$(hostname)"}}"

# 3. Đường dẫn các file log
NGINX_ACCESS_LOG="${2:-${NGINX_ACCESS_LOG:-"/var/log/nginx/access.log"}}"
NGINX_ERROR_LOG="${3:-${NGINX_ERROR_LOG:-"/var/log/nginx/error.log"}}"
AUTH_LOG="${AUTH_LOG:-""}"          # Để trống sẽ tự động phát hiện (/var/log/auth.log hoặc /var/log/secure)
FAIL2BAN_LOG="${FAIL2BAN_LOG:-"/var/log/fail2ban.log"}"

# File ghi log hoạt động của script
REPORT_LOG="${REPORT_LOG:-"/root/security_report.log"}"
LOG_DIR=$(dirname "$REPORT_LOG")
if [ ! -d "$LOG_DIR" ] || [ ! -w "$LOG_DIR" ]; then
    mkdir -p "$LOG_DIR" 2>/dev/null || REPORT_LOG="/tmp/security_report.log"
fi

# ------------------------------------------------------------------------------

# Tự động dọn dẹp file tạm khi thoát script
TEMP_DIR="/tmp"
CHART_FILE="${TEMP_DIR}/sec_chart_$$.png"
trap 'rm -f "$CHART_FILE"' EXIT

log_msg() {
    local timestamp
    timestamp=$(date +"%Y-%m-%d %H:%M:%S")
    echo "[$timestamp] $1" | tee -a "$REPORT_LOG"
}

# Kiểm tra cấu hình bắt buộc
if [ -z "$BOT_TOKEN" ] || [ -z "$CHAT_ID" ]; then
    echo "❌ Lỗi: BOT_TOKEN hoặc CHAT_ID chưa được thiết lập!"
    echo "Cách dùng:"
    echo "  1. Mở file script và điền: BOT_TOKEN=\"...\" CHAT_ID=\"...\""
    echo "  2. Hoặc chạy qua biến môi trường: BOT_TOKEN=\"...\" CHAT_ID=\"...\" $0 [SITE_NAME] [NGINX_ACCESS_LOG]"
    exit 1
fi

log_msg "🔍 Bắt đầu phân tích log bảo mật cho: $SITE_NAME"

# ------------------------ PHÁT HIỆN LOG FILE ----------------------------------
# Nếu file Nginx access log không tồn tại theo đường dẫn mặc định, thử tìm theo SITE_NAME
if [ ! -f "$NGINX_ACCESS_LOG" ]; then
    if [ -f "/var/log/nginx/${SITE_NAME}.access.log" ]; then
        NGINX_ACCESS_LOG="/var/log/nginx/${SITE_NAME}.access.log"
    elif [ -f "/var/log/nginx/${SITE_NAME}_access.log" ]; then
        NGINX_ACCESS_LOG="/var/log/nginx/${SITE_NAME}_access.log"
    fi
fi

# Tự động phát hiện log SSH (Ubuntu/Debian vs CentOS/RHEL)
if [ -z "$AUTH_LOG" ]; then
    if [ -f "/var/log/auth.log" ]; then
        AUTH_LOG="/var/log/auth.log"
    elif [ -f "/var/log/secure" ]; then
        AUTH_LOG="/var/log/secure"
    fi
fi

# ------------------------ 1. PHÂN TÍCH TÀI NGUYÊN ------------------------------
REPORT_TIME=$(date +"%Y-%m-%d %H:%M:%S")

# Disk Usage (Root partition)
DISK_INFO=$(df -h / 2>/dev/null | awk 'NR==2 {print $5 " (" $3 "/" $2 ")"}')
DISK_INFO="${DISK_INFO:-"N/A"}"

# Memory Usage
if command -v free >/dev/null 2>&1; then
    RAM_INFO=$(free -m 2>/dev/null | awk 'NR==2 {printf "%.0f%% (%dMB/%dMB)", ($3/$2)*100, $3, $2}')
else
    RAM_INFO="N/A"
fi

# CPU Load Average
CPU_LOAD=$(uptime 2>/dev/null | awk -F'load average:' '{print $2}' | sed 's/^ //')
CPU_LOAD="${CPU_LOAD:-"N/A"}"

# ------------------------ 2. PHÂN TÍCH NGINX LOG ------------------------------
TODAY_NGINX=$(date +"%d/%b/%Y")
TOTAL_REQ=0
COUNT_2XX=0
COUNT_3XX=0
COUNT_403=0
COUNT_404=0
COUNT_5XX=0
TOP_PATHS=""
TOP_OFFENDING_IPS=""

if [ -f "$NGINX_ACCESS_LOG" ]; then
    # Kiểm tra số dòng log hôm nay
    TODAY_MATCHES=$(grep "$TODAY_NGINX" "$NGINX_ACCESS_LOG" 2>/dev/null | wc -l | tr -d ' ')
    
    if [ "$TODAY_MATCHES" -gt 50 ]; then
        LOG_STREAM="grep '$TODAY_NGINX' '$NGINX_ACCESS_LOG'"
    else
        LOG_STREAM="tail -n 25000 '$NGINX_ACCESS_LOG'"
    fi

    # Thống kê mã trạng thái HTTP
    STATUS_COUNTS=$(eval "$LOG_STREAM" 2>/dev/null | grep -oE '" [1-5][0-9]{2} ' | tr -d '" ' | sort | uniq -c)
    
    if [ -n "$STATUS_COUNTS" ]; then
        COUNT_2XX=$(echo "$STATUS_COUNTS" | awk '$2 ~ /^2/ {sum += $1} END {print sum+0}')
        COUNT_3XX=$(echo "$STATUS_COUNTS" | awk '$2 ~ /^3/ {sum += $1} END {print sum+0}')
        COUNT_403=$(echo "$STATUS_COUNTS" | awk '$2 == "403" {sum += $1} END {print sum+0}')
        COUNT_404=$(echo "$STATUS_COUNTS" | awk '$2 == "404" {sum += $1} END {print sum+0}')
        COUNT_5XX=$(echo "$STATUS_COUNTS" | awk '$2 ~ /^5/ {sum += $1} END {print sum+0}')
        TOTAL_REQ=$((COUNT_2XX + COUNT_3XX + COUNT_403 + COUNT_404 + COUNT_5XX))
    fi

    # Top 5 đường dẫn bị lỗi 403 / 404 (Dấu hiệu bị bot scan lỗ hổng .env, wp-login, xmlrpc,...)
    TOP_PATHS=$(eval "$LOG_STREAM" 2>/dev/null | grep -E '" (403|404) ' | awk '{print $7}' | grep -v '^-$' | sort | uniq -c | sort -nr | head -n 5)

    # Top 5 IP gửi nhiều request lỗi nhất (4xx & 5xx)
    TOP_OFFENDING_IPS=$(eval "$LOG_STREAM" 2>/dev/null | grep -E '" [45][0-9]{2} ' | awk '{print $1}' | sort | uniq -c | sort -nr | head -n 5)
fi

# ------------------------ 3. PHÂN TÍCH SSH SECURITY ---------------------------
TODAY_SYSLOG=$(date +"%b %e")
COUNT_SSH_FAIL=0
COUNT_SSH_ACCEPTED=0
TOP_SSH_ATTACKERS=""
RECENT_SSH_LOGINS=""

if [ -n "$AUTH_LOG" ] && [ -f "$AUTH_LOG" ]; then
    SSH_MATCHES=$(grep "$TODAY_SYSLOG" "$AUTH_LOG" 2>/dev/null | wc -l | tr -d ' ')
    if [ "$SSH_MATCHES" -gt 10 ]; then
        SSH_STREAM="grep '$TODAY_SYSLOG' '$AUTH_LOG'"
    else
        SSH_STREAM="tail -n 5000 '$AUTH_LOG'"
    fi
    
    SSH_DATA=$(eval "$SSH_STREAM" 2>/dev/null)

    # Số lần SSH thất bại (Brute force)
    COUNT_SSH_FAIL=$(echo "$SSH_DATA" | grep -E "(Failed password|authentication failure|Failed publickey)" | wc -l | tr -d ' ')

    # Top IP brute-force SSH nhiều nhất
    TOP_SSH_ATTACKERS=$(echo "$SSH_DATA" | grep -E "(Failed password|authentication failure)" | grep -oE '[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}' | sort | uniq -c | sort -nr | head -n 3)

    # Đăng nhập SSH thành công
    SSH_ACCEPTED_LINES=$(echo "$SSH_DATA" | grep -E "Accepted (password|publickey)")
    if [ -n "$SSH_ACCEPTED_LINES" ]; then
        COUNT_SSH_ACCEPTED=$(echo "$SSH_ACCEPTED_LINES" | wc -l | tr -d ' ')
        RECENT_SSH_LOGINS=$(echo "$SSH_ACCEPTED_LINES" | tail -n 3 | awk '{
            user=""; ip="";
            for(i=1;i<=NF;i++){
                if($i=="for") user=$(i+1);
                if($i=="from") ip=$(i+1);
            }
            print "• <code>" user "@" ip "</code> (" $1 " " $2 " " $3 ")"
        }')
    fi
fi

# ------------------------ 4. PHÂN TÍCH FAIL2BAN -------------------------------
COUNT_BANNED=0
RECENT_BANS=""
TODAY_ISO=$(date +"%Y-%m-%d")

if [ -f "$FAIL2BAN_LOG" ]; then
    F2B_MATCHES=$(grep "$TODAY_ISO" "$FAIL2BAN_LOG" 2>/dev/null | wc -l | tr -d ' ')
    if [ "$F2B_MATCHES" -gt 5 ]; then
        F2B_STREAM="grep '$TODAY_ISO' '$FAIL2BAN_LOG'"
    else
        F2B_STREAM="tail -n 2000 '$FAIL2BAN_LOG'"
    fi

    F2B_DATA=$(eval "$F2B_STREAM" 2>/dev/null)
    BANNED_LINES=$(echo "$F2B_DATA" | grep " Ban ")
    if [ -n "$BANNED_LINES" ]; then
        COUNT_BANNED=$(echo "$BANNED_LINES" | wc -l | tr -d ' ')
        RECENT_BANS=$(echo "$BANNED_LINES" | tail -n 3 | awk '{
            jail=$6; ip="";
            for(i=1;i<=NF;i++) if($i=="Ban") ip=$(i+1);
            split($2, t, ",");
            print "• " jail " -> <code>" ip "</code> (" t[1] ")"
        }')
    fi
fi

# ------------------------ 5. VẼ CHART VỚI QUICKCHART API ----------------------
log_msg "📊 Đang khởi tạo biểu đồ qua QuickChart API..."

CHART_SUCCESS=0
CHART_PAYLOAD=$(cat <<EOF
{
  "backgroundColor": "#0f172a",
  "width": 750,
  "height": 420,
  "devicePixelRatio": 2,
  "chart": {
    "type": "bar",
    "data": {
      "labels": ["Lỗi 5xx", "Lỗi 403", "Lỗi 404", "SSH Thất Bại", "IPs Bị Ban"],
      "datasets": [{
        "label": "Số lượng",
        "data": [$COUNT_5XX, $COUNT_403, $COUNT_404, $COUNT_SSH_FAIL, $COUNT_BANNED],
        "backgroundColor": [
          "rgba(239, 68, 68, 0.9)",
          "rgba(249, 115, 22, 0.9)",
          "rgba(234, 179, 8, 0.9)",
          "rgba(220, 38, 38, 0.9)",
          "rgba(139, 92, 246, 0.9)"
        ],
        "borderColor": [
          "#ef4444",
          "#f97316",
          "#eab308",
          "#dc2626",
          "#8b5cf6"
        ],
        "borderWidth": 1.5,
        "borderRadius": 6
      }]
    },
    "options": {
      "legend": { "display": false },
      "title": {
        "display": true,
        "text": "BÁO CÁO BẢO MẬT & LỖI HỆ THỐNG - $SITE_NAME",
        "fontColor": "#f8fafc",
        "fontSize": 18,
        "padding": 16
      },
      "plugins": {
        "datalabels": {
          "display": true,
          "anchor": "end",
          "align": "top",
          "color": "#f8fafc",
          "font": { "weight": "bold", "size": 13 }
        }
      },
      "scales": {
        "yAxes": [{
          "ticks": { "fontColor": "#94a3b8", "beginAtZero": true, "precision": 0 },
          "gridLines": { "color": "#1e293b" }
        }],
        "xAxes": [{
          "ticks": { "fontColor": "#e2e8f0", "fontSize": 13, "fontStyle": "bold" },
          "gridLines": { "display": false }
        }]
      }
    }
  }
}
EOF
)

# Tải ảnh chart từ QuickChart
curl -s --connect-timeout 8 --max-time 15 -X POST "https://quickchart.io/chart" \
    -H "Content-Type: application/json" \
    -d "$CHART_PAYLOAD" \
    -o "$CHART_FILE" 2>> "$REPORT_LOG"

if [ -s "$CHART_FILE" ]; then
    CHART_SUCCESS=1
    log_msg "✅ Tạo biểu đồ thành công (${CHART_FILE})"
else
    log_msg "⚠️ Không thể kết nối tới QuickChart, chuyển sang chế độ báo cáo văn bản thuần."
fi

# ------------------------ 6. SOẠN TIN NHẮN BÁO CÁO ----------------------------
# Caption tóm tắt cho ảnh biểu đồ (< 1000 ký tự)
SUMMARY_CAPTION="📊 <b>BÁO CÁO AN NINH & SỰ CỐ MÁY CHỦ</b>
• <b>Server:</b> <code>$SITE_NAME</code>
• <b>Thời gian:</b> <code>$REPORT_TIME</code>
• <b>Tài nguyên:</b> RAM: <code>$RAM_INFO</code> | Disk: <code>$DISK_INFO</code> | CPU: <code>$CPU_LOAD</code>

⚡ <b>Chỉ số giám sát (24h):</b>
• 🌐 Tổng HTTP Requests: <b>$TOTAL_REQ</b> (2xx: $COUNT_2XX | 3xx: $COUNT_3XX)
• ⚠️ Lỗi máy chủ (5xx): <b>$COUNT_5XX</b>
• 🚫 Bị chặn (403): <b>$COUNT_403</b>
• 🔍 Quét/Dò file (404): <b>$COUNT_404</b>
• 🚨 SSH đăng nhập thất bại: <b>$COUNT_SSH_FAIL</b>
• 🛡️ Fail2ban chặn IP: <b>$COUNT_BANNED</b>"

# Định dạng chi tiết các mục phân tích
FORMATTED_PATHS=""
if [ -n "$TOP_PATHS" ]; then
    FORMATTED_PATHS=$(echo "$TOP_PATHS" | awk '{printf "• <code>%s</code>: <b>%s</b> lần\n", $2, $1}')
else
    FORMATTED_PATHS="• <i>Không phát hiện đường dẫn dò quét bất thường</i>"
fi

FORMATTED_IPS=""
if [ -n "$TOP_OFFENDING_IPS" ]; then
    FORMATTED_IPS=$(echo "$TOP_OFFENDING_IPS" | awk '{printf "• <code>%s</code>: <b>%s</b> lỗi\n", $2, $1}')
else
    FORMATTED_IPS="• <i>Không phát hiện IP spam lỗi bất thường</i>"
fi

FORMATTED_SSH_ATTACKERS=""
if [ -n "$TOP_SSH_ATTACKERS" ]; then
    FORMATTED_SSH_ATTACKERS=$(echo "$TOP_SSH_ATTACKERS" | awk '{printf "  ↳ <code>%s</code>: <b>%s</b> lần\n", $2, $1}')
fi

# Tin nhắn chi tiết
DETAILED_MESSAGE="📋 <b>CHI TIẾT PHÂN TÍCH AN NINH & HỆ THỐNG</b>
• <b>Server:</b> <code>$SITE_NAME</code>

🌐 <b>Top đường dẫn bị quét nhiều nhất (403/404):</b>
$FORMATTED_PATHS

🎯 <b>Top IP nghi vấn (Gây nhiều lỗi nhất):</b>
$FORMATTED_IPS

🔐 <b>Hoạt động đăng nhập SSH:</b>
• Thất bại (Brute-force): <b>$COUNT_SSH_FAIL</b> lần
${FORMATTED_SSH_ATTACKERS:-"  ↳ <i>Không có IP đáng ngờ</i>"}
• Thành công: <b>$COUNT_SSH_ACCEPTED</b> lần
${RECENT_SSH_LOGINS:-"• <i>Chưa có đăng nhập SSH mới</i>"}

🛡️ <b>Hoạt động Fail2ban:</b>
• Tổng số IP đã khóa: <b>$COUNT_BANNED</b>
${RECENT_BANS:-"• <i>Không có IP mới bị khóa</i>"}"

# ------------------------ 7. GỬI BÁO CÁO QUA TELEGRAM --------------------------
log_msg "📤 Đang gửi báo cáo về Telegram..."

if [ "$CHART_SUCCESS" -eq 1 ]; then
    # Gửi ảnh biểu đồ kèm tóm tắt
    PHOTO_RES=$(curl -s -X POST "$TELEGRAM_API/bot$BOT_TOKEN/sendPhoto" \
        -F "chat_id=$CHAT_ID" \
        -F "photo=@$CHART_FILE" \
        -F "caption=$SUMMARY_CAPTION" \
        -F "parse_mode=HTML")

    if echo "$PHOTO_RES" | grep -q '"ok":true'; then
        log_msg "✅ Gửi biểu đồ thành công!"
    else
        log_msg "❌ Lỗi gửi ảnh Telegram: $PHOTO_RES"
        # Dự phòng: gửi caption dạng tin nhắn thường nếu gửi ảnh lỗi
        curl -s -X POST "$TELEGRAM_API/bot$BOT_TOKEN/sendMessage" \
            -d "chat_id=$CHAT_ID" \
            -d "text=$SUMMARY_CAPTION" \
            -d "parse_mode=HTML" >> "$REPORT_LOG" 2>&1
    fi
else
    # Gửi tin nhắn tóm tắt text nếu không có biểu đồ
    curl -s -X POST "$TELEGRAM_API/bot$BOT_TOKEN/sendMessage" \
        -d "chat_id=$CHAT_ID" \
        -d "text=$SUMMARY_CAPTION" \
        -d "parse_mode=HTML" >> "$REPORT_LOG" 2>&1
fi

# Gửi tin nhắn phân tích chi tiết (Top scan paths, Top IPs, SSH log)
MSG_RES=$(curl -s -X POST "$TELEGRAM_API/bot$BOT_TOKEN/sendMessage" \
    -d "chat_id=$CHAT_ID" \
    -d "text=$DETAILED_MESSAGE" \
    -d "parse_mode=HTML")

if echo "$MSG_RES" | grep -q '"ok":true'; then
    log_msg "✅ Gửi chi tiết báo cáo thành công!"
else
    log_msg "❌ Lỗi gửi chi tiết Telegram: $MSG_RES"
fi

log_msg "🎉 Hoàn tất chu trình báo cáo an ninh cho $SITE_NAME!"
exit 0
