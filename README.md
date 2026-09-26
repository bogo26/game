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
./tools/dev.sh stress --level=level_3 --seconds=20              # ...on a real level
python3 tools/gen_levels.py                                     # rebuild the run's layouts
```

- `tools/dev.sh` looks for Godot in `/Applications`, `~/Applications` and `~/Downloads`. Set `GODOT=/path/to/Godot` to override.
- On Windows, run the same commands from Git Bash, or call Godot directly:

```bash
godot --headless --path . --import
godot --headless --path . -s res://tests/run_tests.gd
```

- Press **F3** in game for the performance overlay (FPS, frame times, per-system costs).
- **Options** (main menu or pause menu): volumes, fullscreen, screen shake, damage numbers, reduce flashing, rumble, colour-blind friendly player colours, gamepad aim assist and tips.

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
| Map (hold) | Back / Select | Tab (or M) |
| Pause | Start | Esc |

## Playing

1. `./tools/dev.sh run`, then pick **Start Run**.
2. Every player presses **A** (gamepad) or **Enter** (keyboard) to join. Browse heroes with left/right and press A/Enter to ready up.
3. Fight through 3 levels: clear the lockdown arena rooms, then reach the exit portal. Hold **Tab** / **Back** for the map.
4. Beat the Demon Lord in the throne room.

Things to use in the levels:
- **Barrels** explode and chain; they hurt enemies, never heroes.
- **Urns** drop XP.
- **Chasms** can't be walked on, but shots fly over them, and enemies knocked in fall.
- **Water** slows everyone.
- **Spike traps** fire in waves and stab whoever stands on them, enemies included.
- **Nests** spawn enemies until destroyed.
- **Chests** give the whole team a bonus upgrade.
- **Shrines** bless the team: Fury, Haste, Life or Wrath.

Upgrades include four **elemental chains** for your attack: fire, ice, poison and lightning. Each has three tiers, and the third is a big one:
- **Inferno:** burning enemies explode.
- **Shatter:** frozen enemies take double damage and burst into a freezing nova.
- **Plague:** poisoned enemies leave toxic clouds.
- **Thunderstrike:** every 5th hit calls down a bolt.

**Test Room** on the main menu is a drop-in sandbox with an endless horde and one of everything. Add `-- --upgrades=fire_3,ice_2` to `./tools/dev.sh run` to start with those upgrades and the tiers before them.

**Replaying:** pick Casual, Normal or Hard in character select (LB / RB or Q / E; Hard unlocks after a Normal win). Every run picks one of two layouts for each level and may mirror it, and from the second level on some enemies arrive as elites (Swift, Volatile, Splitting). The end screen shows everyone's numbers and awards, and records best times.

Debug flags (after `--`): `--level=3`, `--bots=4`, `--heroes=rogue,mage`, `--layout=b`, `--mirror=hv`, `--elite-chance=0.3`, `--debug-levelups=2`, `--show-map`.

## Status

Milestone 11 (player-experience pass) is done: run-flow fixes, readable telegraphs and spawns, hit and low-HP feedback, arena waves, team lives, an options screen with accessibility settings, button prompts for every controller, difficulty and records, map variety and elite enemies.

Milestone 9 (exports) is prepared:
- macOS + Windows presets, an app icon and `./tools/dev.sh export`.
- Building needs the Godot export templates installed once (see above).

See [docs/DESIGN.md](docs/DESIGN.md#milestones).
