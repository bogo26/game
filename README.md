# Horde Crawler (working title)

1–4 player **local co-op** top-down pixel-art horde crawler for **macOS and Windows**. Pick a hero, fight through hordes of up to 300 enemies, and upgrade on every level-up. Play the 8-level dungeon run, or hold out in **Endless Waves** for as long as you can.

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
- Godot keeps the list of script classes and the imported art in `.godot/`, which isn't in git, and only the editor (or `--import`) refreshes it. After a pull that adds scripts or art, `./tools/dev.sh run` and `stress` re-import once before starting. If you launch the game another way and get `Could not find type ...` errors or a black screen, run `./tools/dev.sh import` (or open the project in the editor) once.
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
3. Fight down through the dungeon: **1 → 2 → 3 → mini boss → 4 → 5 → 6 → final boss**. In each level, clear the lockdown arena rooms, then reach the exit portal. Hold **Tab** / **Back** for the map.

   Swarmers, brutes, spitters and exploders make up most of the horde, and every level has an enemy of its own:

   | Level | | | Its own enemy |
   |---|---|---|---|
   | 1 | Crypt Entrance | spike traps, barrels, urns | **Bats**: fast, frail, weaving flocks of three |
   | 2 | Flooded Halls | water, nests | **Drowned**: slow on land, fast in water |
   | 3 | Bone Pits | chasms and bridges | **Bone archers**: show their aim as a line, then shoot along it |
   | Mini boss | *one of three bosses (below)* | beat it to open the way on, and pick a **legendary** (below) | its servants |
   | 4 | Fungal Caverns | toxic pools, spore nests | **Sporecaps**: burst into spore clouds when killed |
   | 5 | Frozen Vaults | crevasses, slush, spike galleries | **Frost boars**: charge down a marked lane, into walls or over crevasse edges |
   | 6 | Molten Forge | lava channels, powder kegs, four arenas | **Salamanders**: lob molten slag where you stand |
   | Final boss | *one of three bosses (below)* | beat it to win the run | its servants |

   Every run meets one of three mini bosses and one of three final bosses, each in a level of its own:

   | | Level | Boss | Its own enemy |
   |---|---|---|---|
   | Mini boss | The Ossuary | the **Bone Colossus**: club sweeps, grave spikes, and once enraged, leaps and risen dead | **Revenants**: fall apart into bone piles that get back up unless smashed |
   | Mini boss | Toadstool Hollow | the **Toadstool Tyrant**, a giant toadstool: bounces onto you hop after hop, puffs rings of spore clouds, and once enraged, lobs spore bombs | **Sporelings**: little mushrooms that hop |
   | Mini boss | The Sunken Cistern | the **Mire Serpent**: dives out of reach, hunts you as a fin and bursts up under you; spits and lunges when it surfaces | **Eels**: slither, and swim fast through the channels |
   | Final boss | Demon's Throne | the **Demon Lord**: fireball fans, slams, fire rings and charges | **Imps**, its servants: blink to your side through small portals |
   | Final boss | The Mycelium Deep | the **Spore Mother**, a towering fungus: shielded by spore pods until you burst them; roots, spore rain, spore spirals and fairy rings | **Puffballs**: burst into spore clouds |
   | Final boss | The Frozen Court | the **Frost Queen**: ice lances, frost novas to dash through, icicle hail, a sweeping beam and blizzards; her frost slows you | **Frost wraiths**: flying ghosts that shoot ice |

   The horde is wary of your AoEs. After a moment to notice one, enemies get out from under a Meteor's mark or a mortar shell, go round Arrow Rain, caltrops, fire trails and toxic clouds, and wait outside a Whirlwind or Blade Vortex, so drop them where the pack is thickest or where it's headed.

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

**Legendaries:** beating the mini boss lets every player pick one of their hero's three legendaries. Each turns one of the hero's abilities into something new for the rest of the run, with a new name, look and behaviour:

| Hero | Attack | Special | Movement | Ultimate |
|---|---|---|---|---|
| Knight | **Crescent Wave**: every 3rd swing sends a crescent of light through a whole line | **Challenge**: yank nearby enemies to your feet, stunned; take less damage per enemy caught | **Juggernaut**: carry everything in your path, then slam it down | |
| Ranger | **Ricochet**: arrows glance from enemy to enemy | **Cluster Arrow**: a heavy arrow bursts into a ring of 12 | **Decoy**: a scarecrow the horde goes after, then caltrops | |
| Mage | | **Frozen Orb**: an ice orb sprays shards, then bursts into a Frost Nova | **Chronoshift**: snap back to where you blinked from, undoing damage | **Singularity**: a black hole drags enemies in, then collapses |
| Cleric | **Prism Orbs**: orbs split in three at each wall bounce | **Bastion**: a dome that stops enemy shots and pushes enemies out | | **Judgement**: pillars of light strike the toughest enemies, bosses first |
| Berserker | **Throwing Axe**: every 3rd swing throws the axe out and back | **Bloodbath**: kills burst in blood, chaining through the pack | **Rebound**: three slams in a row, each bigger | |
| Rogue | | **Blade Vortex**: knives whirl around you, then fly out | **Shadowstrike**: appear behind an enemy for a sure crit | **Shadow Hunt**: clones hunt on their own |
| Engineer | **Flamethrower**: a gout of fire that sets enemies burning | **Mortar**: mortars shell the biggest pack | | **Tesla Grid**: lightning links between the tower, you and your turrets |
| Necromancer | **Haunt**: bolt kills rise as seeking wisps | **Bone Golem**: one big golem made of corpses draws the horde | | **Lich Form**: become a Lich; your kills rise as skeletons |

**Test Room** on the main menu is a drop-in sandbox with an endless horde and one of everything. Add `-- --upgrades=fire_3,ice_2` to `./tools/dev.sh run` to start with those upgrades and the tiers before them; legendaries work too (`--upgrades=knight_crescent_wave,mage_singularity`: each hero only takes its own).

**Replaying:** pick Casual, Normal or Hard in character select (LB / RB or Q / E; Hard unlocks after a Normal win, or after reaching wave 20 of Endless Waves on Normal). Every run picks one of two layouts for each regular level and may mirror it, and from the second level on some enemies arrive as elites (Swift, Volatile, Splitting). The end screen shows everyone's numbers and awards, and records best times.

**Endless Waves** (main menu): no dungeon, just waves that keep getting harder, until the team falls. Join and pick heroes and a difficulty as for a run.
- The team holds **The Pit**, one sealed arena (pillars, pools, spike beds, powder kegs), in a different tile theme each game.
- Each wave comes in through portals. Once it's beaten there's a short break with a heart, the XP pulled in and any upgrade picks earned during the wave, then the next wave comes. If three or fewer enemies hold out for 20 s, the wave counts as cleared anyway, and they stay in the fight. The arrow points at the last five.
- Every wave is harder than the last: more enemies, more HP, a faster pace, tougher kinds (brutes from wave 2, spitters from 3, exploders from 4), elites from wave 4, and each wave features one of the levels' own enemies (two from wave 12, three from wave 24). After wave 10 enemies hit harder, and after wave 20 their HP climbs faster and faster.
- **Every 5th wave is a boss:** a random mini boss on waves 5, 15, 25…, a random final boss on waves 10, 20, 30…. Beating one opens a legendary round (each player transforms another of their hero's abilities, until all three are taken), refills the team's lives and gives everyone a bonus upgrade.
- The end screen shows the wave you reached, and your best wave is kept per difficulty.

Debug flags (after `--`): `--level=3` (the run's 1-based position: `--level=4` is the mini boss, `--level=8` the final boss), `--boss=grove` (which boss: `lair`, `grove` or `cistern` for the mini boss, `boss`, `mycelium` or `glacier` for the final one), `--waves` (Endless Waves) and `--wave=5` (from that wave), `--bots=4`, `--heroes=rogue,mage`, `--layout=b`, `--mirror=hv`, `--elite-chance=0.3`, `--debug-levelups=2`, `--show-map`. For example, `./tools/dev.sh run res://src/main/game.tscn -- --waves --wave=5 --bots=4` shows bots fighting a boss wave.

## Status

Milestone 16 (Endless Waves) is done: a second mode on the main menu, where the team holds one arena against waves that keep getting harder, with a boss every 5th wave (each one a legendary round) and a best wave per difficulty.

Milestone 15 (legendary upgrades) is done: beating the mini boss offers each player their hero's three legendaries, and each of the 24 turns one ability into a new form with its own look, behaviour and sounds.

Milestone 14 (more bosses) is done: every run now meets one of three mini bosses and one of three final bosses. New are the Toadstool Tyrant and the Mire Serpent (mini bosses) and the Spore Mother and the Frost Queen (final bosses), each with a level, tile theme, sounds and servant enemy of its own (sporelings, eels, puffballs, frost wraiths).

Milestone 13 (level enemies) is done: eight new enemies, one of its own for every level (bats, drowned, bone archers, revenants, sporecaps, frost boars, salamanders, imps), each with its own behaviour, art, sounds and warnings; the Bone Colossus raises revenants and the Demon Lord summons imps.

Milestone 12 (dungeon expansion) is done: the run is now 1-2-3, a mini boss (the Bone Colossus), 4-5-6 and the final boss, with three new levels (each with a second layout), four new tile themes and a shared `Boss` base for both bosses.

Milestone 11 (player-experience pass) is done: run-flow fixes, readable telegraphs and spawns, hit and low-HP feedback, arena waves, team lives, an options screen with accessibility settings, button prompts for every controller, difficulty and records, map variety and elite enemies.

Milestone 9 (exports) is prepared:
- macOS + Windows presets, an app icon and `./tools/dev.sh export`.
- Building needs the Godot export templates installed once (see above).

See [docs/DESIGN.md](docs/DESIGN.md#milestones).
