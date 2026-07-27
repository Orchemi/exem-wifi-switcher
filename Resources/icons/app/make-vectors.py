"""앱 아이콘 벡터 원본(tile.svg / symbol.svg) 생성기 — 1024x1024.

메뉴바 아이콘과 같은 기하 언어를 쓴다. 앱 아이콘 심볼은
manual(핀) + dhcp(순환 화살표)를 한 그림으로 합친 것이다.

색·깊이감(그라디언트·광택·그림자) 합성은 export.sh 가 ImageMagick 으로 한다.
여기서는 형태만 만든다.
"""
import math
from pathlib import Path

CANVAS = 1024
TILE = 824                 # macOS 관례: 캔버스의 80.5%
TILE_R_RATIO = 0.2425      # 실측(Terminal.app): 변의 24.25%
TILE_N = 2.2               # 실측 코너 초타원 지수 (2.0 이면 정원호)
SYMBOL_FILL = 0.58         # 심볼이 타일 변에서 차지하는 비율

NOM_R_MID = 250.0          # 기준 치수 — 최종 배율은 아래에서 계산해 곱한다
NOM_W = 70.0
TH_START, TH_END = 302.0, 242.0   # 메뉴바 dhcp 와 같은 각도 (위쪽 60° 틈)
HEAD_HW_K, HEAD_LEN_K = 1.05, 1.70
PIN_FILL = 0.68
PIN_DY = -0.05          # 핀 광학 보정 (ri 대비 비율, 음수면 위로)


def f(x):
    s = f"{x:.2f}".rstrip("0").rstrip(".")
    return s if s != "-0" else "0"


def pt(p):
    return f"{f(p[0])} {f(p[1])}"


def squircle(x, y, size, r, n, seg=64):
    """초타원 코너 둥근 사각형. 코너를 촘촘히 샘플링한 폴리라인(오차 <0.03px)."""
    def corner(cx, cy, sx, sy):
        out = []
        for i in range(seg + 1):
            t = math.pi / 2 * i / seg
            u = math.cos(t) ** (2 / n)
            v = math.sin(t) ** (2 / n)
            out.append((cx + sx * r * (1 - u), cy + sy * r * (1 - v)))
        return out

    # corner() 는 "세로변 쪽 → 가로변 쪽" 순서로 점을 낸다.
    # 시계방향 한 바퀴가 되도록 우상/좌하만 뒤집는다.
    # (네 조각의 방향이 어긋나면 경로가 스스로 교차해 evenodd 로 칠할 때
    #  변 가운데가 체크무늬처럼 뚫린다 — 실제로 한 번 겪었다.)
    x1, y1 = x + size, y + size
    path = (corner(x, y, 1, 1)                # 좌상: 왼쪽변 → 위쪽변
            + corner(x1, y, -1, 1)[::-1]      # 우상: 위쪽변 → 오른쪽변
            + corner(x1, y1, -1, -1)          # 우하: 오른쪽변 → 아래쪽변
            + corner(x, y1, 1, -1)[::-1])     # 좌하: 아래쪽변 → 왼쪽변
    return "M" + pt(path[0]) + "".join("L" + pt(p) for p in path[1:]) + "Z"


def symbol(ox, oy, r_mid, w):
    """고리+화살촉+핀. (ox,oy) 는 고리 중심. 절대좌표로 낸다."""
    ro, ri = r_mid + w / 2, r_mid - w / 2
    a0, a1 = math.radians(TH_START), math.radians(TH_END)
    P = lambda r, a: (ox + r * math.cos(a), oy + r * math.sin(a))
    large = 1 if (TH_END - TH_START) % 360 > 180 else 0

    ring = (f"M{pt(P(ro, a0))}A{f(ro)} {f(ro)} 0 {large} 1 {pt(P(ro, a1))}"
            f"L{pt(P(ri, a1))}A{f(ri)} {f(ri)} 0 {large} 0 {pt(P(ri, a0))}Z")

    head_hw, head_len = HEAD_HW_K * w, HEAD_LEN_K * w
    m = P(r_mid, a1)
    rad = (math.cos(a1), math.sin(a1))
    tan = (-math.sin(a1), math.cos(a1))
    b_out = (m[0] + head_hw * rad[0], m[1] + head_hw * rad[1])
    b_in = (m[0] - head_hw * rad[0], m[1] - head_hw * rad[1])
    apex = (m[0] + head_len * tan[0], m[1] + head_len * tan[1])
    head = f"M{pt(b_out)}L{pt(apex)}L{pt(b_in)}Z"

    # 핀 — 메뉴바 manual 과 같은 비율(머리 반지름 rp 기준):
    #   꼭짓점 = 머리중심 + 1.713rp / 구멍 = 0.4255rp / 외접반지름 = 1.3565rp
    rp = PIN_FILL * ri / 1.3565
    hole = 0.4255 * rp
    hcy = oy - 0.3565 * rp + PIN_DY * ri          # 핀 외접원 중심을 고리 중심에 맞춘다
    tip_y = hcy + 1.713 * rp
    cosb = rp / (tip_y - hcy)
    sinb = math.sqrt(1 - cosb * cosb)
    lt = (ox - rp * sinb, hcy + rp * cosb)
    rt = (ox + rp * sinb, hcy + rp * cosb)
    pin = (f"M{pt((ox, tip_y))}L{pt(lt)}A{f(rp)} {f(rp)} 0 1 1 {pt(rt)}Z"
           f"M{pt((ox, hcy - hole))}"
           f"A{f(hole)} {f(hole)} 0 1 0 {pt((ox, hcy + hole))}"
           f"A{f(hole)} {f(hole)} 0 1 0 {pt((ox, hcy - hole))}Z")

    # 고리 위쪽은 틈이므로 상단 경계는 화살촉이 정한다
    xs = [ox - ro, ox + ro, b_out[0], b_in[0], apex[0]]
    ys = [oy + ro, b_out[1], b_in[1], apex[1]]
    return ring + head + pin, (min(xs), min(ys), max(xs), max(ys))


SVG = ('<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" '
       'viewBox="0 0 1024 1024">\n{c}\n  '
       '<path fill="#000" fill-rule="evenodd" d="{d}"/>\n</svg>\n')


def build(outdir):
    outdir = Path(outdir)
    outdir.mkdir(parents=True, exist_ok=True)

    # 1) 타일 실루엣
    xy = (CANVAS - TILE) / 2
    d_tile = squircle(xy, xy, TILE, TILE * TILE_R_RATIO, TILE_N)
    (outdir / "tile.svg").write_text(SVG.format(d=d_tile, c=(
        "  <!--\n"
        "    앱 아이콘 타일 실루엣 (스퀘어클).\n"
        "    macOS 실제 아이콘(Terminal.app)의 알파를 실측해 맞췄다 —\n"
        f"    캔버스의 80.5%({TILE}px), 코너 반지름 = 변의 {TILE_R_RATIO*100:.2f}%,\n"
        f"    코너 초타원 지수 {TILE_N} (2.0 이면 정원호).\n"
        "    색·광택·그림자는 export.sh 가 이 실루엣을 마스크로 삼아 입힌다.\n"
        "  -->")))

    # 2) 심볼 — 기준 치수로 bbox 를 잰 뒤 타일에 맞춰 재계산
    _, (x0, y0, x1, y1) = symbol(0, 0, NOM_R_MID, NOM_W)
    k = SYMBOL_FILL * TILE / max(x1 - x0, y1 - y0)
    d_sym, bb = symbol(0, 0, NOM_R_MID * k, NOM_W * k)
    ox = CANVAS / 2 - (bb[0] + bb[2]) / 2
    oy = CANVAS / 2 - (bb[1] + bb[3]) / 2
    d_sym, bb = symbol(ox, oy, NOM_R_MID * k, NOM_W * k)

    (outdir / "symbol.svg").write_text(SVG.format(d=d_sym, c=(
        "  <!--\n"
        "    앱 아이콘 심볼 — 메뉴바 manual(핀) 과 dhcp(순환 화살표) 를 겹친 형태.\n"
        "    \"고정된 자리를, 자동으로 갈아 끼운다\" 는 앱의 한 줄이 그대로 형태가 된다.\n"
        f"    고리 각도는 메뉴바 dhcp 와 동일({TH_START:.0f}°→{TH_END:.0f}°, 위쪽 60° 틈),\n"
        "    핀 비율도 메뉴바 manual 과 동일하다.\n"
        "    16px 에서 살아남아야 하는 메뉴바 쪽은 획을 더 굵게 쓴다 — 의도된 차이다.\n"
        f"    바운딩박스 {bb[2]-bb[0]:.0f}x{bb[3]-bb[1]:.0f}, 타일 변의 {SYMBOL_FILL*100:.0f}%.\n"
        "    검정으로 그려 두고 export.sh 가 흰색으로 뒤집어 쓴다.\n"
        "  -->")))

    print(f"타일  {TILE}px  코너 r={TILE*TILE_R_RATIO:.1f} n={TILE_N}")
    print(f"심볼  {bb[2]-bb[0]:.1f} x {bb[3]-bb[1]:.1f}  (배율 {k:.4f})")


if __name__ == "__main__":
    import sys
    # 기본 출력은 이 스크립트가 놓인 디렉토리 — 레포 경로에 의존하지 않는다.
    build(sys.argv[1] if len(sys.argv) > 1 else Path(__file__).parent)
