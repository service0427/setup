# Ubuntu 22.04 자동화 서버 셋업 스크립트

수십 대의 다양한 하드웨어 사양 서버에서 Ubuntu 22.04 기반 자동화 에이전트 환경을 일관되게 구성하기 위한 스크립트입니다.

## 개요

- **대상 OS**: Ubuntu 22.04 LTS (Jammy Jellyfish)
- **목적**: 쿠팡 자동화 에이전트 + WireGuard VPN 환경 구성
- **특징**:
  - 멱등성(Idempotent) - 여러 번 실행해도 안전
  - vpn_coupang_v1 자동 설치 포함
  - AnyDesk 무인 접속 자동 설정
  - **헬스체크 & 네트워크 자동 복구 시스템 포함**
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
| AnyDesk | Latest | 원격 데스크톱 (무인 접속 설정) |

### 헬스체크 시스템 (Health Agent)
```
/opt/health-agent/
├── health-agent.sh       # 시스템 상태 수집 (1분마다)
├── network-recovery.sh   # 네트워크 자동 복구 (5분마다)
├── health-status         # CLI 상태 확인 도구
├── config.env            # 설정 파일
└── data/
    ├── current.json      # 현재 상태
    └── history.jsonl     # 24시간 히스토리
```

### 수집 정보
| 카테고리 | 항목 |
|----------|------|
| **기본** | hostname, IP, AnyDesk ID, uptime |
| **CPU** | 사용률, 코어 수, 로드 평균, 온도 |
| **메모리** | 총/사용/가용, 스왑 사용률 |
| **디스크** | 총/사용/여유, 사용률 |
| **네트워크** | 인터페이스 상태, 인터넷 연결, DNS, VPN |
| **프로세스** | 에이전트 상태, Chrome 수, Node 수 |
| **서비스** | AnyDesk, SSH, 로그인 실패 횟수 |
| **시스템** | 재부팅 필요 여부, 좀비 프로세스, OOM 발생 |

### 네트워크 자동 복구
```
장애 감지 → 레벨1: 인터페이스 재시작
         → 레벨2: DHCP 갱신
         → 레벨3: DNS 재설정
         → 레벨4: NetworkManager 재시작
         → 레벨5: 시스템 재부팅 (옵션)
```

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

### 3. 상태 확인
```bash
health-status       # 상태 요약
health-status -f    # 전체 정보
health-status -w    # 실시간 모니터링
health-status -l    # 로그 확인
health-status -j    # JSON 출력
```

### 4. 에이전트 실행
```bash
cd ~/vpn_coupang_v1
node index-vpn-multi.js --threads 4 --status
```

## 스크립트 구조

```
setup.sh (v1.3.0)
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
│   ├── [8] AnyDesk 설치 + 무인접속 설정
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
    ├── [22] vpn_coupang_v1 클론 & npm install
    ├── [23] Health Agent 설치
    └── [24] 최종 확인
```

## 완료 리포트 예시

```
========================================
  셋업 완료! v1.3.0
========================================

[ 시스템 정보 ]
  - 호스트명: U22-01
  - RAM: 32GB | CPU: 16 cores
  - 타임존: Asia/Seoul
  - 자동 로그인: 활성화

[ 원격 접속 정보 ]
  - IP: 121.173.150.131
  - AnyDesk ID: 1426417165
  - AnyDesk PW: Tech1324!

[ 설치 현황 ]
  - Node.js: v22.x.x
  - Python: Python 3.11.x
  - Chrome: 131.x.x
  - WireGuard: wireguard-tools v1.x
  - AnyDesk: 설치됨

[ 최적화 현황 ]
  - Snap: 제거됨
  - CUPS: 비활성화
  - CPU Governor: performance
  - swappiness: 10
  - 스왑 파일: 32G

[ 에이전트 현황 ]
  - 에이전트 경로: /home/tech/vpn_coupang_v1
  - node_modules: 설치됨
  - Patchright: 설치됨

[ 헬스체크 ]
  - Health Agent: active
  - Network Recovery: active
  - CLI 명령어: health-status
```

## 중앙 서버 연동 (TODO)

헬스체크 데이터를 중앙 서버로 전송하려면:

1. `/opt/health-agent/config.env` 수정:
```bash
HUB_URL="http://your-hub-server:3000/api/health"
ENABLE_PUSH="true"
```

2. 서비스 재시작:
```bash
sudo systemctl restart health-agent.timer
```

### 중앙 서버 API 스펙 (예정)
```
POST /api/health
Content-Type: application/json

{
  "hostname": "U22-01",
  "timestamp": "2024-01-01T00:00:00Z",
  "basic": { ... },
  "cpu": { ... },
  "memory": { ... },
  "disk": { ... },
  "network": { ... },
  "processes": { ... },
  "services": { ... },
  "health": { ... }
}
```

## 보안 고려사항

이 스크립트는 자동화 에이전트 운영을 위해 일부 보안 설정을 완화합니다:

- **자동 업데이트 비활성화**: 보안 패치가 자동 적용되지 않음
- **화면 잠금 비활성화**: 물리적 접근 시 보안 취약
- **sudo 타임아웃 무제한**: 재부팅 전까지 sudo 비밀번호 불필요
- **다수 명령어 NOPASSWD**: 자주 사용하는 명령어 비밀번호 없이 실행
- **AnyDesk 무인 접속**: 원격 접속 가능

프로덕션 환경에서는 정기적인 수동 업데이트를 권장합니다.

## 파일 구조

```
setup/
├── setup.sh                    # 메인 설치 스크립트
├── README.md                   # 문서
└── health-agent/               # 헬스체크 시스템
    ├── health-agent.sh         # 상태 수집 스크립트
    ├── network-recovery.sh     # 네트워크 복구 스크립트
    ├── health-status           # CLI 도구
    ├── config.env              # 설정 파일
    ├── install.sh              # 독립 설치 스크립트
    ├── health-agent.service    # systemd 서비스
    ├── health-agent.timer      # systemd 타이머 (1분)
    ├── network-recovery.service
    └── network-recovery.timer  # systemd 타이머 (5분)
```

## 라이선스

Private - Internal Use Only
