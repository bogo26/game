# Horde Crawler — Design

Working title. A 1–4 player **local co-op**, top-down **pixel-art horde crawler** for **macOS and Windows**, built with **Godot 4 (GDScript)**.

Players pick heroes, fight through hand-built levels packed with hordes of up to **300 enemies on screen**, and choose upgrades (pick 1 of 3) on every team level-up. Two modes: the 8-level dungeon **run**, and **Endless Waves**, which holds one arena against waves that keep getting harder until the team falls (see [Endless Waves](#endless-waves)).

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
- **Ultimate:** charged by the damage the other three deal (never by its own), plus a slow trickle; the meter fills no faster than once in 16 s (about 9 s with every Recharge), and not at all while the ultimate is still at work

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

Four kinds make up most of the horde throughout the run. Every level adds an enemy of its own that no other level has (`tests/test_enemies.gd` checks it, the other bosses' levels included), and the bosses bring their own servants.

| Enemy | Where | Role |
|---|---|---|
| Swarmer | throughout | Fast and weak; most of the horde |
| Brute | throughout | Slow, tanky, heavy hits |
| Spitter | throughout | Keeps distance and fires projectiles |
| Exploder | throughout | Rushes in, telegraphs, explodes |
| Bat | Crypt Entrance | Fast and frail (5 HP), in flocks of three that weave from side to side. Flies: water doesn't slow it and it never goes over a chasm's edge |
| Drowned | Flooded Halls | Shambles on land, but swims through water at twice its walking speed (drawn swimming there), so the pools belong to it |
| Bone archer | Bone Pits | A sniper: aims for 0.8 s with a pink line from 185 px away (the aim is locked), then looses a fast shard along the line. Step out of it |
| Revenant | The Ossuary; the Bone Colossus raises them | An armoured skeleton that falls apart into a bone pile when killed. Unless the pile is smashed (a kill of its own, with XP), it rattles and gets back up after 4 s |
| Sporecap | Fungal Caverns | A slow mushroom that bursts into a spore cloud when killed (30 px, 4 s) that hurts heroes inside. Kill it from range, or step out |
| Frost boar | Frozen Vaults | A charger: lines up for 0.7 s under a band exactly as wide as what it hits, then charges 170 px in a straight line and hits twice as hard. A charge into a wall dazes it for 1.3 s; one over a crevasse edge sends it down |
| Salamander | Molten Forge | Lobs molten slag where a hero stands: the landing spot is marked for the 0.9 s flight, then it bursts (22 px) and the slag burns for 1.5 s |
| Imp | Demon's Throne; the Demon Lord summons them | Flies, and every 3.5 s blinks to the side of a hero 56-220 px away: a portal shows where for 0.45 s while it fades out, then it steps out next to them |
| Sporeling | Toadstool Hollow; the Toadstool Tyrant sprouts them | A little mushroom in packs of three that gets about in hops (1.6 a second): it sits still, then leaps nearly twice its walking speed |
| Eel | The Sunken Cistern; the Mire Serpent's brood | Slithers from side to side in pairs, and swims 2.2x as fast as it crawls: the channels belong to it |
| Puffball | The Mycelium Deep; the Spore Mother calls them | An exploder whose burst leaves a spore cloud (26 px, 3 s) - and so does killing it first |
| Frost wraith | The Frozen Court; the Frost Queen calls them | A flying spitter: floats over water and crevasses and shoots shards of ice |
| Bone Colossus (mini boss) | The Ossuary | Club sweeps, grave spikes, leaps; raises swarmers and revenants; node-based |
| Toadstool Tyrant (mini boss) | Toadstool Hollow | Bounces hop after hop onto the nearest hero, puffs rings of spore clouds; enraged, lobs spore bombs and sprouts sporelings |
| Mire Serpent (mini boss) | The Sunken Cistern | Dives out of reach and hunts a hero as a fin, bursts up under them; spits fans of water and lunges; enraged, bursts twice and brings eels |
| Demon Lord (final boss) | Demon's Throne | Phase-based attack patterns; summons swarmers and imps; node-based |
| Spore Mother (final boss) | The Mycelium Deep | Rooted in place and shielded by spore pods until they burst; roots erupt along bands, spore rain and spirals; fairy rings; calls puffballs |
| Frost Queen (final boss) | The Frozen Court | Keeps her distance: ice lances, frost novas to dash through, icicle hail, a sweeping glacial beam, blizzards; her frost chills; calls frost wraiths |

**Elites** (`Elites`, from the second level on; always in the test room): about 1 in 40 spawns of the walking kinds above (every one but the revenant, which already comes back once) arrives as an elite, at most 4 alive at once (×0.5 on Casual, ×2 on Hard).
- An elite is drawn 1.5× bigger with a pulsing outline in its trait's colour (the instance shader draws it from a code in the tint channel), with its hurtbox and footprint scaled to match, ×6 HP, ×1.25 damage and half the knockback.
- Traits: **Swift** (cyan, +60% speed), **Volatile** (orange: blows up 0.6 s after it dies, telegraphed, 25 damage in 36 px), **Splitting** (green: breaks into 3 ordinary enemies of its kind).
- Each drops a big XP gem (10) and has a 30% chance of a heart.
- Elites are extra enemy types made at setup from the base ones (`Elites.variants()`), so the horde needs nothing new per enemy.

## Difficulty and records

Chosen in character select with LB / RB (Q / E). Casual and Normal are open from the start; every harder difficulty unlocks with a win on the one before it, or by reaching wave 20 of Endless Waves on it (`Profile.unlocked()`): Hard after Normal, Nightmare after Hard, Torment after Nightmare. Locked ones are skipped, and a dim line under the picker says how to open the next. Both modes use the same difficulties.

| | Enemy HP | Enemy damage | Spawn rate | Team lives per level | Elites | Enemy speed |
|---|---|---|---|---|---|---|
| Casual | ×0.75 | ×0.7 | ×0.8 | 2 | ×0.5 | ×1 |
| Normal | ×1 | ×1 | ×1 | 1 | ×1 | ×1 |
| Hard | ×1.3 | ×1.3 | ×1.2 | 0 | ×2 | ×1 |
| Nightmare | ×1.7 | ×1.6 | ×1.35 | 0 | ×3 | ×1.1 |
| Torment | ×2.2 | ×2 | ×1.5 | 0 | ×4 | ×1.2 |

- Enemy damage is a real multiplier (`HordeSim.damage_mult`): contact, spit, exploder and elite blasts, spikes and every boss attack.
- Enemy speed (`HordeSim.speed_mult`) scales walking only (charges and hops keep their own); a restless horde speeds up on top of it, to 1.3× the difficulty's own at most. Elites stay capped at 4 alive whatever the chance.
- **Profile** (`Profile`, `user://profile.cfg`): runs played, wins and best time per difficulty, the hardest difficulty won with each hero, shown as a bronze / silver / gold / amethyst / ruby star by the hero's name in character select, and the best wave reached in Endless Waves per difficulty (`best_wave`, in its own `[waves]` section). The end screen announces "NEW BEST TIME!", "NEW BEST WAVE!" and "HARD UNLOCKED!" (or "NIGHTMARE UNLOCKED!", "TORMENT UNLOCKED!").
  - Best times only compare runs of the same length: the profile stores a run version (`Profile.RUN_VERSION`, 2 = the 8-level run), and loading an older profile drops its best times but keeps wins, the difficulties unlocked and the stars. Profiles saved before Nightmare and Torment existed (three numbers per difficulty list) are padded.

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
- **Picks wait for arena fights to end:** while an arena fight is on, level-up rounds queue (the HUD shows "+2" next to the level) and open back to back 1 s after the arena is cleared. In corridors, from chests and during boss fights they open at once.
- Upgrades that only help with teammates (Guardian Angel) are never offered to a solo player (`UpgradeData.team_only`).
- Upgrades are either stat modifiers (flat or %) or ability modifiers. They're written as short effect lines in `UpgradeData.effects`:
  - `stat damage pct 0.1`
  - `stat max_hp flat 20`
  - `ability attack pierce 1`
  - `ability all area_pct 0.12`
- `UpgradePool.validate()` and the tests check every line against the known stats and mod keys.
- The library (`src/upgrades/data/upgrade_library.tres`) is generated by `tools/gen_upgrades.py`. It has 86 upgrades: 17 generic (including 1–2 epics), 4–5 per hero, 12 elemental ones and 24 legendaries (both below).
- **Offers:** 3 distinct cards per player, weighted by rarity (common 10, rare 4, epic 1.2). Hero-specific cards weigh ×1.6, and maxed cards never appear. A card with `requires` is only offered once that upgrade was taken. Legendaries are never offered in these rounds.

### Elemental attacks

Four chains of three upgrades give a hero's **attack** an element. Each tier needs the one before it, and the third is the big one (epic). All numbers scale with the damage of the hit that applied them.

| Element | Tier I | Tier II | Tier III |
|---|---|---|---|
| **Fire** | *Ember Strikes*: burn for 50% of the hit per second, 3 s | *Wildfire*: 80% per second, 4 s; burning enemies set enemies touching them alight | *Inferno*: burning enemies explode when they die (3× the burn per second, 38 px) and set everything they hit ablaze, but blasts don't chain: what a blast kills doesn't explode, and the fire it lights is ordinary fire |
| **Ice** | *Frostbite*: chilled, 40% slower for 2.5 s | *Permafrost*: every 3rd chill freezes the enemy solid for 1.5 s | *Shatter*: frozen enemies take double damage from attacks, and die in a nova that chills everything near them twice (freezing most of them) |
| **Poison** | *Venom*: stacks up to 4; each stack deals 25% of the hit per second for 4 s and slows 6% | *Virulence*: up to 8 stacks, 6 s | *Plague*: poisoned enemies leave a toxic cloud (2.5 s) that adds a stack every 0.5 s to everything inside (at most 10 clouds) |
| **Lightning** | *Static Charge*: every hit staggers its target (small shove and stun) and zaps the nearest enemy within 56 px for 50% | *Arc Lightning*: zaps chain through 3 enemies for 60% and stun them | *Thunderstrike*: every 5th hit calls down a bolt (3× damage, 0.8 s stun) that chains through 6 enemies |

- Elements ride on the attack only: projectile attacks log the enemies they hit, and melee swings (and the Rogue's shadow clones) pass their hits to `Elements.on_attack_hit()`. Specials and ultimates don't carry them.
- Heroes can mix elements. Tiers are ability mods on the attack (`ability attack fire 1` per tier), so they need no special handling in the upgrade code.
- **Statuses** live in `HordeSim` arrays (burn, poison stacks, chill, frost, frozen). Damage over time ticks in the horde's movement loop and is credited to the last hero to hit, for kills and ultimate charge (but statuses an ultimate applied don't charge it: see Ultimate charge). Enemies are tinted by status: frozen, burning, poisoned or chilled.
- **Who is affected.** Barrels and urns take no statuses. Bosses burn and get poisoned, but never freeze or slow.
- **Death effects** (Inferno, Shatter, Plague) are logged when an enemy dies, and at most 6 play per frame, so chains ripple outward. Fire spreading is checked for a share of the horde every frame.
  - **Inferno blasts never set off more blasts.** While one lands, `HordeSim.inferno_blast` is on and the enemies it kills log no Inferno of their own; the fire it lights carries Wildfire but not Inferno. An enemy the hero (or Wildfire spreading from the hero's fire) set alight still explodes when something else kills it, so each blast stands for an enemy the hero's own fire reached, and one kill no longer sets off the whole horde.
- **Cost.** In the worst case (all four elements at tier III on four heroes firing ~1000 elemental shots a second), the element code costs ~0.04 ms per frame. The stress test with `--elements` still meets the targets: 4.7 ms average, 7.9 ms p99.
- **Runs:** each player's picks are stored in `GameState` and re-applied when the next level builds the heroes again.

### Legendary upgrades (the mini boss's reward)

Beating the mini boss opens a **LEGENDARY** round ("LEGENDARY!  TRANSFORM AN ABILITY", `GameState.LEGENDARY_ROUND`, queued first by `World._on_mini_boss_defeated()` and opening 1.6 s later, after the death's slow motion). Each player is offered their own hero's three legendaries (`UpgradePool.legendary_offers()`), and **each turns a different ability into a new form**: a new name, look and behaviour for the rest of the run. So the pick is which ability to transform for levels 4–6 and the final boss. The final boss gives none; the chest by the mini boss's exit still gives its ordinary treasure round. In Endless Waves the bosses of waves 10, 20 and 30 give one each (see [Endless Waves](#endless-waves)).

| Hero | Legendary | Transforms | What changes |
|---|---|---|---|
| Knight | Crescent Wave | Sword Slash | Every 3rd swing is a gold heavy slash that also sends a crescent of light through a whole line (the heavy swing's damage, with the Knight's elements) |
| Knight | Challenge | Ground Slam | A gold ring closes in: every enemy within 80 px (in sight) is yanked to the Knight's feet and stunned 1.2 s; −4% damage taken per enemy caught (max −40%) for 5 s |
| Knight | Juggernaut | Shield Charge | Enemies in the path ride along on the shield (up to 10), then a crash: 14 + 3 per enemy carried, ×1.5 and longer stun if a wall stopped the charge; carried enemies go over chasm edges |
| Ranger | Ricochet | Piercing Arrow | After each hit an arrow turns toward the nearest enemy ahead within 80 px (a green streak shows the turn), 3 times; Piercing Shots adds one |
| Ranger | Cluster Arrow | Fan Volley | One heavy arrow (20) bursts where it hits an enemy or a wall, or at the end of its flight, into a ring of 12 piercing arrows (Wide Volley adds 2) |
| Ranger | Decoy | Backflip | A straw scarecrow (60 HP, 3 s) stays where the Ranger stood; the horde treats it as a hero (walks to it, spitters shoot at it, exploders blow up on it), then it bursts into a 34 px patch of caltrops |
| Mage | Frozen Orb | Frost Nova | An ice orb drifts 125 px toward the aim over 1.4 s, spraying slowing shards in a turning spiral, then bursts into the full Frost Nova where it stops |
| Mage | Chronoshift | Blink | The blink leaves a ghostly echo with a clock ring; 2.5 s later the Mage snaps back to it, undoing half the damage taken meanwhile (Blink Nova blasts both ends) |
| Mage | Singularity | Meteor | A black hole at the aim point for 3 s drags enemies within 110 px (not bosses) into its core, grinding them, then collapses in the Meteor's blast |
| Cleric | Prism Orbs | Holy Orb | Rainbow-rimmed orbs split in three at a wall bounce (±25°, 70% damage each), twice: up to 9 |
| Cleric | Bastion | Sanctuary | For 5 s the zone is a dome: enemy shots (boss fireballs and ice lances too) fizzle at its edge and enemies are pushed out; allies inside still heal |
| Cleric | Judgement | Divine Light | Still revives everyone and heals the team 40%, then 12 pillars of light strike the toughest enemies on screen one after another (90 each, bosses first) instead of the flat smite |
| Berserker | Throwing Axe | Axe Cleave | The combo finisher hurls the axe out 110 px and back to the hand, hitting both ways (with elements); while it flies the finisher is an ordinary heavy cleave |
| Berserker | Bloodbath | Blood Frenzy | While the frenzy lasts the Berserker glows red and every kill bursts in blood (12 in 28 px, heals 2); burst kills burst too, so it chains |
| Berserker | Rebound | Leap Slam | After each landing the Berserker leaps onto the nearest enemy not already underfoot (110 px): 3 slams, each +20% area and +25% damage |
| Rogue | Blade Vortex | Knife Ring | The knives orbit the Rogue for 3 s, cutting each enemy they touch at most every 0.4 s (60% damage), then fly outward as the old ring (Fan of Knives adds 6) |
| Rogue | Shadowstrike | Shadow Step | The Rogue appears behind the enemy nearest the aim (110 px) and stabs it for a guaranteed crit, marking everything within 30 px; with nobody in reach it's a Shadow Step |
| Rogue | Shadow Hunt | Shadow Clones | For 6 s the clones hunt on their own instead of copying the Rogue: each blinks to an enemy near the Rogue every 0.35 s, stabs it (elements too) and marks it |
| Engineer | Flamethrower | Rivet Gun | A jittery gout of flame about 100 px long (two jets of 5 every 0.14 s; Amplify lengthens it) that passes through everything and sets it burning (50% of the hit per second, 3 s); the fire spreads to whatever touches a burning enemy, as Wildfire's does |
| Engineer | Mortar | Deploy Turret | Mortars (max 2) lob a shell every 1.4 s at the densest pack 40–220 px away, onto a dashed ring in the owner's colour: 14 in 26 px with knockback |
| Engineer | Tesla Grid | Tesla Tower | For 8 s the tower links itself to the Engineer and every turret or mortar within 200 px with lightning; enemies on a link take 10 and a short stun every 0.2 s (the tower no longer chains) |
| Necromancer | Haunt | Soul Bolt | Enemies killed by Soul Bolts rise as wisps that home in on another enemy (140 px) and burst for 70% damage; wisp kills release wisps too (10 at most) |
| Necromancer | Bone Golem | Raise Dead | Up to 6 fresh corpses fuse into one golem (80 HP + 20 a corpse, 1.4–2× size) that the horde goes after and that slams (14 in 24 px, short stun); casting again feeds and heals it |
| Necromancer | Lich Form | Army of the Dead | For 10 s the Necromancer is a Lich: bigger, floating and ghostly green, 25% less damage taken, Soul Bolts in threes, and every kill (by the Necromancer or a minion) rises as a skeleton, up to the army's cap |

- **Forms are ability templates** (`src/heroes/data/forms/<upgrade id>.tres`, written by `tools/gen_hero_data.py` from its `FORMS` table: the hero's own ability props plus overrides). `Hero._take_form()` cancels and unbinds the old ability, duplicates the template and gives it the old one's `mods` and cooldown. Every form extends the class of the ability it replaces, so the upgrades the hero took (and takes later) keep their meaning: Wide Slash still widens the Crescent Wave, Supercoil lengthens the Tesla Grid, Sturdy Bones toughens the golem and the Lich's skeletons, Endless Legion raises the Lich's cap. Hero cards that name the old ability show its new name (`LevelUpScreen.card_text()`).
- 4 forms are data only (Ricochet, Prism Orbs, Flamethrower, Mortar); 20 have a small script in `src/heroes/abilities/forms/`.
- **The Flamethrower is tuned against the Rivet Gun** it replaces (2026-10-01), measured in Endless Waves with a solo Engineer attacking only, both with the same upgrades, standing still, closing in or keeping away. The old gout (60 px, two jets of 3 every 0.12 s, a burn that didn't spread) beat the rivets with no upgrades, but by wave 16 it did only 40% of their damage unless the Engineer stood inside the horde, so taking it felt like a downgrade. Now: about 2× the rivets' damage on wave 4 and +35-65% on wave 12. On wave 24 it does +2-35% against a full elemental build and about 4× without one: the elements scale with each hit, which is why a jet hits for 5 (not 4 every 0.12 s), so its procs keep up with a rivet's 6. Kiting it still keeps up. Its burn is ProjectileSim's `BURN` effect (now with the Wildfire flag), and `ProjectileAbility.area_reach` makes Amplify lengthen its shots' lifetime.
- **Cards:** rarity Legendary (orange-gold), one stack, `form_slot` the slot they transform; the card's last line shows the player's button and the slot. With four players a card holds about 88 characters (`gen_upgrades.py` checks).
- **Ultimates** still never charge themselves: the forms' hits happen in `_activate` / `_tick_active` (or through minions and zones made there), so they're flagged as the ultimate's; a Singularity collapsing because its Mage went down sets the flag itself.
- **Debug:** `--upgrades=knight_crescent_wave` gives a legendary like any other card; hero cards (legendaries included) only go to their own hero, so one list can hold every hero's.
- **Stats (`src/core/stats.gd`):** `value = (base + flat) × (1 + pct)`. The stat list is max HP, armor, move speed, damage, attack speed, crit chance, crit damage, pickup range, regen, ultimate charge rate, life on kill and revive speed.
- **Pick screen controls:** each player picks in their own area: one centred panel, two halves, or four quadrants. Gamepads use left/right + A. Keyboard players use A/D or arrows + Enter, or the mouse. Bots pick after 0.6 s.
- **Accidental-pick guard:** human input is ignored for the first 0.35 s after the cards appear, so a player mashing A (dash) or left-click (attack) can't pick one by accident.
- **Rounds:** `GameState.pending_rounds` queues them oldest first, each labelled with the team level it was earned at, or as a treasure (chest, shown first) or bonus (debug) round, so titles are always right.
  - Once everyone has picked, the result stays up for 0.3 s so the last player sees "PICKED!" too.
  - With 3–4 players each panel sits in its player's HUD corner; with 2 the lower slot is on the left.
  - Rounds wait until the level banner has gone. Rounds earned after the exit is reached, or once the run is won or lost, carry over to the next level instead of opening then.
- Upgrades last for the whole run and reset on game over.
- XP needed per level: `24·L^1.35 + 16·L`, scaled by `1 + 0.35 × (players − 1)` (see `src/core/xp_curve.gd`). Every level-up stops the game for everyone, so the curve paces them at about two per regular level: a dozen in a run, a pick screen every minute or so. Staying behind to farm the corridors doesn't pay for long: see Keep moving (the restless horde).

## Levels and run flow

- **Map variety:** levels 1–6 each have a second layout (`level_1b` ...: same size, quotas and theme, but different room shapes, route, and chest and shrine spots). Every run picks one per level from `GameState.run_seed` and mirrors it left-right and/or upside down (boss levels only left-right): `RunConfig.layout_for()`, `LevelData.mirrored()`. That's 8 versions of each normal level. `--layout=a|b` and `--mirror=none|h|v|hv` pin them for debugging. The level tests check every layout in every mirror, and bots play every second layout mirrored.
- **Boss pools:** each run meets one of three mini bosses and one of three final bosses, picked from the seed too (`RunConfig.boss_pool`, `RunConfig.choices()`). Every boss has a level of its own (layout, theme, own enemy), as tough as the boss level it stands in for; `--boss=<level file>` (e.g. `--boss=grove`) pins one.
- **Authoring:**
  - Levels are ASCII layouts in `LevelData` resources; the legend is in `level_data.gd`.
  - `tools/gen_levels.py` builds the run's layouts from shaped rooms, halls, terrain and props, and writes `src/levels/data/level_*.tres`, the mini bosses' `lair.tres`, `grove.tres` and `cistern.tres` and the final bosses' `boss.tres`, `mycelium.tres` and `glacier.tres`, with each level's difficulty settings, theme and boss (see Map features).
  - The sandbox `test_room.tres` is hand-written.
- **Rendering:** `Level` turns a layout into a `TileMapLayer` for rendering and a `LevelGrid` for collision and pathfinding.
- **Run order:** 1 → 2 → 3 → mini boss → 4 → 5 → 6 → final boss. `src/levels/run_config.tres` lists:

  | # | Banner | Level | Theme | Arenas | Enemy HP | Its own enemy |
  |---|---|---|---|---|---|---|
  | 1 | LEVEL 1 | Crypt Entrance | crypt | 2 | ×1.0 | bats |
  | 2 | LEVEL 2 | Flooded Halls | flooded | 2 | ×1.35 | drowned |
  | 3 | LEVEL 3 | Bone Pits | bones | 3 | ×1.8 | bone archers |
  | 4 | MINI BOSS | one of: The Ossuary (the Bone Colossus), Toadstool Hollow (the Toadstool Tyrant), The Sunken Cistern (the Mire Serpent) | ossuary / grove / cistern | boss room | ×2.0 | revenants / sporelings / eels |
  | 5 | LEVEL 4 | Fungal Caverns: toxic pools, spore nests | fungal | 3 | ×2.2 | sporecaps |
  | 6 | LEVEL 5 | Frozen Vaults: crevasses, slush, spike galleries | frost | 3 | ×2.6 | frost boars |
  | 7 | LEVEL 6 | Molten Forge: lava channels, powder kegs | forge | 4 | ×3.0 | salamanders |
  | 8 | FINAL BOSS | one of: Demon's Throne (the Demon Lord), The Mycelium Deep (the Spore Mother), The Frozen Court (the Frost Queen) | throne / mycelium / glacier | boss room | ×3.2 | imps / puffballs / frost wraiths (summoned) |

  Banners number the regular levels on their own (`RunConfig.title()`). Each level sets:
  - enemy mix: brutes, spitters and exploders grow more common level by level, next to the level's own enemy
  - an HP multiplier (above)
  - corridor pressure
  - arena quotas
  - a theme (tile sheet and decorations) and an optional tint
  - for boss levels: the boss (`boss_scene`), what the objective calls its room (`boss_room`), whether it is the final boss, and how much tougher the boss is than the level (`boss_hp_multiplier`: 1.5 for every boss, `BOSS_HP` in `gen_levels.py`; its servants only get the level's HP)
- **`LevelDirector` runs the objectives:**
  - An **arena room** (digit tiles) activates when a living hero is 36+ px inside it. Stragglers are pulled in with the leader, every door touching the room turns solid, and the spawner switches to arena mode.
  - The quota comes in **waves**: 2 (45% / 55%) up to 60 enemies, 3 (30% / 33% / 37%) above. The next wave comes once 25% or less of the current one is left (or after 12 s), after a 2 s breather, with a "WAVE 2/3" callout and a horn.
  - The room is cleared once its last wave has spawned and nothing is left alive in it. Quotas are ×(1 + 0.4 per extra player). The objective shows the wave and the enemies left: not yet spawned (this wave and later ones), in portals, and alive inside.
  - **Clearing an arena** (and so opening the exit) pulls every XP gem on the level to the nearest hero. Gems still lying around when a level ends are banked as XP, and each hero's ultimate charge carries over to the next level.
  - Clearing opens the doors, drops a heart, and returns the spawner to the corridor trickle.
  - The **exit portal** opens when every arena is cleared. The level completes after all living heroes stand in it for 1 s.
  - A **boss level's** one arena is its boss room, which spawns the level's boss instead of waves (and turns the spawner off). Picks open at once during the fight.
    - **Mini boss** (the Ossuary, Toadstool Hollow or the Sunken Cistern): when the boss dies its room clears like an arena (doors open, a heart, the XP vacuum), the music goes back to the dungeon track, the HUD calls out its name ("BONE COLOSSUS SLAIN!"), every player picks a legendary (see Legendary upgrades), and the exit portal behind its room opens (a chest waits beside it). The team walks on to level 4.
    - **Final boss** (the Demon's Throne, the Mycelium Deep or the Frozen Court, no exit): the boss's death ends the run in victory.
    - During the fight the objective arrow (and the bots) follow the boss, or what it calls for: the Spore Mother points at her pods ("Burst the spore pods!  3 left"). The HUD adds the boss's state to its name ("SHIELDED", "SUBMERGED", "BLIZZARD").
  - **Keep moving (the restless horde).** The corridors never stop spawning, so a team could stay and farm them for as long as it liked. Instead, out of fights the team has **60 s** (`LevelDirector.RESTLESS_AFTER`) to reach its next objective: an arena cleared, the mini boss's room cleared, then the exit. Each objective reached starts the clock over, and arena and boss fights stop it (so do pick screens, which pause the level).
    - When it runs out, the HUD calls "THE HORDE GROWS RESTLESS" with a growl (and a one-time tip), and the horde gains a stage at once and another every 15 s (`RESTLESS_EVERY`) until the next objective:

      | Stage (time without progress) | 1 (1:00) | 2 (1:15) | 3 (1:30) | 4 (1:45) | each 15 s after |
      |---|---|---|---|---|---|
      | XP and heart drops | 75% | 50% | 25% | none | none |
      | Corridor spawn rate | ×1.25 | ×1.5 | ×1.75 | ×2 | +25% |
      | Corridor alive cap (share of the player-count cap) | +10% | +20% | +30% | +40% | +10%, up to the whole cap |
      | HP of new enemies | ×1.2 | ×1.4 | ×1.6 | ×1.8 | +20% |
      | Enemy damage | ×1.1 | ×1.2 | ×1.3 | ×1.4 | +10% |
      | Enemy speed (`HordeSim.speed_mult`; charges keep theirs) | ×1.05 | ×1.1 | ×1.15 | ×1.2 | +5%, at most ×1.3 |
      | Elite chance | +1/40 | +2/40 | +3/40 | +4/40 | +1/40 (×0.5 on Casual, ×2 on Hard; level 1 too; still at most 4 alive) |

    - Drops fade for every enemy killed out of a fight, elites and nests included. Fractions of a gem carry over from kill to kill (`World._faded_xp`), so at 50% every other swarmer drops its gem. Urns, barrels, chests, the arena-clear heart and the XP vacuum don't fade.
    - Walking into an arena or the boss room holds the horde at the level's own settings, with full drops: the fight and the boss's adds are as usual. Clearing the room calms the horde and starts the clock over.
    - Only levels with a corridor horde have a clock (levels 1–6 and the mini bosses'); the final boss's level, Endless Waves and the test room don't. Bots walking straight from objective to objective need 6–28 s, and `test_bots_can_finish_every_level` checks they never let the clock run out. `--restless-after=5` shortens it for testing.
- **HUD:**
  - The objective text sits under the XP bar.
  - The keep-moving clock sits right of the team hearts: the time left to reach the next objective ("0:42"), grey, then gold and blinking for the last 10 s. It hides during fights. Once the horde is restless it reads "RESTLESS  XP 50%" (then "RESTLESS  no XP") in red.
  - A yellow arrow at the screen edge points to off-screen objectives (the next arena or the exit). The next arena is the one closest **on foot** from the team (`LevelGrid.walk_distances`, a BFS where walls, closed doors and chasms block and props don't), not in a straight line.
- **Spawner modes:**
  - CORRIDOR: off-screen trickle at a fraction of the alive cap.
  - ARENA: spawns on the room's floor at least 96 px from heroes, until the quota is spent.
  - OFF.
- **Bosses** (`Boss`, `src/enemies/boss/`): a boss's body is a `HordeSim` entry of its own enemy type, so every ability, projectile and zone hits it. The boss node moves that body, draws a sprite sheet of square frames (walk ×2, wind-up, action; 64×64, the Spore Mother 96×96) and runs the attacks; the base class holds what they share (body, sprite and wind-up glow, summons through portals, phase fanfare, the death, hitting heroes in a circle or a band). Bosses are immune to stun, slow and freezing; HP is base × level multiplier × the level's boss multiplier (1.5) × player-count scaling (see Spawn director). The boss multiplier makes each boss a real fight: without it most bosses fell in about half a minute.
  - A boss body can be **out of reach** (`HordeSim.hidden`: nothing hits, finds or touches it, like the Mire Serpent under the murk) or **shielded** (`HordeSim.guard`: the share of every hit, burns and poison included, it shrugs off).
  - **Every attack is telegraphed** during its wind-up: the boss glows hot pink (a flash shader, which hit flashes can't wash out) and growls, and the warning is drawn above the horde.
- **Mini boss (Bone Colossus, `BoneColossus`):** 1100 HP. A lumbering heap of bones with a club, fighting up close and from below.
  - Phase 1 (100–50%): walks at the nearest hero; **club sweeps** (only when someone is in reach) and **grave spikes** that burst under every hero.
  - Phase 2 (below 50%): enraged (faster, a roar and 8 risen dead: 3 revenants among 5 swarmers); spikes also burst around each hero, it **leaps** onto the hero furthest away (bone shards burst from the landing), and it **raises the dead** (2 revenants among 4 swarmers).
  - Telegraphs: sweep: a wedge exactly as wide as the swing, filling up (`FxLayer.warn_arc`); spikes: a filling circle under each hero, where they stood when it wound up; leap: the landing circle, until it lands; raise: the spawn portals.
  - In the air it deals no contact damage (its body counts as stunned).
- **Final boss (Demon Lord, `BossDemon`):** 1800 HP, three phases:
  - fireball fans and ground slams
  - plus fire rings and summons: imps spread among swarmers (a phase change brings 9-12 adds, 3-4 of them imps; the summon attack 8, 3 of them imps)
  - enraged: faster, plus telegraphed charges
  - Telegraphs: slam: its exact circle filling up; charge: a band as wide as what it hits; fan: one aim line per fireball, with the aim locked when the wind-up starts; fire ring: a ring of turning dots around the boss; summon: the adds' spawn portals.
- **Mini boss (Toadstool Tyrant, `ToadstoolTyrant`):** 1150 HP. A giant red-capped toadstool with an angry face that waddles after the nearest hero.
  - Phase 1 (100–50%): **bounces** - three hops in a row, each onto the hero nearest when it squats (120 px at most), 22 damage where it lands - and **spore bursts** when heroes crowd it: a cloud under it and six in a ring 44 px out (7 a hit, 5 s).
  - Phase 2 (below 50%): enraged (faster, 7 sporelings sprout around it), four hops a bounce, eight clouds a burst, **spore bombs** lobbed at every hero and two more around them (each leaves a cloud), and **sprouts** of 5 sporelings.
  - Telegraphs: each hop's landing circle from its squat until it lands (it throbs pink while squatting); every cloud's circle before a burst; each bomb's landing circle; spawn portals. In the air it deals no contact damage.
- **Mini boss (Mire Serpent, `MireSerpent`):** 1000 HP. A great serpent that hides in the murk of its cistern and never walks.
  - Surfaced (5 s, 3.6 s enraged): **spits** a fan of 3 water shots (5 enraged) at the nearest hero and **lunges** its head down an 84 px band at anyone close.
  - Then it **dives**: still hittable for 0.45 s while it sinks, then out of reach (the HUD says SUBMERGED) while it **hunts** the nearest hero as a fin and a wake at 62 px/s (74 enraged) - slower than a hero walks, faster than one wades - for 2.4 s (1.8 s enraged). It stops, a circle fills for 0.7 s, and it **bursts up** there (24 damage in 32 px).
  - Phase 2 (below 50%): 5 eels come up as it enrages, every burst brings 2 more, and each dive bursts up twice (a breath of 0.6 s, then a quick 1 s hunt).
  - Telegraphs: the burst's circle; the fan's aim lines (locked when the wind-up starts); the lunge's band, exactly as wide as what it bites; spawn portals.
- **Final boss (Spore Mother, `SporeMother`):** 1800 HP. A towering fungus rooted in the middle of her cavern; she never moves.
  - **Spore pods** (90 HP each, one-of-a-kind HP scaling) sprout around her as the fight starts (3) and again in phase 2 (4), tied to her by glowing threads. While any stands she is **shielded** (she shrugs off 80% of every hit; the boss bar turns grey-violet, the HUD says SHIELDED and the objective points at the pods). Her pods wither when she dies.
  - Phase 1 (100–60%): **roots** burst along a band from her toward every hero (22 damage; step out of it) and **spore rain**: bombs on and around every hero and three more anywhere near her, each leaving a spore cloud.
  - Phase 2 (60–25%): the pods grow back, 8 adds come (4 puffballs); adds two more random root bands, **spore spirals** (three arms of spores wheeling out of her for 2.4 s) and **calls** of 6 adds (3 puffballs).
  - Phase 3 (below 25%): enraged (faster, another crowd, four spiral arms, three extra root bands) and **fairy rings**: seven rings 32 px wide around her; every other one erupts (24 damage), then the ones between them. Stand in a ring that waits, then step into one that has erupted.
  - Telegraphs: every root band; each bomb's landing circle; a ring of turning dots before a spiral; each fairy ring, filling up; spawn portals.
- **Final boss (Frost Queen, `FrostQueen`):** 1900 HP. A gaunt queen of ice gliding over her court, keeping 80–130 px from the nearest hero. Her frost **chills**: a chilled hero walks at 60% speed for a moment (tinted icy).
  - Phase 1 (100–60%): **ice lances** (an aim line to every hero, then a fast shard down each), **frost novas** (a ring of frost rolling out to 170 px: it hits each hero once as it passes, 18 damage and a chill - dash through it or stand outside the circle) and **icicle hail** (for 2.4 s, icicles crash down on and around the heroes, each after its circle shows for 0.8 s).
  - Phase 2 (60–25%): a crowd with 3 frost wraiths, then the **glacial beam** (a freezing beam sweeps a 115° wedge through the nearest hero in 1.6 s, 20 damage and a chill) and **calls** of 6 adds (3 frost wraiths).
  - Phase 3 (below 25%): enraged (faster, lances in threes) and **blizzards**: for 5 s a wind pushes every hero one way (34 px/s) while shards of ice ride it in from the upwind wall.
  - Backed into a wall with a hero on her for 0.8 s, she **steps through the ice** to a spot 150 px beyond them: she fades out for 0.5 s while a frost portal shows where she'll appear.
  - Telegraphs: aim lines (locked when the wind-up starts); the nova's full reach, filling up; each icicle's circle; the beam's wedge and where it starts; the "BLIZZARD!" callout; spawn portals.
- **Screens:** Main menu → Character select → Game (levels, or Endless Waves) → End screen → Play again / Change heroes / Main menu.
  - **End screen:** difficulty, levels, enemies, team level, time and Second Winds; any records set; and a table of every player's kills, damage dealt and taken, downs, revives given and biggest hit, with awards: Slayer (most kills), Medic (most revives), Tank (most damage taken), Sharpshooter (biggest hit) - only with teammates to beat - and Untouchable (never downed). After Endless Waves the title is "GAME OVER" and the wave reached takes the place of the levels. **Play again** starts a new game right away with the same team, heroes, difficulty and mode; **Change heroes** goes to character select with everyone still joined and their last hero picked.
  - **Main menu:** Start Run, Endless Waves, Test Room (drop-in sandbox), Options, Quit. Start Run and Endless Waves set `GameState.mode`, which character select, the Game and the end screen follow. The main, pause and end menus use Godot focus navigation, so keyboard, any gamepad or mouse all work, with move/confirm sounds (`UiSounds`).
  - **Character select:** 4 quadrants. Each shows the hero running on the spot, toughness / damage / speed as pips, a difficulty tag (Easy / Medium / Hard) and the four abilities with that player's own buttons.
    - Press A/Enter to join (holding that button doesn't also ready you up).
    - Left/right to browse the 8-hero roster.
    - A/Enter to ready, B/Esc to un-ready or leave.
    - When everyone who joined is ready, any of them presses A/Enter (or Start on a gamepad) to begin. There is no countdown.
    - With nobody joined, B/Esc/Backspace returns to the main menu. The press that makes the last player leave doesn't count.
  - **Enter with Alt held** is the fullscreen shortcut and never counts as a confirm press, even if Alt is let go first.
  - **`Game`:** builds a `World` per level, shows "LEVEL n" / "MINI BOSS" / "FINAL BOSS" and "LEVEL CLEAR!" banners, and banks stats. A team wipe means defeat; the final boss's death means victory.
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
- **Bots** (`BotDriver`) follow the current objective with A* over the level grid and use their abilities. The test suite has four god-mode bots finish every level and second layout and every boss's level, and `./tools/dev.sh run res://src/main/game.tscn -- --bots=4 --level=4` shows a bot mini boss fight (`--level=8` the final boss; add `--boss=grove` and so on for a particular one).

## Endless Waves

The second mode (main menu → Endless Waves): no dungeon, just waves that keep getting harder, until the team falls. The score is the wave reached, and the best wave is kept per difficulty.

- **The Pit** (`src/levels/data/waves.tres`, built by `tools/gen_levels.py`, not part of the run) is one sealed arena of about 60×40 tiles. It has four pillars, a pool on either side, spike beds at the top and bottom, powder kegs by the walls, a few urns, the team's spawn in the middle, and four `B` spots for bosses. It has no doors, exit, nests, chests or shrines, and no chasms, because frost wraiths could hover over one out of reach. Each game mirrors it at random and dresses it in one of the 12 tile themes (`WaveDirector.arena_for()`).
- **The loop:**
  - A break: 4 s before wave 1 (under the "ENDLESS WAVES" banner), then 5 s, counted down in the objective ("Wave 3 cleared!  Next wave in 4").
  - Then the wave: "WAVE n" and the horn, and its enemies come in through portals on the arena's floor, as in arena fights ("Wave 7  -  42 left").
  - The wave is cleared once all of it has come in and nothing is left alive. If three or fewer hold out for 20 s, it counts as cleared anyway, and they stay in the fight. With five or fewer left, the arrow (and the bots) go for the nearest one.
  - A clear drops a heart at the team, pulls in every XP gem (`arena_cleared`, as for an arena) and says "WAVE n CLEARED".
- **Picks** earned during a wave wait for the break after it, and the HUD shows "+2" as in arena fights. During a boss wave they open at once. The countdown stops while the pick screen is up.
- **Every wave is harder than the last** (`WaveDirector.settings()`, per wave w; the difficulty's multipliers come on top):

  | | Rule | w1 | w5 | w10 | w20 | w30 |
  |---|---|---|---|---|---|---|
  | Enemies (solo) | 24 + 9 per wave, at most 300; ×(1 + 0.4 per extra player) | 24 | 60 | 105 | 195 | 285 |
  | Enemy HP | +0.115 a wave up to wave 20 (×3.2, the final boss level's), then ×1.07 a wave | ×1.0 | ×1.46 | ×2.04 | ×3.19 | ×6.27 |
  | Spawns per second | 24 + 1.2 per wave, at most 48 | 24 | 29 | 35 | 47 | 48 |
  | Enemy damage | +3% a wave after wave 10 | ×1.0 | ×1.0 | ×1.0 | ×1.3 | ×1.6 |
  | Elites | from wave 4: `Elites.CHANCE`, +10% a wave, at most ×3 | – | ×1.1 | ×1.6 | ×2.6 | ×3 |

  - The mix: swarmers throughout. Brutes join on wave 2, spitters on 3 and exploders on 4, and each grows more common up to 0.25 / 0.16 / 0.22, a little above the Molten Forge's.
  - From wave 2, each regular wave features one of the 12 level enemies (bats, drowned, bone archers, revenants, sporecaps, frost boars, salamanders, imps, sporelings, eels, puffballs, frost wraiths) at weight 0.15, in an order shuffled per game. From wave 12 the one before it stays on, and from wave 24 the two before.
  - At most as many enemies are alive at once as in the run (the alive cap by player count), so bigger waves last longer rather than crowding more.
- **Boss waves:** every 5th wave. Waves 5, 15, 25… bring a mini boss and waves 10, 20, 30… a final boss. Each game shuffles the three of each kind, so all three come before any repeats. The pools are read from `RunConfig` (its levels and boss pools), so a boss added to the run joins Endless Waves too.
  - The boss comes through a portal (1 s) at the `B` furthest from the team, with "BOSS WAVE" and the boss music. Its HP scales with its wave, like the horde's, on the bosses' player curve (without the run's boss multiplier: the first boss wave comes after only four waves' worth of picks).
  - The spawner stays off, as in the run's boss rooms: the boss brings its own servants.
  - Beating it says "<NAME> SLAIN!", gives a treasure round (a bonus pick) and refills the team's lives. It never ends the game.
  - **Legendaries come on waves 10, 20 and 30 only** (`WaveDirector.LEGENDARY_WAVES`, the first three final bosses): beating those bosses opens a **legendary round** (see Legendary upgrades) ahead of the bonus pick, so each hero's three legendaries come one at a time, about ten waves apart, instead of all three by wave 15 (every boss wave used to give one). The mini bosses of waves 5, 15 and 25, and every boss after wave 30, give none (`LevelDirector.grants_legendary()`). If no hero has a legendary left to take, no round is queued at all (`World.legendaries_left()`), rather than an empty one. At those waves a team is around level 6, 10 and 15, whatever its size (bots, Normal).
- **Team lives:** the difficulty's lives per level at the start, refilled after every boss wave, so five waves play the part of a run's level. A wipe with no life left ends the game: "GAME OVER / You reached wave n", then the end screen.
- **Records:** `Profile.record_waves()` keeps the furthest wave per difficulty, shown in character select ("Best: wave 12") and announced on the end screen ("NEW BEST WAVE!"). Reaching wave 20 on a difficulty also unlocks the next one (`Profile.UNLOCK_WAVE`): Hard from Normal, Nightmare from Hard, Torment from Nightmare.
- **Code:**
  - `WaveDirector` extends `LevelDirector`, and the World uses it instead when `wave_mode` is on. It reuses the base's arena spawning (`SpawnDirector.start_arena`), enemy counting, boss spawning (`_spawn_boss(at, scene)`) and boss objective. It replaces `tick()`, `picks_held()` (the World asks the director) and the boss's death.
  - The Game builds one World for the whole game (`_load_waves()`).
  - `GameState.wave` is the last wave that started.
  - Debug: `--waves` plays Endless Waves, and `--wave=N` starts at wave N.
  - `tests/test_waves.gd` checks:
    - the curve, the boss schedule and the mix
    - The Pit
    - the loop, stragglers and held picks
    - boss waves, with every boss fighting in The Pit
    - records and screens
    - a full wave-33 horde
    - four bots holding out through the first waves and a boss wave

## Map features

What makes the levels play differently, beyond their shapes:

| Layout char | Feature | How it plays |
|---|---|---|
| `~` | Water | Everyone walks at 60% speed. Bots avoid it when they can. |
| `:` | Chasm (lava in the forge and on the throne level) | Can't be walked on. Shots and line of sight cross it. An enemy shoved toward it harder than 30 px/s goes over the edge and dies. The last hero to hit or push it gets the kill, and its XP lands on the nearest floor. |
| `^` | Spike trap | Retracted, then warning, then up, on a 3 s cycle, firing in diagonal waves. When the spikes shoot up they stab everyone on them: heroes take 14, enemies 24 × the level's enemy HP multiplier. |
| `b` | Explosive barrel | Breaks in one hit, then blows up 0.05 s later: 40 × HP multiplier with big knockback. It breaks other barrels (chains) and never hurts heroes. |
| `u` | Urn | Breaks in one hit and scatters 6 XP (sometimes a heart). |
| `N` | Nest | Spawns 2 enemies from the level's mix every ~2.6 s while a hero is within 230 px. Arena nests sleep until the fight starts, and an arena with nests clears only once they're destroyed ("Destroy the nests!"). |
| `C` | Treasure chest | Touch it: the whole team gets an extra upgrade round ("TREASURE!"). |
| `A` | Shrine | Touch it for a team blessing, shown on the shrine: Fury (+50% damage, 30 s), Haste (+30% move and attack speed, 30 s), Life (full heal, revive everyone) or Wrath (smite everything on screen). |

- **Implementation.** Barrels, urns and nests are stationary `HordeSim` entries (`EnemyData` behaviours `OBJECT` / `NEST`), so every attack already hits them. They block walking on their tile (`LevelGrid.set_blocker`) until destroyed, but not shots. Objects aren't enemies: they give no kill credit, corpses or XP gems, don't count toward the spawner's cap, and bots and minions don't target them. Chests and shrines are `Interactable` nodes.
- **Terrain.** `LevelGrid` keeps `solid` (walking: walls, closed doors, chasms, props) apart from `shot_solid` (projectiles and sight: walls and closed doors). It also stores terrain per tile and logs walkability changes, so the bots' A* only updates the cells that changed.
- **Arena rooms.** Each arena is found by flood fill from its digit tiles, so everything inside its walls belongs to it: water, traps, chasms and props. The level test checks that shutting an arena's doors seals it.
- **Themes.** Each level names a tile sheet (`assets/tiles/tiles_<theme>.png`: crypt, flooded, bones, ossuary, fungal, frost, forge, throne, and the other bosses' grove, cistern, mycelium and glacier). Water (toxic pools in the fungal caverns, slush in the frozen vaults) and chasm/lava tiles are animated, and lava (`Level.LAVA_THEMES`: forge, throne) glows. The level is decorated from a per-tile hash:
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
- **Flow field:** multi-source BFS from all living players over the tile grid. It runs on a `WorkerThreadPool` thread with double buffering and refreshes about every 0.2 s. Enemies follow the field toward the nearest player, except when they can walk straight there (see Enemy movement).
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
              abilities/forms/ (the legendaries' forms), HeroMissile, Minion,
              data/<hero>.tres and data/forms/<legendary>.tres (generated by tools/gen_hero_data.py)
  enemies/    EnemyData + data/*.tres, SpawnDirector (corridor/arena modes), Elites,
              boss/ (Boss base; mini bosses BoneColossus, ToadstoolTyrant, MireSerpent;
              final bosses BossDemon, SporeMother, FrostQueen)
  upgrades/   UpgradeData, UpgradePool, data/*.tres
  levels/     Level (tiles + grid + arena rooms from LevelData), LevelDirector (arenas, exit, bosses),
              WaveDirector (Endless Waves), RunConfig, data/*.tres (generated by tools/gen_levels.py)
  ui/         HUD, level-up screen, main menu, character select, pause menu, end screen
  main/       Game (run controller: levels or Endless Waves, banners, victory/defeat)
assets/fonts  Pixel5x8 proportional bitmap font (BMFont, generated), default theme font
tests/        headless test runner + test_*.gd
tools/        dev.sh helper (dev.cmd on Windows), stress test scene
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
  - The legendaries add mortars (they pick the densest pack among a dozen candidates and lob shells), the bone golem (a big skeleton that slams in a circle) and the Ranger's decoy (it stands still, takes contact damage and lays its caltrops when it goes).
  - **Lures:** decoys and the golem are added to the horde's targets (`World._snapshot_heroes()`), so the flow field, steering, spitters, chargers and exploders treat them like heroes. Bosses still go after heroes.
- **`HeroMissile`:** the few shots an ability flies itself (a thrown axe that comes back, orbiting knives, homing wisps, the ice orb, the heavy arrow): a sprite from the fx atlas, hits through `HordeSim.query_bodies()` (the projectiles' hurtbox test) and `World.hit_enemy()`, each enemy once or again after a delay (knives in one vortex share that memory). The owning ability ticks it in `_tick_active`.
  - Minion damage counts toward the owner's lifesteal and, unless an ultimate summoned them (Army of the Dead, the tesla tower), ultimate charge.
  - They retarget every 0.4 s.
  - Caps: Raise Dead 8, Army of the Dead 16, turrets 2, towers 1.
- Upgrades tweak abilities through `Ability.mods` (e.g. `pierce`, `count`, `area_pct`, `max_active`, `minion_hp_pct`). There are 86 upgrades: 17 generic, 4–5 per hero, 12 elemental and 24 legendaries, which replace an ability with a new form (see Legendary upgrades).
- `ProjectileSim` shots can also turn toward the next enemy after a hit (`TRAIT_RICOCHET`), log the kills they make (`TRAIT_REAP`), fork at a wall bounce (`splits`) and set enemies on fire (`Effect.BURN`).
- Hero tuning lives in `tools/gen_hero_data.py`, which writes `src/heroes/data/*.tres`. Edit the table and re-run it, or edit the `.tres` in the Godot inspector.
- **Ultimate charge:** damage dealt ÷ the hero's `ult_cost`, plus 1% per second passively, both times the charge rate (Recharge: +25% each). The player ring pulses when the ultimate is ready.
  - **A ceiling:** however much the hero deals, the meter fills no faster than `Hero.ULT_MAX_PER_SECOND` (1/16 per second) times the charge rate: 16 s from empty, 12.8 s / 10.7 s / 9.1 s with one / two / three Recharges. Charge earned faster waits in `Hero.ult_bank` (no more than the meter still needs) and flows in at that pace, so a burst isn't lost. Late in a run damage grows into the thousands per second, and without it the meter refilled in about a second.
  - **Not while it works:** nothing charges the meter (not even the trickle) while the ultimate is still at work (`Hero.ult_working()`): its ability is active (a spin, a buff, clones, a meteor on its way down, a singularity, a lich), or a zone or minion it made is still there (`World.ultimate_at_work()`: Arrow Rain, a tesla tower, the army). Toxic clouds don't count: plague can keep spreading from cloud to cloud. So a 16 s Rampage or Tesla Tower can't be kept up for good. Meanwhile the HUD's ultimate bar glows dimly.
  - An ultimate never charges itself (it could be chained otherwise). While one works (its `_activate` / `_tick_active`, the clones' swings) `HordeSim.ult_hits` is on, and its hits also go to `ult_damage_by_slot`, which `World._apply_ult_charge()` leaves out. Minions and zones made meanwhile keep that (`World.add_minion` / `add_zone`), and so do the statuses it applies (`status_ult`: their damage over time, spreading fire and death effects) and the barrels it sets off. It all still counts as damage dealt, for stats and lifesteal.
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

### Enemy movement
Every walking enemy moves in `HordeSim._move()`:
- **Momentum:** each enemy has its own walking velocity (`HordeSim.walk`). It eases toward where the enemy wants to go at its kind's `agility` per second: bats 14, swarmers 8, brutes 4, frost boars 3. Heroes use the same easing.
  - Charges and hops keep their own speed profile.
  - Stuns and freezes stop an enemy dead, and so does every action that plants its feet: wind-ups, fuses, lining up a charge, catching its breath, a blink. So warnings never slide.
  - Separation and knockback stay outside it.
- **Straight when the way is clear:**
  - Every 0.25 s (staggered by uid), an enemy more than 2 tiles from its nearest hero and within 22 tiles of them checks whether it can walk straight there. `LevelGrid.walk_line_clear()` is blocked by walls, closed doors, chasms and props, but not by water.
  - While the way is clear, it heads straight at the hero at the true angle. Otherwise it follows the flow field, and momentum turns the hand-off into a curve.
  - That's at most 1,200 short rays a second at 300 enemies. The DDA behind both `walk_line_clear()` and `line_of_sight()` runs on plain ints, about 40% faster than before.
- **Pace and approach:** each enemy has two traits of its own.
  - `pace`: it walks at its kind's speed ±10%. Charges keep their full length.
  - `bend`: closer than 7 tiles, melee enemies arc in sideways by it (up to 0.8), so the horde fans out and closes in from several sides. They straighten out for the last stretch.
- **Arrival and crowds:**
  - Closing in, an enemy eases off over 12 px and stops at 60% of touching distance. It still hurts, but it doesn't pile onto the hero.
  - Inside that distance, the hero counts as a body in the separation push, so the crowd behind can't squeeze anyone onto the hero's feet.
  - Pressed from the front (separation pushing against its way), an enemy slows down, to as little as 15% of its speed, and waits its turn instead of shoving.
- **Steering clear of the heroes' AoEs:** every frame the World hands the horde the circles that are hurting enemies or about to (`World._collect_dangers()` → `HordeSim.add_danger()`):
  - lasting zones that do something to enemies: Arrow Rain, caltrops, fire trails, toxic clouds (not Sanctuary, which only heals)
  - blasts on their way down: a Meteor's mark, mortar shells
  - auras round a hero: Whirlwind, Blade Vortex

  Abilities report theirs through `Ability.add_dangers()` and mortars through `Minion.add_dangers()`; a downed hero's wait with them. Then:
  - Each enemy takes a moment to notice a new one: 0.2 s, plus up to 0.3 s more by its uid. So a Meteor still catches the middle of a pack, but its rim gets out in time.
  - Caught in one, an enemy gets out the nearest way, at full speed.
    - Unless a wall, a chasm or another AoE is in the way straight out (`HordeSim._escape_way()`): then it tries turns of up to 135° either way, and straight back, and takes the one that gets it clear of them all soonest (each 45° turned counts as 6 px further, a way toward its goal a little nearer). So an enemy pinned against a wall or in a corner gets out along the wall, and one between two AoEs doesn't flee from one into the other.
  - Walking into one, it stops going in over the last 16 px before the edge (its footprint stays 3 px clear) and turns that part of its way along the edge, so it goes round. It keeps to the side it's already going round, else takes the side its hero is on, else its own `bend`. (The flow field's steps turn from tile to tile: going by them, it would dither.)
    - Choosing a side, it looks 45° further round the edge (`_round_open()`): if a wall shuts that side it goes round the other, and with both shut (an AoE across a corridor) it waits at the edge.
  - When its hero stands inside (a spinning Knight), it waits at the edge instead.
  - Busy enemies don't break off: a wind-up, a lit fuse, lining up or making a charge, a blink or a stun. Imps never blink into one.
  - Cost: dangers are flagged per tile (a bit each, at most 32 at once), so only the enemies near one look at it, and ones nobody can have noticed yet are skipped. Like the separation push, half of those enemies work out their turn each frame; the others take the one they worked out the frame before (`HordeSim.dodge`). The F3 overlay and the stress test count the dangers.
    - Walls are only looked for round dangers that have one in reach (`_walled()`: a scan of the danger's tiles, once a frame, by the first enemy that needs it), so in the open a way out costs a couple of tile lookups, and only near walls a ray.
- **Facing:** an enemy faces the first of these that applies:
  - its aim, while lining up a charge or drawing an aimed shot
  - its target, when within 2 tiles, in range (ranged enemies) or standing still
  - the way it walks, never the crowd's jostle or a knockback

  It only turns once that way is more than about 12° off vertical, so crowds don't flicker.
- **Walk cycle:** walkers step as far as they actually walk (`HordeSim.stride`, at `anim_fps` at full speed).
  - They step slower wading, chilled or queueing, and tread once they've reached a hero.
  - They stand in their neutral pose (frame 0) when still.
  - Flyers flap on the clock.

### Enemy behaviours
- **Chaser:** goes for the nearest hero, straight when the way is clear or within 2 tiles, else along the flow field, and round the heroes' AoEs (see Enemy movement).
- **Ranged (spitter):** inside its range, it circles its target at about 80% of that range at half speed, changing sides every 2.4 s, and backs off when heroes get closer than 55% of it. When its cooldown is up and it has line of sight, it stops dead and glows hot pink for 0.4 s (its shot pose), then fires at the nearest hero. It only starts a shot while it's inside the camera view, so nothing fires from off screen.
- **Exploder:** lights its fuse when close, then blasts heroes in its radius that it has line of sight to (walls stop it, like the boss slam). Killing it during the fuse cancels the blast, and self-destructs drop no XP.
- **Knockback:** damage pushes enemies away from the hit source, scaled per type (brutes resist). A shove also breaks an enemy's stride: its walking speed drops by the shove over 160 px/s (after its resistance), by 85% at most, then it gets going again at its agility. Stun freezes, slow halves speed, and marks make enemies take ×1.75 damage.
- **Each level's own enemy** is data (`EnemyData`) plus a few behaviour switches in the horde's loop, so it costs about 0.1 ms per frame with every kind in the stress room:
  - **Flocks and flyers (bats):** `pack` spawns that many together; `weave` adds a sideways swing to their steering (a sine per enemy); `flying` enemies ignore water and are never carried over a chasm's edge.
  - **Swimmers (drowned):** `swim_speed` replaces the wading slow in water, where they're drawn with their swim frames.
  - **Aimed shots (bone archers):** `EnemyData.Shot.AIMED` locks the aim when the wind-up starts (`HordeSim.aim`); the World draws it as a live line (`FxLayer.set_live_bands`) that ends at the first wall (`LevelGrid.shot_reach`) and vanishes if the archer dies or is stunned out of it.
  - **Lobs (salamanders):** `Shot.LOB` logs the throw; the World flies the glob (`FxLayer.lob`), marks the landing, bursts it there (walls stop the burst) and leaves slag.
  - **Chargers (frost boars, `Behavior.CHARGER`):** roam, line up (pink glow, a live band as wide as its reach), charge (`charge_speed` × `charge_time`, contact damage ×2), then catch their breath (0.6 s), or stay dazed (1.3 s) after a wall. The charge counts as a push, so it can carry the boar over a chasm's edge.
  - **Blinkers (imps, `Behavior.BLINKER`):** pick a spot about 30 px from a hero, on their own side if they can, that the hero can see and that's out of the heroes' AoEs; a portal opens there while they fade out.
  - **Bone piles (`Behavior.PILE`):** a revenant (`OnDeath.BONES`) leaves one that remembers what it was (`state`) and gets back up when its timer runs out. Piles count as enemies (arenas wait for them) but don't walk, block tiles or leave corpses.
  - **Enemy hazards** (`World.add_hazard()`: spore clouds from `OnDeath.SPORES` (`cloud_damage` a hit), slag): heroes inside take a hit whenever their hit invulnerability runs out. `World.lob()` flies any bomb (salamanders' slag, the mushroom bosses' spores) and leaves the right remains.
  - **Hoppers (sporelings):** `hop` hops a second; each spends 55% of its time in the air at 1.8x speed and sits still for the rest, drawn sitting, landing, taking off and up high (`HordeSim.hop_frame()`).

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
| 12 | Dungeon expansion: an 8-level run (levels 1–3, a mini boss, levels 4–6, the final boss), the Bone Colossus, Fungal Caverns / Frozen Vaults / Molten Forge with second layouts, four new themes | done |
| 13 | Level enemies: every level's own enemy (bats, drowned, bone archers, revenants, sporecaps, frost boars, salamanders, imps) with its behaviour, art, sounds and warnings; bosses raise revenants and summon imps | done |
| 14 | More bosses: boss pools (each run meets one of three mini bosses and one of three final bosses); the Toadstool Tyrant and the Mire Serpent (mini), the Spore Mother and the Frost Queen (final), each with a level, theme and servant of its own (sporelings, eels, puffballs, frost wraiths) | done |
| 15 | Legendary upgrades: beating the mini boss offers each player three legendaries, each turning one of the hero's abilities into a new form (24 in all), with their shots, minions, sounds and tests | done |
| 16 | Endless Waves: a second mode where the team holds one arena (The Pit) against waves that keep getting harder until it falls; a boss every 5th wave, each a legendary round; best wave per difficulty | done |

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
- **Milestone 13 re-check** (every level enemy in the stress room, 2026-09-27, same Air, fullscreen, back to back with the milestone 12 build): 4.95 ms average, 6.36 ms p99, 2.17 ms sim, against 4.79 / 6.32 / 2.06 ms before. The new behaviours cost about 0.1 ms of simulation.
- **Milestone 14 re-check** (the bosses' servants added to the stress room, 2026-09-27, same Air, back to back with the milestone 13 build): 4.93 ms average, 6.36 ms p99, 2.11 ms sim, against 4.78 / 6.18 / 2.06 ms before. Hops and the out-of-reach and shield checks cost next to nothing.
- **Milestone 15 check** (legendaries, 2026-09-27): not on the Air, but headless in a Linux container, so only simulation time counts (headless frame pacing isn't a measurement). 20 s with `--ult-spam`, each hero given all three of its legendaries at once (more than a run allows) against the same heroes without: Rogue, Engineer, Necromancer and Cleric 2.59 → 2.75 ms sim (flames, forks and ricochets add ~0.17 ms of projectiles); Knight, Ranger, Mage and Berserker 2.51 → 2.51 ms. Re-measure on the Air.
- **Enemy movement check** (2026-09-27): on the Air, but headless, so only simulation time counts. Headless runs read higher than windowed ones, before and after alike. Three 20 s stress runs alternated with the build before:
  - The horde went from 1.04 to 1.29 ms, and the whole simulation from 3.13 to 3.25 ms.
  - On its own, the horde step (300 mixed enemies round four heroes, 120 fps) went from 0.77 to 1.01 ms. The clear-path rays and the nearest-hero search they need cost 0.08 ms of that, arc-in and arrival 0.04 ms, and facing 0.035 ms.
  - The shared DDA got about 40% faster, which speeds up every `line_of_sight()` check too.
  - Re-measure windowed with `--fullscreen --max-fps=120 --seconds=60`.
- **AoE avoidance check** (2026-09-28): headless in a Linux container, so only simulation time counts. Four 20 s stress runs alternated with the build before, in each mode:
  - The horde went from 1.40 to 1.49 ms (plain, 2 dangers on average) and from 1.33 to 1.40 ms (`--ult-spam`, 1.5 on average); the whole simulation stayed within run-to-run noise.
  - Worst case, on its own: 300 enemies round four heroes with three overlapping AoEs on the crowd (205 enemies near one). The horde step goes from 1.51 to 1.88 ms. Of that, the steering is ~0.18 ms (about 110 enemies work out a turn each frame, ~1.65 µs each) and flagging the tiles ~0.025 ms; the rest is the crowd itself, kept at a distance and packed along the edges. AoEs that no enemy is near cost ~0.03 ms.
  - Re-measure on the Air.
- **Smarter dodging check** (walls and other AoEs in the way out, going round the open side; 2026-10-01): headless in a Linux container, so only simulation time counts.
  - Real level (`--level=level_3 --ult-spam`, three 20 s runs alternated with the build before): 2.32–2.44 ms sim before, 2.34–2.58 ms after, within run-to-run noise. The occasional 26–40 ms spike shows up in both builds.
  - Worst case, on its own: 300 swarmers among 32 AoEs (every slot) in a room full of pillars, about 20 enemies working out a way out each frame. The horde step goes from about 1.2–1.5 ms to 1.5–1.9 ms (best of 3, noisy machine): the way-out search costs ~0.19 ms of that (~9 µs per enemy, mostly checking that straight out is open near walls), the going-round checks ~0.01 ms. Walking the danger bits by set bit only (not bit by bit) took back part of it.

## Art, effects and audio

- **Art:** all sprites, tiles and the UI font are generated by `tools/gen_placeholder_art.gd` (deterministic and license-free):
  - 8 heroes (idle/run/dash/downed)
  - 16 enemy kinds, the bone pile and the spore pod (walk + action frames; flyers get a shadow)
  - six bosses: the demon, the bone colossus, the toadstool tyrant, the mire serpent (and its fin) and the frost queen at 64×64, the spore mother at 96×96
  - projectiles (the legendary forms' in row 3 of the fx atlas: crescent, axe, ice shard, flame, prism orb, heavy arrow, ice orb; never hot pink), pickups and particle blobs
  - dungeon tiles in twelve themes
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
  - **Each level's own enemy** warns the same way: a bone archer's aim line and its hot pink shard, a frost boar's charge band, where a salamander's slag will land, an imp's portal. Spore clouds are pink zones; burning slag is orange.
  - **Heroes** have a 1 px outline in their player colour (`hero_outline.gdshader`), so two players on the same hero, or the dark Rogue and Necromancer on dark floors, are easy to find. A "P1" tag shows over each hero for 3 s at level start, after a revive and while downed. Reticles are drawn above everything (`HeroOverlay`).
  - Hearts are drawn above the horde and marked on the minimap; shrine blessings ring heroes in pale gold rather than a player-like colour. A heart heals 25% of max HP and only goes to a hurt hero: the most hurt one in range, never one at full HP. Holy Dash also heals the Cleric for half as much, so it works solo.
  - Lines 1 px wide are drawn as line primitives: with vertex snapping on, a 1 px quad at an angle collapses to nothing.
- **Feedback** (feel every hit, never miss a downed friend):
  - **Getting hit:** rumble scaled to the share of HP lost, the player's HUD panel flashes red, and hits of 15%+ of max HP shake the screen and show a big red number. Heroes' numbers are never pushed out by the horde's. Each player's hurt sound has its own pitch.
  - **Low HP (≤ 30%):** the hero's outline and HUD panel pulse red; crossing the line plays a heartbeat (at most every 3 s) and a rumble.
  - **Invulnerability looks different by cause:** blink after a hit, bright while dashing, a gold shimmer after a revive.
  - **Abilities:** the special and movement ability ping (a ring, plus a tick for the special) and flash their HUD bar when they come back; a press that can't do anything (on cooldown, no ult charge, channelling) flashes the bar red with a soft blip. The ultimate announces itself once per charge: a chime, a rumble and "ULT!".
  - **Downed:** a pulsing "!" and "P1" over the body, a dashed circle showing where to stand, and the revive progress as a ring; a rising tone while someone revives, and a "help" ping (at most every 3 s) while nobody does. The HUD's "DOWN! revive me" blinks.
  - **Hitstop** (a world-level freeze, the HUD keeps running): 0.08 s on a boss phase change; 0.3 s then 0.6 s of slow motion on a boss's death. Ordinary hits never freeze the game.
- **Damage numbers:** one node draws up to 40 numbers.
  - **Crits** always get a gold double-size number with "!" (e.g. `14!`), a gold star burst and a "tink" sound. Ordinary numbers can never push them off screen.
  - Ordinary hits get a white number from 12 damage up (double size from 40).
  - Damage to heroes shows in red.
- **Other effects:**
  - vector FX (`FxLayer`) for slashes, rings, telegraphs and zones
  - white hit flash in the shader
  - frozen tint
  - pixel-snapped screen shake
- **Audio:** `tools/gen_audio.gd` renders 78 SFX and 3 music loops (menu, dungeon, boss) with a small synth and sequencer into `assets/audio`.
- **`Audio` autoload:**
  - Plays SFX through a 24-voice pool on an `SFX` bus. Six voices are reserved for cues players must not miss (down, revive, ult, level-up, heartbeat, help, boss wind-up and death, the restless horde's growl, stings...), so a flood of hits can't cut them off.
  - Each sound has a minimum repeat interval (e.g. kills every 50 ms), so a horde never drowns everything out.
  - Loops music on a `Music` bus and crossfades between tracks (0.6 s). The boss track starts when a boss room's fight does (and gives way to the dungeon track when the mini boss falls); victory and defeat have their own stings.
  - Volumes are set in the pause menu and saved to `user://settings.cfg`.
- **Sound hooks:**
  - Every ability plays a sound by type; ultimates add a swell.
  - World events cover hits, kills, explosions, pickups, hurt/down/revive and level-ups.
  - The level director plays door, clear and portal sounds, and the World the growl when the horde grows restless; the bosses play roar, wind-up, slam, spikes and fireball.
  - The level enemies: a bow, bones falling apart and rattling back up, a spore burst, a snort and a thud into a wall, a lob and its sizzle, an imp's blink.
  - The other bosses: the Tyrant's springy hops, the Serpent's splash, bubbles and bite, pods sprouting and roots bursting, the Queen's nova, beam and blizzard.
  - UI sounds on moves and confirms.
- **Fullscreen:** F11 / Alt+Enter toggles it anywhere; the pause menu also has a fullscreen switch.

## Verification

- `./tools/dev.sh test` runs the headless test suite. It compiles and loads every script and scene, then runs `tests/test_*.gd`. Any engine error fails the run.
- `./tools/dev.sh stress [--fullscreen] [--max-fps=120] [--seconds=60] [--log-slow]` runs the horde stress test. It prints frame, sim and draw timings plus entity counts, and exits non-zero when it misses the targets. Uncapped runs check avg ≤ 6 ms and p99 ≤ 8.3 ms. Capped runs check that p99 stays within 125% of the frame budget.
- Movie Maker captures (`--write-movie shots/frame.png`) are used to check rendering.
- The F3 overlay shows FPS, frame times, per-system costs and entity counts in any build.
