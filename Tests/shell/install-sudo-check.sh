#!/bin/bash
# ---------------------------------------------------------------------------
# scripts/install.sh 의 **설치 후 자체 점검이 사실을 말하는지** 검증.
#
# 그 점검은 두 가지를 알린다 — apply 는 암호 없이 실행되어야 **맞고**,
# save-config 는 암호 없이 실행되면 **틀렸다**(설정 파일을 root 소유로 잠근 의미가 사라진다).
#
# 예전에는 둘 다 `sudo -n -l <경로>` 로 물었다. 그 물음은 두 가지를 답하지 못한다.
#   1. **root 로 실행하면 자기 자신에게 묻는 꼴이 된다.** root 는 무엇이든 되므로 답은 늘 "된다".
#      앱의 [설치] 버튼이 바로 그 길이라, 앱으로 설치한 사람 전원이
#      "save-config 가 암호 없이 실행됩니다" 라는 틀린 보안 경고를 봤다 (2026-08-03 실기계).
#   2. **-l 은 '실행할 수 있는가' 까지만 답한다.** 관리자 계정은 %admin ALL=(ALL) ALL 로
#      무엇이든 실행할 수 있어서, 사용자로 실행해도 save-config 가 '열려 있는' 것으로 보인다.
#      무암호인지는 -ll(긴 형식)이 찍는 `Options: !authenticate` 로만 갈린다.
#
# 시스템을 건드리지 않는다 — sudoers 도 sudo 도 실제로 부르지 않는다.
# install.sh 의 판정 구간만 표식 사이에서 떼어다 **가짜 sudo** 와 함께 돌린다.
# 가짜 sudo 가 돌려주는 글은 이 기계의 sudo 1.9.17 이 실제로 찍은 형식 그대로다.
#
# `swift test` 가 이 파일을 실행하므로 별도로 부를 일은 없지만 단독 실행도 된다:
#
#     ./Tests/shell/install-sudo-check.sh
# ---------------------------------------------------------------------------

REPO_ROOT=$(cd "$(dirname "$0")/../.." && pwd)
INSTALL="$REPO_ROOT/scripts/install.sh"

pass_count=0
fail_count=0

t_pass() { pass_count=$(( pass_count + 1 )); }
t_fail() {
    fail_count=$(( fail_count + 1 ))
    printf '  실패: %s\n' "$*" >&2
}
t_section() { printf '\n▸ %s\n' "$*"; }

# t_says <찾을 문구> <설명> <글>
t_says() {
    case "$3" in
        *"$1"*) t_pass ;;
        *) t_fail "$2 — '$1' 이 없습니다
$3" ;;
    esac
}

# t_silent_about <없어야 할 문구> <설명> <글>
t_silent_about() {
    case "$3" in
        *"$1"*) t_fail "$2 — '$1' 이 있습니다
$3" ;;
        *) t_pass ;;
    esac
}

SCRATCH=$(mktemp -d)
trap 'rm -rf "$SCRATCH"' EXIT

# --- 판정 구간을 install.sh 에서 그대로 떼어낸다 --------------------------------
#
# 사본을 만들어 고치지 않는다. **install.sh 에 적힌 그 글자**를 돌려야 이 검증이 의미가 있다.

REGION="$SCRATCH/region.sh"
awk '/^# >>> sudo-rule-check$/{f=1;next} /^# <<< sudo-rule-check$/{f=0} f' "$INSTALL" > "$REGION"

t_section "판정 구간을 install.sh 에서 떼어낼 수 있다"
if [ -s "$REGION" ]; then t_pass; else
    t_fail "install.sh 에 '# >>> sudo-rule-check' ~ '# <<< sudo-rule-check' 표식이 없습니다
     (표식이 사라지면 이 검증은 아무것도 재지 않는 채 조용히 통과한다)"
    printf '\n---------------------------------------------\n'
    printf '통과 %d개, 실패 %d개\n' "$pass_count" "$fail_count"
    exit 1
fi
for symbol in sudo_privilege_entry sudo_password_state report_sudo_rule_state; do
    if grep -q "^$symbol()" "$REGION"; then t_pass; else
        t_fail "떼어낸 구간에 $symbol 이 없습니다"
    fi
done

t_section "install.sh 본문이 그 판정을 실제로 부른다"
# 구간만 멀쩡하고 본문이 부르지 않으면 시스템에서는 아무것도 달라지지 않는다.
if grep -q '^    report_sudo_rule_state$' "$INSTALL"; then t_pass; else
    t_fail "install.sh 의 설치 결과 단계가 report_sudo_rule_state 를 부르지 않습니다"
fi

t_section "거짓말하던 옛 물음이 남아 있지 않다"
# `sudo -n -l <경로>` 는 '암호 없이 되는가' 가 아니라 '실행할 수 있는가' 에 답한다.
for pattern in 'sudo -n -l ' 'sudo -n -l -U'; do
    if grep -q -- "$pattern" "$INSTALL"; then
        t_fail "install.sh 에 '$pattern' 이 남아 있습니다 (무암호 여부를 답하지 못하는 물음입니다)"
    else
        t_pass
    fi
done

# --- 가짜 sudo -------------------------------------------------------------------
#
# 아무것도 실행하지 않는다. 물어본 명령에 따라 미리 적어 둔 대답만 돌려주고, 받은 인자를 적어 둔다.
# 대답 세 가지:  nopasswd(무암호로 열려 있다) · password(암호를 묻는다) · denied(규칙에 안 걸린다)

FAKEBIN="$SCRATCH/bin"
mkdir -p "$FAKEBIN"
cat > "$FAKEBIN/sudo" <<'FAKE_SUDO'
#!/bin/bash
# 테스트용 가짜 sudo. 실제 sudo 를 부르지 않는다.
printf '%s\n' "$*" >> "${FAKE_SUDO_LOG:-/dev/null}"

command_path=""
for argument in "$@"; do
    case "$argument" in
        /*) command_path="$argument" ;;
    esac
done

# 명령 없이 물으면 '목록 조회가 되는가' 를 묻는 것이다.
if [ -z "$command_path" ]; then
    exit "${FAKE_SUDO_LIST:-0}"
fi

case "${command_path##*/}" in
    apply) answer="${FAKE_ANSWER_APPLY:-denied}" ;;
    save-config) answer="${FAKE_ANSWER_SAVE_CONFIG:-denied}" ;;
    *) answer=denied ;;
esac

# 아래 두 글은 macOS 의 sudo 1.9.17 이 실제로 찍은 형식이다 (2026-08-03 실측).
# 무암호 규칙에만 `Options: !authenticate` 가 붙는다.
case "$answer" in
    nopasswd)
        printf 'Sudoers entry: /private/etc/sudoers.d/exem-wifi-switcher\n'
        printf '    RunAsUsers: root\n'
        printf '    Options: !authenticate\n'
        printf '    Commands:\n'
        printf '\t%s\n' "$command_path"
        printf '    Matched: %s\n' "$command_path"
        ;;
    password)
        # 관리자 계정이 %admin ALL=(ALL) ALL 로 걸리는 자리. 실행은 되지만 암호를 묻는다.
        printf 'Sudoers entry: /private/etc/sudoers\n'
        printf '    RunAsUsers: ALL\n'
        printf '    Commands:\n'
        printf '\tALL\n'
        printf '    Matched: %s\n' "$command_path"
        ;;
    *)
        exit 1
        ;;
esac
exit 0
FAKE_SUDO
chmod +x "$FAKEBIN/sudo"

LOG="$SCRATCH/sudo-calls.log"

# report <IS_ROOT> <apply 대답> <save-config 대답> [목록 조회 종료코드]
report() {
    : > "$LOG"
    (
        set -euo pipefail
        PATH="$FAKEBIN:$PATH"
        export PATH
        IS_ROOT="$1"
        # 실제 계정 이름을 쓰지 않는다 — 이 글은 실패하면 그대로 출력된다.
        TARGET_USER=test-target
        APPLY_PATH=/usr/local/libexec/exem-wifi-switcher/apply
        SAVE_CONFIG_PATH=/usr/local/libexec/exem-wifi-switcher/save-config
        SUDOERS_PATH=/etc/sudoers.d/exem-wifi-switcher
        export FAKE_ANSWER_APPLY="$2"
        export FAKE_ANSWER_SAVE_CONFIG="$3"
        export FAKE_SUDO_LIST="${4:-0}"
        export FAKE_SUDO_LOG="$LOG"
        # shellcheck disable=SC1090
        . "$REGION"
        report_sudo_rule_state
    ) 2>&1
}

# --- root 실행 (앱의 [설치] 버튼) ------------------------------------------------

t_section "root 실행에서 save-config 를 두고 없는 경고를 하지 않는다"
# 실기계의 정상 상태다 — apply 는 무암호 규칙으로 열려 있고, save-config 는 관리자 계정이
# 암호를 넣어야 실행된다. 여기서 경고가 나오면 그것이 지금 고치는 오탐이다.
out=$(report 1 nopasswd password)
t_silent_about "경고: save-config" "root 실행에서 틀린 보안 경고가 나온다" "$out"
t_says "save-config — 암호 없이 실행되지 않습니다" "의도된 상태를 말하지 않는다" "$out"
t_says "apply — 확인됨" "root 실행에서 apply 무암호 규칙을 확인하지 못한다" "$out"

t_section "root 실행에서 대상 계정을 지목해 묻는다"
# root 자신에게 물으면 대답은 언제나 '된다' 이고, 그것은 대상 계정에 대해 아무 말도 하지 않는다.
t_says "-U test-target" "root 실행인데 대상 계정을 지목하지 않는다" "$(cat "$LOG")"

t_section "sudo 를 조회로만 쓴다 (아무 명령도 실행하지 않는다)"
# 상태를 보려고 권한 동작을 실제로 돌리면 설치 점검이 시스템을 바꾸게 된다.
while IFS= read -r line; do
    [ -n "$line" ] || continue
    case "$line" in
        *" -ll"*) t_pass ;;
        *) t_fail "조회(-ll)가 아닌 sudo 호출이 있습니다: $line" ;;
    esac
done < "$LOG"

t_section "root 실행에서도 save-config 가 정말 열려 있으면 경고한다"
# 오탐만 없애고 탐지력을 죽이면 고친 것이 아니다.
out=$(report 1 nopasswd nopasswd)
t_says "경고: save-config" "무암호로 열린 save-config 를 지나친다" "$out"
t_says "설정 파일을 root 소유로 잠근 의미가 없습니다" "왜 위험한지 말하지 않는다" "$out"
t_says "/etc/sudoers.d/exem-wifi-switcher" "어디를 봐야 하는지 말하지 않는다" "$out"

t_section "root 실행에서 apply 무암호 규칙이 없으면 확인됐다고 하지 않는다"
# 이쪽도 root 로 물으면 언제나 '된다' 가 나오던 자리다. 없는 것을 확인됐다고 적으면
# 전환할 때마다 암호를 묻는 기계를 정상이라고 보내게 된다.
out=$(report 1 password password)
t_silent_about "apply — 확인됨" "무암호 규칙이 없는데 확인됐다고 적는다" "$out"
t_says "새 터미널에서 확인" "직접 확인할 방법을 주지 않는다" "$out"

# --- 터미널 실행 (일반 사용자) ---------------------------------------------------

t_section "사용자 실행에서는 자기 규칙을 그대로 묻는다"
out=$(report 0 nopasswd password)
t_says "apply — 확인됨" "사용자 실행에서 apply 무암호 규칙을 확인하지 못한다" "$out"
t_says "save-config — 암호 없이 실행되지 않습니다" "의도된 상태를 말하지 않는다" "$out"
t_silent_about "경고: save-config" "사용자 실행에서 틀린 보안 경고가 나온다" "$out"
t_silent_about "-U " "사용자 실행인데 남의 계정을 지목해 묻는다" "$(cat "$LOG")"

t_section "관리자라서 실행은 되는 상태를 무암호로 착각하지 않는다"
# %admin ALL=(ALL) ALL 로 걸리면 sudo -l 은 '실행할 수 있다' 고 답한다.
# 그것을 무암호로 읽는 것이 이 오탐의 뿌리였다.
out=$(report 0 password password)
t_silent_about "경고: save-config" "실행 가능한 것을 무암호로 읽는다" "$out"
t_silent_about "apply — 확인됨" "실행 가능한 것을 무암호로 읽는다" "$out"

# --- 확인할 수 없는 자리 ---------------------------------------------------------

t_section "확인하지 못했으면 확인한 척하지 않는다"
# 규칙 조회 자체가 막히는 설정이 있다. 그때 '암호 없이 실행되지 않습니다' 라고 단정하면
# 확인하지 않은 것을 확인한 것처럼 말하는 것이다. 틀린 단정보다 모른다는 말이 낫다.
out=$(report 1 denied denied 1)
t_says "apply — 이 자리에서는 확인하지 못했습니다" "확인 못 한 것을 그대로 말하지 않는다" "$out"
t_says "save-config — 이 자리에서는 확인하지 못했습니다" "확인 못 한 것을 그대로 말하지 않는다" "$out"
t_silent_about "save-config — 암호 없이 실행되지 않습니다" "확인하지 않은 것을 단정한다" "$out"
t_silent_about "경고: save-config" "확인하지 않은 것을 경고로 단정한다" "$out"

t_section "규칙에 걸리지 않는 것과 확인할 수 없는 것을 가른다"
# 조회는 되는데 그 명령이 규칙에 없는 상태. save-config 는 이것이 정상이다.
out=$(report 1 denied denied 0)
t_says "save-config — 암호 없이 실행되지 않습니다" "규칙에 없는 것을 모른다고 말한다" "$out"
t_silent_about "apply — 확인됨" "규칙에 없는 apply 를 확인됐다고 적는다" "$out"

# --- 결과 -------------------------------------------------------------------

printf '\n---------------------------------------------\n'
printf '통과 %d개, 실패 %d개\n' "$pass_count" "$fail_count"
if [ "$fail_count" -ne 0 ]; then
    exit 1
fi
exit 0
