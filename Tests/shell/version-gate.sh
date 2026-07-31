#!/bin/bash
# ---------------------------------------------------------------------------
# scripts/package-release.sh 의 **버전 게이트** 검증.
#
# 태그와 번들 버전이 어긋난 zip 을 올리면 태그를 보고 내려받은 사람이 다른 버전을 받고,
# README 가 권하는 SHA-256 대조가 무엇을 확인한 것인지 알 수 없게 된다. 그것을 막는 검사다.
#
# **레포에 태그를 만들지 않는다.** 판정은 `--check-tag <버전> <태그...>` 로 값을 주입해 재고,
# 번들 버전 대조는 임시 디렉터리에 만든 가짜 Info.plist 로 잰다.
# zip 을 만들지도, 시스템을 건드리지도 않는다.
#
# `swift test` 가 이 파일을 실행하므로 별도로 부를 일은 없지만 단독 실행도 된다:
#
#     ./Tests/shell/version-gate.sh
# ---------------------------------------------------------------------------

REPO_ROOT=$(cd "$(dirname "$0")/../.." && pwd)
PACKAGE_RELEASE="$REPO_ROOT/scripts/package-release.sh"
BUILD_APP="$REPO_ROOT/scripts/build-app.sh"

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
        t_fail "$label — 기대 종료코드 $expected, 실제 $status
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
        *) t_fail "$label — 출력에 '$needle' 이 없습니다
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
        *"$needle"*) t_fail "$label — 출력에 '$needle' 이 있습니다
$output" ;;
        *) t_pass ;;
    esac
}

# --- 태그가 없는 상태 ----------------------------------------------------------
#
# 개발 중 zip 을 만드는 정상 상황이다. **막지 않는다** — 막으면 릴리즈가 아닌 빌드를
# 하려던 사람이 태그를 달게 되고, 그러면 태그가 릴리즈 지점을 가리키지 않게 된다.

t_section "HEAD 에 태그가 없으면 지나간다"
t_status 0 "태그 없음" -- bash "$PACKAGE_RELEASE" --check-tag 0.1.0
t_says "개발 빌드" "태그가 없다는 사실을 한 줄로 알린다" -- bash "$PACKAGE_RELEASE" --check-tag 0.1.0

# 릴리즈 태그 형태가 아닌 태그는 판정에 넣지 않는다 (`v<major>.<minor>.<patch>` 만 본다).
t_section "릴리즈 태그가 아닌 태그는 판정하지 않는다"
for tag in nightly latest v0.1 v1 0.1.0 v0.1.0-rc1 release-0.1.0; do
    t_status 0 "태그 '$tag' 를 릴리즈 태그로 보지 않는다" -- bash "$PACKAGE_RELEASE" --check-tag 0.1.0 "$tag"
done

# --- 일치 ------------------------------------------------------------------

t_section "태그와 번들 버전이 같으면 지나간다"
t_status 0 "v0.1.0 ↔ 0.1.0" -- bash "$PACKAGE_RELEASE" --check-tag 0.1.0 v0.1.0
t_status 0 "v1.2.3 ↔ 1.2.3" -- bash "$PACKAGE_RELEASE" --check-tag 1.2.3 v1.2.3
t_status 0 "다른 종류의 태그가 함께 붙어 있어도 된다" -- \
    bash "$PACKAGE_RELEASE" --check-tag 0.1.0 nightly v0.1.0

# --- 어긋남 (막는다) ----------------------------------------------------------

t_section "태그와 번들 버전이 다르면 막는다"
t_status 1 "v0.2.0 ↔ 0.1.0" -- bash "$PACKAGE_RELEASE" --check-tag 0.1.0 v0.2.0
t_status 1 "v0.1.1 ↔ 0.1.0 (patch 만 달라도)" -- bash "$PACKAGE_RELEASE" --check-tag 0.1.0 v0.1.1
# 한 커밋에 두 버전이 걸려 있으면 어느 태그를 보고 내려받았는지에 따라 대조 결과가 갈린다.
t_status 1 "맞는 태그가 하나 있어도 어긋난 태그가 있으면 막는다" -- \
    bash "$PACKAGE_RELEASE" --check-tag 0.1.0 v0.1.0 v0.2.0

# 왜 막는지와 어떻게 맞추는지가 함께 나와야 한다. 종료코드만으로는 사람이 다음 행동을 알 수 없다.
t_says "v0.2.0" "어긋난 태그를 그대로 보여준다" -- bash "$PACKAGE_RELEASE" --check-tag 0.1.0 v0.2.0
t_says "SHA-256" "왜 문제인지 말한다" -- bash "$PACKAGE_RELEASE" --check-tag 0.1.0 v0.2.0
t_says "SHORT_VERSION" "어디를 고치면 되는지 말한다" -- bash "$PACKAGE_RELEASE" --check-tag 0.1.0 v0.2.0

# --- 인자 --------------------------------------------------------------------

t_section "버전 없이 부르면 막는다"
t_status 1 "--check-tag 뒤에 버전이 없다" -- bash "$PACKAGE_RELEASE" --check-tag

# --- git 을 읽는 자리 ----------------------------------------------------------
#
# 소스 zip 을 받아 푼 자리·git 이 없는 기계·얕은 클론에서도 죽지 않아야 한다.
# 볼 것이 없는 것과 어긋난 것은 다르다 — 볼 것이 없으면 조용히 지나간다.

SCRATCH=$(mktemp -d)
trap 'rm -rf "$SCRATCH"' EXIT

t_section "저장소가 아닌 자리에서도 태그 읽기가 죽지 않는다"
# 레포 밖에 스크립트 사본을 두고 부른다 (사본의 REPO_ROOT 는 git 저장소가 아니다).
mkdir -p "$SCRATCH/outside/scripts"
cp "$PACKAGE_RELEASE" "$SCRATCH/outside/scripts/package-release.sh"
outside_tags=$(bash "$SCRATCH/outside/scripts/package-release.sh" --print-head-tags 2>&1)
outside_status=$?
if [ "$outside_status" = "0" ]; then t_pass; else t_fail "저장소가 아닌 자리에서 종료코드 $outside_status
$outside_tags"; fi
if [ -z "$outside_tags" ]; then t_pass; else t_fail "저장소가 아닌 자리에서 태그를 냈습니다: '$outside_tags'"; fi

t_section "git 이 PATH 에 없어도 죽지 않는다"
mkdir -p "$SCRATCH/bin"
for tool in bash grep sed awk uname mktemp dirname; do
    tool_path=$(command -v "$tool" 2>/dev/null) || continue
    ln -sf "$tool_path" "$SCRATCH/bin/$tool"
done
gitless_tags=$(PATH="$SCRATCH/bin" bash "$PACKAGE_RELEASE" --print-head-tags 2>&1)
gitless_status=$?
if [ "$gitless_status" = "0" ]; then t_pass; else t_fail "git 없는 PATH 에서 종료코드 $gitless_status
$gitless_tags"; fi
if [ -z "$gitless_tags" ]; then t_pass; else t_fail "git 없는 PATH 에서 태그를 냈습니다: '$gitless_tags'"; fi
# 판정 자체도 같은 PATH 에서 돌아야 한다 (grep 만 쓴다).
t_status 0 "git 없는 PATH 에서 판정" -- env PATH="$SCRATCH/bin" bash "$PACKAGE_RELEASE" --check-tag 0.1.0 v0.1.0
t_status 1 "git 없는 PATH 에서도 어긋남은 잡는다" -- env PATH="$SCRATCH/bin" bash "$PACKAGE_RELEASE" --check-tag 0.1.0 v0.2.0

t_section "이 레포에서 태그 읽기가 조용히 성공한다"
t_status 0 "--print-head-tags" -- bash "$PACKAGE_RELEASE" --print-head-tags

# --- 이 검사가 실제 스크립트에 걸려 있는가 ---------------------------------------
#
# 판정 함수만 있고 파이프라인이 부르지 않으면 게이트가 아니다.

t_section "게이트가 파이프라인에 걸려 있다"
if grep -q 'check_version_against_tags "\$VERSION" \$(tags_at_head)' "$PACKAGE_RELEASE"; then
    t_pass
else
    t_fail "package-release.sh 가 조립 전에 태그 판정을 부르지 않습니다"
fi
# 조립보다 먼저 봐야 한다 — 어긋난 버전으로는 만들 zip 이 없다.
gate_line=$(grep -n 'check_version_against_tags "\$VERSION"' "$PACKAGE_RELEASE" | head -1 | cut -d: -f1)
build_line=$(grep -n 'build-app.sh" --output' "$PACKAGE_RELEASE" | head -1 | cut -d: -f1)
if [ -n "$gate_line" ] && [ -n "$build_line" ] && [ "$gate_line" -lt "$build_line" ]; then
    t_pass
else
    t_fail "태그 판정이 번들 조립보다 뒤에 있습니다 (판정 $gate_line 행, 조립 $build_line 행)"
fi

# --- 번들 버전 ↔ SHORT_VERSION --------------------------------------------------
#
# --skip-build 로 예전 번들을 묶으면 스크립트가 찍어 주는 버전만 새것이 되고, 그 값이
# 그대로 릴리즈 노트로 간다. 그 자리를 막는 검사다.

t_section "번들 Info.plist 의 버전을 build-app.sh 의 SHORT_VERSION 과 대조한다"
if grep -q 'bundle_short_version "\$APP_BUNDLE"' "$PACKAGE_RELEASE"; then t_pass; else
    t_fail "package-release.sh 가 번들 Info.plist 의 버전을 보지 않습니다"
fi

fake_bundle() {
    local dir="$1" version="$2"
    mkdir -p "$dir/Contents"
    cat > "$dir/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleShortVersionString</key>
    <string>${version}</string>
</dict>
</plist>
PLIST
}

if command -v plutil >/dev/null 2>&1; then
    # 스크립트의 bundle_short_version 과 같은 명령으로 읽는다.
    read_bundle_version() {
        plutil -extract CFBundleShortVersionString raw -o - "$1/Contents/Info.plist" 2>/dev/null || true
    }

    fake_bundle "$SCRATCH/match.app" "0.1.0"
    bundle_version=$(read_bundle_version "$SCRATCH/match.app")
    if [ "$bundle_version" = "0.1.0" ]; then t_pass; else
        t_fail "번들 버전을 읽지 못했습니다 (실제 '$bundle_version')"
    fi

    fake_bundle "$SCRATCH/stale.app" "0.0.9"
    bundle_version=$(read_bundle_version "$SCRATCH/stale.app")
    if [ "$bundle_version" != "0.1.0" ]; then t_pass; else
        t_fail "예전 번들과 새 버전을 구별하지 못했습니다"
    fi

    # 키가 없는 번들은 빈 값이 나온다 — 빈 값은 버전과 같을 수 없으므로 그대로 걸린다.
    mkdir -p "$SCRATCH/empty.app/Contents"
    printf '<?xml version="1.0" encoding="UTF-8"?>\n<plist version="1.0"><dict/></plist>\n' \
        > "$SCRATCH/empty.app/Contents/Info.plist"
    bundle_version=$(read_bundle_version "$SCRATCH/empty.app")
    if [ -z "$bundle_version" ]; then t_pass; else
        t_fail "버전 키가 없는 번들에서 값이 나왔습니다: '$bundle_version'"
    fi
fi

# --- zip 이름은 고정이다 --------------------------------------------------------
#
# README 의 내려받기 버튼은 releases/latest/download/EXEM-Wifi-Switcher.zip 을 가리킨다.
# 자산 이름은 그 주소의 마지막 조각이라 이름에 버전이 들어오는 순간 버튼이 404 를 받는다.
# 사람이 눈으로 보고 알아채는 종류의 고장이 아니다 (버튼은 그대로 있고 누르면 안 될 뿐이다).

t_section "zip 이름에 버전이 들어가지 않는다"
if grep -q 'ARCHIVE="\$OUTPUT_DIR/\$ARCHIVE_BASENAME\.zip"' "$PACKAGE_RELEASE"; then t_pass; else
    t_fail "zip 이름이 '\$ARCHIVE_BASENAME.zip' 고정이 아닙니다 (README 의 내려받기 버튼이 끊깁니다)"
fi
if grep -qE 'ARCHIVE="[^"]*\$(\{)?VERSION' "$PACKAGE_RELEASE"; then
    t_fail "zip 이름에 버전이 들어 있습니다 (releases/latest/download 주소가 릴리즈마다 달라집니다)"
else
    t_pass
fi

# 버튼이 가리키는 주소와 실제 자산 이름이 같은 값에서 나와야 한다.
if grep -q 'RELEASE_DOWNLOAD_URL="https://github.com/[^"]*/releases/latest/download/\$ARCHIVE_BASENAME\.zip"' "$PACKAGE_RELEASE"; then
    t_pass
else
    t_fail "고정 내려받기 주소가 ARCHIVE_BASENAME 에서 나오지 않습니다 (주소와 자산 이름이 갈라집니다)"
fi

# README 의 버튼이 정말 그 주소를 가리키는지 본다. 스크립트만 맞고 README 가 옛 주소면
# 고쳐야 할 곳을 반쪽만 고친 것이다.
if [ -f "$REPO_ROOT/README.md" ]; then
    if grep -q 'releases/latest/download/EXEM-Wifi-Switcher\.zip' "$REPO_ROOT/README.md"; then
        t_pass
    else
        t_fail "README 의 내려받기 버튼이 고정 주소를 가리키지 않습니다"
    fi
fi

# --- 버전의 출처가 하나인가 -----------------------------------------------------
#
# 릴리즈 노트에 적을 버전·Info.plist·이 검사가 모두 같은 값을 봐야 게이트가 뜻을 갖는다.
# 다른 자리에 버전을 적으면 그 자리가 조용히 갈라진다.

t_section "버전의 출처는 build-app.sh 의 SHORT_VERSION 하나다"
version_from_script=$("$BUILD_APP" --print-version)
if [ -n "$version_from_script" ]; then t_pass; else t_fail "--print-version 이 빈 값을 냈습니다"; fi

plist_version=$("$BUILD_APP" --print-plist | \
    plutil -extract CFBundleShortVersionString raw -o - - 2>/dev/null || true)
if [ "$plist_version" = "$version_from_script" ]; then t_pass; else
    t_fail "Info.plist 의 버전('$plist_version')이 --print-version('$version_from_script')과 다릅니다"
fi

# package-release.sh 는 버전을 스스로 적지 않고 build-app.sh 에서 받아 온다.
if grep -q 'VERSION=$("$REPO_ROOT/scripts/build-app.sh" --print-version)' "$PACKAGE_RELEASE"; then
    t_pass
else
    t_fail "package-release.sh 가 버전을 build-app.sh 에서 받지 않습니다"
fi
# 버전 문자열을 따로 박아 두면 두 출처가 된다.
if grep -qE '^[A-Z_]*VERSION="[0-9]+\.[0-9]+\.[0-9]+"' "$PACKAGE_RELEASE"; then
    t_fail "package-release.sh 에 버전이 직접 박혀 있습니다"
else
    t_pass
fi

# --- 결과 -------------------------------------------------------------------

printf '\n---------------------------------------------\n'
printf '통과 %d개, 실패 %d개\n' "$pass_count" "$fail_count"
if [ "$fail_count" -ne 0 ]; then
    exit 1
fi
exit 0
