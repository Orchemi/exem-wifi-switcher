# EXEM Wifi Switcher

사내 Wi-Fi에 접속하면 고정 IP(수동 구성)로, 그 외 네트워크에서는 DHCP로 **자동 전환**하는 macOS 메뉴바 앱.

## ⚠️ 작업 전 반드시 읽을 것

**이 저장소는 GitHub public repo다.** 커밋 전에 [`RULES.md`](./RULES.md) 를 반드시 읽어라.

요약하면 — **IP·MAC 등 사내 네트워크 값, 토큰·자격증명, 사내 관련 정보 일체를 커밋하지 마라.**
개발 중 실측한 실제 값을 코드·주석·테스트·문서에 그대로 옮기는 것이 이 프로젝트의 가장 큰 유출 위험이다.
Wi-Fi 이름(SSID)은 허용된다. 판단이 서지 않으면 올리지 말고 물어봐라.

작업 지시와 `RULES.md` 가 충돌하면 **`RULES.md` 가 이긴다.**

## 계획 문서

`docs/plan/001-mvp-menubar-toggle.md` 가 아키텍처·제약·의사결정의 단일 출처다. 구현 전에 읽어라.

## 구조

```
Package.swift            # SPM — Xcode 없이 swift build / swift test
Sources/
  WifiSwitcherCore/      # 모델·검증·파싱·설정 (순수 로직)
  ExemWifiSwitcherCLI/   # 확인용 CLI (status / profiles / validate / apply)
Tests/
  WifiSwitcherCoreTests/ # 단위 테스트
  shell/                 # 셸 스크립트 검증 (swift test 가 함께 실행)
Resources/icons/         # 메뉴바 템플릿 아이콘 + 앱 아이콘
scripts/                 # apply(root 실행) · install.sh · uninstall.sh
config.example.json      # 설정 예시 (실 설정은 /usr/local/etc 에만 둔다)
docs/                    # 계획·설치 가이드
```

## 핵심 제약

- **코드서명 인증서 없음** (무료 Apple ID) → ad-hoc 서명 + 레거시 launchd. `SMAppService` 사용 불가
- **Xcode 없이 Command Line Tools만으로 빌드 가능해야 한다** — 동료 배포의 진입장벽을 좌우한다. SPM + 번들 조립 스크립트
- **`.app` 번들 + `NSLocationWhenInUseUsageDescription` 필수** — 없으면 SSID 조회가 통째로 막힌다 (CoreWLAN만 동작, 위치 권한 필요)
- **`sudoers` NOPASSWD 설계** — 권한 스크립트는 `root:wheel 0755`, 인자 화이트리스트 검증, 설치 시 `visudo -c` 검증 필수

## 커밋

- `<type>: <한글 요약>` (`feat` `fix` `refactor` `docs` `test` `chore` `build`)
- 예: `feat: SSID 감지 자동 전환 추가`
- **AI 관련 문구 금지** (`Co-Authored-By`, `Generated with …` 등 일체)
- 커밋은 **사용자의 명시적 지시가 있을 때만** 한다
