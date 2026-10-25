from glass import *

def rpoly(pts, r):
    import math
    n=len(pts); out=[]
    for i in range(n):
        p0,p1,p2=pts[i-1],pts[i],pts[(i+1)%n]
        def u(a,b):
            dx,dy=b[0]-a[0],b[1]-a[1]; l=math.hypot(dx,dy); return dx/l,dy/l,l
        ax,ay,l1=u(p1,p0); bx,by,l2=u(p1,p2)
        ang=math.acos(max(-1,min(1,ax*bx+ay*by))); t=min(r/math.tan(ang/2),l1/2,l2/2); rr=t*math.tan(ang/2)
        a=(p1[0]+ax*t,p1[1]+ay*t); b=(p1[0]+bx*t,p1[1]+by*t)
        cross=(p1[0]-p0[0])*(p2[1]-p1[1])-(p1[1]-p0[1])*(p2[0]-p1[0])
        out.append((a,b,rr,1 if cross>0 else 0))
    d="M%.1f %.1f"%out[0][0]
    for i,(a,b,rr,sw) in enumerate(out):
        if i: d+="L%.1f %.1f"%a
        d+="A%.1f %.1f 0 0 %d %.1f %.1f"%(rr,rr,sw,b[0],b[1])
    return d+"Z"

# 1. Winners' stand: three glass blocks, the middle one in focus
def stand():
    base=770
    L=rrect(190,base-300,190,300,46); M=rrect(417,base-430,190,430,46); R=rrect(644,base-210,190,210,46)
    cap=rrect(417,base-430,190,430,46)
    body=(glow(rrect(430,base-440,164,200,50),blur="b40",opacity=0.85)
          +glass(L,tint=("#FFFFFF","#8F97FF"),strength=1.2)
          +glass(R,tint=("#FFFFFF","#8F97FF"),strength=1.2)
          +glass(M,tint=(AMBER_A,AMBER_B),strength=1.9,edge=3.2))
    return icon('<g transform="translate(0 -20)">'+body+'</g>')

# 2. Lectern: lit slanted top on a tapered column and a base slab
def lectern():
    desk=rpoly([(270,468),(752,380),(752,452),(270,540)],34)
    col=rpoly([(410,536),(612,500),(590,742),(432,742)],26)
    base=rrect(250,738,524,70,35)
    body=(glow(rpoly([(300,470),(730,392),(730,440),(300,520)],30),blur="b40",opacity=0.95)
          +glass(base,tint=("#FFFFFF","#8F97FF"),strength=1.1)
          +glass(col,tint=("#FFFFFF","#8F97FF"),strength=1.25)
          +glass(desk,tint=(AMBER_A,AMBER_B),strength=1.9,edge=3.2))
    return icon('<g transform="translate(0 -6)">'+body+'</g>')

# 3. Raised platform: three isometric glass tiers, the top one lit
def tiers():
    def tier(cy, size, r, t, tint, strength, lit=False):
        sk=f'translate(512 {cy}) scale(1 0.58) rotate(45)'
        d=rrect(-size/2,-size/2,size,size,r)
        side=''.join(f'<g transform="translate(512 {cy+dy}) scale(1 0.58) rotate(45)"><path d="{d}" fill="{"#6A5BA0" if lit else "#3A3F7A"}" opacity="0.55"/></g>' for dy in range(t,0,-3))
        top=f'<g transform="{sk}">'+glass(d,tint=tint,strength=strength,shadow=False,edge=3)+'</g>'
        return side+top
    body=''
    body+=f'<g transform="translate(512 760) scale(1 0.58) rotate(45)"><path d="{rrect(-250,-250,500,500,70)}" fill="#000" opacity="0.5" filter="url(#b28)"/></g>'
    body+=tier(640,470,64,70,("#FFFFFF","#8F97FF"),1.2)
    body+=tier(530,330,52,70,("#FFFFFF","#8F97FF"),1.3)
    body+=glow(rrect(-90,-90,180,180,36).replace('M','M'),blur="b40",opacity=0.0)
    body+=f'<g transform="translate(512 430) scale(1 0.58) rotate(45)">'+glow(rrect(-110,-110,220,220,40),blur="b40",opacity=0.95)+'</g>'
    body+=tier(420,200,42,70,(AMBER_A,AMBER_B),1.9,lit=True)
    return icon('<g transform="translate(0 10)">'+body+'</g>')

if __name__=="__main__":
    for k,f in (("p1",stand),("p2",lectern),("p3",tiers)):
        open(f"{k}-icon.svg","w").write(f())

# 1b. Winners' stand as 3D glass blocks (oblique view) with the window in focus standing on the middle block
def stand3d():
    DX, DY, bottom = 52, 46, 800
    def box(x, w, h, tint, strength, shade_side=True):
        top_y = bottom - h
        front = rrect(x, top_y, w, h, 30)
        topf = rpoly([(x+10, top_y), (x+w-10, top_y), (x+w-10+DX, top_y-DY), (x+10+DX, top_y-DY)], 10)
        side = rpoly([(x+w, top_y+14), (x+w+DX, top_y+14-DY), (x+w+DX, bottom-30-DY), (x+w, bottom-14)], 10)
        return (glass(side, tint=("#B6BBFF", "#5A63D8"), strength=strength*0.9, shadow=False, edge=2)
                + glass(topf, tint=("#FFFFFF", "#DDE0FF"), strength=strength*1.1, shadow=False, edge=2)
                + glass(front, tint=tint, strength=strength, shadow=True, edge=3))
    cool = ("#FFFFFF", "#8F97FF")
    pane = rrect(424, 118, 168, 214, 46) + rrect(466, 164, 84, 122, 22)
    body = (box(634, 170, 200, cool, 1.15) + box(174, 170, 290, cool, 1.15) + box(404, 170, 420, cool, 1.35)
            + glow(rrect(440, 130, 136, 190, 40), blur="b40", opacity=0.9)
            + glass(pane, tint=(AMBER_A, AMBER_B), strength=2.0, edge=3.2, rule="evenodd"))
    return icon('<g transform="translate(52 66) scale(0.9)">' + body + '</g>')

if __name__ == "__main__":
    open("p4-icon.svg", "w").write(stand3d())
