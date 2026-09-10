#!/usr/bin/env python3
"""Generate placeholder pixel-art sprite sheets for Claude Buddy.

Output: Sources/ClaudeBuddy/Resources/buddy.png (main) and buddy_1..buddy_4.png (tinted clones).
Sheet layout: 32x32 px frames, 4 columns, one animation per row (unused frames stay empty).
Rows come in FAT_LEVELS blocks of 16: block 0 is the normal body, each further block is a wider one
(used as the agent's context window fills up; level 2 is sweaty, level 3 dizzy and sweaty).
Within a block the row order must match `Pose` in Sources/ClaudeBuddy/Model.swift:
  0 idle  1 read  2 type(desk)  3 run  4 wait  5 sleep  6 oops  7 wave  8 spawn  9 eat  10 mine
  11 coffee  12 dance  13 stretch  14 juggle  15 think
Replace these PNGs with your own art as long as you keep the same grid.
"""
import struct, zlib, os, sys

FRAME = 32
COLS = 4
FAT_LEVELS = [0, 2, 4, 6]      # extra body width in px per level
CONDITIONS = ['fine', 'fine', 'sweaty', 'dizzy']   # per fat level: dizzy implies sweaty

def rgb(h, a=255):
    h = h.lstrip('#'); return (int(h[0:2],16), int(h[2:4],16), int(h[4:6],16), a)

BASE = {
    '.': (0,0,0,0),
    'o': rgb('2b2118'),   # outline
    's': rgb('f2c9a0'),   # skin
    'S': rgb('d9a274'),   # skin shadow
    'e': rgb('1a1a1a'),   # eye
    'w': rgb('ffffff'),   # eye white
    'h': rgb('e8734a'),   # hoodie
    'H': rgb('c4552f'),   # hoodie shadow
    'p': rgb('3b4a6b'),   # pants
    'P': rgb('2a3650'),   # pants shadow
    'b': rgb('4a90d9'),   # book cover
    'B': rgb('f7f3e8'),   # page
    'k': rgb('6b7280'),   # laptop body
    'K': rgb('111827'),   # screen
    'g': rgb('22c55e'),   # terminal green
    'd': rgb('60a5fa'),   # sweat drop
    'y': rgb('facc15'),   # sparkle
    'z': rgb('94a3b8'),   # zzz
    'c': rgb('c98b4b'),   # cookie
    'C': rgb('5a3a1a'),   # chocolate chips
    'r': rgb('8b8f99'),   # rock
    'R': rgb('5b5f69'),   # rock shadow
    'x': rgb('8a5a2b'),   # pickaxe handle
    'X': rgb('cbd5e1'),   # pickaxe head
    'G': rgb('f7931a'),   # bitcoin nugget
    'M': rgb('6b3e1e'),   # coffee
    'n': rgb('f472b6'),   # music note
}
TINTS = [
    ('e8734a', 'c4552f'),  # 0 main: coral
    ('2dd4bf', '14958a'),  # 1 teal
    ('a78bfa', '7c5cd6'),  # 2 violet
    ('4ade80', '22a352'),  # 3 green
    ('60a5fa', '3b7fd6'),  # 4 blue
]

class Frame:
    def __init__(self):
        self.px = [['.']*FRAME for _ in range(FRAME)]
    def blit(self, art, x, y):
        for j, row in enumerate(art):
            for i, ch in enumerate(row):
                if ch != '.': self.put(x+i, y+j, ch)
    def put(self, x, y, ch):
        if 0 <= x < FRAME and 0 <= y < FRAME: self.px[y][x] = ch

def widen(art, extra):
    """Insert `extra` copies of the middle column so the shape gets fatter but keeps its outline."""
    out = []
    for row in art:
        mid = len(row) // 2
        out.append(row[:mid] + row[mid] * extra + row[mid:])
    return out

# Base character is 12 wide, 20 tall. Origin x is recomputed per width so it stays centred.
BASE_W = 12
OY = 10

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
def head_variant(row4=None, row5=None):
    h = list(HEAD_OPEN)
    if row4: h[4] = row4
    if row5: h[5] = row5
    return h
HEAD_BLINK = head_variant("..osoSSoso..")
HEAD_DOWN  = head_variant("..osssssso..", "..oSeSSeSo..")
HEAD_WIDE  = head_variant("..owewwewo..")
HEAD_HAPPY = head_variant("..oseSSeso..", "..oSsSSsSo..")
HEAD_SLEEP = head_variant("..oSsSSsSo..")
HEAD_YAWN  = head_variant("..oSsSSsSo..")
HEAD_YAWN[6] = "..ohSeeSho.."           # closed eyes, mouth wide open
HEAD_DIZZY = head_variant("..oweSSewo..", "..oewSSweo..")   # swirly two-tone eyes

TORSO = [
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

class Body:
    """Draws the character at a given extra width. All arm/prop positions derive from W."""
    def __init__(self, extra, condition='fine'):
        self.extra = extra
        self.condition = condition
        self.W = BASE_W + extra
        self.ox = (FRAME - self.W) // 2
        self.head = {k: widen(v, extra) for k, v in dict(open=HEAD_OPEN, blink=HEAD_BLINK, down=HEAD_DOWN,
                                                          wide=HEAD_WIDE, happy=HEAD_HAPPY, sleep=HEAD_SLEEP,
                                                          yawn=HEAD_YAWN, dizzy=HEAD_DIZZY).items()}
        self.torso = widen(TORSO, extra)
        self.legs = widen(LEGS, extra)

    # column helpers: left arm at x+1, right arm at x+W-2
    def L(self): return self.ox + 1
    def R(self): return self.ox + self.W - 2

    def arms_down(self, f, y):
        for col, outer in ((self.L(), self.L()-1), (self.R(), self.R()+1)):
            for j in range(9, 13): f.put(col, y+j, 'h'); f.put(outer, y+j, 'o')
            f.put(col, y+13, 's'); f.put(outer, y+13, 'o'); f.put(col, y+14, 'o'); f.put(outer, y+9, 'o')

    def arm_up(self, f, y, side):
        col = self.L() if side < 0 else self.R()
        outer = col-1 if side < 0 else col+1
        for j in range(4, 10): f.put(col, y+j, 'h')
        f.put(col, y+3, 's'); f.put(col, y+2, 'o')
        for j in range(2, 10): f.put(outer, y+j, 'o')

    def arms_forward(self, f, y, row):
        for col in (self.L(), self.L()+1, self.R()-1, self.R()): f.put(col, y+row, 'h')
        f.put(self.L()+1, y+row+1, 's'); f.put(self.R()-1, y+row+1, 's')
        f.put(self.L()-1, y+row, 'o'); f.put(self.R()+1, y+row, 'o')

    def arms_out(self, f, y):
        for i in range(self.L()-3, self.L()+1): f.put(i, y+10, 'h')
        for i in range(self.R(), self.R()+4): f.put(i, y+10, 'h')
        f.put(self.L()-4, y+10, 's'); f.put(self.R()+4, y+10, 's')
        for i in range(self.L()-4, self.L()+1): f.put(i, y+9, 'o'); f.put(i, y+11, 'o')
        for i in range(self.R(), self.R()+5): f.put(i, y+9, 'o'); f.put(i, y+11, 'o')

    def draw(self, f, head='open', y_off=0, arms='down', x_off=0):
        # Too much context: the character is dizzy (and sweaty) no matter what it is doing.
        if self.condition == 'dizzy' and head != 'sleep': head = 'dizzy'
        self.ox += x_off
        x, y = self.ox, OY + y_off
        f.blit(self.head[head], x, y)
        f.blit(self.torso, x, y+8)
        f.blit(self.legs, x, y+14)
        if arms == 'down': self.arms_down(f, y)
        elif arms == 'up_right': self.arms_down(f, y); self.arm_up(f, y, +1)
        elif arms == 'up_both': self.arm_up(f, y, -1); self.arm_up(f, y, +1)
        elif arms == 'forward': self.arms_forward(f, y, 12)
        elif arms == 'out': self.arms_out(f, y)
        elif arms == 'eat': self.arms_eat(f, y)
        elif arms == 'chin': self.arms_down(f, y); self.arm_chin(f, y)
        self.ox -= x_off
        self.last_x_off = x_off

    def sweat_overlay(self, f, i):
        """Animated sweat, added to frame `i` of every row: two drops when sweaty, a shower when dizzy."""
        if self.condition == 'fine': return
        xo = getattr(self, 'last_x_off', 0)
        L, R = self.ox + xo - 1, self.ox + xo + self.W
        cx = self.ox + xo + self.W // 2
        drops = [(L, OY + 2, 0), (R, OY + 3, 2)]
        if self.condition == 'dizzy':
            drops += [(L - 2, OY + 6, 1), (R + 2, OY + 7, 3), (cx - 3, OY - 3, 2), (cx + 3, OY - 4, 0), (L - 1, OY + 11, 3)]
        for (x, y0, ph) in drops:
            y = y0 + (i + ph) % 4          # each drop falls one pixel per frame, then starts over
            f.put(x, y, 'd'); f.put(x, y + 1, 'd')

    # props, positioned relative to the body
    def book(self, f, flip):
        art = ["obbbbbbbbo", "oBBBBoBBBo", "oBBBBoBBBo", "oBBBBoBBBo", "oooooooooo"] if not flip else \
              ["obbbbbbbbo", "oBBBoBBBBo", "oBBBoBBBBo", "oBBBoBBBBo", "oooooooooo"]
        art = widen(art, self.extra)
        f.blit(art, self.ox+1, OY+9)

    def laptop(self, f, cursor):
        scr = ["okkkkkkkkkko", "okKKKKKKKKko", "okKgKKKKKKko" if cursor else "okKggKKKKKko",
               "okKKKKKKKKko", "okkkkkkkkkko", "ookkkkkkkkoo"]
        f.blit(widen(scr, self.extra), self.ox, OY+16)

    def desk(self, f, phase):
        """Sitting at a desk: chair behind, keyboard in front, monitor on the right with code being typed."""
        y = OY + 1
        # chair: backrest peeking out above the shoulders and on both sides of the torso
        for i in range(self.ox + 1, self.ox + self.W - 1): f.put(i, y + 7, 'P')
        for j in range(7, 13): f.put(self.ox, y + j, 'P'); f.put(self.ox + self.W - 1, y + j, 'P')
        # desk top spanning the whole frame, with the monitor standing on it
        left, right = 1, FRAME - 2
        for i in range(left, right + 1): f.put(i, y + 13, 'x'); f.put(i, y + 14, 'C')
        for j in range(15, 20): f.put(left + 1, y + j, 'C'); f.put(right - 1, y + j, 'C')
        # keyboard in front of the character
        for i in range(self.L(), self.R() + 1): f.put(i, y + 12, 'k')
        # hands on the keys, alternating which one is lifted
        lh, rh = (0, 1) if phase % 2 == 0 else (1, 0)
        f.put(self.L() + 1, y + 11 - lh, 's'); f.put(self.L() + 2, y + 11 - lh, 's')
        f.put(self.R() - 2, y + 11 - rh, 's'); f.put(self.R() - 1, y + 11 - rh, 's')
        # monitor: kept inside the frame even for the widest bodies
        mx = min(self.R() + 3, FRAME - 9)
        my = y + 4
        f.blit(["ooooooooo", "oKKKKKKKo", "oKKKKKKKo", "oKKKKKKKo", "oKKKKKKKo", "ooooooooo", "...oko...", "..ooooo.."], mx, my)
        lines = [[3, 0, 0, 0], [3, 2, 0, 0], [3, 2, 4, 0], [3, 2, 4, 1]][phase % 4]
        for r, n in enumerate(lines):
            for i in range(n): f.put(mx + 1 + i, my + 1 + r, 'g' if (r + i) % 3 else 'd')
        if phase % 2 == 0:
            r = max(k for k, n in enumerate(lines) if n)
            f.put(mx + 1 + lines[r], my + 1 + r, 'B')          # blinking cursor

    def arm_chin(self, f, y):
        """Right arm bent up, hand resting on the chin."""
        col, outer = self.R(), self.R() + 1
        for j in range(8, 13): f.put(col, y + j, 'h'); f.put(outer, y + j, 'o')
        f.put(col, y + 13, 'o'); f.put(outer, y + 13, 'o')
        f.put(col, y + 7, 's'); f.put(col - 1, y + 7, 's'); f.put(outer, y + 7, 'o')
        f.put(col, y + 6, 'o'); f.put(col - 1, y + 6, 'o')

    def thought(self, f, phase):
        """Thought dots rising from the head, then a little cloud."""
        x = self.ox + self.W
        dots = [(x, OY), (x + 1, OY - 2), (x + 2, OY - 4)]
        for k in range(min(phase + 1, 3)): f.put(*dots[k], 'z')
        if phase >= 3:
            f.blit([".zzz.", "zzzzz", ".zzz."], x + 2, OY - 8)

    def sweat(self, f, phase, side=+1):
        x, y = (self.ox + self.W - 1 if side > 0 else self.ox), OY + 3 + phase
        x2 = x - 1 if side > 0 else x + 1
        f.put(x, y, 'd'); f.put(x, y+1, 'd'); f.put(x2, y+1, 'd'); f.put(x, y+2, 'd')


    def cookie(self, f, bitten):
        art = [".ccc.", "cCcCc", ".ccC."] if not bitten else ["..cc.", ".cCcc", "..cC."]
        # held just below the mouth so the eyes stay visible
        f.blit(art, self.ox + self.W // 2 - 1, OY + 6)

    def arms_eat(self, f, y):
        # both hands raised to the mouth
        for col, outer in ((self.L(), self.L()-1), (self.R(), self.R()+1)):
            for j in range(8, 13): f.put(col, y+j, 'h'); f.put(outer, y+j, 'o')
            f.put(outer, y+7, 'o'); f.put(col, y+7, 's'); f.put(col, y+13, 'o'); f.put(outer, y+13, 'o')
        # forearms towards the centre at row 7, hands next to the cookie
        for i in range(self.L()+1, self.ox + self.W // 2 - 1): f.put(i, y+7, 's'); f.put(i, y+6, 'o'); f.put(i, y+8, 'o')
        for i in range(self.ox + self.W // 2 + 4, self.R()): f.put(i, y+7, 's'); f.put(i, y+6, 'o'); f.put(i, y+8, 'o')

    def pickaxe(self, f, raised, sparks=False, nugget=False):
        """Old-school mining: both hands on a pickaxe, swinging at a rock on the right."""
        y = OY
        R = self.R()
        # rock on the ground to the right of the character
        rock = ["...rrr...", "..rrrrr..", ".rrrRrrr.", "rrRRrrRRr", "rRrrrrrRr"]
        if nugget: rock = ["...rrr...", "..rrGrr..", ".rrrRGrr.", "rrRRrrRRr", "rRrrrrrRr"]
        f.blit(rock, R + 1, y + 15)
        if raised:
            # handle rises up-right from the hands, pick head at the top
            for (dx, dy) in [(1, 11), (2, 10), (3, 9), (4, 8), (5, 7)]: f.put(R + dx, y + dy, 'x')
            for dx in range(4, 9): f.put(R + dx, y + 6, 'X')
            f.put(R + 4, y + 7, 'X'); f.put(R + 8, y + 7, 'X')
        else:
            # handle slams down-right, pick head buried in the rock
            for (dx, dy) in [(1, 11), (2, 12), (3, 13), (4, 14)]: f.put(R + dx, y + dy, 'x')
            for dx in range(3, 8): f.put(R + dx, y + 15, 'X')
            f.put(R + 3, y + 14, 'X'); f.put(R + 7, y + 14, 'X')
            if sparks:
                for (dx, dy) in [(2, 13), (8, 12), (9, 14), (1, 14)]: f.put(R + dx, y + dy, 'y')

    def mug(self, f, at_mouth, steam):
        """Coffee mug in the right hand: at chest height, or raised to the mouth."""
        art = ["oMMMo", "oBBBo", "oBBBo", ".ooo."] if not at_mouth else ["oBBBo", "oBBBo", "oBBBo", ".ooo."]
        x = self.R() - 1
        y = OY + (11 if not at_mouth else 5)
        f.blit(art, x, y)
        # arm bent up to the mug
        for j in range(9, 12 if not at_mouth else 9): f.put(self.R(), OY + j, 'h')
        if at_mouth:
            for j in range(6, 10): f.put(self.R(), OY + j, 'h'); f.put(self.R() + 1, OY + j, 'o')
            f.put(self.R(), OY + 5, 's')
        # steam
        for dx, dy in ([(1, -2), (3, -3)] if steam == 0 else [(2, -3), (3, -1)]):
            f.put(x + dx, y + dy, 'z')

    def headphones(self, f, y_off=0, x_off=0):
        x, y = self.ox + x_off, OY + y_off
        for i in range(3, self.W - 3): f.put(x + i, y - 1, 'k')
        f.put(x + 2, y, 'k'); f.put(x + self.W - 3, y, 'k')
        for j in range(3, 6): f.put(x + 1, y + j, 'k'); f.put(x + self.W - 2, y + j, 'k')
        f.put(x + 1, y + 2, 'o'); f.put(x + self.W - 2, y + 2, 'o'); f.put(x + 1, y + 6, 'o'); f.put(x + self.W - 2, y + 6, 'o')

    def notes(self, f, phase):
        note = [".n", ".n", "nn"]
        if phase == 0:
            f.blit(note, self.ox - 4, OY + 2); f.blit(note, self.ox + self.W + 2, OY + 5)
        else:
            f.blit(note, self.ox - 3, OY + 5); f.blit(note, self.ox + self.W + 3, OY + 1)

    def balls(self, f, phase):
        """Three balls juggled in an arc above the head; `phase` rotates them."""
        cx = self.ox + self.W // 2
        arc = [(cx - 5, OY + 4), (cx - 3, OY - 1), (cx + 1, OY - 3), (cx + 4, OY + 1), (cx + 5, OY + 6)]
        colors = ['y', 'd', 'c']
        for k, ch in enumerate(colors):
            x, y = arc[(k * 2 + phase) % len(arc)]
            f.put(x, y, ch); f.put(x+1, y, ch); f.put(x, y+1, ch); f.put(x+1, y+1, ch)

    def zzz(self, f, phase):
        x, y = self.ox + self.W, OY - 1 - phase
        for (dx, dy) in [(0,0),(1,0),(2,0),(1,1),(0,2),(1,2),(2,2)]: f.put(x+dx, y+dy, 'z')

def terminal(f, tick):
    box = ["oooooooooo", "oKKKKKKKKo", "oKgggKKKKo", "oKgKKKKKKo" if tick else "oKggKKKKKo", "oKKKKKKKKo", "oooooooooo"]
    f.blit(box, 22, 0)

def sparkles(f, phase):
    pts = [(3,6),(28,8),(4,22),(27,24)] if phase == 0 else [(4,12),(27,4),(2,26),(29,18)]
    for (x, y) in pts:
        for dx, dy in [(0,0),(-1,0),(1,0),(0,-1),(0,1)]: f.put(x+dx, y+dy, 'y')

def make_block(extra, condition='fine'):
    b = Body(extra, condition)
    def fr(**kw):
        f = Frame(); b.draw(f, **kw); return f
    rows = []
    a, c, d = fr(), fr(y_off=1), fr(head='blink');           rows.append([a, c, fr(), d])          # idle
    a, c = fr(head='down', arms='forward'), fr(head='down', arms='forward'); b.book(a, False); b.book(c, True); rows.append([a, c])  # read
    typing = []
    for ph in range(4):
        x = fr(head='down' if ph % 2 == 0 else 'open', y_off=1, arms='forward'); b.desk(x, ph); typing.append(x)
    rows.append(typing)                                                                                   # type
    a, c = fr(), fr(y_off=1); terminal(a, True); terminal(c, False);                rows.append([a, c])  # run
    rows.append([fr(arms='up_right'), fr(y_off=1, arms='up_right')])                                     # wait
    a, c = fr(head='sleep', y_off=1), fr(head='sleep', y_off=1); b.zzz(a, 0); b.zzz(c, 1); rows.append([a, c])  # sleep
    a, c = fr(head='wide', arms='out'), fr(head='wide', y_off=1, arms='out'); b.sweat(a, 0); b.sweat(c, 1); rows.append([a, c])  # oops
    a = fr(head='happy', arms='up_right'); c = fr(head='happy', y_off=1, arms='up_right'); c.put(b.R()+2, OY+4, 's'); c.put(b.R()+2, OY+3, 'o'); rows.append([a, c])  # wave
    a, c = fr(head='happy', arms='out'), fr(head='happy', y_off=1, arms='out'); sparkles(a, 0); sparkles(c, 1); rows.append([a, c])  # spawn
    a = fr(head='happy', arms='eat'); b.cookie(a, False)
    c = fr(head='blink', arms='eat'); b.cookie(c, True)
    d = fr(head='happy', y_off=1, arms='eat'); b.cookie(d, True)
    rows.append([a, c, d])                                                                                # eat
    a = fr(head='down', arms='forward'); b.pickaxe(a, True)
    c = fr(head='down', arms='forward'); b.pickaxe(c, True)
    d = fr(head='down', y_off=1, arms='forward'); b.pickaxe(d, False, sparks=True)
    e = fr(head='happy', y_off=1, arms='forward'); b.pickaxe(e, False, nugget=True)
    rows.append([a, c, d, e])                                                                             # mine
    # --- easter eggs ---
    a = fr(head='happy'); b.mug(a, False, 0)
    c = fr(head='happy', y_off=1); b.mug(c, False, 1)
    d = fr(head='blink'); b.mug(d, True, 0)
    e = fr(head='happy'); b.mug(e, False, 1)
    rows.append([a, c, d, e])                                                                             # coffee
    a = fr(head='happy', arms='out', x_off=-1); b.headphones(a, x_off=-1); b.notes(a, 0)
    c = fr(head='blink'); b.headphones(c)
    d = fr(head='happy', arms='out', x_off=1); b.headphones(d, x_off=1); b.notes(d, 1)
    e = fr(head='happy', y_off=1); b.headphones(e, y_off=1)
    rows.append([a, c, d, e])                                                                             # dance
    a = fr(head='yawn', arms='up_both'); c = fr(head='yawn', y_off=-1, arms='up_both'); d = fr(head='sleep', y_off=1)
    rows.append([a, c, d])                                                                                # stretch
    balls = []
    for ph in range(4):
        x = fr(arms='forward'); b.balls(x, ph); balls.append(x)
    rows.append(balls)                                                                                    # juggle
    think = []
    for ph in range(4):
        x = fr(head='blink' if ph == 3 else 'open', arms='chin'); b.thought(x, ph); think.append(x)
    rows.append(think)                                                                                    # think
    for row in rows:
        for i, f in enumerate(row): b.sweat_overlay(f, i)
    return rows

def make_frames():
    rows = []
    for extra, cond in zip(FAT_LEVELS, CONDITIONS): rows += make_block(extra, cond)
    return rows

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
        print(f'wrote {name} ({W}x{Hh}, {len(rows)} rows, {len(FAT_LEVELS)} fat levels)')
    if '--preview' in sys.argv:
        for row in rows:
            for fr in row: print('\n'.join(''.join(r) for r in fr.px)); print()

if __name__ == '__main__':
    main()
