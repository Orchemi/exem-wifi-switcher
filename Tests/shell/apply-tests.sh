#!/bin/bash
# ---------------------------------------------------------------------------
# scripts/apply · install.sh · uninstall.sh 검증.
#
# 시스템을 건드리지 않는다 — sudo 를 쓰지 않고, 설치 스크립트는 --dry-run 으로만 돌린다.
# `swift test` 가 이 파일을 실행하므로 별도로 부를 일은 없지만 단독 실행도 된다:
#
#     ./Tests/shell/apply-tests.sh
# ---------------------------------------------------------------------------

REPO_ROOT=$(cd "$(dirname "$0")/../.." && pwd)
APPLY="$REPO_ROOT/scripts/apply"

pass_count=0
fail_count=0

t_pass() { pass_count=$(( pass_count + 1 )); }
t_fail() {
    fail_count=$(( fail_count + 1 ))
    printf '  실패: %s\n' "$*" >&2
}
t_section() { printf '\n▸ %s\n' "$*"; }

# t_accept <설명> <입력> — 검증 함수가 통과시켜야 하는 입력
t_accept() {
    local fn="$1" value="$2"
    if "$fn" "$value"; then t_pass; else t_fail "$fn 이 '$value' 를 거부했습니다 (통과해야 함)"; fi
}
# t_reject <설명> <입력> — 검증 함수가 반드시 막아야 하는 입력
t_reject() {
    local fn="$1" value="$2"
    if "$fn" "$value"; then t_fail "$fn 이 '$value' 를 통과시켰습니다 (거부해야 함)"; else t_pass; fi
}
t_equals() {
    local expected="$1" actual="$2" label="$3"
    if [ "$expected" = "$actual" ]; then t_pass; else t_fail "$label — 기대 '$expected', 실제 '$actual'"; fi
}

# --- 문법 -------------------------------------------------------------------

t_section "셸 문법"
for script in "$APPLY" "$REPO_ROOT/scripts/install.sh" "$REPO_ROOT/scripts/uninstall.sh"; do
    if bash -n "$script" 2>/dev/null; then t_pass; else t_fail "문법 오류: $script"; fi
done

# 위험한 구문이 들어오는 것을 막는다. root 로 도는 스크립트에 eval 은 없어야 한다.
if grep -qE '(^|[^[:alnum:]_])eval[[:space:]]' "$APPLY"; then
    t_fail "apply 에 eval 이 있습니다"
else
    t_pass
fi

# --- 검증 함수 (직접 호출) ----------------------------------------------------

# main 은 실행되지 않는다. 검증 함수만 가져온다.
# shellcheck source=../../scripts/apply
. "$APPLY"

t_section "프로필 이름 화이트리스트"
for name in office dhcp home a A Z0 x-y_z office2 abcdefghijklmnop; do
    t_accept validate_profile_name "$name"
done

# 셸 인젝션·경로 탈출·형식 위반은 전부 막혀야 한다.
t_reject validate_profile_name 'office; rm -rf /'
t_reject validate_profile_name 'office;id'
t_reject validate_profile_name 'office && id'
t_reject validate_profile_name 'office|id'
t_reject validate_profile_name '$(id)'
t_reject validate_profile_name '`id`'
t_reject validate_profile_name '${HOME}'
t_reject validate_profile_name '../../etc/passwd'
t_reject validate_profile_name '/etc/sudoers'
t_reject validate_profile_name './apply'
t_reject validate_profile_name 'office name'
t_reject validate_profile_name $'office\nrm -rf /'
t_reject validate_profile_name $'office\trm'
t_reject validate_profile_name 'office*'
t_reject validate_profile_name 'office?'
t_reject validate_profile_name 'office~'
t_reject validate_profile_name '-office'
t_reject validate_profile_name '_office'
t_reject validate_profile_name '.office'
t_reject validate_profile_name 'office.json'
t_reject validate_profile_name ''
t_reject validate_profile_name 'abcdefghijklmnopq'   # 17자
t_reject validate_profile_name '사무실'
t_reject validate_profile_name 'office>out'
t_reject validate_profile_name 'office<in'
t_reject validate_profile_name '*'

t_section "권한 비트 판정 (다른 사용자가 쓸 수 있는가)"

# 그룹 쓰기도 '다른 사람이 쓸 수 있는' 것이다. group-write 를 통과시키면
# admin 그룹의 아무 프로세스나 root 의 networksetup 인자를 갈아치울 수 있다.
for unsafe in 0002 0020 0022 0664 0775 0777 0666 2775; do
    if mode_allows_foreign_write "$unsafe"; then t_pass; else t_fail "권한 $unsafe 를 안전하다고 판정했습니다"; fi
done
for safe in 0644 0755 0400 0600 0555 0444 4755; do
    if mode_allows_foreign_write "$safe"; then t_fail "권한 $safe 를 위험하다고 판정했습니다"; else t_pass; fi
done
# 판독 실패는 안전으로 넘기지 않는다 (fail closed). stat 가 실패하면 여기로 온다.
for broken in '' 'abc' '8' '09' '  ' '0644 '; do
    if mode_allows_foreign_write "$broken"; then t_pass; else t_fail "판독할 수 없는 권한값 '$broken' 을 통과시켰습니다"; fi
done

t_section "IPv4 주소 형식"
for address in 192.0.2.1 198.51.100.254 203.0.113.7 203.0.113.254 0.0.0.0 255.255.255.255; do
    t_accept is_ipv4 "$address"
done
t_reject is_ipv4 '192.0.2'
t_reject is_ipv4 '192.0.2.1.5'
t_reject is_ipv4 '192.0.2.256'
t_reject is_ipv4 '192.0.2.01'      # 앞자리 0 (8진수 해석 위험)
t_reject is_ipv4 '192.0.2.-1'
t_reject is_ipv4 ' 192.0.2.1'
t_reject is_ipv4 '192.0.2.1 '
t_reject is_ipv4 '192.0.2.1;id'
t_reject is_ipv4 '192.0.2.1$(id)'
t_reject is_ipv4 '0x c0.0.2.1'
t_reject is_ipv4 ''
t_reject is_ipv4 'localhost'

t_section "서브넷 마스크"
for mask in 255.255.255.0 255.255.255.128 255.255.0.0 255.0.0.0 255.255.254.0 128.0.0.0; do
    t_accept is_netmask "$mask"
done
t_reject is_netmask '255.255.0.255'   # 1비트가 끊겼다
t_reject is_netmask '255.0.255.0'
t_reject is_netmask '0.0.0.0'
t_reject is_netmask '255.255.255.255'
t_reject is_netmask '192.0.2.1'

t_section "라우터가 서브넷 안에 있는가"
if same_subnet 192.0.2.10 255.255.255.0 192.0.2.1; then t_pass; else t_fail "같은 대역인데 다르다고 판정"; fi
if same_subnet 192.0.2.10 255.255.255.128 192.0.2.100; then t_pass; else t_fail "/25 같은 대역 판정 실패"; fi
if same_subnet 192.0.2.10 255.255.255.128 192.0.2.200; then t_fail "/25 다른 대역인데 같다고 판정"; else t_pass; fi
if same_subnet 192.0.2.10 255.255.255.0 198.51.100.1; then t_fail "다른 대역인데 같다고 판정"; else t_pass; fi
if same_subnet 192.0.2.10 255.255.255.0 192.0.3.1; then t_fail "인접 대역인데 같다고 판정"; else t_pass; fi

t_equals "4294967040" "$(ip_to_int 255.255.255.0)" "ip_to_int 255.255.255.0"
t_equals "3221225985" "$(ip_to_int 192.0.2.1)" "ip_to_int 192.0.2.1"

# --- 설정 파일 읽기 ----------------------------------------------------------

t_section "설정 파일 읽기"
WORK_DIR=$(mktemp -d -t exem-wifi-switcher-tests)
cleanup() { rm -rf "$WORK_DIR"; }
trap cleanup EXIT

FIXTURE="$WORK_DIR/config.json"
cat > "$FIXTURE" <<'JSON'
{
  "version": 1,
  "service": "Wi-Fi",
  "defaultProfile": "auto",
  "profiles": [
    { "name": "office", "mode": "manual", "ip": "192.0.2.10", "subnet": "255.255.255.0",
      "router": "192.0.2.1", "dns": ["192.0.2.53", "198.51.100.53"], "ssids": ["EXAMPLE-AP"] },
    { "name": "auto", "mode": "dhcp", "dns": [], "ssids": [] }
  ]
}
JSON

t_equals "Wi-Fi" "$(config_get "$FIXTURE" service)" "service 읽기"
t_equals "0" "$(find_profile_index "$FIXTURE" office)" "office 인덱스"
t_equals "1" "$(find_profile_index "$FIXTURE" auto)" "auto 인덱스"
if find_profile_index "$FIXTURE" nosuch >/dev/null; then
    t_fail "없는 프로필을 찾았다고 보고했습니다"
else
    t_pass
fi
# 이름 비교는 글롭이 아니라 문자 그대로여야 한다.
if find_profile_index "$FIXTURE" '*' >/dev/null; then
    t_fail "'*' 가 프로필 이름과 매칭됐습니다 (글롭 비교 사고)"
else
    t_pass
fi
t_equals "192.0.2.10" "$(config_get "$FIXTURE" profiles.0.ip)" "ip 읽기"
t_equals "2" "$(config_get "$FIXTURE" profiles.0.dns)" "dns 개수"
t_equals "192.0.2.53" "$(config_get "$FIXTURE" profiles.0.dns.0)" "dns 첫 항목"
if config_get "$FIXTURE" profiles.1.ip >/dev/null 2>&1; then
    t_fail "DHCP 프로필에 없는 ip 를 읽어냈습니다"
else
    t_pass
fi

# --- 설정 파일 사본 뜨기 (TOCTOU 차단 경로) -------------------------------------

t_section "설정 파일을 한 번만 열어 사본을 만든다"

# 이 경로는 평소 root 로만 지나간다. 하지만 여기서 잘못되면 전환이 통째로 멈추므로
# 시스템에 이미 있는 root 소유 파일(/etc/hosts — root:wheel 0644)로 실제 동작을 확인한다.
# 내용이 JSON 이 아니어도 상관없다. 이 함수는 파싱하지 않는다.
if [ -f /etc/hosts ]; then
    ( open_config_snapshot /etc/hosts >/dev/null 2>&1 )
    t_equals "0" "$?" "root 소유 파일로 사본 만들기"

    # 사본이 원본과 같은 내용이어야 한다.
    open_config_snapshot /etc/hosts >/dev/null 2>&1
    if cmp -s /etc/hosts "$CONFIG_SNAPSHOT"; then t_pass; else t_fail "사본 내용이 원본과 다릅니다"; fi
    # 사본은 만든 사람만 볼 수 있어야 한다.
    t_equals "700" "$(stat -f '%OLp' "$CONFIG_SNAPSHOT_DIR")" "사본 디렉터리 권한"
    remove_config_snapshot
    # open_config_snapshot 이 EXIT trap 을 자기 것으로 바꿔 놓는다 (apply 안에서는 그게 맞다).
    # 테스트 쪽 정리를 잃지 않도록 여기서 되돌린다.
    trap cleanup EXIT
else
    printf '  건너뜀: /etc/hosts 가 없습니다\n'
fi

# root 소유가 아닌 파일은 거부해야 한다. 여기를 통과하면 설정 잠금이 통째로 무의미해진다.
printf '{}' > "$WORK_DIR/user-owned.json"
( open_config_snapshot "$WORK_DIR/user-owned.json" >/dev/null 2>&1 )
t_equals "4" "$?" "사용자 소유 파일 거부"

# 디렉터리·심링크 같은 일반 파일 아닌 것도 거부한다.
( open_config_snapshot "$WORK_DIR" >/dev/null 2>&1 )
t_equals "4" "$?" "디렉터리 거부"

# 사본을 만든 뒤에는 원본 경로를 다시 열지 않는다 (검사한 것과 읽는 것이 같아야 한다).
if grep -qE 'config_get "\$CONFIG_FILE"|find_profile_index "\$CONFIG_FILE"|load_profile_values "\$CONFIG_FILE"' "$APPLY"; then
    t_fail "사본을 두고도 원본 경로를 다시 파싱합니다 (TOCTOU 창이 남습니다)"
else
    t_pass
fi

# --- 설정 값 재검증 ----------------------------------------------------------

t_section "설정에서 읽은 값 재검증"

# 프로필 하나짜리 설정 파일을 만든다.
write_profile_fixture() {
    cat > "$WORK_DIR/one.json"
}

# load_profile_values 를 서브셸에서 돌린다. die 가 exit 하므로 종료 코드로 판정한다.
expect_profile_status() {
    local expected="$1" label="$2"
    ( load_profile_values "$WORK_DIR/one.json" 0 test >/dev/null 2>&1 )
    t_equals "$expected" "$?" "$label"
}

write_profile_fixture <<'JSON'
{ "profiles": [ { "name": "test", "mode": "manual", "ip": "192.0.2.10",
  "subnet": "255.255.255.0", "router": "192.0.2.1", "dns": ["192.0.2.53"] } ] }
JSON
expect_profile_status 0 "정상 고정 IP 프로필"
load_profile_values "$WORK_DIR/one.json" 0 test >/dev/null 2>&1
t_equals "manual" "$PROFILE_MODE" "읽어낸 mode"
t_equals "192.0.2.10" "$PROFILE_IP" "읽어낸 ip"
t_equals "255.255.255.0" "$PROFILE_SUBNET" "읽어낸 subnet"
t_equals "192.0.2.1" "$PROFILE_ROUTER" "읽어낸 router"
t_equals "1" "${#PROFILE_DNS[@]}" "읽어낸 DNS 개수"

write_profile_fixture <<'JSON'
{ "profiles": [ { "name": "test", "mode": "dhcp", "dns": [] } ] }
JSON
expect_profile_status 0 "정상 DHCP 프로필"

# 고정 IP 프로필에 DNS 가 없으면 적용해서는 안 된다.
# 적용하면 networksetup 이 resolver 를 0개로 만들고 이름 해석이 통째로 끊긴다.
# 여기서 멈추면 네트워크는 손대기 전 그대로 남는다 (fail closed).
write_profile_fixture <<'JSON'
{ "profiles": [ { "name": "test", "mode": "manual", "ip": "192.0.2.10",
  "subnet": "255.255.255.0", "router": "192.0.2.1", "dns": [] } ] }
JSON
expect_profile_status 4 "고정 IP 인데 DNS 가 비어 있음"

write_profile_fixture <<'JSON'
{ "profiles": [ { "name": "test", "mode": "manual", "ip": "192.0.2.10",
  "subnet": "255.255.255.0", "router": "192.0.2.1" } ] }
JSON
expect_profile_status 4 "고정 IP 인데 dns 항목 자체가 없음"

write_profile_fixture <<'JSON'
{ "profiles": [ { "name": "test", "mode": "manual", "ip": "192.0.2.300",
  "subnet": "255.255.255.0", "router": "192.0.2.1" } ] }
JSON
expect_profile_status 4 "형식이 틀린 ip"

write_profile_fixture <<'JSON'
{ "profiles": [ { "name": "test", "mode": "manual", "ip": "192.0.2.10",
  "subnet": "255.255.0.255", "router": "192.0.2.1" } ] }
JSON
expect_profile_status 4 "연속이 아닌 서브넷 마스크"

write_profile_fixture <<'JSON'
{ "profiles": [ { "name": "test", "mode": "manual", "ip": "192.0.2.10",
  "subnet": "255.255.255.0", "router": "198.51.100.1" } ] }
JSON
expect_profile_status 4 "대역 밖 라우터"

write_profile_fixture <<'JSON'
{ "profiles": [ { "name": "test", "mode": "manual", "ip": "192.0.2.10",
  "subnet": "255.255.255.0" } ] }
JSON
expect_profile_status 4 "router 항목 누락"

write_profile_fixture <<'JSON'
{ "profiles": [ { "name": "test", "mode": "manual", "ip": "192.0.2.10; echo hacked",
  "subnet": "255.255.255.0", "router": "192.0.2.1" } ] }
JSON
expect_profile_status 4 "ip 에 셸 메타문자"

write_profile_fixture <<'JSON'
{ "profiles": [ { "name": "test", "mode": "dhcp", "ip": "192.0.2.10" } ] }
JSON
expect_profile_status 4 "DHCP 인데 ip 가 남아 있음"

write_profile_fixture <<'JSON'
{ "profiles": [ { "name": "test", "mode": "static" } ] }
JSON
expect_profile_status 4 "알 수 없는 mode"

write_profile_fixture <<'JSON'
{ "profiles": [ { "name": "test", "mode": "dhcp", "dns": ["192.0.2.53", "not-an-ip"] } ] }
JSON
expect_profile_status 4 "형식이 틀린 DNS 주소"

write_profile_fixture <<'JSON'
{ "profiles": [ { "name": "test", "mode": "dhcp", "dns":
  ["192.0.2.1","192.0.2.2","192.0.2.3","192.0.2.4","192.0.2.5",
   "192.0.2.6","192.0.2.7","192.0.2.8","192.0.2.9"] } ] }
JSON
expect_profile_status 4 "DNS 서버 9개 (상한 초과)"

# --- 적용 순서와 되돌리기 ------------------------------------------------------

t_section "부분 적용 줄이기 (DNS 먼저 · 실패하면 되돌리기)"

# DNS 를 IPv4 보다 먼저 걸어야 한다.
#
# 반대로 하면 -setmanual 성공 → -setdnsservers 실패 때 'IP 는 새 값, DNS 는 옛 값' 이 남는다.
# 그 상태는 IP 만 보면 목표와 같아 보여서 다시 부를 계기가 없고, DNS 는 영영 고쳐지지 않는다.
main_line=$(grep -n '^main() {' "$APPLY" | cut -d: -f1)
dns_line=$(awk -v start="$main_line" 'NR > start && /networksetup -setdnsservers/ { print NR; exit }' "$APPLY")
ipv4_line=$(awk -v start="$main_line" 'NR > start && /networksetup -setmanual|networksetup -setdhcp/ { print NR; exit }' "$APPLY")
if [ -n "$dns_line" ] && [ -n "$ipv4_line" ] && [ "$dns_line" -lt "$ipv4_line" ]; then
    t_pass
else
    t_fail "apply 가 IPv4 를 DNS 보다 먼저 적용합니다 (부분 적용이 남습니다)"
fi

# 현재 DNS 읽기 — 되돌리기의 근거다. networksetup 을 셸 함수로 대신해 실제 동작을 확인한다.
(
    networksetup() { printf '192.0.2.53\n198.51.100.53\n'; }
    read_current_dns "Wi-Fi" || exit 1
    [ "${#PREVIOUS_DNS[@]}" -eq 2 ] || exit 1
    [ "${PREVIOUS_DNS[0]}" = "192.0.2.53" ] || exit 1
    [ "${PREVIOUS_DNS[1]}" = "198.51.100.53" ] || exit 1
) >/dev/null 2>&1
t_equals "0" "$?" "현재 DNS 목록 읽기"

# "설정된 서버가 없음" 은 빈 목록이지 읽기 실패가 아니다.
(
    networksetup() { printf "There aren't any DNS Servers set on Wi-Fi.\n"; }
    read_current_dns "Wi-Fi" || exit 1
    [ "${#PREVIOUS_DNS[@]}" -eq 0 ] || exit 1
) >/dev/null 2>&1
t_equals "0" "$?" "수동 지정이 없는 상태 읽기"

# 조회 자체가 실패하면 되돌릴 근거가 없다는 사실을 그대로 알려야 한다.
(
    networksetup() { return 4; }
    read_current_dns "Wi-Fi"
) >/dev/null 2>&1
t_equals "1" "$?" "DNS 조회 실패를 삼키지 않는다"

# 되돌리기: 읽어 둔 값이 있으면 그 값으로, 없으면 그 사실을 알린다.
# **어느 쪽이든 0 을 돌려준다** — 되돌리기 결과가 원래의 실패 메시지를 덮어써서는 안 된다.
restore_note=$(
    networksetup() { printf '%s\n' "$*" > "$WORK_DIR/restore-args"; }
    PREVIOUS_DNS=(192.0.2.53)
    PREVIOUS_DNS_READ=1
    restore_dns "Wi-Fi"
)
t_equals "0" "$?" "되돌리기 종료 코드"
t_equals "-setdnsservers Wi-Fi 192.0.2.53" "$(cat "$WORK_DIR/restore-args" 2>/dev/null)" "되돌린 DNS 인자"
case "$restore_note" in
    *되돌렸습니다*) t_pass ;;
    *) t_fail "되돌리기 결과를 알리지 않습니다 — 실제 알림: '$restore_note'" ;;
esac

restore_note=$(
    networksetup() { printf '%s\n' "$*" > "$WORK_DIR/restore-args"; }
    PREVIOUS_DNS=()
    PREVIOUS_DNS_READ=1
    restore_dns "Wi-Fi"
)
t_equals "-setdnsservers Wi-Fi Empty" "$(cat "$WORK_DIR/restore-args" 2>/dev/null)" "수동 지정이 없던 상태로 되돌리기"

rm -f "$WORK_DIR/restore-args"
restore_note=$(
    networksetup() { printf '%s\n' "$*" > "$WORK_DIR/restore-args"; }
    PREVIOUS_DNS=()
    PREVIOUS_DNS_READ=0
    restore_dns "Wi-Fi"
)
t_equals "0" "$?" "읽어 둔 값이 없을 때의 종료 코드"
if [ -e "$WORK_DIR/restore-args" ]; then
    t_fail "이전 값을 모르는 채로 DNS 를 건드렸습니다"
else
    t_pass
fi
case "$restore_note" in
    *되돌리지*) t_pass ;;
    *) t_fail "되돌리지 못했다는 사실을 알리지 않습니다 — 실제 알림: '$restore_note'" ;;
esac

# IPv4 적용 실패 경로에서 실제로 되돌리기를 부르는가.
if [ "$(grep -c 'restore_dns "\$service"' "$APPLY")" -ge 2 ]; then
    t_pass
else
    t_fail "IPv4 적용이 실패해도 DNS 를 되돌리지 않습니다 (절반만 적용된 구성이 남습니다)"
fi

# --- 하위 프로세스 동작 -------------------------------------------------------

t_section "apply 실행 (권한 없이)"

# 악의적 인자는 exit 2 (인자 검증) 로 막혀야 한다 — 설정을 읽기도 전이다.
MARKER="$WORK_DIR/injection-marker"
for bad in 'office; touch '"$MARKER" '$(touch '"$MARKER"')' '`touch '"$MARKER"'`' '../../etc/passwd' 'office name' '' '*'; do
    "$APPLY" "$bad" >/dev/null 2>&1
    status=$?
    t_equals "2" "$status" "악의적 인자 '$bad' 의 종료 코드"
done
if [ -e "$MARKER" ]; then
    t_fail "인젝션 페이로드가 실행됐습니다 ($MARKER 가 생성됨)"
else
    t_pass
fi

# 인자 개수가 다르면 거부한다.
"$APPLY" >/dev/null 2>&1; t_equals "2" "$?" "인자 없음"
"$APPLY" office extra >/dev/null 2>&1; t_equals "2" "$?" "인자 2개"

# 형식이 맞는 이름은 인자 검증을 통과하고 root 검사에서 멈춘다 (exit 3).
# 이 순서가 지켜져야 "설정을 읽거나 네트워크를 건드리기 전에 권한을 확인한다" 가 성립한다.
if [ "$(id -u)" -ne 0 ]; then
    "$APPLY" office >/dev/null 2>&1
    t_equals "3" "$?" "root 아닌 상태에서 유효한 이름"
else
    printf '  건너뜀: root 로 실행 중이라 권한 검사 테스트를 생략합니다\n'
fi

# --help 는 아무것도 바꾸지 않고 종료한다.
"$APPLY" --help >/dev/null 2>&1; t_equals "0" "$?" "--help"

# --- 설치 스크립트 (dry-run) --------------------------------------------------

t_section "install.sh --dry-run"
install_output=$("$REPO_ROOT/scripts/install.sh" --dry-run 2>&1)
install_status=$?
t_equals "0" "$install_status" "install.sh --dry-run 종료 코드"

# dry-run 안에서 실제 visudo 문법 검증이 돌아야 한다 (sudoers 를 잘못 놓는 사고 방지).
case "$install_output" in
    *"visudo -c 문법 검증 통과"*) t_pass ;;
    *) t_fail "install.sh 가 visudo 문법 검증을 통과했다고 보고하지 않았습니다" ;;
esac
# sudo 는 dry-run 에서 실행되지 않아야 한다.
case "$install_output" in
    *"[dry-run] sudo /usr/bin/install"*) t_pass ;;
    *) t_fail "install.sh dry-run 이 설치 명령을 보여주지 않았습니다" ;;
esac
# 와일드카드로 임의 명령을 여는 규칙이 들어가면 안 된다.
case "$install_output" in
    *"apply *"*) t_fail "sudoers 규칙에 와일드카드 인자가 들어 있습니다" ;;
    *) t_pass ;;
esac

# 설정 파일은 root:wheel 0644 여야 한다 — 사용자 권한으로 고칠 수 있으면
# 무암호 apply 를 통해 root 의 networksetup 인자가 통째로 조작된다.
case "$install_output" in
    *"install -o root -g wheel -m 0644"*) t_pass ;;
    *) t_fail "설정 파일을 root:wheel 0644 로 놓지 않습니다" ;;
esac
case "$install_output" in
    *"-g admin"*) t_fail "admin 그룹에 쓰기를 여는 설치 명령이 남아 있습니다" ;;
    *) t_pass ;;
esac
case "$install_output" in
    *0664*|*0775*) t_fail "그룹 쓰기를 여는 권한(0664·0775)이 설치 명령에 남아 있습니다" ;;
    *) t_pass ;;
esac

# save-config 는 설치하되 **sudoers 에는 넣지 않는다.**
case "$install_output" in
    *"save-config"*) t_pass ;;
    *) t_fail "save-config 를 설치하지 않습니다" ;;
esac
sudoers_block=$(printf '%s\n' "$install_output" | sed -n '/^Cmnd_Alias/,/NOPASSWD/p')
case "$sudoers_block" in
    *"save-config"*) t_fail "sudoers 규칙이 save-config 를 무암호로 열고 있습니다 (설정 잠금이 무의미해집니다)" ;;
    *) t_pass ;;
esac

# 여러 계정이 쓰는 Mac 에서 재설치가 이전 사용자를 조용히 끊는다는 사실을 고지해야 한다.
case "$install_output" in
    *"한 사람만 허용"*) t_pass ;;
    *) t_fail "sudo 규칙이 단일 사용자용이라는 고지가 없습니다" ;;
esac

# /usr/local/etc 가 없는 Mac 에서 이 도구와 무관한 디렉터리가 엉뚱한 권한으로 생기면 안 된다.
case "$install_output" in
    *"/usr/local, /usr/local/libexec, /usr/local/etc"*) t_pass ;;
    *) t_fail "상위 디렉터리를 어떤 소유·권한으로 만드는지 고지하지 않습니다" ;;
esac

# Homebrew 가 /usr/local 을 소유할 때 chown 을 처방하면 Homebrew 가 통째로 망가진다.
if grep -q "절대로 sudo chown root:wheel /usr/local 을 실행하지 마세요" "$REPO_ROOT/scripts/install.sh"; then
    t_pass
else
    t_fail "Homebrew 환경에서 chown 을 처방하지 말라는 안내가 없습니다"
fi
if grep -q "homebrew_owns_usr_local" "$REPO_ROOT/scripts/install.sh"; then
    t_pass
else
    t_fail "Homebrew 감지 경로가 없습니다"
fi

t_section "install.sh — 앱에서 부르는 길"

# 앱은 관리자 인증을 거쳐 root 로 이 스크립트를 부른다. 그 자리에서는 규칙을 적을 계정을
# 알 수 없으므로 --user 로 받는다. 그 인자가 곧 sudoers 에 들어가므로 검사가 헐거우면 안 된다.
"$REPO_ROOT/scripts/install.sh" --user >/dev/null 2>&1
t_equals "1" "$?" "--user 뒤에 값이 없음"
"$REPO_ROOT/scripts/install.sh" --dry-run --user 'bad name' >/dev/null 2>&1
t_equals "1" "$?" "계정 이름에 공백"
"$REPO_ROOT/scripts/install.sh" --dry-run --user 'x;id' >/dev/null 2>&1
t_equals "1" "$?" "계정 이름에 셸 메타문자"
"$REPO_ROOT/scripts/install.sh" --dry-run --user 'no-such-user-exem-test' >/dev/null 2>&1
t_equals "1" "$?" "없는 계정"
# 시스템 계정 앞으로 무암호 규칙을 적지 않는다.
"$REPO_ROOT/scripts/install.sh" --dry-run --user root >/dev/null 2>&1
t_equals "1" "$?" "로그인 계정이 아닌 대상"

# --yes 는 확인 입력을 건너뛴다. dry-run 과 함께 써도 아무것도 바꾸지 않는다.
"$REPO_ROOT/scripts/install.sh" --dry-run --yes >/dev/null 2>&1
t_equals "0" "$?" "--yes 와 --dry-run"

t_section "install.sh — 번들 안에서도 같은 코드가 돈다"

# 앱 번들은 레포 구조가 아니다. 설치할 원본을 **스크립트 자기 위치** 기준으로 찾지 못하면
# 앱에서 누른 [설치] 는 파일을 못 찾고 멈춘다. 레포 없이 같은 배치를 만들어 확인한다.
BUNDLE_LIKE="$WORK_DIR/Bundle.app/Contents/Resources/scripts"
mkdir -p "$BUNDLE_LIKE"
for file in install.sh uninstall.sh apply save-config; do
    install -m 0755 "$REPO_ROOT/scripts/$file" "$BUNDLE_LIKE/$file"
done
install -m 0644 "$REPO_ROOT/config.example.json" "$BUNDLE_LIKE/config.example.json"

bundle_output=$("$BUNDLE_LIKE/install.sh" --dry-run --user "$(id -un)" 2>&1)
t_equals "0" "$?" "번들 배치에서 install.sh --dry-run"
case "$bundle_output" in
    *"$BUNDLE_LIKE"*) t_pass ;;
    *) t_fail "번들 안 스크립트가 자기 자리를 설치 원본으로 쓰지 않습니다" ;;
esac
case "$bundle_output" in
    *"visudo -c 문법 검증 통과"*) t_pass ;;
    *) t_fail "번들 배치에서 sudoers 검증까지 가지 못했습니다" ;;
esac

# 앱 번들은 사용자가 쓸 수 있는 자리에 있다. 최소한 **다른 사용자**가 갈아 끼울 수 있는
# 상태라면 root 로 실행할 내용으로 받아들이지 않는다.
chmod 0775 "$BUNDLE_LIKE/apply"
"$BUNDLE_LIKE/install.sh" --dry-run --user "$(id -un)" >/dev/null 2>&1
t_equals "1" "$?" "그룹 쓰기가 열린 원본 거부"
chmod 0755 "$BUNDLE_LIKE/apply"

# uninstall.sh 도 같은 길로 들어온다.
uninstall_bundle_output=$("$BUNDLE_LIKE/uninstall.sh" --dry-run --user "$(id -un)" --skip-running-app 2>&1)
t_equals "0" "$?" "번들 배치에서 uninstall.sh --dry-run"
case "$uninstall_bundle_output" in
    *"종료하지 않습니다"*) t_pass ;;
    *) t_fail "--skip-running-app 이 앱을 종료하지 않는다고 알리지 않습니다" ;;
esac
"$REPO_ROOT/scripts/uninstall.sh" --dry-run --user 'bad name' >/dev/null 2>&1
t_equals "1" "$?" "uninstall 계정 이름 검사"

# 사용자 쪽 흔적(로그인 항목·앱 설정값)은 root 의 홈이 아니라 대상 계정의 홈에서 찾아야 한다.
if grep -q 'launchctl bootout "gui/\$TARGET_UID/' "$REPO_ROOT/scripts/uninstall.sh"; then
    t_pass
else
    t_fail "uninstall 이 대상 계정의 GUI 도메인을 쓰지 않습니다 (root 로 실행하면 남의 도메인을 봅니다)"
fi
if grep -q 'run_as_target_user tccutil reset Location' "$REPO_ROOT/scripts/uninstall.sh"; then
    t_pass
else
    t_fail "uninstall 이 위치 권한 기록을 대상 계정으로 지우지 않습니다"
fi

t_section "save-config"

# 저장 경로도 root 로 도는 스크립트다. apply 와 같은 원칙을 지켜야 한다.
if bash -n "$REPO_ROOT/scripts/save-config" 2>/dev/null; then t_pass; else t_fail "save-config 문법 오류"; fi
if grep -qE '(^|[^[:alnum:]_])eval[[:space:]]' "$REPO_ROOT/scripts/save-config"; then
    t_fail "save-config 에 eval 이 있습니다"
else
    t_pass
fi
# sudoers 에 넣지 말라는 경고가 스크립트 안에 남아 있어야 한다 (읽는 사람이 판단할 근거).
if grep -q "NOPASSWD 목록에 넣지 마라" "$REPO_ROOT/scripts/save-config"; then t_pass; else
    t_fail "save-config 에 sudoers 금지 경고가 없습니다"
fi

# root 가 아니면 아무것도 하지 않는다.
"$REPO_ROOT/scripts/save-config" /private/var/tmp/nonexistent-exem-config.json >/dev/null 2>&1
t_equals "3" "$?" "root 아닌 상태에서의 종료 코드"
"$REPO_ROOT/scripts/save-config" >/dev/null 2>&1; t_equals "2" "$?" "인자 없음"
"$REPO_ROOT/scripts/save-config" a b >/dev/null 2>&1; t_equals "2" "$?" "인자 2개"
"$REPO_ROOT/scripts/save-config" relative/path.json >/dev/null 2>&1; t_equals "2" "$?" "상대 경로"
"$REPO_ROOT/scripts/save-config" --help >/dev/null 2>&1; t_equals "0" "$?" "--help"

# 내용 검사는 root 없이도 직접 부를 수 있다.
. "$REPO_ROOT/scripts/save-config"
cat > "$WORK_DIR/good.json" <<'JSON'
{ "version": 1, "service": "Wi-Fi", "defaultProfile": "auto",
  "profiles": [ { "name": "auto", "mode": "dhcp" } ] }
JSON
( assert_looks_like_config "$WORK_DIR/good.json" >/dev/null 2>&1 )
t_equals "0" "$?" "정상 설정 모양"

printf 'not json at all' > "$WORK_DIR/bad.json"
( assert_looks_like_config "$WORK_DIR/bad.json" >/dev/null 2>&1 )
t_equals "4" "$?" "JSON 이 아닌 내용"

cat > "$WORK_DIR/empty-profiles.json" <<'JSON'
{ "version": 1, "service": "Wi-Fi", "defaultProfile": "auto", "profiles": [] }
JSON
( assert_looks_like_config "$WORK_DIR/empty-profiles.json" >/dev/null 2>&1 )
t_equals "4" "$?" "프로필이 하나도 없는 설정"

cat > "$WORK_DIR/no-service.json" <<'JSON'
{ "version": 1, "defaultProfile": "auto", "profiles": [ { "name": "auto", "mode": "dhcp" } ] }
JSON
( assert_looks_like_config "$WORK_DIR/no-service.json" >/dev/null 2>&1 )
t_equals "4" "$?" "service 가 없는 설정"

t_section "uninstall.sh --dry-run"
uninstall_output=$("$REPO_ROOT/scripts/uninstall.sh" --dry-run 2>&1)
t_equals "0" "$?" "uninstall.sh --dry-run 종료 코드"

# 설치한 것을 하나라도 빠뜨리면 "다 지웠다" 가 거짓말이 된다.
case "$uninstall_output" in
    *"save-config"*) t_pass ;;
    *) t_fail "uninstall 이 save-config 를 언급하지 않습니다" ;;
esac
case "$uninstall_output" in
    *"tccutil reset Location"*) t_pass ;;
    *) t_fail "uninstall 이 위치 권한(TCC) 기록을 정리하지 않습니다" ;;
esac
# 앱 설정값 경로는 HOME 에서 만들어진다. HOME 이 없는 환경(테스트 러너)에서는 출력에 나오지
# 않으므로 스크립트 자체를 본다. cfprefsd 캐시 때문에 파일만 지워서는 되살아난다 — defaults 도 함께 봐야 한다.
if grep -q 'Library/Preferences/\$BUNDLE_ID.plist' "$REPO_ROOT/scripts/uninstall.sh"; then t_pass; else
    t_fail "uninstall 이 앱 설정값(plist)을 정리하지 않습니다"
fi
if grep -q 'defaults delete' "$REPO_ROOT/scripts/uninstall.sh"; then t_pass; else
    t_fail "uninstall 이 defaults 캐시를 지우지 않습니다 (파일만 지우면 되살아납니다)"
fi
case "$uninstall_output" in
    *"앱 번들"*) t_pass ;;
    *) t_fail "uninstall 이 앱 번들은 지우지 않는다는 사실을 알리지 않습니다" ;;
esac
# "남은 항목이 없습니다" 처럼 사실과 다른 마무리 문구를 쓰지 않는다.
if grep -q "남은 항목이 없습니다" "$REPO_ROOT/scripts/uninstall.sh"; then
    t_fail "uninstall 이 사실과 다른 마무리 문구를 씁니다 (앱 번들·알림 권한이 남는다)"
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
