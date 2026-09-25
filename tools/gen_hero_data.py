#!/usr/bin/env python3
"""Writes src/heroes/data/<id>.tres from the HEROES table below.

Hero tuning lives here for now because hand-editing nested sub-resources in
.tres files is error-prone; the Godot inspector can edit the output too.
Run: python3 tools/gen_hero_data.py
"""
import os

SCRIPTS = {
    "data": "res://src/heroes/hero_data.gd",
    "projectile": "res://src/heroes/abilities/projectile_ability.gd",
    "melee": "res://src/heroes/abilities/melee_arc.gd",
    "burst": "res://src/heroes/abilities/area_burst.gd",
    "dash": "res://src/heroes/abilities/dash_ability.gd",
    "blink": "res://src/heroes/abilities/blink_ability.gd",
    "zone": "res://src/heroes/abilities/zone_ability.gd",
    "channel": "res://src/heroes/abilities/channel_ability.gd",
}

# Enum values (must match the GDScript enums).
LOOK = {"arrow": 0, "bolt": 1, "orb": 2, "spit": 3, "knife": 4, "rivet": 5, "soul": 6, "fire": 7}
DASH_DIR = {"move_or_aim": 0, "aim": 1, "away_from_aim": 2}
BURST_TARGET = {"self": 0, "aim_point": 1, "screen": 2}
ZONE_TARGET = {"self": 0, "aim_point": 1}

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
}


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
    for key in ("display_name", "role", "description", "max_hp", "move_speed", "armor", "ult_cost"):
        out.append("%s = %s" % (key, fmt(hero[key])))
    for slot in ("attack", "special", "movement", "ultimate"):
        out.append('%s = SubResource("Resource_%s")' % (slot, slot))
    path = os.path.join(os.path.dirname(__file__), "..", "src", "heroes", "data", hero_id + ".tres")
    with open(path, "w") as f:
        f.write("\n".join(out) + "\n")


if __name__ == "__main__":
    for hero_id, hero in HEROES.items():
        write_hero(hero_id, hero)
    print("wrote %d heroes" % len(HEROES))
