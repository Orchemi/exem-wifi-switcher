#!/bin/bash
# ---------------------------------------------------------------------------
# install.sh — EXEM Wifi Switcher 전환 코어를 설치한다.
#
# 이 스크립트는 시스템에 네 가지를 남긴다. 그 외에는 아무것도 건드리지 않는다.
#
#   1. /usr/local/libexec/exem-wifi-switcher/apply       (root:wheel 0755)
#        네트워크 구성을 실제로 바꾸는 스크립트. 이 파일만 암호 없이 root 로 실행된다.
#   2. /usr/local/libexec/exem-wifi-switcher/save-config (root:wheel 0755)
#        설정 파일을 제자리에 놓는 스크립트. **관리자 인증을 거쳐야** 실행된다
#        (sudoers 에 넣지 않는다 — 넣으면 설정 파일을 잠근 의미가 사라진다).
#   3. /usr/local/etc/exem-wifi-switcher/config.json     (root:wheel 0644)
#        사용자의 프로필 설정. 사용자 권한으로는 고칠 수 없다.
#        이 파일의 값이 root 의 networksetup 인자가 되기 때문이다.
#   4. /etc/sudoers.d/exem-wifi-switcher                 (root:wheel 0440)
#        위 1번 경로를, 프로필 이름 형태의 인자로 부를 때만 암호 없이 허용하는 규칙.
#
# 무엇을 할지 먼저 전부 출력하고 확인을 받은 뒤에 진행한다.
# 미리 보기만 하려면:  ./scripts/install.sh --dry-run
#
# 되돌리기:  ./scripts/uninstall.sh
#
# 두 길로 들어온다. **설치 로직은 이 파일 하나뿐이다** — 앱이 같은 파일을 부른다.
#
#   1. 터미널에서 일반 사용자로 실행 → 필요한 순간에만 sudo 로 승격한다
#   2. 앱의 [설치] 버튼 → 관리자 인증을 거쳐 root 로 실행된다.
#      root 로 들어올 때는 sudo 규칙을 적을 대상 계정을 알 수 없으므로 --user 로 받는다
#
# 그래서 설치할 원본(apply · save-config · config.example.json)은 레포 위치가 아니라
# **이 스크립트가 놓인 자리**를 기준으로 찾는다. 레포에서 실행하든 앱 번들 안에서
# 실행하든 같은 코드가 같은 결과를 낸다.
# ---------------------------------------------------------------------------
set -euo pipefail

# 이 스크립트는 root 로도 실행된다 (앱의 [설치] 버튼). 그 자리에서 PATH 를 물려받지 않는다 —
# apply · save-config 가 지키는 규칙과 같다.
PATH=/usr/sbin:/usr/bin:/sbin:/bin
export PATH

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd -P)
SCRIPT_NAME=$(basename "$0")

# 설치할 원본을 이 스크립트 기준으로 찾는다.
#   레포     <repo>/scripts/install.sh        → apply·save-config 는 같은 자리, 예시 설정은 한 단계 위
#   앱 번들  …/Contents/Resources/scripts/    → 넷 다 같은 자리
SOURCE_APPLY="$SCRIPT_DIR/apply"
SOURCE_SAVE_CONFIG="$SCRIPT_DIR/save-config"
if [ -f "$SCRIPT_DIR/config.example.json" ]; then
    SOURCE_CONFIG_EXAMPLE="$SCRIPT_DIR/config.example.json"
else
    SOURCE_CONFIG_EXAMPLE="$SCRIPT_DIR/../config.example.json"
fi

LIBEXEC_DIR=/usr/local/libexec/exem-wifi-switcher
APPLY_PATH="$LIBEXEC_DIR/apply"
SAVE_CONFIG_PATH="$LIBEXEC_DIR/save-config"
CONFIG_DIR=/usr/local/etc/exem-wifi-switcher
CONFIG_PATH="$CONFIG_DIR/config.json"
SUDOERS_PATH=/etc/sudoers.d/exem-wifi-switcher
PROFILE_NAME_MAX_LENGTH=16

DRY_RUN=0
ASSUME_YES=0
USER_OVERRIDE=""

IS_ROOT=0
[ "$(id -u)" -eq 0 ] && IS_ROOT=1

err() { printf '%s\n' "$*" >&2; }
die() { err ""; err "중단: $*"; exit 1; }
heading() { printf '\n\033[1m%s\033[0m\n' "$*"; }

usage() {
    cat <<'USAGE'
사용법: ./scripts/install.sh [--dry-run] [--yes] [--user <계정>]

  --dry-run     실제로 바꾸지 않고, 실행할 명령만 보여준다 (sudo 를 쓰지 않는다)
  --yes         확인 입력을 건너뛴다. 부르는 쪽이 같은 내용을 이미 보여주고
                확인을 받았을 때만 쓴다 (앱의 [설치] 버튼이 이 길로 들어온다)
  --user <계정> sudo 규칙을 적을 대상 계정. root 로 실행할 때는 반드시 지정해야 한다
  --help        이 도움말
USAGE
}

while [ $# -gt 0 ]; do
    case "$1" in
        --dry-run) DRY_RUN=1; shift ;;
        --yes) ASSUME_YES=1; shift ;;
        --user) [ $# -ge 2 ] || die "--user 뒤에 계정 이름이 필요합니다"; USER_OVERRIDE="$2"; shift 2 ;;
        --help|-h) usage; exit 0 ;;
        *) usage >&2; die "알 수 없는 옵션입니다: $1" ;;
    esac
done

# 권한이 필요한 명령은 전부 이 함수를 통한다. dry-run 에서는 출력만 한다.
# 이미 root 면 sudo 를 거치지 않는다 — 앱에서 들어온 경로에는 sudo 를 쓸 자리가 없다.
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

# --- 안전성 검사 ------------------------------------------------------------

# 권한 비트가 root 외의 사용자에게 쓰기를 열어 주는가. 열려 있으면 0(참).
# 판독할 수 없는 값은 위험한 쪽으로 판정한다(fail closed).
# 그룹 쓰기도 world 쓰기와 똑같이 위험하다 — 그 그룹의 아무 프로세스나 내용을 갈아 끼울 수 있다.
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

# 이 파일을 "소유자 말고 다른 사람" 이 고칠 수 있는가.
#
# root 로 실행될 내용을 여기서 읽어 가므로, 아무나 쓸 수 있는 자리에 있으면 설치하지 않는다.
# 심링크는 따라가지 않고 그대로 거부한다 — 링크가 가리키는 자리를 우리가 보장할 수 없다.
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
        die "$label 을 소유자 외의 사용자가 고칠 수 있습니다: $path (권한 $perms)
     root 로 실행될 내용을 여기서 가져오므로, 이 상태에서는 설치하지 않습니다."
    fi
}

# root 로 돌 때 이 스크립트 자신이 신뢰할 수 있는 자리에 있는지 본다.
#
# 앱 번들은 사용자가 쓸 수 있는 자리에 놓이므로 **앱 자신은 신뢰 경계가 아니다.**
# 이 검사가 막는 것은 "이 Mac 의 다른 계정이 내용을 갈아 끼울 수 있는 상태" 까지다.
# 그 이상은 보장하지 않는다 (apply · save-config 의 assert_self_is_safe 와 같은 발상).
assert_self_is_safe() {
    assert_not_foreign_writable "$SCRIPT_DIR" "설치 스크립트 디렉터리"
    assert_not_foreign_writable "$SCRIPT_DIR/$SCRIPT_NAME" "설치 스크립트"
}

# --- 사전 점검 --------------------------------------------------------------

[ "$(uname)" = "Darwin" ] || die "macOS 에서만 동작합니다"
[ -x /usr/sbin/networksetup ] || die "networksetup 을 찾지 못했습니다"
[ -f "$SOURCE_APPLY" ] || die "apply 를 찾지 못했습니다: $SOURCE_APPLY"
[ -f "$SOURCE_SAVE_CONFIG" ] || die "save-config 를 찾지 못했습니다: $SOURCE_SAVE_CONFIG"
[ -f "$SOURCE_CONFIG_EXAMPLE" ] || die "config.example.json 을 찾지 못했습니다: $SOURCE_CONFIG_EXAMPLE"

# root 자리에 놓을 내용이 오는 곳부터 확인한다.
assert_not_foreign_writable "$SOURCE_APPLY" "설치할 apply"
assert_not_foreign_writable "$SOURCE_SAVE_CONFIG" "설치할 save-config"
assert_not_foreign_writable "$SOURCE_CONFIG_EXAMPLE" "예시 설정 파일"

# 문법이 깨진 스크립트를 root 자리에 놓지 않는다.
bash -n "$SOURCE_APPLY" || die "apply 에 문법 오류가 있습니다"
bash -n "$SOURCE_SAVE_CONFIG" || die "save-config 에 문법 오류가 있습니다"

# 터미널에서는 일반 사용자로 실행한다 (권한이 필요한 부분만 sudo).
# 앱에서 관리자 인증을 거쳐 들어오면 이미 root 다. 그때는 규칙을 적을 계정을 알 수 없으므로
# --user 로 받고, 이 파일 자신이 신뢰할 만한 자리에 있는지 먼저 확인한다.
if [ "$IS_ROOT" -eq 1 ]; then
    assert_self_is_safe
    if [ -z "$USER_OVERRIDE" ] && [ -z "${SUDO_USER:-}" ]; then
        die "root 로 실행할 때는 --user <계정> 으로 sudo 규칙을 적을 대상을 지정하세요
     (그냥 실행하면 root 계정 앞으로 규칙이 적혀 아무 쓸모가 없습니다)"
    fi
fi

# 앱에서 들어왔는가. 안내 문구가 갈리는 기준이다.
#
# 앱으로 설치한 사람에게는 **레포도 swift 도 없다.** 그 사람이 [설치] 전에 읽는 마지막 화면은
# 이 스크립트의 --dry-run 출력 전문이므로, 여기에 `swift run …` 이나 `./scripts/uninstall.sh` 를
# 실으면 실행할 수 없는 명령을 '다음 할 일' 로 받는다.
#   - 앱   : --user / --yes 로 들어온다 (계획 미리보기는 --dry-run --user, 실제 실행은 --yes --user)
#   - 레포 : 아무것도 붙지 않는다
INVOKED_FROM_APP=0
if [ "$IS_ROOT" -eq 1 ] || [ "$ASSUME_YES" -eq 1 ] || [ -n "$USER_OVERRIDE" ]; then
    INVOKED_FROM_APP=1
fi

TARGET_USER="${USER_OVERRIDE:-${SUDO_USER:-$(id -un)}}"
case "$TARGET_USER" in
    ''|*[!a-zA-Z0-9._-]*) die "사용자 이름에 예상 밖의 문자가 있습니다: '$TARGET_USER'" ;;
esac
TARGET_UID=$(id -u "$TARGET_USER" 2>/dev/null) || die "사용자를 확인하지 못했습니다: $TARGET_USER"
case "$TARGET_UID" in
    ''|*[!0-9]*) die "사용자 uid 를 읽지 못했습니다: $TARGET_USER" ;;
esac
# 시스템 계정(uid < 500)에는 규칙을 넣지 않는다. 로그인해서 쓰는 계정만 대상이다.
if [ "$TARGET_UID" -lt 500 ]; then
    die "로그인 계정이 아닙니다: $TARGET_USER (uid=$TARGET_UID)"
fi

# 이 계정이 admin 그룹에 속하는가.
#
# `sudo` 를 실행해 보는 방식(`sudo -n -v`)은 쓰지 않는다 — 확인하려고 부른 명령이
# 그 자리에서 암호를 묻거나 실패 기록을 남긴다. 그룹 소속은 아무것도 건드리지 않고 읽을 수 있다.
user_is_admin() {
    local name="$1" group
    for group in $(id -Gn "$name" 2>/dev/null); do
        [ "$group" = "admin" ] && return 0
    done
    return 1
}

# 관리자 계정이 아니면 첫 sudo 에서 죽는다. **그때는 sudo 자신의 메시지만 남는다** —
# 원인도, 다음에 무엇을 하면 되는지도 없다. 이 스크립트의 다른 실패는 전부 원인과 대안을 주므로
# 이 자리만 어긋나 있었다. 그래서 sudo 를 부르기 전에 미리 말한다.
#
# root 로 들어온 경우(앱의 [설치])는 볼 것이 없다 — 이미 인증을 거쳤다.
if [ "$IS_ROOT" -eq 0 ] && ! user_is_admin "$(id -un)"; then
    NOT_ADMIN_MESSAGE="관리자 계정이 아닙니다: $(id -un)
     관리자 계정에서 실행하거나, 앱의 [설치] 버튼으로 관리자 이름·암호를 입력하세요.
     (이 스크립트는 권한이 필요한 명령마다 sudo 로 승격합니다)"
    if [ "$DRY_RUN" -eq 1 ]; then
        # 미리 보기는 sudo 를 쓰지 않으므로 끝까지 돈다. 다만 실제 설치는 막힐 자리다.
        err "알림: $NOT_ADMIN_MESSAGE"
    else
        die "$NOT_ADMIN_MESSAGE"
    fi
fi

# Homebrew 가 이 경로를 쓰고 있는가. (Intel Mac 의 Homebrew 는 /usr/local 을 사용자 소유로 바꾼다)
homebrew_owns_usr_local() {
    [ -d /usr/local/Homebrew ] || [ -d /usr/local/Cellar ] || [ -x /usr/local/bin/brew ]
}

# 상위 디렉터리가 root 소유가 아니면 그 경로에 root 스크립트를 둘 수 없다.
#
# sudo 는 sudoers 에 적힌 **경로**를 실행한다. 그 경로의 상위 디렉터리를 사용자가 소유하면
# 사용자 권한 프로세스가 디렉터리를 통째로 갈아 끼울 수 있고, 그러면 그 자리에 놓인 임의의
# 코드가 무암호로 root 실행된다. 그래서 이 검사는 경고가 아니라 **중단**이다.
#
# 심링크는 따라가지 않고 그대로 거부한다. 링크의 소유·권한만 보고 통과시키면
# 링크가 가리키는 사용자 소유 디렉터리에 그대로 설치하게 된다.
check_parent_directory() {
    local path="$1" owner perms
    if [ -L "$path" ]; then
        die "$path 이 심볼릭 링크입니다.
     링크가 가리키는 자리를 누가 소유하는지 보장할 수 없어 설치하지 않습니다."
    fi
    [ -e "$path" ] || return 0
    owner=$(stat -f '%u' "$path") || die "$path 의 소유자를 읽지 못했습니다. 설치를 중단합니다."
    perms=$(stat -f '%OLp' "$path") || die "$path 의 권한을 읽지 못했습니다. 설치를 중단합니다."
    case "$owner" in
        ''|*[!0-9]*) die "$path 의 소유자를 읽지 못했습니다. 설치를 중단합니다." ;;
    esac

    if [ "$owner" -ne 0 ]; then
        if [ "$path" = /usr/local ] && homebrew_owns_usr_local; then
            die "/usr/local 이 Homebrew 소유입니다 (uid=$owner).

     이 상태에서는 root 로 실행되는 스크립트를 /usr/local 아래에 안전하게 둘 수 없습니다.
     sudo 는 규칙에 적힌 경로를 그대로 실행하므로, 그 경로를 사용자 권한으로 갈아 끼울 수
     있으면 임의의 코드가 무암호로 root 실행됩니다.

     >>> 절대로 sudo chown root:wheel /usr/local 을 실행하지 마세요. <<<
     Homebrew 가 통째로 망가지고, brew 로는 되돌릴 수 없습니다.
     (Apple Silicon 의 Homebrew 는 /opt/homebrew 를 쓰므로 이 문제가 없습니다)

     지금 할 수 있는 것:
       - Apple Silicon Mac 이나 Homebrew 가 /usr/local 을 쓰지 않는 Mac 에서 설치한다
       - 또는 이 도구를 쓰지 않는다. 이 조합을 아직 지원하지 않는 이유는 여기에 적어
         두었습니다: https://github.com/Orchemi/exem-wifi-switcher/blob/main/docs/guide.md#한계"
        fi
        die "$path 의 소유자가 root 가 아닙니다 (uid=$owner).
     이 상태에서는 권한 스크립트를 안전하게 놓을 수 없습니다.
     이 경로를 쓰는 다른 도구가 없다면 sudo chown root:wheel '$path' 로 정리한 뒤 다시 실행하세요.
     (Homebrew 등 /usr/local 을 소유하는 도구가 있다면 chown 하지 마세요 — 그 도구가 망가집니다)"
    fi
    # group-write 도 world-write 와 똑같이 위험하다 — 그 그룹의 아무 프로세스나 경로를 갈아 끼울 수 있다.
    if [ $(( 8#$perms & 8#0022 )) -ne 0 ]; then
        die "$path 을 root 외의 사용자가 쓸 수 있습니다 (권한 $perms). 설치를 중단합니다."
    fi
}
check_parent_directory /usr/local
check_parent_directory /usr/local/libexec
check_parent_directory /usr/local/etc

# --- sudoers 내용 만들기 -----------------------------------------------------

# sudoers 의 인자 패턴은 glob 이라 "문자 클래스의 반복"을 표현할 수 없다.
# 그래서 `*` 를 쓰는 대신 길이별 고정 패턴을 나열한다.
# 이렇게 하면 공백·세미콜론·슬래시·점이 섞인 인자는 sudo 단계에서 이미 거부된다.
build_sudoers_content() {
    local index=1 pattern="[A-Za-z0-9]" line
    printf '%s\n' "# EXEM Wifi Switcher"
    printf '%s\n' "# 네트워크 구성 전환 스크립트 하나만 암호 없이 실행하도록 허용한다."
    printf '%s\n' "#"
    printf '%s\n' "#   명령  : $APPLY_PATH  (이 경로 외에는 아무것도 허용하지 않는다)"
    printf '%s\n' "#   인자  : 프로필 이름 형태 1개. 와일드카드(*)를 쓰지 않고 길이별 패턴을 나열한다"
    printf '%s\n' "#   사용자: $TARGET_USER"
    printf '%s\n' "#"
    # 이 줄은 들어온 길에 따라 갈리지 않는다 — 앱으로 설치해도 터미널로 설치해도
    # 같은 파일이 놓여야 한다. 그래서 두 길을 다 적는다.
    printf '%s\n' "# 이 파일은 install.sh 가 만들었다. 앱 설정 창의 [제거] 또는 scripts/uninstall.sh 로 완전히 지울 수 있다."
    printf '%s\n' ""
    printf '%s\n' "Cmnd_Alias EXEM_WIFI_SWITCHER_APPLY = \\"
    while [ "$index" -le "$PROFILE_NAME_MAX_LENGTH" ]; do
        line="    $APPLY_PATH $pattern"
        if [ "$index" -lt "$PROFILE_NAME_MAX_LENGTH" ]; then
            printf '%s,\\\n' "$line"
        else
            printf '%s\n' "$line"
        fi
        pattern="$pattern[A-Za-z0-9_-]"
        index=$(( index + 1 ))
    done
    printf '%s\n' ""
    printf '%s\n' "$TARGET_USER ALL=(root) NOPASSWD: EXEM_WIFI_SWITCHER_APPLY"
}

# --- 무엇을 할지 먼저 보여준다 ------------------------------------------------

# 이 계획은 앱의 [설치] 창에 전문이 그대로 실린다. 그 사람이 닿을 수 있는 길만 적는다.
if [ "$INVOKED_FROM_APP" -eq 1 ]; then
    UNDO_HINT="설정 창의 권한 항목에서 [제거]"
else
    UNDO_HINT="./scripts/uninstall.sh"
fi

cat <<PLAN

===========================================================================
 EXEM Wifi Switcher — 전환 코어 설치
===========================================================================

이 스크립트는 아래 작업만 합니다. 그 외에는 어떤 파일도 만들지 않습니다.

 설치 원본  $SCRIPT_DIR
 대상 계정  $TARGET_USER

 1) 권한 스크립트 배치
      $LIBEXEC_DIR/   (디렉터리, root:wheel 0755)
        apply         root:wheel 0755 — networksetup -setmanual / -setdhcp 를 실행합니다.
                      이 파일 하나만 암호 없이 root 로 실행됩니다.
        save-config   root:wheel 0755 — 설정 파일을 제자리에 놓습니다.
                      암호 없이 실행되지 않습니다. 저장할 때마다 관리자 인증을 받습니다.

      상위 디렉터리(/usr/local, /usr/local/libexec, /usr/local/etc)가 없으면
      root:wheel 0755 로 만듭니다. 이미 있으면 건드리지 않습니다.

 2) 설정 디렉터리 생성
      $CONFIG_DIR/     (디렉터리, root:wheel 0755)
      $CONFIG_PATH
      소유자 root:wheel, 권한 0644 — 사용자 권한으로는 고칠 수 없습니다.

      왜 잠그는가: 이 파일의 dns · router 값은 아래 3) 규칙으로 무암호 실행되는 apply 를 통해
      root 의 networksetup 인자가 됩니다. 파일을 사용자가 고칠 수 있으면, 암호를 모르는 코드가
      시스템 DNS 와 기본 게이트웨이를 갈아치울 수 있습니다.
      대신 앱에서 저장할 때 관리자 인증을 한 번 받습니다. 전환할 때는 묻지 않습니다.

      설정 파일이 없으면 config.example.json 을 복사합니다.
      이미 있으면 내용은 그대로 두고 소유자·권한만 위 값으로 맞춥니다.

 3) sudo 규칙 추가
      $SUDOERS_PATH
      소유자 root:wheel, 권한 0440
      '$TARGET_USER' 계정이 위 1)의 apply 를 암호 없이 실행할 수 있게 합니다.
      save-config 는 여기 넣지 않습니다. 다른 명령도 열지 않습니다.
      파일을 놓기 전에 visudo -c 로 문법을 검증합니다.

      ※ 이 규칙은 '$TARGET_USER' 한 사람만 허용합니다. 이 Mac 을 여러 계정이 쓴다면,
        다른 계정으로 이 스크립트를 다시 실행할 때 규칙 파일이 통째로 덮여
        이전 계정의 무암호 전환이 조용히 끊깁니다. (그 계정에서 다시 실행하면 복구됩니다)

설치되는 sudo 규칙 전문:
---------------------------------------------------------------------------
$(build_sudoers_content)
---------------------------------------------------------------------------

되돌리려면:  $UNDO_HINT

PLAN

if [ "$DRY_RUN" -eq 1 ]; then
    printf '%s\n' "[dry-run] 실제로는 아무것도 바꾸지 않습니다. 실행할 명령만 보여줍니다."
elif [ "$ASSUME_YES" -eq 1 ]; then
    # 부르는 쪽이 같은 내용을 보여주고 확인을 받았다는 전제다 (앱의 [설치] 버튼).
    printf '%s\n' "확인을 받았다는 전제로 진행합니다 (--yes)."
else
    if [ ! -t 0 ]; then
        die "확인 입력을 받을 수 없는 환경입니다 (터미널에서 직접 실행하거나 --yes 를 쓰세요)"
    fi
    printf '위 내용대로 설치하려면 yes 를 입력하세요: '
    read -r reply
    [ "$reply" = "yes" ] || die "사용자가 취소했습니다"
fi

# --- 1) 권한 스크립트 --------------------------------------------------------

heading "1/3  권한 스크립트 배치"

# 상위 디렉터리를 **하나씩 명시적으로** 만든다.
#
# BSD 의 install -d 는 중간 디렉터리도 -o/-g/-m 을 그대로 물려 만든다. 예전처럼 leaf 만
# 지정하면, /usr/local/etc 가 없는 Mac(Apple Silicon + Homebrew 조합에서 흔하다)에서
# 이 도구와 무관한 시스템 디렉터리가 엉뚱한 소유·권한으로 생겨난다.
for parent in /usr/local /usr/local/libexec /usr/local/etc; do
    if [ ! -d "$parent" ]; then
        run_privileged /usr/bin/install -d -o root -g wheel -m 0755 "$parent"
        printf '    상위 디렉터리를 만들었습니다: %s (root:wheel 0755)\n' "$parent"
    fi
done

run_privileged /usr/bin/install -d -o root -g wheel -m 0755 "$LIBEXEC_DIR"
run_privileged /usr/bin/install -o root -g wheel -m 0755 "$SOURCE_APPLY" "$APPLY_PATH"
run_privileged /usr/bin/install -o root -g wheel -m 0755 "$SOURCE_SAVE_CONFIG" "$SAVE_CONFIG_PATH"
printf '    %s\n' "$APPLY_PATH"
printf '    %s\n' "$SAVE_CONFIG_PATH"

# --- 2) 설정 파일 -----------------------------------------------------------

heading "2/3  설정 디렉터리"
run_privileged /usr/bin/install -d -o root -g wheel -m 0755 "$CONFIG_DIR"
if [ -f "$CONFIG_PATH" ]; then
    # 내용은 사용자 것이므로 건드리지 않는다. 다만 소유·권한은 반드시 맞춘다 —
    # 예전 버전이 놓은 root:admin 0664 를 그대로 두면 admin 그룹의 아무 프로세스나
    # root 의 networksetup 인자를 갈아치울 수 있다.
    run_privileged /usr/sbin/chown root:wheel "$CONFIG_PATH"
    run_privileged /bin/chmod 0644 "$CONFIG_PATH"
    printf '    기존 설정을 유지하고 권한만 맞췄습니다: %s (root:wheel 0644)\n' "$CONFIG_PATH"
else
    run_privileged /usr/bin/install -o root -g wheel -m 0644 "$SOURCE_CONFIG_EXAMPLE" "$CONFIG_PATH"
    printf '    예시 설정을 복사했습니다: %s\n' "$CONFIG_PATH"
    printf '    앱의 설정 창에서 실제 값을 등록하세요 (저장할 때 관리자 인증을 한 번 받습니다)\n'
fi

# --- 3) sudoers -------------------------------------------------------------

heading "3/3  sudo 규칙"

SUDOERS_TEMP=$(mktemp -t exem-wifi-switcher-sudoers)
cleanup() { rm -f "$SUDOERS_TEMP"; }
trap cleanup EXIT
chmod 0600 "$SUDOERS_TEMP"
build_sudoers_content > "$SUDOERS_TEMP"

# 문법 검증이 먼저다. 잘못된 파일이 /etc/sudoers.d 에 들어가면 sudo 자체가 망가진다.
if ! visudo -c -f "$SUDOERS_TEMP" >/dev/null 2>&1; then
    err "생성한 sudo 규칙이 문법 검사를 통과하지 못했습니다. 아래는 검사 결과입니다:"
    visudo -c -f "$SUDOERS_TEMP" >&2 || true
    die "sudoers 파일을 설치하지 않았습니다 (시스템은 그대로입니다)"
fi
printf '    visudo -c 문법 검증 통과\n'

run_privileged /usr/bin/install -o root -g wheel -m 0440 "$SUDOERS_TEMP" "$SUDOERS_PATH"

# 설치 후 전체 sudoers 를 다시 검증한다. 문제가 있으면 즉시 되돌린다.
if [ "$DRY_RUN" -eq 0 ]; then
    if [ "$IS_ROOT" -eq 1 ]; then
        visudo_ok() { visudo -c >/dev/null 2>&1; }
    else
        visudo_ok() { sudo visudo -c >/dev/null 2>&1; }
    fi
    if ! visudo_ok; then
        run_privileged /bin/rm -f "$SUDOERS_PATH"
        die "설치 후 전체 sudoers 검증에 실패해 방금 넣은 파일을 되돌렸습니다"
    fi
    printf '    전체 sudoers 검증 통과: %s\n' "$SUDOERS_PATH"
fi

# --- 확인 -------------------------------------------------------------------

heading "설치 결과"

# 규칙이 대상 계정에 실제로 걸렸는지 sudo 에게 되묻는다.
#
# root 로 실행 중일 때는 -U 로 대상 계정의 규칙을 조회한다. 이 경우 root 는 애초에 암호를
# 묻지 않으므로 "무암호인가" 까지는 확인되지 않는다 — 규칙이 그 계정·그 경로·그 인자에
# 걸리는지까지만 본다. (터미널에서 사용자로 실행하면 -n 이 무암호 여부까지 확인한다)
sudo_rule_matches() {
    if [ "$IS_ROOT" -eq 1 ]; then
        sudo -n -l -U "$TARGET_USER" "$@" >/dev/null 2>&1
    else
        sudo -n -l "$@" >/dev/null 2>&1
    fi
}

if [ "$DRY_RUN" -eq 1 ]; then
    printf '  [dry-run] 아무것도 설치하지 않았습니다.\n'
else
    ls -l "$APPLY_PATH" "$SAVE_CONFIG_PATH" "$SUDOERS_PATH" "$CONFIG_PATH"
    printf '\n  암호 없이 실행되는지 확인:\n'
    if sudo_rule_matches "$APPLY_PATH" dhcp; then
        printf '    apply — 확인됨. 프로필 전환 시 암호를 묻지 않습니다\n'
    else
        printf '    apply — 아직 확인되지 않았습니다. 새 터미널에서 아래 명령으로 다시 확인하세요:\n'
        printf '      sudo -n -l %s dhcp\n' "$APPLY_PATH"
    fi
    # save-config 가 무암호로 열려 있으면 설정 파일을 잠근 의미가 사라진다. 그 경우 소리 내어 알린다.
    if sudo_rule_matches "$SAVE_CONFIG_PATH"; then
        printf '\n    경고: save-config 가 암호 없이 실행됩니다.\n'
        printf '      %s 에 이 경로를 여는 규칙이 남아 있는지 확인하세요.\n' "$SUDOERS_PATH"
        printf '      이 상태에서는 설정 파일을 root 소유로 잠근 의미가 없습니다.\n'
    else
        printf '    save-config — 암호 없이 실행되지 않습니다 (의도된 상태입니다)\n'
    fi
fi

# 다음 할 일도 들어온 길에 따라 갈린다.
#
# 앱으로 온 사람에게 `swift run …` 을 건네면 안 된다 — 레포도 swift 도 없고,
# README 가 내건 전제("터미널을 쓰지 않는다")와도 어긋난다.
if [ "$INVOKED_FROM_APP" -eq 1 ]; then
    cat <<'NEXT'

다음 할 일
  1. 설정 등록     설정 창에서 사내 Wi-Fi 이름·IP·서브넷 마스크·라우터·DNS 를 입력하고 [저장]
                   (저장할 때 관리자 인증을 한 번 더 받습니다)
  2. 확인          메뉴바 아이콘의 첫 줄이 '초기 설정하기' 에서 바뀌면 끝났습니다.
                   설정 창의 권한 항목에서도 같은 상태를 볼 수 있습니다

되돌리기         설정 창의 권한 항목에서 [제거]
NEXT
else
    cat <<'NEXT'

다음 할 일
  1. 설정 등록     앱을 실행해 설정 창에서 값을 입력하고 저장 (관리자 인증 1회)
                   터미널로 하려면: sudo nano /usr/local/etc/exem-wifi-switcher/config.json
                   그때는 파일 안 "_readme" 블록을 지우세요 — 남아 있으면 앱이
                   '아직 저장 안 됨' 으로 판정해 값을 쓰지 않습니다
  2. 설정 검증     swift run exem-wifi-switcher-cli validate
  3. 현재 상태     swift run exem-wifi-switcher-cli status
  4. 전환         swift run exem-wifi-switcher-cli apply <프로필이름>

되돌리기         ./scripts/uninstall.sh
NEXT
fi
