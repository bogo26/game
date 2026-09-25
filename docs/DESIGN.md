# Horde Crawler — Design

Working title. A 1–4 player **local co-op**, top-down **pixel-art horde crawler** for **macOS and Windows**, built with **Godot 4 (GDScript)**.

Players pick heroes, fight through hand-built levels packed with hordes of up to **300 enemies on screen**, and choose upgrades (pick 1 of 3) on every team level-up.

## Targets

| Area | Target |
|---|---|
| Players | 1–4 local, any mix of keyboard+mouse (max 1) and gamepads |
| Platforms | macOS (Apple Silicon + Intel), Windows 10/11 |
| Performance | **120 fps at 4K**: ≤ 6 ms average and ≤ 8.3 ms p99 frame time; game simulation ≤ 3 ms CPU |
| Horde | 300 enemies alive at once with 4 players, plus ~400 projectiles |
| Art | 16×16 pixel art, 640×360 base resolution, integer scaling only |

## Controls (twin-stick)

| Action | Gamepad | Keyboard + mouse |
|---|---|---|
| Move / aim | Left stick / right stick | WASD / mouse |
| Attack (hold to repeat) | RT | LMB |
| Special | LT | RMB |
| Movement ability (dash/bash) | RB (or A) | Space (or Shift) |
| Ultimate | LB (or Y) | Q |
| Pause | Start | Esc |
| Join (character select) | A / Start | Enter / Space |

Aim behaviour on gamepad:
- Aim follows the right stick while it is held.
- When the stick is released, aim stays where it was.
- After 0.5 s without aiming, aim follows the movement direction, so players who never touch the right stick still shoot where they walk.

## Heroes

Each hero has four abilities:
- **Attack:** spammable
- **Special:** cooldown
- **Movement:** dash or bash on a short cooldown, with brief i-frames
- **Ultimate:** charged by dealing damage and getting kills, not by a timer

Two players may pick the same hero. Every player has a colour (P1 red, P2 blue, P3 green, P4 yellow), which is used for their ring, reticle and HUD panel.

| Hero | Attack | Special | Movement | Ultimate |
|---|---|---|---|---|
| **Knight** (tank) | Sword arc slash | Ground Slam: AoE stun around self | Shield Charge: dash that bashes and knocks back everything in its path | Whirlwind: 4 s spin, damage aura, 50% damage reduction |
| **Ranger** (ranged DPS) | Piercing arrow | Fan volley: 5 arrows in a cone | Backflip: leaps away from the aim direction and drops a caltrop trap | Arrow Rain: 5 s barrage at the aim point |
| **Mage** (AoE control) | Magic bolt | Frost Nova: slow/freeze around self | Blink: short teleport toward aim | Meteor: huge AoE after a 1 s telegraph |
| **Cleric** (support) | Holy orb (bounces) | Sanctuary: healing zone for allies | Holy Dash: dash that heals allies it passes through | Divine Light: revives all allies, heals the team, damages on-screen enemies |
| **Berserker** (bruiser) | Axe cleave (3rd hit of the combo is bigger) | Blood Frenzy: +attack speed and lifesteal for 5 s, costs HP | Leap Slam: jump to the aim point with an AoE on landing | Rampage: 10 s, grows in size, huge cleaves, heals on kill |
| **Rogue** (crit) | Fast twin-dagger stabs | Knife Ring: 12 knives thrown in 360° | Shadow Step: dash through enemies and mark them (marked enemies take guaranteed crits) | Shadow Clones: 3 clones copy the Rogue's attacks for 6 s |
| **Engineer** (turrets) | Rivet gun | Deploy Turret (max 2, auto-fires) | Rocket Boots: dash that leaves a fire trail | Tesla Tower: chain lightning for 8 s |
| **Necromancer** (summoner) | Soul bolt | Raise Dead: fallen enemies rise as skeleton allies (max 8) | Wraith Walk: 1 s incorporeal dash through enemies, which also chills them | Army of the Dead: 20 skeletons for 10 s |

Backlog ideas for 9+: Alchemist (thrown flasks), Monk (dash-strike combos), Bard (team buffs).

Downed state:
- At 0 HP a hero is downed.
- A teammate standing nearby for 3 s revives them at 30% HP.
- If everyone is downed, the run is over.
- Friendly fire is off.

## Enemies

| Enemy | Role |
|---|---|
| Swarmer | Fast and weak; most of the horde |
| Brute | Slow, tanky, heavy hits |
| Spitter | Keeps distance and fires projectiles |
| Exploder | Rushes in, telegraphs, explodes |
| Big Demon (boss) | Phase-based attack patterns, node-based |

Spawn director:
- Spawns just outside the camera on walkable tiles, in waves plus a constant trickle.
- Alive cap by player count: 150 / 200 / 250 / 300.
- Recycles enemies left more than ~1.5 screens behind.
- Enemy HP scales by player count: ×(1 + 0.35 × (n − 1)).
- Heroes get 0.5 s of i-frames after a contact hit.

## Progression — pick 1 of 3

- Enemies drop XP gems. XP is shared by the team.
- On a team level-up the game pauses and **every player picks their own card at the same time** in their own screen quadrant, with their own controller. Play resumes when everyone has picked.
- Upgrades are either stat modifiers (flat or %) or ability modifiers (e.g. `attack.pierce +1`, `movement.charges +1`).
- The pool holds about 16 generic upgrades plus about 4 per hero.
- Upgrades last for the whole run and reset on game over.
- XP needed per level: `6·L^1.35 + 4·L`, scaled by `1 + 0.35 × (players − 1)` (see `src/core/xp_curve.gd`).

## Levels and run flow

- Levels are tile maps (`TileMapLayer`, 16 px tiles). Wall tiles carry a custom `solid` flag that collision and pathfinding read.
- Each level has corridors with a steady trickle of enemies and 2–3 **arena rooms**. In an arena room the doors lock and waves run until the kill quota is met.
- A level ends at an **exit portal** that all living players must stand in.
- Run: Level 1 → Level 2 → Level 3 → Boss arena → Victory. Difficulty rises per level.
- Screen flow: Main menu → Character select (4 quadrants: join, pick, ready) → Levels → Victory / Game over → Main menu.
- Shared camera: follows the middle of the group with fixed zoom, and players can't leave the screen. Levels are designed for this.

## Technical architecture

### Rendering and frame pacing
- The game renders into a **640×360 viewport** (stretch mode `viewport`, aspect `expand`, scale mode `integer`) and is upscaled by a whole number: 3× at 1080p, 4× at 1440p, 6× at 4K. This makes 4K almost free on the GPU. With `expand`, extra screen space shows more world rather than black bars.
- **Compatibility renderer** (OpenGL): mature 2D batching and the broadest Mac/Windows support.
- `max_fps = 0` with V-Sync on: the game runs at the display's refresh rate. The stress test turns V-Sync off to measure real frame cost.
- Game simulation runs in `_process` with a variable delta, clamped to 1/30 s. Fast movers (dashes, projectiles) use swept movement so they can't tunnel through walls.

### Data-oriented horde
Nodes are too expensive for 300+ enemies at 120 fps, so hordes are **plain data**:
- `HordeSim` keeps all enemy state in packed arrays and updates it in one typed loop.
- **Rendering:** one `MultiMeshInstance2D` draws every enemy from a single atlas. Per-instance custom data carries animation frame, hit-flash and tint, read by a small canvas shader. The buffer is uploaded with a single `multimesh.buffer = …` per frame.
- **Y-sorting:** native `PackedInt32Array.sort()` on packed `(y << 10) | index` keys.
- **Spatial hash** (linked lists in packed arrays, 16 px cells), rebuilt every frame. It serves separation, contact damage, attack hit queries and projectile hits.
- **Flow field:** multi-source BFS from all living players over the tile grid. It runs on a `WorkerThreadPool` thread with double buffering and refreshes about every 0.2 s. Every enemy follows the field toward the nearest player.
- **Wall collision:** per-axis solid-tile lookups, with no physics engine.
- `ProjectileSim`, `PickupSim` (XP gems) and `FxSim` (particles) follow the same pattern.
- Heroes, bosses and summons (≤ 8 per player) are normal nodes.
- **Fallback if typed GDScript misses the 3 ms budget:** port only `HordeSim` + `ProjectileSim` to a C++ GDExtension behind the same API.

### Code layout
```
src/
  autoload/   Events (signal bus), InputRouter, GameState, PerfMonitor
  core/       PlayerInput, XpCurve, Stats, SpatialHash, FlowField
  sim/        HordeSim, ProjectileSim, PickupSim, FxSim
  camera/     shared camera
  heroes/     Hero (generic body), HeroData, Ability + reusable abilities, per-hero data
  enemies/    EnemyData, SpawnDirector, behaviours, boss
  upgrades/   UpgradeData, UpgradePool, data/*.tres
  levels/     Level, level data, arena rooms, exit portal
  ui/         menus, character select, HUD, level-up screen
tests/        headless test runner + test_*.gd
tools/        dev.sh helper, stress test scene
docs/         this document
```

### Input
- `InputRouter` (autoload) owns four `PlayerInput` slots and polls hardware directly, not through the InputMap. That keeps any mix of keyboard and gamepads separated per player.
- It reports join presses from unassigned devices.
- It handles hot-plug: an unplugged pad pauses the game, and a new device pressing A takes over the disconnected player.
- Menus navigate per player through `PlayerInput.ui_pressed()`, not Godot's global focus.

### Conventions
- Typed GDScript everywhere. Hot loops use locals and packed arrays.
- Systems talk through `Events` or explicit references, never `get_node` across scenes.
- Pure logic (stats, flow field, spatial hash, sims) doesn't reference autoloads, so it can be unit-tested headless.
- Every feature lands with tests where it has logic worth testing.

## Milestones

| # | Milestone | Status |
|---|---|---|
| 1 | Setup: project settings, autoloads, test runner, perf overlay, docs | done |
| 2 | Co-op movement: input router + join, hero move/aim/dash, shared camera, test room | |
| 3 | Horde tech: HordeSim, MultiMesh shader, spatial hash, threaded flow field, projectiles, pickups, stress test + **perf gate** | |
| 4 | Combat: ability framework, Knight / Ranger / Mage / Cleric, downed/revive, 4 enemy types | |
| 5 | Progression: stats and modifiers, upgrade pool, simultaneous level-up screen | |
| 6 | Levels & flow: 3 levels + boss, arena rooms, menus, HUD, scaling (**vertical slice**) | |
| 7 | Heroes 5–8: Berserker, Rogue, Engineer, Necromancer + summons | |
| 8 | Art & juice: pixel-art pack, particles, shake, SFX/music | |
| 9 | Export: macOS + Windows builds | |

## Verification

- `./tools/dev.sh test` runs the headless test suite. It compiles and loads every script and scene, then runs `tests/test_*.gd`. Any engine error fails the run.
- `./tools/dev.sh stress` runs the horde stress test (milestone 3+). It prints frame and sim timings and exits non-zero when it misses the targets.
- Movie Maker captures (`--write-movie shots/frame.png`) are used to check rendering.
- The F3 overlay shows FPS, frame times, per-system costs and entity counts in any build.
