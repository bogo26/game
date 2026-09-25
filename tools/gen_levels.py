#!/usr/bin/env python3
"""Builds the run's level layouts and writes src/levels/data/level_*.tres.

Levels are designed here as rooms + corridors on a character canvas (see the
legend in src/levels/level_data.gd), so layouts stay easy to tweak and review
in diffs. Arena rooms use their digit as floor; any opening a corridor cuts
into an arena room's wall becomes a door ('D').
Run: python3 tools/gen_levels.py
"""
import os


class Canvas:
    def __init__(self, w, h):
        self.w, self.h = w, h
        self.g = [[" "] * w for _ in range(h)]
        self.arenas = []  # (id, x0, y0, x1, y1) outer wall rect

    def _wall_around(self, x0, y0, x1, y1):
        for y in range(y0 - 1, y1 + 2):
            for x in range(x0 - 1, x1 + 2):
                if 0 <= x < self.w and 0 <= y < self.h and self.g[y][x] == " ":
                    self.g[y][x] = "#"

    def carve(self, x0, y0, x1, y1, ch="."):
        """Floor rectangle (inclusive) with walls added around it."""
        for y in range(y0, y1 + 1):
            for x in range(x0, x1 + 1):
                self.g[y][x] = ch
        self._wall_around(x0, y0, x1, y1)

    def room(self, x0, y0, x1, y1):
        self.carve(x0, y0, x1, y1)

    def arena(self, room_id, x0, y0, x1, y1):
        self.carve(x0, y0, x1, y1, str(room_id))
        self.arenas.append((room_id, x0 - 1, y0 - 1, x1 + 1, y1 + 1))

    def hall(self, x0, y0, x1, y1):
        """Corridor rectangle: floor that may cut through existing walls."""
        for y in range(y0, y1 + 1):
            for x in range(x0, x1 + 1):
                if self.g[y][x] in (" ", "#"):
                    self.g[y][x] = "."
        self._wall_around(x0, y0, x1, y1)

    def pillar(self, x, y, w=2, h=2):
        for yy in range(y, y + h):
            for xx in range(x, x + w):
                self.g[yy][xx] = "#"

    def put(self, x, y, ch):
        self.g[y][x] = ch

    def block(self, x, y, w, h, ch):
        for yy in range(y, y + h):
            for xx in range(x, x + w):
                self.g[yy][xx] = ch

    def finish(self):
        # Openings cut into arena walls become doors.
        for (rid, x0, y0, x1, y1) in self.arenas:
            for x in range(x0, x1 + 1):
                for y in (y0, y1):
                    if self.g[y][x] == ".":
                        self.g[y][x] = "D"
            for y in range(y0, y1 + 1):
                for x in (x0, x1):
                    if self.g[y][x] == ".":
                        self.g[y][x] = "D"
        return "\n".join("".join(r).rstrip() for r in self.g)


def level1():
    c = Canvas(96, 52)
    c.room(2, 20, 14, 30)                 # start
    c.put(8, 25, "P")
    c.hall(15, 23, 25, 27)                # -> arena 1
    c.arena(1, 26, 16, 49, 34)
    c.pillar(33, 21); c.pillar(42, 21); c.pillar(33, 29); c.pillar(42, 29)
    c.hall(50, 23, 58, 27)                # -> pillar hall
    c.room(59, 12, 72, 40)
    for y in (16, 24, 32):
        c.pillar(63, y); c.pillar(68, y)
    c.put(61, 14, "S"); c.put(70, 38, "S")
    c.hall(73, 36, 77, 40)                # -> arena 2
    c.arena(2, 78, 30, 93, 49)
    c.pillar(84, 38, 3, 3)
    c.hall(73, 13, 80, 17)                # -> exit room (north-east)
    c.room(81, 4, 92, 18)
    c.block(85, 8, 3, 3, "X")
    return c


def level2():
    c = Canvas(112, 64)
    c.room(2, 2, 16, 14)
    c.put(9, 8, "P")
    c.hall(17, 6, 31, 10)
    c.arena(1, 32, 2, 55, 22)
    c.pillar(38, 8, 3, 2); c.pillar(48, 14, 3, 2)
    c.hall(42, 23, 46, 33)                # south to the flooded hall
    c.room(20, 34, 70, 46)                # long hall with pillars
    for x in range(26, 68, 8):
        c.pillar(x, 38); c.pillar(x + 3, 43)
    c.put(22, 36, "S"); c.put(68, 44, "S"); c.put(45, 45, "S")
    c.hall(71, 38, 81, 42)
    c.arena(2, 82, 30, 108, 56)
    c.pillar(90, 38, 2, 2); c.pillar(100, 38, 2, 2); c.pillar(90, 48, 2, 2); c.pillar(100, 48, 2, 2)
    c.hall(93, 19, 97, 29)                # north to exit
    c.room(86, 4, 104, 18)
    c.block(94, 9, 3, 3, "X")
    c.hall(56, 12, 85, 16)                # loop from arena 1 to the exit room
    return c


def level3():
    c = Canvas(120, 76)
    c.room(50, 62, 66, 72)
    c.put(58, 67, "P")
    c.hall(56, 51, 60, 61)
    c.arena(1, 44, 36, 72, 50)
    c.pillar(52, 41, 2, 3); c.pillar(64, 41, 2, 3)
    c.hall(30, 41, 43, 45)                # west
    c.room(6, 30, 29, 56)
    for (x, y) in ((11, 35), (20, 35), (11, 48), (20, 48)):
        c.pillar(x, y, 3, 2)
    c.put(8, 32, "S"); c.put(27, 54, "S")
    c.hall(15, 13, 19, 29)
    c.arena(2, 4, 2, 32, 12)
    c.pillar(12, 6, 2, 2); c.pillar(24, 6, 2, 2)
    c.hall(73, 41, 87, 45)                # east
    c.arena(3, 88, 28, 116, 58)
    for (x, y) in ((95, 35), (107, 35), (95, 50), (107, 50), (101, 42)):
        c.pillar(x, y, 2, 2)
    c.hall(100, 13, 104, 27)
    c.room(92, 2, 112, 12)
    c.block(101, 5, 3, 3, "X")
    c.hall(33, 5, 91, 9)                  # northern gallery joining arena 2 and the exit
    return c


def boss():
    c = Canvas(64, 58)
    c.room(24, 46, 40, 54)
    c.put(32, 50, "P")
    c.hall(30, 39, 34, 45)
    c.arena(9, 6, 4, 58, 38)
    for (x, y) in ((14, 10), (48, 10), (14, 30), (48, 30)):
        c.pillar(x, y, 2, 2)
    c.put(32, 12, "B")
    return c


LEVELS = [
    ("level_1", "Crypt Entrance", level1, {
        "enemy_weights": {"swarmer": 1.0, "brute": 0.05, "spitter": 0.04, "exploder": 0.03},
        "hp_multiplier": 1.0, "corridor_cap_fraction": 0.4, "corridor_spawn_rate": 16.0,
        "arena_quotas": [45, 65], "arena_spawn_rate": 26.0, "tint": (1.0, 1.0, 1.0)}),
    ("level_2", "Flooded Halls", level2, {
        "enemy_weights": {"swarmer": 1.0, "brute": 0.10, "spitter": 0.10, "exploder": 0.07},
        "hp_multiplier": 1.35, "corridor_cap_fraction": 0.5, "corridor_spawn_rate": 20.0,
        "arena_quotas": [80, 100], "arena_spawn_rate": 32.0, "tint": (0.82, 0.92, 1.1)}),
    ("level_3", "Bone Pits", level3, {
        "enemy_weights": {"swarmer": 1.0, "brute": 0.15, "spitter": 0.12, "exploder": 0.12},
        "hp_multiplier": 1.8, "corridor_cap_fraction": 0.55, "corridor_spawn_rate": 24.0,
        "arena_quotas": [100, 110, 140], "arena_spawn_rate": 38.0, "tint": (1.1, 0.95, 0.85)}),
    ("boss", "Demon's Throne", boss, {
        "enemy_weights": {"swarmer": 1.0, "exploder": 0.1},
        "hp_multiplier": 2.2, "corridor_cap_fraction": 0.0, "corridor_spawn_rate": 0.0,
        "arena_quotas": [0, 0, 0, 0, 0, 0, 0, 0, 0], "arena_spawn_rate": 20.0,
        "tint": (1.15, 0.8, 0.8), "is_boss_level": True}),
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
    for (file_id, name, builder, settings) in LEVELS:
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
            else:
                lines.append("%s = %s" % (key, fmt(value)))
        with open(os.path.join(out_dir, file_id + ".tres"), "w") as f:
            f.write("\n".join(lines) + "\n")
        print("%-8s %s\n%s\n" % (file_id, name, layout))


if __name__ == "__main__":
    main()
