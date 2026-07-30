#!/bin/bash
# ---------------------------------------------------------------------------
# publish-wiki.sh — docs/*.md 를 GitHub Wiki 페이지로 발행한다.
#
# 원본은 이 저장소의 docs/ 에 둔다. 그래야 버전과 함께 태그되고 RULES.md 의 유출 점검
# 그물 안에 있는다 — Wiki 를 직접 고치면 그 그물을 벗어난다. 이 스크립트가 매 발행마다
# 그 그물을 다시 던지고, docs/ 하나를 사이드바 있는 Wiki 로 옮겨 심는다.
#
# 하는 일은 넷뿐이다.
#   1. docs/ 바로 아래의 .md 를 훑는다 (docs/plan/ · docs/screenshots/ 는 뺀다)
#   2. 문서 사이 링크 · 저장소 파일 링크 · 이미지 경로를 Wiki 에서 통하는 형태로 바꾸고,
#      머리말과 _Sidebar.md 를 만든다
#   3. 바뀐 내용에 RULES.md §3 유출 점검을 다시 돌린다 — 하나라도 걸리면 아무것도 밀지 않는다
#   4. Wiki 저장소를 받아 바뀐 페이지를 커밋·푸시한다 (--dry-run · --output 은 여기서 멈춘다)
#
# 페이지 이름 대응은 docs/index.md → Home.md 하나만 고정한다. 그 밖에는 파일 이름을 그대로
# 쓴다 (docs/settings.md → settings.md 처럼) — 문서가 늘 때마다 이 스크립트를 고쳐야 하면
# 곧 어긋나기 때문이다.
#
# 사용법
#   ./scripts/publish-wiki.sh                발행한다 (Wiki 저장소를 받아 커밋·푸시)
#   ./scripts/publish-wiki.sh --dry-run      무엇이 어떻게 바뀌어 어디로 가는지만 보여준다
#   ./scripts/publish-wiki.sh --output <경로> 변환 결과만 그 디렉터리에 쓴다 (git 을 건드리지 않는다)
# ---------------------------------------------------------------------------
set -euo pipefail
export LC_ALL=C

REPO_ROOT=$(cd "$(dirname "$0")/.." && pwd)
DOCS_DIR="$REPO_ROOT/docs"

REPO_SLUG="Orchemi/exem-wifi-switcher"
REPO_URL="https://github.com/$REPO_SLUG"
RAW_BASE="https://raw.githubusercontent.com/$REPO_SLUG/main"
WIKI_CLONE_URL="https://github.com/$REPO_SLUG.wiki.git"
WIKI_NEW_PAGE_URL="$REPO_URL/wiki/_new"

DRY_RUN=0
OUTPUT_DIR=""

err() { printf '%s\n' "$*" >&2; }
die() { err ""; err "중단: $*"; exit 1; }
heading() { printf '\n\033[1m%s\033[0m\n' "$*"; }

usage() {
    cat <<'USAGE'
사용법: ./scripts/publish-wiki.sh [옵션]

  --dry-run         무엇이 어떻게 바뀌어 어디로 가는지 보여주고 아무것도 밀지 않는다
  --output <경로>   변환 결과만 그 디렉터리에 쓴다 (테스트가 쓴다. git 을 건드리지 않는다)
  --help            이 도움말
USAGE
}

while [ $# -gt 0 ]; do
    case "$1" in
        --dry-run) DRY_RUN=1; shift ;;
        --output) [ $# -ge 2 ] || die "--output 뒤에 경로가 필요합니다"; OUTPUT_DIR="$2"; shift 2 ;;
        --help|-h) usage; exit 0 ;;
        *) usage >&2; die "알 수 없는 옵션입니다: $1" ;;
    esac
done

[ -d "$DOCS_DIR" ] || die "docs 디렉터리가 없습니다: $DOCS_DIR"

WORK_DIR=""
CLONE_DIR=""
cleanup() {
    [ -n "$WORK_DIR" ] && rm -rf "$WORK_DIR"
    [ -n "$CLONE_DIR" ] && rm -rf "$CLONE_DIR"
    return 0
}
trap cleanup EXIT

# --- 1) 문서 탐색 -------------------------------------------------------------
#
# docs/ 바로 아래의 .md 만 본다 (-maxdepth 1). docs/plan/ 은 내부 설계 문서라 발행하지 않고,
# docs/screenshots/ 는 애초에 .md 가 없다. 목록을 여기 하드코딩하지 않는 이유는 문서가 늘 때마다
# 이 스크립트를 고쳐야 하면 곧 어긋나기 때문이다 — docs/ 를 훑어 있는 대로 발행한다.

heading "1/4  문서 탐색"

SRC_FILES=()
while IFS= read -r f; do
    SRC_FILES+=("$f")
done < <(find "$DOCS_DIR" -maxdepth 1 -type f -name '*.md' | sort)

[ "${#SRC_FILES[@]}" -gt 0 ] || die "발행할 문서를 찾지 못했습니다: $DOCS_DIR/*.md"

BASENAMES=()
SLUGS=()
OUTPUT_NAMES=()
TITLES=()

for f in "${SRC_FILES[@]}"; do
    base=$(basename "$f")
    base="${base%.md}"

    # 페이지 이름 대응은 index → Home 하나만 고정한다. 나머지는 파일 이름을 그대로 쓴다.
    if [ "$base" = "index" ]; then
        slug="Home"
    else
        slug="$base"
    fi

    # 사이드바 항목 이름은 파일명이 아니라 문서의 첫 '# ' 제목에서 가져온다.
    title=$(awk '/^# / { sub(/^# +/, ""); print; exit }' "$f")
    [ -n "$title" ] || title="$base"

    BASENAMES+=("$base")
    SLUGS+=("$slug")
    OUTPUT_NAMES+=("$slug.md")
    TITLES+=("$title")

    printf '    docs/%s.md → %s.md  (%s)\n' "$base" "$slug" "$title"
done

# --- 2) 변환 -----------------------------------------------------------------
#
# 바뀌는 것은 넷이다 — 문서 사이 링크, 저장소 파일 링크, 이미지 경로, 그리고 머리말 한 줄.
# 순서가 중요하다: '../README.md' 를 저장소 절대경로로 바꾸는 규칙이 일반 '../' 규칙보다
# 먼저 와야 한다(README 는 저장소 루트 URL 하나로, 나머지는 blob/main/<경로> 로 간다).

heading "2/4  변환"

# '../README.md' · '../README.md#앵커' → 저장소 루트 URL (+ 앵커).
# GitHub 는 README.md 를 저장소 루트 페이지에 그대로 렌더링하므로 blob URL 이 아니라 루트 URL 이다.
readme_rule() {
    sed -E "s|\]\(\.\./README\.md(#[^)]*)?\)|](${REPO_URL}\1)|g"
}

# 그 밖의 '../<경로>' → 저장소 blob URL. (README.md 는 위에서 이미 처리됐다.)
repo_link_rule() {
    sed -E "s|\]\(\.\./([^)]+)\)|](${REPO_URL}/blob/main/\1)|g"
}

# docs/ 안의 하위 디렉터리를 가리키는 링크(예: './plan/x.md') → docs/ 밑의 저장소 blob URL.
# 발행하는 문서는 전부 docs/ 바로 아래에 있으므로, 슬래시가 있는 상대경로는 발행되지 않는 파일이다.
docs_subpath_rule() {
    sed -E "s|\]\((\./)?([A-Za-z0-9_-]+/[^)]+\.md(#[^)]*)?)\)|](${REPO_URL}/blob/main/docs/\2)|g"
}

# 같은 자리에 있는 다른 발행 문서로 가는 링크 → '.md' 를 벗기고 앞의 './' 도 없앤다.
same_level_doc_rule() {
    sed -E "s|\]\((\./)?([A-Za-z0-9_-]+)\.md(#[^)]*)?\)|](\2\3)|g"
}

# index → Home. 위 규칙이 먼저 './index.md' 를 'index' 로 벗겨 놓으므로 그 뒤에 이름만 바꾼다.
index_to_home_rule() {
    sed -E "s|\]\(index(#[^)]*)?\)|](Home\1)|g"
}

# docs/screenshots/*.png → raw.githubusercontent.com 절대 URL. 마크다운 이미지와 <img> 둘 다.
image_rule() {
    sed -E \
        -e "s|(!\[[^]]*\]\()(\./)?screenshots/|\1${RAW_BASE}/docs/screenshots/|g" \
        -e "s|(<img[^>]*src=\")(\./)?screenshots/|\1${RAW_BASE}/docs/screenshots/|g"
}

render_body() {
    local src="$1"
    readme_rule < "$src" | repo_link_rule | docs_subpath_rule \
        | same_level_doc_rule | index_to_home_rule | image_rule
}

# 발행물임을 밝히는 머리말. 여기서 고치면 다음 발행 때 덮어써진다는 사실과 원본 위치를
# 함께 적는다 — Wiki 를 직접 고친 사람의 글이 조용히 사라지는 것을 막는 유일한 장치다.
page_header() {
    local rel="$1"
    cat <<HEADER
> 이 페이지는 [\`$rel\`]($REPO_URL/blob/main/$rel) 에서 자동 발행됩니다.
> 여기서 고치면 다음 발행 때 덮어써집니다 — 원본을 고쳐 주세요.

HEADER
}

WORK_DIR=$(mktemp -d)

i=0
while [ "$i" -lt "${#SRC_FILES[@]}" ]; do
    src="${SRC_FILES[$i]}"
    base="${BASENAMES[$i]}"
    out="${OUTPUT_NAMES[$i]}"
    rel="docs/$base.md"

    { page_header "$rel"; render_body "$src"; } > "$WORK_DIR/$out"

    i=$((i + 1))
done

# _Sidebar.md — Home 을 맨 위에, 나머지는 docs/index.md 가 늘어놓은 순서대로, 마지막에 저장소 링크.
#
# 순서를 파일 이름에서 뽑지 않는 이유: 알파벳순은 읽는 순서가 아니다. index.md 의 표에는
# 사람이 정한 순서가 이미 들어 있고(설정하기 → 자동 전환 → …), 사이드바와 Home 이 서로 다른
# 순서로 같은 목록을 보여주면 읽는 사람이 둘을 대조하게 된다. 순서의 출처도 하나여야 한다.
# index.md 가 언급하지 않은 문서는 빠뜨리지 않고 뒤에 붙인다.
sidebar_order() {
    local index_file="$DOCS_DIR/index.md"
    [ -f "$index_file" ] || return 0
    sed -nE 's|.*\]\((\./)?([A-Za-z0-9_-]+)\.md(#[^)]*)?\).*|\2|p' "$index_file"
}

emit_sidebar_entry() {
    local want="$1" i=0
    while [ "$i" -lt "${#SLUGS[@]}" ]; do
        if [ "${SLUGS[$i]}" = "$want" ] && [ -z "${EMITTED[$i]}" ]; then
            printf '* [%s](%s)\n' "${TITLES[$i]}" "${SLUGS[$i]}"
            EMITTED[$i]=1
            return 0
        fi
        i=$((i + 1))
    done
    return 0
}

SIDEBAR="$WORK_DIR/_Sidebar.md"
EMITTED=()
i=0
while [ "$i" -lt "${#SLUGS[@]}" ]; do
    EMITTED+=("")
    i=$((i + 1))
done
{
    emit_sidebar_entry "Home"
    while IFS= read -r name; do
        [ -n "$name" ] || continue
        emit_sidebar_entry "$name"
    done < <(sidebar_order)
    # index.md 에 없는 문서도 사이드바에서 빠지지 않게 한다.
    i=0
    while [ "$i" -lt "${#SLUGS[@]}" ]; do
        if [ -z "${EMITTED[$i]}" ]; then
            printf '* [%s](%s)\n' "${TITLES[$i]}" "${SLUGS[$i]}"
            EMITTED[$i]=1
        fi
        i=$((i + 1))
    done
    printf -- '\n---\n[저장소로 돌아가기](%s)\n' "$REPO_URL"
} > "$SIDEBAR"

printf '    _Sidebar.md 생성 (%d 개 항목)\n' "${#SLUGS[@]}"

# --- 3) 유출 점검 -------------------------------------------------------------
#
# RULES.md §3 · scripts/package-release.sh 와 같은 정규식이다 — 새로 짓지 않고 그대로 가져다 쓴다.
# 문서용 예약 대역(192.0.2.x 등)은 애초에 이 대역 패턴(10./192.168./172.16-31.)에 걸리지 않는다.
# 문서용 MAC(00:00:5E:00:53:xx)만 예외로 통과시킨다.

heading "3/4  유출 점검"

MAC_PATTERN='([0-9a-f]{2}:){5}[0-9a-f]{2}'
DOC_MAC_PATTERN='00:00:5e:00:53:[0-9a-f]{2}'
IP_PATTERN='\b10\.[0-9]{1,3}\.|\b192\.168\.[0-9]{1,3}\.|\b172\.(1[6-9]|2[0-9]|3[01])\.[0-9]{1,3}\.'
# 문자 클래스로 적는다 — 이 스크립트 자신이 RULES.md 의 사전 점검 grep 에 걸리지 않도록 한다.
# 정규식으로는 [U] 가 U 와 같으므로 찾는 대상은 그대로다 (scripts/package-release.sh 와 같은 관례).
HOME_PATTERN='/[U]sers/'

leak_found=0

mac_hits=$(grep -rIniE "$MAC_PATTERN" "$WORK_DIR" 2>/dev/null | grep -viE "$DOC_MAC_PATTERN" || true)
if [ -n "$mac_hits" ]; then
    err "  MAC 주소로 보이는 값이 있습니다 (문서용 00:00:5E:00:53:xx 는 통과합니다):"
    printf '%s\n' "$mac_hits" >&2
    leak_found=1
fi

ip_hits=$(grep -rIniE "$IP_PATTERN" "$WORK_DIR" 2>/dev/null || true)
if [ -n "$ip_hits" ]; then
    err "  사내 대역으로 보이는 IP 가 있습니다 (192.0.2.x 등 문서용 예약 대역은 걸리지 않습니다):"
    printf '%s\n' "$ip_hits" >&2
    leak_found=1
fi

home_hits=$(grep -rInE "$HOME_PATTERN" "$WORK_DIR" 2>/dev/null || true)
if [ -n "$home_hits" ]; then
    err "  사용자 홈 절대경로가 있습니다:"
    printf '%s\n' "$home_hits" >&2
    leak_found=1
fi

if [ "$leak_found" -ne 0 ]; then
    die "유출 점검에 걸렸습니다. docs/ 원본을 고친 뒤 다시 시도하세요 (아무것도 밀지 않았습니다)."
fi
printf '    걸린 것 없음\n'

# --- 4) 발행 -----------------------------------------------------------------

heading "4/4  발행"

if [ -n "$OUTPUT_DIR" ]; then
    # --output 은 그 디렉터리의 .md 를 먼저 지운다. 실수로 docs/ 나 저장소 루트를 주면
    # 원본이 발행물로 덮인다 (원본은 링크가 벗겨진 채로 돌아오지 않는다). 그 자리를 막는다.
    mkdir -p "$OUTPUT_DIR"
    resolved_output=$(cd "$OUTPUT_DIR" && pwd)
    case "$resolved_output" in
        "$DOCS_DIR"|"$REPO_ROOT")
            die "--output 으로 원본 자리를 줄 수 없습니다: $resolved_output
     발행물이 docs/ 원본을 덮어씁니다. 다른 디렉터리를 주세요." ;;
    esac
    # 옛 산출물이 섞이지 않도록 먼저 비운다 (테스트가 매번 같은 디렉터리를 재사용할 수 있다).
    find "$OUTPUT_DIR" -maxdepth 1 -type f -name '*.md' -exec rm -f {} +
    cp "$WORK_DIR"/*.md "$OUTPUT_DIR"/
    printf '    변환 결과를 썼습니다: %s (git 은 건드리지 않았습니다)\n' "$OUTPUT_DIR"
    exit 0
fi

if [ "$DRY_RUN" -eq 1 ]; then
    printf '    [dry-run] 아무것도 밀지 않습니다. 실제로 실행하면 다음으로 갑니다:\n'
    printf '      %s\n' "$WIKI_CLONE_URL"
    printf '    바뀔 페이지\n'
    for name in "${OUTPUT_NAMES[@]}"; do
        printf '      %s\n' "$name"
    done
    printf '      _Sidebar.md\n'
    exit 0
fi

command -v git >/dev/null 2>&1 || die "git 을 찾지 못했습니다"

CLONE_DIR=$(mktemp -d)
clone_output=$(git clone --quiet --depth 1 "$WIKI_CLONE_URL" "$CLONE_DIR" 2>&1) || {
    if printf '%s' "$clone_output" | grep -qi 'not found'; then
        err ""
        err "  Wiki 저장소가 아직 없습니다. 첫 페이지가 없으면 git 저장소 자체가 생기지 않습니다."
        err "  아래 주소에서 페이지를 하나 만든 뒤 다시 실행하세요."
        err ""
        err "    $WIKI_NEW_PAGE_URL"
        err ""
        exit 2
    fi
    die "Wiki 저장소를 받지 못했습니다:
$clone_output"
}

# _Sidebar.md 를 포함해 이 스크립트가 만드는 페이지로 전부 덮어쓴다. Wiki 쪽에서 손으로 만든
# 페이지(우리가 모르는 파일)는 건드리지 않는다 — 대응표에 없는 페이지를 지우는 것은 이 스크립트의 일이 아니다.
i=0
while [ "$i" -lt "${#OUTPUT_NAMES[@]}" ]; do
    cp "$WORK_DIR/${OUTPUT_NAMES[$i]}" "$CLONE_DIR/${OUTPUT_NAMES[$i]}"
    i=$((i + 1))
done
cp "$WORK_DIR/_Sidebar.md" "$CLONE_DIR/_Sidebar.md"

(cd "$CLONE_DIR" && git add -A)
if git -C "$CLONE_DIR" diff --cached --quiet; then
    printf '    바뀐 내용이 없습니다. 커밋하지 않았습니다.\n'
    exit 0
fi

git -C "$CLONE_DIR" commit --quiet -m "docs: 문서 발행 ($(date +%Y-%m-%d))"
git -C "$CLONE_DIR" push --quiet origin HEAD
printf '    발행했습니다: %s\n' "$REPO_URL/wiki"
