#!/bin/bash
# ---------------------------------------------------------------------------
# uninstall.sh — install.sh 가 남긴 것을 전부 지운다.
#
# 지우는 대상
#   /etc/sudoers.d/exem-wifi-switcher              sudo 규칙
#   /usr/local/libexec/exem-wifi-switcher/         권한 스크립트 두 개(apply · save-config)와 그 디렉터리
#   /usr/local/etc/exem-wifi-switcher/             설정 (--keep-config 로 남길 수 있음)
#   ~/Library/LaunchAgents/com.horbis.exem-wifi-switcher.agent.plist
#                                                  옛 방식 로그인 항목 (0.1.0 이전 버전에서 켠 경우에만)
#   ~/Library/Preferences/com.horbis.exem-wifi-switcher.plist
#                                                  앱이 남긴 설정값(자동 전환 on/off 등)
#
# 지우지 않는 것 (지울 수 없거나, 사용자 것이라 건드리지 않는다)
#   EXEM Wifi Switcher.app                         사용자가 둔 자리에 그대로 있다. 직접 지운다
#   /usr/local/libexec · /usr/local/etc            이 도구가 만들었더라도 다른 도구가 쓸 수 있어 남긴다
#   지금 방식의 로그인 항목(SMAppService)           파일이 아니라 macOS 가 들고 있는 기록이라
#                                                  셸에서 끌 공개 수단이 없다. 앱의 체크상자로 끄거나
#                                                  앱 번들을 지우면 macOS 가 함께 정리한다
#   위치 권한(TCC) 기록                             SIP 가 보호하는 영역이라 tccutil 로도 번들 하나만
#                                                  지목해 지우는 길이 없다 (2026-07-30 실측 — 사용자
#                                                  권한으로도 root 로도 "Failed to reset Location
#                                                  approval status" 로 똑같이 실패했고 2026-08-03 에
#                                                  다시 확인했다). 위치 권한은 코드 서명에 매이는데,
#                                                  배포본은 Developer ID 로 서명하고 공증해서 신원이
#                                                  고정이다. 그래서 이 기록이 남아 있으면 다시 설치해도
#                                                  macOS 가 그 승인을 그대로 쓴다 (docs/updating.md).
#                                                  지우려면 시스템 설정 > 개인정보 보호 및 보안 >
#                                                  위치 서비스에서 직접 뺀다
#
# 마지막에 위 파일들이 정말 사라졌는지 다시 확인하고, 하나라도 남으면 실패로 끝난다.
# 지우지 않은 것(앱 번들·알림 권한·위치 권한 기록)은 마무리 문구에 그대로 적는다 —
# "전부 지웠다" 로 뭉뚱그리지 않는다.
#
# 미리 보기:  ./scripts/uninstall.sh --dry-run
#
# install.sh 와 같이 두 길로 들어온다 (터미널 / 앱의 [제거] 버튼).
# root 로 들어오면 HOME 이 root 의 것이라 사용자 쪽 흔적을 찾지 못하므로, --user 로 받은
# 계정에서 홈 디렉터리·uid 를 다시 구한다. 그러지 않으면 로그인 항목과 앱 설정값이 남는데도
# "전부 지웠다" 로 끝나 버린다.
# ---------------------------------------------------------------------------
set -euo pipefail

# install.sh 와 같은 이유로 PATH 를 물려받지 않는다 (root 로도 실행된다).
PATH=/usr/sbin:/usr/bin:/sbin:/bin
export PATH

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd -P)
SCRIPT_NAME=$(basename "$0")

LIBEXEC_DIR=/usr/local/libexec/exem-wifi-switcher
CONFIG_DIR=/usr/local/etc/exem-wifi-switcher
SUDOERS_PATH=/etc/sudoers.d/exem-wifi-switcher
BUNDLE_ID=com.horbis.exem-wifi-switcher
AGENT_LABEL="$BUNDLE_ID.agent"
APP_PROCESS_NAME="EXEM Wifi Switcher"

DRY_RUN=0
KEEP_CONFIG=0
ASSUME_YES=0
SKIP_RUNNING_APP=0
USER_OVERRIDE=""

IS_ROOT=0
[ "$(id -u)" -eq 0 ] && IS_ROOT=1

err() { printf '%s\n' "$*" >&2; }
die() { err ""; err "중단: $*"; exit 1; }
heading() { printf '\n\033[1m%s\033[0m\n' "$*"; }

usage() {
    cat <<'USAGE'
사용법: ./scripts/uninstall.sh [--dry-run] [--keep-config] [--yes] [--user <계정>]
                              [--skip-running-app]

  --dry-run           실제로 지우지 않고, 실행할 명령만 보여준다
  --keep-config       /usr/local/etc/exem-wifi-switcher 의 설정을 남긴다
  --yes               확인 입력을 건너뛴다. 부르는 쪽이 같은 내용을 이미 보여주고
                      확인을 받았을 때만 쓴다 (앱의 [제거] 버튼이 이 길로 들어온다)
  --user <계정>       사용자 쪽 흔적을 찾을 계정. root 로 실행할 때는 반드시 지정해야 한다
  --skip-running-app  실행 중인 앱을 종료하지 않는다 (앱이 자기 자신을 부를 때)
  --help              이 도움말
USAGE
}

while [ $# -gt 0 ]; do
    case "$1" in
        --dry-run) DRY_RUN=1; shift ;;
        --keep-config) KEEP_CONFIG=1; shift ;;
        --yes) ASSUME_YES=1; shift ;;
        --skip-running-app) SKIP_RUNNING_APP=1; shift ;;
        --user) [ $# -ge 2 ] || die "--user 뒤에 계정 이름이 필요합니다"; USER_OVERRIDE="$2"; shift 2 ;;
        --help|-h) usage; exit 0 ;;
        *) usage >&2; die "알 수 없는 옵션입니다: $1" ;;
    esac
done

run_privileged() {
    if [ "$DRY_RUN" -eq 1 ]; then
        printf '    [dry-run] sudo %s\n' "$*"
        return 0
    fi
    if [ "$IS_ROOT" -eq 1 ]; then
        "$@"
    else
        sudo "$@"
    fi
}

# --- 이 스크립트가 놓인 자리 --------------------------------------------------

mode_allows_foreign_write() {
    local perms="${1-}"
    if [[ ! "$perms" =~ ^[0-7]{3,5}$ ]]; then
        return 0
    fi
    if [ $(( 8#$perms & 8#0022 )) -ne 0 ]; then
        return 0
    fi
    return 1
}

assert_not_foreign_writable() {
    local path="$1" label="$2" perms
    if [ -L "$path" ]; then
        die "$label 이 심볼릭 링크입니다: $path"
    fi
    if [ ! -e "$path" ]; then
        die "$label 이 없습니다: $path"
    fi
    perms=$(stat -f '%OLp' "$path") || die "$label 의 권한을 읽지 못했습니다: $path"
    if mode_allows_foreign_write "$perms"; then
        die "$label 을 소유자 외의 사용자가 고칠 수 있습니다: $path (권한 $perms)"
    fi
}

# install.sh 와 같은 이유로, root 로 돌 때만 자기 자리를 확인한다.
assert_self_is_safe() {
    assert_not_foreign_writable "$SCRIPT_DIR" "제거 스크립트 디렉터리"
    assert_not_foreign_writable "$SCRIPT_DIR/$SCRIPT_NAME" "제거 스크립트"
}

# --- 사용자 쪽 맥락 ----------------------------------------------------------
#
# 로그인 항목·앱 설정값·위치 권한 기록은 전부 **사용자** 에게 달려 있다.
# root 로 실행되면 HOME 이 /var/root 라 그대로 두면 남의 집을 뒤지게 된다.

if [ "$IS_ROOT" -eq 1 ]; then
    assert_self_is_safe
    if [ -z "$USER_OVERRIDE" ] && [ -z "${SUDO_USER:-}" ]; then
        die "root 로 실행할 때는 --user <계정> 으로 대상을 지정하세요
     (그러지 않으면 로그인 항목과 앱 설정값이 남는데도 다 지웠다고 끝납니다)"
    fi
fi
TARGET_USER="${USER_OVERRIDE:-${SUDO_USER:-$(id -un)}}"
case "$TARGET_USER" in
    ''|*[!a-zA-Z0-9._-]*) die "사용자 이름에 예상 밖의 문자가 있습니다: '$TARGET_USER'" ;;
esac
TARGET_UID=$(id -u "$TARGET_USER" 2>/dev/null) || die "사용자를 확인하지 못했습니다: $TARGET_USER"
case "$TARGET_UID" in
    ''|*[!0-9]*) die "사용자 uid 를 읽지 못했습니다: $TARGET_USER" ;;
esac

# 홈 디렉터리는 디렉터리 서비스에 물어본다 — HOME 은 실행 맥락에 따라 달라진다.
# (dscl 대신 dscacheutil 을 쓰는 이유는 홈 경로를 스크립트에 적지 않아도 되기 때문이다)
# 이름에 공백이 있는 홈도 통째로 받도록 접두어만 떼어 낸다.
read_target_home() {
    local raw line
    raw=$(dscacheutil -q user -a name "$TARGET_USER" 2>/dev/null) || return 1
    while IFS= read -r line; do
        case "$line" in
            "dir: "*) printf '%s' "${line#dir: }"; return 0 ;;
        esac
    done <<< "$raw"
    return 1
}
TARGET_HOME=$(read_target_home) || TARGET_HOME=""
if [ -z "$TARGET_HOME" ] && [ "$IS_ROOT" -eq 0 ]; then
    TARGET_HOME="${HOME:-}"
fi

# 홈을 찾지 못한 환경(자동화·테스트)에서는 사용자 쪽 경로를 아예 만들지 않는다.
# 빈 문자열을 이어붙이면 시스템 경로(/Library/...)를 가리키게 되므로 대상에서 빼는 편이 안전하다.
AGENT_PLIST=""
PREFERENCES_PLIST=""
if [ -n "$TARGET_HOME" ] && [ "$TARGET_HOME" != "/" ]; then
    AGENT_PLIST="$TARGET_HOME/Library/LaunchAgents/$AGENT_LABEL.plist"
    PREFERENCES_PLIST="$TARGET_HOME/Library/Preferences/$BUNDLE_ID.plist"
fi

# 사용자 맥락이 필요한 명령(defaults)은 그 사용자로 실행한다.
# root 로 실행하면 root 의 설정을 건드리게 된다.
run_as_target_user() {
    if [ "$IS_ROOT" -eq 1 ] && [ "$TARGET_USER" != "root" ]; then
        sudo -u "$TARGET_USER" "$@"
    else
        "$@"
    fi
}

# --- 무엇을 지울지 먼저 보여준다 ---------------------------------------------

cat <<PLAN

===========================================================================
 EXEM Wifi Switcher — 제거
===========================================================================

지울 대상 (현재 있는 것만 지웁니다)

PLAN

present_count=0
report_target() {
    local path="$1" note="${2:-}"
    if [ -e "$path" ] || [ -L "$path" ]; then
        printf '  [있음] %s %s\n' "$path" "$note"
        present_count=$(( present_count + 1 ))
    else
        # 없을 때도 무엇을 대상으로 보고 있는지 그대로 적는다 — 목록 자체가 투명성 문서다.
        printf '  [없음] %s %s\n' "$path" "$note"
    fi
}
report_target "$SUDOERS_PATH" "(sudo 규칙)"
report_target "$LIBEXEC_DIR" "(권한 스크립트 apply · save-config)"
if [ "$KEEP_CONFIG" -eq 1 ]; then
    printf '  [유지] %s (--keep-config)\n' "$CONFIG_DIR"
else
    report_target "$CONFIG_DIR" "(설정 — 사용자가 입력한 네트워크 값이 들어 있습니다)"
fi
if [ -n "$AGENT_PLIST" ]; then
    report_target "$AGENT_PLIST" "(옛 방식 로그인 항목 — 0.1.0 이전 버전에서 켠 경우에만 있습니다)"
fi
if [ -n "$PREFERENCES_PLIST" ]; then
    report_target "$PREFERENCES_PLIST" "(앱 설정값 — 자동 전환 on/off 등)"
fi

# 실행 중인 앱은 파일이 아니라 상태다. 남아 있는지 파일처럼 확인할 수 없으므로 매번 다시 본다.
# (위치 권한(TCC) 기록도 파일이 아닌 상태지만, macOS 가 이것을 지우는 명령을 제공하지 않아
# 이 스크립트가 시도할 것 자체가 없다 — 6/6 과 마무리 문구에서 안내만 한다)
if pgrep -x "$APP_PROCESS_NAME" >/dev/null 2>&1; then
    if [ "$SKIP_RUNNING_APP" -eq 1 ]; then
        printf '  [있음] 실행 중인 앱 — 종료하지 않습니다 (--skip-running-app)\n'
    else
        printf '  [있음] 실행 중인 앱 — 종료합니다 (%s)\n' "$APP_PROCESS_NAME"
    fi
    present_count=$(( present_count + 1 ))
else
    printf '  [없음] 실행 중인 앱\n'
fi

printf '\n앱 번들(%s.app)은 사용자가 둔 자리에 있어 이 스크립트가 지우지 않습니다. 직접 지우세요.\n\n' "$APP_PROCESS_NAME"

if [ "$present_count" -eq 0 ]; then
    printf '지울 파일이 없습니다.\n'
    exit 0
fi

if [ "$DRY_RUN" -eq 1 ]; then
    printf '%s\n' "[dry-run] 실제로는 아무것도 지우지 않습니다."
elif [ "$ASSUME_YES" -eq 1 ]; then
    printf '%s\n' "확인을 받았다는 전제로 진행합니다 (--yes)."
else
    if [ ! -t 0 ]; then
        die "확인 입력을 받을 수 없는 환경입니다 (터미널에서 직접 실행하거나 --yes 를 쓰세요)"
    fi
    printf '위 항목을 지우려면 yes 를 입력하세요: '
    read -r reply
    [ "$reply" = "yes" ] || die "사용자가 취소했습니다"
fi

# --- 1) 실행 중인 앱 ---------------------------------------------------------

heading "1/6  실행 중인 앱"
if [ "$SKIP_RUNNING_APP" -eq 1 ]; then
    # 앱이 자기 자신을 제거하는 길이다. 여기서 앱을 죽이면 사용자는 결과를 볼 창을 잃는다.
    printf '    종료하지 않습니다 — 앱에서 제거를 실행했습니다\n'
elif pgrep -x "$APP_PROCESS_NAME" >/dev/null 2>&1; then
    if [ "$DRY_RUN" -eq 1 ]; then
        printf '    [dry-run] pkill -x %s\n' "$APP_PROCESS_NAME"
    else
        # 메뉴바 앱이 계속 돌면 방금 지운 설정을 다시 만들거나, 지웠는데도 아이콘이 남는다.
        pkill -x "$APP_PROCESS_NAME" >/dev/null 2>&1 || true
        sleep 1
        if pgrep -x "$APP_PROCESS_NAME" >/dev/null 2>&1; then
            err "    경고: 앱이 아직 실행 중입니다. 메뉴에서 직접 종료하세요."
        else
            printf '    종료했습니다: %s\n' "$APP_PROCESS_NAME"
        fi
    fi
else
    printf '    실행 중이 아닙니다\n'
fi

# --- 2) 로그인 항목 ---------------------------------------------------------

heading "2/6  로그인 항목"
if [ -n "$AGENT_PLIST" ] && [ -f "$AGENT_PLIST" ]; then
    if [ "$DRY_RUN" -eq 1 ]; then
        printf '    [dry-run] launchctl bootout gui/%s/%s\n' "$TARGET_UID" "$AGENT_LABEL"
        printf '    [dry-run] rm -f %s\n' "$AGENT_PLIST"
    else
        # 대상 계정의 GUI 도메인을 지정한다 — root 로 돌 때 id -u 는 0 이라 남의 도메인을 본다.
        launchctl bootout "gui/$TARGET_UID/$AGENT_LABEL" >/dev/null 2>&1 || true
        rm -f "$AGENT_PLIST"
        printf '    옛 방식 항목을 제거했습니다: %s\n' "$AGENT_PLIST"
    fi
else
    printf '    옛 방식으로 등록된 항목이 없습니다\n'
fi
# 지금 방식(SMAppService)의 로그인 항목은 파일이 아니라 macOS 가 들고 있는 기록이다.
# 셸에서 끄는 공개 수단이 없으므로, 뭉개지 말고 어떻게 끄는지 그대로 적는다.
printf '    지금 방식의 로그인 항목은 macOS 가 들고 있어 이 스크립트가 끄지 못합니다\n'
printf '      · 앱 설정 창의 [로그인 시 자동 실행] 체크상자를 끄거나\n'
printf '      · 앱 번들(%s.app)을 지우면 macOS 가 함께 정리합니다\n' "$APP_PROCESS_NAME"

# --- 3) sudo 규칙 -----------------------------------------------------------

heading "3/6  sudo 규칙"
if [ -e "$SUDOERS_PATH" ]; then
    run_privileged /bin/rm -f "$SUDOERS_PATH"
    if [ "$DRY_RUN" -eq 0 ]; then
        printf '    제거했습니다: %s\n' "$SUDOERS_PATH"
        # 규칙을 뺀 뒤에도 sudoers 전체가 정상인지 확인한다.
        if sudo visudo -c >/dev/null 2>&1; then
            printf '    남은 sudoers 검증 통과\n'
        else
            err "    경고: sudoers 전체 검증에 실패했습니다. sudo visudo -c 로 직접 확인하세요"
        fi
    fi
else
    printf '    없습니다\n'
fi

# --- 4) 권한 스크립트 --------------------------------------------------------

heading "4/6  권한 스크립트"
if [ -e "$LIBEXEC_DIR" ]; then
    # apply 와 save-config 가 이 디렉터리 안에 있다. 디렉터리째 지운다.
    run_privileged /bin/rm -rf "$LIBEXEC_DIR"
    if [ "$DRY_RUN" -eq 0 ]; then
        printf '    제거했습니다: %s (apply · save-config)\n' "$LIBEXEC_DIR"
    fi
else
    printf '    없습니다\n'
fi

# --- 5) 설정 ---------------------------------------------------------------

heading "5/6  설정"
if [ "$KEEP_CONFIG" -eq 1 ]; then
    printf '    남겨둡니다: %s\n' "$CONFIG_DIR"
elif [ -e "$CONFIG_DIR" ]; then
    run_privileged /bin/rm -rf "$CONFIG_DIR"
    if [ "$DRY_RUN" -eq 0 ]; then
        printf '    제거했습니다: %s\n' "$CONFIG_DIR"
    fi
else
    printf '    없습니다\n'
fi

# --- 6) 앱이 남긴 사용자 쪽 흔적 ----------------------------------------------

heading "6/6  앱 설정값과 위치 권한"
if [ -n "$PREFERENCES_PLIST" ] && [ -e "$PREFERENCES_PLIST" ]; then
    if [ "$DRY_RUN" -eq 1 ]; then
        printf '    [dry-run] defaults delete %s\n' "$BUNDLE_ID"
        printf '    [dry-run] rm -f %s\n' "$PREFERENCES_PLIST"
    else
        # defaults 를 먼저 지운다. cfprefsd 가 값을 캐시하고 있어, 파일만 지우면 되살아난다.
        run_as_target_user defaults delete "$BUNDLE_ID" >/dev/null 2>&1 || true
        rm -f "$PREFERENCES_PLIST"
        printf '    제거했습니다: %s\n' "$PREFERENCES_PLIST"
    fi
else
    printf '    앱 설정값이 없습니다\n'
fi

# 위치 권한(TCC)은 SIP 가 보호하는 영역이라 tccutil 로 번들 하나만 지목해 지우는 길이 없다.
# 2026-07-30 에 오너 기계에서 실제로 tccutil reset Location <번들 ID> 를 시도해 확인했다 —
# 사용자 권한으로도 root 로도 "Failed to reset Location approval status" 로 똑같이 실패했다.
# 그래서 이 스크립트는 그 명령을 부르지 않는다: 실패가 정해진 명령을 매번 실행하면서
# "직접 실행하세요" 로 똑같이 실행할 수 없는 대안을 주는 것은 안내가 아니라 오해다.
#
# 위치 권한은 번들 식별자가 아니라 **코드 서명**에 매인다 (docs/updating.md).
# 배포본은 Developer ID 로 서명하고 공증하므로 신원이 고정이다. 그래서 이 기록이 남아 있으면
# 앱을 지웠다가 새 판을 깔아도 macOS 가 다시 묻지 않고 남은 승인을 그대로 쓴다
# (2026-08-03 실측: 지우고 새 판을 내려받아 설치했더니 권한 창 없이 '허용됨' 으로 시작했다).
# SIGN_IDENTITY 없이 직접 빌드한 앱은 반대다. ad-hoc 서명이라 빌드마다 서명이 달라져
# 위치 권한이 매번 풀리고, 이 기록이 남아 있어도 macOS 가 다시 묻는다.
printf '    위치 권한(TCC) 기록은 macOS 가 들고 있어 이 스크립트가 지우지 못합니다\n'
printf '      · macOS 는 tccutil 로 앱 하나만 지목해 이 기록을 지우는 길을 제공하지 않습니다\n'
printf '      · 지우려면 시스템 설정 > 개인정보 보호 및 보안 > 위치 서비스에서 직접 빼세요\n'
printf '      · 남아 있어도 다음 설치를 막지 않습니다. 내려받은 앱은 서명 신원이 고정이라,\n'
printf '        기록을 두면 다시 설치해도 macOS 가 위치 권한을 다시 묻지 않습니다\n'
printf '      · 직접 빌드하신 앱이라면 빌드마다 서명이 달라져 그때마다 다시 묻습니다\n'

# --- 잔여물 확인 ------------------------------------------------------------

heading "잔여물 확인"
if [ "$DRY_RUN" -eq 1 ]; then
    printf '  [dry-run] 아무것도 지우지 않았으므로 확인을 건너뜁니다.\n'
    exit 0
fi

leftovers=0
check_gone() {
    local path="$1"
    if [ -e "$path" ] || [ -L "$path" ]; then
        printf '  남아 있음: %s\n' "$path"
        leftovers=$(( leftovers + 1 ))
    else
        printf '  없음: %s\n' "$path"
    fi
}
check_gone "$SUDOERS_PATH"
check_gone "$LIBEXEC_DIR"
if [ -n "$AGENT_PLIST" ]; then
    check_gone "$AGENT_PLIST"
fi
if [ -n "$PREFERENCES_PLIST" ]; then
    if [ "$SKIP_RUNNING_APP" -eq 1 ] && [ -e "$PREFERENCES_PLIST" ]; then
        # 앱이 아직 돌고 있으면 cfprefsd 가 설정값 파일을 다시 만들 수 있다.
        # 실패로 세지 않되 뭉개지도 않는다 — 무엇을 더 하면 되는지 그대로 적는다.
        printf '  남아 있음: %s\n' "$PREFERENCES_PLIST"
        printf '    앱이 실행 중이라 다시 만들어진 것으로 보입니다. 앱을 종료한 뒤 다시 실행하면 지워집니다\n'
    else
        check_gone "$PREFERENCES_PLIST"
    fi
fi
if [ "$KEEP_CONFIG" -eq 0 ]; then
    check_gone "$CONFIG_DIR"
fi

if [ "$leftovers" -ne 0 ]; then
    die "$leftovers 개 항목이 남아 있습니다. 위 경로를 직접 확인하세요."
fi

# 전부 지웠다고 뭉뚱그리지 않는다.
# 이 스크립트가 지운 것과 지우지 않은 것을 갈라서 적어야 사실이 된다.
printf '\n이 스크립트가 설치했던 항목은 전부 지웠습니다.\n'
if [ "$KEEP_CONFIG" -eq 1 ]; then
    printf '설정은 요청대로 남겨두었습니다: %s\n' "$CONFIG_DIR"
fi
printf '\n아직 남아 있는 것 (직접 정리하세요)\n'
printf '  - 앱 번들: %s.app — 둔 자리에서 직접 지우세요\n' "$APP_PROCESS_NAME"
printf '  - 로그인 항목: 앱 설정 창에서 끄거나, 앱 번들을 지우면 함께 사라집니다\n'
printf '  - 알림 권한: 시스템 설정 > 알림 에서 %s 항목을 지우세요\n' "$APP_PROCESS_NAME"
printf '    (macOS 는 알림 설정을 명령으로 지울 방법을 제공하지 않습니다)\n'
printf '  - 위치 권한 기록: 시스템 설정 > 개인정보 보호 및 보안 > 위치 서비스 에서 %s 항목을 지우세요\n' "$APP_PROCESS_NAME"
printf '    (macOS 는 이 기록을 명령으로 지울 방법을 제공하지 않습니다. 남아 있어도 다음 설치는 막지 않습니다)\n'
