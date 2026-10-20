#!/usr/bin/env bash

# ==============================================================================
# Telegram Server Security & Error Log Reporter with QuickChart
# ==============================================================================
# Script tự động phân tích log hệ thống (Nginx, SSH, Fail2ban), tài nguyên
# máy chủ, vẽ biểu đồ qua QuickChart API và gửi báo cáo an ninh về Telegram.
# ==============================================================================

# -------------------------- 1. ĐỌC CẤU HÌNH NGOÀI -----------------------------
# Tự động nạp file cấu hình nếu tồn tại (vd: backup.env hoặc security-report.conf)
CONFIG_FILE="${CONFIG_FILE:-""}"
if [ -z "$CONFIG_FILE" ]; then
    for cfg in "/root/backup.env" "/root/.config/nhato/backup.env" "$(dirname "$0")/backup.env" "$(dirname "$0")/security-report.conf"; do
        if [ -r "$cfg" ]; then
            CONFIG_FILE="$cfg"
            break
        fi
    done
fi
if [ -n "$CONFIG_FILE" ] && [ -r "$CONFIG_FILE" ]; then
    # shellcheck disable=SC1090
    source "$CONFIG_FILE"
fi

# -------------------------- 2. CẤU HÌNH CƠ BẢN ---------------------------------
# 1. Telegram Bot Token & Chat ID
BOT_TOKEN="${BOT_TOKEN:-""}"
CHAT_ID="${CHAT_ID:-""}"

# Telegram API endpoint (Đổi sang Cloudflare Worker proxy nếu nhà mạng chặn Telegram)
# Mặc định: https://api.telegram.org (hoặc kế thừa TELEGRAM_API_BASE từ backup.env)
TELEGRAM_API="${TELEGRAM_API:-${TELEGRAM_API_BASE:-"https://api.telegram.org"}}"

# 2. Tên máy chủ / Website nhận diện
SITE_NAME="${SITE_NAME:-"$(hostname)"}"

# 3. Đường dẫn các file log
NGINX_ACCESS_LOG="${NGINX_ACCESS_LOG:-"/var/log/nginx/access.log"}"
NGINX_ERROR_LOG="${NGINX_ERROR_LOG:-"/var/log/nginx/error.log"}"
AUTH_LOG="${AUTH_LOG:-""}"          # Để trống sẽ tự động phát hiện (/var/log/auth.log, /var/log/secure, hoặc journalctl)
FAIL2BAN_LOG="${FAIL2BAN_LOG:-"/var/log/fail2ban.log"}"

# File ghi log hoạt động của script
REPORT_LOG="${REPORT_LOG:-"/root/security_report.log"}"
LOG_DIR=$(dirname "$REPORT_LOG")
if [ ! -d "$LOG_DIR" ] || [ ! -w "$LOG_DIR" ]; then
    mkdir -p "$LOG_DIR" 2>/dev/null || REPORT_LOG="/tmp/security_report.log"
fi

# Chế độ chạy
DRY_RUN=0
QUIET=0

# -------------------------- 3. XỬ LÝ THAM SỐ DÒNG LỆNH -------------------------
print_help() {
    cat <<EOF
Cách dùng: $0 [TÙY CHỌN] [SITE_NAME] [NGINX_ACCESS_LOG] [NGINX_ERROR_LOG]

TÙY CHỌN:
  --test, --dry-run   Chạy phân tích và in kết quả ra terminal, KHÔNG gửi tới Telegram
  --quiet, -q         Chạy im lặng, chỉ ghi log file (thích hợp cho Cronjob)
  --help, -h          Hiển thị hướng dẫn này

VÍ DỤ:
  $0 --test
  $0 "My Site" /var/log/nginx/site.access.log
  $0 --dry-run "My Site" /var/log/nginx/access.log /var/log/nginx/error.log
EOF
    exit 0
}

POSITIONAL_ARGS=()
while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run|--test)
            DRY_RUN=1
            shift
            ;;
        --quiet|-q)
            QUIET=1
            shift
            ;;
        --help|-h)
            print_help
            ;;
        -*)
            echo "⚠️ Tùy chọn không nhận diện: $1"
            print_help
            ;;
        *)
            POSITIONAL_ARGS+=("$1")
            shift
            ;;
    esac
done

[ "${#POSITIONAL_ARGS[@]}" -ge 1 ] && SITE_NAME="${POSITIONAL_ARGS[0]}"
[ "${#POSITIONAL_ARGS[@]}" -ge 2 ] && NGINX_ACCESS_LOG="${POSITIONAL_ARGS[1]}"
[ "${#POSITIONAL_ARGS[@]}" -ge 3 ] && NGINX_ERROR_LOG="${POSITIONAL_ARGS[2]}"

# -------------------------- 4. HÀM BỔ TRỢ & BẢO MẬT --------------------------
TEMP_DIR="/tmp"
CHART_FILE="${TEMP_DIR}/sec_chart_$$.png"
TEMP_ACCESS="${TEMP_DIR}/sec_access_$$.tmp"
TEMP_SSH="${TEMP_DIR}/sec_ssh_$$.tmp"

cleanup() {
    rm -f "$CHART_FILE" "$TEMP_ACCESS" "$TEMP_SSH"
}
trap cleanup EXIT

log_msg() {
    local timestamp
    timestamp=$(date +"%Y-%m-%d %H:%M:%S")
    if [ "$QUIET" -eq 0 ]; then
        echo "[$timestamp] $1" | tee -a "$REPORT_LOG"
    else
        echo "[$timestamp] $1" >> "$REPORT_LOG"
    fi
}

escape_html() {
    printf '%s' "$1" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g; s/"/\&quot;/g'
}

# Kiểm tra cấu hình bắt buộc (bỏ qua nếu chạy dry-run)
if [ "$DRY_RUN" -eq 0 ]; then
    if [ -z "$BOT_TOKEN" ] || [ -z "$CHAT_ID" ]; then
        echo "❌ Lỗi: BOT_TOKEN hoặc CHAT_ID chưa được thiết lập!"
        echo "Cách dùng:"
        echo "  1. Mở file script và điền: BOT_TOKEN=\"...\" CHAT_ID=\"...\""
        echo "  2. Hoặc tạo file backup.env trong cùng thư mục / /root/backup.env"
        echo "  3. Hoặc chạy qua biến môi trường: BOT_TOKEN=\"...\" CHAT_ID=\"...\" $0 [SITE_NAME] [NGINX_ACCESS_LOG]"
        exit 1
    fi
fi

log_msg "🔍 Bắt đầu phân tích an ninh cho máy chủ: $SITE_NAME"

# -------------------------- 5. TỰ ĐỘNG TÌM FILE LOG ---------------------------
# Nếu file Nginx access log không tồn tại theo đường dẫn mặc định, thử tìm theo SITE_NAME
if [ ! -f "$NGINX_ACCESS_LOG" ]; then
    if [ -f "/var/log/nginx/${SITE_NAME}.access.log" ]; then
        NGINX_ACCESS_LOG="/var/log/nginx/${SITE_NAME}.access.log"
    elif [ -f "/var/log/nginx/${SITE_NAME}_access.log" ]; then
        NGINX_ACCESS_LOG="/var/log/nginx/${SITE_NAME}_access.log"
    fi
fi

if [ ! -f "$NGINX_ERROR_LOG" ]; then
    if [ -f "/var/log/nginx/${SITE_NAME}.error.log" ]; then
        NGINX_ERROR_LOG="/var/log/nginx/${SITE_NAME}.error.log"
    elif [ -f "/var/log/nginx/${SITE_NAME}_error.log" ]; then
        NGINX_ERROR_LOG="/var/log/nginx/${SITE_NAME}_error.log"
    fi
fi

# Tự động phát hiện log SSH (Ubuntu/Debian vs CentOS/RHEL vs Systemd Journal)
SSH_MODE="file"
if [ -z "$AUTH_LOG" ]; then
    if [ -f "/var/log/auth.log" ]; then
        AUTH_LOG="/var/log/auth.log"
    elif [ -f "/var/log/secure" ]; then
        AUTH_LOG="/var/log/secure"
    elif command -v journalctl >/dev/null 2>&1; then
        SSH_MODE="journal"
    fi
fi

# -------------------------- 6. TÀI NGUYÊN MÁY CHỦ -----------------------------
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

# -------------------------- 7. PHÂN TÍCH NGINX ACCESS LOG ----------------------
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
    # TỐI ƯU HIỆU NĂNG: Lọc một lần duy nhất qua tail và lưu vào file tạm trong /tmp
    # Giảm 90% tải đĩa và chạy trong chớp mắt ngay cả khi access.log có kích thước hàng GB
    tail -n 100000 "$NGINX_ACCESS_LOG" 2>/dev/null | grep "$TODAY_NGINX" > "$TEMP_ACCESS" 2>/dev/null

    # Nếu hôm nay có ít hơn 50 dòng (ví dụ vừa sang ngày mới), lấy 25.000 dòng gần nhất
    if [ "$(wc -l < "$TEMP_ACCESS" 2>/dev/null || echo 0)" -lt 50 ]; then
        tail -n 25000 "$NGINX_ACCESS_LOG" > "$TEMP_ACCESS" 2>/dev/null
    fi

    # Thống kê mã trạng thái HTTP từ file tạm
    STATUS_COUNTS=$(grep -oE '" [1-5][0-9]{2} ' "$TEMP_ACCESS" 2>/dev/null | tr -d '" ' | sort | uniq -c)

    if [ -n "$STATUS_COUNTS" ]; then
        COUNT_2XX=$(echo "$STATUS_COUNTS" | awk '$2 ~ /^2/ {sum += $1} END {print sum+0}')
        COUNT_3XX=$(echo "$STATUS_COUNTS" | awk '$2 ~ /^3/ {sum += $1} END {print sum+0}')
        COUNT_403=$(echo "$STATUS_COUNTS" | awk '$2 == "403" {sum += $1} END {print sum+0}')
        COUNT_404=$(echo "$STATUS_COUNTS" | awk '$2 == "404" {sum += $1} END {print sum+0}')
        COUNT_5XX=$(echo "$STATUS_COUNTS" | awk '$2 ~ /^5/ {sum += $1} END {print sum+0}')
        TOTAL_REQ=$((COUNT_2XX + COUNT_3XX + COUNT_403 + COUNT_404 + COUNT_5XX))
    fi

    # Top 5 đường dẫn bị lỗi 403 / 404 (Tương thích cả Nginx combined và WordOps/custom format)
    TOP_PATHS=$(grep -E '" (403|404) ' "$TEMP_ACCESS" 2>/dev/null | awk -F'"' '{print $2}' | awk '{print $2}' | grep -v '^$' | grep -v '^-$' | sort | uniq -c | sort -nr | head -n 5)

    # Top 5 IP gửi nhiều request lỗi nhất (4xx & 5xx)
    TOP_OFFENDING_IPS=$(grep -E '" [45][0-9]{2} ' "$TEMP_ACCESS" 2>/dev/null | awk '{print $1}' | sort | uniq -c | sort -nr | head -n 5)
fi

# -------------------------- 8. PHÂN TÍCH NGINX ERROR LOG -----------------------
CRITICAL_ERRORS=""
if [ -f "$NGINX_ERROR_LOG" ]; then
    TODAY_ERR=$(date +"%Y/%m/%d")
    # Lọc các lỗi nghiêm trọng: PHP-FPM sập, Upstream timeout (504), Connection refused (502), Rate limit
    CRITICAL_ERRORS=$(tail -n 3000 "$NGINX_ERROR_LOG" 2>/dev/null | grep "$TODAY_ERR" | grep -iE "(upstream timed out|Connection refused|FastCGI sent in stderr|limiting requests|directory index of .* is forbidden)" | tail -n 3)
fi

# -------------------------- 9. PHÂN TÍCH SSH SECURITY --------------------------
TODAY_SYSLOG=$(date +"%b %e")
COUNT_SSH_FAIL=0
COUNT_SSH_ACCEPTED=0
TOP_SSH_ATTACKERS=""
RECENT_SSH_LOGINS=""

if [ "$SSH_MODE" = "file" ] && [ -n "$AUTH_LOG" ] && [ -f "$AUTH_LOG" ]; then
    tail -n 30000 "$AUTH_LOG" 2>/dev/null | grep "$TODAY_SYSLOG" > "$TEMP_SSH" 2>/dev/null
    if [ "$(wc -l < "$TEMP_SSH" 2>/dev/null || echo 0)" -lt 10 ]; then
        tail -n 5000 "$AUTH_LOG" > "$TEMP_SSH" 2>/dev/null
    fi
elif [ "$SSH_MODE" = "journal" ] || command -v journalctl >/dev/null 2>&1; then
    # Hỗ trợ Ubuntu 24.04+ / systemd-journald
    journalctl -u ssh --since today --no-pager 2>/dev/null > "$TEMP_SSH"
    if [ ! -s "$TEMP_SSH" ]; then
        journalctl -u ssh -n 5000 --no-pager 2>/dev/null > "$TEMP_SSH"
    fi
fi

if [ -s "$TEMP_SSH" ]; then
    # Số lần SSH thất bại (Brute force)
    COUNT_SSH_FAIL=$(grep -E -c "(Failed password|authentication failure|Failed publickey)" "$TEMP_SSH" 2>/dev/null || echo 0)

    # Top IP brute-force SSH nhiều nhất
    TOP_SSH_ATTACKERS=$(grep -E "(Failed password|authentication failure)" "$TEMP_SSH" 2>/dev/null | grep -oE '[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}' | sort | uniq -c | sort -nr | head -n 3)

    # Đăng nhập SSH thành công
    SSH_ACCEPTED_LINES=$(grep -E "Accepted (password|publickey)" "$TEMP_SSH" 2>/dev/null)
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

# -------------------------- 10. PHÂN TÍCH FAIL2BAN ----------------------------
COUNT_BANNED=0
RECENT_BANS=""
TODAY_ISO=$(date +"%Y-%m-%d")

if [ -f "$FAIL2BAN_LOG" ]; then
    F2B_DATA=$(tail -n 5000 "$FAIL2BAN_LOG" 2>/dev/null | grep "$TODAY_ISO")
    if [ -z "$F2B_DATA" ]; then
        F2B_DATA=$(tail -n 1500 "$FAIL2BAN_LOG" 2>/dev/null)
    fi

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

# -------------------------- 11. KHỞI TẠO BIỂU ĐỒ QUICKCHART -------------------
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
        "text": "BÁO CÁO BẢO MẬT VÀ LỖI HỆ THỐNG - $SITE_NAME",
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
curl -s --connect-timeout 8 --max-time 15 --compressed -X POST "https://quickchart.io/chart" \
    -H "Content-Type: application/json" \
    -d "$CHART_PAYLOAD" \
    -o "$CHART_FILE" 2>> "$REPORT_LOG"

if [ -s "$CHART_FILE" ]; then
    CHART_SUCCESS=1
    log_msg "✅ Tạo biểu đồ thành công (${CHART_FILE})"
else
    log_msg "⚠️ Không thể kết nối tới QuickChart, chuyển sang chế độ báo cáo văn bản thuần."
fi

# -------------------------- 12. SOẠN TIN NHẮN BÁO CÁO -------------------------
# Caption tóm tắt cho ảnh biểu đồ (< 1000 ký tự)
# Lưu ý: Không dùng ký tự dấu chấm phẩy ; trong caption gửi qua curl -F
SUMMARY_CAPTION="📊 <b>BÁO CÁO AN NINH VÀ SỰ CỐ MÁY CHỦ</b>
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
    FORMATTED_PATHS=$(echo "$TOP_PATHS" | while read -r count path; do
        safe_path=$(escape_html "$path")
        printf '• <code>%s</code>: <b>%s</b> lần\n' "$safe_path" "$count"
    done)
else
    FORMATTED_PATHS="• <i>Không phát hiện đường dẫn dò quét bất thường</i>"
fi

FORMATTED_IPS=""
if [ -n "$TOP_OFFENDING_IPS" ]; then
    FORMATTED_IPS=$(echo "$TOP_OFFENDING_IPS" | while read -r count ip; do
        safe_ip=$(escape_html "$ip")
        printf '• <code>%s</code>: <b>%s</b> lỗi\n' "$safe_ip" "$count"
    done)
else
    FORMATTED_IPS="• <i>Không phát hiện IP spam lỗi bất thường</i>"
fi

FORMATTED_ERRORS=""
if [ -n "$CRITICAL_ERRORS" ]; then
    FORMATTED_ERRORS=$(echo "$CRITICAL_ERRORS" | while read -r err_line; do
        safe_err=$(escape_html "$err_line")
        printf '• <code>%s</code>\n' "$safe_err"
    done)
fi

FORMATTED_SSH_ATTACKERS=""
if [ -n "$TOP_SSH_ATTACKERS" ]; then
    FORMATTED_SSH_ATTACKERS=$(echo "$TOP_SSH_ATTACKERS" | while read -r count ip; do
        safe_ip=$(escape_html "$ip")
        printf '  ↳ <code>%s</code>: <b>%s</b> lần\n' "$safe_ip" "$count"
    done)
fi

# Tin nhắn chi tiết
DETAILED_MESSAGE="📋 <b>CHI TIẾT PHÂN TÍCH AN NINH VÀ HỆ THỐNG</b>
• <b>Server:</b> <code>$SITE_NAME</code>

🌐 <b>Top đường dẫn bị quét nhiều nhất (403/404):</b>
$FORMATTED_PATHS

🎯 <b>Top IP nghi vấn (Gây nhiều lỗi nhất):</b>
$FORMATTED_IPS"

if [ -n "$FORMATTED_ERRORS" ]; then
    DETAILED_MESSAGE="${DETAILED_MESSAGE}

⚠️ <b>Lỗi Web Server (Nginx Error Log):</b>
$FORMATTED_ERRORS"
fi

DETAILED_MESSAGE="${DETAILED_MESSAGE}

🔐 <b>Hoạt động đăng nhập SSH:</b>
• Thất bại (Brute-force): <b>$COUNT_SSH_FAIL</b> lần
${FORMATTED_SSH_ATTACKERS:-"  ↳ <i>Không có IP đáng ngờ</i>"}
• Thành công: <b>$COUNT_SSH_ACCEPTED</b> lần
${RECENT_SSH_LOGINS:-"• <i>Chưa có đăng nhập SSH mới</i>"}

🛡️ <b>Hoạt động Fail2ban:</b>
• Tổng số IP đã khóa: <b>$COUNT_BANNED</b>
${RECENT_BANS:-"• <i>Không có IP mới bị khóa</i>"}"

# -------------------------- 13. DRY-RUN HOẶC GỬI TELEGRAM ---------------------
if [ "$DRY_RUN" -eq 1 ]; then
    echo -e "\n==================== [CHẾ ĐỘ KIỂM THỬ: DRY-RUN] ===================="
    echo "--- [1. TÓM TẮT BÁO CÁO (CAPTION)] ---"
    echo -e "$SUMMARY_CAPTION" | sed 's/<[^>]*>//g'
    echo -e "\n--- [2. CHI TIẾT PHÂN TÍCH] ---"
    echo -e "$DETAILED_MESSAGE" | sed 's/<[^>]*>//g'
    if [ "$CHART_SUCCESS" -eq 1 ]; then
        echo -e "\n📊 File biểu đồ tạm đã tạo tại: $CHART_FILE"
    fi
    echo -e "===================================================================="
    log_msg "✅ Hoàn tất kiểm thử thành công (Không gửi tới Telegram)."
    exit 0
fi

log_msg "📤 Đang gửi báo cáo về Telegram..."

if [ "$CHART_SUCCESS" -eq 1 ]; then
    # Gửi ảnh biểu đồ kèm tóm tắt
    PHOTO_RES=$(curl -s --connect-timeout 10 --max-time 25 -X POST "$TELEGRAM_API/bot$BOT_TOKEN/sendPhoto" \
        -F "chat_id=$CHAT_ID" \
        -F "photo=@$CHART_FILE" \
        -F "caption=$SUMMARY_CAPTION" \
        -F "parse_mode=HTML")

    if echo "$PHOTO_RES" | grep -q '"ok":true'; then
        log_msg "✅ Gửi biểu đồ thành công!"
    else
        log_msg "❌ Lỗi gửi ảnh Telegram: $PHOTO_RES"
        # Dự phòng: gửi caption dạng tin nhắn thường nếu gửi ảnh lỗi
        curl -s --connect-timeout 10 --max-time 25 -X POST "$TELEGRAM_API/bot$BOT_TOKEN/sendMessage" \
            --data-urlencode "chat_id=$CHAT_ID" \
            --data-urlencode "text=$SUMMARY_CAPTION" \
            --data-urlencode "parse_mode=HTML" >> "$REPORT_LOG" 2>&1
    fi
else
    # Gửi tin nhắn tóm tắt text nếu không có biểu đồ
    curl -s --connect-timeout 10 --max-time 25 -X POST "$TELEGRAM_API/bot$BOT_TOKEN/sendMessage" \
        --data-urlencode "chat_id=$CHAT_ID" \
        --data-urlencode "text=$SUMMARY_CAPTION" \
        --data-urlencode "parse_mode=HTML" >> "$REPORT_LOG" 2>&1
fi

# Gửi tin nhắn phân tích chi tiết (Top scan paths, Top IPs, SSH log)
MSG_RES=$(curl -s --connect-timeout 10 --max-time 25 -X POST "$TELEGRAM_API/bot$BOT_TOKEN/sendMessage" \
    --data-urlencode "chat_id=$CHAT_ID" \
    --data-urlencode "text=$DETAILED_MESSAGE" \
    --data-urlencode "parse_mode=HTML")

if echo "$MSG_RES" | grep -q '"ok":true'; then
    log_msg "✅ Gửi chi tiết báo cáo thành công!"
else
    log_msg "❌ Lỗi gửi chi tiết Telegram: $MSG_RES"
fi

log_msg "🎉 Hoàn tất chu trình báo cáo an ninh cho $SITE_NAME!"
exit 0
