#!/bin/bash
# ---------------------------------------------------------------------------
# scripts/uninstall.sh 의 **--dry-run 이 사실만 말하는지** 검증.
#
# --dry-run 은 "무엇을 지울지 먼저 보기" 위한 길이다(README '제거'). 그런데
# sudo 규칙 · 권한 스크립트 · 설정 세 단계는 `run_privileged` 로 실제 삭제를 건너뛰면서도
# 그 뒤에서 "제거했습니다" 를 조건 없이 찍고 있었다 — dry-run 인데 이미 지운 것처럼 말한 것이다.
# 이 스크립트는 sudoers 와 네트워크 설정을 건드리므로 그 오해의 값이 크다.
#
# 시스템을 건드리지 않는다 — 실제 시스템 경로(/etc/sudoers.d/... 등) 대신 스크래치 디렉터리를
# 가리키도록 경로 세 줄만 바꿔치기한 **사본**을 만들어 그 사본에만 --dry-run 을 돌린다.
# sudo 는 부르지 않는다(부르지 않아도 사본 경로가 "있는 것"으로 보이면 버그가 그대로 드러난다).
#
# `swift test` 가 이 파일을 실행하므로 별도로 부를 일은 없지만 단독 실행도 된다:
#
#     ./Tests/shell/uninstall-dry-run.sh
# ---------------------------------------------------------------------------

REPO_ROOT=$(cd "$(dirname "$0")/../.." && pwd)
UNINSTALL="$REPO_ROOT/scripts/uninstall.sh"

pass_count=0
fail_count=0

t_pass() { pass_count=$(( pass_count + 1 )); }
t_fail() {
    fail_count=$(( fail_count + 1 ))
    printf '  실패: %s\n' "$*" >&2
}
t_section() { printf '\n▸ %s\n' "$*"; }

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

# --- 사본 준비 -----------------------------------------------------------------
#
# uninstall.sh 는 대상 경로를 상수로 박아 둔다(단일 출처를 지키려는 설계라 인자로 받지 않는다).
# 실제 시스템 경로가 "있는 것"이어야 3/6·4/6·5/6 의 삭제 분기를 실제로 타므로,
# 그 세 상수 줄만 스크래치 경로로 바꿔치기한 사본을 만든다. 로직은 원본 그대로다.

SCRATCH=$(mktemp -d)
trap 'rm -rf "$SCRATCH"' EXIT

FIXTURE="$SCRATCH/uninstall.sh"
sed \
    -e "s#^LIBEXEC_DIR=.*#LIBEXEC_DIR=$SCRATCH/target/libexec#" \
    -e "s#^CONFIG_DIR=.*#CONFIG_DIR=$SCRATCH/target/etc#" \
    -e "s#^SUDOERS_PATH=.*#SUDOERS_PATH=$SCRATCH/target/sudoers-rule#" \
    "$UNINSTALL" > "$FIXTURE"
chmod +x "$FIXTURE"

# 바꿔치기가 실제로 세 줄 다 먹혔는지 먼저 확인한다 — 그러지 않으면 아래 검사가
# "지울 것이 없어서" 조용히 통과하는 거짓 안전판이 된다.
t_section "사본에서 대상 경로 세 줄이 스크래치로 바뀌었다"
for var in LIBEXEC_DIR CONFIG_DIR SUDOERS_PATH; do
    if grep -q "^$var=$SCRATCH/" "$FIXTURE"; then
        t_pass
    else
        t_fail "$var 이 스크래치 경로로 바뀌지 않았습니다 (uninstall.sh 의 상수 선언 형태가 바뀌었을 수 있습니다)"
    fi
done

mkdir -p "$SCRATCH/target/libexec" "$SCRATCH/target/etc"
touch "$SCRATCH/target/sudoers-rule"

# --- dry-run 은 과거형으로 말하지 않는다 ---------------------------------------

t_section "지울 대상이 있어도 dry-run 은 이미 지운 것처럼 말하지 않는다"
t_silent_about "제거했습니다" "dry-run 출력에 과거형 완료 표현이 있다" -- \
    bash "$FIXTURE" --dry-run --yes --skip-running-app

t_says "3/6" "3/6 단계가 출력된다" -- bash "$FIXTURE" --dry-run --yes --skip-running-app
t_says "4/6" "4/6 단계가 출력된다" -- bash "$FIXTURE" --dry-run --yes --skip-running-app
t_says "5/6" "5/6 단계가 출력된다" -- bash "$FIXTURE" --dry-run --yes --skip-running-app
t_says "[dry-run] sudo /bin/rm -f $SCRATCH/target/sudoers-rule" \
    "sudo 규칙 단계가 dry-run 명령을 보여준다" -- bash "$FIXTURE" --dry-run --yes --skip-running-app
t_says "[dry-run] sudo /bin/rm -rf $SCRATCH/target/libexec" \
    "권한 스크립트 단계가 dry-run 명령을 보여준다" -- bash "$FIXTURE" --dry-run --yes --skip-running-app
t_says "[dry-run] sudo /bin/rm -rf $SCRATCH/target/etc" \
    "설정 단계가 dry-run 명령을 보여준다" -- bash "$FIXTURE" --dry-run --yes --skip-running-app

# --- dry-run 은 실제로 아무것도 지우지 않는다 -----------------------------------
#
# 위에서 이미 여러 번 --dry-run 을 돌렸다. 그 뒤에도 사본 대상이 그대로 있어야 한다.

t_section "dry-run 은 실제로 아무것도 지우지 않는다"
if [ -e "$SCRATCH/target/sudoers-rule" ]; then t_pass; else
    t_fail "sudoers 규칙 사본이 dry-run 인데도 사라졌습니다"
fi
if [ -d "$SCRATCH/target/libexec" ]; then t_pass; else
    t_fail "권한 스크립트 디렉터리 사본이 dry-run 인데도 사라졌습니다"
fi
if [ -d "$SCRATCH/target/etc" ]; then t_pass; else
    t_fail "설정 디렉터리 사본이 dry-run 인데도 사라졌습니다"
fi

# --- 종료코드 --------------------------------------------------------------

t_section "dry-run 은 성공으로 끝난다"
bash "$FIXTURE" --dry-run --yes --skip-running-app >/dev/null 2>&1
status=$?
if [ "$status" = "0" ]; then t_pass; else t_fail "dry-run 종료코드 $status (기대 0)"; fi

# --- 결과 -------------------------------------------------------------------

printf '\n---------------------------------------------\n'
printf '통과 %d개, 실패 %d개\n' "$pass_count" "$fail_count"
if [ "$fail_count" -ne 0 ]; then
    exit 1
fi
exit 0
