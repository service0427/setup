#!/bin/bash
#===============================================================================
# Ubuntu 22.04 자동화 서버 초기 설정 스크립트 (통합 버전)
# - 쿠팡 자동화 에이전트용 최적화 환경 구성
# - WireGuard VPN + Playwright 브라우저 자동화 지원
# - Ubuntu 24는 자동 로그아웃 이슈로 22.04 권장
#
# 사용법: sudo ./setup.sh
# GitHub: https://github.com/service0427/setup
#===============================================================================

set -e  # 에러 발생 시 중단

# 버전 정보
SCRIPT_VERSION="1.1.0"

# 실제 사용자 확인 (sudo로 실행해도 원래 사용자 찾기)
REAL_USER=${SUDO_USER:-$USER}
REAL_HOME=$(eval echo ~$REAL_USER)

# 시스템 정보
TOTAL_RAM_GB=$(free -g | awk '/^Mem:/{print $2}')
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
echo "[1/20] 타임존 설정 (Asia/Seoul)..."
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
echo "[2/20] 기본 패키지 설치..."
sudo apt update && sudo apt upgrade -y
sudo apt install -y \
    curl git openssh-server htop wget gnupg \
    ca-certificates apt-transport-https \
    software-properties-common build-essential \
    im-config  # 한글 입력기 설정용

#---------------------------------------
# 3. Node.js 22.x 설치
#---------------------------------------
echo "[3/20] Node.js 22.x 설치..."
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
echo "[4/20] Python 3.11 설치..."
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
echo "[5/20] Google Chrome 설치..."
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
echo "[6/20] 브라우저 자동화 의존성 설치..."
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
echo "[7/20] WireGuard VPN 설치..."
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
# 8. AnyDesk 설치
#---------------------------------------
echo "[8/20] AnyDesk 설치..."
if ! command -v anydesk &> /dev/null; then
    curl -fsSL https://keys.anydesk.com/repos/DEB-GPG-KEY | sudo tee /etc/apt/keyrings/keys.anydesk.com.asc >/dev/null
    sudo chmod a+r /etc/apt/keyrings/keys.anydesk.com.asc
    echo 'deb [signed-by=/etc/apt/keyrings/keys.anydesk.com.asc] https://deb.anydesk.com all main' | \
        sudo tee /etc/apt/sources.list.d/anydesk-stable.list >/dev/null
    sudo apt update
    sudo apt install -y anydesk
    sudo systemctl enable --now anydesk
    echo "AnyDesk 설치 완료"
else
    echo "AnyDesk 이미 설치됨"
fi

#---------------------------------------
# 9. 한글 입력기 설치 (fcitx5)
#---------------------------------------
echo "[9/20] 한글 입력기 설치..."
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
echo "[10/20] Snap 패키지 제거..."
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
echo "[11/20] CUPS 프린터 서비스 비활성화..."
if systemctl is-active --quiet cups.service 2>/dev/null; then
    sudo systemctl stop cups.service cups-browsed.service 2>/dev/null || true
    sudo systemctl disable cups.service cups-browsed.service 2>/dev/null || true
    echo "CUPS 서비스 비활성화 완료"
else
    echo "CUPS 이미 비활성화됨"
fi

#---------------------------------------
# 12. 자동 업데이트 비활성화
#---------------------------------------
echo "[12/20] 자동 업데이트 비활성화..."
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
echo "[13/20] CPU Governor 설정..."
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
echo "[14/20] 시스템 커널 파라미터 최적화..."

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
echo "[15/20] 스왑 파일 설정..."

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
    # dd 사용 (btrfs/ZFS 호환)
    sudo dd if=/dev/zero of=/swapfile bs=1G count=${SWAP_SIZE%G} status=progress 2>/dev/null || \
    sudo fallocate -l $SWAP_SIZE /swapfile
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
# 16. 자동 로그인 설정
#---------------------------------------
echo "[16/20] 자동 로그인 설정..."
GDM_CONF="/etc/gdm3/custom.conf"
if [ -f "$GDM_CONF" ]; then
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
# 17. VPN 모드용 sudoers 설정
#---------------------------------------
echo "[17/20] VPN 모드용 sudoers 설정..."
SUDOERS_FILE="/etc/sudoers.d/${REAL_USER}-vpn-nopasswd"
if [ ! -f "$SUDOERS_FILE" ]; then
    echo "${REAL_USER} ALL=(ALL) NOPASSWD: /usr/bin/node, /usr/sbin/ip, /sbin/ip, /usr/bin/wg, /usr/bin/wg-quick" | \
        sudo tee "$SUDOERS_FILE" > /dev/null
    sudo chmod 440 "$SUDOERS_FILE"
    echo "VPN sudoers 설정 완료"
else
    echo "VPN sudoers 이미 설정됨"
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
echo "[18/20] GNOME 검색 & Tracker 비활성화..."

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
echo "[19/20] GUI 및 사용자 서비스 최적화..."

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
echo "[20/20] GUI 외관 설정..."

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
echo "  - VPN sudoers: $(test -f /etc/sudoers.d/${REAL_USER}-vpn-nopasswd && echo '설정됨' || echo '미설정')"
echo ""
echo "[ 다음 단계 ]"
echo "  1. 재부팅: sudo reboot"
echo "  2. vpn_coupang_v1 설치:"
echo "     git clone https://github.com/service0427/vpn_coupang_v1.git"
echo "     cd vpn_coupang_v1 && npm install"
echo ""
