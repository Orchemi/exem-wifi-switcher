# EXEM Wifi Switcher

사내 Wi-Fi에 접속하면 고정 IP(수동 구성)로, 그 외 네트워크에서는 DHCP로 **자동 전환**하는 macOS 메뉴바 앱.

## ⚠️ 작업 전 반드시 읽을 것

**이 저장소는 GitHub public repo이고, Releases 에 빌드된 앱을 올린다.**
커밋·배포 전에 [`RULES.md`](./RULES.md) 를 반드시 읽어라.

요약하면 — **IP·MAC 등 사내 네트워크 값, 토큰·자격증명, 사내 관련 정보 일체를 커밋하지 마라.**
개발 중 실측한 실제 값을 코드·주석·테스트·문서에 그대로 옮기는 것이 이 프로젝트의 가장 큰 유출 위험이다.
번들에 스크립트가 들어가면서 **배포물도 같은 점검 대상**이 됐다 (RULES.md §4).
Wi-Fi 이름(SSID)은 허용된다. 판단이 서지 않으면 올리지 말고 물어봐라.

작업 지시와 `RULES.md` 가 충돌하면 **`RULES.md` 가 이긴다.**

## 계획 문서

`docs/plan/001-mvp-menubar-toggle.md` 가 아키텍처·제약·의사결정의 단일 출처다. 구현 전에 읽어라.

## 구조

```
Package.swift            # SPM — Xcode 없이 swift build / swift test
Sources/
  WifiSwitcherCore/      # 모델·검증·파싱·설정 (순수 로직)
  ExemWifiSwitcherApp/   # 메뉴바 앱 (AppKit 글루 — 판단은 코어에)
  ExemWifiSwitcherCLI/   # 확인용 CLI (status / profiles / validate / apply)
Tests/
  WifiSwitcherCoreTests/ # 단위 테스트
  shell/                 # 셸 스크립트 검증 (swift test 가 함께 실행)
Resources/icons/         # 메뉴바 템플릿 아이콘 + 앱 아이콘
scripts/                 # apply·save-config(root 실행) · install.sh · uninstall.sh
                         # build-app.sh(번들 조립) · package-release.sh(배포 zip)
config.example.json      # 설정 예시 (실 설정은 /usr/local/etc 에만 둔다)
docs/                    # 계획 문서
```

**앱 번들은 설치 스크립트를 품는다.** `build-app.sh` 가 `install.sh` · `uninstall.sh` ·
`apply` · `save-config` · `config.example.json` 을 `Contents/Resources/scripts/` 에 넣고
**그 뒤에** ad-hoc 서명한다(번들 안 파일이 서명에 봉인된다). 설정 창의 [설치] 버튼은 그 스크립트를
관리자 인증을 거쳐 실행한다.

## 핵심 제약

- **설치 로직의 단일 출처는 `scripts/install.sh` 다. Swift 로 다시 구현하지 마라.**
  앱은 그 스크립트를 번들에 품고 실행할 뿐이다. 두 벌이 되면 터미널로 설치한 사람과
  앱으로 설치한 사람이 다른 시스템을 갖게 되고, 그 차이는 조용히 벌어진다.
  설치 절차를 바꿔야 하면 스크립트를 고친다 — 앱에는 계획을 보여주고 실행하는 코드만 둔다
  (`Sources/WifiSwitcherCore/BundledInstaller.swift` · `Sources/ExemWifiSwitcherApp/InstallerService.swift`)
- **`install.sh` 는 자기 위치 기준으로 원본을 찾는다** — 레포에서도 번들 안에서도 같은 코드가 돈다.
  레포 루트를 기준으로 삼는 코드를 되살리지 마라
- **`install.sh` · `uninstall.sh` 는 root 로도 실행된다** (앱에서 부르는 길). PATH 를 물려받지 않고,
  `--user` 로 대상 계정을 받으며, root 로 들어오면 자기 자리가 안전한지 먼저 확인한다
- **코드서명 인증서 없음** (무료 Apple ID) → ad-hoc 서명. 공증이 없어 내려받은 앱은
  Gatekeeper 에 한 번 막힌다 (README 에 여는 방법을 적어 두었다)
- **로그인 항목은 `SMAppService.mainApp` 이다** — ad-hoc 서명으로 동작한다 (2026-07-29 실측).
  `SMAppService` 가 Developer ID 를 요구한다는 것은 **`.daemon`**(root 데몬) 이야기이고,
  앱 자신을 올리는 `.mainApp` 에는 해당하지 않는다. **`~/Library/LaunchAgents` 에 plist 를 놓는
  옛 방식으로 되돌리지 마라** — 그러면 시스템 설정에서 '로그인 시 열기' 가 아니라
  '백그라운드에서 허용' 에 잡히고, 앱이 상태를 읽을 수 없어 macOS 가 꺼도 체크상자는 켜진 채가 된다
  (`Sources/WifiSwitcherCore/LoginItem.swift` 머리말에 근거를 적어 두었다)
- **Xcode 없이 Command Line Tools만으로 빌드 가능해야 한다** — 소스를 읽고 직접 빌드하려는 사람의 진입장벽이다. SPM + 번들 조립 스크립트
- **`.app` 번들 + `NSLocationWhenInUseUsageDescription` 필수** — 없으면 SSID 조회가 통째로 막힌다 (CoreWLAN만 동작, 위치 권한 필요)
- **`sudoers` NOPASSWD 설계** — 권한 스크립트는 `root:wheel 0755`, 인자 화이트리스트 검증, 설치 시 `visudo -c` 검증 필수

## 커밋

- `<type>: <한글 요약>` (`feat` `fix` `refactor` `docs` `test` `chore` `build`)
- 예: `feat: SSID 감지 자동 전환 추가`
- **AI 관련 문구 금지** (`Co-Authored-By`, `Generated with …` 등 일체)
- 커밋은 **사용자의 명시적 지시가 있을 때만** 한다
