#!/usr/bin/env python3
"""Generate placeholder pixel-art sprite sheets for Claude Buddy.

Output: Sources/ClaudeBuddy/Resources/buddy.png (main) and buddy_1..buddy_4.png (tinted clones).
Sheet layout: 32x32 px frames, one animation per row, 4 frames per row (unused frames stay empty).
Row order must match `Pose.row` in Sources/ClaudeBuddy/Model.swift:
  0 idle  1 read  2 type  3 run  4 wait  5 sleep  6 oops  7 wave  8 spawn
Replace these PNGs with your own art as long as you keep the same grid.
"""
import struct, zlib, os, sys

FRAME = 32
COLS = 4

# ---- palette (letter -> RGBA) -------------------------------------------------
def rgb(h, a=255):
    h = h.lstrip('#'); return (int(h[0:2],16), int(h[2:4],16), int(h[4:6],16), a)

BASE = {
    '.': (0,0,0,0),
    'o': rgb('2b2118'),   # outline
    's': rgb('f2c9a0'),   # skin
    'S': rgb('d9a274'),   # skin shadow
    'e': rgb('1a1a1a'),   # eye
    'w': rgb('ffffff'),   # eye white / highlights
    'h': rgb('e8734a'),   # hoodie
    'H': rgb('c4552f'),   # hoodie shadow
    'p': rgb('3b4a6b'),   # pants
    'P': rgb('2a3650'),   # pants shadow
    'b': rgb('4a90d9'),   # book cover
    'B': rgb('f7f3e8'),   # page
    'k': rgb('6b7280'),   # laptop body
    'K': rgb('111827'),   # laptop screen
    'g': rgb('22c55e'),   # terminal green
    'd': rgb('60a5fa'),   # sweat drop
    'y': rgb('facc15'),   # sparkle
    'z': rgb('94a3b8'),   # zzz / sleepy grey
}
# hoodie tints for subagent clones (h, H)
TINTS = [
    ('e8734a', 'c4552f'),  # 0 main: coral
    ('2dd4bf', '14958a'),  # 1 teal
    ('a78bfa', '7c5cd6'),  # 2 violet
    ('4ade80', '22a352'),  # 3 green
    ('60a5fa', '3b7fd6'),  # 4 blue
]

# ---- drawing helpers ------------------------------------------------------------
class Frame:
    def __init__(self):
        self.px = [['.']*FRAME for _ in range(FRAME)]
    def blit(self, art, x, y):
        for j, row in enumerate(art):
            for i, ch in enumerate(row):
                if ch == '.': continue
                xx, yy = x+i, y+j
                if 0 <= xx < FRAME and 0 <= yy < FRAME:
                    self.px[yy][xx] = ch
    def put(self, x, y, ch):
        if 0 <= x < FRAME and 0 <= y < FRAME: self.px[y][x] = ch

# Character origin: (10, 10) -> body is 12 wide, 21 tall, feet on row 30.
OX, OY = 10, 10

HEAD_OPEN = [
    "....oooo....",
    "...ohhhho...",
    "..ohhhhhho..",
    "..ohssssho..",
    "..oseSSeso..",
    "..osssssso..",
    "..ohSssSho..",
    "...ohhhho...",
]
HEAD_BLINK = HEAD_OPEN[:4] + ["..osoSSoso.."] + HEAD_OPEN[5:]
HEAD_DOWN  = HEAD_OPEN[:4] + ["..osssssso..", "..oSeSSeSo.."] + HEAD_OPEN[6:]   # looking down
HEAD_WIDE  = HEAD_OPEN[:4] + ["..owewweo...".replace("o...", "wo..")] + HEAD_OPEN[5:]  # startled
HEAD_HAPPY = HEAD_OPEN[:4] + ["..oseSSeso..", "..oSsSSsSo.."] + HEAD_OPEN[6:]
HEAD_SLEEP = HEAD_OPEN[:4] + ["..oSsSSsSo.."] + HEAD_OPEN[5:]

TORSO = [               # rows 8..13 relative to origin (arms drawn separately)
    "..ohhhhhho..",
    "..ohhhhhho..",
    "..ohhhhhho..",
    "..oHhhhhHo..",
    "..oHhhhhHo..",
    "..ohhhhhho..",
]
LEGS = [
    "..oppppppo..",
    "..oppPPppo..",
    "..opp..ppo..",
    "..opp..ppo..",
    "..oPP..PPo..",
    "..ooo..ooo..",
]
# arms: drawn as columns at x=1 (left) and x=10 (right), rows relative to origin
def arms_down(f, x, y):
    for j in range(9, 14):
        f.put(x+1, y+j, 'o' if j == 13 else 'h'); f.put(x+10, y+j, 'o' if j == 13 else 'h')
    f.put(x+1, y+13, 's'); f.put(x+10, y+13, 's')
    f.put(x+0, y+9, 'o'); f.put(x+11, y+9, 'o')
    for j in range(9, 13): f.put(x+0, y+j, 'o'); f.put(x+11, y+j, 'o')
    f.put(x+0, y+13, 'o'); f.put(x+11, y+13, 'o')
    f.put(x+1, y+14, 'o'); f.put(x+10, y+14, 'o')

def arm_up(f, x, y, side):  # side -1 left, +1 right
    col = x+1 if side < 0 else x+10
    for j in range(4, 10): f.put(col, y+j, 'h')
    f.put(col, y+3, 's'); f.put(col, y+2, 'o')
    outer = col-1 if side < 0 else col+1
    for j in range(2, 10): f.put(outer, y+j, 'o')

def arms_forward(f, x, y, row):  # both arms pointing forward/down at `row`
    for i in (1, 2, 9, 10): f.put(x+i, y+row, 'h')
    f.put(x+2, y+row+1, 's'); f.put(x+9, y+row+1, 's')
    f.put(x+0, y+row, 'o'); f.put(x+11, y+row, 'o')
    for i in range(0, 12): f.put(x+i, y+row-1, f.px[y+row-1][x+i] if f.px[y+row-1][x+i] != '.' else '.')

def arms_out(f, x, y):  # arms spread to the sides
    for i in range(-2, 2): f.put(x+i, y+10, 'h')
    for i in range(10, 14): f.put(x+i, y+10, 'h')
    f.put(x-3, y+10, 's'); f.put(x+14, y+10, 's')
    for i in range(-3, 2): f.put(x+i, y+9, 'o'); f.put(x+i, y+11, 'o')
    for i in range(10, 15): f.put(x+i, y+9, 'o'); f.put(x+i, y+11, 'o')

def body(f, head, y_off=0, arms='down'):
    x, y = OX, OY + y_off
    f.blit(head, x, y)
    f.blit(TORSO, x, y+8)
    f.blit(LEGS, x, y+14 - 0)
    if arms == 'down': arms_down(f, x, y)
    elif arms == 'up_right': arms_down(f, x, y); arm_up(f, x, y, +1)
    elif arms == 'forward': arms_forward(f, x, y, 12)
    elif arms == 'out': arms_out(f, x, y)
    elif arms == 'none': pass

def book(f, flip):
    art = [
        "obbbbbbbbo",
        "oBBBBoBBBo",
        "oBBBBoBBBo",
        "oBBBBoBBBo",
        "oooooooooo",
    ] if not flip else [
        "obbbbbbbbo",
        "oBBBoBBBBo",
        "oBBBoBBBBo",
        "oBBBoBBBBo",
        "oooooooooo",
    ]
    f.blit(art, OX+1, OY+9)

def laptop(f, cursor):
    scr = [
        "okkkkkkkkkko",
        "okKKKKKKKKko",
        "okKgKKKKKKko" if cursor else "okKggKKKKKko",
        "okKKKKKKKKko",
        "okkkkkkkkkko",
        "ookkkkkkkkoo",
    ]
    f.blit(scr, OX, OY+16)

def terminal(f, tick):
    box = [
        "oooooooooo",
        "oKKKKKKKKo",
        "oKgggKKKKo",
        "oKgKKKKKKo" if tick else "oKggKKKKKo",
        "oKKKKKKKKo",
        "oooooooooo",
    ]
    f.blit(box, 21, 1)

def sparkles(f, phase):
    pts = [(4,6),(27,8),(6,22),(26,24)] if phase == 0 else [(5,12),(26,4),(3,26),(28,18)]
    for (x, y) in pts:
        f.put(x, y, 'y'); f.put(x-1, y, 'y'); f.put(x+1, y, 'y'); f.put(x, y-1, 'y'); f.put(x, y+1, 'y')

def sweat(f, phase):
    x, y = OX+11, OY+3 + phase
    f.put(x, y, 'd'); f.put(x, y+1, 'd'); f.put(x-1, y+1, 'd'); f.put(x, y+2, 'd')

def zzz(f, phase):
    x, y = OX+12, OY-1 - phase
    for (dx, dy) in [(0,0),(1,0),(2,0),(1,1),(0,2),(1,2),(2,2)]: f.put(x+dx, y+dy, 'z')

# ---- animations -----------------------------------------------------------------
def make_frames():
    rows = []
    # 0 idle: bob + blink
    a = Frame(); body(a, HEAD_OPEN)
    b = Frame(); body(b, HEAD_OPEN, y_off=1)
    c = Frame(); body(c, HEAD_OPEN)
    d = Frame(); body(d, HEAD_BLINK)
    rows.append([a, b, c, d])
    # 1 read
    a = Frame(); body(a, HEAD_DOWN, arms='forward'); book(a, False)
    b = Frame(); body(b, HEAD_DOWN, arms='forward'); book(b, True)
    rows.append([a, b])
    # 2 type
    a = Frame(); body(a, HEAD_DOWN, arms='forward'); laptop(a, True)
    b = Frame(); body(b, HEAD_DOWN, y_off=1, arms='forward'); laptop(b, False)
    rows.append([a, b])
    # 3 run (terminal)
    a = Frame(); body(a, HEAD_OPEN); terminal(a, True)
    b = Frame(); body(b, HEAD_OPEN, y_off=1); terminal(b, False)
    rows.append([a, b])
    # 4 wait (hand raised)
    a = Frame(); body(a, HEAD_OPEN, arms='up_right')
    b = Frame(); body(b, HEAD_OPEN, y_off=1, arms='up_right')
    rows.append([a, b])
    # 5 sleep
    a = Frame(); body(a, HEAD_SLEEP, y_off=1); zzz(a, 0)
    b = Frame(); body(b, HEAD_SLEEP, y_off=1); zzz(b, 1)
    rows.append([a, b])
    # 6 oops
    a = Frame(); body(a, HEAD_WIDE, arms='out'); sweat(a, 0)
    b = Frame(); body(b, HEAD_WIDE, y_off=1, arms='out'); sweat(b, 1)
    rows.append([a, b])
    # 7 wave
    a = Frame(); body(a, HEAD_HAPPY, arms='up_right')
    b = Frame(); body(b, HEAD_HAPPY, y_off=1, arms='up_right'); b.put(OX+12, OY+3, 's'); b.put(OX+12, OY+2, 'o')
    rows.append([a, b])
    # 8 spawn
    a = Frame(); body(a, HEAD_HAPPY, arms='out'); sparkles(a, 0)
    b = Frame(); body(b, HEAD_HAPPY, y_off=1, arms='out'); sparkles(b, 1)
    rows.append([a, b])
    return rows

# ---- PNG writer -----------------------------------------------------------------
def write_png(path, width, height, pixels):
    raw = b''.join(b'\x00' + bytes(v for px in row for v in px) for row in pixels)
    def chunk(t, d): return struct.pack('>I', len(d)) + t + d + struct.pack('>I', zlib.crc32(t + d) & 0xffffffff)
    png = b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', width, height, 8, 6, 0, 0, 0))
    png += chunk(b'IDAT', zlib.compress(raw, 9)) + chunk(b'IEND', b'')
    with open(path, 'wb') as fh: fh.write(png)

def render_sheet(rows, palette):
    W, H = FRAME*COLS, FRAME*len(rows)
    out = [[(0,0,0,0)]*W for _ in range(H)]
    for r, frames in enumerate(rows):
        for c, fr in enumerate(frames):
            for y in range(FRAME):
                for x in range(FRAME):
                    out[r*FRAME+y][c*FRAME+x] = palette[fr.px[y][x]]
    return W, H, out

def main():
    here = os.path.dirname(os.path.abspath(__file__))
    outdir = os.path.join(here, '..', 'Sources', 'ClaudeBuddy', 'Resources')
    os.makedirs(outdir, exist_ok=True)
    rows = make_frames()
    for i, (h, H) in enumerate(TINTS):
        pal = dict(BASE); pal['h'] = rgb(h); pal['H'] = rgb(H)
        W, Hh, px = render_sheet(rows, pal)
        name = 'buddy.png' if i == 0 else f'buddy_{i}.png'
        write_png(os.path.join(outdir, name), W, Hh, px)
        print(f'wrote {name} ({W}x{Hh})')
    # ascii preview of frame 0 for a quick sanity check
    if '--preview' in sys.argv:
        for row in rows:
            for fr in row:
                print('\n'.join(''.join(r) for r in fr.px)); print()

if __name__ == '__main__':
    main()
