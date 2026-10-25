"""Flat artwork for the Raised Platform: Icon Composer layers (no filters) and the menu-bar template."""
import math
def rr_pts(x, y, w, h, r, n=24):
    """Sample the boundary of a rounded rectangle (corner arcs, n steps each)."""
    pts = []
    for cx, cy, a0 in ((x+w-r, y+r, -90), (x+w-r, y+h-r, 0), (x+r, y+h-r, 90), (x+r, y+r, 180)):
        for i in range(n+1):
            a = math.radians(a0 + 90*i/n); pts.append((cx + r*math.cos(a), cy + r*math.sin(a)))
    return pts
def iso(pts, cx, cy, sy=0.58):
    """Rotate 45 degrees, squash vertically, move to (cx, cy): a rounded square seen from above."""
    c, s = math.cos(math.radians(45)), math.sin(math.radians(45))
    return [(cx + (px*c - py*s), cy + (px*s + py*c)*sy) for px, py in pts]
def hull(points):
    pts = sorted(set((round(x, 2), round(y, 2)) for x, y in points))
    def cross(o, a, b): return (a[0]-o[0])*(b[1]-o[1]) - (a[1]-o[1])*(b[0]-o[0])
    lo = []
    for p in pts:
        while len(lo) >= 2 and cross(lo[-2], lo[-1], p) <= 0: lo.pop()
        lo.append(p)
    up = []
    for p in reversed(pts):
        while len(up) >= 2 and cross(up[-2], up[-1], p) <= 0: up.pop()
        up.append(p)
    return lo[:-1] + up[:-1]
def path(pts): return "M" + "L".join(f"{x:.1f} {y:.1f}" for x, y in pts) + "Z"
def tier(cx, cy, size, r, t, sy=0.58):
    top = iso(rr_pts(-size/2, -size/2, size, size, r), cx, cy, sy)
    body = hull(top + [(x, y+t) for x, y in top])          # the slab: top face swept down by its thickness
    return path(top), path(body)

# tiers as in the approved icon (1024 canvas, group offset +10)
TIERS = [(512, 650, 470, 64, 70), (512, 540, 330, 52, 70), (512, 430, 200, 42, 70)]
def svg(inner): return f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024" width="1024" height="1024">{inner}</svg>'
def flat_layers(out):
    bg = ('<defs><linearGradient id="bg" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#2B2E5A"/>'
          '<stop offset="1" stop-color="#0A0B1B"/></linearGradient></defs><rect width="1024" height="1024" fill="url(#bg)"/>')
    open(f"{out}/0-background.svg", "w").write(svg(bg))
    names = ["1-lower-tier", "2-middle-tier", "3-top-tier-lit"]
    for i, (cx, cy, size, r, t) in enumerate(TIERS):
        top, body = tier(cx, cy, size, r, t)
        if i < 2:
            inner = f'<path d="{body}" fill="#6A72E0" opacity="0.55"/><path d="{top}" fill="#FFFFFF" opacity="0.78"/>'
        else:
            inner = f'<path d="{body}" fill="#FF6A3D" opacity="0.9"/><path d="{top}" fill="#FFB257"/>'
        open(f"{out}/{names[i]}.svg", "w").write(svg(inner))

# menu bar: three slabs, flat black, real gaps between them (masks cut the gap into the slab below)
def menubar(out, size=36):
    sy = 0.5
    specs = [(18, 20.3, 22.6, 4.5, 3.2), (18, 13.5, 14.85, 3.6, 2.6), (18, 7.5, 8.5, 2.6, 2.2)]   # cx, cy, side, r, thickness
    parts, defs = [], []
    shapes = [tier(cx, cy, s, r, t, sy) for cx, cy, s, r, t in specs]
    for i, (top, body) in enumerate(shapes):
        mask = ""
        if i < len(shapes) - 1:
            above = shapes[i+1][1]
            defs.append(f'<mask id="m{i}"><rect width="36" height="36" fill="#fff"/><path d="{above}" fill="#000" stroke="#000" stroke-width="2.6" stroke-linejoin="round"/></mask>')
            mask = f' mask="url(#m{i})"'
        parts.append(f'<path d="{body}" fill="#000"{mask}/>')
    s = f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 36 36" width="{size}" height="{size}"><defs>{"".join(defs)}</defs>{"".join(parts)}</svg>'
    open(f"{out}/menubar-template.svg", "w").write(s)

if __name__ == "__main__":
    import sys
    flat_layers(sys.argv[1]); menubar(sys.argv[2])
