#!/usr/bin/env python3
"""Builds the run's level layouts and writes src/levels/data/level_*.tres.

Levels are designed here on a character canvas (legend in
src/levels/level_data.gd) from shapes: rectangles, octagons, discs, caves,
rings around pits, and halls between them, plus terrain (water, chasms,
spike traps) and props (barrels, urns, nests, chests, shrines). Walls are
added around everything at the end, and any corridor floor touching an arena
room becomes a door. A seeded RNG keeps the output stable, so layouts stay
easy to review in diffs.
Run: python3 tools/gen_levels.py
"""
import os
import random

FLOORISH = set(".PSB0123456789")
WALKABLE = FLOORISH | set("~^")


class Canvas:
    def __init__(self, w, h, seed):
        self.w, self.h = w, h
        self.g = [[" "] * w for _ in range(h)]
        self.room = {}  # (x, y) -> arena id, for every cell inside an arena
        self.rng = random.Random(seed)

    def inside(self, x, y):
        return 0 <= x < self.w and 0 <= y < self.h

    def get(self, x, y):
        return self.g[y][x] if self.inside(x, y) else " "

    def set(self, x, y, ch):
        if self.inside(x, y):
            self.g[y][x] = ch

    # --- shapes: carve floor (or an arena's digit) ---------------------------------

    def _carve(self, cells, ch=".", rid=None):
        for (x, y) in cells:
            if not self.inside(x, y):
                continue
            self.set(x, y, str(rid) if rid else ch)
            if rid:
                self.room[(x, y)] = rid

    @staticmethod
    def rect_cells(x0, y0, x1, y1):
        return [(x, y) for y in range(y0, y1 + 1) for x in range(x0, x1 + 1)]

    @staticmethod
    def octagon_cells(x0, y0, x1, y1, cut):
        out = []
        for y in range(y0, y1 + 1):
            for x in range(x0, x1 + 1):
                if min(x - x0, x1 - x) + min(y - y0, y1 - y) >= cut:
                    out.append((x, y))
        return out

    @staticmethod
    def disc_cells(cx, cy, r):
        return [(x, y) for y in range(cy - r, cy + r + 1) for x in range(cx - r, cx + r + 1)
                if (x - cx) ** 2 + (y - cy) ** 2 <= r * r + r * 0.6]

    def cave_cells(self, x0, y0, x1, y1, fill=0.44, steps=5, rounded=False):
        """Organic cave (cellular automaton) inside a rectangle: its biggest open
        region. `rounded` keeps it inside the rectangle's ellipse (tidier edges)."""
        w, h = x1 - x0 + 1, y1 - y0 + 1
        mid_x, mid_y = (w - 1) / 2.0, (h - 1) / 2.0

        def outside(x, y):
            return rounded and ((x - mid_x) / (w / 2.0)) ** 2 + ((y - mid_y) / (h / 2.0)) ** 2 > 1.0
        wall = [[outside(x, y) or self.rng.random() < fill for x in range(w)] for y in range(h)]

        def walls_near(x, y):
            n = 0
            for dy in (-1, 0, 1):
                for dx in (-1, 0, 1):
                    if dx or dy:
                        xx, yy = x + dx, y + dy
                        n += 1 if not (0 <= xx < w and 0 <= yy < h) or wall[yy][xx] else 0
            return n
        for step in range(steps):
            wall = [[outside(x, y) or walls_near(x, y) >= 5 or (step < 2 and walls_near(x, y) <= 1)
                     for x in range(w)] for y in range(h)]
        seen, best = set(), []
        for y in range(h):
            for x in range(w):
                if wall[y][x] or (x, y) in seen:
                    continue
                region, stack = [], [(x, y)]
                seen.add((x, y))
                while stack:
                    cx, cy = stack.pop()
                    region.append((cx, cy))
                    for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                        nx, ny = cx + dx, cy + dy
                        if 0 <= nx < w and 0 <= ny < h and not wall[ny][nx] and (nx, ny) not in seen:
                            seen.add((nx, ny))
                            stack.append((nx, ny))
                if len(region) > len(best):
                    best = region
        return [(x0 + x, y0 + y) for (x, y) in best]

    def rect(self, x0, y0, x1, y1):
        self._carve(self.rect_cells(x0, y0, x1, y1))

    def octagon(self, x0, y0, x1, y1, cut):
        self._carve(self.octagon_cells(x0, y0, x1, y1, cut))

    def disc(self, cx, cy, r):
        self._carve(self.disc_cells(cx, cy, r))

    def cave(self, x0, y0, x1, y1, fill=0.44):
        self._carve(self.cave_cells(x0, y0, x1, y1, fill))

    def arena(self, rid, cells):
        self._carve(cells, rid=rid)

    def hall(self, x0, y0, x1, y1, toward=None):
        """Corridor: floor over void and walls only (never over rooms). With
        `toward` ("n", "s", "e" or "w") each lane runs that way and stops at the
        first arena tile, so it meets a round or ragged arena right at its edge."""
        if toward is None:
            for (x, y) in self.rect_cells(x0, y0, x1, y1):
                if self.get(x, y) in (" ", "#"):
                    self.set(x, y, ".")
            return
        if toward in "ew":
            lanes = [[(x, y) for x in (range(x0, x1 + 1) if toward == "e" else range(x1, x0 - 1, -1))]
                     for y in range(y0, y1 + 1)]
        else:
            lanes = [[(x, y) for y in (range(y0, y1 + 1) if toward == "s" else range(y1, y0 - 1, -1))]
                     for x in range(x0, x1 + 1)]
        for lane in lanes:
            for (x, y) in lane:
                if (x, y) in self.room:
                    break
                if self.get(x, y) in (" ", "#"):
                    self.set(x, y, ".")

    # --- features on existing floor ------------------------------------------------------

    def fill(self, cells, ch):
        """Terrain (water ~, chasm :, spikes ^) or floor (.) over walkable floor;
        arena cells stay part of their arena."""
        for (x, y) in cells:
            cur = self.get(x, y)
            if cur in WALKABLE or cur == ":":
                if ch == "." and (x, y) in self.room:
                    self.set(x, y, str(self.room[(x, y)]))
                else:
                    self.set(x, y, ch)

    def pillar(self, x, y, w=2, h=2):
        for (xx, yy) in self.rect_cells(x, y, x + w - 1, y + h - 1):
            self.set(xx, yy, "#")
            self.room.pop((xx, yy), None)

    def put(self, x, y, ch):
        assert self.get(x, y) in WALKABLE, "put %s on %r at %d,%d" % (ch, self.get(x, y), x, y)
        self.set(x, y, ch)

    def _free_around(self, x, y):
        """Props go where they can't wall off a path: all 8 neighbours walkable."""
        return all(self.get(x + dx, y + dy) in WALKABLE or self.get(x + dx, y + dy) in "bu"
                   for dx in (-1, 0, 1) for dy in (-1, 0, 1) if dx or dy)

    def scatter(self, cells, ch, count):
        spots = [c for c in cells if self.get(*c) in FLOORISH - set("PSB") and self._free_around(*c)]
        self.rng.shuffle(spots)
        placed = []
        for (x, y) in spots:
            if len(placed) >= count:
                break
            if all(abs(x - px) + abs(y - py) > 2 for (px, py) in placed):
                self.set(x, y, ch)
                placed.append((x, y))

    def cluster(self, x, y, ch="b", pattern=((0, 0), (1, 0), (0, 1))):
        for dx, dy in pattern:
            if self.get(x + dx, y + dy) in FLOORISH - set("PSB"):
                self.set(x + dx, y + dy, ch)

    # --- output ------------------------------------------------------------------------------

    def finish(self):
        # Corridor floor touching an arena becomes its doors.
        for y in range(self.h):
            for x in range(self.w):
                if self.g[y][x] == "." and (x, y) not in self.room:
                    for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                        if (x + dx, y + dy) in self.room:
                            self.g[y][x] = "D"
                            break
        # Walls around everything that isn't void.
        for y in range(self.h):
            for x in range(self.w):
                if self.g[y][x] != " ":
                    continue
                for dy in (-1, 0, 1):
                    for dx in (-1, 0, 1):
                        if self.get(x + dx, y + dy) not in (" ", "#"):
                            self.g[y][x] = "#"
        return "\n".join("".join(r).rstrip() for r in self.g)


# --- the run -----------------------------------------------------------------------------------

def level1():
    """Crypt Entrance: learn the new toys. Urns at the start, a spike gauntlet,
    an octagonal arena with barrels, a pillar hall with a shrine, an optional
    treasure crypt guarded by a nest, and a round arena around a sarcophagus."""
    c = Canvas(112, 60, seed=11)
    start = c.octagon_cells(3, 21, 18, 35, 3)
    c._carve(start)
    c.put(10, 28, "P")
    for (x, y) in ((6, 24), (15, 24), (6, 32), (15, 32)):
        c.put(x, y, "u")
    a1 = c.octagon_cells(33, 17, 58, 39, 6)      # arena 1: octagon with pillars and barrels
    c.arena(1, a1)
    c.hall(19, 26, 34, 30, "e")                  # east to it, through a spike gauntlet
    c.fill(c.rect_cells(23, 26, 28, 30), "^")
    for (x, y) in ((39, 22), (51, 22), (39, 33), (51, 33)):
        c.pillar(x, y)
    c.cluster(44, 20)
    c.cluster(45, 36, pattern=((0, 0), (1, 0), (1, -1)))
    c.cluster(36, 28, pattern=((0, 0), (0, 1)))
    c.cluster(55, 28, pattern=((0, 0), (0, 1)))
    c.hall(57, 26, 68, 30, "w")                  # east to the pillar hall
    hall = c.rect_cells(67, 14, 82, 44)
    c._carve(hall)
    for y in (18, 26, 34):
        c.pillar(71, y)
        c.pillar(77, y)
    c.rect(83, 27, 85, 29)                       # shrine alcove
    c.put(85, 28, "A")
    c.put(69, 16, "S")
    c.put(80, 42, "S")
    c.scatter(hall, "u", 3)
    c.hall(73, 6, 75, 14)                        # optional: north to the treasure crypt
    crypt = c.rect_cells(64, 1, 84, 5)
    c._carve(crypt)
    c.put(74, 2, "C")
    c.put(66, 3, "N")
    c.put(82, 3, "u")
    c.put(65, 5, "u")
    c.cluster(69, 1, pattern=((0, 0), (1, 0)))
    a2 = c.disc_cells(98, 45, 11)                # arena 2: round, spikes around a sarcophagus
    c.arena(2, a2)
    c.hall(80, 38, 92, 42, "e")                  # south-east to it
    c.pillar(97, 44, 3, 2)
    for (x0, y0, x1, y1) in ((96, 39, 100, 40), (96, 48, 100, 49), (92, 43, 93, 46), (104, 43, 105, 46)):
        c.fill(c.rect_cells(x0, y0, x1, y1), "^")
    c.cluster(90, 49)
    c.cluster(106, 40, pattern=((0, 0), (1, 0), (0, -1)))
    c.hall(96, 22, 100, 34, "s")                 # north to the exit
    c.rect(89, 10, 108, 23)
    c.fill(c.rect_cells(97, 15, 99, 17), "X")
    return c


def level2():
    """Flooded Halls: water everywhere slows the fight; nests in the long hall
    and a flooded arena you clear by destroying its nests."""
    c = Canvas(118, 64, seed=22)
    c.rect(2, 2, 16, 14)
    c.put(9, 8, "P")
    c.put(3, 3, "u")
    c.put(15, 3, "u")
    c.hall(17, 6, 33, 10)                        # flooded corridor
    c.fill(c.rect_cells(21, 6, 29, 10), "~")
    a1 = c.rect_cells(32, 2, 58, 24)             # arena 1: pumping chamber, two channels
    c.arena(1, a1)
    for y0 in (8, 16):
        c.fill(c.rect_cells(32, y0, 58, y0 + 1), "~")
    c.pillar(39, 4)
    c.pillar(51, 21)
    c.cluster(44, 11, pattern=((0, 0), (1, 0), (0, 1), (1, 1)))
    c.cluster(36, 20)
    c.cluster(54, 4, pattern=((0, 0), (1, 0)))
    c.hall(43, 25, 47, 34)                       # south to the flooded hall
    long_hall = c.rect_cells(18, 34, 76, 48)
    c._carve(long_hall)
    c.fill(c.disc_cells(29, 41, 5), "~")         # two big pools with dry islands
    c.fill(c.disc_cells(29, 41, 1), ".")
    c.fill(c.disc_cells(62, 41, 6), "~")
    c.fill(c.disc_cells(62, 41, 2), ".")
    c.put(62, 41, "N")
    c.put(40, 45, "N")
    c.cluster(28, 40, pattern=((0, 0), (1, 1)))
    for x in range(44, 56, 5):
        c.pillar(x, 37)
    c.put(20, 36, "S")
    c.put(74, 46, "S")
    c.scatter(long_hall, "u", 4)
    c.rect(46, 49, 50, 51)                       # shrine alcove
    c.put(48, 51, "A")
    c.hall(8, 38, 18, 42)                        # optional: west, wading to the treasure
    side = c.rect_cells(2, 30, 8, 50)
    c._carve(side)
    c.fill(c.rect_cells(2, 36, 8, 46), "~")
    c.fill(c.rect_cells(4, 38, 6, 44), ".")
    c.put(5, 32, "C")
    c.put(3, 49, "u")
    c.put(7, 49, "u")
    c.hall(76, 39, 86, 43)                       # east to arena 2
    a2 = c.rect_cells(84, 30, 112, 58)           # arena 2: flooded, nests on islands
    c.arena(2, a2)
    c.fill(c.rect_cells(84, 30, 112, 58), "~")
    for (x, y) in ((91, 36), (105, 36), (91, 52), (105, 52), (98, 44)):
        c.fill(c.disc_cells(x, y, 3), ".")
    for (x, y) in ((91, 36), (105, 36), (91, 52), (105, 52)):
        c.put(x, y, "N")
    c.fill(c.rect_cells(84, 40, 112, 42), ".")   # a dry causeway through the middle
    c.cluster(97, 46)
    c.hall(96, 18, 100, 30)                      # north to the exit
    c.rect(88, 4, 108, 18)
    c.fill(c.rect_cells(97, 9, 99, 11), "X")
    c.hall(58, 12, 88, 16)                       # a loop from arena 1 to the exit room
    return c


def level3():
    """Bone Pits: chasms. A ring arena around a pit, a cave full of cracks, a
    bridge arena over the abyss, a treasure island and a cave arena of nests."""
    c = Canvas(124, 80, seed=33)
    start = c.cave_cells(48, 64, 70, 76, fill=0.36)
    c._carve(start)
    c.fill(c.disc_cells(58, 70, 2), ".")
    c.put(58, 70, "P")
    a1 = c.disc_cells(58, 40, 12)                # arena 1: a ring around a pit
    c.arena(1, a1)
    c.hall(56, 52, 60, 67, "n")                  # north to it
    c.fill(c.disc_cells(58, 40, 4), ":")
    for (x, y) in ((51, 33), (65, 33), (51, 47), (65, 47)):
        c.cluster(x, y, pattern=((0, 0), (1, 0)))
    c.hall(28, 38, 47, 42, "e")                  # west to the cave
    cave = c.cave_cells(4, 22, 30, 60, fill=0.42)
    c._carve(cave)
    c.fill(c.rect_cells(8, 45, 26, 46), ":")     # a crack across the cave...
    c.fill(c.rect_cells(15, 45, 17, 46), ".")    # ...with a bridge
    c.fill(c.rect_cells(15, 43, 17, 44), "^")    # guarded by spikes
    c.scatter(cave, "u", 5)
    c.scatter(cave, "S", 2)
    c.put(*_open_spot(c, cave, (12, 30)), "N")
    c.hall(14, 16, 18, 30)                       # north to the bridge arena
    a2 = c.rect_cells(4, 2, 36, 17)              # arena 2: bridges over the abyss
    c.arena(2, a2)
    c.fill(c.rect_cells(4, 7, 36, 11), ":")
    for x in (9, 20, 31):
        c.fill(c.rect_cells(x, 7, x + 1, 11), ".")
    c.cluster(7, 4)
    c.cluster(17, 13, pattern=((0, 0), (1, 0)))
    c.cluster(28, 4, pattern=((0, 0), (0, 1)))
    c.hall(36, 12, 100, 16)                      # the northern gallery
    c.fill(c.rect_cells(60, 12, 66, 16), "^")    # spike traps along it
    c.put(46, 14, "S")
    c.hall(46, 5, 48, 12)                        # up to the treasure island
    island_room = c.rect_cells(38, 1, 58, 5)
    c._carve(island_room)
    c.fill(c.rect_cells(38, 1, 58, 5), ":")
    c.fill(c.rect_cells(46, 1, 48, 5), ".")      # a narrow bridge...
    c.fill(c.rect_cells(51, 1, 56, 5), ".")      # ...to the island
    c.fill(c.rect_cells(46, 1, 56, 2), ".")
    c.put(54, 3, "C")
    c.put(52, 4, "A")
    a3 = c.cave_cells(84, 24, 120, 62, fill=0.38, rounded=True)
    c.arena(3, a3)                               # arena 3: a cave of nests
    c.hall(71, 38, 90, 42, "e")                  # east to it
    for spot in ((95, 34), (110, 44), (96, 52)):
        c.put(*_open_spot(c, a3, spot), "N")
    c.scatter(a3, "b", 4)
    c.hall(98, 12, 102, 30, "s")                 # north to the exit
    c.rect(94, 2, 116, 12)
    c.fill(c.rect_cells(104, 5, 106, 7), "X")
    return c


def boss():
    """Demon's Throne: a spike gauntlet with barrels up to a throne room with
    lava pools in its corners and a shrine for one last blessing."""
    c = Canvas(72, 64, seed=44)
    c.rect(26, 52, 44, 60)
    c.put(35, 56, "P")
    c.put(43, 53, "A")
    c.put(27, 59, "u")
    c.put(43, 59, "u")
    c.hall(32, 40, 38, 51)                       # the approach
    c.fill(c.rect_cells(32, 44, 38, 47), "^")
    c.cluster(32, 49, pattern=((0, 0), (0, 1)))
    c.cluster(38, 49, pattern=((0, 0), (0, 1)))
    throne = c.rect_cells(6, 4, 64, 40)
    c.arena(9, throne)
    for (x, y) in ((13, 10), (57, 10), (13, 34), (57, 34)):
        c.fill(c.disc_cells(x, y, 4), ":")
    for (x, y) in ((21, 14), (48, 14), (21, 29), (48, 29)):
        c.pillar(x, y)
    c.cluster(24, 20)
    c.cluster(45, 20, pattern=((0, 0), (1, 0), (1, 1)))
    c.put(35, 12, "B")
    return c


# --- second layouts (the run picks one per level, then may mirror it) ----------------------

def level1b():
    """Crypt Entrance, the north gate: from a southern hall through a spike
    gauntlet to a round arena, east through a pillared octagon (shrine to the
    north, a treasure crypt with a nest to the south) to an octagonal arena of
    spikes, and up to the exit."""
    c = Canvas(112, 60, seed=111)
    start = c.rect_cells(4, 40, 20, 54)
    c._carve(start)
    c.put(12, 47, "P")
    for (x, y) in ((5, 41), (19, 41), (5, 53), (19, 53)):
        c.put(x, y, "u")
    a1 = c.disc_cells(14, 22, 11)                # arena 1: round, four pillars, barrels
    c.arena(1, a1)
    c.hall(11, 33, 15, 39, "n")                  # north to it, through a spike gauntlet
    c.fill(c.rect_cells(11, 35, 15, 37), "^")
    for (x, y) in ((9, 17), (18, 17), (9, 26), (18, 26)):
        c.pillar(x, y)
    c.cluster(13, 14, pattern=((0, 0), (1, 0)))
    c.cluster(5, 21, pattern=((0, 0), (0, 1)))
    c.cluster(22, 22, pattern=((0, 0), (0, 1), (-1, 1)))
    c.hall(24, 20, 45, 24, "w")                  # east to the octagon hall
    hall = c.octagon_cells(44, 12, 66, 34, 5)
    c._carve(hall)
    for (x, y) in ((50, 17), (59, 17), (50, 28), (59, 28)):
        c.pillar(x, y)
    c.rect(53, 8, 57, 11)                        # shrine alcove
    c.put(55, 9, "A")
    c.put(47, 23, "S")
    c.put(63, 23, "S")
    c.scatter(hall, "u", 3)
    c.hall(53, 35, 57, 42)                       # optional: south to the treasure crypt
    crypt = c.rect_cells(46, 43, 64, 48)
    c._carve(crypt)
    c.put(55, 47, "C")
    c.put(48, 45, "N")
    c.put(63, 44, "u")
    c.put(47, 48, "u")
    a2 = c.octagon_cells(76, 14, 100, 36, 6)     # arena 2: octagon, spikes around a sarcophagus
    c.arena(2, a2)
    c.hall(66, 22, 77, 26, "e")                  # east to it
    c.pillar(87, 24, 3, 2)
    for (x0, y0, x1, y1) in ((85, 20, 91, 21), (85, 28, 91, 29), (81, 23, 82, 26), (96, 23, 97, 26)):
        c.fill(c.rect_cells(x0, y0, x1, y1), "^")
    c.cluster(80, 17)
    c.cluster(95, 33, pattern=((0, 0), (1, 0), (1, -1)))
    c.hall(86, 7, 90, 14, "s")                   # north to the exit
    c.rect(78, 1, 98, 6)
    c.fill(c.rect_cells(87, 2, 89, 4), "X")
    return c


def level2b():
    """Flooded Halls, the cistern: north from the south-east through a flooded
    corridor to a cistern arena with a moated island, west along a hall of
    pools and nests, and into a flooded arena of nests before the exit."""
    c = Canvas(118, 64, seed=222)
    c.rect(100, 48, 114, 60)
    c.put(107, 54, "P")
    c.put(101, 59, "u")
    c.put(113, 59, "u")
    a1 = c.octagon_cells(90, 8, 116, 35, 6)      # arena 1: a cistern, an island in a moat
    c.arena(1, a1)
    c.hall(104, 36, 108, 47, "n")                # flooded corridor north to it
    c.fill(c.rect_cells(104, 39, 108, 44), "~")
    c.fill(c.disc_cells(103, 21, 8), "~")
    c.fill(c.disc_cells(103, 21, 4), ".")
    c.cluster(102, 20, pattern=((0, 0), (1, 0), (0, 1), (1, 1)))
    c.cluster(94, 12)
    c.cluster(112, 30, pattern=((0, 0), (0, -1)))
    c.pillar(96, 28)
    c.pillar(110, 12)
    c.hall(62, 18, 91, 22, "e")                  # west from it: the hall of pools
    long_hall = c.rect_cells(30, 12, 62, 30)
    c._carve(long_hall)
    c.fill(c.disc_cells(40, 21, 5), "~")
    c.fill(c.disc_cells(40, 21, 1), ".")
    c.fill(c.disc_cells(54, 21, 4), "~")
    c.fill(c.disc_cells(54, 21, 1), ".")
    c.put(54, 21, "N")
    c.put(34, 27, "N")
    for x in (46, 49):
        c.pillar(x, 14)
    c.put(32, 14, "S")
    c.put(60, 28, "S")
    c.scatter(long_hall, "u", 4)
    c.rect(44, 8, 48, 11)                        # shrine alcove
    c.put(46, 9, "A")
    c.hall(34, 31, 38, 38)                       # optional: south, wading to the treasure
    side = c.rect_cells(24, 39, 48, 45)
    c._carve(side)
    c.fill(side, "~")
    c.fill(c.rect_cells(34, 39, 38, 45), ".")
    c.fill(c.rect_cells(24, 43, 48, 44), ".")
    c.put(26, 44, "C")
    c.put(47, 43, "u")
    a2 = c.rect_cells(2, 4, 26, 34)              # arena 2: flooded, nests on islands
    c.arena(2, a2)
    c.hall(26, 16, 31, 20, "w")                  # west to it
    c.fill(a2, "~")
    for (x, y) in ((8, 10), (20, 10), (8, 28), (20, 28), (14, 19)):
        c.fill(c.disc_cells(x, y, 3), ".")
    for (x, y) in ((8, 10), (20, 10), (8, 28), (20, 28)):
        c.put(x, y, "N")
    c.fill(c.rect_cells(2, 17, 26, 19), ".")     # a dry causeway through the middle
    c.cluster(13, 21)
    c.hall(12, 35, 16, 46, "n")                  # south to the exit
    c.rect(4, 47, 24, 58)
    c.fill(c.rect_cells(13, 51, 15, 53), "X")
    return c


def level3b():
    """Bone Pits, the long drop: bridges over the abyss right from the start,
    a cracked cave below, a ring arena around a pit (the treasure island above
    it), a gallery of spikes, a cave arena of nests and the exit beneath it."""
    c = Canvas(124, 80, seed=333)
    start = c.cave_cells(6, 3, 30, 16, fill=0.36)
    c._carve(start)
    c.fill(c.disc_cells(18, 10, 2), ".")
    c.put(18, 10, "P")
    a1 = c.rect_cells(4, 26, 36, 41)             # arena 1: bridges over the abyss
    c.arena(1, a1)
    c.hall(16, 8, 20, 26, "s")                   # south to it (from inside the cave)
    c.fill(c.rect_cells(4, 31, 36, 35), ":")
    for x in (9, 20, 31):
        c.fill(c.rect_cells(x, 31, x + 1, 35), ".")
    c.cluster(7, 28)
    c.cluster(26, 39, pattern=((0, 0), (1, 0)))
    c.cluster(33, 28, pattern=((0, 0), (0, 1)))
    cave = c.cave_cells(4, 50, 40, 76, fill=0.42)
    c._carve(cave)
    c.hall(18, 42, 22, 56, "n")                  # the cave, south of the bridges
    c.fill(c.rect_cells(8, 62, 34, 63), ":")     # a crack across the cave...
    c.fill(c.rect_cells(20, 62, 22, 63), ".")    # ...with a bridge
    c.fill(c.rect_cells(20, 60, 22, 61), "^")    # guarded by spikes
    c.scatter(cave, "u", 5)
    c.scatter(cave, "S", 2)
    c.put(*_open_spot(c, cave, (10, 70)), "N")
    a2 = c.disc_cells(62, 62, 12)                # arena 2: a ring around a pit
    c.arena(2, a2)
    c.hall(38, 60, 51, 64, "e")                  # east to it
    c.fill(c.disc_cells(62, 62, 4), ":")
    for (x, y) in ((55, 55), (68, 55), (55, 68), (68, 68)):
        c.cluster(x, y, pattern=((0, 0), (1, 0)))
    island_room = c.rect_cells(52, 36, 72, 42)   # optional: the treasure island, north of it
    c._carve(island_room)
    c.fill(island_room, ":")
    c.fill(c.rect_cells(60, 40, 62, 42), ".")    # a narrow bridge...
    c.fill(c.rect_cells(55, 36, 66, 38), ".")    # ...to the island
    c.fill(c.rect_cells(60, 38, 62, 40), ".")
    c.put(57, 37, "C")
    c.put(65, 37, "A")
    c.hall(60, 43, 62, 50, "s")
    c.hall(74, 60, 84, 64, "w")                  # east: the gallery of spikes
    c.rect(80, 20, 84, 64)
    c.fill(c.rect_cells(80, 38, 84, 44), "^")
    c.put(82, 50, "S")
    a3 = c.cave_cells(88, 4, 120, 40, fill=0.38, rounded=True)
    c.arena(3, a3)                               # arena 3: a cave of nests
    c.hall(84, 20, 92, 24, "e")
    for spot in ((96, 12), (112, 22), (100, 32)):
        c.put(*_open_spot(c, a3, spot), "N")
    c.scatter(a3, "b", 4)
    c.hall(100, 25, 104, 56, "n")                # south to the exit (stops at the cave)
    c.rect(94, 57, 116, 70)
    c.fill(c.rect_cells(104, 62, 106, 64), "X")
    return c


def _open_spot(c, cells, near):
    """The cell of `cells` nearest to `near` with room around it."""
    best, best_d = None, 1 << 30
    for (x, y) in cells:
        if c.get(x, y) in FLOORISH - set("PSB") and c._free_around(x, y):
            d = (x - near[0]) ** 2 + (y - near[1]) ** 2
            if d < best_d:
                best, best_d = (x, y), d
    return best


LEVELS = [
    ("level_1", "Crypt Entrance", level1, {
        "enemy_weights": {"swarmer": 1.0, "brute": 0.05, "spitter": 0.04, "exploder": 0.03},
        "hp_multiplier": 1.0, "corridor_cap_fraction": 0.4, "corridor_spawn_rate": 16.0,
        "arena_quotas": [45, 60], "arena_spawn_rate": 26.0, "theme": "crypt", "tint": (1.0, 1.0, 1.0)}),
    ("level_2", "Flooded Halls", level2, {
        "enemy_weights": {"swarmer": 1.0, "brute": 0.10, "spitter": 0.10, "exploder": 0.07},
        "hp_multiplier": 1.35, "corridor_cap_fraction": 0.5, "corridor_spawn_rate": 20.0,
        "arena_quotas": [80, 30], "arena_spawn_rate": 32.0, "theme": "flooded", "tint": (1.0, 1.0, 1.0)}),
    ("level_3", "Bone Pits", level3, {
        "enemy_weights": {"swarmer": 1.0, "brute": 0.15, "spitter": 0.12, "exploder": 0.12},
        "hp_multiplier": 1.8, "corridor_cap_fraction": 0.55, "corridor_spawn_rate": 24.0,
        "arena_quotas": [100, 110, 60], "arena_spawn_rate": 38.0, "theme": "bones", "tint": (1.0, 1.0, 1.0)}),
    ("level_1b", "Crypt Entrance", level1b, None),
    ("level_2b", "Flooded Halls", level2b, None),
    ("level_3b", "Bone Pits", level3b, None),
    ("boss", "Demon's Throne", boss, {
        "enemy_weights": {"swarmer": 1.0, "exploder": 0.1},
        "hp_multiplier": 2.2, "corridor_cap_fraction": 0.0, "corridor_spawn_rate": 0.0,
        "arena_quotas": [0, 0, 0, 0, 0, 0, 0, 0, 0], "arena_spawn_rate": 20.0,
        "theme": "throne", "tint": (1.0, 1.0, 1.0), "is_boss_level": True}),
]


def fmt(v):
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, float):
        return repr(v)
    if isinstance(v, int):
        return str(v)
    if isinstance(v, str):
        return '"%s"' % v
    if isinstance(v, tuple):
        return "Color(%s)" % ", ".join(repr(float(x)) for x in (list(v) + [1.0])[:4])
    raise TypeError(v)


def main():
    out_dir = os.path.join(os.path.dirname(__file__), "..", "src", "levels", "data")
    by_name = {}
    for (file_id, name, builder, settings) in LEVELS:
        if settings is None:  # a second layout: same settings as the first
            settings = by_name[name]
        by_name.setdefault(name, settings)
        layout = builder().finish()
        lines = ['[gd_resource type="Resource" script_class="LevelData" load_steps=2 format=3]', "",
                 '[ext_resource type="Script" path="res://src/levels/level_data.gd" id="1_data"]', "",
                 "[resource]", 'script = ExtResource("1_data")',
                 "display_name = %s" % fmt(name), 'layout = "%s"' % layout]
        for key, value in settings.items():
            if key == "enemy_weights":
                pairs = ", ".join('&"%s": %s' % (k, repr(float(w))) for k, w in value.items())
                lines.append("enemy_weights = {%s}" % pairs)
            elif key == "arena_quotas":
                lines.append("arena_quotas = PackedInt32Array(%s)" % ", ".join(str(q) for q in value))
            elif key == "theme":
                lines.append('theme = &"%s"' % value)
            else:
                lines.append("%s = %s" % (key, fmt(value)))
        with open(os.path.join(out_dir, file_id + ".tres"), "w") as f:
            f.write("\n".join(lines) + "\n")
        print("%-8s %s\n%s\n" % (file_id, name, layout))


if __name__ == "__main__":
    main()
