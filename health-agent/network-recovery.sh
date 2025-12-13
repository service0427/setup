#!/bin/bash
#===============================================================================
# 네트워크 자동 복구 스크립트 (Network Recovery)
# - 네트워크 연결 모니터링 및 자동 복구
# - 5분마다 systemd timer로 실행
#
# 복구 순서:
# 1. 인터페이스 재시작
# 2. DHCP 갱신
# 3. DNS 재설정
# 4. NetworkManager 재시작
# 5. 최후의 수단: 시스템 재부팅 (옵션)
#===============================================================================

set -e

# 설정
CONFIG_FILE="/opt/health-agent/config.env"
if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
fi

LOG_DIR="${LOG_DIR:-/var/log/health-agent}"
MAX_FAILURES="${MAX_FAILURES:-3}"
ENABLE_AUTO_REBOOT="${ENABLE_AUTO_REBOOT:-false}"
PING_TARGETS="${PING_TARGETS:-8.8.8.8 1.1.1.1 168.126.63.1}"  # Google, Cloudflare, KT DNS

mkdir -p "$LOG_DIR"

TIMESTAMP=$(date +"%Y-%m-%d %H:%M:%S")
FAILURE_COUNT_FILE="/tmp/network_failure_count"

log() {
    echo "[$TIMESTAMP] $1" >> "$LOG_DIR/network-recovery.log"
    echo "[$TIMESTAMP] $1"
}

#===============================================================================
# 네트워크 상태 확인
#===============================================================================

check_interface() {
    DEFAULT_IFACE=$(ip route 2>/dev/null | grep default | awk '{print $5}' | head -1)
    if [ -z "$DEFAULT_IFACE" ]; then
        log "ERROR: 기본 네트워크 인터페이스를 찾을 수 없음"
        return 1
    fi

    IFACE_STATUS=$(cat /sys/class/net/${DEFAULT_IFACE}/operstate 2>/dev/null || echo "unknown")
    if [ "$IFACE_STATUS" != "up" ]; then
        log "ERROR: 인터페이스 $DEFAULT_IFACE 상태: $IFACE_STATUS"
        return 1
    fi

    return 0
}

check_gateway() {
    GATEWAY=$(ip route | grep default | awk '{print $3}' | head -1)
    if [ -z "$GATEWAY" ]; then
        log "ERROR: 게이트웨이를 찾을 수 없음"
        return 1
    fi

    if ! ping -c 1 -W 3 "$GATEWAY" &>/dev/null; then
        log "ERROR: 게이트웨이 $GATEWAY 응답 없음"
        return 1
    fi

    return 0
}

check_internet() {
    for target in $PING_TARGETS; do
        if ping -c 1 -W 3 "$target" &>/dev/null; then
            return 0
        fi
    done

    log "ERROR: 외부 인터넷 연결 실패"
    return 1
}

check_dns() {
    if nslookup google.com &>/dev/null; then
        return 0
    fi

    log "ERROR: DNS 확인 실패"
    return 1
}

full_check() {
    check_interface && check_gateway && check_internet && check_dns
}

#===============================================================================
# 복구 함수들
#===============================================================================

recovery_level_1() {
    log "복구 레벨 1: 인터페이스 재시작"

    DEFAULT_IFACE=$(ip route 2>/dev/null | grep default | awk '{print $5}' | head -1)
    if [ -n "$DEFAULT_IFACE" ]; then
        sudo ip link set "$DEFAULT_IFACE" down 2>/dev/null || true
        sleep 2
        sudo ip link set "$DEFAULT_IFACE" up 2>/dev/null || true
        sleep 5
    fi
}

recovery_level_2() {
    log "복구 레벨 2: DHCP 갱신"

    DEFAULT_IFACE=$(ip route 2>/dev/null | grep default | awk '{print $5}' | head -1)
    if [ -n "$DEFAULT_IFACE" ]; then
        sudo dhclient -r "$DEFAULT_IFACE" 2>/dev/null || true
        sleep 2
        sudo dhclient "$DEFAULT_IFACE" 2>/dev/null || true
        sleep 5
    fi
}

recovery_level_3() {
    log "복구 레벨 3: DNS 재설정"

    # systemd-resolved 재시작
    sudo systemctl restart systemd-resolved 2>/dev/null || true
    sleep 3

    # DNS 캐시 정리
    sudo resolvectl flush-caches 2>/dev/null || true
}

recovery_level_4() {
    log "복구 레벨 4: NetworkManager 재시작"

    sudo systemctl restart NetworkManager 2>/dev/null || \
    sudo systemctl restart networking 2>/dev/null || true
    sleep 10
}

recovery_level_5() {
    log "복구 레벨 5: 시스템 재부팅"

    if [ "$ENABLE_AUTO_REBOOT" = "true" ]; then
        log "자동 재부팅 시작..."
        echo "Network recovery failed, rebooting..." | wall 2>/dev/null || true
        sleep 5
        sudo reboot
    else
        log "자동 재부팅 비활성화됨. 수동 개입 필요"
    fi
}

#===============================================================================
# 메인 로직
#===============================================================================

main() {
    # 네트워크 상태 확인
    if full_check; then
        log "네트워크 정상"
        echo "0" > "$FAILURE_COUNT_FILE"
        exit 0
    fi

    # 실패 카운트 증가
    FAILURES=$(cat "$FAILURE_COUNT_FILE" 2>/dev/null || echo "0")
    FAILURES=$((FAILURES + 1))
    echo "$FAILURES" > "$FAILURE_COUNT_FILE"

    log "네트워크 장애 감지 (연속 실패: $FAILURES)"

    # 단계별 복구 시도
    recovery_level_1
    if full_check; then
        log "복구 성공 (레벨 1)"
        echo "0" > "$FAILURE_COUNT_FILE"
        exit 0
    fi

    recovery_level_2
    if full_check; then
        log "복구 성공 (레벨 2)"
        echo "0" > "$FAILURE_COUNT_FILE"
        exit 0
    fi

    recovery_level_3
    if full_check; then
        log "복구 성공 (레벨 3)"
        echo "0" > "$FAILURE_COUNT_FILE"
        exit 0
    fi

    recovery_level_4
    if full_check; then
        log "복구 성공 (레벨 4)"
        echo "0" > "$FAILURE_COUNT_FILE"
        exit 0
    fi

    # 최대 실패 횟수 초과 시 재부팅
    if [ "$FAILURES" -ge "$MAX_FAILURES" ]; then
        log "최대 실패 횟수 초과 ($FAILURES >= $MAX_FAILURES)"
        recovery_level_5
    else
        log "복구 실패. 다음 실행까지 대기..."
    fi
}

main
