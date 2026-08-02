#!/bin/bash
# ---------------------------------------------------------------------------
# 서명·공증 갈림길 검증 (scripts/build-app.sh · scripts/package-release.sh).
#
# 두 스크립트는 환경변수 `SIGN_IDENTITY` · `NOTARY_PROFILE` 이 있으면 Developer ID 서명과
# 공증으로 가고, 없으면 예전 그대로 ad-hoc 으로 간다. **없는 쪽이 기본이다.**
# 인증서는 빌려 쓰는 것이라 사라질 수 있고, 사라지면 환경변수를 빼는 것만으로 돌아와야 한다.
#
# **여기서 잴 수 있는 것과 없는 것을 갈라 둔다.**
# 이 기계에는 Developer ID 인증서도 공증 자격증명도 없다. 그래서 실제 서명·제출·staple 은
# 재지 못한다. 대신 인증서 없이도 확실히 판정할 수 있는 것만 잰다.
#   · 환경변수가 없을 때 계획이 ad-hoc 인가 (무회귀)
#   · 환경변수가 있을 때 계획이 developer-id + hardened runtime 인가
#   · 없는 인증서 이름을 주면 **빌드를 시작하기 전에** 멈추는가
#   · 공증 자격증명만 주고 서명 신원을 빼면 **아무것도 만들기 전에** 멈추는가
#   · 순서가 지켜져 있는가 (유출 점검 → 공증 → zip)
#
# 여기 쓰는 인증서 이름·프로파일 이름은 **전부 가짜다.** 진짜 값은 저장소에 들어가지 않는다.
#
# 아무것도 빌드하지 않고, 네트워크를 쓰지 않고, 시스템을 건드리지 않는다.
# `swift test` 가 이 파일을 실행하므로 별도로 부를 일은 없지만 단독 실행도 된다:
#
#     ./Tests/shell/signing.sh
# ---------------------------------------------------------------------------

REPO_ROOT=$(cd "$(dirname "$0")/../.." && pwd)
BUILD_APP="$REPO_ROOT/scripts/build-app.sh"
PACKAGE_RELEASE="$REPO_ROOT/scripts/package-release.sh"
# Developer ID 서명에만 넘기는 빌드 입력. 번들 리소스가 아니라서 Resources/ 가 아니라 여기 있다.
ENTITLEMENTS="$REPO_ROOT/scripts/location.entitlements"
LOCATION_ENTITLEMENT_KEY="com.apple.security.personal-information.location"

# 키체인에 있을 리 없는 이름. 진짜 인증서 이름을 여기 적지 마라.
FAKE_IDENTITY="Developer ID Application: Nobody At All (0000000000)"
FAKE_PROFILE="not-a-real-notary-profile"

pass_count=0
fail_count=0

t_pass() { pass_count=$(( pass_count + 1 )); }
t_fail() {
    fail_count=$(( fail_count + 1 ))
    printf '  실패: %s\n' "$*" >&2
}
t_section() { printf '\n▸ %s\n' "$*"; }

# t_status <기대 종료코드> <설명> -- <명령...>
t_status() {
    local expected="$1" label="$2"
    shift 3   # 기대값 · 설명 · '--'
    local output status
    output=$("$@" 2>&1)
    status=$?
    if [ "$status" = "$expected" ]; then
        t_pass
    else
        t_fail "$label: 기대 종료코드 $expected, 실제 $status
$output"
    fi
}

# t_says <찾을 문구> <설명> -- <명령...>
t_says() {
    local needle="$1" label="$2"
    shift 3
    local output
    output=$("$@" 2>&1) || true
    case "$output" in
        *"$needle"*) t_pass ;;
        *) t_fail "$label: 출력에 '$needle' 이 없습니다
$output" ;;
    esac
}

# t_silent_about <없어야 할 문구> <설명> -- <명령...>
t_silent_about() {
    local needle="$1" label="$2"
    shift 3
    local output
    output=$("$@" 2>&1) || true
    case "$output" in
        *"$needle"*) t_fail "$label: 출력에 '$needle' 이 있습니다
$output" ;;
        *) t_pass ;;
    esac
}

# grep 으로 스크립트 본문을 보는 자리. 실행으로는 잴 수 없는 것(실제 서명·공증)의
# **모양과 순서**만이라도 붙잡아 둔다.
t_grep() {
    local label="$1" file="$2" pattern="$3"
    # 패턴이 '-' 로 시작할 수 있다 (--options runtime 처럼). -- 로 옵션 해석을 끊는다.
    if grep -qE -e "$pattern" -- "$file"; then t_pass; else t_fail "$label ($file 에 '$pattern' 이 없습니다)"; fi
}
t_grep_absent() {
    local label="$1" file="$2" pattern="$3"
    if grep -qE -e "$pattern" -- "$file"; then t_fail "$label ($file 에 '$pattern' 이 있습니다)"; else t_pass; fi
}

# 파일 안에서 A 가 B 보다 먼저 나오는지 본다. 이 두 스크립트에서는 순서가 곧 안전장치다.
t_order() {
    local label="$1" file="$2" first="$3" second="$4"
    local first_line second_line
    first_line=$(grep -nE -e "$first" -- "$file" | head -1 | cut -d: -f1)
    second_line=$(grep -nE -e "$second" -- "$file" | head -1 | cut -d: -f1)
    if [ -z "$first_line" ] || [ -z "$second_line" ]; then
        t_fail "$label: 찾지 못했습니다 ('$first' $first_line 행, '$second' $second_line 행)"
    elif [ "$first_line" -lt "$second_line" ]; then
        t_pass
    else
        t_fail "$label: 순서가 뒤집혔습니다 ('$first' $first_line 행, '$second' $second_line 행)"
    fi
}

SCRATCH=$(mktemp -d)
trap 'rm -rf "$SCRATCH"' EXIT

# --- 서명 계획: 환경변수가 없으면 ad-hoc ------------------------------------------
#
# 무회귀의 핵심이다. 인증서를 빌린 뒤에도, 빌린 것을 잃은 뒤에도 이 길은 그대로여야 한다.

t_section "SIGN_IDENTITY 가 없으면 ad-hoc 이다"
t_status 0 "--print-signing" -- env -u SIGN_IDENTITY bash "$BUILD_APP" --print-signing
t_says "mode=adhoc" "ad-hoc 모드를 보고한다" -- env -u SIGN_IDENTITY bash "$BUILD_APP" --print-signing
t_says "hardened-runtime=no" "hardened runtime 을 켜지 않는다" -- env -u SIGN_IDENTITY bash "$BUILD_APP" --print-signing
t_says "timestamp=no" "타임스탬프를 받지 않는다 (네트워크가 필요 없다)" -- \
    env -u SIGN_IDENTITY bash "$BUILD_APP" --print-signing
t_says "entitlements=no" "entitlements 를 넘기지 않는다 (hardened runtime 을 켜지 않는다)" -- \
    env -u SIGN_IDENTITY bash "$BUILD_APP" --print-signing
t_silent_about "developer-id" "developer-id 를 말하지 않는다" -- env -u SIGN_IDENTITY bash "$BUILD_APP" --print-signing
# 빈 문자열도 '없음'과 같게 봐야 한다 (`SIGN_IDENTITY=` 로 지우고 부르는 길이 있다).
t_says "mode=adhoc" "빈 값은 없는 것과 같다" -- env SIGN_IDENTITY= bash "$BUILD_APP" --print-signing

# --- 서명 계획: 환경변수가 있으면 Developer ID -------------------------------------
#
# 계획은 계획일 뿐이다. 인증서가 키체인에 있는지는 보지 않는다. 그래서 가짜 이름으로도 잰다.

t_section "SIGN_IDENTITY 가 있으면 Developer ID 다"
t_status 0 "--print-signing" -- env SIGN_IDENTITY="$FAKE_IDENTITY" bash "$BUILD_APP" --print-signing
t_says "mode=developer-id" "developer-id 모드를 보고한다" -- \
    env SIGN_IDENTITY="$FAKE_IDENTITY" bash "$BUILD_APP" --print-signing
# hardened runtime 은 공증의 전제 조건이다. 이게 꺼진 채 서명하면 공증이 그 이유로 반려된다.
t_says "hardened-runtime=yes" "hardened runtime 을 켠다 (공증의 전제 조건)" -- \
    env SIGN_IDENTITY="$FAKE_IDENTITY" bash "$BUILD_APP" --print-signing
t_says "timestamp=yes" "보안 타임스탬프를 받는다" -- \
    env SIGN_IDENTITY="$FAKE_IDENTITY" bash "$BUILD_APP" --print-signing
# hardened runtime 을 켜면 위치 entitlement 가 함께 가야 한다. 둘은 한 몸이다.
t_says "entitlements=yes" "entitlements 를 함께 넘긴다 (hardened runtime 과 한 몸이다)" -- \
    env SIGN_IDENTITY="$FAKE_IDENTITY" bash "$BUILD_APP" --print-signing

# 계획 출력에 인증서 이름이 섞이면 로그·이슈로 실명과 Team ID 가 새어 나간다.
t_silent_about "Nobody At All" "인증서 이름을 찍지 않는다" -- \
    env SIGN_IDENTITY="$FAKE_IDENTITY" bash "$BUILD_APP" --print-signing

t_section "--print-signing 은 아무것도 만들지 않는다"
t_silent_about "실행 파일 빌드" "빌드 단계로 들어가지 않는다" -- bash "$BUILD_APP" --print-signing
t_says "--print-signing" "--help 에 적혀 있다" -- bash "$BUILD_APP" --help

# --- 없는 인증서: 빌드 전에 멈춘다 --------------------------------------------------
#
# 빌드는 몇 분 걸리고 서명은 마지막 단계다. 이름 오타 하나를 알아채는 데 그 시간을 다 쓰면
# 사람은 다음부터 서명 없이 만들게 된다.

t_section "키체인에 없는 SIGN_IDENTITY 로는 빌드를 시작하지 않는다"
BUILD_OUTPUT_DIR="$SCRATCH/build-out"
mkdir -p "$BUILD_OUTPUT_DIR"
t_status 1 "없는 인증서 이름" -- \
    env SIGN_IDENTITY="$FAKE_IDENTITY" bash "$BUILD_APP" --output "$BUILD_OUTPUT_DIR"
# 사람이 다음에 무엇을 할지 알 수 있어야 한다. 종료코드만으로는 이름을 어디서 보는지 모른다.
t_says "security find-identity -v -p codesigning" "쓸 이름을 어디서 보는지 알려 준다" -- \
    env SIGN_IDENTITY="$FAKE_IDENTITY" bash "$BUILD_APP" --output "$BUILD_OUTPUT_DIR"
t_says "ad-hoc" "인증서 없이 만드는 길이 남아 있다고 말한다" -- \
    env SIGN_IDENTITY="$FAKE_IDENTITY" bash "$BUILD_APP" --output "$BUILD_OUTPUT_DIR"
# 빌드 단계 머리말이 찍혔다면 이미 늦은 것이다.
t_silent_about "1/5" "빌드 단계에 들어가지 않는다" -- \
    env SIGN_IDENTITY="$FAKE_IDENTITY" bash "$BUILD_APP" --output "$BUILD_OUTPUT_DIR"
if [ -z "$(ls -A "$BUILD_OUTPUT_DIR")" ]; then t_pass; else
    t_fail "멈춘 뒤에도 출력 디렉터리에 무언가 남았습니다: $(ls -A "$BUILD_OUTPUT_DIR")"
fi
# 점검이 빌드보다 앞에 있어야 한다 (실행으로 본 것을 파일 순서로도 못 박아 둔다).
t_order "인증서 점검이 swift build 보다 먼저다" "$BUILD_APP" 'security find-identity' 'swift build -c'

# --- 서명 명령의 모양 -------------------------------------------------------------
#
# 실제 서명은 인증서가 없어 재지 못한다. 명령의 모양만이라도 붙잡아 둔다.
# hardened runtime 이 ad-hoc 쪽으로 새면 ad-hoc 서명이 실패하고, Developer ID 쪽에서 빠지면
# 공증이 반려된다. 둘 다 인증서를 받은 날에야 알게 되는 종류의 고장이다.

t_section "ad-hoc 서명 명령은 예전 그대로다"
t_grep "ad-hoc 은 --sign - 로 서명한다" "$BUILD_APP" 'codesign --force --sign - --identifier "\$BUNDLE_ID" "\$APP_BUNDLE"'
t_grep "ad-hoc 단계 머리말이 그대로다" "$BUILD_APP" 'heading "5/5  ad-hoc 서명"'
t_grep "ad-hoc 서명 확인 문구가 그대로다" "$BUILD_APP" '서명 확인됨 \(ad-hoc, 식별자 %s\)'

t_section "Developer ID 서명 명령에 hardened runtime 과 타임스탬프가 있다"
t_grep "SIGN_IDENTITY 로 서명한다" "$BUILD_APP" 'codesign --force --sign "\$SIGN_IDENTITY"'
t_grep "hardened runtime 과 타임스탬프를 켠다" "$BUILD_APP" '--options runtime --timestamp'
# --timestamp 는 Apple 서버를 부른다. 네트워크가 끊긴 자리에서 실패했을 때 무엇을 볼지 알려야 한다.
t_grep "타임스탬프 실패에 네트워크를 짚어 준다" "$BUILD_APP" '네트워크 연결을 확인하세요'

# --- 위치 entitlement -----------------------------------------------------------
#
# hardened runtime(--options runtime)을 켠 서명에서는 위치 entitlement 가 없으면
# 위치 승인 창이 **조용히** 뜨지 않는다. 오류도 로그도 남지 않고, 서명과 공증은 전부 통과한다.
# 만든 사람 기계에서는 예전에 준 권한이 남아 있어 멀쩡히 돌아가므로, 처음 설치한 사람만 죽는다.
# 실측 근거는 scripts/build-app.sh 의 ENTITLEMENTS_FILE 자리에 적어 두었다.
#
# 인증서가 없어 실제 서명은 재지 못한다. 대신 인증서 없이도 확실히 판정되는 것만 잰다.
#   · 서명에 넘길 파일이 제자리에 있고 plist 로 읽히는가
#   · 그 파일에 위치 키가 있고, **그 하나뿐인가** (entitlement 는 하나하나가 샌드박스 완화다)
#   · 그 파일에 XML 주석이 없는가 (아래에 따로 적는다)
#   · 서명 명령과 계획 출력이 Developer ID 쪽에서만 그것을 말하는가
#   · 파일이 없으면 서명은커녕 빌드도 시작하지 않는가

t_section "서명에 넘길 entitlements 파일이 제자리에 있다"
if [ -f "$ENTITLEMENTS" ]; then t_pass; else t_fail "$ENTITLEMENTS 이 없습니다"; fi
t_status 0 "plist 로 읽힌다" -- plutil -lint "$ENTITLEMENTS"
t_grep "위치 키가 있다" "$ENTITLEMENTS" "$LOCATION_ENTITLEMENT_KEY"
t_grep "값이 true 다" "$ENTITLEMENTS" '<true/>'
# 필요 없는 entitlement 를 얹지 않는다. 하나가 늘면 그만큼 앱이 열린다.
entitlement_keys=$(grep -c '<key>' "$ENTITLEMENTS")
if [ "$entitlement_keys" = "1" ]; then t_pass; else
    t_fail "entitlement 가 $entitlement_keys 개 있습니다 (위치 하나만 두기로 했습니다)"
fi
# 빌드 입력이지 번들 리소스가 아니다. 번들에 넣으면 서명에 봉인된 값과 파일이 두 벌이 된다.
t_grep_absent "번들 안으로 복사하지 않는다" "$BUILD_APP" '(cp|install) .*ENTITLEMENTS_FILE'

# **주석을 넣으면 hardened runtime 서명이 실패한다.** entitlements 를 DER 로 굽는 파서가
# XML 주석을 받지 않아 codesign 이 "AMFIUnserializeXML: syntax error" 로 죽는다 (2026-08-03 실측).
# plutil -lint 는 주석을 통과시키므로 위 검사로는 잡히지 않는다. 설명을 파일 안에 적고 싶은
# 마음이 드는 자리라 여기서 못 박아 둔다 (설명은 scripts/build-app.sh 쪽에 있다).
t_section "entitlements 파일에 XML 주석을 넣지 않는다"
t_grep_absent "주석이 없다" "$ENTITLEMENTS" '<!--'

t_section "Developer ID 서명에만 entitlements 를 넘긴다"
t_grep "Developer ID 서명 명령에 있다" "$BUILD_APP" \
    '--options runtime --timestamp --entitlements "\$ENTITLEMENTS_FILE"'
# ad-hoc 은 hardened runtime 을 켜지 않으므로 이 entitlement 가 의미가 없다.
t_grep_absent "ad-hoc 서명 명령에는 없다" "$BUILD_APP" 'codesign --force --sign - .*--entitlements'

t_section "entitlements 파일이 없으면 Developer ID 빌드를 시작하지 않는다"
# scripts/build-app.sh 만 있고 entitlements 파일이 없는 가짜 저장소를 만든다.
# build-app.sh 는 자기 위치에서 저장소 뿌리를 잡으므로, 이것만으로 '파일이 사라진 저장소'가 된다.
NO_ENT_REPO="$SCRATCH/no-entitlements"
NO_ENT_OUT="$SCRATCH/no-entitlements-out"
mkdir -p "$NO_ENT_REPO/scripts" "$NO_ENT_OUT"
cp "$BUILD_APP" "$NO_ENT_REPO/scripts/build-app.sh"
NO_ENT_BUILD="$NO_ENT_REPO/scripts/build-app.sh"

t_status 1 "파일이 없는 저장소 + SIGN_IDENTITY" -- \
    env SIGN_IDENTITY="$FAKE_IDENTITY" bash "$NO_ENT_BUILD" --output "$NO_ENT_OUT"
t_says "entitlements 파일이 없습니다" "무엇이 없는지 말한다" -- \
    env SIGN_IDENTITY="$FAKE_IDENTITY" bash "$NO_ENT_BUILD" --output "$NO_ENT_OUT"
t_says "location.entitlements" "어느 파일인지 짚어 준다" -- \
    env SIGN_IDENTITY="$FAKE_IDENTITY" bash "$NO_ENT_BUILD" --output "$NO_ENT_OUT"
# 조용히 죽는 쪽을 먼저 막는다. 인증서 안내가 먼저 나오면 이 점검을 지나쳤다는 뜻이다.
t_silent_about "security find-identity" "인증서 점검보다 먼저 멈춘다" -- \
    env SIGN_IDENTITY="$FAKE_IDENTITY" bash "$NO_ENT_BUILD" --output "$NO_ENT_OUT"
t_silent_about "1/5" "빌드 단계에 들어가지 않는다" -- \
    env SIGN_IDENTITY="$FAKE_IDENTITY" bash "$NO_ENT_BUILD" --output "$NO_ENT_OUT"
if [ -z "$(ls -A "$NO_ENT_OUT")" ]; then t_pass; else
    t_fail "멈춘 뒤에도 출력 디렉터리에 무언가 남았습니다: $(ls -A "$NO_ENT_OUT")"
fi
# 점검이 빌드보다, 그리고 인증서 확인보다 앞에 있어야 한다 (실행으로 본 것을 파일 순서로도 못 박는다).
# 'security find-identity' 는 도움말에도 적혀 있다. 실제로 키체인을 보는 줄과 대 본다.
t_order "entitlements 점검이 인증서 점검보다 먼저다" "$BUILD_APP" \
    '\[ ! -f "\$ENTITLEMENTS_FILE" \]' 'CODESIGNING_IDENTITIES=\$\(security find-identity'
t_order "entitlements 점검이 swift build 보다 먼저다" "$BUILD_APP" \
    '\[ ! -f "\$ENTITLEMENTS_FILE" \]' 'swift build -c'

# **이 게이트는 ad-hoc 길을 막지 않는다.** 막으면 인증서 없는 기계에서 빌드가 통째로 죽는다.
t_says "mode=adhoc" "파일이 없어도 ad-hoc 계획은 그대로다" -- \
    env -u SIGN_IDENTITY bash "$NO_ENT_BUILD" --print-signing
t_status 0 "파일이 없어도 ad-hoc 계획은 0 으로 끝난다" -- \
    env -u SIGN_IDENTITY bash "$NO_ENT_BUILD" --print-signing
if command -v swift >/dev/null 2>&1; then
    # 실제 빌드 길도 막히지 않는지 본다. 이 가짜 저장소에는 Package.swift 가 없어 swift build 에서
    # 넘어지는데, **거기까지 갔다는 것**이 사전 점검을 통과했다는 증거다.
    t_says "1/5" "파일이 없어도 ad-hoc 빌드는 사전 점검을 지나간다" -- \
        env -u SIGN_IDENTITY bash "$NO_ENT_BUILD" --output "$NO_ENT_OUT"
    t_silent_about "entitlements 파일이 없습니다" "ad-hoc 길에서는 이 게이트를 걸지 않는다" -- \
        env -u SIGN_IDENTITY bash "$NO_ENT_BUILD" --output "$NO_ENT_OUT"
fi

t_section "주석이 든 entitlements 파일로는 Developer ID 빌드를 시작하지 않는다"
# 같은 방식으로, 이번에는 파일은 있는데 주석이 든 가짜 저장소를 만든다.
COMMENTED_REPO="$SCRATCH/commented-entitlements"
COMMENTED_OUT="$SCRATCH/commented-entitlements-out"
mkdir -p "$COMMENTED_REPO/scripts" "$COMMENTED_OUT"
cp "$BUILD_APP" "$COMMENTED_REPO/scripts/build-app.sh"
{
    printf '%s\n' '<?xml version="1.0" encoding="UTF-8"?>'
    printf '%s\n' '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">'
    printf '%s\n' '<!-- 왜 필요한지 여기 적고 싶어진다. 그러면 서명이 죽는다. -->'
    printf '%s\n' '<plist version="1.0">'
    printf '%s\n' '<dict>'
    printf '    <key>%s</key>\n' "$LOCATION_ENTITLEMENT_KEY"
    printf '%s\n' '    <true/>'
    printf '%s\n' '</dict>'
    printf '%s\n' '</plist>'
} > "$COMMENTED_REPO/scripts/location.entitlements"
COMMENTED_BUILD="$COMMENTED_REPO/scripts/build-app.sh"

# plist 로는 멀쩡히 읽힌다. 그래서 문법 검사만으로는 잡히지 않는다는 것을 함께 못 박는다.
t_status 0 "주석이 있어도 plist 문법 검사는 통과한다" -- \
    plutil -lint "$COMMENTED_REPO/scripts/location.entitlements"
t_status 1 "주석이 든 파일 + SIGN_IDENTITY" -- \
    env SIGN_IDENTITY="$FAKE_IDENTITY" bash "$COMMENTED_BUILD" --output "$COMMENTED_OUT"
t_says "XML 주석이 있습니다" "무엇이 문제인지 말한다" -- \
    env SIGN_IDENTITY="$FAKE_IDENTITY" bash "$COMMENTED_BUILD" --output "$COMMENTED_OUT"
t_says "build-app.sh" "설명을 어디에 적으면 되는지 말한다" -- \
    env SIGN_IDENTITY="$FAKE_IDENTITY" bash "$COMMENTED_BUILD" --output "$COMMENTED_OUT"
t_silent_about "1/5" "빌드 단계에 들어가지 않는다" -- \
    env SIGN_IDENTITY="$FAKE_IDENTITY" bash "$COMMENTED_BUILD" --output "$COMMENTED_OUT"

# --- 공증: 자격증명만 있고 서명 신원이 없으면 막는다 ---------------------------------
#
# ad-hoc 번들은 공증할 수 없다. 그대로 제출하면 Apple 쪽에서 반려되는데, 그때 받는 말로는
# 무엇이 잘못됐는지 알기 어렵다. 여기서 먼저 막는다.

t_section "NOTARY_PROFILE 만으로는 묶지 않는다"
t_status 1 "SIGN_IDENTITY 없이 NOTARY_PROFILE 만" -- \
    env -u SIGN_IDENTITY NOTARY_PROFILE="$FAKE_PROFILE" bash "$PACKAGE_RELEASE" --output "$SCRATCH/pkg-out"
t_says "ad-hoc" "왜 안 되는지 말한다" -- \
    env -u SIGN_IDENTITY NOTARY_PROFILE="$FAKE_PROFILE" bash "$PACKAGE_RELEASE" --output "$SCRATCH/pkg-out"
t_says "SIGN_IDENTITY" "무엇을 주면 되는지 말한다" -- \
    env -u SIGN_IDENTITY NOTARY_PROFILE="$FAKE_PROFILE" bash "$PACKAGE_RELEASE" --output "$SCRATCH/pkg-out"
# 조립·유출점검을 다 마친 뒤에 막으면 그 시간을 버린다. 첫 단계 머리말 전에 멈춰야 한다.
t_silent_about "1/6" "버전 단계에 들어가기 전에 멈춘다" -- \
    env -u SIGN_IDENTITY NOTARY_PROFILE="$FAKE_PROFILE" bash "$PACKAGE_RELEASE" --output "$SCRATCH/pkg-out"
if [ ! -d "$SCRATCH/pkg-out" ]; then t_pass; else
    t_fail "막은 뒤에도 출력 디렉터리를 만들었습니다: $SCRATCH/pkg-out"
fi

# --- 공증 계획 ---------------------------------------------------------------------
#
# 계획 출력은 "지금 이 환경변수로 돌리면 무슨 일이 벌어지나" 를 미리 보라고 있는 것이다.
# **그래서 계획이 실제 실행과 다른 답을 내면 없느니만 못하다.** 사람은 그 답을 믿고 움직인다.
# 한때 `NOTARY_PROFILE` 만 준 조합에서 계획은 "공증한다" 고 답하는데 실제로는 중단됐다.
# 아래 마지막 절이 네 조합 전부에서 둘이 같은 답을 내는지 실행해서 대조한다.

t_section "NOTARY_PROFILE 이 없으면 공증하지 않는다"
t_status 0 "--print-notary-plan" -- env -u NOTARY_PROFILE bash "$PACKAGE_RELEASE" --print-notary-plan
t_says "mode=skip" "건너뛴다고 보고한다" -- env -u NOTARY_PROFILE bash "$PACKAGE_RELEASE" --print-notary-plan
# SIGN_IDENTITY 만 있는 조합도 공증은 하지 않는다 (서명만 하고 묶는 길이다).
t_says "mode=skip" "서명만 하는 조합도 공증은 건너뛴다" -- \
    env -u NOTARY_PROFILE SIGN_IDENTITY="$FAKE_IDENTITY" bash "$PACKAGE_RELEASE" --print-notary-plan

t_section "둘 다 있으면 공증한다고 보고한다"
t_status 0 "--print-notary-plan" -- \
    env SIGN_IDENTITY="$FAKE_IDENTITY" NOTARY_PROFILE="$FAKE_PROFILE" bash "$PACKAGE_RELEASE" --print-notary-plan
t_says "mode=notarize" "공증한다고 보고한다" -- \
    env SIGN_IDENTITY="$FAKE_IDENTITY" NOTARY_PROFILE="$FAKE_PROFILE" bash "$PACKAGE_RELEASE" --print-notary-plan
t_says "profile=$FAKE_PROFILE" "어느 프로파일인지 보고한다" -- \
    env SIGN_IDENTITY="$FAKE_IDENTITY" NOTARY_PROFILE="$FAKE_PROFILE" bash "$PACKAGE_RELEASE" --print-notary-plan

# **묶을 수 없는 조합에 '공증한다' 고 답하면 안 된다.** 그렇게 답한 적이 있고, 그 조합으로
# 실제로 돌리면 첫 단계 전에 중단된다. 계획이 사람을 그리로 보내면 안 된다.
t_section "SIGN_IDENTITY 없는 NOTARY_PROFILE 은 계획도 막힌다고 답한다"
t_says "mode=blocked" "막힌다고 보고한다" -- \
    env -u SIGN_IDENTITY NOTARY_PROFILE="$FAKE_PROFILE" bash "$PACKAGE_RELEASE" --print-notary-plan
t_silent_about "mode=notarize" "공증한다고 답하지 않는다" -- \
    env -u SIGN_IDENTITY NOTARY_PROFILE="$FAKE_PROFILE" bash "$PACKAGE_RELEASE" --print-notary-plan
# 종료코드도 실제 실행과 같아야 한다. 0 을 내면 CI 가 계획만 보고 통과시킨 뒤 묶기에서 넘어진다.
t_status 1 "막히는 조합은 1 로 끝난다" -- \
    env -u SIGN_IDENTITY NOTARY_PROFILE="$FAKE_PROFILE" bash "$PACKAGE_RELEASE" --print-notary-plan
t_says "SIGN_IDENTITY" "무엇을 주면 되는지도 함께 말한다" -- \
    env -u SIGN_IDENTITY NOTARY_PROFILE="$FAKE_PROFILE" bash "$PACKAGE_RELEASE" --print-notary-plan

t_says "--print-notary-plan" "--help 에 적혀 있다" -- bash "$PACKAGE_RELEASE" --help
# 환경변수가 어떻든 --help 는 나와야 한다 (막히는 조합일수록 도움말을 찾는다).
t_status 0 "막히는 조합에서도 --help 는 나온다" -- \
    env -u SIGN_IDENTITY NOTARY_PROFILE="$FAKE_PROFILE" bash "$PACKAGE_RELEASE" --help
# 계획만 내는 자리다. 네트워크를 쓰거나 제출하면 안 된다.
t_silent_about "notarytool submit" "제출하지 않는다" -- \
    env SIGN_IDENTITY="$FAKE_IDENTITY" NOTARY_PROFILE="$FAKE_PROFILE" bash "$PACKAGE_RELEASE" --print-notary-plan

# 판정이 두 곳에 적히면 그 순간부터 갈라진다. 조건은 한 곳에만 있어야 한다.
t_section "계획과 실제 실행이 같은 판정 함수를 쓴다"
t_grep "판정 함수가 있다" "$PACKAGE_RELEASE" '^notary_blocked\(\) \{'
notary_blocked_uses=$(grep -c 'notary_blocked' "$PACKAGE_RELEASE")
# 정의 1 + 계획 출력 1 + 실행 경로 1 = 3 이상
if [ "$notary_blocked_uses" -ge 3 ]; then t_pass; else
    t_fail "notary_blocked 를 쓰는 자리가 $notary_blocked_uses 곳뿐입니다 (계획과 실행 둘 다 써야 합니다)"
fi
raw_condition_count=$(grep -c -- '-n "\$NOTARY_PROFILE" \] && \[ -z "\$SIGN_IDENTITY"' "$PACKAGE_RELEASE")
if [ "$raw_condition_count" -le 1 ]; then t_pass; else
    t_fail "같은 조건을 $raw_condition_count 곳에 적어 두었습니다 (한 곳이 바뀌면 조용히 갈라집니다)"
fi

# --- ad-hoc 번들을 공증에 들이지 않는다 ---------------------------------------------
#
# 환경변수는 이번에 무엇을 하려는지만 말한다. 번들에 실제로 무엇이 찍혀 있는지는 다른 문제다.
# --skip-build 로 예전에 ad-hoc 으로 만들어 둔 번들을 묶으면 그 둘이 갈라지고, 알아채지 못한 채
# 공증에 들어가 알 수 없는 이유로 반려된다. 그 자리를 막는지 본다.
#
# **여기는 인증서 없이도 실제로 잴 수 있다.** ad-hoc 서명한 가짜 번들을 만들어 놓고
# 서명 신원만 주면 되기 때문이다 (빌드도 네트워크도 필요 없다).

t_section "ad-hoc 으로 서명된 번들은 SIGN_IDENTITY 와 함께 묶지 않는다"
if command -v codesign >/dev/null 2>&1; then
    ADHOC_DIR="$SCRATCH/adhoc-bundle"
    ADHOC_APP="$ADHOC_DIR/EXEM Wifi Switcher.app"
    mkdir -p "$ADHOC_APP/Contents/MacOS"
    bash "$BUILD_APP" --print-plist > "$ADHOC_APP/Contents/Info.plist"
    printf '#!/bin/bash\nexit 0\n' > "$ADHOC_APP/Contents/MacOS/EXEM Wifi Switcher"
    chmod 0755 "$ADHOC_APP/Contents/MacOS/EXEM Wifi Switcher"
    printf 'APPL????' > "$ADHOC_APP/Contents/PkgInfo"
    # 번들이 품어야 할 다섯도 넣는다. 환경변수 없는 기본 경로가 끝까지 도는지 함께 재기 때문이다
    # (이것이 없으면 다른 이유로 멈춰서 무엇을 확인한 것인지 알 수 없게 된다).
    mkdir -p "$ADHOC_APP/Contents/Resources/scripts"
    for bundled in install.sh uninstall.sh apply save-config; do
        install -m 0755 "$REPO_ROOT/scripts/$bundled" "$ADHOC_APP/Contents/Resources/scripts/$bundled"
    done
    install -m 0644 "$REPO_ROOT/config.example.json" "$ADHOC_APP/Contents/Resources/scripts/config.example.json"
    codesign --force --sign - --identifier "com.horbis.exem-wifi-switcher" "$ADHOC_APP" 2>/dev/null

    t_status 1 "ad-hoc 번들 + SIGN_IDENTITY" -- \
        env SIGN_IDENTITY="$FAKE_IDENTITY" bash "$PACKAGE_RELEASE" --skip-build --output "$ADHOC_DIR"
    t_says "--skip-build" "어디를 의심해야 하는지 말한다" -- \
        env SIGN_IDENTITY="$FAKE_IDENTITY" bash "$PACKAGE_RELEASE" --skip-build --output "$ADHOC_DIR"
    t_says "공증이 반려됩니다" "그대로 두면 무엇이 일어나는지 말한다" -- \
        env SIGN_IDENTITY="$FAKE_IDENTITY" bash "$PACKAGE_RELEASE" --skip-build --output "$ADHOC_DIR"
    if [ ! -e "$ADHOC_DIR/EXEM-Wifi-Switcher.zip" ]; then t_pass; else
        t_fail "막았는데도 zip 이 만들어졌습니다"
    fi

    # 같은 번들을 환경변수 없이 묶는 길은 막지 않아야 한다 (기본 경로 무회귀).
    t_status 0 "환경변수가 없으면 같은 번들을 그대로 묶는다" -- \
        env -u SIGN_IDENTITY -u NOTARY_PROFILE bash "$PACKAGE_RELEASE" --skip-build --output "$ADHOC_DIR"
    if [ -e "$ADHOC_DIR/EXEM-Wifi-Switcher.zip" ]; then t_pass; else
        t_fail "환경변수 없는 기본 경로에서 zip 이 만들어지지 않았습니다"
    fi
fi

# --- 계획과 실제 실행이 어긋나지 않는다 (네 조합 전부) --------------------------------
#
# 계획 출력이 있는 이유는 "돌리기 전에 미리 보기" 하나다. 그러니 **계획과 실행이 갈라지는 순간
# 그 플래그는 사람을 잘못된 곳으로 보내는 장치가 된다.** 실제로 갈라진 적이 있다.
#
# 네 조합을 전부 실행해서 두 답을 맞춰 본다. 무엇을 맞춰 보는지 분명히 해 둔다.
#   맞춰 본다   **환경변수만으로 정해지는 것**. 이 조합이 막히는가 아닌가.
#               계획이 mode=blocked 라고 답한 조합만 실행에서 그 사유로 멈춰야 하고,
#               계획이 막히지 않는다고 답한 조합은 실행에서 그 사유로 멈추면 안 된다.
#   맞춰 보지 않는다  인증서가 키체인에 있는지, 번들이 정말 그것으로 서명됐는지.
#               이것들은 환경변수가 아니라 환경이고, 계획을 낸 뒤에도 바뀐다.
#               (그래서 아래 실행에서 SIGN_IDENTITY 를 준 조합은 다른 사유로 멈춘다. 정상이다.)
#
# 실행 쪽은 --skip-build 로 위에서 만든 가짜 번들을 쓴다. 빌드도 네트워크도 필요 없다.

t_section "네 조합에서 계획과 실제 실행이 같은 판정을 낸다"
if [ -n "${ADHOC_DIR:-}" ] && [ -d "$ADHOC_DIR" ]; then
    BLOCKED_REASON="NOTARY_PROFILE 은 있는데 SIGN_IDENTITY 가 없습니다"
    MATRIX_DIR="$SCRATCH/matrix"

    for combo in none sign notary both; do
        rm -rf "$MATRIX_DIR"
        cp -R "$ADHOC_DIR" "$MATRIX_DIR"
        rm -f "$MATRIX_DIR/EXEM-Wifi-Switcher.zip"

        # env 는 첫 비옵션 인자에서 옵션 해석을 멈춘다. -u 를 대입보다 **먼저** 적어야 한다.
        case "$combo" in
            none)   combo_env=(env -u SIGN_IDENTITY -u NOTARY_PROFILE) ;;
            sign)   combo_env=(env -u NOTARY_PROFILE SIGN_IDENTITY="$FAKE_IDENTITY") ;;
            notary) combo_env=(env -u SIGN_IDENTITY NOTARY_PROFILE="$FAKE_PROFILE") ;;
            both)   combo_env=(env SIGN_IDENTITY="$FAKE_IDENTITY" NOTARY_PROFILE="$FAKE_PROFILE") ;;
        esac

        plan_output=$("${combo_env[@]}" bash "$PACKAGE_RELEASE" --print-notary-plan 2>&1)
        plan_status=$?
        run_output=$("${combo_env[@]}" bash "$PACKAGE_RELEASE" --skip-build --output "$MATRIX_DIR" 2>&1) || true

        case "$plan_output" in *"mode=blocked"*) plan_blocked=1 ;; *) plan_blocked=0 ;; esac
        case "$run_output" in *"$BLOCKED_REASON"*) run_blocked=1 ;; *) run_blocked=0 ;; esac

        if [ "$plan_blocked" = "$run_blocked" ]; then t_pass; else
            t_fail "조합 '$combo' 에서 계획과 실행이 다릅니다 (계획 막힘=$plan_blocked, 실행 막힘=$run_blocked)
계획:
$plan_output
실행:
$run_output"
        fi

        # 막힌다고 답했으면 종료코드도 실행과 같아야 한다 (둘 다 1).
        if [ "$plan_blocked" = "1" ]; then
            if [ "$plan_status" = "1" ]; then t_pass; else
                t_fail "조합 '$combo' 에서 계획이 막힌다고 하면서 종료코드 $plan_status 를 냈습니다"
            fi
        else
            if [ "$plan_status" = "0" ]; then t_pass; else
                t_fail "조합 '$combo' 에서 막히지 않는데 계획이 종료코드 $plan_status 를 냈습니다"
            fi
        fi
    done
    rm -rf "$MATRIX_DIR"
fi

# --- 순서: 유출 점검 → 공증 → 티켓 → zip ---------------------------------------------
#
# 이 세 순서는 전부 실행해 봐야 알 수 있는 것이 아니라, 뒤집혀도 아무 오류 없이 통과한다.
# 그래서 파일 순서로 못 박는다.
#   · 유출 점검이 공증보다 먼저여야 한다. 공증은 번들을 Apple 서버에 올리는 행위라,
#     사내 값이 섞인 번들을 올린 시점에 이미 유출이다.
#   · staple 이 zip 보다 먼저여야 한다. 티켓은 zip 이 아니라 '.app' 에 붙는다.
#     뒤집히면 티켓 없는 zip 이 나가고, 만든 사람 기계에서는 잘 열려 알아채지 못한다.

# --- 배포 직전에 번들의 entitlement 를 다시 본다 ------------------------------------
#
# 위의 build-app 게이트는 **만들 때** 빠지는 것을 막는다. 그런데 --skip-build 로 예전 번들을
# 묶는 길이 있고, 그 번들이 entitlement 없이 서명됐는지는 환경변수로 알 수 없다.
# 이번 사고는 "서명·공증은 전부 통과하는데 앱 기능만 죽는" 모양이었고, 배포 직전에 그것을 잡을
# 그물이 하나도 없었다. 그래서 조립된 번들에서 직접 읽어 확인한다.
#
# 실행으로는 여기까지 오지 못한다 (그 앞의 Developer ID 서명 확인이 인증서 없는 기계에서 먼저 막는다).
# 그러니 명령의 모양과 자리만이라도 붙잡아 둔다.

t_section "묶기 전에 번들의 위치 entitlement 를 읽어 확인한다"
t_grep "번들에서 직접 읽는다" "$PACKAGE_RELEASE" 'codesign -d --entitlements -'
t_grep "어떤 키를 찾는지 적혀 있다" "$PACKAGE_RELEASE" "$LOCATION_ENTITLEMENT_KEY"
t_grep "없으면 무엇이 벌어지는지 말한다" "$PACKAGE_RELEASE" '자동 전환이 통째로 죽습니다'
# ad-hoc 번들에는 이 entitlement 가 없고 있을 이유도 없다. Developer ID 쪽에서만 본다
# (기본 경로에서 이 점검이 걸리면 인증서 없는 사람이 릴리즈를 통째로 못 만든다).
t_order "서명 주체 확인 → entitlement 확인" "$PACKAGE_RELEASE" \
    'Authority=Developer ID Application' 'codesign -d --entitlements -'
t_order "entitlement 확인 → 배포 전 점검" "$PACKAGE_RELEASE" \
    'codesign -d --entitlements -' 'heading "4/6  배포 전 점검"'

t_section "유출 점검이 공증보다 먼저다"
t_order "배포 전 점검 → 공증" "$PACKAGE_RELEASE" 'heading "4/6  배포 전 점검"' 'heading "5/6  공증"'
t_order "유출 스캔 → 제출" "$PACKAGE_RELEASE" 'scan_for "사내 대역으로 보이는 IP"' 'notarytool submit'

t_section "티켓을 붙인 뒤에 zip 을 만든다"
t_order "공증 → zip" "$PACKAGE_RELEASE" 'heading "5/6  공증"' 'heading "6/6  zip"'
t_order "staple → zip" "$PACKAGE_RELEASE" 'stapler staple' 'ditto -c -k --sequesterRsrc --keepParent "\$APP_BUNDLE" "\$ARCHIVE"'
t_grep "붙인 티켓을 다시 읽어 확인한다" "$PACKAGE_RELEASE" 'stapler validate'
# staple 은 번들 안에 파일을 하나 더 넣는다. 그 뒤 서명이 온전한지 다시 봐야 한다.
t_order "staple → 서명 재검증" "$PACKAGE_RELEASE" 'stapler staple' 'codesign --verify --strict "\$APP_BUNDLE" \|\| die "티켓'
# 반려됐을 때 사유를 어디서 보는지 알려 주지 않으면 사람은 "Invalid" 한 줄만 들고 막힌다.
t_grep "반려 사유를 보는 명령을 알려 준다" "$PACKAGE_RELEASE" 'notarytool log'

t_section "제출용 zip 과 배포용 zip 은 다른 파일이다"
# 같은 파일을 쓰면 제출 시점에 만든(티켓 없는) zip 이 그대로 배포물이 된다.
t_grep "제출용 zip 을 따로 만든다" "$PACKAGE_RELEASE" 'SUBMISSION_ZIP='
t_grep_absent "제출에 배포용 zip 을 쓰지 않는다" "$PACKAGE_RELEASE" 'notarytool submit "\$ARCHIVE"'

# --- 기본 경로 무회귀 ---------------------------------------------------------------
#
# 환경변수가 없을 때 예전과 같은 말을 하는지 본다. 문구가 바뀌면 릴리즈 노트에 옮겨 적는
# 사람이 다른 것을 적게 된다.

t_section "환경변수가 없으면 예전 문구 그대로다"
t_grep "ad-hoc 번들의 서명 확인 문구" "$PACKAGE_RELEASE" '서명 확인 \(ad-hoc — 공증은 하지 않습니다\)'
t_grep "공증을 건너뛴다고 한 줄 알린다" "$PACKAGE_RELEASE" 'NOTARY_PROFILE 이 없어 건너뜁니다'
t_grep "공증이 없으면 Gatekeeper 여는 방법을 적으라고 한다" "$PACKAGE_RELEASE" '확인 없이 열기'
# 공증한 릴리즈에는 그 안내 대신 위치 권한을 다시 줘야 한다는 말이 들어가야 한다.
t_grep "공증한 릴리즈에는 위치 권한 안내를 넣는다" "$PACKAGE_RELEASE" '위치 권한을 한 번 다시 줘야 합니다'

# --- 저장소에 실값이 없는가 ---------------------------------------------------------
#
# 인증서 이름에는 사람 실명과 Team ID 가 들어간다. 저장소는 public 이다.

t_section "인증서 정보를 파일에 적어 두지 않았다"
for script in "$BUILD_APP" "$PACKAGE_RELEASE"; do
    # 환경변수로 받기만 하고, 값을 스크립트에 박아 두면 안 된다.
    t_grep_absent "인증서 이름이 박혀 있다" "$script" '^SIGN_IDENTITY="Developer ID'
    t_grep_absent "공증 프로파일 이름이 박혀 있다" "$script" '^NOTARY_PROFILE="[A-Za-z0-9]'
    # Team ID 는 대문자·숫자 10자리다. 괄호에 담긴 그 모양이 파일에 있으면 안 된다.
    t_grep_absent "Team ID 로 보이는 값이 있다" "$script" '\([A-Z0-9]{10}\)'
done

# --- 결과 -------------------------------------------------------------------

printf '\n---------------------------------------------\n'
printf '통과 %d개, 실패 %d개\n' "$pass_count" "$fail_count"
if [ "$fail_count" -ne 0 ]; then
    exit 1
fi
exit 0
