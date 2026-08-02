#!/bin/bash
# ---------------------------------------------------------------------------
# package-release.sh — 만든 '.app' 을 GitHub Releases 에 올릴 zip 하나로 묶는다.
#
# 하는 일은 여섯뿐이다.
#   1. 태그와 번들 버전이 어긋나지 않았는지 본다
#   2. 번들을 새로 조립한다 (--skip-build 로 건너뛸 수 있다)
#   3. 서명이 온전한지, 번들이 품어야 할 파일이 다 있는지, 번들 버전이 맞는지 확인한다
#   4. 공개해서는 안 될 값이 번들에 섞이지 않았는지 훑는다 (RULES.md 배포 전 점검)
#   5. 공증하고 티켓을 번들에 붙인다 (NOTARY_PROFILE 이 있을 때만)
#   6. ditto 로 zip 을 만들고 SHA-256 을 찍는다
#
# **4 → 5 → 6 순서는 뜻이 있다.** 유출 점검이 공증보다 먼저이고, 공증이 zip 보다 먼저다.
# 근거는 각 단계 머리말에 적어 두었다. 바꾸지 마라.
#
# **zip 이름에 버전을 넣지 않는다.** 이름은 'EXEM-Wifi-Switcher.zip' 하나로 고정한다.
# GitHub 은 releases/latest/download/<자산이름> 을 최신 릴리즈의 그 이름 자산으로 넘겨주는데,
# 이름에 버전이 있으면 그 주소가 매 릴리즈마다 달라져 README 의 내려받기 버튼을 판올림할 때마다
# 고쳐야 한다. 고치는 것을 잊으면 버튼은 옛 버전을 계속 내주고, 아무도 알아채지 못한다.
# 대신 **파일 이름만 보고는 어느 버전인지 알 수 없게 된다.** 사람이 버전을 확인하는 자리가
# 릴리즈 노트와 번들의 Info.plist 둘로 줄어든다는 뜻이다. 이 스크립트가 마지막에 버전과
# SHA-256 을 함께 찍는 것은 그 둘을 릴리즈 노트로 옮겨 적으라는 뜻이다.
# 버전 게이트는 이름과 무관하게 그대로다 (build-app.sh 의 SHORT_VERSION ↔ HEAD 태그 ↔ 번들 plist).
#
# 서명·공증은 두 갈래이고, 갈림길은 환경변수 둘이다. **기본은 둘 다 없는 길이다.**
#
# 1) 환경변수가 없으면 번들은 ad-hoc 서명이고 공증도 하지 않는다. 내려받은 사람은 첫 실행에서
#    Gatekeeper 경고를 만난다. 그 사실과 여는 방법을 README 에 적어 두었다.
# 2) `SIGN_IDENTITY` 로 Developer ID 서명한 번들에 `NOTARY_PROFILE` 을 함께 주면 공증까지 한다.
#    Apple 이 검사한 뒤 티켓을 발급하고, 그 티켓을 번들에 붙이면(staple) Gatekeeper 경고가 사라진다.
#    `NOTARY_PROFILE` 은 `xcrun notarytool store-credentials` 로 키체인에 저장해 둔 프로파일 이름이다.
#    **자격증명은 키체인에만 있다.** 이름도 값도 저장소에 적지 마라.
#
# ad-hoc 번들은 공증할 수 없다. `NOTARY_PROFILE` 만 주고 `SIGN_IDENTITY` 를 빼면 시작 전에 막는다.
#
# 사용법
#   ./scripts/package-release.sh                 dist/ 에 zip 을 만든다
#   ./scripts/package-release.sh --skip-build    이미 조립된 번들을 그대로 묶는다
#   ./scripts/package-release.sh --output ~/tmp  다른 위치에 만든다
#   ./scripts/package-release.sh --print-notary-plan
#                                                아무것도 하지 않고 공증 계획만 출력한다
#                                                mode=skip / mode=notarize profile=<이름> /
#                                                mode=blocked reason=<사유> (이때는 1 로 끝난다)
#
#   SIGN_IDENTITY="Developer ID Application: ..." NOTARY_PROFILE="<프로파일>" \
#     ./scripts/package-release.sh               서명하고 공증해서 묶는다
# ---------------------------------------------------------------------------
set -euo pipefail

REPO_ROOT=$(cd "$(dirname "$0")/.." && pwd)

APP_NAME="EXEM Wifi Switcher"
ARCHIVE_BASENAME="EXEM-Wifi-Switcher"

# README 의 내려받기 버튼이 가리키는 고정 주소. 자산 이름이 이 주소의 마지막 조각이므로
# 둘은 함께 움직인다 (한쪽만 바꾸면 버튼이 404 를 받는다).
RELEASE_DOWNLOAD_URL="https://github.com/Orchemi/exem-wifi-switcher/releases/latest/download/$ARCHIVE_BASENAME.zip"

OUTPUT_DIR="$REPO_ROOT/dist"
SKIP_BUILD=0

# 서명 신원과 공증 프로파일. 둘 다 비어 있는 것이 기본이고, 그때는 예전과 똑같이 동작한다.
# 값을 저장소에 적지 마라 (인증서 이름에는 실명과 Team ID 가, 프로파일 뒤에는 자격증명이 있다).
SIGN_IDENTITY="${SIGN_IDENTITY:-}"
NOTARY_PROFILE="${NOTARY_PROFILE:-}"

err() { printf '%s\n' "$*" >&2; }
die() { err ""; err "중단: $*"; exit 1; }
heading() { printf '\n\033[1m%s\033[0m\n' "$*"; }

usage() {
    cat <<'USAGE'
사용법: ./scripts/package-release.sh [옵션]

  --output <경로>   zip 을 만들 디렉터리 (기본: dist)
  --skip-build      번들을 다시 조립하지 않는다 (이미 만든 것을 묶는다)
  --check-tag <버전> [태그...]
                    태그↔버전 판정만 하고 끝낸다 (테스트가 쓴다 — git 을 보지 않는다)
  --print-head-tags HEAD 에 붙은 태그만 출력한다 (테스트가 쓴다 — git 이 없으면 빈 출력)
  --print-notary-plan
                    아무것도 하지 않고 공증 계획만 출력한다 (테스트가 쓴다)
                    묶을 수 없는 조합이면 mode=blocked 를 내고 1 로 끝난다
  --help            이 도움말

환경변수
  SIGN_IDENTITY     Developer ID 인증서 이름 (scripts/build-app.sh 이 서명에 쓴다)
  NOTARY_PROFILE    xcrun notarytool store-credentials 로 저장해 둔 키체인 프로파일 이름
                    설정하면 공증까지 한다. SIGN_IDENTITY 없이는 쓸 수 없다
USAGE
}

# 환경변수 조합이 묶을 수 없는 것인지 판정한다. **이 판정은 여기 한 곳에만 있다.**
# 계획 출력과 실제 실행이 서로 다른 자리에서 판정하면 둘이 조용히 갈라진다. 실제로 갈라진 적이 있다.
# 계획은 "공증한다" 고 답하는데 정작 돌리면 중단됐다. 그러면 미리 보라고 만든 플래그가
# 사람을 잘못된 곳으로 보낸다. 조건을 여기 말고 다른 데 또 적지 마라.
notary_blocked() {
    [ -n "$NOTARY_PROFILE" ] && [ -z "$SIGN_IDENTITY" ]
}

# 왜 묶을 수 없는지와 무엇을 하면 되는지. 계획 출력과 실제 실행이 같은 말을 하도록 함께 쓴다.
explain_notary_blocked() {
    err ""
    err "  ad-hoc 서명한 번들은 공증할 수 없습니다. 공증은 Apple 이 발급한 Developer ID 로"
    err "  서명하고 hardened runtime 을 켠 번들만 받습니다. ad-hoc 에는 신원이 없어 Apple 이"
    err "  누구의 것인지 알 수 없고, 제출해도 반려됩니다."
    err ""
    err "  둘 중 하나를 고르세요."
    err "    · SIGN_IDENTITY 도 함께 준다 (서명하고 공증한다)"
    err "    · NOTARY_PROFILE 을 지운다 (예전처럼 ad-hoc 으로 묶는다)"
}

# 공증 계획. **환경변수만 보고 말한다** (키체인도 네트워크도 번들도 건드리지 않는다).
# 그래서 답할 수 있는 것과 없는 것이 갈린다.
#   답한다   환경변수 조합만으로 정해지는 것: 공증을 하는가·건너뛰는가·아예 막히는가
#   답 못 한다 그 인증서가 키체인에 실제로 있는지, 번들이 정말 그것으로 서명됐는지,
#            공증 자격증명이 살아 있는지. 이것들은 환경이지 계획이 아니고, 계획을 낸 뒤에도
#            바뀔 수 있다. 그 확인은 실제로 묶는 길에서 한다.
# 막히는 조합은 환경변수만 보고도 알 수 있다. 그러니 여기서 답해야 한다.
print_notary_plan() {
    if notary_blocked; then
        printf 'mode=blocked reason=no-sign-identity\n'
        err ""
        err "  이 조합으로는 묶을 수 없습니다. NOTARY_PROFILE 은 있는데 SIGN_IDENTITY 가 없습니다."
        explain_notary_blocked
        return 1
    fi
    if [ -z "$NOTARY_PROFILE" ]; then
        printf 'mode=skip\n'
    else
        printf 'mode=notarize profile=%s\n' "$NOTARY_PROFILE"
    fi
}

# --- 버전 ↔ 태그 -------------------------------------------------------------
#
# 버전의 출처는 scripts/build-app.sh 의 SHORT_VERSION 하나다. Info.plist 도 릴리즈 노트에 적을 값도 그 값에서 나온다.
# 그런데 사람이 손으로 다는 태그는 그 값을 모른다. 어긋난 채로 올리면 `v0.1.0` 태그를 보고 내려받은
# zip 안에 다른 버전의 번들이 들어 있게 되고, README 가 권하는 **SHA-256 대조가 무엇을 확인하는지**
# 알 수 없게 된다. 받은 사람이 스스로 확인할 유일한 수단이 그것이라 여기서 막는다 —
# RULES.md §4 점검과 같은 방식이다 (걸리면 zip 을 만들지 않는다).
#
# **태그가 없는 것은 정상이다.** 개발 중 zip 을 만드는 길이 그렇다. 한 줄 알리고 지나간다.
# 릴리즈 태그로 보는 것은 `v<major>.<minor>.<patch>` 형태뿐이다 — 그 밖의 태그는 판정에 넣지 않는다.
# 같은 버전의 태그가 **다른 커밋에** 있는지까지는 보지 않는다. 그것은 올리지 않는 개발 zip 의 이야기이고,
# 올리는 zip 은 항상 태그가 붙은 커밋에서 나온다.

is_release_tag() {
    printf '%s' "$1" | grep -qE '^v[0-9]+\.[0-9]+\.[0-9]+$'
}

# 인자 중 릴리즈 태그 형태만 한 줄에 하나씩 남긴다.
filter_release_tags() {
    local tag
    for tag in "$@"; do
        [ -n "$tag" ] || continue
        is_release_tag "$tag" && printf '%s\n' "$tag"
    done
    return 0
}

# 버전과 다른 릴리즈 태그를 출력한다. 하나라도 있으면 1.
# HEAD 의 릴리즈 태그는 **전부** 번들 버전과 같아야 한다 — 한 커밋에 두 버전이 걸려 있으면
# 어느 쪽 태그를 보고 내려받았는지에 따라 대조 결과가 갈린다.
mismatched_release_tags() {
    local version="$1" tag status=0
    shift
    for tag in "$@"; do
        [ "$tag" = "v$version" ] && continue
        printf '%s\n' "$tag"
        status=1
    done
    return "$status"
}

# git 이 없거나 저장소가 아니거나 얕은 클론이면(태그가 따라오지 않는다) 아무것도 출력하지 않는다.
# 볼 것이 없는 것과 어긋난 것은 다르다 — 여기서는 조용히 지나간다.
tags_at_head() {
    command -v git >/dev/null 2>&1 || return 0
    git -C "$REPO_ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1 || return 0
    git -C "$REPO_ROOT" tag --points-at HEAD 2>/dev/null || true
}

# check_version_against_tags <버전> <태그...> — 판정하고 사람에게 말한다. 어긋나면 1.
check_version_against_tags() {
    local version="$1" release_tags mismatched mismatched_line
    shift
    release_tags=$(filter_release_tags "$@")

    if [ -z "$release_tags" ]; then
        printf '    HEAD 에 릴리즈 태그가 없습니다 — 개발 빌드로 봅니다\n'
        return 0
    fi

    # 태그에는 공백이 들어갈 수 없으므로 따옴표 없이 나눠 넘긴다.
    # shellcheck disable=SC2086
    mismatched=$(mismatched_release_tags "$version" $release_tags) || true
    if [ -n "$mismatched" ]; then
        # 여러 줄을 한 줄로 잇는다 (태그에는 공백이 없다).
        # shellcheck disable=SC2086,SC2116
        mismatched_line=$(echo $mismatched)
        err ""
        err "  HEAD 에 붙은 릴리즈 태그와 번들 버전이 다릅니다."
        err "    태그      $mismatched_line"
        err "    번들 버전  $version  (scripts/build-app.sh 의 SHORT_VERSION)"
        err ""
        err "  이대로 올리면 태그를 보고 내려받은 사람이 다른 버전의 번들을 받습니다."
        err "  릴리즈 노트의 SHA-256 을 대조해도 무엇을 확인한 것인지 알 수 없게 됩니다."
        err ""
        err "  맞추는 길 둘 — 태그를 옮기지 말고 하나를 고르세요."
        err "    · scripts/build-app.sh 의 SHORT_VERSION 을 태그에 맞춘다"
        err "    · 버전을 올린 커밋을 만들고 그 커밋에 새 태그를 단다"
        return 1
    fi

    # 남은 태그는 전부 "v$version" 이다 (다른 것은 위에서 걸렸다).
    printf '    HEAD 태그와 같습니다 (v%s)\n' "$version"
    return 0
}

# 묶는 번들이 정말 그 버전인지 본다. --skip-build 로 예전 번들을 그대로 묶으면 이 스크립트가
# 찍어 주는 버전만 새것이고 안에는 옛 번들이 들어간다. 그 값을 그대로 릴리즈 노트에 옮겨 적으면
# 받는 사람은 없는 버전을 받았다고 믿는다. 조립을 건너뛴 길에서만 생기는 어긋남이다.
bundle_short_version() {
    plutil -extract CFBundleShortVersionString raw -o - "$1/Contents/Info.plist" 2>/dev/null || true
}

while [ $# -gt 0 ]; do
    case "$1" in
        --output) [ $# -ge 2 ] || die "--output 뒤에 경로가 필요합니다"; OUTPUT_DIR="$2"; shift 2 ;;
        --skip-build) SKIP_BUILD=1; shift ;;
        --check-tag)
            [ $# -ge 2 ] || die "--check-tag 뒤에 버전이 필요합니다"
            shift
            check_version_against_tags "$@"
            exit $?
            ;;
        --print-head-tags) tags_at_head; exit 0 ;;
        # 판정 결과를 종료코드로도 낸다 (--check-tag 와 같은 방식이다).
        # 막히는 조합에 0 을 내면 CI 가 계획만 보고 통과시킨 뒤 실제 묶기에서 넘어진다.
        --print-notary-plan) print_notary_plan; exit $? ;;
        --help|-h) usage; exit 0 ;;
        *) usage >&2; die "알 수 없는 옵션입니다: $1" ;;
    esac
done

[ "$(uname)" = "Darwin" ] || die "macOS 에서만 묶을 수 있습니다"
command -v ditto >/dev/null || die "ditto 를 찾지 못했습니다"
command -v codesign >/dev/null || die "codesign 을 찾지 못했습니다"
command -v shasum >/dev/null || die "shasum 을 찾지 못했습니다"
command -v plutil >/dev/null || die "plutil 을 찾지 못했습니다"

# 공증을 하겠다면, 할 수 있는 조건인지 **아무것도 만들기 전에** 본다.
# 조립까지 다 마친 뒤 마지막 단계에서 막히면 그 시간을 통째로 버린다.
#
# 판정과 설명은 --print-notary-plan 과 **같은 함수**를 쓴다. 조건을 여기 따로 적으면
# 미리 보기와 실제 실행이 갈라지고, 갈라진 것은 실제로 묶어 보기 전까지 아무도 모른다.
if notary_blocked; then
    err ""
    err "중단: NOTARY_PROFILE 은 있는데 SIGN_IDENTITY 가 없습니다."
    explain_notary_blocked
    exit 1
fi
if [ -n "$NOTARY_PROFILE" ]; then
    # 도구가 있는지는 환경변수로 알 수 없다. 그래서 계획 출력이 아니라 여기서 본다.
    command -v xcrun >/dev/null || die "xcrun 을 찾지 못했습니다 (공증에는 Command Line Tools 가 필요합니다)"
fi

VERSION=$("$REPO_ROOT/scripts/build-app.sh" --print-version)
[ -n "$VERSION" ] || die "버전을 읽지 못했습니다"

APP_BUNDLE="$OUTPUT_DIR/$APP_NAME.app"
ARCHIVE="$OUTPUT_DIR/$ARCHIVE_BASENAME.zip"

# --- 1) 버전 ----------------------------------------------------------------
#
# 조립보다 먼저 본다. 어긋난 버전으로는 만들 zip 이 없으므로 빌드를 시작할 이유도 없다.

heading "1/6  버전"
printf '    %s (scripts/build-app.sh 의 SHORT_VERSION 하나가 출처입니다)\n' "$VERSION"
# 태그에는 공백이 들어갈 수 없으므로 따옴표 없이 나눠 넘긴다.
# shellcheck disable=SC2046
check_version_against_tags "$VERSION" $(tags_at_head) \
    || die "태그와 번들 버전을 맞춘 뒤 다시 묶으세요"

# --- 2) 번들 ----------------------------------------------------------------

heading "2/6  번들"
if [ "$SKIP_BUILD" -eq 1 ]; then
    printf '    다시 조립하지 않습니다 (--skip-build)\n'
else
    "$REPO_ROOT/scripts/build-app.sh" --output "$OUTPUT_DIR" >/dev/null
    printf '    조립했습니다\n'
fi
[ -d "$APP_BUNDLE" ] || die "번들이 없습니다: $APP_BUNDLE"
# 여기서 버전을 함께 적지 않는다 — 이 자리에서는 아직 번들의 버전을 확인하지 않았고,
# --skip-build 로 예전 번들을 묶는 길에서는 그 말이 거짓이 된다 (버전은 3/6 에서 대조한다).
printf '    %s\n' "$APP_BUNDLE"

# --- 3) 온전한지 확인 ---------------------------------------------------------

heading "3/6  번들 점검"

codesign --verify --strict "$APP_BUNDLE" || die "서명 검증에 실패했습니다 (다시 조립하세요)"

# 환경변수는 이 실행에서 무엇을 하려는지만 말한다. **번들에 실제로 무엇이 찍혀 있는지는 다른 문제다.**
# --skip-build 로 예전에 ad-hoc 으로 조립해 둔 번들을 묶으면, SIGN_IDENTITY 가 있다는 것만 보고
# ad-hoc 번들을 공증에 넣게 된다. 그러면 Apple 쪽에서 알 수 없는 이유로 반려되고, 사람은
# 인증서나 자격증명을 의심하며 시간을 쓴다. 그래서 번들의 서명 주체를 직접 읽어 대조한다.
if [ -n "$SIGN_IDENTITY" ]; then
    # 파이프로 잇지 않는다 (grep 이 먼저 끝나면 codesign 이 SIGPIPE 로 죽고 pipefail 에 걸린다).
    BUNDLE_SIGNING_INFO=$(codesign -dvv "$APP_BUNDLE" 2>&1 || true)
    case "$BUNDLE_SIGNING_INFO" in
        *"Authority=Developer ID Application"*) : ;;
        *)
            err ""
            err "중단: SIGN_IDENTITY 를 주었는데 번들이 Developer ID 로 서명돼 있지 않습니다."
            err ""
            err "  ad-hoc 서명된 번들을 묶으려 하고 있습니다. 이대로는 공증이 반려됩니다."
            err "  --skip-build 로 예전에 만들어 둔 번들을 묶고 있지 않은지 보세요."
            err "  --skip-build 없이 다시 돌리면 이 환경변수로 새로 서명해 조립합니다."
            exit 1
            ;;
    esac
    printf '    서명 확인 (Developer ID)\n'
else
    printf '    서명 확인 (ad-hoc — 공증은 하지 않습니다)\n'
fi

# 묶는 번들의 Info.plist 가 build-app.sh 의 SHORT_VERSION 과 같은지 본다.
# 두 값이 갈릴 수 있는 자리는 --skip-build 하나다.
BUNDLE_VERSION_IN_PLIST=$(bundle_short_version "$APP_BUNDLE")
[ "$BUNDLE_VERSION_IN_PLIST" = "$VERSION" ] || die "번들 버전($BUNDLE_VERSION_IN_PLIST)이 build-app.sh 의 SHORT_VERSION($VERSION)과 다릅니다. --skip-build 로 예전 번들을 묶고 있지 않은지 보세요"
printf '    번들 버전 %s (build-app.sh 의 SHORT_VERSION 과 같습니다)\n' "$BUNDLE_VERSION_IN_PLIST"

# 앱의 [설치] 버튼이 부르는 파일들. 하나라도 빠지면 내려받은 사람은 버튼만 있고 동작이 없다.
BUNDLED_SCRIPTS="$APP_BUNDLE/Contents/Resources/scripts"
for required in install.sh uninstall.sh apply save-config config.example.json; do
    [ -f "$BUNDLED_SCRIPTS/$required" ] || die "번들에 $required 이 없습니다"
done
printf '    설치 스크립트 5개 확인\n'

# --- 4) 공개해서는 안 될 값 ----------------------------------------------------
#
# 번들에 스크립트를 넣게 되면서 표면이 늘었다. 개발 중 만든 설정 파일이나 실측값이
# 딸려 들어가면 zip 을 내려받은 사람에게 그대로 간다. RULES.md 의 점검을 여기서 한 번 더 한다.

heading "4/6  배포 전 점검"

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
# 사설 대역은 〈접두어 + 서브넷 옥텟 + 점〉 형태로 찾는다. 근거는 RULES.md §3 "사설 대역 패턴을
# 왜 이렇게 적는가" 에 적어 두었다 — 한때 이 자리가 '10\.' 이었고, IP 가 아닌 십진수에 다 걸려서
# 릴리즈를 통째로 막았다. `\b` 와 뒤따르는 옥텟을 빼지 마라.
scan_for "사내 대역으로 보이는 IP" '\b10\.[0-9]{1,3}\.|\b192\.168\.[0-9]{1,3}\.|\b172\.(1[6-9]|2[0-9]|3[01])\.[0-9]{1,3}\.'
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

# --- 5) 공증 ------------------------------------------------------------------
#
# **유출 점검(4)이 여기보다 먼저인 것은 의도된 순서다. 바꾸지 마라.**
# 공증은 번들을 Apple 서버에 올리는 행위다. 사내 값이 섞인 번들을 올리면 zip 을 만들기도 전에,
# 남의 손에 들어간 시점에 이미 유출이다. 우리 쪽에서 지울 수 있는 것도 아니다.
# 점검을 통과한 번들만 밖으로 나간다.
#
# 공증이 하는 일: Apple 이 번들을 받아 악성 여부를 검사하고 티켓을 발급한다. 그 티켓을 번들에
# 붙이면(staple) 내려받은 사람이 오프라인이어도 Gatekeeper 가 티켓을 읽어 경고 없이 연다.

heading "5/6  공증"
if [ -z "$NOTARY_PROFILE" ]; then
    printf '    NOTARY_PROFILE 이 없어 건너뜁니다 (내려받은 사람은 첫 실행에서 Gatekeeper 경고를 봅니다)\n'
else
    # 제출용 zip 은 최종 배포물과 다른 파일이다. 최종 zip 은 티켓을 붙인 **뒤에** 만들어야 하므로
    # 이 자리에서 만든 것을 그대로 쓸 수 없다. 임시 디렉터리에 만들고 끝나면 지운다.
    NOTARY_TEMP_DIR=$(mktemp -d)
    trap 'rm -rf "$NOTARY_TEMP_DIR"' EXIT
    SUBMISSION_ZIP="$NOTARY_TEMP_DIR/$ARCHIVE_BASENAME-submit.zip"
    SUBMISSION_LOG="$NOTARY_TEMP_DIR/notarytool.txt"

    ditto -c -k --sequesterRsrc --keepParent "$APP_BUNDLE" "$SUBMISSION_ZIP"
    printf '    제출합니다. 심사가 끝날 때까지 기다립니다 (보통 몇 분)\n'

    if xcrun notarytool submit "$SUBMISSION_ZIP" \
        --keychain-profile "$NOTARY_PROFILE" --wait 2>&1 | tee "$SUBMISSION_LOG"; then
        NOTARY_OK=1
    else
        NOTARY_OK=0
    fi
    # --wait 는 반려돼도 0 으로 끝나는 경우가 있다. 종료코드만 믿지 않고 판정 문구도 함께 본다.
    case "$(cat "$SUBMISSION_LOG")" in
        *"status: Accepted"*) : ;;
        *) NOTARY_OK=0 ;;
    esac

    if [ "$NOTARY_OK" -ne 1 ]; then
        # 제출 id 를 뽑아 둔다. 반려 사유는 이 id 로만 볼 수 있고, 그것 없이는 무엇이 걸렸는지
        # 알 방법이 없다 (notarytool 은 "Invalid" 한 줄만 남긴다).
        SUBMISSION_ID=$(sed -n 's/^ *id: *\([0-9A-Za-z-]*\) *$/\1/p' "$SUBMISSION_LOG" | head -1)
        err ""
        err "  공증이 통과하지 못했습니다. 반려 사유는 따로 받아 봐야 합니다."
        if [ -n "$SUBMISSION_ID" ]; then
            err "    xcrun notarytool log $SUBMISSION_ID --keychain-profile \"$NOTARY_PROFILE\""
        else
            err "    xcrun notarytool log <submission-id> --keychain-profile \"<프로파일 이름>\""
            err "  제출 id 는 위 출력의 'id:' 줄에 있습니다."
        fi
        err ""
        err "  자주 걸리는 것: hardened runtime 이 꺼진 서명, 만료된 인증서, 서명되지 않은 실행 파일."
        die "공증을 통과한 뒤 다시 묶으세요"
    fi

    # 티켓을 번들에 붙인다. 이걸 하지 않으면 공증은 통과해도 오프라인에서 경고가 그대로 뜬다.
    xcrun stapler staple "$APP_BUNDLE" || die "티켓을 번들에 붙이지 못했습니다 (staple 실패)"
    xcrun stapler validate "$APP_BUNDLE" || die "붙인 티켓을 읽지 못했습니다 (stapler validate 실패)"
    # staple 은 번들 안에 파일을 하나 더 넣는다. 서명이 그대로인지 다시 확인한다.
    codesign --verify --strict "$APP_BUNDLE" || die "티켓을 붙인 뒤 서명 검증에 실패했습니다"
    printf '    공증 통과 · 티켓 붙임 · 서명 확인\n'

    # Gatekeeper 가 실제로 어떻게 판정하는지 보여 준다. **여기서는 막지 않는다.**
    # spctl 은 번들이 아니라 이 기계의 정책을 함께 재는 도구라, 평가가 꺼져 있거나
    # 정책이 다른 기계에서는 번들이 멀쩡해도 다른 답이 나온다. 배포 가부를 가르는 근거는
    # 위의 stapler validate 와 codesign --verify 이고, 이 줄은 사람이 눈으로 보라고 찍는다.
    if command -v spctl >/dev/null 2>&1; then
        printf '    Gatekeeper 판정 (참고용):\n'
        spctl -a -vvv -t exec "$APP_BUNDLE" 2>&1 | sed 's/^/      /' || true
    fi
fi

# --- 6) 묶기 -----------------------------------------------------------------
#
# **공증(5)이 여기보다 먼저인 것도 의도된 순서다.** 공증 티켓은 zip 이 아니라 '.app' 에 붙는다.
# 티켓을 붙이기 전에 zip 을 만들면 티켓 없는 번들을 배포하게 되고, 내려받은 사람은 공증을
# 했는데도 Gatekeeper 경고를 본다. 우리 기계에서는 (심사 기록이 남아) 잘 열리므로 알아채기도 어렵다.

heading "6/6  zip"
rm -f "$ARCHIVE"
# ditto 를 쓰는 이유: zip(1) 과 달리 리소스 포크와 확장 속성을 지켜 서명이 깨지지 않는다.
ditto -c -k --sequesterRsrc --keepParent "$APP_BUNDLE" "$ARCHIVE"
printf '    %s\n' "$ARCHIVE"
printf '    %s\n' "$(shasum -a 256 "$ARCHIVE" | awk '{ print $1 }')"

# --- 결과 -------------------------------------------------------------------
#
# 릴리즈 노트에 적을 것이 공증 여부에 따라 갈린다. 공증한 zip 에 "Gatekeeper 가 막는다" 를
# 적으면 없는 문제의 해결법을 알려 주는 셈이고, 공증하지 않은 zip 에 그 줄이 빠지면
# 받은 사람은 "손상됐다" 만 보고 지운다. 둘 다 사람을 잘못된 곳으로 보낸다.

if [ -n "$NOTARY_PROFILE" ]; then
    GATEKEEPER_NOTE="  - 앞 버전에서 올라오는 사람은 **위치 권한을 한 번 다시 줘야 합니다**
    (서명 신원이 바뀌는 릴리즈에서는 macOS 가 다른 앱으로 보고 권한을 새로 묻습니다.
     설정 창의 권한 항목에서 [허용 요청])"
else
    GATEKEEPER_NOTE="  - 서명·공증이 없어 첫 실행에서 Gatekeeper 가 막는다는 사실과 여는 방법
    (시스템 설정 > 개인정보 보호 및 보안 에서 \"확인 없이 열기\")"
fi

heading "완료"
cat <<NEXT
  파일     $ARCHIVE
  버전     $VERSION
  SHA-256  $(shasum -a 256 "$ARCHIVE" | awk '{ print $1 }')

파일 이름에는 버전이 없습니다. README 의 내려받기 버튼이 이 고정 주소를 가리키고,
GitHub 이 이 이름의 자산을 최신 릴리즈에서 찾아 주기 때문입니다.

  $RELEASE_DOWNLOAD_URL

그래서 **올릴 때 자산 이름을 바꾸면 그 버튼이 조용히 끊깁니다.** 이름을 그대로 두세요.
받는 사람이 버전을 확인할 수 있는 곳도 릴리즈 노트뿐입니다.

릴리즈 노트에 반드시 적을 것
  - **위 버전** (파일 이름으로는 알 수 없습니다)
$GATEKEEPER_NOTE
  - 위 SHA-256 (내려받은 파일이 올린 그대로인지 확인할 수 있게)
  - 이 앱이 무엇을 설치하는지 (docs/what-gets-installed.md)
  - sudoers 규칙이나 설정 파일 형식이 바뀌었다면 **재설치가 필요하다는 사실을 맨 위에**
    (앱만 바꿔 넣은 사람은 전환이 조용히 실패하는 것을 자기 실수로 여긴다)
NEXT
