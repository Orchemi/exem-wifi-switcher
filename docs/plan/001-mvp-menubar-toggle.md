# 001-mvp-menubar-toggle

## 개요

- **제품명**: EXEM Wifi Switcher
- **상태**: Phase 0 완료 / Phase 1 착수 대기
- **생성일**: 2026-07-27

## 배경

사내 Wi-Fi는 IPv4 **수동 구성**(고정 IP)을 쓰고, 집·외부는 **DHCP**를 쓴다. 두 곳을 오갈 때마다 IP·서브넷 마스크·라우터를 손으로 다시 입력해야 한다. 이 왕복을 없앤다.

**최종 지향점은 "사람이 아무것도 누르지 않는 것"이다.** Wi-Fi 이름을 보고 알아서 전환한다.

## 목표

- [x] **SSID 기반 자동 전환** — 사내 Wi-Fi면 고정 IP, 그 외엔 DHCP
- [ ] 메뉴바에서 현재 상태 확인 + 수동 전환 (자동이 어긋났을 때의 손잡이)
- [ ] 전환 시 관리자 암호를 묻지 않음 (설치 시 1회 승인)
- [ ] 온보딩에서 프로필 설정 — 사내에서는 현재 설정을 자동 추출, 사외에서는 직접 입력
- [ ] **GitHub public repo로 공개, 동료가 clone → 설치 스크립트로 바로 설치**
- [ ] 로그인 항목에 `EXEM Wifi Switcher` 로 표시

### 비목표

- **서명·공증된 바이너리 배포(dmg/pkg)** — 유료 Developer Program 가입 의사 없음(사용자 확인).
  대신 **소스 공개 + 각자 빌드** 방식으로 배포한다. 신뢰의 근거를 서명이 아니라 **읽을 수 있는 코드**에 둔다.
- **데스크톱 위젯** — 철회됨. 자동 전환이 되면 누를 일이 없다.
  (참고: Phase 0에서 위젯 경로가 기술적으로 가능함은 확인됐다. 제품 판단으로 접은 것이다.)

## 공개 배포 원칙 (public repo 전제 — 전 Phase에 적용)

이 레포는 **공개된다.** 아래는 협상 대상이 아니다.

- [ ] **실제 사내 네트워크 값을 레포에 커밋하지 마라.** IP·서브넷·라우터·MAC 주소는 사내 인프라 정보다.
      README·예시·테스트 픽스처는 전부 플레이스홀더(`10.0.0.x`, `192.168.x.x` 등 문서용 예시)를 쓴다.
      실제 값은 **각 사용자가 온보딩에서 입력**하고 로컬에만 저장된다.
- [ ] **사용자 설정 파일은 커밋되지 않는다** — `config.json`은 `/usr/local/etc/` 에 있고 레포에는 `config.example.json` 만 둔다.
- [ ] **투명성 문서가 필수다.** 이 도구는 `sudoers`를 수정하고 백그라운드 실행 항목을 등록한다.
      README에 **무엇을·어디에·왜 설치하는지, 어떻게 완전히 제거하는지**를 숨김없이 적는다.
      권한을 요구하는 도구를 공개 배포하면서 그 내역을 감추면 안 된다.
- [ ] 설치 스크립트는 **하는 일을 먼저 출력하고 사용자 확인을 받은 뒤** 진행한다. 조용히 시스템을 바꾸지 마라.

## 설계

### 제약 조건

1. `networksetup -setmanual/-setdhcp` 는 **root 권한**이 필요하다.
2. SSID 조회는 **위치 권한 + `.app` 번들**이 필요하다 (Phase 0에서 실증, 아래 참조).
3. **코드서명 인증서 없음** (무료 Apple ID). ad-hoc 서명 + 레거시 launchd 경로로 간다.
   `SMAppService`(Developer ID 요구)는 쓸 수 없다.
4. **Xcode 16.4 = macOS 15.5 SDK.** macOS 26 전용 API는 쓸 수 없다.

### Phase 0 실증 결과 (확정 — 재조사 불필요)

| 항목 | 결과 |
|---|---|
| SSID 조회 방법 | **CoreWLAN `CWInterface.ssid()` 만 동작.** `ipconfig getsummary`·`system_profiler` 는 `<redacted>` 반환 |
| 전제 조건 | **`.app` 번들 + `NSLocationWhenInUseUsageDescription` + ad-hoc 서명.** 순수 CLI 바이너리는 TCC 귀속이 안 돼 영구 실패 |
| 권한 지속성 | 번들 ID 단위로 유지. **재빌드·재서명해도 재승인 불필요** (개발·재설치에 걸림돌 없음) |
| 권한 범위 | 해당 앱에만 적용. 셸의 `ipconfig` 는 승인 후에도 여전히 가려짐 |
| root 컨텍스트 | 미검증이나 **불필요** — 앱이 SSID를 읽어 전달하므로 root는 알 필요가 없다 |
| 위치 권한 없는 대안 | 라우터 IP / 라우터 MAC(ARP) 는 권한 없이 조회 가능. **BSSID는 위치 권한 필요** |

> **설계적 함의**: SSID 판독은 앱(사용자 세션) 책임, 네트워크 변경은 root 책임으로 나뉜다.

### 접근 방식

```
[EXEM Wifi Switcher.app]  ← 메뉴바 앱 (로그인 시 자동 실행)
   ├ CoreLocation 1회 승인 → CWInterface.ssid() 로 현재 SSID 판독
   ├ SCDynamicStore 로 네트워크 변경 감시
   ├ 판정: SSID가 사내 목록에 있으면 → 고정 IP 프로필 / 아니면 → DHCP
   └ 적용: sudo -n /usr/local/libexec/exem-wifi-switcher/apply <프로필>
                          ↓
   [apply 스크립트 · root:wheel 0755] → networksetup -setmanual / -setdhcp
        ↑ /etc/sudoers.d/exem-wifi-switcher 가 이 경로만 NOPASSWD 로 허용
```

root 헬퍼 데몬과 XPC가 없다. 위젯 샌드박스가 빠지면서 `sudo -n` + sudoers 화이트리스트만으로 충분해졌다.

### 빌드: SPM + 번들 조립 (Xcode 프로젝트 아님)

**동료가 Xcode 없이 Command Line Tools만으로 빌드할 수 있어야 한다.** 공개 배포의 진입장벽을 좌우한다.

- Swift Package Manager로 실행 파일 빌드 → 스크립트로 `.app` 번들 조립(Info.plist·아이콘·ad-hoc 서명)
- Xcode·XcodeGen 의존 제거 (Phase 0의 `project.yml`·`Widget/`·`Helper/`·XPC 코드는 **폐기**)
- `Info.plist`에 **`NSLocationWhenInUseUsageDescription` 필수** — 없으면 SSID 경로가 통째로 막힌다

### 네이밍 (고정)

| 대상 | 값 |
|---|---|
| 제품 표시명 | `EXEM Wifi Switcher` |
| 앱 번들 | `EXEM Wifi Switcher.app` |
| Bundle ID | `com.horbis.exem-wifi-switcher` |
| LaunchAgent Label | `com.horbis.exem-wifi-switcher.agent` |
| GitHub | `Orchemi/exem-wifi-switcher` (public) |
| 로컬 디렉토리 | `tools/exem-wifi-switcher` |
| 권한 스크립트 (전환) | `/usr/local/libexec/exem-wifi-switcher/apply` — sudoers 로 무암호 |
| 권한 스크립트 (저장) | `/usr/local/libexec/exem-wifi-switcher/save-config` — **관리자 인증 필요, sudoers 에 없음** |
| sudoers 파일 | `/etc/sudoers.d/exem-wifi-switcher` |
| 설정 파일 | `/usr/local/etc/exem-wifi-switcher/config.json` (`root:wheel 0644`) |

> **반드시 `.app` 번들로 등록하라.** 맨 실행 파일을 LaunchAgent로 등록하면 로그인 항목에 실행 파일 이름이 그대로 노출된다
> (Phase 0에서 `server` 로 표시되는 사고가 실제로 발생했다). 서명이 없어 "확인되지 않은 개발자" 표기는 남지만, 이름만은 제품명으로 보여야 한다.

### 보안 요구사항 (타협 불가)

sudoers NOPASSWD 설계이므로 아래를 어기면 **로컬 권한 상승 취약점**이 된다. 공개 배포되므로 더욱 엄격히 지킨다.

- [ ] `apply` 스크립트는 **`root:wheel`, `0755`** — 사용자 쓰기 권한이 있으면 안 된다
- [ ] 상위 디렉토리도 root 소유 (심링크 교체 공격 차단)
- [ ] sudoers 항목은 **전체 경로 + 인자 패턴 제한**. 와일드카드로 임의 명령을 열지 마라
- [ ] `apply`는 인자를 화이트리스트 검증 (프로필 이름만 허용, 셸 인젝션 차단)
- [ ] **설정 파일은 `root:wheel 0644`, 설정 디렉터리는 `root:wheel 0755`.**
      이 파일의 값이 root 의 `networksetup` 인자가 되므로, 사용자 권한으로 고칠 수 있으면
      암호 없는 네트워크 재구성이 된다 (위 "뒤집힌 결정" 참조)
- [ ] **저장 경로(`save-config`)를 sudoers 에 넣지 마라.** 넣는 순간 위 잠금이 무의미해진다
- [ ] 상위 디렉터리를 하나씩 명시적으로 만든다. BSD `install -d` 는 중간 디렉터리도 같은
      소유·모드로 만들어, 이 도구와 무관한 시스템 디렉터리(`/usr/local/etc`)를 잘못된 권한으로 남긴다
- [ ] 설치 시 sudoers를 임시 경로에 쓰고 **`visudo -c` 검증 후** 이동.
      검증 없이 잘못된 파일을 놓으면 **`sudo` 자체가 망가진다**

### 디자인 방향 (오너 지시 — 아이콘·UI 전반)

> "깔끔하고 전문적이면서도 미적인 것. **담백하게.**"

- **판단이 갈리면 덜어내는 쪽으로.** 요소를 하나 빼서 나빠지지 않으면 빼는 게 맞다
- "미적"은 화려함이 아니라 **비례·정렬·여백의 정확함**이다. 장식을 더하지 말고 정렬에 공을 들여라
- 색은 최소한으로, 상태 구분에 꼭 필요한 곳에만, 채도는 낮게
- 귀엽거나 소비자 앱처럼 튀는 방향이 아니다 — **실무자가 메뉴바에 상시 띄워두는 전문 도구**의 얼굴
- macOS 시스템 앱의 절제된 톤을 기준점으로 삼는다

### 커밋 컨벤션

- 형식: `<type>: <한글 요약>` (예: `feat: SSID 감지 자동 전환 추가`)
- type: `feat` / `fix` / `refactor` / `docs` / `test` / `chore` / `build`
- 본문도 한글. **AI 관련 문구(`Co-Authored-By`, `Generated with …`)를 어떤 형태로도 남기지 마라**
- 제목은 명령형·간결하게, 마침표 없이

### 의사결정 기록

| 결정 사항 | 선택지 | 결정 | 이유 |
|---|---|---|---|
| UI 형태 | 위젯 / 메뉴바 앱 | **메뉴바 앱** | 자동 전환이면 누를 일이 없어 위젯 가치가 낮고 샌드박스 복잡도만 남음 |
| 권한 경로 | root 헬퍼+XPC / sudoers | **sudoers NOPASSWD** | 샌드박스 제약 소멸로 XPC 불필요. 코드량 대폭 감소 |
| 빌드 | Xcode 프로젝트 / SPM | **SPM + 번들 조립** | 동료가 Xcode 없이 CLT만으로 빌드 가능 → 배포 진입장벽 최소화 |
| 배포 | 바이너리(dmg) / 소스 공개 | **소스 공개** | 서명 불가 상태에서 root 권한 도구를 배포하려면 코드가 감사 가능해야 한다 |
| SSID 판독 위치 | 앱 / root | **앱** | Phase 0 실증: 위치 권한은 `.app` 번들에만 귀속. root는 알 필요 없음 |
| 자동 전환 기본값 | on / off | **on** | 목표가 "사람이 건들 것 없게". 단 전환 시 알림으로 가시성 확보 |
| 설정 파일 권한 | `root:admin 0664` / `root:wheel 0644` | **`root:wheel 0644`** (2026-07-27 뒤집힘) | 아래 "뒤집힌 결정" 참조 |
| 프로필 이름 길이 | 16자 / 확장 | **16자 유지** | `office`·`home` 수준이면 충분. 늘리면 sudoers 고정 패턴 줄 수가 그대로 늘어난다 |
| DNS | IPv4만 / IPv6 포함 | **IPv4만** | 범위 확장의 실익이 없다. 한계를 README에 명시한다 |
| 메뉴바 UI | NSMenu / 커스텀 팝오버 | **NSMenu** | macOS 시스템 앱의 절제된 톤에 부합. 오너 지시("담백하게")와 한 방향이고, 커스텀 UI는 장식이 붙기 쉽다 |
| 설정 저장 권한 경로 | sudoers 확장 / 관리자 인증 / 터미널 안내 | **관리자 인증 1회** (`save-config`) | 저장은 온보딩 1회성이라 인증을 받아도 UX 손해가 작다. sudoers 에 저장 경로를 넣으면 파일을 잠근 의미가 그대로 사라진다 |

### 뒤집힌 결정

#### 설정 파일 권한: `root:admin 0664` → `root:wheel 0644` (2026-07-27, 오너 판단)

**원래 기록** — "admin은 어차피 `apply`를 무암호로 부를 수 있어 **실질적 권한 상승이 없다**.
`apply`가 설정 값을 재검증하므로 임의 명령으로 이어지지 않는다. 반면 0644면 온보딩 저장마다
sudo를 물어야 해 UX 손해가 크다."

**왜 뒤집혔는가 — 비교 대상을 잘못 잡았다.**

원래 논증은 "admin이 `apply`를 부를 수 있다"를 기준선으로 삼았다. 그러나 권한 상승을 재는 기준선은
**이 도구를 설치하기 전의 시스템**이다. 설치 전에는 `networksetup -setdnsservers` 와 `-setmanual`
둘 다 관리자 인증을 요구했다. 설치 후에는 요구하지 않는다. **그 델타가 로컬 권한 상승이다.**

구체적으로, `config.json` 이 사용자 쓰기 가능하면 — **암호를 모르는 채 그 사용자로 실행되는
코드**(내려받은 앱·스크립트·악성코드)가 —

- `dns` 를 공격자 resolver 로 바꿔 root 가 시스템 DNS 를 고정하게 만든다 → 모든 이름 해석 가로채기
- `router` 를 LAN 안 공격자 호스트로 바꾼다 → 기본 게이트웨이 탈취

`apply` 의 재검증은 **형식만** 본다. 형식이 맞는 임의의 IPv4 는 그대로 통과한다.
"임의 명령으로 이어지지 않는다"는 맞지만, 임의 명령이 필요 없다는 것이 요점이다.

**바뀐 것**

- 설정 파일 `root:wheel 0644`, 설정 디렉터리 `root:wheel 0755` (예전 `root:admin 0775` 는
  admin 그룹이 파일을 갈아 끼울 수 있었다). `install.sh` 는 기존 설치의 권한도 맞춰 준다
- 저장은 `save-config` (root:wheel 0755)가 **관리자 인증을 한 번 받고** 처리한다.
  이 경로는 **sudoers 에 넣지 않는다** — 넣으면 잠금이 원위치다
- 전환(`apply`)은 그대로 무암호다. 이 도구의 존재 이유가 거기에 있다
- 비-admin 계정에서는 저장이 불가능하다는 안내는 그대로 유효하다 (인증 창을 띄우기 전에 알린다)

**UX 손해에 대한 원래 우려는 유효하지 않았다.** 저장은 온보딩과 값 변경 때뿐이고, 전환은 인증을
요구하지 않는다. "온보딩 저장마다 sudo" 는 실질적으로 "설치 후 한 번" 이다.

## 작업 단계

### Phase 0: SSID 판독 실증 ✅ 완료

- [x] SSID 조회 방법 조사 및 실측 (CoreWLAN만 동작 확인)
- [x] 위치 권한 필요 조건 확인 (`.app` 번들 + Info.plist 키 + ad-hoc 서명)
- [x] 권한 지속성 확인 (재빌드해도 유지)
- [x] 대안 식별자 조사 (라우터 IP·MAC은 권한 불필요, BSSID는 권한 필요)

### Phase 1: 전환 코어 ✅ 완료 (설치는 미실행 — 사용자가 직접)

- [x] Phase 0 잔재 정리 — `project.yml`·`Widget/`·`Helper/`·`Shared/`·`App/`·XPC 코드 폐기, SPM 구조로 재편
- [x] `NetworkProfile` 모델 (name, mode, ip, subnet, router, dns[], ssids[])
- [x] `networksetup -getinfo` 파싱 → 현재 구성·수동/DHCP 판별
- [x] `apply` 스크립트 (`-setmanual`/`-setdhcp`, 인자 화이트리스트 검증)
- [x] `config.json` 읽기·쓰기 + `config.example.json`
- [x] 설치 스크립트: `apply` 배치(root:wheel 0755) + sudoers(`visudo -c` 검증)
- [x] 제거 스크립트: sudoers·스크립트·설정·로그인 항목 **완전 원복** + 잔여물 검증
- [x] 파싱·상태 판별·인자 검증 단위 테스트 (`swift test` 69건 + 셸 검증 102건)

**Phase 1 결과물**

| 경로 | 역할 |
|---|---|
| `Package.swift` | SPM. `swift build` / `swift test` 로 Xcode 없이 빌드 |
| `Sources/WifiSwitcherCore/` | 모델·검증·파싱·설정. 프로세스를 띄우는 곳은 `SystemCommand.swift` 하나뿐 |
| `Sources/ExemWifiSwitcherCLI/` | `status` / `profiles` / `validate` / `apply` 확인용 CLI |
| `scripts/apply` | root 로 실행되는 유일한 스크립트. 인자는 프로필 이름 1개 |
| `scripts/install.sh` | 하는 일을 먼저 출력 → 확인 → 설치. `--dry-run` 지원 |
| `scripts/uninstall.sh` | 완전 원복 + 잔여물 0 검증. `--dry-run` / `--keep-config` |
| `Tests/shell/apply-tests.sh` | 인젝션 차단·설치 스크립트 검증. `swift test` 가 함께 실행 |

**인자 검증 규칙은 세 곳에 같은 내용이 있다** (다층 방어). 바꿀 때 함께 바꾼다.

1. `Sources/WifiSwitcherCore/ProfileName.swift` — 앱이 명령을 만들기 전
2. `scripts/apply` 의 `validate_profile_name` — root 로 실행된 직후
3. `/etc/sudoers.d/exem-wifi-switcher` 의 인자 패턴 — sudo 가 실행 자체를 거부
   (glob 은 문자 클래스의 반복을 표현할 수 없어 **길이별 고정 패턴 16줄**을 나열한다.
   `*` 를 쓰지 않으므로 공백·`;`·`/` 가 섞인 인자는 sudo 단계에서 걸러진다)

### Phase 2: 메뉴바 앱 ✅ 완료 (설치·등록은 미실행 — 사용자가 직접)

- [x] SPM 실행 파일 + `.app` 번들 조립 스크립트 (Info.plist·아이콘·ad-hoc 서명)
- [x] 메뉴바 아이콘으로 현재 상태 구분 표시 (`manual` / `dhcp` / `error` 템플릿 이미지, 없으면 SF Symbols)
- [x] 온보딩: 설치 **안내** — 앱은 sudo 를 대신 실행하지 않는다. 미설치 상태와 해결 방법을 메뉴·설정 창에 명시
      (위치 권한 요청은 SSID 를 실제로 읽는 Phase 3 로 미룬다. 권한 설명 키는 Info.plist 에 이미 있다)
- [x] **온보딩 분기** — 현재 수동이면 현재 값에서 프로필 추출 제안 / DHCP면 직접 입력 폼
- [x] 입력 검증 (IP·서브넷·라우터 형식, 라우터가 서브넷 안에 있는지) — `NetworkProfile.validate()` 재사용, 칸별 사유 표시
- [x] 메뉴에서 수동 전환 (전환 중·실패 상태 표시 포함)
- [ ] 자동 전환 on/off 토글 — **Phase 3 로 미룸.** 동작하지 않는 토글을 미리 두면 거짓말이 된다
- [x] 로그인 항목 등록 경로 (`.app` 번들만 등록, 설정 창에서 켜고 끔)
      — 실제 등록·시스템 설정 표시명 확인은 사용자가 직접 (에이전트는 시스템을 바꾸지 않는다)

**Phase 2 결과물**

| 경로 | 역할 |
|---|---|
| `scripts/build-app.sh` | SPM 빌드 → `.app` 조립(Info.plist·아이콘·ad-hoc 서명). `--print-plist` 는 빌드 없이 plist 만 출력 |
| `Sources/ExemWifiSwitcherApp/` | 메뉴바 앱. AppKit 글루만 있고 판단은 전부 코어에 있다 |
| `Sources/WifiSwitcherCore/StatusModel.swift` | 관측값 → 아이콘·머리말·전환 가능 여부. 시스템 호출 없음 |
| `Sources/WifiSwitcherCore/ProfileDraft.swift` | 온보딩 입력 다듬기·칸별 오류 배정·설정 조립 |
| `Sources/WifiSwitcherCore/LoginItem.swift` | LaunchAgent plist 생성·등록·해제 (`.app` 번들이 아니면 거부) |

**Phase 3 가 얹힐 자리**

- 상태 갱신: `StatusItemController.refresh()` — 지금은 30초 주기 + 메뉴 열 때. `SCDynamicStore` 감시가 들어오면 주기 확인은 보조로 물러난다
- 전환 실행: `StatusItemController.apply(profileName:userInitiated:)` — 자동 전환은 `userInitiated: false` 로 부르면 실패해도 창을 띄우지 않고 아이콘·메뉴에만 남는다
- SSID 목록: `NetworkProfile.ssids` 는 이미 있고 온보딩이 덮어쓰지 않는다 (`OnboardingSetup.makeConfig` 가 보존)

### Phase 3: SSID 자동 전환 ✅ 완료 (설치·권한 승인은 미실행 — 사용자가 직접)

- [x] CoreWLAN SSID 판독 + 위치 권한 미승인 시 안내 처리
- [x] `SCDynamicStore` 네트워크 변경 감시 (주기 확인은 60초 보조로 물러남)
- [x] 사내 SSID 목록(설정 가능, 기본값 제공) 매칭 → 프로필 적용
- [x] **무한 루프 방지** — 디바운스 + 현재 상태와 같으면 no-op + 정착 대기 + 실패 백오프 + 중단
- [x] 전환 시 알림 (모르는 사이 IP가 바뀌지 않도록)
- [x] 실패 시 폴백 — 전환 실패가 기존 연결을 망가뜨리지 않을 것
- [x] 자동 전환 on/off 토글 (Phase 2 에서 미룬 항목). 기본값 켜짐, `UserDefaults` 에 보관

**Phase 3 결과물**

| 경로 | 역할 |
|---|---|
| `Sources/WifiSwitcherCore/SSIDReading.swift` | SSID 판독 결과 6갈래. "못 읽었다" 를 이유별로 나눠 사용자에게 할 말을 남긴다 |
| `Sources/WifiSwitcherCore/AutoSwitch.swift` | **판정의 전부.** 관측값 + 지난 시도 기록 → 전환할지, 안 한다면 왜인지. 시스템 호출 없음 |
| `Sources/WifiSwitcherCore/AutoSwitchPreferences.swift` | on/off 보관 (기본 켜짐). 저장소를 주입할 수 있어 테스트가 시스템을 건드리지 않는다 |
| `Sources/WifiSwitcherCore/SwitchAnnouncement.swift` | 알림 문구. 사실만, 느낌표 없이 |
| `Sources/ExemWifiSwitcherApp/WiFiSSIDReader.swift` | CoreWLAN `CWInterface.ssid()` 를 부르는 유일한 자리 |
| `Sources/ExemWifiSwitcherApp/LocationAuthority.swift` | 위치 권한 요청·감시 (`CLLocationManager`) |
| `Sources/ExemWifiSwitcherApp/NetworkChangeMonitor.swift` | `SCDynamicStore` 감시 + 디바운스(조용해지면 1.2초, 최대 6초) |
| `Sources/ExemWifiSwitcherApp/SwitchNotifier.swift` | 알림 전달. 번들 밖이거나 권한이 없으면 조용히 물러난다 |
| `Sources/ExemWifiSwitcherApp/Diagnostics.swift` | `--diagnose` — 메뉴바가 안 보일 때의 상태 확인 통로. **주소 값은 찍지 않는다** |

**무한 루프를 막는 다섯 겹** (전부 `AutoSwitchPolicyTests` 가 지킨다)

1. **디바운스** — 한 번 갈아타는 동안 몰려오는 SCDynamicStore 이벤트를 하나로 묶는다
2. **no-op** — 현재 구성이 이미 목표면 명령을 내지 않는다. 전환이 이벤트를 낳고 그 이벤트가 다시 전환을 부르는 고리를 여기서 끊는다.
   **판정에는 IP·서브넷·라우터와 DNS 가 함께 들어간다** — IP 만 보면 사내 DNS 가 남은 채 밖에서 도는 구성을 정상으로 본다.
   다만 DNS 를 **읽지 못한 것**은 '다르다' 가 아니라 판정 불가다 (그렇게 다루면 조회 실패마다 무한 재적용이 된다)
3. **정착 대기** — 적용 직후 8초는 `-getinfo` 가 옛 값을 보여줄 수 있으므로 다시 걸지 않는다.
   시도했는데 결과가 기록되지 않은 경우도 같은 시간만큼 잡아 둔다
4. **헛도는 전환 감지** — 성공 이후 **한 번도** 목표 구성을 관측하지 못했으면 재적용을 멈추고 메뉴에 남긴다.
   반대로 한 번이라도 정착을 관측했다면 그 기록을 정산하고(`recordSettled`), 나중에 구성이 풀렸을 때 **다시 적용한다** —
   정산이 없으면 "적용은 됐었는데 나중에 풀린" 상황이 "효과가 없다" 로 굳어 그 Wi-Fi 를 떠날 때까지 멈춘다
5. **실패 백오프와 중단** — 10초 → 30초 → 90초 → 270초(상한 270초 — 5회째에 멈추므로 그보다 큰 상한은 쓰이지 않는다),
   5회 연속 실패하면 그 Wi-Fi 에서는 멈춘다

**멈춘 상태에서 빠져나오는 길이 Wi-Fi 변경 하나여서는 안 된다.** 자동 전환을 껐다 켜거나 메뉴의 **"지금 다시 시도"**
를 누르면 실패 기록을 지우고 그 자리에서 다시 건다 (원인을 고친 뒤 — 예: `install.sh` 재실행 — 앱을 다시 띄우지 않아도 되게).

**판단 근거가 없으면 아무것도 하지 않는다.** 위치 권한이 없거나 Wi-Fi 가 꺼져 있어 SSID 를 읽지 못하면 구성을 건드리지 않는다.
"모르면 DHCP" 로 두면 사내에서 인터넷이 끊긴다.

**사용자의 손이 자동보다 우선한다.** 메뉴에서 직접 고른 프로필은 그 Wi-Fi 에 머무는 동안 자동 전환이 되돌리지 않는다.
전환 중에 누른 프로필도 버리지 않고 지금 전환이 끝난 뒤 이어서 적용한다.

**관측은 한 번에 하나만 돈다.** 갱신을 부르는 문이 넷(주기 확인·SCDynamicStore·메뉴 열기·위치 권한 변경)인데
`probe.read` 는 수백 ms 가 걸린다. 겹쳐 돌면 늦게 시작한 읽기가 먼저 끝나 **낡은 관측이 새 값을 덮어쓰고**
그 값으로 전환을 판정한다. `StatusItemController` 가 요청을 하나로 묶어 직렬화한다.

**적용은 DNS 부터 한다.** IPv4 를 먼저 걸면 `-setdnsservers` 가 실패했을 때 'IP 는 새 값, DNS 는 옛 값' 인
절반짜리 구성이 남고, 그 상태는 IP 만 보면 목표와 같아 보인다. DNS 를 먼저 걸면 실패 시 아무것도 바꾸지 않은 채 멈추고,
IPv4 에서 실패하면 DNS 를 이전 값으로 되돌린다.

### Phase 3 미해결: 메뉴바 아이콘이 그려지지 않는 문제

Phase 2 에서 발견한 문제가 그대로 남아 있다. `NSStatusItem` 이 `isVisible=true` 이고 좌표까지 보고하는데 화면에 나타나지 않는다.

코드 쪽 흔한 원인은 전부 확인했고 **이상이 없다**.

| 점검 | 결과 |
|---|---|
| `NSStatusItem` 강한 참조 | `StatusItemController` → `AppDelegate` → 최상위 `delegate` 로 유지됨 |
| `setActivationPolicy(.accessory)` | `main.swift` 에 있음 |
| `LSUIElement` | Info.plist 에 `true` (테스트가 검사) |
| 아이콘 이미지 | 번들에 6개, 16×16 / 32×32. 크기 0 아님 |
| 첫 렌더 시점 | `applicationDidFinishLaunching` 이후 |

환경 요인이 유력하다 — **노치가 있는 MacBook Pro(Mac15,6) + 기존 상태 아이콘 12개 남짓**이면 새 항목이 노치 뒤로 밀려
그려지지 않는 알려진 동작에 부합한다. Phase 2 에서 표준 최소 예제도 같은 결과였다.
**확정하려면 다른 Mac(또는 외부 모니터)에서 확인해야 한다.** 여기서 더 파지 않는다.

대신 메뉴바가 유일한 출입구가 되지 않게 했다.

- `--diagnose` — 메뉴바 없이 상태 확인 (SSID 판독 여부·자동 전환 판정까지)
- 앱을 한 번 더 실행하면 이미 떠 있는 앱의 설정 창이 열린다 (`DistributedNotificationCenter`)
- CLI 로 상태 확인·수동 전환 (SSID 판독은 번들 앱에서만 가능하다)
- 아이콘 이미지를 못 찾으면 폭 0 항목이 되지 않도록 글자로 대체
- 사용자가 취할 수 있는 조치를 README "문제 해결" 에 기록

### Phase 4: 공개 배포 준비

- [x] `README.md` (한글) — 무엇을 하는 도구인지, 설치·제거, **설치되는 항목 전체 목록과 이유**, 문제 해결
      (Phase 3 에서 먼저 작성 — RULES.md §5 가 요구하는 투명성 문서다. 스크린샷은 남은 항목)
- [ ] `README.md` 스크린샷 (메뉴바 표시 문제가 풀린 뒤)
- [ ] `docs/INSTALL.md` — 사전 요구사항(CLT), 단계별 설치, 위치 권한 승인 안내, 문제 해결
- [x] `LICENSE` (MIT)
- [ ] `.gitignore` — 빌드 산출물, 로컬 설정, `.DS_Store`, 아이콘 생성 중간물
- [ ] **커밋 전 실제 사내 IP·MAC 유출 여부 전수 점검** (`git grep`)
- [ ] `scripts/install.sh` — clone 후 한 줄 설치, 하는 일을 먼저 고지
- [ ] `scripts/uninstall.sh` — 완전 원복
- [ ] GitHub Actions: 빌드 검증 (선택)
- [ ] macOS 업데이트로 설정이 풀렸을 때 복구 절차를 README에 기록

## 진행 로그

| 날짜 | 내용 | 비고 |
|---|---|---|
| 2026-07-27 | 요구 수집·아키텍처 확정 | 초안: 위젯 + root 헬퍼 + XPC |
| 2026-07-27 | 위젯 철회 → 메뉴바 앱 | XPC·App Group·샌드박스 제약 소멸, sudoers 방식으로 단순화 |
| 2026-07-27 | 네이밍 확정 | 스파이크가 로그인 항목에 `server` 로 노출된 사고 반영 |
| 2026-07-27 | **Phase 0 완료 — SSID 판독 실증 성공** | `.app` 번들 + 위치 권한이면 읽힘. 자동 전환 전제 성립 |
| 2026-07-27 | **공개 배포로 방침 전환** | 소스 공개 + 각자 빌드. SPM 전환으로 Xcode 의존 제거 |
| 2026-07-27 | **Phase 1 완료 — 전환 코어** | SPM 재편, 검증·파싱·설정, `apply`/설치/제거 스크립트, 테스트 171건 |
| 2026-07-27 | 설치는 사용자가 직접 실행 | 에이전트는 시스템을 바꾸지 않는다 — 스크립트만 만들고 `--dry-run` 으로만 검증 |
| 2026-07-27 | **Phase 2 완료 — 메뉴바 앱** | `.app` 조립 스크립트, NSMenu, 온보딩(현재 구성 분기), 로그인 항목. 테스트 114건 |
| 2026-07-27 | 설정 저장은 **제자리 쓰기**로 | 파일을 갈아 끼우면 소유자가 사용자로 바뀌어 root 로 도는 `apply` 가 설정을 거부한다 (아래 참고) |
| 2026-07-27 | 자동 전환 토글을 메뉴에서 뺌 | 눌러도 아무 일이 없는 항목은 거짓말이 된다. Phase 3 에서 동작과 함께 넣는다 |
| 2026-07-27 | **Phase 3 완료 — SSID 자동 전환** | CoreWLAN 판독 + SCDynamicStore 감시 + 5겹 루프 방지 + 알림. 테스트 163건 |
| 2026-07-27 | SSID 를 못 읽으면 **아무것도 하지 않는다** | "모르면 DHCP" 는 사내에서 인터넷을 끊는다. 판단 근거가 없으면 현상 유지가 안전하다 |
| 2026-07-27 | 수동 선택이 자동보다 우선 | 자동이 사용자의 손을 곧바로 되돌리면 도구가 아니라 방해가 된다. Wi-Fi 가 바뀌면 자동으로 복귀 |
| 2026-07-27 | 메뉴바 아이콘 미표시 — 코드 이상 없음, 환경 요인으로 결론 | 노치 + 상태 항목 과다. 대신 `--diagnose`·재실행·CLI 로 출입구를 늘림 |
| 2026-07-27 | **설정 파일 권한 결정 뒤집힘** — `root:admin 0664` → `root:wheel 0644` | 기준선을 "admin이 apply를 부를 수 있다" 가 아니라 **설치 전 시스템**으로 잡아야 했다. 저장은 관리자 인증 1회(`save-config`), 전환은 그대로 무암호 |
| 2026-07-27 | **고정 IP 프로필에 DNS 필수** | 비우면 `apply` 가 시스템 DNS 를 지워 이름 해석이 끊긴다. 창의 안내 문구가 오히려 비우도록 유도하고 있었다. 세 계층(검증·초안·`apply`)에서 모두 막는다 |
| 2026-07-27 | DNS "읽지 못함" 과 "없음" 을 나눔 | 뭉개면 조회 실패 상태에서 빈 DNS 를 자기 값인 줄 알고 저장하게 된다 |
| 2026-07-27 | `apply` 가 설정 파일을 한 번만 읽도록 | 경로를 stat 한 뒤 plutil 로 수십 번 다시 여는 구조는 검사와 사용 사이가 벌어진다(TOCTOU). fd 를 잡고 `/dev/fd` 로 그 fd 를 검사한 뒤 사본에서만 파싱한다 |
| 2026-07-27 | 프로필 이름 규칙 **3계층 교차 테스트** 도입 | 패턴 개수만 세는 검사는 한 계층만 넓어진 드리프트를 못 잡는다. 같은 입력을 세 계층에 먹여 판정 일치를 대조한다 |
| 2026-07-27 | **정착을 관측하면 시도 기록을 정산한다** | 성공 기록이 지워지지 않아, 나중에 구성이 풀리면 '적용했는데 효과가 없다' 로 그 Wi-Fi 에서 영영 멈췄다. 사용자가 시스템 설정에서 IP 를 만지거나 macOS 업데이트가 되돌리면 곧바로 걸리는 길이다 |
| 2026-07-27 | **DNS 를 '이미 적용됨' 판정에 넣음** | 주석은 "DNS 는 따로 비교" 라고 적어 두었지만 그런 코드가 없었다. IP 만 맞으면 통과해, 사내 DNS 를 문 채 집에서 도는 구성이 정상으로 판정됐다. 읽지 못한 경우는 '다르다' 가 아니라 **판정 불가**로 다룬다 |
| 2026-07-27 | 적용 순서를 **DNS → IPv4** 로 뒤집고 되돌리기 추가 | 부분 적용이 남으면 IP 만 보고 '이미 적용됨' 으로 굳어 DNS 가 영영 고쳐지지 않았다. DNS 를 먼저 걸면 실패해도 손대기 전 그대로다 |
| 2026-07-27 | 멈춤에서 빠져나오는 손잡이 (`clearAttempts`) | 백오프·중단이 Wi-Fi 변경으로만 풀렸다. 사내에서 권한이 풀려 5회 실패한 뒤 `install.sh` 를 다시 실행해도 자동 전환은 멈춘 채였다. 토글 on · "지금 다시 시도" 로 연다 |
| 2026-07-27 | 관측 갱신을 **직렬화** | 갱신 진입점이 넷인데 in-flight 가드가 없어, 늦게 시작한 읽기가 먼저 끝나면 낡은 관측이 새 값을 덮어썼다. 최악은 Wi-Fi 를 갈아타는 순간 낡은 값으로 판정하는 것 |
| 2026-07-27 | 알림 권한 거부를 메뉴에 상시 표기 | 거부되면 전환이 **완전히 무성**이 된다. 메뉴바 아이콘 미표시와 겹치면 사용자가 알 통로가 없다. 승인 답을 기다리는 동안의 알림은 버리지 않고 들고 있다가 보낸다 |
| 2026-07-27 | 백오프 상한 300초 → 270초 | 5회째에 멈추므로 300초는 **도달 불가능한 숫자**였다. 문서와 코드가 갈라지는 자리를 없앤다 |

## 참고

- 환경: macOS 26.5.2, Xcode 16.4(macOS 15.5 SDK), Swift 6.1.2
- 실제 사내 네트워크 값은 **이 문서에 기록하지 않는다** (공개 레포)
- **설정 파일 소유권**: 설치된 `config.json` 은 `root:wheel 0644` 다. `apply` 는 root 소유가 아니거나
  root 외에 쓰기가 열린 설정을 거부한다(심링크·교체 공격 차단). 앱은 이 파일에 직접 쓰지 못한다 —
  검증을 통과한 내용을 사용자 전용 임시 파일(0700 디렉터리 / 0600 파일)에 놓고,
  `do shell script … with administrator privileges` 로 **관리자 인증을 한 번 받아** `save-config` 를
  root 로 실행한다. `save-config` 가 내용을 다시 확인하고 `install(1)` 로 갈아 끼운다.
  인증을 취소하거나 실패하면 이전 설정이 그대로 남고, 준비해 둔 임시 파일 경로를 그대로 알려
  터미널에서 이어서 저장할 수 있게 한다. 관리자 그룹이 아닌 계정에서는 **인증 창을 띄우기 전에** 알린다.
- Phase 0 부산물: 검증용 임시 앱에 부여된 위치 권한은 `tccutil reset Location <bundle-id>` 로 정리 가능
