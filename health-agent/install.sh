#!/bin/bash
#===============================================================================
# Health Agent 설치 스크립트
# 사용법: sudo ./install.sh
#===============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="/opt/health-agent"

echo "=========================================="
echo "  Health Agent 설치"
echo "=========================================="
echo ""

# root 확인
if [ "$EUID" -ne 0 ]; then
    echo "root 권한이 필요합니다. sudo로 실행하세요."
    exit 1
fi

# 디렉토리 생성
echo "[1/5] 디렉토리 생성..."
mkdir -p "$INSTALL_DIR"
mkdir -p "$INSTALL_DIR/data"
mkdir -p /var/log/health-agent

# 스크립트 복사
echo "[2/5] 스크립트 복사..."
cp "$SCRIPT_DIR/health-agent.sh" "$INSTALL_DIR/"
cp "$SCRIPT_DIR/network-recovery.sh" "$INSTALL_DIR/"
cp "$SCRIPT_DIR/health-status" "$INSTALL_DIR/"

# 설정 파일 (기존 설정 보존)
if [ ! -f "$INSTALL_DIR/config.env" ]; then
    cp "$SCRIPT_DIR/config.env" "$INSTALL_DIR/"
    echo "  - 설정 파일 생성됨"
else
    echo "  - 기존 설정 파일 유지"
fi

# 실행 권한
chmod +x "$INSTALL_DIR/health-agent.sh"
chmod +x "$INSTALL_DIR/network-recovery.sh"
chmod +x "$INSTALL_DIR/health-status"

# CLI 심볼릭 링크
echo "[3/5] CLI 도구 설치..."
ln -sf "$INSTALL_DIR/health-status" /usr/local/bin/health-status

# systemd 서비스 설치
echo "[4/5] systemd 서비스 설치..."
cp "$SCRIPT_DIR/health-agent.service" /etc/systemd/system/
cp "$SCRIPT_DIR/health-agent.timer" /etc/systemd/system/
cp "$SCRIPT_DIR/network-recovery.service" /etc/systemd/system/
cp "$SCRIPT_DIR/network-recovery.timer" /etc/systemd/system/

systemctl daemon-reload

# 타이머 활성화
echo "[5/5] 타이머 활성화..."
systemctl enable --now health-agent.timer
systemctl enable --now network-recovery.timer

# 최초 실행
echo ""
echo "최초 헬스체크 실행..."
"$INSTALL_DIR/health-agent.sh" || true

echo ""
echo "=========================================="
echo "  설치 완료!"
echo "=========================================="
echo ""
echo "사용법:"
echo "  health-status       # 상태 요약"
echo "  health-status -f    # 전체 정보"
echo "  health-status -w    # 실시간 모니터링"
echo "  health-status -l    # 로그 확인"
echo ""
echo "설정 파일: $INSTALL_DIR/config.env"
echo ""
echo "타이머 상태:"
systemctl status health-agent.timer --no-pager | head -5
echo ""
