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
| Map (hold) | Back / Select | Tab (or M) |
| Pause | Start | Esc |
| Join (character select) | A / Start | Enter / Space |

**Button prompts** use each player's own device: the Pixel5x8 font has button icons in the private-use range from U+E000 (Xbox, PlayStation and Nintendo face buttons, bumpers, triggers, Start/Back, and mouse buttons), and `PlayerInput.glyph(action)` picks the set from the pad's name (PS / DualSense / DualShock → PlayStation; Nintendo / Switch / Pro Controller → Nintendo; anything else → Xbox). Keyboard players see key names like [Q]. Every prompt (character select, pick screen, HUD, tips, controls card, pause pages) uses it.

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
| **Necromancer** (summoner) | Soul bolt | Raise Dead: fallen enemies rise as skeleton allies (max 8) | Wraith Walk: 1 s incorporeal dash through enemies, which also chills them | Army of the Dead: 16 skeletons for 10 s |

Backlog ideas for 9+: Alchemist (thrown flasks), Monk (dash-strike combos), Bard (team buffs).

Downed state:
- At 0 HP a hero is downed.
- A teammate standing nearby for 3 s revives them at 30% HP.
- **Team lives:** the team has 1 life per level (hearts next to the XP bar). If everyone is downed and a life is left, it's spent on a **Second Wind**: everyone gets back up at 50% HP with 2 s of invulnerability, enemies within 100 px of each hero are shoved away and stunned for 1 s, and enemy shots on screen vanish. With no life left, the run is over. The end screen counts the Second Winds used.
- Friendly fire is off.

## Enemies

| Enemy | Role |
|---|---|
| Swarmer | Fast and weak; most of the horde |
| Brute | Slow, tanky, heavy hits |
| Spitter | Keeps distance and fires projectiles |
| Exploder | Rushes in, telegraphs, explodes |
| Big Demon (boss) | Phase-based attack patterns, node-based |

**Elites** (`Elites`, from the second level on; always in the test room): about 1 in 40 spawns of the four kinds above arrives as an elite, at most 4 alive at once (×0.5 on Casual, ×2 on Hard).
- An elite is drawn 1.5× bigger with a pulsing outline in its trait's colour (the instance shader draws it from a code in the tint channel), with its hurtbox and footprint scaled to match, ×6 HP, ×1.25 damage and half the knockback.
- Traits: **Swift** (cyan, +60% speed), **Volatile** (orange: blows up 0.6 s after it dies, telegraphed, 25 damage in 36 px), **Splitting** (green: breaks into 3 ordinary enemies of its kind).
- Each drops a big XP gem (10) and has a 30% chance of a heart.
- Elites are extra enemy types made at setup from the base ones (`Elites.variants()`), so the horde needs nothing new per enemy.

## Difficulty and records

Chosen in character select with LB / RB (Q / E); Hard unlocks after a win on Normal.

| | Enemy HP | Enemy damage | Spawn rate | Team lives per level | Elites |
|---|---|---|---|---|---|
| Casual | ×0.75 | ×0.7 | ×0.8 | 2 | ×0.5 |
| Normal | ×1 | ×1 | ×1 | 1 | ×1 |
| Hard | ×1.3 | ×1.3 | ×1.2 | 0 | ×2 |

- Enemy damage is a real multiplier (`HordeSim.damage_mult`): contact, spit, exploder and elite blasts, spikes and every boss attack.
- **Profile** (`Profile`, `user://profile.cfg`): runs played, wins and best time per difficulty, and the hardest difficulty won with each hero, shown as a bronze / silver / gold star by the hero's name in character select. The end screen announces "NEW BEST TIME!" and "HARD UNLOCKED!".

Spawn director:
- Spawns just outside the camera on walkable tiles, in waves plus a constant trickle. Off-screen spawns stay at least 110 px from every hero.
- **Spawn portals:** anything that appears where players can see it (arena waves, nests, boss summons) comes through a portal first. `SpawnDirector.queue_spawn()` opens a swirling dark portal and the enemy steps out 0.5 s later. Enemies waiting in portals count toward the cap and the arena's enemies left, and an arena can't clear while any are waiting.
- Alive cap by player count: 150 / 200 / 250 / 300.
- Recycles enemies left more than ~1.5 screens behind.
- Enemy HP scales by player count: ×(1 + 0.35 × (n − 1)).
- Heroes get 0.5 s of i-frames after a contact hit, 1.5 s when a level starts (or they drop in), and 0.75 s when play resumes after picking upgrades or the pause menu.
- **Boss and nests** don't come in bigger numbers with more players, so their HP scales on its own curve: ×(0.6 + 0.45 × (n − 1)), i.e. 0.6 solo up to 1.95 for four (ordinary enemies stay at ×(1 + 0.35 × (n − 1))).

## Progression — pick 1 of 3

- Enemies drop XP gems. XP is shared by the team.
- On a team level-up the game pauses and **every player picks their own card at the same time** in their own screen quadrant, with their own controller. Play resumes when everyone has picked.
- **Picks wait for arena fights to end:** while an arena fight is on, level-up rounds queue (the HUD shows "+2" next to the level) and open back to back 1 s after the arena is cleared. In corridors, from chests and during the boss fight they open at once.
- Upgrades that only help with teammates (Guardian Angel) are never offered to a solo player (`UpgradeData.team_only`).
- Upgrades are either stat modifiers (flat or %) or ability modifiers. They're written as short effect lines in `UpgradeData.effects`:
  - `stat damage pct 0.1`
  - `stat max_hp flat 20`
  - `ability attack pierce 1`
  - `ability all area_pct 0.12`
- `UpgradePool.validate()` and the tests check every line against the known stats and mod keys.
- The library (`src/upgrades/data/upgrade_library.tres`) is generated by `tools/gen_upgrades.py`. It has 62 upgrades: 17 generic (including 1–2 epics), 4–5 per hero, and 12 elemental ones (below).
- **Offers:** 3 distinct cards per player, weighted by rarity (common 10, rare 4, epic 1.2). Hero-specific cards weigh ×1.6, and maxed cards never appear. A card with `requires` is only offered once that upgrade was taken.

### Elemental attacks

Four chains of three upgrades give a hero's **attack** an element. Each tier needs the one before it, and the third is the big one (epic). All numbers scale with the damage of the hit that applied them.

| Element | Tier I | Tier II | Tier III |
|---|---|---|---|
| **Fire** | *Ember Strikes*: burn for 50% of the hit per second, 3 s | *Wildfire*: 80% per second, 4 s; burning enemies set enemies touching them alight | *Inferno*: burning enemies explode when they die (3× the burn per second, 38 px) and set everything they hit ablaze, so it chains |
| **Ice** | *Frostbite*: chilled, 40% slower for 2.5 s | *Permafrost*: every 3rd chill freezes the enemy solid for 1.5 s | *Shatter*: frozen enemies take double damage from attacks, and die in a nova that chills everything near them twice (freezing most of them) |
| **Poison** | *Venom*: stacks up to 4; each stack deals 25% of the hit per second for 4 s and slows 6% | *Virulence*: up to 8 stacks, 6 s | *Plague*: poisoned enemies leave a toxic cloud (2.5 s) that adds a stack every 0.5 s to everything inside (at most 10 clouds) |
| **Lightning** | *Static Charge*: every hit staggers its target (small shove and stun) and zaps the nearest enemy within 56 px for 50% | *Arc Lightning*: zaps chain through 3 enemies for 60% and stun them | *Thunderstrike*: every 5th hit calls down a bolt (3× damage, 0.8 s stun) that chains through 6 enemies |

- Elements ride on the attack only: projectile attacks log the enemies they hit, and melee swings (and the Rogue's shadow clones) pass their hits to `Elements.on_attack_hit()`. Specials and ultimates don't carry them.
- Heroes can mix elements. Tiers are ability mods on the attack (`ability attack fire 1` per tier), so they need no special handling in the upgrade code.
- **Statuses** live in `HordeSim` arrays (burn, poison stacks, chill, frost, frozen). Damage over time ticks in the horde's movement loop and is credited to the last hero to hit, for kills and ultimate charge. Enemies are tinted by status: frozen, burning, poisoned or chilled.
- **Who is affected.** Barrels and urns take no statuses. Bosses burn and get poisoned, but never freeze or slow.
- **Death effects** (Inferno, Shatter, Plague) are logged when an enemy dies, and at most 6 play per frame, so chains ripple outward. Fire spreading is checked for a share of the horde every frame.
- **Cost.** In the worst case (all four elements at tier III on four heroes firing ~1000 elemental shots a second), the element code costs ~0.04 ms per frame. The stress test with `--elements` still meets the targets: 4.7 ms average, 7.9 ms p99.
- **Runs:** each player's picks are stored in `GameState` and re-applied when the next level builds the heroes again.
- **Stats (`src/core/stats.gd`):** `value = (base + flat) × (1 + pct)`. The stat list is max HP, armor, move speed, damage, attack speed, crit chance, crit damage, pickup range, regen, ultimate charge rate, life on kill and revive speed.
- **Pick screen controls:** each player picks in their own area: one centred panel, two halves, or four quadrants. Gamepads use left/right + A. Keyboard players use A/D or arrows + Enter, or the mouse. Bots pick after 0.6 s.
- **Accidental-pick guard:** human input is ignored for the first 0.35 s after the cards appear, so a player mashing A (dash) or left-click (attack) can't pick one by accident.
- **Rounds:** `GameState.pending_rounds` queues them oldest first, each labelled with the team level it was earned at, or as a treasure (chest, shown first) or bonus (debug) round, so titles are always right.
  - Once everyone has picked, the result stays up for 0.3 s so the last player sees "PICKED!" too.
  - With 3–4 players each panel sits in its player's HUD corner; with 2 the lower slot is on the left.
  - Rounds wait until the level banner has gone. Rounds earned after the exit is reached, or once the run is won or lost, carry over to the next level instead of opening then.
- Upgrades last for the whole run and reset on game over.
- XP needed per level: `6·L^1.35 + 4·L`, scaled by `1 + 0.35 × (players − 1)` (see `src/core/xp_curve.gd`).

## Levels and run flow

- **Map variety:** levels 1–3 each have a second layout (`level_1b` ...: same size, quotas and theme, but different room shapes, route, and chest and shrine spots). Every run picks one per level from `GameState.run_seed` and mirrors it left-right and/or upside down (the boss level only left-right): `RunConfig.layout_for()`, `LevelData.mirrored()`. That's 8 versions of each normal level. `--layout=a|b` and `--mirror=none|h|v|hv` pin them for debugging. The level tests check every layout in every mirror, and bots play every second layout mirrored.
- **Authoring:**
  - Levels are ASCII layouts in `LevelData` resources; the legend is in `level_data.gd`.
  - `tools/gen_levels.py` builds the run's layouts from shaped rooms, halls, terrain and props, and writes `src/levels/data/level_*.tres` / `boss.tres` with each level's difficulty settings and theme (see Map features).
  - The sandbox `test_room.tres` is hand-written.
- **Rendering:** `Level` turns a layout into a `TileMapLayer` for rendering and a `LevelGrid` for collision and pathfinding.
- **Run order:** `src/levels/run_config.tres` lists Crypt Entrance → Flooded Halls → Bone Pits → Demon's Throne (boss). Each level sets:
  - enemy mix
  - an HP multiplier (1.0 / 1.35 / 1.8 / 2.2)
  - corridor pressure
  - arena quotas
  - a theme (tile sheet and decorations) and an optional tint
- **`LevelDirector` runs the objectives:**
  - An **arena room** (digit tiles) activates when a living hero is 36+ px inside it. Stragglers are pulled in with the leader, every door touching the room turns solid, and the spawner switches to arena mode.
  - The quota comes in **waves**: 2 (45% / 55%) up to 60 enemies, 3 (30% / 33% / 37%) above. The next wave comes once 25% or less of the current one is left (or after 12 s), after a 2 s breather, with a "WAVE 2/3" callout and a horn.
  - The room is cleared once its last wave has spawned and nothing is left alive in it. Quotas are ×(1 + 0.4 per extra player). The objective shows the wave and the enemies left: not yet spawned (this wave and later ones), in portals, and alive inside.
  - **Clearing an arena** (and so opening the exit) pulls every XP gem on the level to the nearest hero. Gems still lying around when a level ends are banked as XP, and each hero's ultimate charge carries over to the next level.
  - Clearing opens the doors, drops a heart, and returns the spawner to the corridor trickle.
  - The **exit portal** opens when every arena is cleared. The level completes after all living heroes stand in it for 1 s.
  - The **boss level's** throne room spawns the Demon Lord instead of waves. Its death ends the run in victory.
- **HUD:**
  - The objective text sits under the XP bar.
  - A yellow arrow at the screen edge points to off-screen objectives (the next arena or the exit). The next arena is the one closest **on foot** from the team (`LevelGrid.walk_distances`, a BFS where walls, closed doors and chasms block and props don't), not in a straight line.
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
  - **Every attack is telegraphed** during its wind-up: the boss glows hot pink (a flash shader, which hit flashes can't wash out) and growls, and the warning is drawn above the horde:
    - slam: its exact circle filling up
    - charge: a band as wide as what it hits
    - fan: one aim line per fireball, with the aim locked when the wind-up starts
    - fire ring: a ring of turning dots around the boss
    - summon: the adds' spawn portals
  - HP is 1800 × level multiplier × player-count scaling. It is immune to stun and slow.
- **Screens:** Main menu → Character select → Game (levels) → End screen → Play again / Change heroes / Main menu.
  - **End screen:** difficulty, levels, enemies, team level, time and Second Winds; any records set; and a table of every player's kills, damage dealt and taken, downs, revives given and biggest hit, with awards: Slayer (most kills), Medic (most revives), Tank (most damage taken), Sharpshooter (biggest hit) - only with teammates to beat - and Untouchable (never downed). **Play again** starts a new run right away with the same team, heroes and difficulty; **Change heroes** goes to character select with everyone still joined and their last hero picked.
  - **Main menu:** Start Run, Test Room (drop-in sandbox), Options, Quit. The main, pause and end menus use Godot focus navigation, so keyboard, any gamepad or mouse all work, with move/confirm sounds (`UiSounds`).
  - **Character select:** 4 quadrants. Each shows the hero running on the spot, toughness / damage / speed as pips, a difficulty tag (Easy / Medium / Hard) and the four abilities with that player's own buttons.
    - Press A/Enter to join (holding that button doesn't also ready you up).
    - Left/right to browse the 8-hero roster.
    - A/Enter to ready, B/Esc to un-ready or leave.
    - When everyone who joined is ready, any of them presses A/Enter (or Start on a gamepad) to begin. There is no countdown.
    - With nobody joined, B/Esc/Backspace returns to the main menu. The press that makes the last player leave doesn't count.
  - **Enter with Alt held** is the fullscreen shortcut and never counts as a confirm press, even if Alt is let go first.
  - **`Game`:** builds a `World` per level, shows "LEVEL n" and "LEVEL CLEAR!" banners, and banks stats. A team wipe means defeat; the boss's death means victory.
  - **Pause:** Start or Esc opens it for any player: Resume, Controls (every player's buttons, abilities and hero blurb), Builds (every player's upgrades: elements at their highest tier, the rest with stack counts), Options, and Quit to menu, which needs a second press within 3 s. Pause screens draw above the level banners.
  - **Learning by playing:**
    - A **controls card** next to each player's HUD panel lists their four buttons at the start of a run (and in the test room); each line greys out once used, and the card fades once attack, special and movement have been used, or after 20 s.
    - **Tips**, each shown once ever (remembered in `Settings.seen_tips`, off with the Tips option): a teammate is down and how to revive them, an arena's doors seal, the ultimate is ready (with the button), picks are waiting for the arena, the exit is open, and what chests and shrines do.
    - Chests and shrines explain themselves when a hero comes within 48 px ("Bonus upgrade for everyone", a blessing's effect).
    - At the exit, the objective says who's being waited for ("Waiting for P2 at the exit").
  - **Options** (`OptionsMenu`, from the main menu and the pause menu): volume, music, sounds, fullscreen, screen shake (off / low / full), damage numbers (all / crits only / off), reduce flashing (softer hit flashes, no invulnerability blinking, dimmer screen-wide bursts), controller rumble, player colours (default or a colour-blind friendly set: orange, sky blue, white, reddish purple), gamepad aim assist (off / ±10° / ±20°, locks onto the enemy nearest the aim within 160 px) and tips. Up/down picks a row, left/right or a click changes it (right-click goes back); volumes stop at 0% and 100%. Everything applies and saves at once.
  - **`Settings` autoload** owns `user://settings.cfg` (volumes, fullscreen, comfort options, which tips were seen). The test runner points it at a temporary file with defaults, so tests never see a player's settings. The press that closes it can't also trigger a dash. It can't be opened under the victory/defeat banner.
  - **End screen:** its buttons ignore input for 0.6 s, so a player still mashing from the fight doesn't skip the results.
  - **Test Room:** with nobody joined, Esc (or Start/B on a pad) goes back to the menu.
- **Shared camera:** follows the middle of the group with fixed zoom, and players can't leave the screen. The leash blocks the player who is running away rather than dragging the others along.
- **Disconnects:** if an assigned controller is unplugged, the game pauses until it is reconnected, or until another controller presses A and takes over that player.
- **Bots** (`BotDriver`) follow the current objective with A* over the level grid and use their abilities. The test suite has four god-mode bots finish every level including the boss, and `./tools/dev.sh run res://src/main/game.tscn -- --bots=4 --level=4` shows a bot boss fight.

## Map features

What makes the levels play differently, beyond their shapes:

| Layout char | Feature | How it plays |
|---|---|---|
| `~` | Water | Everyone walks at 60% speed. Bots avoid it when they can. |
| `:` | Chasm (lava on the throne level) | Can't be walked on. Shots and line of sight cross it. An enemy shoved toward it harder than 30 px/s goes over the edge and dies. The last hero to hit or push it gets the kill, and its XP lands on the nearest floor. |
| `^` | Spike trap | Retracted, then warning, then up, on a 3 s cycle, firing in diagonal waves. When the spikes shoot up they stab everyone on them: heroes take 14, enemies 24 × the level's enemy HP multiplier. |
| `b` | Explosive barrel | Breaks in one hit, then blows up 0.05 s later: 40 × HP multiplier with big knockback. It breaks other barrels (chains) and never hurts heroes. |
| `u` | Urn | Breaks in one hit and scatters 6 XP (sometimes a heart). |
| `N` | Nest | Spawns 2 enemies from the level's mix every ~2.6 s while a hero is within 230 px. Arena nests sleep until the fight starts, and an arena with nests clears only once they're destroyed ("Destroy the nests!"). |
| `C` | Treasure chest | Touch it: the whole team gets an extra upgrade round ("TREASURE!"). |
| `A` | Shrine | Touch it for a team blessing, shown on the shrine: Fury (+50% damage, 30 s), Haste (+30% move and attack speed, 30 s), Life (full heal, revive everyone) or Wrath (smite everything on screen). |

- **Implementation.** Barrels, urns and nests are stationary `HordeSim` entries (`EnemyData` behaviours `OBJECT` / `NEST`), so every attack already hits them. They block walking on their tile (`LevelGrid.set_blocker`) until destroyed, but not shots. Objects aren't enemies: they give no kill credit, corpses or XP gems, don't count toward the spawner's cap, and bots and minions don't target them. Chests and shrines are `Interactable` nodes.
- **Terrain.** `LevelGrid` keeps `solid` (walking: walls, closed doors, chasms, props) apart from `shot_solid` (projectiles and sight: walls and closed doors). It also stores terrain per tile and logs walkability changes, so the bots' A* only updates the cells that changed.
- **Arena rooms.** Each arena is found by flood fill from its digit tiles, so everything inside its walls belongs to it: water, traps, chasms and props. The level test checks that shutting an arena's doors seals it.
- **Themes.** Each level names a tile sheet (`assets/tiles/tiles_<theme>.png`: crypt, flooded, bones, throne). Water and chasm/lava tiles are animated. The level is decorated from a per-tile hash:
  - floor clutter per theme
  - cobwebs in room corners
  - banners, chains and cracks on walls
  - wall torches with an additive, flickering light (`TorchLights`)
- **Layouts** come from `tools/gen_levels.py`:
  - Shapes: rectangles, octagons, discs, organic caves and rings around pits.
  - Halls stop at the first tile of the room they run into, so they meet round rooms at the edge.
  - Walls are added around everything, and corridor floor touching an arena becomes its doors.
- **Minimap.** Hold Tab / M (Back on a gamepad). The level keeps running.
  - It shows only the tiles that have been on screen (`MapReveal`).
  - Arenas are coloured by state: idle, active or cleared.
  - It marks locked doors, the exit, the objective, nests, chests, shrines, the boss, enemies, heroes and the camera view.
  - Seen tiles live in a 1 px-per-tile image that is repainted only where something changed.

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
- **Two shapes per enemy.** An enemy's position is its feet. A small **footprint circle** there (`radius`) handles walls, crowding, contact damage and ground-level attacks (slashes, slams, zones). A **hurtbox** (`hurt_size`, a box standing on the feet and as big as the drawn body) is what projectiles hit, so a shot that visibly crosses the head connects and one passing under the feet doesn't. `tests/test_hurtboxes.gd` checks every hurtbox against its sprite. Projectiles search the hash down to the tallest body alive (a boss only widens the search while it lives).
- Enemy shots hit a circle around the **middle of a hero's body**, not the feet; the boss aims its fireball fans at it.
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
- Upgrades tweak abilities through `Ability.mods` (e.g. `pierce`, `count`, `area_pct`, `max_active`, `minion_hp_pct`). There are 62 upgrades: 17 generic, 4–5 per hero, and 12 elemental.
- Hero tuning lives in `tools/gen_hero_data.py`, which writes `src/heroes/data/*.tres`. Edit the table and re-run it, or edit the `.tres` in the Godot inspector.
- **Ultimate charge:** damage dealt ÷ the hero's `ult_cost`, plus 1% per second passively. The player ring pulses when the ultimate is ready.
- **Critical hits:**
  - Every hit rolls the attacker's crit chance: base 5%, Rogue 15%, Keen Eye +6%, Deadly Precision +8%.
  - A crit deals ×crit damage: base 1.75, +0.35 per Brutal Crits.
  - Projectiles roll once at spawn (crit shots glow and keep the crit through pierce and splash).
  - Melee swings, bursts, zone ticks, dashes, turrets, skeletons and tesla chains roll per enemy per hit.
  - Rogue-marked enemies always take crits, never multiplied twice.
- **Movement abilities:** give i-frames (0.15–0.3 s) and never share a cooldown with other slots.
- Channels (Whirlwind) block attack, special and ultimate, but not movement.
- **Downed:**
  - A downed hero stops being a target, and enemies retarget the living.
  - A teammate standing within 20 px for 3 s revives them at 30% HP with 2 s of i-frames. Progress decays when nobody helps.
  - Holy Dash adds 1.5 s of revive progress, and Divine Light revives everyone.
  - In test rooms, a wiped team gets back up after 3 s. In a run, a wipe ends the run (milestone 6).

### Enemy behaviours
- **Chaser:** flow field; direct steering within 2 tiles of a hero.
- **Ranged (spitter):** holds position inside its range, backs off when heroes get closer than 55% of it. When its cooldown is up and it has line of sight, it stands still and glows hot pink for 0.4 s (its shot pose), then fires at the nearest hero. It only starts a shot while it's inside the camera view, so nothing fires from off screen.
- **Exploder:** lights its fuse when close, then blasts heroes in its radius that it has line of sight to (walls stop it, like the boss slam). Killing it during the fuse cancels the blast, and self-destructs drop no XP.
- **Knockback:** damage pushes enemies away from the hit source, scaled per type (brutes resist). Stun freezes, slow halves speed, and marks make enemies take ×1.75 damage.

### Input
- `InputRouter` (autoload) owns four `PlayerInput` slots and polls hardware directly, not through the InputMap. That keeps any mix of keyboard and gamepads separated per player.
- It reports join presses from unassigned devices. The button used to join counts as already held, so it doesn't also trigger "ready" in menus or a dash in game.
- It handles hot-plug: an unplugged pad pauses the game, and a new device pressing A takes over the disconnected player.
- Character select and the level-up screen navigate per player through `PlayerInput.ui_pressed()`; the main, pause and end menus use Godot's focus, so any device can drive them.

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
| 8 | Art & juice: pixel-art pack, particles, shake, SFX/music | done (generated art; 0x72 pack swap pending your OK) |
| 9 | Export: macOS + Windows builds | presets + icon ready; needs export templates installed to build |
| 10 | Map features: minimap, terrain (water, chasms, spikes), barrels / urns / nests, chests and shrines, level themes + decor, redesigned levels | done |
| 11 | Player-experience pass: run-flow fixes, readability (telegraphs, portals, outlines), game feel (feedback, hitstop, audio), pacing (waves, team lives, held picks, solo fairness), options + accessibility, onboarding (button icons, tips, controls card), replay (stats and awards, difficulty and records, map variety, elites) | done |

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

## Art, effects and audio

- **Art:** all sprites, tiles and the UI font are generated by `tools/gen_placeholder_art.gd` (deterministic and license-free):
  - 8 heroes (idle/run/dash/downed)
  - 5 enemy kinds (walk + action frames)
  - a 64×64 demon boss
  - projectiles, pickups and particle blobs
  - dungeon tiles
  - the Pixel5x8 font

  The planned swap to the CC0 0x72 "DungeonTileset II" pack only changes the PNGs and the atlas coordinates.
- **Particles:** `FxSim` draws up to 700 sprite particles through one coloured MultiMesh:
  - hit sparks (≤ 40/frame)
  - death puffs in each enemy's colour (≤ 30/frame)
  - explosion debris, dash dust, hurt and pickup sparkles, level-up bursts

  Oldest particles are overwritten, so cost is bounded (~0.1 ms).
- **Readability** (what's dangerous, and where you are):
  - **Draw order** (bottom to top): ground effects, props, gems, horde, hearts, warnings (`WarnFx`: telegraphs, fuses, spawn portals), heroes and bosses, particles, effects, damage numbers, **all projectiles**, then the hero overlay. Enemies never hide a warning, and nothing hides a shot.
  - **Hostile = hot pink** (`FxLayer.DANGER`): every enemy projectile uses it (spit and boss fireballs are pink orbs with a white core and a dark outline) and throbs in the shader, and so does every enemy warning. Heroes' own telegraphs (the Mage's Meteor) are dashed and in the caster's colour. The Cleric's orb is pale gold.
  - **Exploders:** a lit fuse shows as a filling circle exactly as big as the blast, with a hiss; it follows the fuse and vanishes if the exploder dies first.
  - **Heroes** have a 1 px outline in their player colour (`hero_outline.gdshader`), so two players on the same hero, or the dark Rogue and Necromancer on dark floors, are easy to find. A "P1" tag shows over each hero for 3 s at level start, after a revive and while downed. Reticles are drawn above everything (`HeroOverlay`).
  - Hearts are drawn above the horde and marked on the minimap; shrine blessings ring heroes in pale gold rather than a player-like colour. A heart heals 25% of max HP and only goes to a hurt hero: the most hurt one in range, never one at full HP. Holy Dash also heals the Cleric for half as much, so it works solo.
  - Lines 1 px wide are drawn as line primitives: with vertex snapping on, a 1 px quad at an angle collapses to nothing.
- **Feedback** (feel every hit, never miss a downed friend):
  - **Getting hit:** rumble scaled to the share of HP lost, the player's HUD panel flashes red, and hits of 15%+ of max HP shake the screen and show a big red number. Heroes' numbers are never pushed out by the horde's. Each player's hurt sound has its own pitch.
  - **Low HP (≤ 30%):** the hero's outline and HUD panel pulse red; crossing the line plays a heartbeat (at most every 3 s) and a rumble.
  - **Invulnerability looks different by cause:** blink after a hit, bright while dashing, a gold shimmer after a revive.
  - **Abilities:** the special and movement ability ping (a ring, plus a tick for the special) and flash their HUD bar when they come back; a press that can't do anything (on cooldown, no ult charge, channelling) flashes the bar red with a soft blip. The ultimate announces itself once per charge: a chime, a rumble and "ULT!".
  - **Downed:** a pulsing "!" and "P1" over the body, a dashed circle showing where to stand, and the revive progress as a ring; a rising tone while someone revives, and a "help" ping (at most every 3 s) while nobody does. The HUD's "DOWN! revive me" blinks.
  - **Hitstop** (a world-level freeze, the HUD keeps running): 0.08 s on a boss phase change; 0.3 s then 0.6 s of slow motion on the boss's death. Ordinary hits never freeze the game.
- **Damage numbers:** one node draws up to 40 numbers.
  - **Crits** always get a gold double-size number with "!" (e.g. `14!`), a gold star burst and a "tink" sound. Ordinary numbers can never push them off screen.
  - Ordinary hits get a white number from 12 damage up (double size from 40).
  - Damage to heroes shows in red.
- **Other effects:**
  - vector FX (`FxLayer`) for slashes, rings, telegraphs and zones
  - white hit flash in the shader
  - frozen tint
  - pixel-snapped screen shake
- **Audio:** `tools/gen_audio.gd` renders 58 SFX and 3 music loops (menu, dungeon, boss) with a small synth and sequencer into `assets/audio`.
- **`Audio` autoload:**
  - Plays SFX through a 24-voice pool on an `SFX` bus. Six voices are reserved for cues players must not miss (down, revive, ult, level-up, heartbeat, help, boss wind-up and death, stings...), so a flood of hits can't cut them off.
  - Each sound has a minimum repeat interval (e.g. kills every 50 ms), so a horde never drowns everything out.
  - Loops music on a `Music` bus and crossfades between tracks (0.6 s). The boss track starts when the throne room's fight does; victory and defeat have their own stings.
  - Volumes are set in the pause menu and saved to `user://settings.cfg`.
- **Sound hooks:**
  - Every ability plays a sound by type; ultimates add a swell.
  - World events cover hits, kills, explosions, pickups, hurt/down/revive and level-ups.
  - The level director plays door, clear and portal sounds; the boss plays roar, slam and fireball.
  - UI sounds on moves and confirms.
- **Fullscreen:** F11 / Alt+Enter toggles it anywhere; the pause menu also has a fullscreen switch.

## Verification

- `./tools/dev.sh test` runs the headless test suite. It compiles and loads every script and scene, then runs `tests/test_*.gd`. Any engine error fails the run.
- `./tools/dev.sh stress [--fullscreen] [--max-fps=120] [--seconds=60] [--log-slow]` runs the horde stress test. It prints frame, sim and draw timings plus entity counts, and exits non-zero when it misses the targets. Uncapped runs check avg ≤ 6 ms and p99 ≤ 8.3 ms. Capped runs check that p99 stays within 125% of the frame budget.
- Movie Maker captures (`--write-movie shots/frame.png`) are used to check rendering.
- The F3 overlay shows FPS, frame times, per-system costs and entity counts in any build.
