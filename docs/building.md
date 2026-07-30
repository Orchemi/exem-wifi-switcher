[← README 로 돌아가기](../README.md)

# 직접 빌드하기

Releases 의 앱을 쓰지 않고 직접 만드셔도 됩니다. **Xcode는 필요 없습니다.**
Command Line Tools만 있으면 됩니다.

```bash
xcode-select --install     # 아직 없다면
git clone https://github.com/Orchemi/exem-wifi-switcher.git
cd exem-wifi-switcher

./scripts/build-app.sh     # dist/EXEM Wifi Switcher.app 조립 (시스템을 바꾸지 않습니다)
open dist                  # 앱을 응용 프로그램 폴더로 옮기고 실행합니다
```

직접 빌드한 앱은 인터넷에서 내려받은 것이 아니므로 Gatekeeper 경고가 뜨지 않습니다.
다만 다시 빌드할 때마다 서명이 달라지므로 위치 권한은 다시 허용해야 합니다
([업데이트할 때 생기는 일](./guide.md#업데이트할-때-생기는-일)).

전환 권한 설치는 앱의 **[설치]** 버튼으로 하시면 되고, 터미널을 선호하신다면 같은 일을 이렇게 할 수 있습니다.

```bash
./scripts/install.sh              # 하는 일을 먼저 보여주고 확인을 받습니다
./scripts/install.sh --dry-run    # 무엇을 할지만 보기
./scripts/uninstall.sh            # 되돌리기
```

앱의 버튼과 위 명령은 **같은 파일**을 실행합니다. `build-app.sh` 가 이 스크립트들을 앱 번들
(`Contents/Resources/scripts/`)에 넣고 그 뒤에 서명하기 때문입니다.

## 개발

```bash
swift build      # 빌드
swift test       # 단위 테스트 + 셸 스크립트 검증

./scripts/build-app.sh --print-plist     # 빌드 없이 Info.plist 만 보기
./scripts/package-release.sh             # 배포용 zip + SHA-256 (배포 전 점검 포함)
```

- 구조와 제약: [`CLAUDE.md`](../CLAUDE.md)
- 설계와 의사결정: [`docs/plan/001-mvp-menubar-toggle.md`](./plan/001-mvp-menubar-toggle.md)
- **커밋하거나 릴리즈를 올리기 전에 반드시**: [`RULES.md`](../RULES.md).
  사내 IP·MAC 등 네트워크 값을 저장소에도 배포물에도 넣지 않습니다
