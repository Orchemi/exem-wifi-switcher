#!/bin/bash
# ---------------------------------------------------------------------------
# package-release.sh — 만든 '.app' 을 GitHub Releases 에 올릴 zip 하나로 묶는다.
#
# 하는 일은 넷뿐이다.
#   1. 번들을 새로 조립한다 (--skip-build 로 건너뛸 수 있다)
#   2. 서명이 온전한지, 번들이 품어야 할 파일이 다 있는지 확인한다
#   3. 공개해서는 안 될 값이 번들에 섞이지 않았는지 훑는다 (RULES.md 배포 전 점검)
#   4. ditto 로 zip 을 만들고 SHA-256 을 찍는다
#
# **서명·공증은 하지 않는다.** 유료 개발자 계정이 없다. 내려받은 사람은 첫 실행에서
# Gatekeeper 경고를 만난다 — 그 사실과 여는 방법을 README 에 적어 두었다.
#
# 사용법
#   ./scripts/package-release.sh                 dist/ 에 zip 을 만든다
#   ./scripts/package-release.sh --skip-build    이미 조립된 번들을 그대로 묶는다
#   ./scripts/package-release.sh --output ~/tmp  다른 위치에 만든다
# ---------------------------------------------------------------------------
set -euo pipefail

REPO_ROOT=$(cd "$(dirname "$0")/.." && pwd)

APP_NAME="EXEM Wifi Switcher"
ARCHIVE_BASENAME="EXEM-Wifi-Switcher"

OUTPUT_DIR="$REPO_ROOT/dist"
SKIP_BUILD=0

err() { printf '%s\n' "$*" >&2; }
die() { err ""; err "중단: $*"; exit 1; }
heading() { printf '\n\033[1m%s\033[0m\n' "$*"; }

usage() {
    cat <<'USAGE'
사용법: ./scripts/package-release.sh [옵션]

  --output <경로>   zip 을 만들 디렉터리 (기본: dist)
  --skip-build      번들을 다시 조립하지 않는다 (이미 만든 것을 묶는다)
  --help            이 도움말
USAGE
}

while [ $# -gt 0 ]; do
    case "$1" in
        --output) [ $# -ge 2 ] || die "--output 뒤에 경로가 필요합니다"; OUTPUT_DIR="$2"; shift 2 ;;
        --skip-build) SKIP_BUILD=1; shift ;;
        --help|-h) usage; exit 0 ;;
        *) usage >&2; die "알 수 없는 옵션입니다: $1" ;;
    esac
done

[ "$(uname)" = "Darwin" ] || die "macOS 에서만 묶을 수 있습니다"
command -v ditto >/dev/null || die "ditto 를 찾지 못했습니다"
command -v codesign >/dev/null || die "codesign 을 찾지 못했습니다"
command -v shasum >/dev/null || die "shasum 을 찾지 못했습니다"

VERSION=$("$REPO_ROOT/scripts/build-app.sh" --print-version)
[ -n "$VERSION" ] || die "버전을 읽지 못했습니다"

APP_BUNDLE="$OUTPUT_DIR/$APP_NAME.app"
ARCHIVE="$OUTPUT_DIR/$ARCHIVE_BASENAME-$VERSION.zip"

# --- 1) 번들 ----------------------------------------------------------------

heading "1/4  번들"
if [ "$SKIP_BUILD" -eq 1 ]; then
    printf '    다시 조립하지 않습니다 (--skip-build)\n'
else
    "$REPO_ROOT/scripts/build-app.sh" --output "$OUTPUT_DIR" >/dev/null
    printf '    조립했습니다\n'
fi
[ -d "$APP_BUNDLE" ] || die "번들이 없습니다: $APP_BUNDLE"
printf '    %s (버전 %s)\n' "$APP_BUNDLE" "$VERSION"

# --- 2) 온전한지 확인 ---------------------------------------------------------

heading "2/4  번들 점검"

codesign --verify --strict "$APP_BUNDLE" || die "서명 검증에 실패했습니다 (다시 조립하세요)"
printf '    서명 확인 (ad-hoc — 공증은 하지 않습니다)\n'

# 앱의 [설치] 버튼이 부르는 파일들. 하나라도 빠지면 내려받은 사람은 버튼만 있고 동작이 없다.
BUNDLED_SCRIPTS="$APP_BUNDLE/Contents/Resources/scripts"
for required in install.sh uninstall.sh apply save-config config.example.json; do
    [ -f "$BUNDLED_SCRIPTS/$required" ] || die "번들에 $required 이 없습니다"
done
printf '    설치 스크립트 5개 확인\n'

# --- 3) 공개해서는 안 될 값 ----------------------------------------------------
#
# 번들에 스크립트를 넣게 되면서 표면이 늘었다. 개발 중 만든 설정 파일이나 실측값이
# 딸려 들어가면 zip 을 내려받은 사람에게 그대로 간다. RULES.md 의 점검을 여기서 한 번 더 한다.

heading "3/4  배포 전 점검"

scan_dirs=("$BUNDLED_SCRIPTS" "$APP_BUNDLE/Contents/Info.plist")

scan_for() {
    local label="$1" pattern="$2"
    # -I 로 실행 파일·이미지는 건너뛴다 (바이너리에서 우연히 맞는 바이트를 잡지 않는다).
    if grep -rIniE "$pattern" "${scan_dirs[@]}" >/dev/null 2>&1; then
        err "  걸린 항목:"
        grep -rIniE "$pattern" "${scan_dirs[@]}" >&2 || true
        die "$label 이 번들에 들어 있습니다. 정리한 뒤 다시 묶으세요."
    fi
}

scan_for "MAC 주소로 보이는 값" '([0-9a-f]{2}:){5}[0-9a-f]{2}'
scan_for "사내 대역으로 보이는 IP" '10\.|192\.168\.[0-9]|172\.(1[6-9]|2[0-9]|3[01])\.'
# 홈 경로 패턴은 문자 클래스로 적는다 — 이 파일 자신이 RULES.md 의 사전 점검 grep 에 걸리지 않도록.
# 정규식으로는 [U] 가 U 와 같으므로 찾는 대상은 그대로다.
scan_for "사용자 홈 절대경로" '/[U]sers/'

# 사용자 설정 파일은 /usr/local/etc 에만 있어야 한다. 번들에 들어가면 남의 값을 배포하게 된다.
if [ -e "$BUNDLED_SCRIPTS/config.json" ]; then
    die "번들에 config.json 이 있습니다 (예시 파일만 들어가야 합니다)"
fi
if find "$APP_BUNDLE" -name '.DS_Store' -print -quit | grep -q .; then
    die "번들에 .DS_Store 가 있습니다"
fi
printf '    사내 값·설정 파일·찌꺼기 없음\n'

# --- 4) 묶기 -----------------------------------------------------------------

heading "4/4  zip"
rm -f "$ARCHIVE"
# ditto 를 쓰는 이유: zip(1) 과 달리 리소스 포크와 확장 속성을 지켜 서명이 깨지지 않는다.
ditto -c -k --sequesterRsrc --keepParent "$APP_BUNDLE" "$ARCHIVE"
printf '    %s\n' "$ARCHIVE"
printf '    %s\n' "$(shasum -a 256 "$ARCHIVE" | awk '{ print $1 }')"

# --- 결과 -------------------------------------------------------------------

heading "완료"
cat <<NEXT
  파일     $ARCHIVE
  버전     $VERSION
  SHA-256  $(shasum -a 256 "$ARCHIVE" | awk '{ print $1 }')

릴리즈 노트에 반드시 적을 것
  - 서명·공증이 없어 첫 실행에서 Gatekeeper 가 막는다는 사실과 여는 방법
    (시스템 설정 > 개인정보 보호 및 보안 에서 "확인 없이 열기")
  - 위 SHA-256 (내려받은 파일이 올린 그대로인지 확인할 수 있게)
  - 이 앱이 무엇을 설치하는지 (README '설치되는 항목 전부')
NEXT
