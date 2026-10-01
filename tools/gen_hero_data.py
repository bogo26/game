#!/usr/bin/env python3
"""Writes src/heroes/data/<id>.tres from the HEROES table below, and the
legendary forms (FORMS) to src/heroes/data/forms/<upgrade id>.tres.

Hero tuning lives here for now because hand-editing nested sub-resources in
.tres files is error-prone; the Godot inspector can edit the output too.
Run: python3 tools/gen_hero_data.py
"""
import os
import re

SCRIPTS = {
    "data": "res://src/heroes/hero_data.gd",
    "projectile": "res://src/heroes/abilities/projectile_ability.gd",
    "melee": "res://src/heroes/abilities/melee_arc.gd",
    "burst": "res://src/heroes/abilities/area_burst.gd",
    "dash": "res://src/heroes/abilities/dash_ability.gd",
    "blink": "res://src/heroes/abilities/blink_ability.gd",
    "zone": "res://src/heroes/abilities/zone_ability.gd",
    "channel": "res://src/heroes/abilities/channel_ability.gd",
    "buff": "res://src/heroes/abilities/buff_ability.gd",
    "summon": "res://src/heroes/abilities/summon_ability.gd",
    "clones": "res://src/heroes/abilities/shadow_clones.gd",
}
# The legendary forms' own scripts (src/heroes/abilities/forms/<key>.gd).
for _form in ("crescent_wave", "challenge", "juggernaut", "cluster_arrow", "decoy", "frozen_orb", "chronoshift",
              "singularity", "bastion", "judgement", "throwing_axe", "bloodbath", "rebound", "blade_vortex",
              "shadowstrike", "shadow_hunt", "tesla_grid", "haunt", "bone_golem", "lich_form"):
    SCRIPTS[_form] = "res://src/heroes/abilities/forms/%s.gd" % _form

# Enum values (must match the GDScript enums).
LOOK = {"arrow": 0, "bolt": 1, "orb": 2, "spit": 3, "knife": 4, "rivet": 5, "soul": 6, "fire": 7,
        "crescent": 25, "axe": 26, "ice_shard": 27, "flame": 28, "prism": 29, "heavy_arrow": 30, "ice_orb": 31}
EFFECT = {"none": 0, "slow": 1, "stun": 2, "burn": 3}
DASH_DIR = {"move_or_aim": 0, "aim": 1, "away_from_aim": 2}
BURST_TARGET = {"self": 0, "aim_point": 1, "screen": 2}
ZONE_TARGET = {"self": 0, "aim_point": 1}
MINION = {"skeleton": 0, "turret": 1, "tesla": 2, "mortar": 3, "golem": 4, "decoy": 5}

HEROES = {
    "knight": {
        "display_name": "Knight", "role": "Tank",
        "description": "Sturdy frontliner. Bashes through crowds and spins into the horde.",
        "max_hp": 140.0, "move_speed": 84.0, "armor": 1.0, "ult_cost": 500.0,
        "attack": ("melee", {"display_name": "Sword Slash", "description": "Wide sword arc in front of you.",
                             "cooldown": 0.42, "hold_to_repeat": True, "reach": 26.0, "arc_degrees": 120.0,
                             "damage": 12.0, "knockback": 90.0}),
        "special": ("burst", {"display_name": "Ground Slam", "description": "Stuns and knocks back everything around you.",
                              "cooldown": 6.0, "target": BURST_TARGET["self"], "radius": 48.0, "damage": 16.0,
                              "knockback": 140.0, "stun_time": 1.2, "color": (0.9, 0.8, 0.6)}),
        "movement": ("dash", {"display_name": "Shield Charge", "description": "Charge forward, bashing and stunning enemies in your path.",
                              "cooldown": 3.5, "direction": DASH_DIR["move_or_aim"], "distance": 72.0, "duration": 0.22,
                              "iframes": 0.3, "damage": 10.0, "hit_radius": 12.0, "knockback": 170.0, "stun_time": 0.6,
                              "color": (0.5, 0.7, 1.0, 0.7)}),
        "ultimate": ("channel", {"display_name": "Whirlwind", "description": "Spin for 4s: constant damage around you, half damage taken.",
                                 "cooldown": 0.5, "duration": 4.0, "radius": 34.0, "interval": 0.2, "damage": 9.0,
                                 "knockback": 60.0, "damage_taken_multiplier": 0.5, "move_speed_multiplier": 1.1}),
    },
    "ranger": {
        "display_name": "Ranger", "role": "Ranged DPS",
        "description": "Fast archer. Pierces lines of enemies and rains arrows on packs.",
        "max_hp": 90.0, "move_speed": 94.0, "armor": 0.0, "ult_cost": 700.0,
        "attack": ("projectile", {"display_name": "Piercing Arrow", "description": "Fast arrow that passes through one enemy.",
                                  "cooldown": 0.26, "hold_to_repeat": True, "damage": 9.0, "speed": 300.0, "radius": 3.0,
                                  "lifetime": 1.1, "pierce": 1, "knockback": 30.0, "look": LOOK["arrow"]}),
        "special": ("projectile", {"display_name": "Fan Volley", "description": "Five piercing arrows in a cone.",
                                   "cooldown": 4.0, "count": 5, "spread_degrees": 50.0, "damage": 8.0, "speed": 280.0,
                                   "radius": 3.0, "lifetime": 1.0, "pierce": 1, "knockback": 40.0, "look": LOOK["arrow"]}),
        "movement": ("dash", {"display_name": "Backflip", "description": "Leap away from where you aim and drop caltrops.",
                              "cooldown": 4.0, "direction": DASH_DIR["away_from_aim"], "distance": 64.0, "duration": 0.2,
                              "iframes": 0.3, "start_zone_radius": 22.0, "start_zone_duration": 4.0,
                              "start_zone_damage": 3.0, "start_zone_slow": 0.6, "color": (0.6, 1.0, 0.6, 0.6)}),
        "ultimate": ("zone", {"display_name": "Arrow Rain", "description": "Arrows pour down on the aimed area for 5s.",
                              "cooldown": 0.5, "target": ZONE_TARGET["aim_point"], "distance": 80.0, "radius": 56.0,
                              "duration": 5.0, "interval": 0.15, "damage": 7.0, "tick_visual": "arrows",
                              "color": (0.9, 0.85, 0.6)}),
    },
    "mage": {
        "display_name": "Mage", "role": "AoE control",
        "description": "Fragile caster. Freezes crowds and drops meteors on them.",
        "max_hp": 80.0, "move_speed": 86.0, "armor": 0.0, "ult_cost": 650.0,
        "attack": ("projectile", {"display_name": "Arcane Bolt", "description": "Bolt that bursts on impact.",
                                  "cooldown": 0.4, "hold_to_repeat": True, "damage": 11.0, "speed": 220.0, "radius": 4.0,
                                  "lifetime": 1.3, "splash_radius": 18.0, "knockback": 50.0, "look": LOOK["bolt"]}),
        "special": ("burst", {"display_name": "Frost Nova", "description": "Freeze and slow everything around you.",
                              "cooldown": 7.0, "target": BURST_TARGET["self"], "radius": 56.0, "damage": 8.0,
                              "knockback": 40.0, "stun_time": 1.5, "slow_time": 3.5, "color": (0.6, 0.85, 1.0)}),
        "movement": ("blink", {"display_name": "Blink", "description": "Teleport a short distance toward your aim.",
                               "cooldown": 3.0, "distance": 80.0, "iframes": 0.15}),
        "ultimate": ("burst", {"display_name": "Meteor", "description": "After 1s a meteor crushes the aimed area.",
                               "cooldown": 0.5, "target": BURST_TARGET["aim_point"], "distance": 100.0, "radius": 72.0,
                               "damage": 120.0, "knockback": 250.0, "stun_time": 0.5, "delay": 1.0,
                               "color": (1.0, 0.5, 0.2)}),
    },
    "cleric": {
        "display_name": "Cleric", "role": "Support",
        "description": "Keeps the team standing. Heals, revives, and smites the whole screen.",
        "max_hp": 110.0, "move_speed": 88.0, "armor": 0.5, "ult_cost": 550.0,
        "attack": ("projectile", {"display_name": "Holy Orb", "description": "Slow orb that pierces and bounces off walls.",
                                  "cooldown": 0.45, "hold_to_repeat": True, "damage": 8.0, "speed": 150.0, "radius": 4.0,
                                  "lifetime": 1.8, "pierce": 2, "bounces": 3, "knockback": 40.0, "look": LOOK["orb"]}),
        "special": ("zone", {"display_name": "Sanctuary", "description": "Holy ground that heals allies inside for 5s.",
                             "cooldown": 9.0, "target": ZONE_TARGET["self"], "radius": 44.0, "duration": 5.0,
                             "interval": 0.5, "heal": 4.0, "color": (1.0, 0.95, 0.5)}),
        "movement": ("dash", {"display_name": "Holy Dash", "description": "Dash that heals allies you pass (and speeds up revives).",
                              "cooldown": 4.0, "direction": DASH_DIR["move_or_aim"], "distance": 64.0, "duration": 0.2,
                              "iframes": 0.25, "heal_allies": 15.0, "color": (1.0, 0.95, 0.6, 0.7)}),
        "ultimate": ("burst", {"display_name": "Divine Light", "description": "Revive all allies, heal the team and smite every enemy on screen.",
                               "cooldown": 0.5, "target": BURST_TARGET["screen"], "damage": 40.0, "knockback": 120.0,
                               "heal_fraction": 0.4, "revive_allies": True, "color": (1.0, 0.95, 0.7)}),
    },
    "berserker": {
        "display_name": "Berserker", "role": "Bruiser",
        "description": "Reckless axe-wielder. Heals by hurting, leaps into packs and goes on a rampage.",
        "max_hp": 130.0, "move_speed": 90.0, "armor": 0.5, "ult_cost": 550.0,
        "attack": ("melee", {"display_name": "Axe Cleave", "description": "Heavy cleave; every third swing hits twice as hard.",
                             "cooldown": 0.48, "hold_to_repeat": True, "reach": 24.0, "arc_degrees": 110.0,
                             "damage": 13.0, "knockback": 80.0, "combo_every": 3, "combo_multiplier": 2.2,
                             "color": (1.0, 0.75, 0.6, 0.9)}),
        "special": ("buff", {"display_name": "Blood Frenzy", "description": "Pay 10% HP: +60% attack speed and 15% lifesteal for 5s.",
                             "cooldown": 10.0, "duration": 5.0, "hp_cost": 0.1, "attack_speed_multiplier": 1.6,
                             "lifesteal_fraction": 0.15, "color": (1.0, 0.25, 0.25)}),
        "movement": ("dash", {"display_name": "Leap Slam", "description": "Leap toward your aim and slam down, stunning enemies.",
                              "cooldown": 4.5, "direction": DASH_DIR["aim"], "distance": 80.0, "duration": 0.34,
                              "iframes": 0.4, "arc_height": 14.0, "landing_damage": 20.0, "landing_radius": 36.0,
                              "landing_stun": 0.4, "color": (1.0, 0.55, 0.3, 0.7)}),
        "ultimate": ("buff", {"display_name": "Rampage", "description": "10s: grow huge, +50% damage, bigger cleaves, heal on kill.",
                              "cooldown": 0.5, "duration": 10.0, "damage_multiplier": 1.5, "area_multiplier": 1.4,
                              "damage_taken_multiplier": 0.7, "move_speed_multiplier": 1.1, "heal_per_kill": 4.0,
                              "scale": 1.5, "color": (1.0, 0.45, 0.2)}),
    },
    "rogue": {
        "display_name": "Rogue", "role": "Crit assassin",
        "description": "Fast and fragile. Marks enemies for critical hits and fights with shadow clones.",
        "max_hp": 85.0, "move_speed": 100.0, "armor": 0.0, "ult_cost": 600.0, "crit_chance": 0.15,
        "attack": ("melee", {"display_name": "Twin Daggers", "description": "Very fast short-range stabs.",
                             "cooldown": 0.2, "hold_to_repeat": True, "reach": 20.0, "arc_degrees": 70.0,
                             "damage": 7.0, "knockback": 20.0, "color": (0.85, 0.85, 1.0, 0.9)}),
        "special": ("projectile", {"display_name": "Knife Ring", "description": "Throw 12 knives in every direction.",
                                   "cooldown": 5.0, "count": 12, "spread_degrees": 360.0, "damage": 9.0, "speed": 260.0,
                                   "radius": 3.0, "lifetime": 0.6, "pierce": 1, "knockback": 30.0, "look": LOOK["knife"]}),
        "movement": ("dash", {"display_name": "Shadow Step", "description": "Dash through enemies, marking them: marked enemies take x1.75 damage.",
                              "cooldown": 3.0, "direction": DASH_DIR["move_or_aim"], "distance": 72.0, "duration": 0.16,
                              "iframes": 0.25, "damage": 6.0, "hit_radius": 12.0, "mark_time": 3.0,
                              "color": (0.5, 0.3, 0.8, 0.7)}),
        "ultimate": ("clones", {"display_name": "Shadow Clones", "description": "3 shadow clones copy your attacks for 6s.",
                                "cooldown": 0.5, "duration": 6.0, "clone_count": 3, "damage": 7.0, "reach": 22.0,
                                "arc_degrees": 80.0}),
    },
    "engineer": {
        "display_name": "Engineer", "role": "Turrets",
        "description": "Builds turrets and a tesla tower, and rockets around leaving fire.",
        "max_hp": 100.0, "move_speed": 88.0, "armor": 0.5, "ult_cost": 650.0,
        "attack": ("projectile", {"display_name": "Rivet Gun", "description": "Rapid-fire rivets.",
                                  "cooldown": 0.14, "hold_to_repeat": True, "damage": 6.0, "speed": 320.0, "radius": 3.0,
                                  "lifetime": 0.9, "knockback": 20.0, "look": LOOK["rivet"]}),
        "special": ("summon", {"display_name": "Deploy Turret", "description": "Place a turret that shoots nearby enemies (max 2).",
                               "cooldown": 6.0, "kind": MINION["turret"], "count": 1, "max_active": 2, "lifetime": 20.0,
                               "minion_damage": 5.0, "attack_interval": 0.3, "attack_range": 140.0}),
        "movement": ("dash", {"display_name": "Rocket Boots", "description": "Rocket dash that leaves a burning trail.",
                              "cooldown": 3.5, "direction": DASH_DIR["move_or_aim"], "distance": 76.0, "duration": 0.18,
                              "iframes": 0.25, "trail_damage": 4.0, "color": (1.0, 0.6, 0.2, 0.7)}),
        "ultimate": ("summon", {"display_name": "Tesla Tower", "description": "8s tower: chain lightning through nearby enemies.",
                                "cooldown": 0.5, "kind": MINION["tesla"], "count": 1, "max_active": 1, "lifetime": 8.0,
                                "minion_damage": 14.0, "attack_interval": 0.35, "attack_range": 150.0}),
    },
    "necromancer": {
        "display_name": "Necromancer", "role": "Summoner",
        "description": "Raises the fallen to fight for the team and walks through the horde as a wraith.",
        "max_hp": 90.0, "move_speed": 86.0, "armor": 0.0, "ult_cost": 650.0,
        "attack": ("projectile", {"display_name": "Soul Bolt", "description": "Piercing bolt of soul fire.",
                                  "cooldown": 0.35, "hold_to_repeat": True, "damage": 9.0, "speed": 200.0, "radius": 4.0,
                                  "lifetime": 1.2, "pierce": 1, "knockback": 30.0, "look": LOOK["soul"]}),
        "special": ("summon", {"display_name": "Raise Dead", "description": "Raise 4 skeletons from fresh corpses (max 8).",
                               "cooldown": 7.0, "kind": MINION["skeleton"], "count": 4, "max_active": 8, "lifetime": 20.0,
                               "use_corpses": True, "corpse_radius": 140.0, "minion_hp": 30.0, "minion_damage": 8.0,
                               "attack_interval": 0.6, "attack_range": 140.0}),
        "movement": ("dash", {"display_name": "Wraith Walk", "description": "Drift through the horde untouchable, chilling everything you pass.",
                              "cooldown": 4.0, "direction": DASH_DIR["move_or_aim"], "distance": 90.0, "duration": 0.45,
                              "iframes": 0.6, "slow_time": 2.0, "hit_radius": 12.0, "color": (0.35, 0.95, 0.8, 0.6)}),
        "ultimate": ("summon", {"display_name": "Army of the Dead", "description": "Summon 16 skeletons for 10s.",
                                "cooldown": 0.5, "kind": MINION["skeleton"], "count": 16, "max_active": 16, "lifetime": 10.0,
                                "spawn_radius": 30.0, "minion_hp": 25.0, "minion_damage": 7.0, "attack_interval": 0.6,
                                "attack_range": 140.0}),
    },
}

# Legendary forms (the mini boss's reward, see tools/gen_upgrades.py): each
# replaces one of a hero's abilities. A form's props are that ability's own
# merged with the overrides here, so its script must be the ability's script
# or a subclass of it (the upgrades the hero took keep their meaning).
# {upgrade id: (hero, slot, script key, overrides)}
FORMS = {
    # --- knight -------------------------------------------------------------------------------
    "knight_crescent_wave": ("knight", "attack", "crescent_wave", {
        "display_name": "Crescent Wave",
        "description": "Sword arc; every 3rd swing also sends a crescent of light through a whole line.",
        "combo_every": 3, "combo_multiplier": 1.5,
        "wave_speed": 230.0, "wave_lifetime": 0.55, "wave_radius": 7.0, "wave_knockback": 70.0}),
    "knight_challenge": ("knight", "special", "challenge", {
        "display_name": "Challenge",
        "description": "Drag every enemy near you to your feet and stun it. Take less damage for each one caught.",
        "radius": 80.0, "damage": 10.0, "knockback": 0.0, "stun_time": 1.2, "color": (1.0, 0.85, 0.4),
        "pull_to": 12.0, "guard_per_enemy": 0.04, "max_guard": 0.4, "guard_time": 5.0}),
    "knight_juggernaut": ("knight", "movement", "juggernaut", {
        "display_name": "Juggernaut",
        "description": "Charge, carrying everything in your path, then slam it all down in a shockwave.",
        "knockback": 0.0, "stun_time": 0.0, "hit_radius": 14.0,
        "max_carried": 10, "carry_offset": 12.0, "crash_radius": 34.0, "crash_damage": 14.0,
        "crash_per_enemy": 3.0, "crash_stun": 0.6, "crash_knockback": 180.0, "wall_bonus": 1.5, "wall_stun": 0.5}),
    # --- ranger -------------------------------------------------------------------------------
    "ranger_ricochet": ("ranger", "attack", "projectile", {
        "display_name": "Ricochet",
        "description": "Arrows glance off each enemy they hit toward the next one nearby, up to 3 times.",
        "pierce": 3, "ricochet": True}),
    "ranger_cluster_arrow": ("ranger", "special", "cluster_arrow", {
        "display_name": "Cluster Arrow",
        "description": "A heavy arrow that bursts into a ring of 12 arrows where it lands.",
        "count": 12, "speed": 270.0, "lifetime": 0.45,
        "heavy_damage": 20.0, "heavy_speed": 240.0, "heavy_lifetime": 0.6, "heavy_radius": 5.0,
        "heavy_knockback": 60.0}),
    "ranger_decoy": ("ranger", "movement", "decoy", {
        "display_name": "Decoy",
        "description": "Backflip, leaving a decoy the horde goes after. It bursts into caltrops.",
        "start_zone_radius": 0.0, "decoy_hp": 60.0, "decoy_time": 3.0, "caltrop_radius": 34.0}),
    # --- mage ---------------------------------------------------------------------------------
    "mage_frozen_orb": ("mage", "special", "frozen_orb", {
        "display_name": "Frozen Orb",
        "description": "Hurl an orb of ice that sprays slowing shards, then bursts into a Frost Nova.",
        "orb_speed": 90.0, "orb_time": 1.4, "shard_interval": 0.07, "shard_turn": 40.0, "shard_damage": 4.0,
        "shard_speed": 170.0, "shard_lifetime": 0.4, "shard_slow": 1.5}),
    "mage_chronoshift": ("mage", "movement", "chronoshift", {
        "display_name": "Chronoshift",
        "description": "Blink, leaving an echo. 2.5s later you snap back to it and undo half the damage taken.",
        "echo_time": 2.5, "undo_share": 0.5, "return_iframes": 0.3}),
    "mage_singularity": ("mage", "ultimate", "singularity", {
        "display_name": "Singularity",
        "description": "A black hole for 3s drags enemies in and grinds them, then collapses in a huge blast.",
        "color": (0.62, 0.35, 1.0), "hole_time": 3.0, "pull_radius": 110.0, "pull_speed": 100.0, "swirl": 0.6,
        "core_radius": 28.0, "grind_damage": 6.0, "grind_interval": 0.25}),
    # --- cleric -------------------------------------------------------------------------------
    "cleric_prism_orbs": ("cleric", "attack", "projectile", {
        "display_name": "Prism Orb",
        "description": "Orb that bounces off walls, splitting in three at a bounce (twice).",
        "look": LOOK["prism"], "splits": 2}),
    "cleric_bastion": ("cleric", "special", "bastion", {
        "display_name": "Bastion",
        "description": "A dome of light for 5s: enemy shots fizzle, enemies are pushed out, allies inside heal.",
        "push_speed": 160.0}),
    "cleric_judgement": ("cleric", "ultimate", "judgement", {
        "display_name": "Judgement",
        "description": "Revive and heal the team, then 12 pillars of light strike the toughest enemies on screen.",
        "pillars": 12, "pillar_interval": 0.12, "pillar_damage": 90.0, "pillar_radius": 22.0, "pillar_stun": 0.6,
        "pillar_knockback": 60.0}),
    # --- berserker ----------------------------------------------------------------------------
    "berserker_throwing_axe": ("berserker", "attack", "throwing_axe", {
        "display_name": "Throwing Axe",
        "description": "Heavy cleave; every third swing hurls the axe out and back, hitting both ways.",
        "throw_reach": 110.0, "throw_speed": 230.0, "return_speed": 260.0, "throw_radius": 6.0}),
    "berserker_bloodbath": ("berserker", "special", "bloodbath", {
        "display_name": "Bloodbath",
        "description": "Pay 10% HP: frenzy for 5s. Every kill bursts in blood that hurts enemies and heals you.",
        "burst_radius": 28.0, "burst_damage": 12.0, "burst_heal": 2.0, "burst_knockback": 60.0}),
    "berserker_rebound": ("berserker", "movement", "rebound", {
        "display_name": "Rebound",
        "description": "Leap and slam, then bounce onto the nearest enemy: 3 slams, each bigger.",
        "hops": 3, "hop_range": 110.0, "hop_distance": 90.0, "hop_duration": 0.28, "area_growth": 1.2,
        "power_growth": 1.25, "min_hop": 24.0}),
    # --- rogue --------------------------------------------------------------------------------
    "rogue_blade_vortex": ("rogue", "special", "blade_vortex", {
        "display_name": "Blade Vortex",
        "description": "12 knives whirl around you for 3s, cutting whatever comes close, then fly outward.",
        "whirl_time": 3.0, "orbit_radius": 26.0, "orbit_speed": 7.0, "whirl_share": 0.6, "rehit": 0.4}),
    "rogue_shadowstrike": ("rogue", "movement", "shadowstrike", {
        "display_name": "Shadowstrike",
        "description": "Appear behind the enemy nearest your aim and stab it: a sure crit. Marks those around it.",
        "strike_range": 110.0, "strike_damage": 24.0, "mark_radius": 30.0, "behind": 9.0}),
    "rogue_shadow_hunt": ("rogue", "ultimate", "shadow_hunt", {
        "display_name": "Shadow Hunt",
        "description": "3 clones hunt on their own for 6s, blinking from enemy to enemy to stab and mark them.",
        "hunt_range": 140.0, "hop_interval": 0.35, "hunt_mark": 2.0}),
    # --- engineer -----------------------------------------------------------------------------
    "engineer_flamethrower": ("engineer", "attack", "projectile", {
        "display_name": "Flamethrower",
        "description": "A roaring gout of fire through the whole pack. Burning enemies set those they touch alight.",
        "cooldown": 0.14, "count": 2, "spread_degrees": 0.0, "jitter_deg": 15.0, "speed": 200.0,
        "speed_jitter": 0.2, "lifetime": 0.5, "radius": 6.0, "pierce": 99, "damage": 5.0, "knockback": 5.0,
        "look": LOOK["flame"], "effect": EFFECT["burn"], "effect_time": 3.0, "area_reach": True}),
    "engineer_mortar": ("engineer", "special", "summon", {
        "display_name": "Deploy Mortar",
        "description": "Place a mortar that lobs shells at the biggest pack in range (max 2).",
        "kind": MINION["mortar"], "minion_damage": 14.0, "attack_interval": 1.4, "attack_range": 220.0}),
    "engineer_tesla_grid": ("engineer", "ultimate", "tesla_grid", {
        "display_name": "Tesla Grid",
        "description": "8s tower: lightning links it to you and your turrets, shocking whatever crosses them.",
        "link_range": 200.0, "link_width": 6.0, "link_damage": 10.0, "link_interval": 0.2, "link_stun": 0.25}),
    # --- necromancer --------------------------------------------------------------------------
    "necro_haunt": ("necromancer", "attack", "haunt", {
        "display_name": "Haunt",
        "description": "Soul bolts. Enemies they kill rise as wisps that seek another enemy and burst on it.",
        "reap": True, "wisp_share": 0.7, "wisp_speed": 120.0, "wisp_turn": 6.0, "wisp_range": 140.0,
        "wisp_life": 2.0, "wisp_burst": 16.0, "max_wisps": 10}),
    "necro_bone_golem": ("necromancer", "special", "bone_golem", {
        "display_name": "Bone Golem",
        "description": "Fuse fresh corpses into a golem the horde goes after. Cast again to feed it.",
        "kind": MINION["golem"], "max_active": 1, "use_corpses": False, "minion_damage": 14.0,
        "attack_interval": 1.1, "golem_hp": 80.0, "hp_per_corpse": 20.0, "corpses": 6}),
    "necro_lich_form": ("necromancer", "ultimate", "lich_form", {
        "display_name": "Lich Form",
        "description": "Become a Lich for 10s: bolts fire in threes and enemies you kill rise as skeletons.",
        "duration": 10.0, "lich_scale": 1.3, "lich_damage_taken": 0.75, "extra_bolts": 2}),
}

ROOT = os.path.join(os.path.dirname(__file__), "..")


def class_name_of(script_path):
    """The class_name a res:// script declares."""
    with open(os.path.join(ROOT, script_path[len("res://"):])) as f:
        match = re.search(r"^class_name (\w+)", f.read(), re.M)
    assert match, "%s has no class_name" % script_path
    return match.group(1)


def fmt(value):
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, float):
        return repr(value)
    if isinstance(value, int):
        return str(value)
    if isinstance(value, tuple):
        rgba = list(value) + [1.0] * (4 - len(value))
        return "Color(%s)" % ", ".join(repr(float(c)) for c in rgba)
    if isinstance(value, str):
        return '"%s"' % value.replace('"', '\\"')
    raise TypeError(value)


def write_hero(hero_id, hero):
    ext = {"data": "1_data"}
    subs = []
    for slot in ("attack", "special", "movement", "ultimate"):
        kind, props = hero[slot]
        if kind not in ext:
            ext[kind] = "%d_%s" % (len(ext) + 1, kind)
        lines = ['[sub_resource type="Resource" id="Resource_%s"]' % slot,
                 'script = ExtResource("%s")' % ext[kind]]
        lines += ["%s = %s" % (k, fmt(v)) for k, v in props.items()]
        subs.append("\n".join(lines))
    out = ['[gd_resource type="Resource" script_class="HeroData" load_steps=%d format=3]' % (len(ext) + len(subs) + 1), ""]
    for kind, rid in ext.items():
        out.append('[ext_resource type="Script" path="%s" id="%s"]' % (SCRIPTS[kind], rid))
    out.append("")
    out.append("\n\n".join(subs))
    out.append("")
    out.append("[resource]")
    out.append('script = ExtResource("1_data")')
    out.append('id = &"%s"' % hero_id)
    for key in ("display_name", "role", "description", "max_hp", "move_speed", "armor", "crit_chance", "ult_cost"):
        if key in hero:
            out.append("%s = %s" % (key, fmt(hero[key])))
    for slot in ("attack", "special", "movement", "ultimate"):
        out.append('%s = SubResource("Resource_%s")' % (slot, slot))
    path = os.path.join(os.path.dirname(__file__), "..", "src", "heroes", "data", hero_id + ".tres")
    with open(path, "w") as f:
        f.write("\n".join(out) + "\n")


def write_form(form_id, form):
    hero_id, slot, kind, overrides = form
    props = dict(HEROES[hero_id][slot][1])
    props.update(overrides)
    script = SCRIPTS[kind]
    out = ['[gd_resource type="Resource" script_class="%s" load_steps=2 format=3]' % class_name_of(script), ""]
    out.append('[ext_resource type="Script" path="%s" id="1_form"]' % script)
    out.append("")
    out.append("[resource]")
    out.append('script = ExtResource("1_form")')
    out += ["%s = %s" % (k, fmt(v)) for k, v in props.items()]
    path = os.path.join(ROOT, "src", "heroes", "data", "forms", form_id + ".tres")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as f:
        f.write("\n".join(out) + "\n")


if __name__ == "__main__":
    for hero_id, hero in HEROES.items():
        write_hero(hero_id, hero)
    for form_id, form in FORMS.items():
        write_form(form_id, form)
    print("wrote %d heroes and %d legendary forms" % (len(HEROES), len(FORMS)))
