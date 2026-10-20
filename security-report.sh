#!/usr/bin/env bash

# ==============================================================================
# Telegram Server Security & Error Log Reporter with QuickChart
# ==============================================================================
# Script tự động phân tích log hệ thống (Nginx, SSH, Fail2ban), tài nguyên
# máy chủ, vẽ biểu đồ qua QuickChart API và gửi báo cáo an ninh về Telegram.
# Hỗ trợ báo cáo theo chu kỳ (1 ngày, 7 ngày, 30 ngày) và tự động dọn log cũ (>60 ngày).
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

# 3. Chu kỳ báo cáo: 1 (hàng ngày), 7 (hàng tuần), 30 (hàng tháng)
PERIOD="${PERIOD:-1}"

# 4. Tự động dọn dẹp log và file backup cũ để tránh đầy ổ cứng (mặc định: 60 ngày = 2 tháng)
AUTO_CLEAN="${AUTO_CLEAN:-1}"
CLEAN_DAYS="${CLEAN_DAYS:-60}"
BACKUP_DIR="${BACKUP_DIR:-"/root/backups"}"

# 5. Đường dẫn các file log
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
ONLY_CLEAN=0

# -------------------------- 3. XỬ LÝ THAM SỐ DÒNG LỆNH -------------------------
print_help() {
    cat <<EOF
Cách dùng: $0 [TÙY CHỌN] [SITE_NAME] [NGINX_ACCESS_LOG] [NGINX_ERROR_LOG]

TÙY CHỌN CHU KỲ BÁO CÁO:
  -p, --period <days>   Chọn chu kỳ: 1 (ngày), 7 (tuần) hoặc 30 (tháng) [Mặc định: 1]
  --daily               Báo cáo 1 ngày (24 giờ qua) [Tương đương -p 1]
  --weekly              Báo cáo 7 ngày (1 tuần qua) [Tương đương -p 7]
  --monthly             Báo cáo 30 ngày (1 tháng qua) [Tương đương -p 30]

TÙY CHỌN BẢO TRÌ & DỌN DẸP LOG:
  --clean               Chỉ chạy dọn dẹp log/backup cũ hơn $CLEAN_DAYS ngày rồi thoát
  --clean-days <days>   Thiết lập số ngày lưu log tối đa [Mặc định: 60 ngày]
  --no-clean            Tắt tính năng tự động dọn log cũ

TÙY CHỌN KHÁC:
  --test, --dry-run     Chạy phân tích và in kết quả ra terminal, KHÔNG gửi tới Telegram
  --quiet, -q           Chạy im lặng, chỉ ghi log file (thích hợp cho Cronjob)
  --help, -h            Hiển thị hướng dẫn này

VÍ DỤ CRONJOB:
  # Báo cáo hàng ngày lúc 08:00 AM:
  0 8 * * * $0 >> $REPORT_LOG 2>&1

  # Báo cáo 7 ngày vào thứ Hai lúc 08:00 AM:
  0 8 * * 1 $0 --weekly >> $REPORT_LOG 2>&1

  # Báo cáo 30 ngày vào ngày 1 hàng tháng lúc 08:00 AM:
  0 8 1 * * $0 --monthly >> $REPORT_LOG 2>&1
EOF
    exit 0
}

POSITIONAL_ARGS=()
while [[ $# -gt 0 ]]; do
    case "$1" in
        --daily)
            PERIOD=1
            shift
            ;;
        --weekly)
            PERIOD=7
            shift
            ;;
        --monthly)
            PERIOD=30
            shift
            ;;
        -p|--period)
            PERIOD="$2"
            shift 2
            ;;
        --clean)
            ONLY_CLEAN=1
            shift
            ;;
        --no-clean)
            AUTO_CLEAN=0
            shift
            ;;
        --clean-days)
            CLEAN_DAYS="$2"
            shift 2
            ;;
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

# Đảm bảo PERIOD hợp lệ
if ! [[ "$PERIOD" =~ ^[0-9]+$ ]] || [ "$PERIOD" -le 0 ]; then
    PERIOD=1
fi

# -------------------------- 4. HÀM BỔ TRỢ & BẢO MẬT --------------------------
TEMP_DIR="/tmp"
CHART_FILE="${TEMP_DIR}/sec_chart_$$.png"
TEMP_ACCESS="${TEMP_DIR}/sec_access_$$.tmp"
TEMP_SSH="${TEMP_DIR}/sec_ssh_$$.tmp"

cleanup() {
    rm -f "$CHART_FILE" "$TEMP_ACCESS" "$TEMP_SSH"
}
trap cleanup EXIT INT TERM

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

# Hàm tính toán ngày quá khứ tương thích cả Linux (GNU date) và macOS (BSD date)
get_past_date() {
    local days="$1"
    local fmt="$2"
    local res
    res=$(date -d "$days days ago" +"$fmt" 2>/dev/null)
    if [ -n "$res" ]; then
        echo "$res"
    else
        date -v-"${days}"d +"$fmt" 2>/dev/null
    fi
}

# Tạo biểu thức regex cho chu kỳ ngày
build_date_regex() {
    local days="$1"
    local fmt="$2"
    local regex=""
    for ((i=0; i<days; i++)); do
        local d
        d=$(get_past_date "$i" "$fmt")
        if [ -n "$d" ]; then
            if [ -z "$regex" ]; then
                regex="$d"
            else
                regex="$regex|$d"
            fi
        fi
    done
    echo "($regex)"
}

# -------------------------- 5. TỰ ĐỘNG DỌN DẸP LOG CŨ (> 60 NGÀY) -------------
CLEANED_COUNT=0
clean_old_logs() {
    log_msg "🧹 Đang kiểm tra và dọn dẹp các file log/backup cũ hơn $CLEAN_DAYS ngày (2 tháng)..."
    local count=0

    # 1. Dọn các file log nén cũ của Nginx (*.gz, *.1, *.old)
    local nginx_dir
    nginx_dir="$(dirname "$NGINX_ACCESS_LOG")"
    if [ -d "$nginx_dir" ] && [ -w "$nginx_dir" ]; then
        local c1
        c1=$(find "$nginx_dir" -type f \( -name "*.gz" -o -name "*.1" -o -name "*.old" \) -mtime +"$CLEAN_DAYS" -print -delete 2>/dev/null | wc -l | tr -d ' ')
        count=$((count + c1))
    fi

    # 2. Dọn các file log xoay vòng trong /var/log (*.gz, *.old)
    if [ -d "/var/log" ] && [ -w "/var/log" ]; then
        local c2
        c2=$(find /var/log -maxdepth 2 -type f \( -name "*.gz" -o -name "*.old" \) -mtime +"$CLEAN_DAYS" -print -delete 2>/dev/null | wc -l | tr -d ' ')
        count=$((count + c2))
    fi

    # 3. Dọn file backup cũ trong BACKUP_DIR nếu tồn tại
    if [ -d "$BACKUP_DIR" ] && [ -w "$BACKUP_DIR" ]; then
        local c3
        c3=$(find "$BACKUP_DIR" -type f \( -name "*.tar.gz" -o -name "*.sql" \) -mtime +"$CLEAN_DAYS" -print -delete 2>/dev/null | wc -l | tr -d ' ')
        count=$((count + c3))
    fi

    # 4. Thu gọn file log của script nếu lớn hơn 10MB
    if [ -f "$REPORT_LOG" ]; then
        local size_kb
        size_kb=$(du -k "$REPORT_LOG" 2>/dev/null | awk '{print $1}')
        if [ "${size_kb:-0}" -gt 10240 ]; then
            tail -n 5000 "$REPORT_LOG" > "${REPORT_LOG}.tmp" && mv "${REPORT_LOG}.tmp" "$REPORT_LOG"
            log_msg "🧹 Đã thu gọn file $REPORT_LOG (giữ 5.000 dòng gần nhất)."
        fi
    fi

    # 5. Dọn dẹp systemd journal nếu có
    if command -v journalctl >/dev/null 2>&1; then
        journalctl --vacuum-time="${CLEAN_DAYS}d" >/dev/null 2>&1 || true
    fi

    CLEANED_COUNT="$count"
    if [ "$count" -gt 0 ]; then
        log_msg "✅ Đã dọn dẹp thành công $count file log và backup cũ hơn $CLEAN_DAYS ngày."
    else
        log_msg "✔️ Hệ thống sạch sẽ, không có file log nào cũ hơn $CLEAN_DAYS ngày."
    fi
}

# Nếu chỉ chạy dọn dẹp log:
if [ "$ONLY_CLEAN" -eq 1 ]; then
    clean_old_logs
    exit 0
fi

# Chạy tự động dọn log nếu bật AUTO_CLEAN
if [ "$AUTO_CLEAN" -eq 1 ]; then
    clean_old_logs
fi

# -------------------------- 6. KIỂM TRA CẤU HÌNH BẮT BUỘC --------------------
if [ "$DRY_RUN" -eq 0 ]; then
    if [ -z "$BOT_TOKEN" ] || [ -z "$CHAT_ID" ]; then
        echo "❌ Lỗi: BOT_TOKEN hoặc CHAT_ID chưa được thiết lập!"
        echo "👉 Bạn hãy tạo file 'backup.env' hoặc 'security-report.conf' hoặc thiết lập biến môi trường."
        exit 1
    fi
fi

# Xác định nhãn chu kỳ báo cáo
if [ "$PERIOD" -eq 1 ]; then
    PERIOD_LABEL="1 NGÀY (24H)"
    PERIOD_TITLE_DESC="24h qua"
elif [ "$PERIOD" -eq 7 ]; then
    PERIOD_LABEL="7 NGÀY (1 TUẦN)"
    PERIOD_TITLE_DESC="7 ngày qua"
elif [ "$PERIOD" -eq 30 ]; then
    PERIOD_LABEL="30 NGÀY (1 THÁNG)"
    PERIOD_TITLE_DESC="30 ngày qua"
else
    PERIOD_LABEL="$PERIOD NGÀY"
    PERIOD_TITLE_DESC="$PERIOD ngày qua"
fi

log_msg "🔍 Bắt đầu phân tích an ninh cho máy chủ: $SITE_NAME (Chu kỳ: $PERIOD_LABEL)"

# -------------------------- 7. TỰ ĐỘNG TÌM FILE LOG ---------------------------
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

# -------------------------- 8. TÀI NGUYÊN MÁY CHỦ -----------------------------
REPORT_TIME=$(date +"%Y-%m-%d %H:%M:%S")

# Dung lượng ổ cứng Root
DISK_INFO=$(df -h / 2>/dev/null | awk 'NR==2 {print $5 " (" $3 "/" $2 ")"}')
DISK_INFO="${DISK_INFO:-"N/A"}"

# Dung lượng RAM
if command -v free >/dev/null 2>&1; then
    RAM_INFO=$(free -m 2>/dev/null | awk 'NR==2 {printf "%.0f%% (%dMB/%dMB)", ($3/$2)*100, $3, $2}')
else
    RAM_INFO="N/A"
fi

# CPU Load Average
CPU_LOAD=$(uptime 2>/dev/null | awk -F'load average:' '{print $2}' | sed 's/^ //')
CPU_LOAD="${CPU_LOAD:-"N/A"}"

# -------------------------- 9. PHÂN TÍCH NGINX ACCESS LOG ----------------------
TOTAL_REQ=0
COUNT_2XX=0
COUNT_3XX=0
COUNT_403=0
COUNT_404=0
COUNT_5XX=0
TOP_PATHS=""
TOP_OFFENDING_IPS=""

if [ -f "$NGINX_ACCESS_LOG" ]; then
    if [ "$PERIOD" -eq 1 ]; then
        TODAY_NGINX=$(date +"%d/%b/%Y")
        tail -n 100000 "$NGINX_ACCESS_LOG" 2>/dev/null | grep "$TODAY_NGINX" > "$TEMP_ACCESS" 2>/dev/null
        if [ "$(wc -l < "$TEMP_ACCESS" 2>/dev/null || echo 0)" -lt 50 ]; then
            tail -n 25000 "$NGINX_ACCESS_LOG" > "$TEMP_ACCESS" 2>/dev/null
        fi
    else
        # Xây dựng regex cho chu kỳ nhiều ngày (7 ngày hoặc 30 ngày)
        NGINX_DATE_REGEX=$(build_date_regex "$PERIOD" "%d/%b/%Y")
        log_msg "⏳ Đang tổng hợp log Nginx trong $PERIOD ngày qua..."
        {
            cat "$NGINX_ACCESS_LOG" 2>/dev/null
            [ -f "${NGINX_ACCESS_LOG}.1" ] && cat "${NGINX_ACCESS_LOG}.1" 2>/dev/null
            find "$(dirname "$NGINX_ACCESS_LOG")" -name "$(basename "$NGINX_ACCESS_LOG").*.gz" -mtime -"$((PERIOD + 2))" -exec gzip -dc {} + 2>/dev/null
        } | grep -E "$NGINX_DATE_REGEX" > "$TEMP_ACCESS" 2>/dev/null
    fi

    STATUS_COUNTS=$(grep -oE '" [1-5][0-9]{2} ' "$TEMP_ACCESS" 2>/dev/null | tr -d '" ' | sort | uniq -c)

    if [ -n "$STATUS_COUNTS" ]; then
        COUNT_2XX=$(echo "$STATUS_COUNTS" | awk '$2 ~ /^2/ {sum += $1} END {print sum+0}')
        COUNT_3XX=$(echo "$STATUS_COUNTS" | awk '$2 ~ /^3/ {sum += $1} END {print sum+0}')
        COUNT_403=$(echo "$STATUS_COUNTS" | awk '$2 == "403" {sum += $1} END {print sum+0}')
        COUNT_404=$(echo "$STATUS_COUNTS" | awk '$2 == "404" {sum += $1} END {print sum+0}')
        COUNT_5XX=$(echo "$STATUS_COUNTS" | awk '$2 ~ /^5/ {sum += $1} END {print sum+0}')
        TOTAL_REQ=$((COUNT_2XX + COUNT_3XX + COUNT_403 + COUNT_404 + COUNT_5XX))
    fi

    # Top 5 đường dẫn bị quét nhiều nhất
    TOP_PATHS=$(grep -E '" (403|404) ' "$TEMP_ACCESS" 2>/dev/null | awk -F'"' '{print $2}' | awk '{print $2}' | grep -v '^$' | grep -v '^-$' | sort | uniq -c | sort -nr | head -n 5)

    # Top 5 IP gây nhiều lỗi nhất
    TOP_OFFENDING_IPS=$(grep -E '" [45][0-9]{2} ' "$TEMP_ACCESS" 2>/dev/null | awk '{print $1}' | sort | uniq -c | sort -nr | head -n 5)
fi

# -------------------------- 10. PHÂN TÍCH NGINX ERROR LOG ----------------------
CRITICAL_ERRORS=""
if [ -f "$NGINX_ERROR_LOG" ]; then
    if [ "$PERIOD" -eq 1 ]; then
        ERR_DATE_REGEX=$(date +"%Y/%m/%d")
    else
        ERR_DATE_REGEX=$(build_date_regex "$PERIOD" "%Y/%m/%d")
    fi
    CRITICAL_ERRORS=$(tail -n 5000 "$NGINX_ERROR_LOG" 2>/dev/null | grep -E "$ERR_DATE_REGEX" | grep -iE "(upstream timed out|Connection refused|FastCGI sent in stderr|limiting requests|directory index of .* is forbidden)" | tail -n 3)
fi

# -------------------------- 11. PHÂN TÍCH SSH SECURITY -------------------------
COUNT_SSH_FAIL=0
COUNT_SSH_ACCEPTED=0
TOP_SSH_ATTACKERS=""
RECENT_SSH_LOGINS=""

if [ "$SSH_MODE" = "file" ] && [ -n "$AUTH_LOG" ] && [ -f "$AUTH_LOG" ]; then
    if [ "$PERIOD" -eq 1 ]; then
        TODAY_SYSLOG=$(date +"%b %e")
        tail -n 30000 "$AUTH_LOG" 2>/dev/null | grep "$TODAY_SYSLOG" > "$TEMP_SSH" 2>/dev/null
        if [ "$(wc -l < "$TEMP_SSH" 2>/dev/null || echo 0)" -lt 10 ]; then
            tail -n 5000 "$AUTH_LOG" > "$TEMP_SSH" 2>/dev/null
        fi
    else
        SYSLOG_DATE_REGEX=$(build_date_regex "$PERIOD" "%b %e")
        {
            cat "$AUTH_LOG" 2>/dev/null
            [ -f "${AUTH_LOG}.1" ] && cat "${AUTH_LOG}.1" 2>/dev/null
            find "$(dirname "$AUTH_LOG")" -name "$(basename "$AUTH_LOG").*.gz" -mtime -"$((PERIOD + 2))" -exec gzip -dc {} + 2>/dev/null
        } | grep -E "$SYSLOG_DATE_REGEX" > "$TEMP_SSH" 2>/dev/null
    fi
elif [ "$SSH_MODE" = "journal" ] || command -v journalctl >/dev/null 2>&1; then
    journalctl -u ssh --since "${PERIOD} days ago" --no-pager 2>/dev/null > "$TEMP_SSH"
    if [ ! -s "$TEMP_SSH" ]; then
        journalctl -u ssh -n 5000 --no-pager 2>/dev/null > "$TEMP_SSH"
    fi
fi

if [ -s "$TEMP_SSH" ]; then
    COUNT_SSH_FAIL=$(grep -E -c "(Failed password|authentication failure|Failed publickey)" "$TEMP_SSH" 2>/dev/null || echo 0)
    TOP_SSH_ATTACKERS=$(grep -E "(Failed password|authentication failure)" "$TEMP_SSH" 2>/dev/null | grep -oE '[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}' | sort | uniq -c | sort -nr | head -n 3)
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

# -------------------------- 12. PHÂN TÍCH FAIL2BAN ----------------------------
COUNT_BANNED=0
RECENT_BANS=""

if [ -f "$FAIL2BAN_LOG" ]; then
    if [ "$PERIOD" -eq 1 ]; then
        F2B_DATE_REGEX=$(date +"%Y-%m-%d")
    else
        F2B_DATE_REGEX=$(build_date_regex "$PERIOD" "%Y-%m-%d")
    fi

    F2B_DATA=$(tail -n 10000 "$FAIL2BAN_LOG" 2>/dev/null | grep -E "$F2B_DATE_REGEX")
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

# -------------------------- 13. KHỞI TẠO BIỂU ĐỒ QUICKCHART -------------------
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
        "text": "BÁO CÁO AN NINH ($PERIOD_LABEL) - $SITE_NAME",
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

# -------------------------- 14. SOẠN TIN NHẮN BÁO CÁO -------------------------
SUMMARY_CAPTION="📊 <b>BÁO CÁO AN NINH VÀ SỰ CỐ MÁY CHỦ ($PERIOD_LABEL)</b>
• <b>Server:</b> <code>$SITE_NAME</code>
• <b>Thời gian:</b> <code>$REPORT_TIME</code>
• <b>Tài nguyên:</b> RAM: <code>$RAM_INFO</code> | Disk: <code>$DISK_INFO</code> | CPU: <code>$CPU_LOAD</code>

⚡ <b>Chỉ số giám sát ($PERIOD_TITLE_DESC):</b>
• 🌐 Tổng HTTP Requests: <b>$TOTAL_REQ</b> (2xx: $COUNT_2XX | 3xx: $COUNT_3XX)
• ⚠️ Lỗi máy chủ (5xx): <b>$COUNT_5XX</b>
• 🚫 Bị chặn (403): <b>$COUNT_403</b>
• 🔍 Quét/Dò file (404): <b>$COUNT_404</b>
• 🚨 SSH đăng nhập thất bại: <b>$COUNT_SSH_FAIL</b>
• 🛡️ Fail2ban chặn IP: <b>$COUNT_BANNED</b>"

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
        safe_err=$(escape_html "$err_line" | cut -c 1-150)
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

DETAILED_MESSAGE="📋 <b>CHI TIẾT PHÂN TÍCH AN NINH VÀ HỆ THỐNG ($PERIOD_LABEL)</b>
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

if [ "$CLEANED_COUNT" -gt 0 ]; then
    DETAILED_MESSAGE="${DETAILED_MESSAGE}

🧹 <b>Bảo trì hệ thống:</b> Đã dọn dẹp $CLEANED_COUNT file log/backup cũ hơn $CLEAN_DAYS ngày."
fi

# -------------------------- 15. DRY-RUN HOẶC GỬI TELEGRAM ---------------------
if [ "$DRY_RUN" -eq 1 ]; then
    echo -e "\n==================== [CHẾ ĐỘ KIỂM THỬ: DRY-RUN ($PERIOD_LABEL)] ===================="
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
    PHOTO_RES=$(curl -s --connect-timeout 10 --max-time 25 -X POST "$TELEGRAM_API/bot$BOT_TOKEN/sendPhoto" \
        -F "chat_id=$CHAT_ID" \
        -F "photo=@$CHART_FILE" \
        -F "caption=$SUMMARY_CAPTION" \
        -F "parse_mode=HTML")

    if echo "$PHOTO_RES" | grep -q '"ok":true'; then
        log_msg "✅ Gửi biểu đồ thành công!"
    else
        log_msg "❌ Lỗi gửi ảnh Telegram: $PHOTO_RES"
        curl -s --connect-timeout 10 --max-time 25 -X POST "$TELEGRAM_API/bot$BOT_TOKEN/sendMessage" \
            --data-urlencode "chat_id=$CHAT_ID" \
            --data-urlencode "text=$SUMMARY_CAPTION" \
            --data-urlencode "parse_mode=HTML" >> "$REPORT_LOG" 2>&1
    fi
else
    curl -s --connect-timeout 10 --max-time 25 -X POST "$TELEGRAM_API/bot$BOT_TOKEN/sendMessage" \
        --data-urlencode "chat_id=$CHAT_ID" \
        --data-urlencode "text=$SUMMARY_CAPTION" \
        --data-urlencode "parse_mode=HTML" >> "$REPORT_LOG" 2>&1
fi

MSG_RES=$(curl -s --connect-timeout 10 --max-time 25 -X POST "$TELEGRAM_API/bot$BOT_TOKEN/sendMessage" \
    --data-urlencode "chat_id=$CHAT_ID" \
    --data-urlencode "text=$DETAILED_MESSAGE" \
    --data-urlencode "parse_mode=HTML")

if echo "$MSG_RES" | grep -q '"ok":true'; then
    log_msg "✅ Gửi chi tiết báo cáo thành công!"
else
    log_msg "❌ Lỗi gửi chi tiết Telegram: $MSG_RES"
fi

log_msg "🎉 Hoàn tất chu trình báo cáo an ninh ($PERIOD_LABEL) cho $SITE_NAME!"
exit 0
