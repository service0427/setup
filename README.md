# Ubuntu 22.04 자동화 서버 셋업 스크립트

수십 대의 다양한 하드웨어 사양 서버에서 Ubuntu 22.04 기반 자동화 에이전트 환경을 일관되게 구성하기 위한 스크립트입니다.

## 개요

- **대상 OS**: Ubuntu 22.04 LTS (Jammy Jellyfish)
- **목적**: 쿠팡 자동화 에이전트 + WireGuard VPN 환경 구성
- **특징**:
  - 멱등성(Idempotent) - 여러 번 실행해도 안전
  - **vpn_coupang_v1 자동 설치 포함**
  - sudo 비밀번호 한 번만 입력 (재부팅 전까지 유효)

> **Note**: Ubuntu 24.04는 자동 로그아웃 이슈로 22.04 권장

## 한 줄 설치

```bash
git clone https://github.com/service0427/setup.git && cd setup && ./setup.sh
```

## 설치 항목

### 런타임 & 도구
| 항목 | 버전 | 용도 |
|------|------|------|
| Node.js | 22.x | 자동화 에이전트 실행 |
| Python | 3.11 | 스크립트 및 도구 |
| Google Chrome | Latest | 브라우저 자동화 |
| WireGuard | Latest | VPN 터널링 |
| Patchright | Latest | 브라우저 자동화 (Playwright fork) |
| AnyDesk | Latest | 원격 데스크톱 |

### 자동 설치되는 에이전트
```
~/vpn_coupang_v1/
├── node_modules/     # npm 의존성
├── index-vpn-multi.js # 메인 실행 파일
└── ...
```

### 시스템 최적화
| 설정 | 값 | 설명 |
|------|-----|------|
| CPU Governor | performance | 최대 성능 모드 |
| vm.swappiness | 10 | RAM 우선 사용 |
| vm.vfs_cache_pressure | 50 | 파일 캐시 유지 |
| 파일 디스크립터 | 65536 | Chrome 다중 인스턴스 |
| ip_forward | 1 | VPN 네트워크 |
| sudo timeout | -1 | 재부팅 전까지 유효 |

### 스왑 파일 (RAM 기반 동적 크기)
| RAM | 스왑 크기 |
|-----|-----------|
| ~8GB | 16GB |
| ~16GB | 24GB |
| ~32GB | 32GB |
| 32GB+ | 48GB |

### sudoers 설정 (비밀번호 없이 실행 가능)
```
/usr/bin/node, /usr/bin/npm, /usr/bin/npx
/usr/sbin/ip, /sbin/ip, /usr/bin/wg, /usr/bin/wg-quick
/usr/bin/systemctl, /usr/bin/apt, /usr/bin/apt-get
/usr/sbin/reboot, /usr/sbin/shutdown
/usr/bin/tee, /usr/bin/kill, /usr/bin/pkill
/usr/bin/chmod, /usr/bin/chown, /usr/bin/mkdir, /usr/bin/rm
/usr/sbin/modprobe
```

### 비활성화 항목
- Snap 패키지 (완전 제거)
- CUPS 프린터 서비스
- 자동 업데이트
- GNOME Tracker
- Evolution 데이터 서버
- 시스템 알림
- 화면 잠금

## 사용법

### 1. 스크립트 다운로드 및 실행
```bash
git clone https://github.com/service0427/setup.git
cd setup
./setup.sh
```

### 2. 재부팅
```bash
sudo reboot
```

### 3. 에이전트 실행
```bash
cd ~/vpn_coupang_v1
node index-vpn-multi.js --threads 4 --status
```

## 스크립트 구조

```
setup.sh (v1.2.0)
├── sudo 타임아웃 설정 (재부팅 전까지 유효)
│
├── PART 1: 시스템 설정 (root 권한)
│   ├── [1] 타임존 설정 (Asia/Seoul)
│   ├── [2] 기본 패키지 설치
│   ├── [3] Node.js 22.x 설치
│   ├── [4] Python 3.11 설치
│   ├── [5] Google Chrome 설치
│   ├── [6] 브라우저 자동화 의존성
│   ├── [7] WireGuard VPN 설치
│   ├── [8] AnyDesk 설치
│   ├── [9] 한글 입력기 (fcitx5)
│   ├── [10] Snap 제거
│   ├── [11] CUPS 비활성화
│   ├── [12] 자동 업데이트 비활성화
│   ├── [13] CPU Governor 설정
│   ├── [14] 커널 파라미터 최적화
│   ├── [15] 스왑 파일 설정
│   ├── [16] 자동 로그인 설정
│   └── [17] sudoers 설정
│
├── PART 2: 사용자 설정 (user 권한)
│   ├── [18] GNOME Tracker 비활성화
│   ├── [19] 사용자 서비스 최적화
│   └── [20] GUI 외관 설정
│
└── PART 3: 에이전트 설치
    ├── [21] Patchright 브라우저 설치
    └── [22] vpn_coupang_v1 클론 & npm install
```

## 주요 변경사항 (v1.2.0)

### 통합된 기능
- vpn_coupang_v1 자동 클론 및 npm install
- Patchright 브라우저 바이너리 자동 설치
- sudo 타임아웃 영구 해제 (재부팅 전까지)

### 확장된 sudoers
- node, npm, npx
- ip, wg, wg-quick (VPN)
- systemctl, apt, apt-get
- reboot, shutdown
- chmod, chown, mkdir, rm
- kill, pkill, tee, modprobe

## 보안 고려사항

이 스크립트는 자동화 에이전트 운영을 위해 일부 보안 설정을 완화합니다:

- **자동 업데이트 비활성화**: 보안 패치가 자동 적용되지 않음
- **화면 잠금 비활성화**: 물리적 접근 시 보안 취약
- **sudo 타임아웃 무제한**: 재부팅 전까지 sudo 비밀번호 불필요
- **다수 명령어 NOPASSWD**: 자주 사용하는 명령어 비밀번호 없이 실행

프로덕션 환경에서는 정기적인 수동 업데이트를 권장합니다.

## 요구사항

- Ubuntu 22.04 LTS Desktop
- 인터넷 연결
- sudo 권한

## 문제 해결

### GUI 환경 없이 실행 시
데스크톱 환경이 없는 서버에서는 GNOME 관련 설정(gsettings)이 무시됩니다.

### 브라우저가 실행되지 않을 때
```bash
# X11 환경 확인
echo $DISPLAY

# 의존성 재설치
npx patchright install-deps chromium
```

### WireGuard 커널 모듈 로드 실패
```bash
# 수동 로드
sudo modprobe wireguard

# 커널 버전 확인 (5.6+ 권장)
uname -r
```

### 에이전트 업데이트
```bash
cd ~/vpn_coupang_v1
git pull
npm install
```

## 라이선스

Private - Internal Use Only
