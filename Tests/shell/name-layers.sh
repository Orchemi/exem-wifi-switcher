#!/bin/bash
# ---------------------------------------------------------------------------
# name-layers.sh — 프로필 이름 검증의 **아래 두 계층**을 같은 입력으로 돌린다.
#
#   사용: ./Tests/shell/name-layers.sh <이름>...
#   출력: 이름 하나당 한 줄, "<apply 판정> <sudoers 판정>" (1=허용, 0=거부)
#
# 위쪽 계층(Sources/WifiSwitcherCore/ProfileName.swift)은 Swift 테스트가 맡고,
# 세 판정이 전부 일치하는지도 그쪽에서 대조한다 (ProfileNameLayerParityTests).
#
# sudoers 계층은 실제 sudo 를 부를 수 없으므로, install.sh 가 만들어내는 인자 패턴을
# 그대로 뽑아 bash `case` 로 매칭해 근사한다. 둘 다 glob(fnmatch) 이라 결과가 같다.
#
# 이름은 argv 로 받는다 — 셸이 쪼개거나 해석할 여지를 남기지 않기 위해서다.
# ---------------------------------------------------------------------------

REPO_ROOT=$(cd "$(dirname "$0")/../.." && pwd)

# scripts/apply 를 source 하면 main 은 돌지 않고 검증 함수만 들어온다.
# (LC_ALL=C 도 함께 들어와 glob 문자 범위가 바이트 단위로 고정된다)
# shellcheck source=../../scripts/apply
. "$REPO_ROOT/scripts/apply"

# --- sudoers 인자 패턴 뽑아내기 ------------------------------------------------

patterns=()
while IFS= read -r line; do
    case "$line" in
        *"/exem-wifi-switcher/apply ["*) ;;
        *) continue ;;
    esac
    pattern=${line#*"/exem-wifi-switcher/apply "}
    pattern=${pattern%,\\}
    patterns+=("$pattern")
done < <("$REPO_ROOT/scripts/install.sh" --dry-run 2>/dev/null)

if [ ${#patterns[@]} -eq 0 ]; then
    printf 'sudoers 인자 패턴을 하나도 찾지 못했습니다\n' >&2
    exit 1
fi

matches_sudoers() {
    local name="$1" pattern
    for pattern in "${patterns[@]}"; do
        # 따옴표 없는 $pattern 은 case 에서 glob 으로 해석된다 — sudo 와 같은 방식이다.
        case "$name" in
            $pattern) return 0 ;;
        esac
    done
    return 1
}

# --- 판정 --------------------------------------------------------------------

for name in "$@"; do
    if validate_profile_name "$name"; then apply_verdict=1; else apply_verdict=0; fi
    if matches_sudoers "$name"; then sudoers_verdict=1; else sudoers_verdict=0; fi
    printf '%s %s\n' "$apply_verdict" "$sudoers_verdict"
done
