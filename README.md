# Horde Crawler (working title)

1–4 player **local co-op** top-down pixel-art horde crawler for **macOS and Windows**. Pick a hero, fight through hordes of up to 300 enemies, and upgrade on every level-up.

Design, controls, heroes and architecture: [docs/DESIGN.md](docs/DESIGN.md).

## Requirements

- [Godot 4.7](https://godotengine.org/download), standard build (not .NET)

## Running

```bash
./tools/dev.sh run      # play
./tools/dev.sh editor   # open in the Godot editor
./tools/dev.sh test     # headless test suite
./tools/dev.sh stress --fullscreen --max-fps=120 --seconds=60   # horde perf test
```

- `tools/dev.sh` looks for Godot in `/Applications`, `~/Applications` and `~/Downloads`. Set `GODOT=/path/to/Godot` to override.
- On Windows, run the same commands from Git Bash, or call Godot directly:

```bash
godot --headless --path . --import
godot --headless --path . -s res://tests/run_tests.gd
```

- Press **F3** in game for the performance overlay (FPS, frame times, per-system costs).

## Controls

| Action | Gamepad | Keyboard + mouse |
|---|---|---|
| Move / aim | Left stick / right stick | WASD / mouse |
| Attack | RT | LMB |
| Special | LT | RMB |
| Dash / bash | RB (or A) | Space (or Shift) |
| Ultimate | LB (or Y) | Q |
| Pause | Start | Esc |

## Playing

1. `./tools/dev.sh run`, then pick **Start Run**.
2. Every player presses **A** (gamepad) or **Enter** (keyboard) to join. Browse heroes with left/right and press A/Enter to ready up.
3. Fight through 3 levels: clear the lockdown arena rooms, then reach the exit portal.
4. Beat the Demon Lord in the throne room.

**Test Room** on the main menu is a drop-in sandbox with an endless horde.

## Status

Milestone 6 is done: the vertical slice is playable end to end.
- Main menu → character select → 3 levels + boss → victory/defeat screen.
- 4 heroes (Knight, Ranger, Mage, Cleric) and 4 enemy types plus the boss.
- Upgrades on every team level-up, and a full HUD.

Next: heroes 5–8, the art pass, then exports. See [docs/DESIGN.md](docs/DESIGN.md#milestones).
