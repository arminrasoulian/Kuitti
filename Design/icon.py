#!/usr/bin/env python3
"""Generate the Kuitti icon + logo-mark SVGs with computed geometry.

Concept (the winner of the concept exploration): a clean white receipt on a
spruce-green gradient, with an upward price-history trend line that rises across
it and BREAKS PAST the top edge into a bright arrowhead — "Kuitti turns a paper
receipt into a rising story of what things cost." A white halo keeps the green
line crisp where it crosses both the paper and the green background.

Emits into Design/sources/:
  icon_master.svg   full-bleed 1024 app icon (opaque gradient bg)
  mark_launch.svg   receipt WITHOUT the trend, transparent, cropped square
                    (the static launch screen; the splash then draws the trend)
  mark_full.svg     receipt WITH the trend, transparent, cropped square
                    (reference: the splash's final frame == this == the icon)
"""
import math
from pathlib import Path

OUT = Path(__file__).parent / "sources"
OUT.mkdir(parents=True, exist_ok=True)

# ── Brand palette ──────────────────────────────────────────────────────────
G_TOP = "#23AD82"   # bright spruce (top of bg gradient)
G_MID = "#15805F"   # core brand spruce
G_BOT = "#0B5440"   # deep spruce (bottom)
LINE = "#157F5F"    # trend line on the white receipt
LINE_HI = "#1FB488"  # bright emerald: arrowhead + lead dot
PAPER_HI = "#FFFFFF"
PAPER_LO = "#EAF3EF"
FAINT = "#D5E3DC"   # faint receipt rules

# ── Receipt box geometry (1024 design space) ───────────────────────────────
LEFT, RIGHT = 322, 702
TOP, BASE = 246, 760
R = 42                # top corner radius
TOOTH_W = 19          # half-tooth width
TOOTH_H = 26          # depth of the perforation teeth below BASE

# ── Crop for the launch/splash mark (keep in sync with SplashView.swift) ───
# Square window that contains the receipt AND the breakout arrow, centered on
# the receipt so the launch logo sits centered with room for the trend.
CROP_X, CROP_Y, CROP_SIDE = 180, 180, 664


def zigzag_bottom():
    pts, x, down = [], RIGHT, True
    while x > LEFT + 0.5:
        x -= TOOTH_W
        pts.append((max(x, LEFT), BASE + TOOTH_H if down else BASE))
        down = not down
    if pts[-1] != (LEFT, BASE):
        pts.append((LEFT, BASE))
    return pts


def receipt_path():
    z = " ".join(f"L {x:.0f},{y:.0f}" for x, y in zigzag_bottom())
    return (f"M {LEFT},{TOP + R} Q {LEFT},{TOP} {LEFT + R},{TOP} "
            f"L {RIGHT - R},{TOP} Q {RIGHT},{TOP} {RIGHT},{TOP + R} "
            f"L {RIGHT},{BASE} {z} L {LEFT},{TOP + R} Z")


# ── Trend line: rises L→R, breaks past the top-right into an arrowhead ──────
TREND = [(372, 686), (452, 612), (536, 648), (628, 470), (700, 388)]
TIP = (814, 248)          # arrow tip, outside the receipt (upper-right)
HEAD_LEN, HEAD_HALF = 92, 54


def _arrowhead():
    lp = TREND[-1]
    dx, dy = TIP[0] - lp[0], TIP[1] - lp[1]
    L = math.hypot(dx, dy)
    ux, uy = dx / L, dy / L
    px, py = -uy, ux
    base = (TIP[0] - ux * HEAD_LEN, TIP[1] - uy * HEAD_LEN)
    b1 = (base[0] + px * HEAD_HALF, base[1] + py * HEAD_HALF)
    b2 = (base[0] - px * HEAD_HALF, base[1] - py * HEAD_HALF)
    return base, b1, b2


def trend_markup():
    base, b1, b2 = _arrowhead()
    line_pts = TREND + [base]
    poly = " ".join(f"{x:.0f},{y:.0f}" for x, y in line_pts)
    tri = (f"M {TIP[0]:.0f},{TIP[1]:.0f} L {b1[0]:.0f},{b1[1]:.0f} "
           f"L {b2[0]:.0f},{b2[1]:.0f} Z")
    dot_a = TREND[1]      # mid dot
    dot_b = TREND[4]      # breakout-shoulder dot (bright)
    return f'''<!-- white halo so the line reads on paper AND on the green bg -->
    <polyline points="{poly}" fill="none" stroke="#FFFFFF" stroke-width="50"
              stroke-linecap="round" stroke-linejoin="round"/>
    <path d="{tri}" fill="#FFFFFF" stroke="#FFFFFF" stroke-width="30" stroke-linejoin="round"/>
    <!-- the trend itself -->
    <polyline points="{poly}" fill="none" stroke="{LINE}" stroke-width="28"
              stroke-linecap="round" stroke-linejoin="round"/>
    <path d="{tri}" fill="{LINE_HI}" stroke="{LINE_HI}" stroke-width="2" stroke-linejoin="round"/>
    <!-- data dots -->
    <circle cx="{dot_a[0]}" cy="{dot_a[1]}" r="21" fill="#FFFFFF"/>
    <circle cx="{dot_a[0]}" cy="{dot_a[1]}" r="11" fill="{LINE}"/>
    <circle cx="{dot_b[0]}" cy="{dot_b[1]}" r="23" fill="#FFFFFF"/>
    <circle cx="{dot_b[0]}" cy="{dot_b[1]}" r="12" fill="{LINE_HI}"/>'''


def receipt_inner():
    """Minimal receipt content: a store-name bar + one faint ghost band.
    Kept sparse so the trend is the single focal idea (avoids sub-40px mush)."""
    return (
        f'<rect x="386" y="300" width="170" height="30" rx="15" fill="{LINE}" opacity="0.9"/>\n    '
        f'<rect x="386" y="356" width="232" height="15" rx="7.5" fill="{FAINT}"/>\n    '
        f'<rect x="386" y="392" width="150" height="15" rx="7.5" fill="{FAINT}"/>'
    )


# ── SVG assembly ───────────────────────────────────────────────────────────
DEFS = f'''<defs>
    <linearGradient id="bg" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="{G_TOP}"/>
      <stop offset="0.55" stop-color="{G_MID}"/>
      <stop offset="1" stop-color="{G_BOT}"/>
    </linearGradient>
    <radialGradient id="glow" cx="0.5" cy="0.34" r="0.72">
      <stop offset="0" stop-color="#FFFFFF" stop-opacity="0.16"/>
      <stop offset="1" stop-color="#FFFFFF" stop-opacity="0"/>
    </radialGradient>
    <linearGradient id="paper" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="{PAPER_HI}"/>
      <stop offset="1" stop-color="{PAPER_LO}"/>
    </linearGradient>
  </defs>'''


def icon_svg():
    return f'''<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">
  {DEFS}
  <rect width="1024" height="1024" fill="url(#bg)"/>
  <rect width="1024" height="1024" fill="url(#glow)"/>
  <path d="{receipt_path()}" fill="#063226" opacity="0.20" transform="translate(0,18)"/>
  <path d="{receipt_path()}" fill="url(#paper)"/>
  <g>
    {receipt_inner()}
  </g>
  <g>
    {trend_markup()}
  </g>
</svg>
'''


def mark_svg(with_trend: bool):
    open_tag = (f'<svg xmlns="http://www.w3.org/2000/svg" '
                f'width="{CROP_SIDE}" height="{CROP_SIDE}" '
                f'viewBox="{CROP_X} {CROP_Y} {CROP_SIDE} {CROP_SIDE}">')
    trend = f"\n  <g>\n    {trend_markup()}\n  </g>" if with_trend else ""
    return f'''{open_tag}
  {DEFS}
  <path d="{receipt_path()}" fill="url(#paper)"/>
  <g>
    {receipt_inner()}
  </g>{trend}
</svg>
'''


(OUT / "icon_master.svg").write_text(icon_svg())
(OUT / "mark_launch.svg").write_text(mark_svg(with_trend=False))
(OUT / "mark_full.svg").write_text(mark_svg(with_trend=True))
for f in ("icon_master.svg", "mark_launch.svg", "mark_full.svg"):
    print("wrote", OUT / f)
