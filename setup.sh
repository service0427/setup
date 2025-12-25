#!/bin/bash
#===============================================================================
# Ubuntu 22.04 자동화 서버 초기 설정 스크립트 (통합 버전)
# - 쿠팡 자동화 에이전트용 최적화 환경 구성
# - WireGuard VPN + Playwright 브라우저 자동화 지원
# - vpn_coupang_v1 에이전트 자동 설치 포함
# - Ubuntu 24는 자동 로그아웃 이슈로 22.04 권장
#
# 사용법: ./setup.sh (sudo 자동 처리)
# GitHub: https://github.com/service0427/setup
#===============================================================================

# set -e 제거 - 일부 명령 실패 시에도 계속 진행하도록 함
# set -e  # 에러 발생 시 중단

# 버전 정보
SCRIPT_VERSION="1.3.2"

# 변수 초기화
ANYDESK_INSTALLED=0

# 스크립트 위치 저장 (나중에 health-agent 경로 찾기용)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 실제 사용자 확인 (sudo로 실행해도 원래 사용자 찾기)
if [ "$EUID" -eq 0 ] && [ -n "$SUDO_USER" ]; then
    REAL_USER=$SUDO_USER
else
    REAL_USER=$USER
fi
REAL_HOME=$(eval echo ~$REAL_USER)

#===============================================================================
# sudo 타임아웃 설정 (재부팅 전까지 비밀번호 한 번만 입력)
#===============================================================================
SUDO_TIMEOUT_FILE="/etc/sudoers.d/timeout-noexpire"
if [ ! -f "$SUDO_TIMEOUT_FILE" ]; then
    echo "sudo 타임아웃 설정 중..."
    # 먼저 한 번 sudo 권한 확인
    sudo -v
    # timestamp_timeout=-1: 재부팅 전까지 sudo 인증 유지
    echo 'Defaults timestamp_timeout=-1' | sudo tee "$SUDO_TIMEOUT_FILE" > /dev/null
    sudo chmod 440 "$SUDO_TIMEOUT_FILE"
    echo "sudo 타임아웃 설정 완료 (재부팅 전까지 유효)"
else
    sudo -v
fi

# 시스템 정보 (LANG=C로 영문 출력 강제)
TOTAL_RAM_GB=$(LANG=C free -g | awk '/^Mem:/{print $2}')
CPU_CORES=$(nproc)

echo "========================================"
echo "  Ubuntu 22.04 자동화 서버 셋업 v${SCRIPT_VERSION}"
echo "========================================"
echo "  실행 사용자: $REAL_USER"
echo "  RAM: ${TOTAL_RAM_GB}GB | CPU: ${CPU_CORES} cores"
echo "========================================"
echo ""

#===============================================================================
# PART 1: 시스템 설정 (sudo 필요)
#===============================================================================

#---------------------------------------
# 1. 타임존 설정 (KST)
#---------------------------------------
echo "[1/24] 타임존 설정 (Asia/Seoul)..."
CURRENT_TZ=$(timedatectl show --property=Timezone --value 2>/dev/null)
if [ "$CURRENT_TZ" != "Asia/Seoul" ]; then
    sudo timedatectl set-timezone Asia/Seoul
    echo "타임존 변경: $CURRENT_TZ → Asia/Seoul"
else
    echo "타임존 이미 설정됨: Asia/Seoul"
fi

#---------------------------------------
# 2. 기본 패키지 설치
#---------------------------------------
echo "[2/24] 기본 패키지 설치..."
sudo apt update && sudo apt upgrade -y
sudo apt install -y \
    curl git openssh-server htop wget gnupg \
    ca-certificates apt-transport-https \
    software-properties-common build-essential \
    im-config  # 한글 입력기 설정용

#---------------------------------------
# 3. Node.js 22.x 설치
#---------------------------------------
echo "[3/24] Node.js 22.x 설치..."
if ! command -v node &> /dev/null; then
    curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash -
    sudo apt-get install -y nodejs
    echo "Node.js 설치 완료: $(node -v)"
else
    NODE_VERSION=$(node -v | cut -d'v' -f2 | cut -d'.' -f1)
    if [ "$NODE_VERSION" -lt 18 ]; then
        echo "Node.js 버전 업그레이드 필요 (현재: $(node -v))"
        curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash -
        sudo apt-get install -y nodejs
        echo "Node.js 업그레이드 완료: $(node -v)"
    else
        echo "Node.js 이미 설치됨: $(node -v)"
    fi
fi

#---------------------------------------
# 4. Python 3.11+ 설치 (deadsnakes PPA)
#---------------------------------------
echo "[4/24] Python 3.11 설치..."
if ! command -v python3.11 &> /dev/null; then
    sudo add-apt-repository -y ppa:deadsnakes/ppa
    sudo apt update
    sudo apt install -y python3.11 python3.11-venv python3.11-dev python3-pip

    # python3 기본 버전 변경
    sudo update-alternatives --install /usr/bin/python3 python3 /usr/bin/python3.11 1
    sudo update-alternatives --set python3 /usr/bin/python3.11 2>/dev/null || true

    echo "Python 설치 완료: $(python3.11 --version)"
else
    echo "Python 3.11 이미 설치됨: $(python3.11 --version)"
fi

#---------------------------------------
# 5. Google Chrome 설치
#---------------------------------------
echo "[5/24] Google Chrome 설치..."
if ! command -v google-chrome &> /dev/null; then
    sudo install -d -m 0755 /etc/apt/keyrings
    wget -qO- https://dl.google.com/linux/linux_signing_key.pub | sudo tee /etc/apt/keyrings/google.asc >/dev/null
    sudo chmod a+r /etc/apt/keyrings/google.asc
    echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/google.asc] http://dl.google.com/linux/chrome/deb/ stable main" | \
        sudo tee /etc/apt/sources.list.d/google-chrome.list >/dev/null
    sudo apt update
    sudo apt install -y google-chrome-stable
    echo "Chrome 설치 완료: $(google-chrome --version)"
else
    echo "Chrome 이미 설치됨: $(google-chrome --version)"
fi

#---------------------------------------
# 6. Playwright/Patchright 브라우저 의존성
#---------------------------------------
echo "[6/24] 브라우저 자동화 의존성 설치..."
sudo apt install -y \
    libnss3 libnspr4 libatk1.0-0 libatk-bridge2.0-0 \
    libcups2 libdrm2 libxkbcommon0 libxcomposite1 \
    libxdamage1 libxrandr2 libgbm1 libpango-1.0-0 \
    libcairo2 libasound2 libatspi2.0-0 \
    fonts-liberation libappindicator3-1 \
    xdg-utils fonts-noto-cjk fonts-noto-color-emoji
echo "브라우저 의존성 설치 완료"

#---------------------------------------
# 7. WireGuard VPN 설치
#---------------------------------------
echo "[7/24] WireGuard VPN 설치..."
if ! command -v wg &> /dev/null; then
    sudo apt install -y wireguard wireguard-tools

    # 커널 모듈 로드
    sudo modprobe wireguard 2>/dev/null || true

    # 부팅 시 자동 로드 설정
    if [ ! -f /etc/modules-load.d/wireguard.conf ]; then
        echo wireguard | sudo tee /etc/modules-load.d/wireguard.conf > /dev/null
    fi

    echo "WireGuard 설치 완료"
else
    echo "WireGuard 이미 설치됨: $(wg --version)"
fi

#---------------------------------------
# 8. AnyDesk 설치 및 무인 접속 설정
#---------------------------------------
echo "[8/24] AnyDesk 설치..."

# AnyDesk 설정값
ANYDESK_PASSWORD="Tech1324!"
ANYDESK_LICENSE="WNIX6Z9J66HVIU9"

if ! command -v anydesk &> /dev/null; then
    curl -fsSL https://keys.anydesk.com/repos/DEB-GPG-KEY | sudo tee /etc/apt/keyrings/keys.anydesk.com.asc >/dev/null
    sudo chmod a+r /etc/apt/keyrings/keys.anydesk.com.asc
    echo 'deb [signed-by=/etc/apt/keyrings/keys.anydesk.com.asc] https://deb.anydesk.com all main' | \
        sudo tee /etc/apt/sources.list.d/anydesk-stable.list >/dev/null
    sudo apt update
    sudo apt install -y anydesk
    sudo systemctl enable --now anydesk

    # 서비스가 완전히 시작될 때까지 대기
    sleep 3

    echo "AnyDesk 설치 완료"
    ANYDESK_INSTALLED=1
else
    echo "AnyDesk 이미 설치됨"
    ANYDESK_INSTALLED=0
fi

# AnyDesk ID가 생성될 때까지 대기 (최초 설치 시)
if [ "$ANYDESK_INSTALLED" -eq 1 ]; then
    echo "  AnyDesk ID 생성 대기 중..."
    for i in {1..30}; do
        ANYDESK_ID=$(anydesk --get-id 2>/dev/null)
        if [ -n "$ANYDESK_ID" ] && [ "$ANYDESK_ID" != "0" ]; then
            break
        fi
        sleep 1
    done
fi

# 라이센스 등록 (미등록 시)
if ! grep -q "ad.license.key" /etc/anydesk/system.conf 2>/dev/null; then
    echo "  라이센스 등록 중..."
    echo "$ANYDESK_LICENSE" | sudo anydesk --register-license 2>/dev/null && \
        echo "  라이센스 등록 완료" || echo "  라이센스 등록 실패 (수동 등록 필요)"
fi

# 무인 접속 비밀번호 설정
echo "  무인 접속 비밀번호 설정 중..."
echo "$ANYDESK_PASSWORD" | sudo anydesk --set-password 2>/dev/null && \
    echo "  비밀번호 설정 완료" || echo "  비밀번호 설정 실패 (수동 설정 필요)"

# AnyDesk ID 출력
ANYDESK_ID=$(anydesk --get-id 2>/dev/null)
if [ -n "$ANYDESK_ID" ]; then
    echo "  AnyDesk ID: $ANYDESK_ID"
fi

#---------------------------------------
# 9. 한글 입력기 설치 (fcitx5)
#---------------------------------------
echo "[9/24] 한글 입력기 설치..."
if ! dpkg -l | grep -q fcitx5-hangul; then
    sudo apt install -y fcitx5 fcitx5-hangul
    sudo -u $REAL_USER im-config -n fcitx5
    echo "한글 입력기 설치 완료"
else
    echo "한글 입력기 이미 설치됨"
fi

#---------------------------------------
# 10. Snap 패키지 완전 제거
#---------------------------------------
echo "[10/24] Snap 패키지 제거..."
if command -v snap &> /dev/null; then
    SNAP_COUNT=$(snap list 2>/dev/null | wc -l)
    if [ "$SNAP_COUNT" -gt 1 ]; then
        echo "Snap 패키지 ${SNAP_COUNT}개 발견, 제거 중..."

        # Firefox 등 일반 snap 먼저 제거
        for pkg in $(snap list 2>/dev/null | awk '!/^Name|^bare|^core|^snapd/{print $1}'); do
            echo "  - $pkg 제거 중..."
            sudo snap remove --purge "$pkg" 2>/dev/null || true
        done

        # core, bare 제거
        for pkg in $(snap list 2>/dev/null | awk '/^bare|^core/{print $1}'); do
            echo "  - $pkg 제거 중..."
            sudo snap remove --purge "$pkg" 2>/dev/null || true
        done

        # snapd 서비스 중지 및 제거
        sudo systemctl stop snapd.service snapd.socket 2>/dev/null || true
        sudo systemctl disable snapd.service snapd.socket 2>/dev/null || true
        sudo apt autoremove --purge snapd -y 2>/dev/null || true

        # 잔여 폴더 제거
        sudo rm -rf $REAL_HOME/snap 2>/dev/null || true
        sudo rm -rf /snap 2>/dev/null || true
        sudo rm -rf /var/snap 2>/dev/null || true
        sudo rm -rf /var/lib/snapd 2>/dev/null || true
        sudo rm -rf /var/cache/snapd 2>/dev/null || true

        echo "Snap 완전 제거 완료"
    else
        echo "Snap 패키지 없음"
    fi
else
    echo "Snap 이미 제거됨"
fi

#---------------------------------------
# 11. CUPS (프린터) 서비스 비활성화
#---------------------------------------
echo "[11/24] 불필요한 서비스 비활성화..."

# CUPS 프린터 서비스
sudo systemctl stop cups.service cups-browsed.service 2>/dev/null || true
sudo systemctl disable cups.service cups-browsed.service 2>/dev/null || true

# Avahi (mDNS/DNS-SD) - 네트워크 서비스 검색, 자동화에 불필요
sudo systemctl stop avahi-daemon.service avahi-daemon.socket 2>/dev/null || true
sudo systemctl disable avahi-daemon.service avahi-daemon.socket 2>/dev/null || true

# ModemManager - 모뎀 관리, 서버에 불필요
sudo systemctl stop ModemManager.service 2>/dev/null || true
sudo systemctl disable ModemManager.service 2>/dev/null || true

# Kerneloops - 커널 충돌 리포트
sudo systemctl stop kerneloops.service 2>/dev/null || true
sudo systemctl disable kerneloops.service 2>/dev/null || true

# PackageKit - GUI 패키지 관리 (apt 사용)
sudo systemctl stop packagekit.service 2>/dev/null || true
sudo systemctl disable packagekit.service 2>/dev/null || true

# Ubuntu Advantage - Ubuntu Pro 서비스
sudo systemctl stop ubuntu-advantage.service 2>/dev/null || true
sudo systemctl disable ubuntu-advantage.service 2>/dev/null || true
sudo systemctl stop ubuntu-advantage-desktop-daemon.service 2>/dev/null || true
sudo systemctl disable ubuntu-advantage-desktop-daemon.service 2>/dev/null || true

# 부팅 스플래시 (Plymouth) - 부팅 22초 절약
sudo systemctl disable plymouth-quit-wait.service 2>/dev/null || true

# NetworkManager-wait-online - 부팅 5초 절약 (네트워크 대기 불필요)
sudo systemctl disable NetworkManager-wait-online.service 2>/dev/null || true

echo "불필요한 서비스 비활성화 완료"

#---------------------------------------
# 12. 자동 업데이트 비활성화
#---------------------------------------
echo "[12/24] 자동 업데이트 비활성화..."
sudo systemctl disable --now unattended-upgrades.service 2>/dev/null || true
sudo systemctl disable --now apt-daily.service apt-daily.timer 2>/dev/null || true
sudo systemctl disable --now apt-daily-upgrade.service apt-daily-upgrade.timer 2>/dev/null || true

# 버전 업그레이드 차단
sudo sed -i 's/Prompt=lts/Prompt=never/g' /etc/update-manager/release-upgrades 2>/dev/null || true
sudo sed -i 's/Prompt=normal/Prompt=never/g' /etc/update-manager/release-upgrades 2>/dev/null || true
echo "자동 업데이트 비활성화 완료"

#---------------------------------------
# 13. CPU Governor → Performance
#---------------------------------------
echo "[13/24] CPU Governor 설정..."
CURRENT_GOV=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null || echo "unknown")
if [ "$CURRENT_GOV" != "performance" ]; then
    # cpufrequtils 설치
    if ! dpkg -l | grep -q cpufrequtils; then
        sudo apt install -y cpufrequtils
    fi

    # performance 모드 설정
    echo 'GOVERNOR="performance"' | sudo tee /etc/default/cpufrequtils > /dev/null

    # 즉시 적용 (모든 CPU 코어)
    for cpu in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
        echo "performance" | sudo tee "$cpu" > /dev/null 2>&1 || true
    done

    sudo systemctl restart cpufrequtils 2>/dev/null || true
    echo "CPU Governor: $CURRENT_GOV → performance 변경 완료"
else
    echo "CPU Governor 이미 performance 모드"
fi

#---------------------------------------
# 14. 시스템 커널 파라미터 최적화
#---------------------------------------
echo "[14/24] 시스템 커널 파라미터 최적화..."

# swappiness 낮추기 (RAM 우선 사용)
if ! grep -q "vm.swappiness=10" /etc/sysctl.conf; then
    sudo sed -i '/vm.swappiness/d' /etc/sysctl.conf
    echo 'vm.swappiness=10' | sudo tee -a /etc/sysctl.conf
    echo "swappiness=10 설정 완료"
else
    echo "swappiness 이미 설정됨"
fi

# vfs_cache_pressure 낮추기 (파일 캐시 유지 - Playwright I/O 최적화)
if ! grep -q "vm.vfs_cache_pressure=50" /etc/sysctl.conf; then
    sudo sed -i '/vm.vfs_cache_pressure/d' /etc/sysctl.conf
    echo 'vm.vfs_cache_pressure=50' | sudo tee -a /etc/sysctl.conf
    echo "vfs_cache_pressure=50 설정 완료"
else
    echo "vfs_cache_pressure 이미 설정됨"
fi

# 파일 디스크립터 한도 증가 (Chrome 다중 인스턴스용)
if ! grep -q "nofile 65536" /etc/security/limits.conf; then
    echo '* soft nofile 65536' | sudo tee -a /etc/security/limits.conf
    echo '* hard nofile 65536' | sudo tee -a /etc/security/limits.conf
    echo "파일 디스크립터 한도 증가 완료"
else
    echo "파일 디스크립터 한도 이미 설정됨"
fi

# 네트워크 최적화 (WireGuard VPN용)
if ! grep -q "net.core.rmem_max" /etc/sysctl.conf; then
    cat << 'EOF' | sudo tee -a /etc/sysctl.conf
# Network optimization for WireGuard
net.core.rmem_max=26214400
net.core.wmem_max=26214400
net.ipv4.ip_forward=1
EOF
    echo "네트워크 최적화 설정 완료"
else
    echo "네트워크 최적화 이미 설정됨"
fi

sudo sysctl -p 2>/dev/null || true

#---------------------------------------
# 15. 스왑 파일 설정 (RAM 기반 동적 크기)
#---------------------------------------
echo "[15/24] 스왑 파일 설정..."

# RAM 크기에 따른 스왑 크기 결정
if [ "$TOTAL_RAM_GB" -le 8 ]; then
    SWAP_SIZE="16G"
elif [ "$TOTAL_RAM_GB" -le 16 ]; then
    SWAP_SIZE="24G"
elif [ "$TOTAL_RAM_GB" -le 32 ]; then
    SWAP_SIZE="32G"
else
    SWAP_SIZE="48G"
fi

if [ ! -f /swapfile ]; then
    echo "${SWAP_SIZE} 스왑 파일 생성 중... (시간이 걸릴 수 있음)"
    # fallocate 먼저 시도 (빠름), 실패시 dd 사용 (btrfs/ZFS 호환)
    if ! sudo fallocate -l $SWAP_SIZE /swapfile 2>/dev/null; then
        echo "fallocate 실패, dd로 재시도..."
        sudo dd if=/dev/zero of=/swapfile bs=1G count=${SWAP_SIZE%G} status=progress
    fi
    sudo chmod 600 /swapfile
    sudo mkswap /swapfile
    sudo swapon /swapfile

    # fstab에 영구 등록
    if ! grep -q "/swapfile" /etc/fstab; then
        echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
    fi
    echo "스왑 파일 생성 완료: $SWAP_SIZE"
else
    CURRENT_SWAP=$(ls -lh /swapfile | awk '{print $5}')
    echo "스왑 파일 이미 존재: $CURRENT_SWAP"
fi

#---------------------------------------
# 16. 자동 로그인 + Wayland 비활성화 (AnyDesk 호환)
#---------------------------------------
echo "[16/24] 자동 로그인 및 X11 설정..."
GDM_CONF="/etc/gdm3/custom.conf"
if [ -f "$GDM_CONF" ]; then
    # Wayland 비활성화 (AnyDesk는 X11 필요)
    if grep -q "#WaylandEnable=false" "$GDM_CONF"; then
        sudo sed -i 's/#WaylandEnable=false/WaylandEnable=false/' "$GDM_CONF"
        echo "Wayland 비활성화 완료 (X11 사용)"
    elif ! grep -q "WaylandEnable=false" "$GDM_CONF"; then
        sudo sed -i '/^\[daemon\]/a WaylandEnable=false' "$GDM_CONF"
        echo "Wayland 비활성화 추가 완료"
    else
        echo "Wayland 이미 비활성화됨"
    fi

    # 자동 로그인 설정
    if ! grep -q "AutomaticLoginEnable=true" "$GDM_CONF" 2>/dev/null; then
        # [daemon] 섹션 확인 및 설정 추가
        if grep -q "^\[daemon\]" "$GDM_CONF"; then
            sudo sed -i "/^\[daemon\]/a AutomaticLoginEnable=true\nAutomaticLogin=$REAL_USER" "$GDM_CONF"
        else
            echo -e "[daemon]\nAutomaticLoginEnable=true\nAutomaticLogin=$REAL_USER" | sudo tee -a "$GDM_CONF"
        fi
        echo "자동 로그인 설정 완료 ($REAL_USER 계정)"
    else
        echo "자동 로그인 이미 설정됨"
    fi
else
    echo "GDM3 설정 파일 없음 (데스크톱 환경 미설치)"
fi

#---------------------------------------
# 17. sudoers 설정 (자주 사용하는 명령어 NOPASSWD)
#---------------------------------------
echo "[17/24] sudoers 설정..."
SUDOERS_FILE="/etc/sudoers.d/${REAL_USER}-automation"
if [ ! -f "$SUDOERS_FILE" ]; then
    cat << EOF | sudo tee "$SUDOERS_FILE" > /dev/null
# 자동화 에이전트용 sudoers 설정
# Node.js & npm
${REAL_USER} ALL=(ALL) NOPASSWD: /usr/bin/node, /usr/bin/npm, /usr/bin/npx

# 네트워크 & VPN
${REAL_USER} ALL=(ALL) NOPASSWD: /usr/sbin/ip, /sbin/ip
${REAL_USER} ALL=(ALL) NOPASSWD: /usr/bin/wg, /usr/bin/wg-quick

# 시스템 관리
${REAL_USER} ALL=(ALL) NOPASSWD: /usr/bin/systemctl
${REAL_USER} ALL=(ALL) NOPASSWD: /usr/bin/apt, /usr/bin/apt-get
${REAL_USER} ALL=(ALL) NOPASSWD: /usr/sbin/reboot, /usr/sbin/shutdown
${REAL_USER} ALL=(ALL) NOPASSWD: /usr/bin/tee
${REAL_USER} ALL=(ALL) NOPASSWD: /usr/bin/kill, /usr/bin/pkill

# 파일 권한
${REAL_USER} ALL=(ALL) NOPASSWD: /usr/bin/chmod, /usr/bin/chown
${REAL_USER} ALL=(ALL) NOPASSWD: /usr/bin/mkdir, /usr/bin/rm

# 모듈 & 커널
${REAL_USER} ALL=(ALL) NOPASSWD: /usr/sbin/modprobe
EOF
    sudo chmod 440 "$SUDOERS_FILE"
    # sudoers 문법 검사
    if sudo visudo -c -f "$SUDOERS_FILE" 2>/dev/null; then
        echo "sudoers 설정 완료"
    else
        echo "sudoers 문법 오류, 파일 삭제"
        sudo rm -f "$SUDOERS_FILE"
    fi
else
    echo "sudoers 이미 설정됨"
fi

#===============================================================================
# PART 2: 사용자 서비스 & GUI 설정 (user 권한)
#===============================================================================

echo ""
echo "[ PART 2: 사용자 설정 ]"
echo ""

#---------------------------------------
# 18. GNOME 검색 & Tracker 비활성화
#---------------------------------------
echo "[18/24] GNOME 검색 & Tracker 비활성화..."

# GNOME 검색 프로바이더 비활성화
sudo -u $REAL_USER gsettings set org.gnome.desktop.search-providers disable-external true 2>/dev/null || true
sudo -u $REAL_USER gsettings set org.gnome.desktop.search-providers disabled "['org.gnome.Contacts.desktop', 'org.gnome.Documents.desktop', 'org.gnome.Nautilus.desktop', 'org.gnome.Calculator.desktop', 'org.gnome.Calendar.desktop', 'org.gnome.Characters.desktop', 'org.gnome.clocks.desktop', 'org.gnome.Terminal.desktop', 'org.gnome.Software.desktop']" 2>/dev/null || true

# Tracker 서비스 비활성화
sudo -u $REAL_USER systemctl --user stop tracker-miner-fs-3.service 2>/dev/null || true
sudo -u $REAL_USER systemctl --user disable tracker-miner-fs-3.service 2>/dev/null || true
sudo -u $REAL_USER systemctl --user mask tracker-miner-fs-3.service 2>/dev/null || true
sudo -u $REAL_USER tracker3 reset --filesystem 2>/dev/null || true

echo "GNOME 검색 & Tracker 비활성화 완료"

#---------------------------------------
# 19. 불필요 사용자 서비스 비활성화 + GUI 설정
#---------------------------------------
echo "[19/24] GUI 및 사용자 서비스 최적화..."

# Evolution 데이터 서버
sudo -u $REAL_USER systemctl --user stop evolution-addressbook-factory.service 2>/dev/null || true
sudo -u $REAL_USER systemctl --user stop evolution-calendar-factory.service 2>/dev/null || true
sudo -u $REAL_USER systemctl --user stop evolution-source-registry.service 2>/dev/null || true
sudo -u $REAL_USER systemctl --user disable evolution-addressbook-factory.service 2>/dev/null || true
sudo -u $REAL_USER systemctl --user disable evolution-calendar-factory.service 2>/dev/null || true
sudo -u $REAL_USER systemctl --user disable evolution-source-registry.service 2>/dev/null || true

# GNOME 온라인 계정
sudo -u $REAL_USER systemctl --user stop goa-daemon.service 2>/dev/null || true
sudo -u $REAL_USER systemctl --user disable goa-daemon.service 2>/dev/null || true

# 핫 코너 비활성화
sudo -u $REAL_USER gsettings set org.gnome.desktop.interface enable-hot-corners false 2>/dev/null || true

# 워크스페이스 1개로 고정
sudo -u $REAL_USER gsettings set org.gnome.mutter dynamic-workspaces false 2>/dev/null || true
sudo -u $REAL_USER gsettings set org.gnome.desktop.wm.preferences num-workspaces 1 2>/dev/null || true

# 시스템 알림 비활성화
sudo -u $REAL_USER gsettings set org.gnome.desktop.notifications show-banners false 2>/dev/null || true
sudo -u $REAL_USER gsettings set org.gnome.desktop.notifications show-in-lock-screen false 2>/dev/null || true

# 최근 파일 기록 비활성화
sudo -u $REAL_USER gsettings set org.gnome.desktop.privacy remember-recent-files false 2>/dev/null || true
sudo -u $REAL_USER gsettings set org.gnome.desktop.privacy remember-app-usage false 2>/dev/null || true

# 화면 잠금 비활성화
sudo -u $REAL_USER gsettings set org.gnome.desktop.screensaver lock-enabled false 2>/dev/null || true
sudo -u $REAL_USER gsettings set org.gnome.desktop.screensaver idle-activation-enabled false 2>/dev/null || true

# 시스템 소리 비활성화
sudo -u $REAL_USER gsettings set org.gnome.desktop.sound event-sounds false 2>/dev/null || true
sudo -u $REAL_USER gsettings set org.gnome.desktop.sound input-feedback-sounds false 2>/dev/null || true

echo "GUI 및 사용자 서비스 최적화 완료"

#---------------------------------------
# 20. GUI 설정 (GNOME)
#---------------------------------------
echo "[20/24] GUI 외관 설정..."

# 화면 꺼짐 방지
sudo -u $REAL_USER gsettings set org.gnome.desktop.session idle-delay 0 2>/dev/null || true

# 다크모드
sudo -u $REAL_USER gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark' 2>/dev/null || true

# 애니메이션 비활성화
sudo -u $REAL_USER gsettings set org.gnome.desktop.interface enable-animations false 2>/dev/null || true

# Dock 정리 (Chrome, Terminal만)
sudo -u $REAL_USER gsettings set org.gnome.shell favorite-apps "['google-chrome.desktop', 'org.gnome.Terminal.desktop']" 2>/dev/null || true

# 휴지통 Dock에 표시
sudo -u $REAL_USER gsettings set org.gnome.shell.extensions.dash-to-dock show-trash true 2>/dev/null || true

# 바탕화면 설정 (Ubuntu 22.04 Jellyfish 다크)
sudo -u $REAL_USER gsettings set org.gnome.desktop.background picture-uri 'file:///usr/share/backgrounds/warty-final-ubuntu.png' 2>/dev/null || true
sudo -u $REAL_USER gsettings set org.gnome.desktop.background picture-uri-dark 'file:///usr/share/backgrounds/jj_dark_by_Hiking93.jpg' 2>/dev/null || true
sudo -u $REAL_USER gsettings set org.gnome.desktop.background picture-options 'zoom' 2>/dev/null || true

# 바탕화면 아이콘 비활성화
sudo -u $REAL_USER gsettings set org.gnome.shell.extensions.ding show-home false 2>/dev/null || true
sudo -u $REAL_USER gsettings set org.gnome.shell.extensions.ding show-trash false 2>/dev/null || true
sudo -u $REAL_USER gsettings set org.gnome.shell.extensions.ding show-volumes false 2>/dev/null || true

echo "GUI 외관 설정 완료"

#===============================================================================
# PART 3: 에이전트 설치
#===============================================================================

echo ""
echo "[ PART 3: 에이전트 설치 ]"
echo ""

#---------------------------------------
# 21. Patchright 브라우저 설치
#---------------------------------------
echo "[21/24] Patchright 브라우저 설치..."
PATCHRIGHT_CACHE="$REAL_HOME/.cache/ms-playwright"

if [ ! -d "$PATCHRIGHT_CACHE" ] || [ -z "$(ls -A $PATCHRIGHT_CACHE 2>/dev/null)" ]; then
    # 임시 디렉토리에서 patchright 설치
    TEMP_DIR=$(mktemp -d)
    cd "$TEMP_DIR"

    # package.json 생성
    cat << 'PKGJSON' > package.json
{
  "name": "patchright-installer",
  "private": true,
  "dependencies": {
    "patchright": "^1.56.1"
  }
}
PKGJSON

    # 사용자 권한으로 설치 (브라우저 바이너리가 사용자 홈에 설치됨)
    sudo -u $REAL_USER npm install
    sudo -u $REAL_USER npx patchright install chromium

    # 정리
    cd /
    rm -rf "$TEMP_DIR"

    echo "Patchright 브라우저 설치 완료"
else
    echo "Patchright 브라우저 이미 설치됨"
fi

#---------------------------------------
# 22. vpn_coupang_v1 에이전트 설치
#---------------------------------------
echo "[22/24] vpn_coupang_v1 에이전트 설치..."
AGENT_DIR="$REAL_HOME/vpn_coupang_v1"

# GitHub 토큰 (private 저장소 접근용) - 실제 운영 시 환경변수로 전달 권장
GITHUB_TOKEN="${GITHUB_TOKEN:-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}"

if [ -d "$AGENT_DIR" ]; then
    echo "기존 에이전트 디렉토리 발견, 업데이트 중..."
    cd "$AGENT_DIR"
    sudo -u $REAL_USER git pull origin main 2>/dev/null || true
    sudo -u $REAL_USER npm install
    echo "에이전트 업데이트 완료"
else
    echo "에이전트 클론 중..."
    sudo -u $REAL_USER git clone https://${GITHUB_TOKEN}@github.com/service0427/vpn_coupang_v1.git "$AGENT_DIR" 2>/dev/null || \
    sudo -u $REAL_USER git clone https://github.com/service0427/vpn_coupang_v1.git "$AGENT_DIR"
    cd "$AGENT_DIR"
    sudo -u $REAL_USER npm install
    echo "에이전트 설치 완료"
fi

# node_modules 확인
if [ -d "$AGENT_DIR/node_modules" ]; then
    echo "  - node_modules 확인됨"
fi

# Patchright 브라우저 확인
if [ -d "$PATCHRIGHT_CACHE" ]; then
    echo "  - Patchright 브라우저 확인됨"
fi

#---------------------------------------
# 23. Health Agent 설치 (헬스체크 & 네트워크 복구)
#---------------------------------------
echo "[23/24] Health Agent 설치..."
HEALTH_AGENT_DIR="/opt/health-agent"
SCRIPT_SOURCE_DIR="$SCRIPT_DIR/health-agent"

if [ -d "$SCRIPT_SOURCE_DIR" ]; then
    # 디렉토리 생성
    mkdir -p "$HEALTH_AGENT_DIR"
    mkdir -p "$HEALTH_AGENT_DIR/data"
    mkdir -p /var/log/health-agent

    # 스크립트 복사
    cp "$SCRIPT_SOURCE_DIR/health-agent.sh" "$HEALTH_AGENT_DIR/"
    cp "$SCRIPT_SOURCE_DIR/network-recovery.sh" "$HEALTH_AGENT_DIR/"
    cp "$SCRIPT_SOURCE_DIR/health-status" "$HEALTH_AGENT_DIR/"

    # 설정 파일 (기존 설정 보존)
    if [ ! -f "$HEALTH_AGENT_DIR/config.env" ]; then
        cp "$SCRIPT_SOURCE_DIR/config.env" "$HEALTH_AGENT_DIR/"
    fi

    # 실행 권한
    chmod +x "$HEALTH_AGENT_DIR/health-agent.sh"
    chmod +x "$HEALTH_AGENT_DIR/network-recovery.sh"
    chmod +x "$HEALTH_AGENT_DIR/health-status"

    # CLI 심볼릭 링크
    ln -sf "$HEALTH_AGENT_DIR/health-status" /usr/local/bin/health-status

    # systemd 서비스 설치
    cp "$SCRIPT_SOURCE_DIR/health-agent.service" /etc/systemd/system/
    cp "$SCRIPT_SOURCE_DIR/health-agent.timer" /etc/systemd/system/
    cp "$SCRIPT_SOURCE_DIR/network-recovery.service" /etc/systemd/system/
    cp "$SCRIPT_SOURCE_DIR/network-recovery.timer" /etc/systemd/system/

    systemctl daemon-reload
    systemctl enable --now health-agent.timer
    systemctl enable --now network-recovery.timer

    # 최초 실행
    "$HEALTH_AGENT_DIR/health-agent.sh" 2>/dev/null || true

    echo "Health Agent 설치 완료"
    echo "  - 헬스체크: 1분마다 실행"
    echo "  - 네트워크 복구: 5분마다 실행"
    echo "  - CLI: health-status"
else
    echo "Health Agent 소스 없음, 스킵"
fi

#---------------------------------------
# 24. 최종 확인
#---------------------------------------
echo "[24/24] 최종 확인..."

# 모든 서비스 상태 확인
echo "  서비스 상태 확인 중..."

#===============================================================================
# 완료 리포트
#===============================================================================
echo ""
echo "========================================"
echo "  셋업 완료! v${SCRIPT_VERSION}"
echo "========================================"
echo ""
echo "[ 시스템 정보 ]"
echo "  - 호스트명: $(hostname)"
echo "  - RAM: ${TOTAL_RAM_GB}GB | CPU: ${CPU_CORES} cores"
echo "  - 타임존: $(timedatectl show --property=Timezone --value 2>/dev/null || cat /etc/timezone)"
echo "  - 자동 로그인: $(grep -q 'AutomaticLoginEnable=true' /etc/gdm3/custom.conf 2>/dev/null && echo '활성화' || echo '비활성화')"
echo ""
echo "[ 원격 접속 정보 ]"
echo "  - IP: $(ip -4 addr show | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | grep -v '127.0.0.1' | head -1)"
echo "  - AnyDesk ID: $(anydesk --get-id 2>/dev/null || echo 'N/A')"
echo "  - AnyDesk PW: $ANYDESK_PASSWORD"
echo ""
echo "[ 설치 현황 ]"
echo "  - Node.js: $(node -v 2>/dev/null || echo 'N/A')"
echo "  - Python: $(python3.11 --version 2>/dev/null || python3 --version 2>/dev/null || echo 'N/A')"
echo "  - Chrome: $(google-chrome --version 2>/dev/null | awk '{print $3}' || echo 'N/A')"
echo "  - WireGuard: $(wg --version 2>/dev/null | head -1 || echo 'N/A')"
echo "  - AnyDesk: $(anydesk --version 2>/dev/null || echo '설치됨')"
echo ""
echo "[ 최적화 현황 ]"
echo "  - Snap: $(command -v snap &>/dev/null && echo '설치됨 (제거 필요)' || echo '제거됨')"
echo "  - CUPS: $(systemctl is-active cups.service 2>/dev/null || echo '비활성화')"
echo "  - CPU Governor: $(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null || echo 'N/A')"
echo "  - swappiness: $(cat /proc/sys/vm/swappiness)"
echo "  - vfs_cache_pressure: $(cat /proc/sys/vm/vfs_cache_pressure)"
echo "  - 스왑 파일: $(swapon --show 2>/dev/null | grep swapfile | awk '{print $3}' || echo 'N/A')"
echo "  - sudoers: $(test -f /etc/sudoers.d/${REAL_USER}-automation && echo '설정됨' || echo '미설정')"
echo ""
echo "[ 에이전트 현황 ]"
echo "  - 에이전트 경로: $AGENT_DIR"
echo "  - node_modules: $(test -d $AGENT_DIR/node_modules && echo '설치됨' || echo '미설치')"
echo "  - Patchright: $(test -d $PATCHRIGHT_CACHE && echo '설치됨' || echo '미설치')"
echo ""
echo "[ 헬스체크 ]"
echo "  - Health Agent: $(systemctl is-active health-agent.timer 2>/dev/null || echo '미설치')"
echo "  - Network Recovery: $(systemctl is-active network-recovery.timer 2>/dev/null || echo '미설치')"
echo "  - CLI 명령어: health-status"
echo ""
echo "[ 다음 단계 ]"
echo "  1. 재부팅: sudo reboot"
echo "  2. 에이전트 실행:"
echo "     cd ~/vpn_coupang_v1"
echo "     node index-vpn-multi.js --threads 4 --status"
echo ""
