#!/usr/bin/env bash
#
# 메뉴바 템플릿 아이콘 SVG → PNG 내보내기 + 육안 확인용 대조 시트 생성.
#
# SVG 가 원본이다. PNG 는 전부 이 스크립트가 다시 만들 수 있는 파생물이므로
# PNG 를 직접 손대지 말고 SVG 를 고친 뒤 이 스크립트를 다시 돌려라.
#
# 사용법:  ./export.sh          (Resources/icons 안에서, 또는 어디서든)
# 의존성:  ImageMagick 7 (`brew install imagemagick`)

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
echo "▶ PNG 내보내기"
for name in "${STATES[@]}"; do
  for pair in "16:" "32:@2x"; do
    size="${pair%%:*}"
    suffix="${pair##*:}"
    out="menubar/${name}${suffix}.png"
    magick -background none -density "$((size * 6))" "menubar/${name}.svg" \
      -define png:color-type=6 "PNG32:${out}"

    got="$(magick identify -format '%wx%h' "$out")"
    if [[ "$got" != "${size}x${size}" ]]; then
      echo "오류: ${out} 이 ${got} 로 나왔다 (기대: ${size}x${size})" >&2
      exit 1
    fi
    printf '  %-18s %s\n' "$out" "$got"
  done
done

# ---------------------------------------------------------------------------
# 2) 대조 시트 — 16px 에서 세 상태가 구분되는지 눈으로 확인하기 위한 것.
#    윗줄: 라이트 메뉴바(검정 심볼) / 아랫줄: 다크 메뉴바(흰 심볼)
#    각 칸은 16px 원본을 8배 최근접이웃 확대 — 실제 픽셀이 그대로 보인다.
# ---------------------------------------------------------------------------
echo "▶ 대조 시트 생성"
for name in "${STATES[@]}"; do
  # 템플릿은 검정+알파다. 다크 배경용으로 RGB 만 반전해 흰 심볼을 만든다.
  magick "menubar/${name}.png" -channel RGB -negate "$TMP/${name}-white.png"

  for mode in light dark; do
    if [[ "$mode" == light ]]; then bg='#f5f5f7'; src="menubar/${name}.png"
    else bg='#1c1c1e'; src="$TMP/${name}-white.png"; fi

    # 8배 확대(픽셀 보간 없이) 후 배경 합성
    magick "$src" -filter point -resize 800% \
      -background "$bg" -flatten "$TMP/${name}-${mode}-zoom.png"
  done
done

for mode in light dark; do
  magick "$TMP/manual-${mode}-zoom.png" "$TMP/dhcp-${mode}-zoom.png" \
    "$TMP/error-${mode}-zoom.png" -background '#808080' -splice 6x0 +append \
    "$TMP/row-${mode}.png"
done

magick "$TMP/row-light.png" "$TMP/row-dark.png" -background '#808080' \
  -splice 0x6 -append -bordercolor '#808080' -border 6 preview.png
echo "  preview.png  $(magick identify -format '%wx%h' preview.png)"

# 실제 메뉴바 크기 시뮬레이션 (다크 바 위 16px 나란히 → 6배 확대)
magick -size 122x24 xc:'#1c1c1e' \
  "$TMP/manual-white.png" -geometry +12+4 -composite \
  "$TMP/dhcp-white.png"   -geometry +46+4 -composite \
  "$TMP/error-white.png"  -geometry +80+4 -composite \
  -filter point -resize 600% preview-menubar.png
echo "  preview-menubar.png  $(magick identify -format '%wx%h' preview-menubar.png)"

# ---------------------------------------------------------------------------
# 3) 앱 아이콘 — 타일 실루엣 + 좁은 2단 그라디언트 + 흰 심볼 + 옅은 그림자.
#
# 담백하게 간다: 광택(sheen)·안쪽 하이라이트·바닥 그림자 같은 겹은 쓰지 않는다.
# 색은 저채도 슬레이트 네이비 한 계열이고 명도 폭도 좁다. 그림자는 밝은 배경에서
# 타일이 묻히지 않을 만큼만 넣는다.
#
# tile.svg / symbol.svg 는 make-vectors.py 가 만든다 (형태를 바꾸려면 그쪽을 고쳐라).
# ---------------------------------------------------------------------------
GRAD_TOP='#3E4F6B'
GRAD_BOTTOM='#232D40'
SHADOW='#101828'

echo "▶ 앱 아이콘 합성"
for f in app/tile.svg app/symbol.svg; do
  [[ -f "$f" ]] || { echo "오류: $f 가 없다. app/make-vectors.py 를 먼저 돌려라." >&2; exit 1; }
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
