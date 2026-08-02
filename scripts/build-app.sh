#!/bin/bash
# ---------------------------------------------------------------------------
# build-app.sh — SPM 으로 빌드한 실행 파일을 '.app' 번들로 조립한다.
#
# **Xcode 없이 Command Line Tools 만으로 동작한다.** 쓰는 도구는 네 개뿐이다.
#   swift     실행 파일 빌드
#   plutil    Info.plist 문법 검증
#   codesign  서명 (ad-hoc 또는 Developer ID)
#   ditto/cp  파일 복사
#
# 왜 번들이어야 하는가
#   1. SSID 조회에 위치 권한이 필요하고, 그 권한은 '.app' 번들 + Info.plist 키 +
#      서명이 있어야만 부여된다 (Phase 0 에서 실증). 맨 실행 파일은 영구 실패한다.
#   2. 로그인 항목에 제품명으로 표시되려면 번들이어야 한다.
#
# 서명은 두 갈래이고, 갈림길은 환경변수 `SIGN_IDENTITY` 하나다. **기본은 ad-hoc 이다.**
# 인증서가 없어도(또는 나중에 없어져도) 환경변수를 주지 않으면 아래 첫째 길로 그대로 돌아간다.
#
# 1) `SIGN_IDENTITY` 가 비어 있으면 ad-hoc(`--sign -`) 서명이다. 유료 인증서가 없어
#    "확인되지 않은 개발자" 표기가 남고, **다시 빌드할 때마다 위치 권한이 풀린다** (2026-07-29 실기 확인).
#    ad-hoc 서명에는 고정된 신원이 없어 TCC 가 코드 해시로 앱을 가른다. 코드가 한 글자만 바뀌어도
#    해시가 달라지므로 macOS 는 **이름만 같은 다른 앱**으로 보고 위치 권한을 다시 묻는다.
#    알림 권한·로그인 항목은 번들 식별자에 매여 있어 남고, 전환 권한·설정은 앱 밖(/usr/local)에 있어
#    영향이 없다. 즉 **다시 물어야 하는 것은 위치 권한 하나뿐이다.**
#
# 2) `SIGN_IDENTITY` 에 Developer ID 인증서 이름을 주면 그것으로 서명하고 hardened runtime
#    (`--options runtime`)과 보안 타임스탬프를 켠다. 신원이 인증서에 고정되므로 코드가 바뀌어도
#    macOS 는 같은 앱으로 보고, **위치 권한이 유지된다.** hardened runtime 은 공증의 전제 조건이라
#    공증(scripts/package-release.sh)으로 가려면 이 길이어야 한다.
#    **인증서 이름은 저장소에 적지 않는다.** 빌드할 때 환경변수로만 준다.
#
# 두 길 사이를 오가는 그 한 번은 어느 쪽이든 위치 권한이 풀린다. 신원 자체가 달라지기 때문이다.
#
# 서명 계획만 미리 보려면 `--print-signing` 을 쓴다. 출력 형식은 다음 줄들로 고정이고,
# 테스트와 사람이 같은 것을 본다 (인증서 이름은 사람 실명이 들어가는 자리라 찍지 않는다).
#   mode=adhoc|developer-id
#   hardened-runtime=yes|no
#   timestamp=yes|no
#   identifier=<번들 식별자>
#
# 번들은 설치 스크립트를 함께 품는다 (Contents/Resources/scripts/).
#   앱의 [설치] 버튼이 관리자 인증을 받아 **그 스크립트를 그대로 실행**한다.
#   설치 로직을 Swift 로 다시 구현하지 않는 이유가 여기에 있다 — 두 벌이 되면 반드시 어긋난다.
#   번들 안 파일은 코드서명에 봉인되므로, 손대면 codesign --verify 가 걸러 낸다.
#
# 사용법
#   ./scripts/build-app.sh                 dist/ 에 조립
#   ./scripts/build-app.sh --output ~/tmp  다른 위치에 조립
#   ./scripts/build-app.sh --debug         디버그 구성으로 빌드
#   ./scripts/build-app.sh --print-plist   빌드 없이 Info.plist 만 출력 (테스트가 쓴다)
#   ./scripts/build-app.sh --print-version 빌드 없이 버전만 출력 (릴리즈 묶기가 쓴다)
#   ./scripts/build-app.sh --print-signing 빌드 없이 서명 계획만 출력 (테스트가 쓴다)
#
#   SIGN_IDENTITY="Developer ID Application: ..." ./scripts/build-app.sh
#                                          Developer ID 로 서명한다 (이름은 키체인에서 확인)
#
# 이 스크립트는 시스템에 아무것도 설치하지 않는다. 만든 '.app' 을 어디에 둘지,
# 로그인 항목으로 등록할지는 전부 사용자가 정한다.
# ---------------------------------------------------------------------------
set -euo pipefail

REPO_ROOT=$(cd "$(dirname "$0")/.." && pwd)

APP_NAME="EXEM Wifi Switcher"
BUNDLE_ID="com.horbis.exem-wifi-switcher"
PRODUCT="exem-wifi-switcher-app"
SHORT_VERSION="0.1.4"
BUNDLE_VERSION="1"
MINIMUM_SYSTEM="13.0"

# 위치 권한 안내문. 사용자가 승인 창에서 읽는 유일한 설명이므로 왜 필요한지 그대로 적는다.
LOCATION_USAGE="접속한 Wi-Fi 이름(SSID)을 확인해 사내 네트워크인지 판단합니다. macOS 는 Wi-Fi 이름을 읽을 때 위치 권한을 요구합니다. 위치는 이 판단에만 쓰이며 저장하거나 외부로 보내지 않습니다."

OUTPUT_DIR="$REPO_ROOT/dist"
CONFIGURATION=release
PRINT_PLIST_ONLY=0
PRINT_VERSION_ONLY=0
PRINT_SIGNING_ONLY=0

# 서명 신원. 비어 있으면 ad-hoc 이다 (기본이고, 인증서가 없는 기계에서 유일하게 가능한 길이다).
# 값을 저장소에 적지 마라. 인증서 이름에는 사람 실명과 Team ID 가 들어간다.
SIGN_IDENTITY="${SIGN_IDENTITY:-}"

err() { printf '%s\n' "$*" >&2; }
die() { err ""; err "중단: $*"; exit 1; }
heading() { printf '\n\033[1m%s\033[0m\n' "$*"; }

usage() {
    cat <<'USAGE'
사용법: ./scripts/build-app.sh [옵션]

  --output <경로>   번들을 만들 디렉터리 (기본: dist)
  --debug           디버그 구성으로 빌드 (기본: release)
  --print-plist     빌드하지 않고 Info.plist 만 출력한다
  --print-version   빌드하지 않고 버전(CFBundleShortVersionString)만 출력한다
  --print-signing   빌드하지 않고 서명 계획만 출력한다 (환경변수 SIGN_IDENTITY 가 정한다)
  --help            이 도움말

환경변수
  SIGN_IDENTITY     Developer ID 인증서 이름. 비우면 ad-hoc 서명 (기본)
                    설정한 이름은 `security find-identity -v -p codesigning` 에 있어야 한다
USAGE
}

# 서명 계획. 빌드도 서명도 하지 않고, 무엇으로 서명할지만 말한다.
# 인증서 이름 자체는 찍지 않는다 (실명과 Team ID 가 들어가는 자리라 로그·이슈로 새기 쉽다).
#
# **환경변수만 보고 답한다. 키체인은 보지 않는다.** SIGN_IDENTITY 가 있으면 Developer ID,
# 없으면 ad-hoc 이고, 그 둘 말고 다른 답은 없다 (막히는 조합이 없다).
# 그 이름의 인증서가 키체인에 실제로 있는지는 계획이 아니라 환경이고, 계획을 낸 뒤에도 바뀐다.
# 그래서 여기서 묻지 않고 실제로 빌드하는 길에서 확인한다 (아래 사전 점검).
# package-release.sh 의 --print-notary-plan 이 mode=blocked 를 내는 것과는 다른 이야기다.
# 그쪽은 환경변수 조합만으로 이미 막힌다는 것을 알 수 있어서 계획이 답할 수 있다.
print_signing_plan() {
    if [ -n "$SIGN_IDENTITY" ]; then
        printf 'mode=developer-id\n'
        printf 'hardened-runtime=yes\n'
        printf 'timestamp=yes\n'
    else
        printf 'mode=adhoc\n'
        printf 'hardened-runtime=no\n'
        printf 'timestamp=no\n'
    fi
    printf 'identifier=%s\n' "$BUNDLE_ID"
}

while [ $# -gt 0 ]; do
    case "$1" in
        --output) [ $# -ge 2 ] || die "--output 뒤에 경로가 필요합니다"; OUTPUT_DIR="$2"; shift 2 ;;
        --debug) CONFIGURATION=debug; shift ;;
        --print-plist) PRINT_PLIST_ONLY=1; shift ;;
        --print-version) PRINT_VERSION_ONLY=1; shift ;;
        --print-signing) PRINT_SIGNING_ONLY=1; shift ;;
        --help|-h) usage; exit 0 ;;
        *) usage >&2; die "알 수 없는 옵션입니다: $1" ;;
    esac
done

# --- Info.plist -------------------------------------------------------------
#
# 여기서 키 하나가 빠지면 조용히 기능이 사라진다 (특히 위치 권한 설명).
# 그래서 내용을 함수로 떼어 두고, 테스트가 --print-plist 로 뽑아 검사한다.

info_plist() {
    cat <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>ko</string>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key>
    <string>${APP_NAME}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>${SHORT_VERSION}</string>
    <key>CFBundleVersion</key>
    <string>${BUNDLE_VERSION}</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>LSMinimumSystemVersion</key>
    <string>${MINIMUM_SYSTEM}</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSLocationWhenInUseUsageDescription</key>
    <string>${LOCATION_USAGE}</string>
    <key>NSSupportsAutomaticTermination</key>
    <false/>
    <key>NSSupportsSuddenTermination</key>
    <false/>
</dict>
</plist>
PLIST
}

if [ "$PRINT_VERSION_ONLY" -eq 1 ]; then
    printf '%s\n' "$SHORT_VERSION"
    exit 0
fi

if [ "$PRINT_PLIST_ONLY" -eq 1 ]; then
    info_plist
    exit 0
fi

# 계획만 낸다. 인증서가 키체인에 있는지는 보지 않는다 (그 확인은 실제로 빌드하는 길에서 한다).
if [ "$PRINT_SIGNING_ONLY" -eq 1 ]; then
    print_signing_plan
    exit 0
fi

# --- 사전 점검 --------------------------------------------------------------

[ "$(uname)" = "Darwin" ] || die "macOS 에서만 조립할 수 있습니다"
command -v swift >/dev/null || die "swift 를 찾지 못했습니다 (xcode-select --install 로 Command Line Tools 를 설치하세요)"
command -v codesign >/dev/null || die "codesign 을 찾지 못했습니다"
command -v plutil >/dev/null || die "plutil 을 찾지 못했습니다"

# 인증서가 정말 있는지 **빌드 전에** 본다. 서명은 마지막 단계라, 여기서 보지 않으면
# 몇 분짜리 빌드를 다 마친 뒤 이름 오타 하나로 실패한다.
if [ -n "$SIGN_IDENTITY" ]; then
    command -v security >/dev/null || die "security 를 찾지 못했습니다 (SIGN_IDENTITY 로 서명하려면 필요합니다)"
    # 목록을 먼저 변수에 받는다. `security ... | grep -q` 로 이으면 grep 이 먼저 끝나면서
    # security 가 SIGPIPE 로 죽고, pipefail 때문에 찾았는데도 실패로 읽힌다.
    CODESIGNING_IDENTITIES=$(security find-identity -v -p codesigning 2>/dev/null || true)
    case "$CODESIGNING_IDENTITIES" in
        *"$SIGN_IDENTITY"*) : ;;
        *)
            err ""
            err "중단: SIGN_IDENTITY 로 준 이름을 코드서명 인증서 목록에서 찾지 못했습니다."
            err ""
            err "  쓸 수 있는 이름을 직접 확인하세요:"
            err "    security find-identity -v -p codesigning"
            err ""
            err "  거기 나온 이름을 따옴표째 그대로 넘기면 됩니다."
            err "  인증서 없이 만들려면 SIGN_IDENTITY 를 지우세요 (ad-hoc 서명으로 돌아갑니다)."
            exit 1
            ;;
    esac
    printf '서명 신원을 키체인에서 확인했습니다 (Developer ID)\n'
fi

APP_BUNDLE="$OUTPUT_DIR/$APP_NAME.app"
CONTENTS="$APP_BUNDLE/Contents"
ICONS_DIR="$REPO_ROOT/Resources/icons"
# 앱이 관리자 인증을 받아 실행할 설치 스크립트가 놓이는 자리.
# Swift 쪽 InstallPaths.bundledScriptsSubpath 와 같은 값이어야 한다 (테스트가 검사한다).
BUNDLED_SCRIPTS_DIR="$CONTENTS/Resources/scripts"

# --- 1) 빌드 ----------------------------------------------------------------

heading "1/5  실행 파일 빌드 ($CONFIGURATION)"
swift build -c "$CONFIGURATION" --package-path "$REPO_ROOT" --product "$PRODUCT"
BIN_PATH="$(swift build -c "$CONFIGURATION" --package-path "$REPO_ROOT" --show-bin-path)"
[ -x "$BIN_PATH/$PRODUCT" ] || die "빌드 결과를 찾지 못했습니다: $BIN_PATH/$PRODUCT"
printf '    %s\n' "$BIN_PATH/$PRODUCT"

# --- 2) 번들 조립 -----------------------------------------------------------

heading "2/5  번들 조립"
rm -rf "$APP_BUNDLE"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"

# 실행 파일 이름도 제품명으로 둔다 — 시스템이 실행 파일 이름을 그대로 보여주는 자리가 있다
# (Phase 0 에서 로그인 항목에 'server' 로 표시된 사고가 있었다).
cp "$BIN_PATH/$PRODUCT" "$CONTENTS/MacOS/$APP_NAME"
chmod 0755 "$CONTENTS/MacOS/$APP_NAME"

info_plist > "$CONTENTS/Info.plist"
plutil -lint "$CONTENTS/Info.plist" >/dev/null || die "Info.plist 문법 검사에 실패했습니다"
printf 'APPL????' > "$CONTENTS/PkgInfo"
printf '    %s\n' "$APP_BUNDLE"

# --- 3) 설치 스크립트 ---------------------------------------------------------
#
# 앱의 [설치] 버튼이 부르는 것이 바로 이 파일들이다. 터미널에서 실행하는 것과 **같은 스크립트**다.
# install.sh 는 자기 위치를 기준으로 원본을 찾으므로, 넷을 한 디렉터리에 나란히 둔다.

heading "3/5  설치 스크립트"
mkdir -p "$BUNDLED_SCRIPTS_DIR"
for script in install.sh uninstall.sh apply save-config; do
    [ -f "$REPO_ROOT/scripts/$script" ] || die "scripts/$script 이 없습니다"
    # 문법이 깨진 스크립트를 번들에 넣지 않는다 — 설치 버튼을 누른 뒤에 알게 되면 늦다.
    bash -n "$REPO_ROOT/scripts/$script" || die "scripts/$script 에 문법 오류가 있습니다"
    install -m 0755 "$REPO_ROOT/scripts/$script" "$BUNDLED_SCRIPTS_DIR/$script"
done
install -m 0644 "$REPO_ROOT/config.example.json" "$BUNDLED_SCRIPTS_DIR/config.example.json"
printf '    %s\n' "$(printf '%s ' install.sh uninstall.sh apply save-config config.example.json)"

# --- 4) 아이콘 --------------------------------------------------------------
#
# 아이콘은 별도로 만들어진다(Resources/icons/README.md). 아직 없으면 경고만 하고 넘어간다 —
# 앱은 아이콘 파일이 없으면 SF Symbols 로 대신 그린다.

heading "4/5  아이콘"
if [ -f "$ICONS_DIR/app/AppIcon.icns" ]; then
    cp "$ICONS_DIR/app/AppIcon.icns" "$CONTENTS/Resources/AppIcon.icns"
    printf '    앱 아이콘  AppIcon.icns\n'
else
    printf '    앱 아이콘 없음 — 기본 아이콘으로 표시됩니다 (%s)\n' "$ICONS_DIR/app/AppIcon.icns"
fi

menubar_copied=0
for state in manual dhcp error; do
    for suffix in "" "@2x"; do
        source_png="$ICONS_DIR/menubar/${state}${suffix}.png"
        if [ -f "$source_png" ]; then
            cp "$source_png" "$CONTENTS/Resources/${state}${suffix}.png"
            menubar_copied=$(( menubar_copied + 1 ))
        fi
    done
done
if [ "$menubar_copied" -gt 0 ]; then
    printf '    메뉴바 아이콘 %d개\n' "$menubar_copied"
else
    printf '    메뉴바 아이콘 없음 — SF Symbols 로 대신 그립니다\n'
fi

# --- 5) 서명 ----------------------------------------------------------------
#
# 번들 안 파일을 전부 넣은 **뒤에** 서명한다. Contents/Resources 도 서명에 봉인되므로,
# 나중에 설치 스크립트를 손대면 codesign --verify 가 어긋난 것을 알려 준다.
# ad-hoc 서명은 신뢰의 근거가 아니다(누구나 다시 서명할 수 있다) — 손댄 흔적을 잡는 장치다.

if [ -n "$SIGN_IDENTITY" ]; then
    # --options runtime (hardened runtime) 은 공증의 전제 조건이다. 없이 서명하면 공증이
    # 그 이유로 반려된다. --timestamp 는 Apple 의 타임스탬프 서버를 부르므로 네트워크가 필요하다.
    heading "5/5  Developer ID 서명"
    codesign --force --sign "$SIGN_IDENTITY" --identifier "$BUNDLE_ID" \
        --options runtime --timestamp "$APP_BUNDLE" \
        || die "Developer ID 서명에 실패했습니다. --timestamp 는 Apple 타임스탬프 서버를 부릅니다. 네트워크 연결을 확인하세요"
    codesign --verify --strict "$APP_BUNDLE"
    printf '    서명 확인됨 (Developer ID, hardened runtime, 식별자 %s)\n' "$BUNDLE_ID"
else
    heading "5/5  ad-hoc 서명"
    codesign --force --sign - --identifier "$BUNDLE_ID" "$APP_BUNDLE"
    codesign --verify --strict "$APP_BUNDLE"
    printf '    서명 확인됨 (ad-hoc, 식별자 %s)\n' "$BUNDLE_ID"
fi

# --- 결과 -------------------------------------------------------------------
#
# 앱을 바꿔 넣는 사람에게 위치 권한이 어떻게 되는지 알려 준다. 서명 방식에 따라 답이 갈린다.
# ad-hoc 은 매번 풀리고, Developer ID 는 유지된다. 다만 **서명 방식이 바뀌는 그 한 번**은
# 어느 쪽이든 풀린다 (신원 자체가 달라진다). 그것을 모르면 사용자는 전환이 조용히 멈춘 것을
# 자기 실수로 여긴다.

if [ -n "$SIGN_IDENTITY" ]; then
    UPGRADE_NOTE="이미 쓰던 앱을 이 번들로 바꾸는 경우
  - 위치 권한은 그대로 남습니다. Developer ID 서명이라 코드가 바뀌어도 신원이 같습니다
  - 단, ad-hoc 으로 만든 앱에서 올라오는 첫 교체는 예외입니다. 서명 신원이 달라지므로
    위치 권한이 한 번 풀립니다. 설정 창의 권한 항목에서 [허용 요청] 을 한 번 누르면 됩니다
  - 전환 권한·설정 값·알림 권한·로그인 항목은 그대로 남습니다"
else
    UPGRADE_NOTE="이미 쓰던 앱을 이 번들로 바꾸는 경우
  - 위치 권한이 풀립니다. ad-hoc 서명이라 코드가 바뀌면 macOS 가 다른 앱으로 봅니다 —
    설정 창의 권한 항목에서 [허용 요청] 을 한 번 누르면 됩니다
  - 전환 권한·설정 값·알림 권한·로그인 항목은 그대로 남습니다"
fi

heading "완료"
printf '  %s\n' "$APP_BUNDLE"

cat <<NEXT

다음 할 일 (전부 사용자가 직접 합니다 — 이 스크립트는 시스템을 바꾸지 않습니다)

  1. 앱 옮기기(선택)     mv "$APP_BUNDLE" /Applications/
  2. 실행                open "$APP_BUNDLE"
                         첫 실행에서 설정 창이 뜹니다.
  3. 전환 권한 설치      설정 창의 권한 섹션에서 [설치] 를 누릅니다.
                         터미널로 하려면: ./scripts/install.sh
  4. 로그인 시 자동 실행  설정 창의 체크상자로 켜고 끕니다.

되돌리기               설정 창의 [앱 삭제] (설치한 항목을 지운 뒤 앱 번들도 휴지통으로 갑니다)
                       터미널로 하려면: ./scripts/uninstall.sh (이 길에서는 앱 번들이 남습니다)

$UPGRADE_NOTE
NEXT
