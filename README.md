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

## Building releases

1. Install the export templates once: open the editor (`./tools/dev.sh editor`), go to **Editor → Manage Export Templates → Download and Install**, and pick 4.7.2 stable.
2. Run `./tools/dev.sh export`. It writes:
   - `build/macos/HordeCrawler.zip`: a universal .app, ad-hoc signed.
   - `build/windows/HordeCrawler.exe`: x86_64, single file with the game data embedded.

The macOS build runs on your own Mac; other people have to right-click → Open the first time, because it isn't notarized. Distributing widely (Steam, itch.io) needs an Apple Developer ID and notarization. Test the Windows build on a Windows PC.

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

Milestone 9 (exports) is prepared:
- macOS + Windows presets, an app icon and `./tools/dev.sh export`.
- Building needs the Godot export templates installed once (see above).

See [docs/DESIGN.md](docs/DESIGN.md#milestones).
