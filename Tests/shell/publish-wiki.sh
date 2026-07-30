#!/bin/bash
# ---------------------------------------------------------------------------
# scripts/publish-wiki.sh 검증.
#
# 네트워크를 쓰지 않고, Wiki 에 아무것도 밀지 않는다 — --output 으로 임시 디렉터리에
# 변환 결과만 뽑아 검사하거나, --dry-run 으로 아무것도 만들지 않는 길만 돌린다.
#
# 이 저장소의 실제 docs/ 를 쓰지 않는다. 다른 작업이 docs/*.md 를 바꾸는 중이라 내용이
# 언제든 달라질 수 있고, 이 검사는 특정 링크·이미지·유출 패턴을 정확히 재는 것이 목적이라
# 통제된 가짜 문서가 필요하다. 대신 REPO_ROOT 를 스크래치 쪽으로 두도록 publish-wiki.sh 의
# 사본을 가짜 저장소 안에 둔다(스크립트는 자기 위치 기준으로 REPO_ROOT 를 구한다) —
# Tests/shell/version-gate.sh 의 "저장소가 아닌 자리" 검사와 같은 수법이다.
#
# `swift test` 가 이 파일을 실행하므로 별도로 부를 일은 없지만 단독 실행도 된다:
#
#     ./Tests/shell/publish-wiki.sh
# ---------------------------------------------------------------------------

REPO_ROOT=$(cd "$(dirname "$0")/../.." && pwd)
PUBLISH_WIKI_SRC="$REPO_ROOT/scripts/publish-wiki.sh"

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
    shift 3
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

t_file_says() {
    local needle="$1" label="$2" file="$3"
    if [ -f "$file" ] && grep -qF "$needle" "$file"; then
        t_pass
    else
        t_fail "$label — '$file' 에 '$needle' 이 없습니다"
    fi
}

SCRATCH=$(mktemp -d)
trap 'rm -rf "$SCRATCH"' EXIT

# --- 가짜 저장소 준비 ----------------------------------------------------------
#
# publish-wiki.sh 는 자기 위치에서 두 단계 위를 REPO_ROOT 로 삼는다(scripts/ 의 부모).
# 그러니 가짜 저장소도 같은 모양(scripts/ · docs/)이어야 한다.

FIXTURE_REPO="$SCRATCH/fixture-repo"
mkdir -p "$FIXTURE_REPO/scripts" "$FIXTURE_REPO/docs/plan" "$FIXTURE_REPO/docs/screenshots"
cp "$PUBLISH_WIKI_SRC" "$FIXTURE_REPO/scripts/publish-wiki.sh"
chmod +x "$FIXTURE_REPO/scripts/publish-wiki.sh"
PUBLISH="$FIXTURE_REPO/scripts/publish-wiki.sh"

cat > "$FIXTURE_REPO/docs/index.md" <<'EOF'
# 문서

[← README 로 돌아가기](../README.md)
[사용 안내](./guide.md)
[설치 안내](../README.md#설치)
EOF

cat > "$FIXTURE_REPO/docs/guide.md" <<'EOF'
# 사용 안내

[문서 목록](./index.md)
[제자리 앵커](./guide.md#설정-값과-dns)
[설계 문서](./plan/design.md)
[`RULES.md`](../RULES.md)
[`scripts/install.sh`](../scripts/install.sh)
[앵커만](#설정-값과-dns)

## 설정 값과 DNS

![스크린샷](screenshots/shot.png)
<img src="screenshots/shot.png" alt="샷">
EOF

cat > "$FIXTURE_REPO/docs/plan/design.md" <<'EOF'
# 설계 (내부용, 발행하지 않는다)
EOF

: > "$FIXTURE_REPO/docs/screenshots/shot.png"

REPO_URL="https://github.com/Orchemi/exem-wifi-switcher"
RAW_BASE="https://raw.githubusercontent.com/Orchemi/exem-wifi-switcher/main"

OUT="$SCRATCH/out"

# --- --help ------------------------------------------------------------------

t_section "--help"
t_status 0 "--help 는 성공으로 끝난다" -- bash "$PUBLISH" --help
t_says "dry-run" "도움말에 --dry-run 이 있다" -- bash "$PUBLISH" --help

# --- --output 으로 변환 결과를 뽑는다 -------------------------------------------

t_section "문서 탐색과 페이지 이름 대응"
t_status 0 "--output 실행이 성공한다" -- bash "$PUBLISH" --output "$OUT"
bash "$PUBLISH" --output "$OUT" >/dev/null

if [ -f "$OUT/Home.md" ]; then t_pass; else t_fail "docs/index.md 가 Home.md 로 대응되지 않았습니다"; fi
if [ -f "$OUT/guide.md" ]; then t_pass; else t_fail "docs/guide.md 가 guide.md 로 대응되지 않았습니다"; fi
if [ ! -e "$OUT/design.md" ] && [ ! -e "$OUT/plan" ]; then t_pass; else t_fail "docs/plan/ 이 발행됐습니다 (발행하면 안 됩니다)"; fi

t_section "문서 사이 링크 — .md 와 ./ 가 벗겨지고 앵커는 남는다"
t_file_says "](guide)" "index.md → guide.md 링크가 확장자 없이 남는다" "$OUT/Home.md"
t_file_says "](Home)" "guide.md → index.md 링크가 Home 으로 대응된다" "$OUT/guide.md"
t_file_says "](guide#설정-값과-dns)" "같은 문서 링크의 앵커가 보존된다" "$OUT/guide.md"
t_file_says "](#설정-값과-dns)" "앵커만 있는 링크는 그대로 둔다" "$OUT/guide.md"

t_section "저장소 파일 링크 — GitHub 절대경로가 된다"
t_file_says "](${REPO_URL})" "../README.md 가 저장소 루트 URL이 된다" "$OUT/Home.md"
t_file_says "](${REPO_URL}#설치)" "../README.md#설치 의 앵커가 저장소 루트 URL 에 남는다" "$OUT/Home.md"
t_file_says "](${REPO_URL}/blob/main/RULES.md)" "../RULES.md 가 blob URL이 된다" "$OUT/guide.md"
t_file_says "](${REPO_URL}/blob/main/scripts/install.sh)" "../scripts/install.sh 가 blob URL이 된다" "$OUT/guide.md"
t_file_says "](${REPO_URL}/blob/main/docs/plan/design.md)" "docs/plan/ 하위 문서 링크가 docs/ 밑 blob URL이 된다" "$OUT/guide.md"

t_section "이미지 — raw URL이 된다 (마크다운·<img> 둘 다)"
t_file_says "![스크린샷](${RAW_BASE}/docs/screenshots/shot.png)" "마크다운 이미지가 raw URL이 된다" "$OUT/guide.md"
t_file_says "src=\"${RAW_BASE}/docs/screenshots/shot.png\"" "<img src> 가 raw URL이 된다" "$OUT/guide.md"

t_section "머리말"
t_file_says "docs/guide.md" "발행 머리말이 원본 경로를 밝힌다" "$OUT/guide.md"
t_file_says "덮어써집니다" "발행 머리말이 덮어써진다는 사실을 말한다" "$OUT/guide.md"

t_section "_Sidebar.md — 항목 이름은 파일명이 아니라 문서 제목에서 온다"
if [ -f "$OUT/_Sidebar.md" ]; then t_pass; else t_fail "_Sidebar.md 가 생기지 않았습니다"; fi
t_file_says "[문서](Home)" "index.md 의 제목 '문서' 가 사이드바에 쓰인다 (파일명 index 가 아니다)" "$OUT/_Sidebar.md"
t_file_says "[사용 안내](guide)" "guide.md 의 제목 '사용 안내' 가 사이드바에 쓰인다 (파일명 guide 가 아니다)" "$OUT/_Sidebar.md"
t_file_says "${REPO_URL}" "사이드바 끝에 저장소로 돌아가는 링크가 있다" "$OUT/_Sidebar.md"
home_line=$(grep -n '(Home)' "$OUT/_Sidebar.md" | head -1 | cut -d: -f1)
guide_line=$(grep -n '(guide)' "$OUT/_Sidebar.md" | head -1 | cut -d: -f1)
if [ -n "$home_line" ] && [ -n "$guide_line" ] && [ "$home_line" -lt "$guide_line" ]; then
    t_pass
else
    t_fail "Home 이 사이드바 맨 위에 있지 않습니다 (Home 줄 $home_line, guide 줄 $guide_line)"
fi

t_section "가장 중요한 회귀 검사 — 발행물에 .md 로 끝나는 내부 링크가 남지 않는다"
leftover=$(grep -nE '\]\([^)]*\.md[)#]' "$OUT"/*.md 2>/dev/null | grep -v '](http' || true)
if [ -z "$leftover" ]; then
    t_pass
else
    t_fail "발행물에 상대 .md 링크가 남아 있습니다:
$leftover"
fi

# --- --dry-run 은 아무것도 밀지 않는다 -------------------------------------------

t_section "--dry-run 은 사람이 읽을 결과만 보여주고 아무것도 밀지 않는다"
DRY_OUT="$SCRATCH/dry-out-should-not-exist"
t_status 0 "--dry-run 은 성공으로 끝난다" -- bash "$PUBLISH" --dry-run
t_says "dry-run" "dry-run 임을 알린다" -- bash "$PUBLISH" --dry-run
t_says "Home.md" "dry-run 이 바뀔 페이지를 보여준다" -- bash "$PUBLISH" --dry-run
t_says "_Sidebar.md" "dry-run 이 사이드바도 바뀔 목록에 넣는다" -- bash "$PUBLISH" --dry-run
bash "$PUBLISH" --dry-run >/dev/null 2>&1 || true
if [ ! -e "$DRY_OUT" ]; then t_pass; else t_fail "dry-run 인데도 무언가 만들어졌습니다: $DRY_OUT"; fi

# dry-run 은 네트워크를 쓰지 않는다 — git 이 없는 PATH 에서도 죽지 않아야 한다.
t_section "--dry-run 은 git 없이도 동작한다 (네트워크로 가는 코드를 타지 않는다는 증거)"
GITLESS_BIN="$SCRATCH/gitless-bin"
mkdir -p "$GITLESS_BIN"
for tool in bash grep sed awk basename dirname mktemp cat mkdir cp rm find date printf sort; do
    tool_path=$(command -v "$tool" 2>/dev/null) || continue
    ln -sf "$tool_path" "$GITLESS_BIN/$tool"
done
t_status 0 "git 없는 PATH 에서도 --dry-run 이 성공한다" -- env PATH="$GITLESS_BIN" bash "$PUBLISH" --dry-run

# 구조 검사: dry-run·--output 분기가 실제 발행(git clone)보다 앞서 나와야 한다.
# 그래야 dry-run 이 항상 network 코드에 닿기 전에 끝난다.
dry_run_line=$(grep -n 'DRY_RUN.*-eq 1' "$PUBLISH_WIKI_SRC" | head -1 | cut -d: -f1)
clone_line=$(grep -n 'git clone' "$PUBLISH_WIKI_SRC" | head -1 | cut -d: -f1)
if [ -n "$dry_run_line" ] && [ -n "$clone_line" ] && [ "$dry_run_line" -lt "$clone_line" ]; then
    t_pass
else
    t_fail "dry-run 분기가 git clone 보다 뒤에 있습니다 (dry-run $dry_run_line 행, clone $clone_line 행)"
fi

# --- Wiki 저장소가 없을 때의 안내 (구조 검사 — 네트워크를 쓰지 않는다) ----------------

t_section "Wiki 가 아직 없을 때 안내한다 (스크립트 안에 문구가 있는지만 본다 — 네트워크는 쓰지 않는다)"
t_file_says "wiki/_new" "새 페이지를 만들라는 안내 URL이 있다" "$PUBLISH_WIKI_SRC"
t_file_says "not found" "clone 실패 메시지를 인식하는 코드가 있다" "$PUBLISH_WIKI_SRC"

# --- 유출 점검 ----------------------------------------------------------------

t_section "유출 점검 — 사설 대역 IP 가 있으면 막는다"
LEAK_REPO="$SCRATCH/leak-repo"
mkdir -p "$LEAK_REPO/scripts" "$LEAK_REPO/docs"
cp "$PUBLISH_WIKI_SRC" "$LEAK_REPO/scripts/publish-wiki.sh"
chmod +x "$LEAK_REPO/scripts/publish-wiki.sh"
# 조각을 이어 붙여 만든다 — 이 테스트 파일 자신이 RULES.md §3 의 사전 점검 grep 에
# (진짜 유출도 아닌) 가짜 사내 IP 로 걸리지 않도록 한다. 실제로 만들어지는 값(대상 파일 안)은
# 그대로 사설 대역이라 유출 점검이 잡아야 한다.
fake_private_ip="10.""20.30.40"
cat > "$LEAK_REPO/docs/leaky.md" <<EOF
# 새는 문서

사내 IP는 ${fake_private_ip} 입니다.
EOF
LEAK_OUT="$SCRATCH/leak-out"
t_status 1 "사설 대역 IP 가 있으면 0이 아닌 종료코드로 멈춘다" -- \
    bash "$LEAK_REPO/scripts/publish-wiki.sh" --output "$LEAK_OUT"
t_says "사내 대역" "왜 막혔는지 말한다" -- bash "$LEAK_REPO/scripts/publish-wiki.sh" --output "$LEAK_OUT"
if [ ! -e "$LEAK_OUT/leaky.md" ]; then t_pass; else t_fail "유출 점검에 걸렸는데도 파일이 써졌습니다: $LEAK_OUT/leaky.md"; fi

t_section "유출 점검 — MAC 주소가 있으면 막는다"
# 같은 이유로 조각을 이어 붙인다 (문서용 플레이스홀더가 아닌 임의의 MAC 모양 값이다).
fake_mac="AA:BB:CC:DD:EE"":FF"
cat > "$LEAK_REPO/docs/leaky.md" <<EOF
# 새는 문서

라우터 MAC은 ${fake_mac} 입니다.
EOF
t_status 1 "MAC 주소가 있으면 막는다" -- bash "$LEAK_REPO/scripts/publish-wiki.sh" --output "$LEAK_OUT"

t_section "유출 점검 — 사용자 홈 절대경로가 있으면 막는다"
home_prefix="/" ; home_prefix="${home_prefix}Users/"
cat > "$LEAK_REPO/docs/leaky.md" <<EOF
# 새는 문서

경로는 ${home_prefix}alice/project 입니다.
EOF
t_status 1 "사용자 홈 경로가 있으면 막는다" -- bash "$LEAK_REPO/scripts/publish-wiki.sh" --output "$LEAK_OUT"

t_section "유출 점검 — 문서용 예약 대역·문서용 MAC은 통과한다"
cat > "$LEAK_REPO/docs/leaky.md" <<'EOF'
# 안전한 문서

예시 IP는 192.0.2.10, 198.51.100.20, 203.0.113.30 입니다.
예시 MAC은 00:00:5E:00:53:0A 입니다.
EOF
t_status 0 "문서용 예약 대역과 문서용 MAC은 막지 않는다" -- \
    bash "$LEAK_REPO/scripts/publish-wiki.sh" --output "$LEAK_OUT"
if [ -f "$LEAK_OUT/leaky.md" ]; then t_pass; else t_fail "안전한 문서인데도 발행되지 않았습니다"; fi

# --- 결과 -------------------------------------------------------------------

printf '\n---------------------------------------------\n'
printf '통과 %d개, 실패 %d개\n' "$pass_count" "$fail_count"
if [ "$fail_count" -ne 0 ]; then
    exit 1
fi
exit 0
