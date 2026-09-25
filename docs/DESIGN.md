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
- Upgrades are either stat modifiers (flat or %) or ability modifiers. They're written as short effect lines in `UpgradeData.effects`:
  - `stat damage pct 0.1`
  - `stat max_hp flat 20`
  - `ability attack pierce 1`
  - `ability all area_pct 0.12`
- `UpgradePool.validate()` and the tests check every line against the known stats and mod keys.
- The library (`src/upgrades/data/upgrade_library.tres`) is generated by `tools/gen_upgrades.py`. It has 34 upgrades: 17 generic (including 1–2 epics) plus 4–5 per hero.
- **Offers:** 3 distinct cards per player, weighted by rarity (common 10, rare 4, epic 1.2). Hero-specific cards weigh ×1.6, and maxed cards never appear.
- **Runs:** each player's picks are stored in `GameState` and re-applied when the next level builds the heroes again.
- **Stats (`src/core/stats.gd`):** `value = (base + flat) × (1 + pct)`. The stat list is max HP, armor, move speed, damage, attack speed, crit chance, crit damage, pickup range, regen, ultimate charge rate, life on kill and revive speed.
- **Pick screen controls:** each player picks in their own area: one centred panel, two halves, or four quadrants. Gamepads use left/right + A. Keyboard players use A/D or arrows + Enter, or the mouse. Bots pick after 0.6 s.
- Upgrades last for the whole run and reset on game over.
- XP needed per level: `6·L^1.35 + 4·L`, scaled by `1 + 0.35 × (players − 1)` (see `src/core/xp_curve.gd`).

## Levels and run flow

- **Authoring:**
  - Levels are ASCII layouts in `LevelData` resources; the legend is in `level_data.gd`.
  - `tools/gen_levels.py` builds the run's layouts from rooms and corridors and writes `src/levels/data/level_*.tres` / `boss.tres` with each level's difficulty settings.
  - The sandbox `test_room.tres` is hand-written.
- **Rendering:** `Level` turns a layout into a `TileMapLayer` for rendering and a `LevelGrid` for collision and pathfinding.
- **Run order:** `src/levels/run_config.tres` lists Crypt Entrance → Flooded Halls → Bone Pits → Demon's Throne (boss). Each level sets:
  - enemy mix
  - an HP multiplier (1.0 / 1.35 / 1.8 / 2.2)
  - corridor pressure
  - arena quotas
  - a floor tint
- **`LevelDirector` runs the objectives:**
  - An **arena room** (digit tiles) activates when a living hero is 36+ px inside it. Stragglers are pulled in with the leader, every door touching the room turns solid, and the spawner switches to arena mode.
  - The room is cleared once its quota has spawned and nothing is left alive in it. Quotas are ×(1 + 0.4 per extra player).
  - Clearing opens the doors, drops a heart, and returns the spawner to the corridor trickle.
  - The **exit portal** opens when every arena is cleared. The level completes after all living heroes stand in it for 1 s.
  - The **boss level's** throne room spawns the Demon Lord instead of waves. Its death ends the run in victory.
- **HUD:**
  - The objective text sits under the XP bar.
  - A yellow arrow at the screen edge points to off-screen objectives (the next arena or the exit).
- **Spawner modes:**
  - CORRIDOR: off-screen trickle at a fraction of the alive cap.
  - ARENA: spawns on the room's floor at least 96 px from heroes, until the quota is spent.
  - OFF.
- **Boss (Demon Lord):**
  - Its body is a `HordeSim` entry, so every ability, projectile and zone hits it.
  - `BossDemon` moves it and runs three phases:
    - fireball fans and ground slams
    - plus fire rings and swarmer summons
    - enraged: faster, plus telegraphed charges
  - HP is 1800 × level multiplier × player-count scaling. It is immune to stun and slow.
- **Screens:** Main menu → Character select → Game (levels) → End screen (victory/defeat + stats) → Play again / Main menu.
  - **Main menu:** Start Run, Test Room (drop-in sandbox), Quit. Menus use Godot focus navigation, so keyboard, any gamepad or mouse all work.
  - **Character select:** 4 quadrants. Press A/Enter to join, left/right to browse the 8-hero roster (unreleased heroes show "Coming soon"), A to ready and B to un-ready or leave. The run starts 1.5 s after everyone is ready.
  - **`Game`:** builds a `World` per level, shows "LEVEL n" and "LEVEL CLEAR!" banners, and banks stats. A team wipe means defeat; the boss's death means victory.
  - **Pause:** Start or Esc opens it for any player, with Resume and Quit to menu. The press that closes it can't also trigger a dash.
- **Shared camera:** follows the middle of the group with fixed zoom, and players can't leave the screen. The leash blocks the player who is running away rather than dragging the others along.
- **Disconnects:** if an assigned controller is unplugged, the game pauses until it is reconnected, or until another controller presses A and takes over that player.
- **Bots** (`BotDriver`) follow the current objective with A* over the level grid and use their abilities. The test suite has four god-mode bots finish every level including the boss, and `./tools/dev.sh run res://src/main/game.tscn -- --bots=4 --level=4` shows a bot boss fight.

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
  core/       PlayerInput, LevelGrid (walkability + collision), XpCurve, Stats, SpatialHash, FlowField
  sim/        HordeSim, ProjectileSim, PickupSim, FxSim
  camera/     shared camera
  world/      World (gameplay root, fixed tick order), BotDriver (bot players for demos/stress tests)
  heroes/     Hero (body, 4 ability slots, downed/revive), HeroData, Ability (abstract) +
              reusable abilities (projectile, melee arc, area burst, dash, blink, zone, channel),
              data/<hero>.tres (generated by tools/gen_hero_data.py)
  enemies/    EnemyData + data/*.tres, SpawnDirector (corridor/arena modes), boss/BossDemon
  upgrades/   UpgradeData, UpgradePool, data/*.tres
  levels/     Level (tiles + grid + arena rooms from LevelData), LevelDirector (arenas, exit, boss),
              RunConfig, data/*.tres (generated by tools/gen_levels.py)
  ui/         HUD, level-up screen, main menu, character select, pause menu, end screen
  main/       Game (run controller: levels, banners, victory/defeat)
assets/fonts  Pixel5x8 proportional bitmap font (BMFont, generated), default theme font
tests/        headless test runner + test_*.gd
tools/        dev.sh helper, stress test scene
docs/         this document
```

### Heroes and abilities
- `HeroData` holds base stats plus four `Ability` resources (attack, special, movement, ultimate). Each `Hero` duplicates them so duplicate picks never share cooldowns.
- Abilities are small reusable scripts configured by data:
  - `ProjectileAbility`: shots, volleys, rings, splash, pierce, bounce
  - `MeleeArcAbility`: cones, combo finishers
  - `AreaBurstAbility`: self, aim point or whole screen; optional telegraph delay, heal and revive
  - `DashAbility`: bash, stun, slow, mark, ally heal, trap drop, fire trail
  - `BlinkAbility`
  - `ZoneAbility`: lasting heal/damage areas
  - `ChannelAbility`: Whirlwind-style stances
- Heroes 5–8 add more ability types:
  - `BuffAbility`: timed self-buffs (damage, attack speed, area, lifesteal, heal-on-kill, damage taken, growth). Blood Frenzy and Rampage use it.
  - `SummonAbility`: skeletons (optionally raised from corpses of the last 5 s), turrets and tesla towers, capped per ability with the oldest replaced.
  - `ShadowClonesAbility`: orbiting clones repeat each attack.
  - Leap arcs for `DashAbility`, with landing impacts.
- **Buff hooks:** the hero multiplies/sums hooks over its four abilities (`damage_factor`, `attack_speed_factor`, `area_factor`, `lifesteal`, …).
- **Minions:** they are nodes ticked by the World.
  - Skeletons walk to and melee the nearest enemy and take contact damage. Turrets shoot rivets. Tesla towers chain lightning across 5 targets.
  - Minion damage counts toward the owner's ultimate charge and lifesteal.
  - They retarget every 0.4 s.
  - Caps: Raise Dead 8, Army of the Dead 16, turrets 2, towers 1.
- Upgrades tweak abilities through `Ability.mods` (e.g. `pierce`, `count`, `area_pct`, `max_active`, `minion_hp_pct`). There are 50 upgrades: 17 generic plus 4–5 per hero.
- Hero tuning lives in `tools/gen_hero_data.py`, which writes `src/heroes/data/*.tres`. Edit the table and re-run it, or edit the `.tres` in the Godot inspector.
- **Ultimate charge:** damage dealt ÷ the hero's `ult_cost`, plus 1% per second passively. The player ring pulses when the ultimate is ready.
- **Movement abilities:** give i-frames (0.15–0.3 s) and never share a cooldown with other slots.
- Channels (Whirlwind) block attack, special and ultimate, but not movement.
- **Downed:**
  - A downed hero stops being a target, and enemies retarget the living.
  - A teammate standing within 20 px for 3 s revives them at 30% HP with 2 s of i-frames. Progress decays when nobody helps.
  - Holy Dash adds 1.5 s of revive progress, and Divine Light revives everyone.
  - In test rooms, a wiped team gets back up after 3 s. In a run, a wipe ends the run (milestone 6).

### Enemy behaviours
- **Chaser:** flow field; direct steering within 2 tiles of a hero.
- **Ranged (spitter):** holds position inside its range, backs off when heroes get closer than 55% of it, and fires when it has line of sight.
- **Exploder:** lights its fuse when close, then blasts heroes in its radius. Killing it during the fuse cancels the blast, and self-destructs drop no XP.
- **Knockback:** damage pushes enemies away from the hit source, scaled per type (brutes resist). Stun freezes, slow halves speed, and marks make enemies take ×1.75 damage.

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
| 2 | Co-op movement: input router + join, hero move/aim/dash, shared camera, test room | done |
| 3 | Horde tech: HordeSim, MultiMesh shader, spatial hash, threaded flow field, projectiles, pickups, stress test + **perf gate** | done: gate passed in GDScript |
| 4 | Combat: ability framework, Knight / Ranger / Mage / Cleric, downed/revive, 4 enemy types | done |
| 5 | Progression: stats and modifiers, upgrade pool, simultaneous level-up screen | done |
| 6 | Levels & flow: 3 levels + boss, arena rooms, menus, HUD, scaling (**vertical slice**) | done |
| 7 | Heroes 5–8: Berserker, Rogue, Engineer, Necromancer + summons | done |
| 8 | Art & juice: pixel-art pack, particles, shake, SFX/music | |
| 9 | Export: macOS + Windows builds | |

## Performance results

Measured with `./tools/dev.sh stress` on 2026-09-25: MacBook Air M2 (fanless), macOS fullscreen **3840×2410**, which is more pixels than 4K. Load: 300 enemies, 4 bot heroes, a 400-projectile cap (~398 alive) and ~160–230 XP gems.

| Run | Avg frame | p99 | Max | Sim (CPU) |
|---|---|---|---|---|
| Uncapped, V-Sync off, 10–30 s | 3.7–4.2 ms (240–270 fps) | 5.2 ms | 6.4 ms | 1.5–1.7 ms |
| Uncapped, 30 s, after the laptop heats up | 4.2 ms | 12.7 ms | 44 ms | 1.7 ms |
| **Capped at 120 fps, 60 s** | 8.33 ms (7200/7200 frames) | 8.47 ms | 10.8 ms | 2.7 ms |

Breakdown per frame (uncapped): horde 0.63 ms, projectiles 0.37 ms, heroes 0.13 ms, instance buffers 0.33 ms, draw submission 0.23 ms.

- **Gate verdict:** the typed GDScript sims meet the budget, so no GDExtension port is needed.
- **The p99 failures** only happen after ~17 s of uncapped rendering at ~250 fps on the fanless M2 Air. That points to thermal throttling: frames go to 13 ms while game code stays at 1.7 ms. At 120 fps (the target), the same machine holds every frame for a full minute.
- **Why sim cost rises when capped:** the CPU clocks down between frames, so sim time goes up to 2.7 ms. That still leaves most of the 8.3 ms budget free, but milestone 4+ features (enemy behaviours, abilities, particles) must stay in budget.
- **Re-check after milestones 4 and 7** with `./tools/dev.sh stress --fullscreen --max-fps=120 --seconds=60`.
- **Milestone 7 re-check** with summoner-heavy heroes and ultimates kept always ready (`--heroes=necromancer,necromancer,engineer,rogue --ult-spam`):
  - Averaged ~46 minions on top of 300 enemies, ~360 projectiles and 110–230 gems.
  - Minions cost 0.3 ms and the whole frame 6.9 ms (146 fps).
  - Measured on an already heat-throttled Air: the plain baseline read 6.5 ms / 3.2 ms sim in the same state, versus 4.1 ms / 1.7 ms when cool. Summoners add about 0.1–0.3 ms over that throttled baseline.
  - After the change that writes only the instance fields that change, re-measure on a cool machine or a desktop.

## Verification

- `./tools/dev.sh test` runs the headless test suite. It compiles and loads every script and scene, then runs `tests/test_*.gd`. Any engine error fails the run.
- `./tools/dev.sh stress [--fullscreen] [--max-fps=120] [--seconds=60] [--log-slow]` runs the horde stress test. It prints frame, sim and draw timings plus entity counts, and exits non-zero when it misses the targets. Uncapped runs check avg ≤ 6 ms and p99 ≤ 8.3 ms. Capped runs check that p99 stays within 125% of the frame budget.
- Movie Maker captures (`--write-movie shots/frame.png`) are used to check rendering.
- The F3 overlay shows FPS, frame times, per-system costs and entity counts in any build.
