"""아이콘 벡터 원본 생성기 — 메뉴바 3종 + 앱 아이콘.

전부 하나의 격자 위에서 같은 기하 언어로 그린다.

    메뉴바 = 크게 깔린 Wi-Fi 베이스 + 그 위를 가로지르는 **외곽선(line)** 배지
             (배지 실루엣 둘레는 파내서 아치가 뒤로 지나가게 보이게 한다)
    앱     = 그 Wi-Fi 베이스 하나 (배지 없음)

배지는 채우지 않고 **윤곽만** 그린다(Docker 메뉴바 아이콘과 같은 방식).
그래서 배지마다 두 도형이 필요하다.
    ink  — 실제로 그리는 것 (외곽선 + 안쪽 심볼)
    mask — 베이스에서 지워낼 것 (**채워진** 실루엣). 이걸 안 쓰고 ink 로 파내면
           배지 안쪽 빈 공간으로 Wi-Fi 아치가 비쳐 들어와 엉킨다.

세 상태가 베이스를 공유하므로 "Wi-Fi 설정 도구"라는 정체는 항상 읽히고,
바뀌는 것은 배지뿐이다.

32단위 격자를 쓰는 이유: 메뉴바 아이콘은 높이 16pt 이고 Retina 에서 @2x = 32px 로
렌더된다. **실사용의 대부분이 32px** 이므로 1단위 = @2x 의 1픽셀이 되게 맞춰 두면
치수를 픽셀로 직접 생각할 수 있다.

캔버스는 정사각이 아니라 **50x36(가로 25pt x 세로 18pt)** 다. 메뉴바가 강제하는 것은
높이뿐이고, 가로로 넓혀야 Wi-Fi 를 키우면서 배지를 우하단 제자리에 둘 수 있다.
정사각 32x32 에서는 배지가 아치 끝자락만 스치는 것이 기하학적 한계였다(README 참조).

  ⚠ 세로로 긴 정사각이 아니므로 표시 코드가 종횡비를 지켜야 한다.
    Sources/ExemWifiSwitcherApp/StatusIcons.swift 가 size 를 16x16 으로 **고정**하면
    가로가 눌린다. README "앱에 연결하기" 절에 필요한 수정을 적어 두었다.

색·그라디언트·그림자·PNG 는 export.sh 가 만든다. 여기서는 형태만 만든다.

의존성: shapely (`pip3 install shapely`).
    배지 둘레를 파내려면 진짜 폴리곤 불리언(차집합)이 필요하다. SVG 의 fill-rule
    로는 안 된다 — evenodd 는 대칭차집합이라 배지 바깥으로 삐져나온 파냄 영역까지
    칠해 버리고, nonzero 는 감김수가 뒤집혀 같은 문제가 난다.
    SVG 는 저장소에 들어 있으므로, 형태를 바꿀 때만 이 스크립트가 필요하다.
    export.sh 는 ImageMagick 만 있으면 돌아간다.

사용법:
    python3 make-icons.py && ./export.sh
"""
import math
import sys
from pathlib import Path

try:
    from shapely import affinity
    from shapely.geometry import LineString, Point, Polygon, box
    from shapely.ops import unary_union
except ModuleNotFoundError:
    sys.exit("오류: shapely 가 필요하다.  pip3 install shapely")

# --------------------------------------------------------------------------
# 기하 상수 — 전부 36x32 격자 기준 (1단위 = 메뉴바 @2x 의 1픽셀)
# --------------------------------------------------------------------------
CANVAS_W, CANVAS_H = 50.0, 36.0

# Wi-Fi 베이스 --------------------------------------------------------------
# 아치는 스트로크가 아니라 중심선을 buffer 해서 만든 아웃라인이다.
# 스트로크는 크기를 바꿔도 굵기가 함께 변하지 않아 템플릿에 부적합하다.
# Wi-Fi 가 주인공이다. 배지에 밀려 구석으로 가면 안 된다 — 폭이 캔버스의 70% 다.
# 아래 수치는 "배지가 점(dot)을 파먹지 않는 한계"에서 역산한 것이다. 더 키우면
# 배지 파냄이 점을 물어뜯는다 (make-icons.py 를 고칠 때 반드시 다시 확인하라).
# 획 두께는 반지름과 **분리해서** 잡는다. 반지름에 비례시키면 Wi-Fi 를 키울 때
# 획이 같이 굵어져, 가느다란 line 배지와 무게가 어긋난다(실제로 4.8 대 2.4 까지 벌어졌다).
#
# 아치는 **3개**다. 표준 Wi-Fi 글리프의 개수이고, 2개면 점과 안쪽 아치 사이가
# 휑하게 비어 "선이 하나 빠진" 것으로 보인다(실제로 그렇게 보였다).
# 반지름은 상수로 두지 않고 아래 arc_radii() 가 계산한다 — 점→아치, 아치→아치
# 간격을 같은 리듬(ARC_GAP)으로 두어야 균일하게 읽히기 때문이다.
ARC_N = 3              # 아치 개수
ARC_T = 4.0            # 아치 두께. @1x 로는 2.00px
ARC_GAP = 3.32         # 점-아치 / 아치-아치 공통 빈틈. @1x 1.66px
DOT_R = 2.50           # 정점의 점. 지름이 획의 1.25배
SPREAD_L = 48.0        # 왼쪽 벌림각(도). 위쪽 수직 기준
SPREAD_R = 105.0       # 오른쪽은 길게 — 배지 뒤로 이어지다 파냄에 잘린다
WIFI_LEFT = 0.8        # 아치 왼쪽 끝의 캔버스 여백
WIFI_TOP = 0.8         # 아치 꼭대기의 캔버스 여백 (정점 y 는 여기서 역산한다)

# 배지 ----------------------------------------------------------------------
# 채우지 않고 **윤곽만** 그린다. fill 로 하면 작아질수록 검은 덩어리가 되고,
# 특히 경고 배지는 채운 원에 느낌표를 파낸 구조라 구멍이 먼저 죽어 뭉개진다.
#
# line 은 fill 보다 **큰 지름을 요구한다** — 획 두께 + 안쪽 여백 + 심볼이 모두
# 들어가야 하기 때문이다. 그래서 배지를 14 -> 22단위로 키웠다.
BADGE_D = 24.8         # 배지 지름 = 캔버스 세로의 68.9%
BADGE_MARGIN = 0.8     # 우하단 여백
BADGE_STROKE = 2.9     # 배지 획. @1x 1.45px — 이보다 얇으면 @1x 에서 회색 죽이 된다
KNOCKOUT = 2.6         # 배지 둘레를 파내는 폭(@1x 1.30px)
SPECK = 1.0            # 파냄이 남긴 이 넓이 미만 조각은 버린다

# 앱 아이콘 -----------------------------------------------------------------
APP_CANVAS = 1024
APP_TILE = 824             # macOS 관례: 캔버스의 80.5%
APP_TILE_R_RATIO = 0.2425  # 실측(Terminal.app): 변의 24.25%
APP_TILE_N = 2.2           # 실측 코너 초타원 지수 (2.0 이면 정원호)
APP_SYMBOL_FILL = 0.70     # 심볼 **가로**가 타일 변에서 차지하는 비율
APP_SYMBOL_DY = 0.012      # 광학 보정: 질량이 위(아치)에 쏠려 있어 조금 내린다
APP_TOL = 0.05             # 경로 단순화 허용 오차(1024 기준 0.05px)

OUT = Path(__file__).parent


# --------------------------------------------------------------------------
# 유틸
# --------------------------------------------------------------------------
def soften(g, r):
    """볼록 코너만 r 만큼 둥글린다 (오목 코너는 그대로 둔다)."""
    return g.buffer(-r, quad_segs=32).buffer(r, quad_segs=32) if r > 0 else g


def unit_to(g, x0, y0, x1, y1):
    """단위 정사각 [0,1]² 에 그린 도형을 박스로 옮긴다."""
    return affinity.affine_transform(g, [x1 - x0, 0, 0, y1 - y0, x0, y0])


def path_d(geom, tol=0.006, nd=3):
    """폴리곤(구멍 포함)을 SVG path 데이터로. fill-rule=evenodd 로 칠한다.

    불리언 결과는 곡선이 전부 폴리라인으로 풀려 점이 수천 개다. 32단위 격자에서
    tol 단위(=@2x 의 0.006px)까지 어긋나도 되는 점은 버린다 — 눈에 보이지 않는
    오차로 파일이 한 자릿수 작아진다.
    """
    geom = geom.simplify(tol, preserve_topology=True)

    def ring(coords):
        pts = [f"{round(x, nd):g} {round(y, nd):g}" for x, y in coords]
        return "M" + pts[0] + "".join("L" + p for p in pts[1:]) + "Z"

    out = []
    for p in getattr(geom, "geoms", [geom]):
        if p.is_empty:
            continue
        out.append(ring(p.exterior.coords[:-1]))
        out += [ring(h.coords[:-1]) for h in p.interiors]
    return "".join(out)


def write_svg(path, geom, vw, vh, comment, tol=0.006, unit=0.5):
    """뷰박스 vw x vh 단위를 unit 배 크기로 표시한다.

    메뉴바는 unit=0.5 — 1단위가 @2x 의 1픽셀이므로 표시 크기(pt)는 그 절반이다.
    앱 아이콘은 unit=1 — 1024 단위가 그대로 1024px 다.
    """
    # tol 은 뷰박스 단위다 — 앱 아이콘(1024)은 격자가 32배 촘촘하므로 크게 준다.
    body = (f'<svg xmlns="http://www.w3.org/2000/svg" '
            f'width="{vw * unit:g}" height="{vh * unit:g}" '
            f'viewBox="0 0 {vw:g} {vh:g}">\n{comment}\n'
            f'  <path fill="#000" fill-rule="evenodd" d="{path_d(geom, tol=tol)}"/>\n</svg>\n')
    path.write_text(body)


# --------------------------------------------------------------------------
# Wi-Fi 베이스
# --------------------------------------------------------------------------
def wifi(ox, oy, radii, t, dot_r, spread, seg=96):
    """동심 아치 + 정점의 점. spread 는 (왼쪽, 오른쪽) 벌림각(도).

    오른쪽을 길게 주는 것이 이 아이콘의 핵심이다. 아치가 배지 안쪽까지
    이어지고 파냄이 그것을 잘라내므로, 아치가 배지 **뒤로 지나간다**고 읽힌다.
    """
    sl, sr = spread
    a0, a1 = math.radians(270 - sl), math.radians(270 + sr)
    parts = []
    for r in radii:
        pts = [(ox + r * math.cos(a0 + (a1 - a0) * i / seg),
                oy + r * math.sin(a0 + (a1 - a0) * i / seg)) for i in range(seg + 1)]
        parts.append(LineString(pts).buffer(t / 2, cap_style=1, quad_segs=32))
    if dot_r:
        parts.append(Point(ox, oy).buffer(dot_r, quad_segs=64))
    return unary_union(parts)


def arc_radii():
    """안쪽 아치부터의 중심선 반지름.

    점 표면 → 안쪽 아치, 아치 → 아치 간격을 모두 ARC_GAP 으로 둔다.
    이 리듬이 어긋나면 "선이 하나 빠진" 것처럼 보인다.
    """
    r1 = DOT_R + ARC_GAP + ARC_T / 2
    return [r1 + i * (ARC_T + ARC_GAP) for i in range(ARC_N)]


def arc_edge():
    """아치 바깥 가장자리 반지름 = Wi-Fi 의 겉 반지름."""
    return arc_radii()[-1] + ARC_T / 2


def wifi_base(spread):
    """여백에 맞춰 놓은 Wi-Fi. 정점 좌표는 왼쪽·위 여백에서 역산한다."""
    edge = arc_edge()
    ox = WIFI_LEFT + math.sin(math.radians(spread[0])) * edge
    return wifi(ox, WIFI_TOP + edge, arc_radii(), ARC_T, DOT_R, spread)


# --------------------------------------------------------------------------
# 배지 — 외곽선(line) 방식. 각 함수는 (ink, mask) 를 돌려준다.
#   ink  = 실제로 그리는 윤곽선
#   mask = 베이스에서 지워낼 **채워진** 실루엣
# --------------------------------------------------------------------------
def outline(shape, w):
    """실루엣 안쪽으로 두께 w 의 테두리만 남긴다."""
    return shape.difference(shape.buffer(-w, quad_segs=32))


def pill(cx, cy, w, h):
    return soften(box(cx - w / 2, cy - h / 2, cx + w / 2, cy + h / 2), w / 2 - 1e-4)


def badge_briefcase(x0, y0, x1, y1, w, top=0.30, hw=0.27, hh=0.35):
    """서류가방 = 회사. 몸통 윤곽 + 위에 얹힌 손잡이 윤곽."""
    W, H = x1 - x0, y1 - y0
    body = soften(box(x0, y0 + top * H, x1, y1), 0.16 * W)
    handle = soften(box(x0 + W * (0.5 - hw), y0, x0 + W * (0.5 + hw), y0 + hh * H),
                    0.35 * W * hw)
    # 손잡이는 몸통 위로 나온 부분만 그린다 (몸통 윗변이 손잡이 바닥을 대신한다)
    ink = unary_union([outline(body, w),
                       outline(handle, w).difference(box(x0, y0 + top * H,
                                                         x1, y1 + 1))])
    return ink, unary_union([body, handle])


def badge_house(x0, y0, x1, y1, w, roof=0.42, dw=0.43, dh=0.46):
    """집 = 집·외부.

    지붕만 있는 오각형은 이 크기에서 **그냥 삼각형 덩어리**로 읽힌다(실렌더로 확인).
    지붕을 0.42 로 낮춰 몸통이 실루엣을 주도하게 하고, 바닥에 문을 낸다.
    문 하나가 "이건 들어가는 곳이다 = 건물이다" 를 즉시 말해준다.
    """
    W, H = x1 - x0, y1 - y0
    sil = soften(unary_union([
        Polygon([(x0 + W / 2, y0), (x1, y0 + roof * H), (x0, y0 + roof * H)]),
        box(x0, y0 + roof * H - 0.02 * H, x1, y1)]), 0.9)
    d_w, d_h = dw * W, dh * H
    door_sil = soften(box(x0 + W / 2 - d_w / 2, y1 - d_h,
                          x0 + W / 2 + d_w / 2, y1), 0.6)
    # 문은 바닥에 얹힌 ∩ 자 — 바닥변은 집 외곽선이 이미 그렸다
    door = outline(door_sil, w).difference(box(x0, y1 - w * 0.9, x1, y1 + 1))
    return unary_union([outline(sil, w), door]), sil


def badge_alert(cx, cy, R, w, top=0.62, bot=0.10, knob=0.52):
    """원 외곽선 + 느낌표 = 경고. 여기서 독창성은 손해다, 관례를 따른다.

    막대와 점은 **링 안쪽 반지름 기준**으로 배치한다. 바깥 반지름으로 잡으면
    막대가 링을 뚫고 점과 붙어 버려 그냥 세로줄 하나로 읽힌다(실제로 겪었다).
    """
    ri = R - w
    bar = pill(cx, cy + (bot - top) / 2 * ri, w, (top + bot) * ri)
    dot = Point(cx, cy + knob * ri).buffer(w / 2, quad_segs=48)
    return (unary_union([outline(Point(cx, cy).buffer(R, quad_segs=96), w), bar, dot]),
            Point(cx, cy).buffer(R, quad_segs=96))


def badge_of(name):
    """우하단에 놓인 (ink, mask)."""
    x1, y1 = CANVAS_W - BADGE_MARGIN, CANVAS_H - BADGE_MARGIN
    x0, y0 = x1 - BADGE_D, y1 - BADGE_D
    w = BADGE_STROKE
    if name == "manual":
        return badge_briefcase(x0, y0, x1, y1, w)
    if name == "dhcp":
        return badge_house(x0, y0, x1, y1, w)
    return badge_alert((x0 + x1) / 2, (y0 + y1) / 2, BADGE_D / 2, w)


BADGES = {
    "manual": "서류가방 윤곽 — 사내 프로필(고정 IP) 적용 중",
    "dhcp": "집 윤곽 — DHCP(집·외부) 적용 중",
    "error": "원 윤곽 + 느낌표 — 전환 실패 / 헬퍼 미설치",
}


# --------------------------------------------------------------------------
# 합성
# --------------------------------------------------------------------------
def menubar(name):
    ink, mask = badge_of(name)
    base = wifi_base((SPREAD_L, SPREAD_R))

    # 파냄(knockout): 배지의 **채워진 실루엣**을 KNOCKOUT 만큼 부풀려 베이스에서 뺀다.
    # 템플릿 이미지는 단색이라 색으로 겹침을 구분할 수 없다 — 투명 링으로 갈라
    # 놓지 않으면 배지와 아치가 한 덩어리로 뭉개진다. ink(윤곽)로 파내면 배지
    # 안쪽 빈 공간에 아치가 비쳐 들어오므로 반드시 mask 를 쓴다.
    halo = mask.buffer(KNOCKOUT, join_style=1, quad_segs=32)

    # 회귀 방지: Wi-Fi 를 더 키우거나 배지를 더 키우면 파냄이 **정점의 점**을
    # 물어뜯는다. 잘린 점은 결함으로 보이므로 여기서 막는다.
    edge = arc_edge()
    apex = Point(WIFI_LEFT + math.sin(math.radians(SPREAD_L)) * edge,
                 WIFI_TOP + edge)
    slack = apex.distance(mask) - DOT_R - KNOCKOUT
    if slack < 0:
        raise SystemExit(
            f"오류: {name} — 배지 파냄이 Wi-Fi 정점의 점을 {-slack:.2f}단위 파먹는다.\n"
            "      Wi-Fi 를 줄이거나(ARC_T·ARC_GAP·DOT_R) 배지를 줄여라(BADGE_D).")

    cut = base.difference(halo)
    cut = unary_union([p for p in getattr(cut, "geoms", [cut]) if p.area >= SPECK])
    return unary_union([cut, ink]), slack, base.area - cut.area


def squircle(x, y, size, r, n, seg=64):
    """초타원 코너 둥근 사각형. 코너를 촘촘히 샘플링한 폴리라인(오차 <0.03px)."""
    def corner(cx, cy, sx, sy):
        out = []
        for i in range(seg + 1):
            th = math.pi / 2 * i / seg
            out.append((cx + sx * r * (1 - math.cos(th) ** (2 / n)),
                        cy + sy * r * (1 - math.sin(th) ** (2 / n))))
        return out

    # corner() 는 "세로변 쪽 → 가로변 쪽" 순서로 점을 낸다.
    # 시계방향 한 바퀴가 되도록 우상/좌하만 뒤집는다.
    x1, y1 = x + size, y + size
    ring = (corner(x, y, 1, 1) + corner(x1, y, -1, 1)[::-1]
            + corner(x1, y1, -1, -1) + corner(x, y1, 1, -1)[::-1])
    return Polygon(ring)


def app_symbol():
    """앱 심볼 = 메뉴바가 공유하는 Wi-Fi 베이스 그대로. 배지는 얹지 않는다."""
    g = wifi_base((SPREAD_L, SPREAD_L))
    x0, y0, x1, y1 = g.bounds
    k = APP_SYMBOL_FILL * APP_TILE / (x1 - x0)   # Wi-Fi 는 가로로 넓다 — 가로 기준
    g = affinity.scale(g, k, k, origin=(0, 0))
    x0, y0, x1, y1 = g.bounds
    return affinity.translate(g,
                              APP_CANVAS / 2 - (x0 + x1) / 2,
                              APP_CANVAS / 2 - (y0 + y1) / 2
                              + APP_SYMBOL_DY * APP_TILE)


# --------------------------------------------------------------------------
def main():
    (OUT / "menubar").mkdir(exist_ok=True)
    (OUT / "app").mkdir(exist_ok=True)

    badge_pct = BADGE_D / CANVAS_H * 100
    for name in BADGES:
        g, slack, cut = menubar(name)
        x0, y0, x1, y1 = g.bounds
        why = BADGES[name]
        write_svg(OUT / "menubar" / f"{name}.svg", g, CANVAS_W, CANVAS_H, (
            "  <!--\n"
            f"    {name} — {why}\n\n"
            "    크게 깔린 Wi-Fi 아치(베이스) 위에 작은 배지를 얹었다.\n"
            f"    배지는 캔버스의 {badge_pct:.0f}% — 주인공은 Wi-Fi 다.\n"
            f"    배지 둘레는 {KNOCKOUT} 단위 파내(knockout) 투명 링을 두었다 —\n"
            "    템플릿 이미지는 단색이라 갈라 놓지 않으면 한 덩어리로 뭉개진다.\n"
            f"    아치는 배지 뒤로 이어지다 그 링에 잘린다(잘린 넓이 {cut:.0f}단위²).\n\n"
            f"    바운딩박스 x {x0:.2f}..{x1:.2f} / y {y0:.2f}..{y1:.2f}"
            f"  ({CANVAS_W:.0f}x{CANVAS_H:.0f} 격자 = @2x 픽셀)\n"
            f"    잉크 비율 {g.area / (CANVAS_W * CANVAS_H) * 100:.1f}%  — 세 상태를 맞춰 두었다\n"
            f"    정점의 점과 배지 사이 여유 {slack:.2f}단위 (음수가 되면 점이 잘린다)\n\n"
            "    템플릿 이미지 규약: 단색 검정 + 알파만. 색·그라디언트·그림자를\n"
            "    넣지 마라. macOS 가 메뉴바 배경에 맞춰 자동으로 반전시킨다.\n"
            "    형태는 make-icons.py 가 만든다 — 이 파일을 손으로 고치지 마라.\n"
            "  -->"))
        print(f"menubar/{name:6s} 잉크 {g.area / (CANVAS_W * CANVAS_H) * 100:5.2f}%  "
              f"아치잘림 {cut:4.0f}  점여유 {slack:4.2f}  "
              f"여백 L{x0:.2f} R{CANVAS_W - x1:.2f} T{y0:.2f} B{CANVAS_H - y1:.2f}")

    xy = (APP_CANVAS - APP_TILE) / 2
    tile = squircle(xy, xy, APP_TILE, APP_TILE * APP_TILE_R_RATIO, APP_TILE_N)
    write_svg(OUT / "app" / "tile.svg", tile, APP_CANVAS, APP_CANVAS, (
        "  <!--\n"
        "    앱 아이콘 타일 실루엣 (스퀘어클).\n"
        "    macOS 실제 아이콘(Terminal.app)의 알파를 실측해 맞췄다 —\n"
        f"    캔버스의 80.5%({APP_TILE:.0f}px), 코너 반지름 = 변의 "
        f"{APP_TILE_R_RATIO * 100:.2f}%,\n"
        f"    코너 초타원 지수 {APP_TILE_N} (2.0 이면 정원호).\n"
        "    색·그림자는 export.sh 가 이 실루엣을 마스크로 삼아 입힌다.\n"
        "  -->"), tol=APP_TOL, unit=1)

    sym = app_symbol()
    x0, y0, x1, y1 = sym.bounds
    write_svg(OUT / "app" / "symbol.svg", sym, APP_CANVAS, APP_CANVAS, (
        "  <!--\n"
        "    앱 심볼 — 메뉴바 3종이 공유하는 Wi-Fi 베이스 그대로다.\n"
        "    앱은 상태가 없으므로 배지를 얹지 않는다: Dock 에는 도구의 정체만,\n"
        "    메뉴바에는 거기에 상태 배지를 더해 보여준다.\n"
        "    메뉴바 쪽은 오른쪽 아치를 길게 빼 배지 뒤로 넣지만(잘려 없어진다),\n"
        "    여기서는 좌우 대칭으로 그린다 — 가릴 것이 없다.\n"
        f"    바운딩박스 {x1 - x0:.0f}x{y1 - y0:.0f}, 타일 변의 "
        f"{APP_SYMBOL_FILL * 100:.0f}%(가로 기준).\n"
        "    검정으로 그려 두고 export.sh 가 흰색으로 뒤집어 쓴다.\n"
        "  -->"), tol=APP_TOL, unit=1)
    print(f"app/tile.svg      {APP_TILE:.0f}px  코너 r="
          f"{APP_TILE * APP_TILE_R_RATIO:.1f} n={APP_TILE_N}")
    print(f"app/symbol.svg    {x1 - x0:.0f} x {y1 - y0:.0f}")


if __name__ == "__main__":
    main()
