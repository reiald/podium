"""Layered-glass icon previews for Podium (static stand-in for Apple's dynamic Liquid Glass)."""
import itertools
_ids = itertools.count(1)

BG_TOP, BG_BOT = "#2B2E5A", "#0A0B1B"
AMBER_A, AMBER_B = "#FFC26B", "#FF6A3D"

def rrect(x, y, w, h, r):
    return (f"M{x+r} {y}H{x+w-r}A{r} {r} 0 0 1 {x+w} {y+r}V{y+h-r}A{r} {r} 0 0 1 {x+w-r} {y+h}"
            f"H{x+r}A{r} {r} 0 0 1 {x} {y+h-r}V{y+r}A{r} {r} 0 0 1 {x+r} {y}Z")

def glass(d, tint=None, strength=1.0, shadow=True, edge=3, rule=None, sb='b28', dy=30):
    """One glass pane: soft shadow, frosted body, specular band, rim light. `tint` = (top, bottom) colours."""
    n = next(_ids); t0, t1 = tint or ("#FFFFFF", "#FFFFFF")
    fr = f' fill-rule="{rule}"' if rule else ""
    out = ""
    if shadow:
        out += f'<path d="{d}"{fr} fill="#000" opacity="{0.38*strength:.2f}" filter="url(#{sb})" transform="translate(0 {dy})"/>'
    out += (f'<defs><linearGradient id="g{n}" x1="0" y1="0" x2="0" y2="1">'
            f'<stop offset="0" stop-color="{t0}" stop-opacity="{0.55*strength:.2f}"/>'
            f'<stop offset="0.5" stop-color="{t0}" stop-opacity="{0.24*strength:.2f}"/>'
            f'<stop offset="1" stop-color="{t1}" stop-opacity="{0.14*strength:.2f}"/></linearGradient>'
            f'<linearGradient id="e{n}" x1="0" y1="0" x2="1" y2="1">'
            f'<stop offset="0" stop-color="#fff" stop-opacity="0.95"/><stop offset="0.45" stop-color="#fff" stop-opacity="0.10"/>'
            f'<stop offset="1" stop-color="#fff" stop-opacity="0.55"/></linearGradient>'
            f'<linearGradient id="s{n}" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#fff" stop-opacity="0.34"/>'
            f'<stop offset="0.42" stop-color="#fff" stop-opacity="0"/></linearGradient></defs>')
    out += f'<path d="{d}"{fr} fill="url(#g{n})"/><path d="{d}"{fr} fill="url(#s{n})"/>'
    out += f'<path d="{d}"{fr} fill="none" stroke="url(#e{n})" stroke-width="{edge}"/>'
    return out

def glow(d, c0=AMBER_A, c1=AMBER_B, blur="b40", opacity=0.9, stroke=None):
    n = next(_ids)
    paint = (f'fill="url(#a{n})"' if stroke is None else f'fill="none" stroke="url(#a{n})" stroke-width="{stroke}" stroke-linecap="butt"')
    return (f'<defs><linearGradient id="a{n}" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="{c0}"/>'
            f'<stop offset="1" stop-color="{c1}"/></linearGradient></defs><path d="{d}" {paint} opacity="{opacity}" filter="url(#{blur})"/>')

def solid(d, c0=AMBER_A, c1=AMBER_B, rule=None, opacity=1.0):
    n = next(_ids); fr = f' fill-rule="{rule}"' if rule else ""
    return (f'<defs><linearGradient id="m{n}" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="{c0}"/>'
            f'<stop offset="1" stop-color="{c1}"/></linearGradient></defs><path d="{d}"{fr} fill="url(#m{n})" opacity="{opacity}"/>')

def icon(inner):
    """1024 canvas: 824 squircle tile (macOS grid) with the dark gradient background, art inside."""
    sq = rrect(100, 100, 824, 824, 186)
    return ('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024" width="1024" height="1024">'
            '<defs>'+''.join(f'<filter id="b{k}" filterUnits="userSpaceOnUse" x="-600" y="-600" width="2200" height="2200">'f'<feGaussianBlur stdDeviation="{k}"/></filter>' for k in (6,10,14,28,40)) +
            f'<linearGradient id="bg" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="{BG_TOP}"/><stop offset="1" stop-color="{BG_BOT}"/></linearGradient>'
            f'<clipPath id="tile"><path d="{sq}"/></clipPath></defs>'
            f'<path d="{sq}" fill="#000" opacity="0.45" filter="url(#b28)" transform="translate(0 22)"/>'
            f'<g clip-path="url(#tile)"><rect width="1024" height="1024" fill="url(#bg)"/>{inner}'
            f'<path d="{sq}" fill="none" stroke="#fff" stroke-opacity="0.18" stroke-width="3"/></g></svg>')

# ---------- B' : Glass Steps (a window sliced along a podium's three steps; light leaks through the seam)
S, OX, OY = 2.6, 252, 252
T = f'transform="translate({OX} {OY}) scale({S}) translate(-28 -28)"'
UP = "M28 168V72A44 44 0 0 1 72 28H184A44 44 0 0 1 228 72V76H148V122H84V168Z"
LO = "M28 184H100V138H164V92H228V184A44 44 0 0 1 184 228H72A44 44 0 0 1 28 184Z"
SEAM = "M14 176H92V130H156V84H242"
def concept_b():
    n = next(_ids)
    crisp = (f'<defs><linearGradient id="c{n}" x1="0" y1="1" x2="1" y2="0"><stop offset="0" stop-color="{AMBER_B}"/>'
             f'<stop offset="1" stop-color="{AMBER_A}"/></linearGradient></defs>'
             f'<path d="M28 176H92V130H156V84H228" fill="none" stroke="url(#c{n})" stroke-width="17" stroke-linejoin="miter"/>')
    body = (f'<g {T}>' + glow(SEAM, blur="b14", opacity=0.9, stroke=60) + glow(SEAM, blur="b6", opacity=1, stroke=30)
            + crisp
            + glass(LO, tint=("#FFFFFF", "#8F97FF"), strength=1.35, shadow=True, edge=1.5, sb="b10", dy=9)
            + glass(UP, tint=("#FFFFFF", "#C4C8FF"), strength=1.5, shadow=True, edge=1.5, sb="b10", dy=9) + '</g>')
    return icon(body)

# ---------- A' : Two windows make a P
def concept_a():
    stem = rrect(300, 190, 230, 560, 52)
    frame = rrect(410, 190, 380, 360, 76) + rrect(480, 262, 240, 216, 36)
    body = ('<g transform="translate(-33 36)">'
            + glow(rrect(520, 200, 260, 340, 60), blur="b40", opacity=0.75)
            + glass(stem, tint=("#FFFFFF", "#8F97FF"), strength=1.15)
            + glass(frame, tint=(AMBER_A, AMBER_B), strength=1.9, rule="evenodd", edge=3.2)
            + '</g>')
    return icon(body)

if __name__ == "__main__":
    for k, f in (("a", concept_a), ("b", concept_b)):
        open(f"{k}-icon.svg", "w").write(f())

# ---------- exploded layers (transparent, for the construction panel)
def _layer(inner):
    f = ''.join(f'<filter id="b{k}" filterUnits="userSpaceOnUse" x="-600" y="-600" width="2200" height="2200"><feGaussianBlur stdDeviation="{k}"/></filter>' for k in (6,10,14,28,40))
    return f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024" width="1024" height="1024"><defs>{f}</defs>{inner}</svg>'

def _bg():
    return (f'<defs><linearGradient id="bgl" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="{BG_TOP}"/><stop offset="1" stop-color="{BG_BOT}"/></linearGradient></defs>'
            f'<path d="{rrect(100,100,824,824,186)}" fill="url(#bgl)"/>')

def layers_a():
    stem = rrect(300, 190, 230, 560, 52); frame = rrect(410, 190, 380, 360, 76) + rrect(480, 262, 240, 216, 36)
    tr = 'transform="translate(-33 36)"'
    return [("background", _bg()),
            ("light", f'<g {tr}>' + glow(rrect(520, 200, 260, 340, 60), blur="b40", opacity=0.75) + '</g>'),
            ("window", f'<g {tr}>' + glass(stem, tint=("#FFFFFF", "#8F97FF"), strength=1.15) + '</g>'),
            ("focus", f'<g {tr}>' + glass(frame, tint=(AMBER_A, AMBER_B), strength=1.9, rule="evenodd", edge=3.2) + '</g>')]

def layers_b():
    n = next(_ids)
    crisp = (f'<defs><linearGradient id="cl{n}" x1="0" y1="1" x2="1" y2="0"><stop offset="0" stop-color="{AMBER_B}"/><stop offset="1" stop-color="{AMBER_A}"/></linearGradient></defs>'
             f'<path d="M28 176H92V130H156V84H228" fill="none" stroke="url(#cl{n})" stroke-width="17"/>')
    return [("background", _bg()),
            ("light", f'<g {T}>' + glow(SEAM, blur="b14", opacity=0.9, stroke=60) + glow(SEAM, blur="b6", opacity=1, stroke=30) + crisp + '</g>'),
            ("lower step", f'<g {T}>' + glass(LO, tint=("#FFFFFF", "#8F97FF"), strength=1.35, edge=1.5, sb="b10", dy=9) + '</g>'),
            ("upper step", f'<g {T}>' + glass(UP, tint=("#FFFFFF", "#C4C8FF"), strength=1.5, edge=1.5, sb="b10", dy=9) + '</g>')]

if __name__ == "__main__":
    for k, f in (("a", layers_a), ("b", layers_b)):
        for i, (name, inner) in enumerate(f()):
            open(f"layer-{k}{i}.svg", "w").write(_layer(inner))
