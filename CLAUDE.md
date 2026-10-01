# CLAUDE.md

Context for agents working in this repo. The game itself is described in
[README.md](README.md) (how to play) and [docs/DESIGN.md](docs/DESIGN.md)
(every rule and number, architecture, performance history). Read the DESIGN.md
section for whatever you touch before changing it.

Horde Crawler: 1-4 player local co-op top-down horde crawler, **Godot 4.7
(GDScript, GL Compatibility)**, 640x360 pixel art, up to 300 enemies on screen.
Two modes: the 8-level dungeon run and Endless Waves.

## Running Godot in a cloud/Linux container

Godot isn't installed. `api.github.com` is blocked by the proxy, but GitHub
release downloads work:

```bash
GD=/tmp/godot && mkdir -p $GD && cd $GD
curl -sSL -o godot.zip https://github.com/godotengine/godot/releases/download/4.7.2-stable/Godot_v4.7.2-stable_linux.x86_64.zip
unzip -q godot.zip && rm godot.zip && chmod +x Godot_v4.7.2-stable_linux.x86_64
export GODOT=$GD/Godot_v4.7.2-stable_linux.x86_64   # tools/dev.sh reads $GODOT
```

- `./tools/dev.sh test` imports, then runs the whole suite headless: ~4 min,
  ~320 tests. It ends with `N passed, M failed`, exit code 0 only if all pass.
  The leaked-ObjectDB/resources warnings at exit are normal.
- One file or one test: `$GODOT --headless --path . -s res://tests/run_tests.gd -- --filter=test_elements`
  (`--filter` matches `file:test_name`, e.g. `--filter=test_ult_charge:test_the_meter`).
  With a filter the "everything loads" check is skipped, so run the full suite
  before committing.
- The `.godot/` import cache isn't in git: after adding a `class_name` script or
  art, run `$GODOT --headless --path . --import` once (`dev.sh test` does it).
- Stress test (perf): `$GODOT --headless --path . res://tools/stress_test.tscn -- --seconds=20 --warmup=4 [--ult-spam] [--level=level_3]`.
  Headless, only the `sim` line means anything. The container is noisy (±0.3 ms
  run to run): compare against a clean `git worktree` of the base commit,
  alternate the runs, and use best-of-N for micro benchmarks.
- Screenshots: Xvfb and Mesa are installed. `xvfb-run -a -s "-screen 0 1920x1080x24" $GODOT --path . --rendering-driver opengl3 -s /abs/path/shot.gd`,
  where the SceneTree script builds a scene on its first `_process` and saves
  `root.get_viewport().get_texture().get_image()` a few frames later.
  **Don't name `class_name` classes (Profile, PlayerInput, ...) in such a script**:
  it compiles them before the autoloads exist and InputRouter breaks. `load()` them
  at runtime instead. Character select takes `--debug-join=N` (bot players).

## Where things live

- `src/autoload/`: `game_state.gd` (run state, the **DIFFICULTY** table and
  names/colours), `input_router.gd`, `events.gd`, `audio.gd`, `settings.gd`.
- `src/core/`: pure logic, no autoloads: `profile.gd` (records, difficulty
  unlocks), `level_grid.gd` (walkability, DDA rays), `flow_field.gd`,
  `stats.gd`, `xp_curve.gd`.
- `src/sim/horde_sim.gd`: the data-oriented horde (packed arrays, one hot loop
  `_move()`): movement, statuses, death effects, **AoE avoidance**
  (`add_danger`, the dodge block in `_move`, `_escape_way`, `_round_open`,
  `_walled`). `projectile_sim.gd`, `pickup_sim.gd`, `fx_sim.gd`.
- `src/heroes/hero.gd`: hero, abilities' slots, **ultimate meter**
  (`ULT_MAX_PER_SECOND`, `ult_bank`, `ult_working()`, `add_ult_charge`).
  `ability.gd` and `abilities/` (+ `abilities/forms/` = legendaries).
- `src/world/world.gd`: ticks everything; `_apply_ult_charge()`,
  `ultimate_at_work()`, `_collect_dangers()`, `hit_enemy()`, zones/minions.
  `elements.gd`: fire/ice/poison/lightning, Inferno/Shatter/Plague.
- `src/levels/`: `level_director.gd` (run levels, arenas, the restless clock,
  applies difficulty), `wave_director.gd` (Endless Waves), `level_data.gd`.
- `src/ui/`: `character_select.gd` (difficulty picker, unlock hint, stars),
  `end_screen.gd`, `hud.gd`, `level_up_screen.gd`.
- Data is generated, don't hand-edit it: hero tuning `tools/gen_hero_data.py`
  → `src/heroes/data/*.tres`; upgrades `tools/gen_upgrades.py` →
  `src/upgrades/data/upgrade_library.tres`; layouts `tools/gen_levels.py`.
  Edit the table, run `python3 tools/<script>.py`, commit both.

## Conventions

- Typed GDScript, tabs. Mixed tabs/spaces is a parse error. `untyped_declaration` warns.
- Comments are `##` doc comments in plain game language that explain the rule
  and why ("Blasts don't chain: what one kills doesn't explode..."). Match that
  voice and density. Constants carry the tunable numbers, with a comment.
- Pure logic (`src/core`, sims) doesn't touch autoloads, so it unit-tests headless.
- Tests: `tests/test_*.gd` extend `res://tests/test_case.gd`, and every `test_*`
  method runs on a fresh instance. Names state behaviour
  (`test_inferno_blasts_dont_chain`). Any engine error during a test fails it.
  Steering tests drive a bare `HordeSim` on a hand-made `LevelGrid`
  (`test_avoidance.gd`); gameplay tests build `world.tscn` with bot devices.
- Gameplay changes update **docs/DESIGN.md** (rule + numbers, and a
  "Performance results" entry for anything in a hot loop) and **README.md**
  (player-facing).
- Commits: a short title in the house style ("Keep moving: the horde grows
  restless when a team lingers"), then a body listing what changed and why,
  with the numbers.

## Gotchas

- Crits are random (5% base). Tests that check exact damage set
  `hero.crit_chance = 0.0` after `_refresh_stats()`/upgrades.
- Only *burning* enemies explode (Inferno), and burns last 4 s. A test that
  waits too long sees the burn run out.
- The ultimate meter fills through `ult_bank` at most `ULT_MAX_PER_SECOND` (and
  not while `ult_working()`). Tests that add charge check
  `ult_charge + ult_bank`, or tick frames.
- Adding a difficulty: `GameState.Difficulty`/`DIFFICULTY`/`DIFFICULTY_NAMES`/`DIFFICULTY_COLORS`,
  `Profile.DIFFICULTIES` (saved arrays get padded on load) and
  `character_select.gd` `STAR_COLORS`. `test_replay.gd` checks they agree.
- HordeSim hot loop: use locals and packed arrays. Danger masks are walked by
  set bit (`bit := bits & -bits`, index `roundi(log(float(bit)) * INV_LN2)`),
  not bit by bit. At most 32 dangers (one bit each in a 64-bit int).
- `test_world_integration:test_four_heroes_fight_the_horde` is random (bots,
  spawns and crits aren't all seeded): its 12 s fight kills anywhere from about
  20 to 60 enemies and it needs more than 20, so it fails once in a while. Rerun
  it before chasing it.
- Measuring how fast something fills or happens in real fights works well as
  a throwaway test file (bots via `BotDriver`, `world.wave_mode` or a run
  level). Delete it before committing.
