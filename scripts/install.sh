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
# ---------------------------------------------------------------------------
set -euo pipefail

REPO_ROOT=$(cd "$(dirname "$0")/.." && pwd)

LIBEXEC_DIR=/usr/local/libexec/exem-wifi-switcher
APPLY_PATH="$LIBEXEC_DIR/apply"
SAVE_CONFIG_PATH="$LIBEXEC_DIR/save-config"
CONFIG_DIR=/usr/local/etc/exem-wifi-switcher
CONFIG_PATH="$CONFIG_DIR/config.json"
SUDOERS_PATH=/etc/sudoers.d/exem-wifi-switcher
PROFILE_NAME_MAX_LENGTH=16

DRY_RUN=0

err() { printf '%s\n' "$*" >&2; }
die() { err ""; err "중단: $*"; exit 1; }
heading() { printf '\n\033[1m%s\033[0m\n' "$*"; }

usage() {
    cat <<'USAGE'
사용법: ./scripts/install.sh [--dry-run]

  --dry-run   실제로 바꾸지 않고, 실행할 명령만 보여준다 (sudo 를 쓰지 않는다)
  --help      이 도움말
USAGE
}

while [ $# -gt 0 ]; do
    case "$1" in
        --dry-run) DRY_RUN=1; shift ;;
        --help|-h) usage; exit 0 ;;
        *) usage >&2; die "알 수 없는 옵션입니다: $1" ;;
    esac
done

# 권한이 필요한 명령은 전부 이 함수를 통한다. dry-run 에서는 출력만 한다.
run_privileged() {
    if [ "$DRY_RUN" -eq 1 ]; then
        printf '    [dry-run] sudo %s\n' "$*"
        return 0
    fi
    sudo "$@"
}

# --- 사전 점검 --------------------------------------------------------------

[ "$(uname)" = "Darwin" ] || die "macOS 에서만 동작합니다"
[ -x /usr/sbin/networksetup ] || die "networksetup 을 찾지 못했습니다"
[ -f "$REPO_ROOT/scripts/apply" ] || die "scripts/apply 가 없습니다 (레포가 온전한지 확인하세요)"
[ -f "$REPO_ROOT/scripts/save-config" ] || die "scripts/save-config 가 없습니다 (레포가 온전한지 확인하세요)"
[ -f "$REPO_ROOT/config.example.json" ] || die "config.example.json 이 없습니다"

# 문법이 깨진 스크립트를 root 자리에 놓지 않는다.
bash -n "$REPO_ROOT/scripts/apply" || die "scripts/apply 에 문법 오류가 있습니다"
bash -n "$REPO_ROOT/scripts/save-config" || die "scripts/save-config 에 문법 오류가 있습니다"

# 이 스크립트 자체는 일반 사용자로 실행한다. 권한이 필요한 부분만 sudo 를 쓴다.
if [ "$(id -u)" -eq 0 ] && [ -z "${SUDO_USER:-}" ]; then
    die "일반 사용자 계정으로 실행하세요 (필요한 순간에만 sudo 로 승격합니다)"
fi
TARGET_USER="${SUDO_USER:-$(id -un)}"
id -u "$TARGET_USER" >/dev/null 2>&1 || die "사용자를 확인하지 못했습니다: $TARGET_USER"
case "$TARGET_USER" in
    ''|*[!a-zA-Z0-9._-]*) die "사용자 이름에 예상 밖의 문자가 있습니다: '$TARGET_USER'" ;;
esac

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
       - 또는 이 도구를 쓰지 않는다. 이 조합은 아직 지원하지 않습니다
         (README '한계' 항목에 적어 두었습니다)"
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
    printf '%s\n' "# 이 파일은 scripts/install.sh 가 만들었고 scripts/uninstall.sh 로 완전히 지울 수 있다."
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

cat <<PLAN

===========================================================================
 EXEM Wifi Switcher — 전환 코어 설치
===========================================================================

이 스크립트는 아래 작업만 합니다. 그 외에는 어떤 파일도 만들지 않습니다.

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

되돌리려면:  ./scripts/uninstall.sh

PLAN

if [ "$DRY_RUN" -eq 1 ]; then
    printf '%s\n' "[dry-run] 실제로는 아무것도 바꾸지 않습니다. 실행할 명령만 보여줍니다."
else
    if [ ! -t 0 ]; then
        die "확인 입력을 받을 수 없는 환경입니다 (터미널에서 직접 실행하세요)"
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
run_privileged /usr/bin/install -o root -g wheel -m 0755 "$REPO_ROOT/scripts/apply" "$APPLY_PATH"
run_privileged /usr/bin/install -o root -g wheel -m 0755 "$REPO_ROOT/scripts/save-config" "$SAVE_CONFIG_PATH"
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
    run_privileged /usr/bin/install -o root -g wheel -m 0644 "$REPO_ROOT/config.example.json" "$CONFIG_PATH"
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
    if ! sudo visudo -c >/dev/null 2>&1; then
        sudo rm -f "$SUDOERS_PATH"
        die "설치 후 전체 sudoers 검증에 실패해 방금 넣은 파일을 되돌렸습니다"
    fi
    printf '    전체 sudoers 검증 통과: %s\n' "$SUDOERS_PATH"
fi

# --- 확인 -------------------------------------------------------------------

heading "설치 결과"
if [ "$DRY_RUN" -eq 1 ]; then
    printf '  [dry-run] 아무것도 설치하지 않았습니다.\n'
else
    ls -l "$APPLY_PATH" "$SAVE_CONFIG_PATH" "$SUDOERS_PATH" "$CONFIG_PATH"
    printf '\n  암호 없이 실행되는지 확인:\n'
    if sudo -n -l "$APPLY_PATH" dhcp >/dev/null 2>&1; then
        printf '    apply — 확인됨. 프로필 전환 시 암호를 묻지 않습니다\n'
    else
        printf '    apply — 아직 확인되지 않았습니다. 새 터미널에서 아래 명령으로 다시 확인하세요:\n'
        printf '      sudo -n -l %s dhcp\n' "$APPLY_PATH"
    fi
    # save-config 가 무암호로 열려 있으면 설정 파일을 잠근 의미가 사라진다. 그 경우 소리 내어 알린다.
    if sudo -n -l "$SAVE_CONFIG_PATH" >/dev/null 2>&1; then
        printf '\n    경고: save-config 가 암호 없이 실행됩니다.\n'
        printf '      %s 에 이 경로를 여는 규칙이 남아 있는지 확인하세요.\n' "$SUDOERS_PATH"
        printf '      이 상태에서는 설정 파일을 root 소유로 잠근 의미가 없습니다.\n'
    else
        printf '    save-config — 암호 없이 실행되지 않습니다 (의도된 상태입니다)\n'
    fi
fi

cat <<'NEXT'

다음 할 일
  1. 설정 등록     앱을 실행해 설정 창에서 값을 입력하고 저장 (관리자 인증 1회)
                   터미널로 하려면: sudo nano /usr/local/etc/exem-wifi-switcher/config.json
  2. 설정 검증     swift run exem-wifi-switcher-cli validate
  3. 현재 상태     swift run exem-wifi-switcher-cli status
  4. 전환         swift run exem-wifi-switcher-cli apply <프로필이름>

되돌리기         ./scripts/uninstall.sh
NEXT
