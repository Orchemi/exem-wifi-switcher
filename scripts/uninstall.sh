#!/bin/bash
# ---------------------------------------------------------------------------
# uninstall.sh — install.sh 가 남긴 것을 전부 지운다.
#
# 지우는 대상
#   /etc/sudoers.d/exem-wifi-switcher              sudo 규칙
#   /usr/local/libexec/exem-wifi-switcher/         권한 스크립트 두 개(apply · save-config)와 그 디렉터리
#   /usr/local/etc/exem-wifi-switcher/             설정 (--keep-config 로 남길 수 있음)
#   ~/Library/LaunchAgents/com.horbis.exem-wifi-switcher.agent.plist
#                                                  로그인 항목 (있을 때만)
#   ~/Library/Preferences/com.horbis.exem-wifi-switcher.plist
#                                                  앱이 남긴 설정값(자동 전환 on/off 등)
#   위치 권한(TCC) 기록                             tccutil reset Location <번들 ID>
#
# 지우지 않는 것 (지울 수 없거나, 사용자 것이라 건드리지 않는다)
#   EXEM Wifi Switcher.app                         사용자가 둔 자리에 그대로 있다. 직접 지운다
#   /usr/local/libexec · /usr/local/etc            이 도구가 만들었더라도 다른 도구가 쓸 수 있어 남긴다
#
# 마지막에 위 파일들이 정말 사라졌는지 다시 확인하고, 하나라도 남으면 실패로 끝난다.
# 지우지 않은 것(앱 번들·알림 권한)은 마무리 문구에 그대로 적는다 — "전부 지웠다" 로 뭉뚱그리지 않는다.
#
# 미리 보기:  ./scripts/uninstall.sh --dry-run
# ---------------------------------------------------------------------------
set -euo pipefail

LIBEXEC_DIR=/usr/local/libexec/exem-wifi-switcher
CONFIG_DIR=/usr/local/etc/exem-wifi-switcher
SUDOERS_PATH=/etc/sudoers.d/exem-wifi-switcher
BUNDLE_ID=com.horbis.exem-wifi-switcher
AGENT_LABEL="$BUNDLE_ID.agent"
APP_PROCESS_NAME="EXEM Wifi Switcher"
# HOME 이 없는 환경(자동화·테스트)에서는 로그인 항목 경로를 만들지 않는다.
# 빈 문자열을 이어붙이면 사용자 파일이 아니라 시스템 경로(/Library/...)를 가리키게 되므로
# 아예 대상에서 제외하는 편이 안전하다.
AGENT_PLIST=""
PREFERENCES_PLIST=""
if [ -n "${HOME:-}" ]; then
    AGENT_PLIST="$HOME/Library/LaunchAgents/$AGENT_LABEL.plist"
    PREFERENCES_PLIST="$HOME/Library/Preferences/$BUNDLE_ID.plist"
fi

DRY_RUN=0
KEEP_CONFIG=0

err() { printf '%s\n' "$*" >&2; }
die() { err ""; err "중단: $*"; exit 1; }
heading() { printf '\n\033[1m%s\033[0m\n' "$*"; }

usage() {
    cat <<'USAGE'
사용법: ./scripts/uninstall.sh [--dry-run] [--keep-config]

  --dry-run       실제로 지우지 않고, 실행할 명령만 보여준다
  --keep-config   /usr/local/etc/exem-wifi-switcher 의 설정을 남긴다
  --help          이 도움말
USAGE
}

while [ $# -gt 0 ]; do
    case "$1" in
        --dry-run) DRY_RUN=1; shift ;;
        --keep-config) KEEP_CONFIG=1; shift ;;
        --help|-h) usage; exit 0 ;;
        *) usage >&2; die "알 수 없는 옵션입니다: $1" ;;
    esac
done

run_privileged() {
    if [ "$DRY_RUN" -eq 1 ]; then
        printf '    [dry-run] sudo %s\n' "$*"
        return 0
    fi
    sudo "$@"
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
    report_target "$AGENT_PLIST" "(로그인 항목)"
fi
if [ -n "$PREFERENCES_PLIST" ]; then
    report_target "$PREFERENCES_PLIST" "(앱 설정값 — 자동 전환 on/off 등)"
fi

# 아래 둘은 파일이 아니라 상태다. 남아 있는지 파일처럼 확인할 수 없으므로 항상 시도한다.
printf '  [시도] 위치 권한(TCC) 기록 초기화 — tccutil reset Location %s\n' "$BUNDLE_ID"
if pgrep -x "$APP_PROCESS_NAME" >/dev/null 2>&1; then
    printf '  [있음] 실행 중인 앱 — 종료합니다 (%s)\n' "$APP_PROCESS_NAME"
    present_count=$(( present_count + 1 ))
else
    printf '  [없음] 실행 중인 앱\n'
fi

printf '\n앱 번들(%s.app)은 사용자가 둔 자리에 있어 이 스크립트가 지우지 않습니다. 직접 지우세요.\n\n' "$APP_PROCESS_NAME"

if [ "$present_count" -eq 0 ]; then
    printf '지울 파일이 없습니다. 위치 권한 기록만 정리하고 끝냅니다.\n'
    if [ "$DRY_RUN" -eq 0 ]; then
        tccutil reset Location "$BUNDLE_ID" >/dev/null 2>&1 || true
    fi
    exit 0
fi

if [ "$DRY_RUN" -eq 1 ]; then
    printf '%s\n' "[dry-run] 실제로는 아무것도 지우지 않습니다."
else
    if [ ! -t 0 ]; then
        die "확인 입력을 받을 수 없는 환경입니다 (터미널에서 직접 실행하세요)"
    fi
    printf '위 항목을 지우려면 yes 를 입력하세요: '
    read -r reply
    [ "$reply" = "yes" ] || die "사용자가 취소했습니다"
fi

# --- 1) 실행 중인 앱 ---------------------------------------------------------

heading "1/6  실행 중인 앱"
if pgrep -x "$APP_PROCESS_NAME" >/dev/null 2>&1; then
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
        printf '    [dry-run] launchctl bootout gui/%s/%s\n' "$(id -u)" "$AGENT_LABEL"
        printf '    [dry-run] rm -f %s\n' "$AGENT_PLIST"
    else
        launchctl bootout "gui/$(id -u)/$AGENT_LABEL" >/dev/null 2>&1 || true
        rm -f "$AGENT_PLIST"
        printf '    제거했습니다: %s\n' "$AGENT_PLIST"
    fi
else
    printf '    등록된 항목이 없습니다\n'
fi

# --- 3) sudo 규칙 -----------------------------------------------------------

heading "3/6  sudo 규칙"
if [ -e "$SUDOERS_PATH" ]; then
    run_privileged /bin/rm -f "$SUDOERS_PATH"
    printf '    제거했습니다: %s\n' "$SUDOERS_PATH"
    # 규칙을 뺀 뒤에도 sudoers 전체가 정상인지 확인한다.
    if [ "$DRY_RUN" -eq 0 ]; then
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
    printf '    제거했습니다: %s (apply · save-config)\n' "$LIBEXEC_DIR"
else
    printf '    없습니다\n'
fi

# --- 5) 설정 ---------------------------------------------------------------

heading "5/6  설정"
if [ "$KEEP_CONFIG" -eq 1 ]; then
    printf '    남겨둡니다: %s\n' "$CONFIG_DIR"
elif [ -e "$CONFIG_DIR" ]; then
    run_privileged /bin/rm -rf "$CONFIG_DIR"
    printf '    제거했습니다: %s\n' "$CONFIG_DIR"
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
        defaults delete "$BUNDLE_ID" >/dev/null 2>&1 || true
        rm -f "$PREFERENCES_PLIST"
        printf '    제거했습니다: %s\n' "$PREFERENCES_PLIST"
    fi
else
    printf '    앱 설정값이 없습니다\n'
fi

# 위치 권한(TCC)은 번들 ID 에 귀속된다. 지우지 않으면 나중에 다시 설치했을 때
# "승인한 적 없는데 승인돼 있는" 상태가 남는다. 실패해도 제거를 멈추지 않는다.
if [ "$DRY_RUN" -eq 1 ]; then
    printf '    [dry-run] tccutil reset Location %s\n' "$BUNDLE_ID"
elif tccutil reset Location "$BUNDLE_ID" >/dev/null 2>&1; then
    printf '    위치 권한 기록을 초기화했습니다: %s\n' "$BUNDLE_ID"
else
    printf '    위치 권한 기록을 초기화하지 못했습니다. 직접 실행하세요:\n'
    printf '      tccutil reset Location %s\n' "$BUNDLE_ID"
fi

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
    check_gone "$PREFERENCES_PLIST"
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
printf '  - 알림 권한: 시스템 설정 > 알림 에서 %s 항목을 지우세요\n' "$APP_PROCESS_NAME"
printf '    (macOS 는 알림 설정을 명령으로 지울 방법을 제공하지 않습니다)\n'
