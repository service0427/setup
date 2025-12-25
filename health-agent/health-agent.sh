#!/bin/bash
#===============================================================================
# 헬스체크 에이전트 (Health Check Agent)
# - 시스템 상태 수집 및 중앙 서버 전송
# - 1분마다 systemd timer로 실행
#
# 설치 위치: /opt/health-agent/
# 설정 파일: /opt/health-agent/config.env
#===============================================================================

set -e

# 설정 파일 로드
CONFIG_FILE="/opt/health-agent/config.env"
if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
fi

# 기본값 설정
HUB_URL="${HUB_URL:-http://localhost:3000/api/health}"
LOG_DIR="${LOG_DIR:-/var/log/health-agent}"
DATA_DIR="${DATA_DIR:-/opt/health-agent/data}"
ENABLE_PUSH="${ENABLE_PUSH:-false}"  # 서버 준비 전까지 false

# 디렉토리 생성
mkdir -p "$LOG_DIR" "$DATA_DIR"

#===============================================================================
# 시스템 정보 수집 함수들
#===============================================================================

get_basic_info() {
    HOSTNAME=$(hostname)
    INTERNAL_IP=$(ip -4 addr show | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | grep -v '127.0.0.1' | head -1)
    EXTERNAL_IP=$(curl -s --connect-timeout 5 https://api.ipify.org 2>/dev/null || echo "N/A")
    ANYDESK_ID=$(anydesk --get-id 2>/dev/null || echo "N/A")
    UPTIME_SECONDS=$(cat /proc/uptime | awk '{print int($1)}')
    UPTIME_HUMAN=$(uptime -p 2>/dev/null || echo "N/A")
    BOOT_TIME=$(who -b 2>/dev/null | awk '{print $3, $4}' || echo "N/A")
}

get_cpu_info() {
    # CPU 사용률 (1초 샘플링)
    CPU_USAGE=$(top -bn1 | grep "Cpu(s)" | awk '{print 100 - $8}' | cut -d'.' -f1)

    # 로드 평균
    LOAD_1=$(cat /proc/loadavg | awk '{print $1}')
    LOAD_5=$(cat /proc/loadavg | awk '{print $2}')
    LOAD_15=$(cat /proc/loadavg | awk '{print $3}')

    # CPU 코어 수
    CPU_CORES=$(nproc)

    # CPU 온도 (가능한 경우)
    if [ -f /sys/class/thermal/thermal_zone0/temp ]; then
        CPU_TEMP=$(($(cat /sys/class/thermal/thermal_zone0/temp) / 1000))
    else
        CPU_TEMP="N/A"
    fi
}

get_memory_info() {
    # 메모리 정보 (MB 단위) - LANG=C로 영문 출력 강제
    MEM_TOTAL=$(LANG=C free -m | awk '/^Mem:/{print $2}')
    MEM_USED=$(LANG=C free -m | awk '/^Mem:/{print $3}')
    MEM_FREE=$(LANG=C free -m | awk '/^Mem:/{print $4}')
    MEM_AVAILABLE=$(LANG=C free -m | awk '/^Mem:/{print $7}')
    MEM_USAGE_PCT=$((MEM_USED * 100 / MEM_TOTAL))

    # 스왑 정보
    SWAP_TOTAL=$(LANG=C free -m | awk '/^Swap:/{print $2}')
    SWAP_USED=$(LANG=C free -m | awk '/^Swap:/{print $3}')
    if [ "$SWAP_TOTAL" -gt 0 ]; then
        SWAP_USAGE_PCT=$((SWAP_USED * 100 / SWAP_TOTAL))
    else
        SWAP_USAGE_PCT=0
    fi
}

get_disk_info() {
    # 루트 파티션
    DISK_TOTAL=$(df -BG / | awk 'NR==2{print $2}' | tr -d 'G')
    DISK_USED=$(df -BG / | awk 'NR==2{print $3}' | tr -d 'G')
    DISK_FREE=$(df -BG / | awk 'NR==2{print $4}' | tr -d 'G')
    DISK_USAGE_PCT=$(df / | awk 'NR==2{print $5}' | tr -d '%')

    # 홈 파티션 (별도 마운트된 경우)
    HOME_USAGE_PCT=$(df /home 2>/dev/null | awk 'NR==2{print $5}' | tr -d '%' || echo "$DISK_USAGE_PCT")
}

get_network_info() {
    # 네트워크 인터페이스 상태
    DEFAULT_IFACE=$(ip route | grep default | awk '{print $5}' | head -1)
    IFACE_STATUS=$(cat /sys/class/net/${DEFAULT_IFACE}/operstate 2>/dev/null || echo "unknown")

    # 외부 연결 테스트
    if ping -c 1 -W 3 8.8.8.8 &>/dev/null; then
        INTERNET_STATUS="connected"
    else
        INTERNET_STATUS="disconnected"
    fi

    # DNS 테스트
    if nslookup google.com &>/dev/null; then
        DNS_STATUS="working"
    else
        DNS_STATUS="failed"
    fi

    # WireGuard VPN 상태
    WG_INTERFACES=$(ip link show type wireguard 2>/dev/null | grep -c "wg-" || echo "0")
    WG_NAMESPACES=$(ip netns list 2>/dev/null | grep -c "U22-\|vpn-" || echo "0")
}

get_process_info() {
    # vpn_coupang_v1 에이전트 상태
    AGENT_RUNNING=$(pgrep -f "index-vpn-multi.js" >/dev/null && echo "running" || echo "stopped")
    AGENT_PID=$(pgrep -f "index-vpn-multi.js" 2>/dev/null || echo "N/A")

    # Chrome/Chromium 프로세스 수
    CHROME_COUNT=$(pgrep -c chrome 2>/dev/null || echo "0")

    # Node.js 프로세스 수
    NODE_COUNT=$(pgrep -c node 2>/dev/null || echo "0")

    # 총 프로세스 수
    TOTAL_PROCESSES=$(ps aux | wc -l)
}

get_service_info() {
    # 주요 서비스 상태
    ANYDESK_STATUS=$(systemctl is-active anydesk 2>/dev/null || echo "unknown")
    SSH_STATUS=$(systemctl is-active ssh 2>/dev/null || echo "unknown")

    # 로그인 실패 횟수 (최근 1시간)
    LOGIN_FAILURES=$(journalctl --since "1 hour ago" 2>/dev/null | grep -c "Failed password" || echo "0")

    # SSH 연결 수
    SSH_CONNECTIONS=$(who | wc -l)
}

get_system_health() {
    # 재부팅 필요 여부
    if [ -f /var/run/reboot-required ]; then
        REBOOT_REQUIRED="yes"
    else
        REBOOT_REQUIRED="no"
    fi

    # 마지막 apt 업데이트
    if [ -f /var/lib/apt/periodic/update-success-stamp ]; then
        LAST_APT_UPDATE=$(stat -c %Y /var/lib/apt/periodic/update-success-stamp)
    else
        LAST_APT_UPDATE="N/A"
    fi

    # 좀비 프로세스 수
    ZOMBIE_COUNT=$(ps aux | awk '$8=="Z"' | wc -l)

    # OOM Killer 발생 횟수 (최근 24시간)
    OOM_COUNT=$(dmesg 2>/dev/null | grep -c "Out of memory" || echo "0")
}

#===============================================================================
# 데이터 수집 및 전송
#===============================================================================

collect_all_data() {
    TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    TIMESTAMP_LOCAL=$(date +"%Y-%m-%d %H:%M:%S")

    get_basic_info
    get_cpu_info
    get_memory_info
    get_disk_info
    get_network_info
    get_process_info
    get_service_info
    get_system_health
}

generate_json() {
    cat << EOF
{
  "timestamp": "$TIMESTAMP",
  "hostname": "$HOSTNAME",
  "basic": {
    "internal_ip": "$INTERNAL_IP",
    "external_ip": "$EXTERNAL_IP",
    "anydesk_id": "$ANYDESK_ID",
    "uptime_seconds": $UPTIME_SECONDS,
    "uptime_human": "$UPTIME_HUMAN",
    "boot_time": "$BOOT_TIME"
  },
  "cpu": {
    "usage_pct": $CPU_USAGE,
    "cores": $CPU_CORES,
    "load_1m": $LOAD_1,
    "load_5m": $LOAD_5,
    "load_15m": $LOAD_15,
    "temp_c": "$CPU_TEMP"
  },
  "memory": {
    "total_mb": $MEM_TOTAL,
    "used_mb": $MEM_USED,
    "free_mb": $MEM_FREE,
    "available_mb": $MEM_AVAILABLE,
    "usage_pct": $MEM_USAGE_PCT,
    "swap_total_mb": $SWAP_TOTAL,
    "swap_used_mb": $SWAP_USED,
    "swap_usage_pct": $SWAP_USAGE_PCT
  },
  "disk": {
    "total_gb": $DISK_TOTAL,
    "used_gb": $DISK_USED,
    "free_gb": $DISK_FREE,
    "usage_pct": $DISK_USAGE_PCT,
    "home_usage_pct": $HOME_USAGE_PCT
  },
  "network": {
    "interface": "$DEFAULT_IFACE",
    "status": "$IFACE_STATUS",
    "internet": "$INTERNET_STATUS",
    "dns": "$DNS_STATUS",
    "wg_interfaces": $WG_INTERFACES,
    "wg_namespaces": $WG_NAMESPACES
  },
  "processes": {
    "agent_status": "$AGENT_RUNNING",
    "agent_pid": "$AGENT_PID",
    "chrome_count": $CHROME_COUNT,
    "node_count": $NODE_COUNT,
    "total": $TOTAL_PROCESSES
  },
  "services": {
    "anydesk": "$ANYDESK_STATUS",
    "ssh": "$SSH_STATUS",
    "login_failures_1h": $LOGIN_FAILURES,
    "ssh_connections": $SSH_CONNECTIONS
  },
  "health": {
    "reboot_required": "$REBOOT_REQUIRED",
    "zombie_count": $ZOMBIE_COUNT,
    "oom_count": $OOM_COUNT
  }
}
EOF
}

save_local() {
    local json="$1"

    # 현재 상태 저장
    echo "$json" > "$DATA_DIR/current.json"

    # 히스토리 저장 (최근 1440개 = 24시간)
    echo "$json" >> "$DATA_DIR/history.jsonl"
    tail -n 1440 "$DATA_DIR/history.jsonl" > "$DATA_DIR/history.jsonl.tmp"
    mv "$DATA_DIR/history.jsonl.tmp" "$DATA_DIR/history.jsonl"

    # 로그
    echo "[$TIMESTAMP_LOCAL] Data collected - CPU:${CPU_USAGE}% MEM:${MEM_USAGE_PCT}% DISK:${DISK_USAGE_PCT}% NET:${INTERNET_STATUS}" >> "$LOG_DIR/agent.log"
}

push_to_hub() {
    local json="$1"

    if [ "$ENABLE_PUSH" = "true" ] && [ -n "$HUB_URL" ]; then
        HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
            -X POST \
            -H "Content-Type: application/json" \
            -d "$json" \
            --connect-timeout 10 \
            --max-time 30 \
            "$HUB_URL" 2>/dev/null || echo "000")

        if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "201" ]; then
            echo "[$TIMESTAMP_LOCAL] Push success (HTTP $HTTP_CODE)" >> "$LOG_DIR/agent.log"
        else
            echo "[$TIMESTAMP_LOCAL] Push failed (HTTP $HTTP_CODE)" >> "$LOG_DIR/agent.log"
        fi
    fi
}

#===============================================================================
# 메인 실행
#===============================================================================

main() {
    collect_all_data
    JSON_DATA=$(generate_json)
    save_local "$JSON_DATA"
    push_to_hub "$JSON_DATA"
}

# 실행
main

# 로그 로테이션 (7일 이상 된 로그 삭제)
find "$LOG_DIR" -name "*.log" -mtime +7 -delete 2>/dev/null || true
