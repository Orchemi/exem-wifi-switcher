#!/usr/bin/env bash
#
# 아이콘 SVG → PNG 내보내기 + 육안 확인용 대조 시트 생성.
#
# SVG 가 원본이다. PNG 는 전부 이 스크립트가 다시 만들 수 있는 파생물이므로
# PNG 를 직접 손대지 말고 SVG 를 고친 뒤 이 스크립트를 다시 돌려라.
# SVG 자체도 손으로 쓰지 않는다 — make-icons.py 가 기하를 계산해서 만든다.
#
#   python3 make-icons.py && ./export.sh
#
# 사용법:  ./export.sh          (Resources/icons 안에서, 또는 어디서든)
# 의존성:  ImageMagick 7 (`brew install imagemagick`)
#          (make-icons.py 쪽은 python3 + shapely — 형태를 바꿀 때만 필요하다)

set -euo pipefail

# 스크립트 자신의 위치를 기준으로 동작한다 — 레포 경로에 의존하지 않는다.
cd "$(dirname "${BASH_SOURCE[0]}")"

command -v magick >/dev/null || {
  echo "오류: ImageMagick(magick) 이 필요하다. brew install imagemagick" >&2
  exit 1
}

STATES=(manual dhcp error)
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# ---------------------------------------------------------------------------
# 1) SVG → PNG (@1x 16 / @2x 32)
#
# macOS 는 메뉴바 아이콘을 1x·2x 두 배율로만 고른다. @3x 는 만들지 않는다.
#
# 함정: ImageMagick 내장 SVG 렌더러는 SVG 사용자 단위를 96dpi 로 해석한다.
#       -density 72 로 주면 16pt 짜리가 12px 로 래스터화되고, 이후 -resize 로
#       16px 까지 억지로 늘리면서 뭉갠다. 그래서 density = 목표px * 6 이다
#       (16px→96, 32px→192). -resize 는 쓰지 않는다.
# ---------------------------------------------------------------------------
#       아이콘은 정사각이 아니다 — 50x36(@2x) / 25x18(@1x) 이다. 메뉴바가 강제하는
#       것은 높이뿐이라 가로로 넓혀 Wi-Fi 를 키웠다(README 참조).
#
#       세로 36 = pointSize 18pt 의 @2x 픽셀 수다. 이 둘이 어긋나면 macOS 가
#       업스케일해서 흐려진다 — StatusIcons.swift 의 pointSize 를 바꾸면 여기도
#       같이 맞춰야 한다.
#
#       density 는 배율 그 자체다. SVG 는 pt 크기(25x18)로 적혀 있고 IM 은 이를
#       96dpi 기준으로 읽으므로, 96 이 @1x, 192 가 @2x 다.
echo "▶ PNG 내보내기"
for name in "${STATES[@]}"; do
  for spec in "96:25x18:" "192:50x36:@2x"; do
    density="${spec%%:*}"
    rest="${spec#*:}"
    want="${rest%%:*}"
    suffix="${rest##*:}"
    out="menubar/${name}${suffix}.png"
    magick -background none -density "$density" "menubar/${name}.svg" \
      -define png:color-type=6 "PNG32:${out}"

    got="$(magick identify -format '%wx%h' "$out")"
    if [[ "$got" != "$want" ]]; then
      echo "오류: ${out} 이 ${got} 로 나왔다 (기대: ${want})" >&2
      exit 1
    fi
    printf '  %-18s %s\n' "$out" "$got"
  done
done

# ---------------------------------------------------------------------------
# 2) 대조 시트 — 세 상태가 구분되는지 눈으로 확인하기 위한 것.
#
#    주 기준은 **32px(@2x)** 다. 메뉴바 아이콘은 16pt 이고 Retina 에서는
#    @2x 로 렌더되므로 실사용의 대부분이 32px 다. 16px(@1x) 은 외장 비레티나
#    모니터용 — 배지가 무엇인지까지는 아니어도 셋이 서로 구분은 돼야 한다.
#
#    각 칸은 원본을 정수배 최근접이웃 확대라 실제 픽셀이 그대로 보인다.
#    윗줄이 라이트 메뉴바(검정 심볼), 아랫줄이 다크 메뉴바(흰 심볼)다.
# ---------------------------------------------------------------------------
echo "▶ 대조 시트 생성"

# 템플릿은 검정+알파다. 다크 배경용으로 RGB 만 반전해 흰 심볼을 만든다.
for name in "${STATES[@]}"; do
  for suffix in "" "@2x"; do
    magick "menubar/${name}${suffix}.png" -channel RGB -negate \
      "$TMP/${name}${suffix}-white.png"
  done
done

# 32px 은 7배, 16px 은 14배 — 같은 224px 로 맞춰 나란히 비교할 수 있게 한다.
zoom_row() {   # $1=suffix  $2=배율  $3=mode  $4=출력
  local suffix="$1" zoom="$2" mode="$3" out="$4" bg src cells=()
  if [[ "$mode" == light ]]; then bg='#f5f5f7'; else bg='#1c1c1e'; fi
  for name in "${STATES[@]}"; do
    if [[ "$mode" == light ]]; then src="menubar/${name}${suffix}.png"
    else src="$TMP/${name}${suffix}-white.png"; fi
    magick "$src" -filter point -resize "$((zoom * 100))%" \
      -background "$bg" -flatten "$TMP/cell-${name}${suffix}-${mode}.png"
    cells+=("$TMP/cell-${name}${suffix}-${mode}.png")
  done
  magick "${cells[@]}" -background '#808080' -splice 6x0 +append "$out"
}

zoom_row "@2x" 7 light "$TMP/r32l.png"
zoom_row "@2x" 7 dark  "$TMP/r32d.png"
zoom_row ""   14 light "$TMP/r16l.png"
zoom_row ""   14 dark  "$TMP/r16d.png"

# 32px 묶음 / 16px 묶음 사이에는 굵은 구분선을 둔다
magick "$TMP/r32l.png" "$TMP/r32d.png" -background '#808080' -splice 0x6 -append \
  "$TMP/block32.png"
magick "$TMP/r16l.png" "$TMP/r16d.png" -background '#808080' -splice 0x6 -append \
  "$TMP/block16.png"
magick "$TMP/block32.png" "$TMP/block16.png" -background '#404040' -splice 0x14 \
  -append -bordercolor '#808080' -border 6 preview.png
echo "  preview.png  $(magick identify -format '%wx%h' preview.png)  (위 32px / 아래 16px)"

# ---------------------------------------------------------------------------
# 3) 실제 메뉴바 시뮬레이션 — 다크 바 위에 셋을 나란히.
#    윗줄이 Retina(@2x), 아랫줄이 비레티나(@1x). 최종 배율을 맞춰 같은 크기로 본다.
#
#    **이웃 아이콘을 함께 놓는다.** 우리 것만 늘어놓으면 큰지 작은지 판단할 수 없다.
#    macOS 기본 메뉴바 아이콘은 대개 세로 14~15pt 를 차지한다 — 그 크기의 중립
#    도형(원, 둥근 사각)을 양옆에 두어 우리 아이콘이 얼마나 큰지 눈으로 재게 한다.
# ---------------------------------------------------------------------------
ref() {        # $1=아이콘높이(px)  $2=출력 — 이웃 아이콘 자리표시 2종
  local ih="$1" out="$2" n=$((ih * 14 / 18))   # 14pt 상당 = 전형적 이웃 크기
  magick -size "$((n * 2))x${ih}" xc:none \
    -fill white -draw "circle $((n/2)),$((ih/2)) $((n/2)),$((ih/2 - n/2))" \
    -draw "roundrectangle $((n+2)),$((ih/2 - n/3)) $((n*2-2)),$((ih/2 + n/3)) 3,3" \
    "$out"
}

bar() {        # $1=suffix  $2=아이콘너비  $3=아이콘높이  $4=배율  $5=출력
  local suffix="$1" iw="$2" ih="$3" zoom="$4" out="$5" pad=$((${3} / 2)) args=() i=0
  local refw=$((ih * 14 / 18 * 2))
  local w=$((3 * iw + refw + 6 * pad)) h=$((ih + ih / 2))
  ref "$ih" "$TMP/ref${suffix}.png"
  args=(-size "${w}x${h}" xc:'#1c1c1e'
        "$TMP/ref${suffix}.png" -geometry "+${pad}+$((ih / 4))" -composite)
  for name in "${STATES[@]}"; do
    args+=("$TMP/${name}${suffix}-white.png"
           -geometry "+$((refw + 2 * pad + i * (iw + pad)))+$((ih / 4))" -composite)
    i=$((i + 1))
  done
  magick "${args[@]}" -filter point -resize "$((zoom * 100))%" "$out"
}

bar "@2x" 50 36 5 "$TMP/bar32.png"
bar ""    25 18 10 "$TMP/bar16.png"
magick "$TMP/bar32.png" "$TMP/bar16.png" -background '#4a4a4a' -splice 0x8 \
  -gravity center -append -bordercolor '#4a4a4a' -border 8 preview-menubar.png
echo "  preview-menubar.png  $(magick identify -format '%wx%h' preview-menubar.png)"

# ---------------------------------------------------------------------------
# 4) 앱 아이콘 — 타일 실루엣 + 좁은 2단 그라디언트 + 흰 심볼 + 옅은 그림자.
#
# 담백하게 간다: 광택(sheen)·안쪽 하이라이트·바닥 그림자 같은 겹은 쓰지 않는다.
# 색은 저채도 슬레이트 네이비 한 계열이고 명도 폭도 좁다. 그림자는 밝은 배경에서
# 타일이 묻히지 않을 만큼만 넣는다.
#
# tile.svg / symbol.svg 는 make-icons.py 가 만든다 (형태를 바꾸려면 그쪽을 고쳐라).
# ---------------------------------------------------------------------------
GRAD_TOP='#3E4F6B'
GRAD_BOTTOM='#232D40'
SHADOW='#101828'

echo "▶ 앱 아이콘 합성"
for f in app/tile.svg app/symbol.svg; do
  [[ -f "$f" ]] || { echo "오류: $f 가 없다. make-icons.py 를 먼저 돌려라." >&2; exit 1; }
done

magick -background none -density 96 app/tile.svg   PNG32:"$TMP/tile.png"
magick -background none -density 96 app/symbol.svg PNG32:"$TMP/symbol.png"

# 세로 2단 그라디언트를 타일 실루엣으로 오려낸다
magick -size 1024x1024 gradient:"${GRAD_TOP}-${GRAD_BOTTOM}" "$TMP/grad.png"
magick "$TMP/grad.png" \( "$TMP/tile.png" -alpha extract \) \
  -alpha off -compose CopyOpacity -composite PNG32:"$TMP/body.png"

# 심볼은 검정으로 그려져 있으므로 RGB 를 반전해 흰색으로 쓴다
magick "$TMP/symbol.png" -channel RGB -negate "$TMP/symbol-white.png"
magick "$TMP/body.png" "$TMP/symbol-white.png" -compose over -composite \
  PNG32:"$TMP/face.png"

# 옅은 드롭섀도 — 합성 후 캔버스가 커지므로 다시 1024 로 맞춘다
magick "$TMP/face.png" \( +clone -background "$SHADOW" -shadow 26x14+0+10 \) \
  +swap -background none -layers merge +repage \
  -gravity center -background none -extent 1024x1024 \
  PNG32:app/app-icon-1024.png
echo "  app/app-icon-1024.png  $(magick identify -format '%wx%h' app/app-icon-1024.png)"

# .icns — iconutil 이 요구하는 이름 규칙대로 iconset 을 채운다
ICONSET="$TMP/AppIcon.iconset"
mkdir -p "$ICONSET"
add() { magick app/app-icon-1024.png -resize "${1}x${1}" PNG32:"$ICONSET/$2"; }
add 16   icon_16x16.png
add 32   icon_16x16@2x.png
add 32   icon_32x32.png
add 64   icon_32x32@2x.png
add 128  icon_128x128.png
add 256  icon_128x128@2x.png
add 256  icon_256x256.png
add 512  icon_256x256@2x.png
add 512  icon_512x512.png
add 1024 icon_512x512@2x.png
iconutil --convert icns --output app/AppIcon.icns "$ICONSET"
echo "  app/AppIcon.icns  $(du -h app/AppIcon.icns | cut -f1)"

# 앱 아이콘 크기별 대조 시트
magick app/app-icon-1024.png -resize 256x256 -background '#ececee' -flatten "$TMP/a256.png"
for s in 128 64 32; do
  magick app/app-icon-1024.png -resize ${s}x${s} -background '#ececee' -flatten \
    -gravity center -extent 256x256 "$TMP/a${s}.png"
done
magick "$TMP/a256.png" "$TMP/a128.png" "$TMP/a64.png" "$TMP/a32.png" \
  -background '#ececee' -splice 10x0 +append -bordercolor '#ececee' -border 10 \
  app/preview-app.png
echo "  app/preview-app.png  $(magick identify -format '%wx%h' app/preview-app.png)"

echo "완료."
echo
echo "⚠ 메뉴바 아이콘은 25x18pt(정사각 아님)다. StatusIcons.swift 의 pointSize 는 18,"
echo "  그리고 종횡비를 지켜야 한다 — README '앱에 연결하기' 절 참조."
