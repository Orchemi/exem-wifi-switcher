#!/bin/bash
# ---------------------------------------------------------------------------
# build-app.sh — SPM 으로 빌드한 실행 파일을 '.app' 번들로 조립한다.
#
# **Xcode 없이 Command Line Tools 만으로 동작한다.** 쓰는 도구는 네 개뿐이다.
#   swift     실행 파일 빌드
#   plutil    Info.plist 문법 검증
#   codesign  ad-hoc 서명
#   ditto/cp  파일 복사
#
# 왜 번들이어야 하는가
#   1. SSID 조회에 위치 권한이 필요하고, 그 권한은 '.app' 번들 + Info.plist 키 +
#      서명이 있어야만 부여된다 (Phase 0 에서 실증). 맨 실행 파일은 영구 실패한다.
#   2. 로그인 항목에 제품명으로 표시되려면 번들이어야 한다.
#
# 서명은 ad-hoc(`--sign -`) 이다. 유료 인증서가 없어 "확인되지 않은 개발자" 표기는
# 남지만, 위치 권한은 번들 식별자 단위로 유지되므로 재빌드해도 다시 승인할 필요는 없다.
#
# 사용법
#   ./scripts/build-app.sh                 dist/ 에 조립
#   ./scripts/build-app.sh --output ~/tmp  다른 위치에 조립
#   ./scripts/build-app.sh --debug         디버그 구성으로 빌드
#   ./scripts/build-app.sh --print-plist   빌드 없이 Info.plist 만 출력 (테스트가 쓴다)
#
# 이 스크립트는 시스템에 아무것도 설치하지 않는다. 만든 '.app' 을 어디에 둘지,
# 로그인 항목으로 등록할지는 전부 사용자가 정한다.
# ---------------------------------------------------------------------------
set -euo pipefail

REPO_ROOT=$(cd "$(dirname "$0")/.." && pwd)

APP_NAME="EXEM Wifi Switcher"
BUNDLE_ID="com.horbis.exem-wifi-switcher"
PRODUCT="exem-wifi-switcher-app"
SHORT_VERSION="0.1.0"
BUNDLE_VERSION="1"
MINIMUM_SYSTEM="13.0"

# 위치 권한 안내문. 사용자가 승인 창에서 읽는 유일한 설명이므로 왜 필요한지 그대로 적는다.
LOCATION_USAGE="접속한 Wi-Fi 이름(SSID)을 확인해 사내 네트워크인지 판단합니다. macOS 는 Wi-Fi 이름을 읽을 때 위치 권한을 요구합니다. 위치는 이 판단에만 쓰이며 저장하거나 외부로 보내지 않습니다."

OUTPUT_DIR="$REPO_ROOT/dist"
CONFIGURATION=release
PRINT_PLIST_ONLY=0

err() { printf '%s\n' "$*" >&2; }
die() { err ""; err "중단: $*"; exit 1; }
heading() { printf '\n\033[1m%s\033[0m\n' "$*"; }

usage() {
    cat <<'USAGE'
사용법: ./scripts/build-app.sh [옵션]

  --output <경로>   번들을 만들 디렉터리 (기본: dist)
  --debug           디버그 구성으로 빌드 (기본: release)
  --print-plist     빌드하지 않고 Info.plist 만 출력한다
  --help            이 도움말
USAGE
}

while [ $# -gt 0 ]; do
    case "$1" in
        --output) [ $# -ge 2 ] || die "--output 뒤에 경로가 필요합니다"; OUTPUT_DIR="$2"; shift 2 ;;
        --debug) CONFIGURATION=debug; shift ;;
        --print-plist) PRINT_PLIST_ONLY=1; shift ;;
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

if [ "$PRINT_PLIST_ONLY" -eq 1 ]; then
    info_plist
    exit 0
fi

# --- 사전 점검 --------------------------------------------------------------

[ "$(uname)" = "Darwin" ] || die "macOS 에서만 조립할 수 있습니다"
command -v swift >/dev/null || die "swift 를 찾지 못했습니다 (xcode-select --install 로 Command Line Tools 를 설치하세요)"
command -v codesign >/dev/null || die "codesign 을 찾지 못했습니다"
command -v plutil >/dev/null || die "plutil 을 찾지 못했습니다"

APP_BUNDLE="$OUTPUT_DIR/$APP_NAME.app"
CONTENTS="$APP_BUNDLE/Contents"
ICONS_DIR="$REPO_ROOT/Resources/icons"

# --- 1) 빌드 ----------------------------------------------------------------

heading "1/4  실행 파일 빌드 ($CONFIGURATION)"
swift build -c "$CONFIGURATION" --package-path "$REPO_ROOT" --product "$PRODUCT"
BIN_PATH="$(swift build -c "$CONFIGURATION" --package-path "$REPO_ROOT" --show-bin-path)"
[ -x "$BIN_PATH/$PRODUCT" ] || die "빌드 결과를 찾지 못했습니다: $BIN_PATH/$PRODUCT"
printf '    %s\n' "$BIN_PATH/$PRODUCT"

# --- 2) 번들 조립 -----------------------------------------------------------

heading "2/4  번들 조립"
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

# --- 3) 아이콘 --------------------------------------------------------------
#
# 아이콘은 별도로 만들어진다(Resources/icons/README.md). 아직 없으면 경고만 하고 넘어간다 —
# 앱은 아이콘 파일이 없으면 SF Symbols 로 대신 그린다.

heading "3/4  아이콘"
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

# --- 4) 서명 ----------------------------------------------------------------

heading "4/4  ad-hoc 서명"
codesign --force --sign - --identifier "$BUNDLE_ID" "$APP_BUNDLE"
codesign --verify --strict "$APP_BUNDLE"
printf '    서명 확인됨 (ad-hoc, 식별자 %s)\n' "$BUNDLE_ID"

# --- 결과 -------------------------------------------------------------------

heading "완료"
printf '  %s\n' "$APP_BUNDLE"

cat <<NEXT

다음 할 일 (전부 사용자가 직접 합니다 — 이 스크립트는 시스템을 바꾸지 않습니다)

  1. 전환 권한 설치      ./scripts/install.sh
  2. 앱 옮기기(선택)     mv "$APP_BUNDLE" /Applications/
  3. 실행                open "$APP_BUNDLE"
                         첫 실행에서 설정 창이 뜹니다.
  4. 로그인 시 자동 실행  설정 창의 체크상자로 켜고 끕니다.

되돌리기               ./scripts/uninstall.sh  (앱 번들은 직접 지우세요)
NEXT
