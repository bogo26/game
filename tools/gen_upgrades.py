#!/usr/bin/env python3
"""Writes src/upgrades/data/upgrade_library.tres from the UPGRADES table.

Effect syntax (see src/upgrades/upgrade_data.gd):
  "stat <name> flat|pct <amount>"      stats: max_hp armor move_speed damage attack_speed
                                        crit_chance crit_damage pickup_range regen ult_charge
                                        life_on_kill revive_speed
  "ability <slot|all> <mod> <amount>"  slots: attack special movement ultimate all
Run: python3 tools/gen_upgrades.py
"""
import os

COMMON, RARE, EPIC = 0, 1, 2

# (id, name, description, rarity, max_stacks, hero_id, [effects])
UPGRADES = [
    # --- generic -------------------------------------------------------------------------
    ("sharpened", "Sharpened", "+10% damage", COMMON, 5, "", ["stat damage pct 0.10"]),
    ("quick_hands", "Quick Hands", "+12% attack speed", COMMON, 5, "", ["stat attack_speed pct 0.12"]),
    ("swift_boots", "Swift Boots", "+8% move speed", COMMON, 3, "", ["stat move_speed pct 0.08"]),
    ("vitality", "Vitality", "+20 max HP", COMMON, 5, "", ["stat max_hp flat 20"]),
    ("iron_skin", "Iron Skin", "+1 armor: every hit you take is 1 lower", RARE, 3, "", ["stat armor flat 1"]),
    ("keen_eye", "Keen Eye", "+6% critical hit chance", COMMON, 5, "", ["stat crit_chance flat 0.06"]),
    ("brutal", "Brutal Crits", "Critical hits deal +35% more", RARE, 3, "", ["stat crit_damage flat 0.35"]),
    ("magnet", "Magnet", "+35% XP pickup range", COMMON, 3, "", ["stat pickup_range pct 0.35"]),
    ("recharge", "Recharge", "Ultimate charges 25% faster", RARE, 3, "", ["stat ult_charge pct 0.25"]),
    ("regeneration", "Regeneration", "Regenerate 0.8 HP per second", RARE, 3, "", ["stat regen flat 0.8"]),
    ("focus", "Focus", "-8% cooldown on all abilities", RARE, 3, "", ["ability all cooldown_pct -0.08"]),
    ("nimble", "Nimble", "-15% movement ability cooldown", COMMON, 3, "", ["ability movement cooldown_pct -0.15"]),
    ("amplify", "Amplify", "+12% area on all abilities", RARE, 3, "", ["ability all area_pct 0.12"]),
    ("bloodthirst", "Bloodthirst", "Heal 1 HP per kill", RARE, 3, "", ["stat life_on_kill flat 1"]),
    ("guardian_angel", "Guardian Angel", "Revive teammates 50% faster, +10 max HP", COMMON, 2, "",
     ["stat revive_speed pct 0.5", "stat max_hp flat 10"]),
    ("glass_cannon", "Glass Cannon", "+30% damage, -15% max HP", EPIC, 1, "",
     ["stat damage pct 0.30", "stat max_hp pct -0.15"]),
    ("overcharge", "Overcharge", "Ultimate: +40% damage, +15% area", EPIC, 2, "",
     ["ability ultimate damage_pct 0.4", "ability ultimate area_pct 0.15"]),
    # --- knight -----------------------------------------------------------------------------
    ("knight_wide_slash", "Wide Slash", "Sword Slash: wider arc, +12% reach", COMMON, 3, "knight",
     ["ability attack arc_deg 30", "ability attack area_pct 0.12"]),
    ("knight_aftershock", "Aftershock", "Ground Slam: +0.4s stun, +20% area", RARE, 3, "knight",
     ["ability special stun_time 0.4", "ability special area_pct 0.2"]),
    ("knight_shockwave", "Shockwave Charge", "Shield Charge ends in a shockwave", RARE, 2, "knight",
     ["ability movement end_burst 18"]),
    ("knight_endless_spin", "Endless Spin", "Whirlwind lasts 1.5s longer", RARE, 2, "knight",
     ["ability ultimate duration 1.5"]),
    # --- ranger -----------------------------------------------------------------------------
    ("ranger_twin_arrows", "Twin Arrows", "Piercing Arrow: +1 arrow", RARE, 3, "ranger",
     ["ability attack count 1", "ability attack spread_deg 8"]),
    ("ranger_piercing", "Piercing Shots", "Arrows pierce 1 more enemy", COMMON, 3, "ranger",
     ["ability attack pierce 1", "ability special pierce 1"]),
    ("ranger_wide_volley", "Wide Volley", "Fan Volley: +2 arrows", COMMON, 3, "ranger",
     ["ability special count 2", "ability special spread_deg 10"]),
    ("ranger_deluge", "Deluge", "Arrow Rain: +2s, +20% area", RARE, 2, "ranger",
     ["ability ultimate duration 2", "ability ultimate area_pct 0.2"]),
    # --- mage -------------------------------------------------------------------------------
    ("mage_bigger_bursts", "Bigger Bursts", "Arcane Bolt: +30% burst area", COMMON, 3, "mage",
     ["ability attack area_pct 0.3"]),
    ("mage_twin_bolts", "Twin Bolts", "Arcane Bolt: +1 bolt", RARE, 2, "mage",
     ["ability attack count 1", "ability attack spread_deg 12"]),
    ("mage_deep_freeze", "Deep Freeze", "Frost Nova: +0.6s freeze, +15% area", RARE, 3, "mage",
     ["ability special stun_time 0.6", "ability special area_pct 0.15"]),
    ("mage_blink_nova", "Blink Nova", "Blink blasts enemies where you land", RARE, 2, "mage",
     ["ability movement arrival_damage 16"]),
    # --- cleric -----------------------------------------------------------------------------
    ("cleric_radiant", "Radiant Sanctuary", "Sanctuary also burns enemies", RARE, 2, "cleric",
     ["ability special zone_damage 6"]),
    ("cleric_blessed_orbs", "Blessed Orbs", "Holy Orb: +1 bounce, +1 pierce", COMMON, 3, "cleric",
     ["ability attack bounces 1", "ability attack pierce 1"]),
    ("cleric_swift_grace", "Swift Grace", "Holy Dash: -20% cooldown, heals 8 more", COMMON, 3, "cleric",
     ["ability movement cooldown_pct -0.2", "ability movement heal_allies 8"]),
    ("cleric_mending", "Mending", "Sanctuary heals 30% more", COMMON, 3, "cleric",
     ["ability special heal_pct 0.3"]),
    ("cleric_wrath", "Wrath of Heaven", "Divine Light: +50% damage", RARE, 2, "cleric",
     ["ability ultimate damage_pct 0.5"]),
]


def q(s):
    return '"%s"' % s.replace("\\", "\\\\").replace('"', '\\"')


def main():
    out = ['[gd_resource type="Resource" script_class="UpgradeLibrary" load_steps=%d format=3]' % (len(UPGRADES) + 3), ""]
    out.append('[ext_resource type="Script" path="res://src/upgrades/upgrade_library.gd" id="1_library"]')
    out.append('[ext_resource type="Script" path="res://src/upgrades/upgrade_data.gd" id="2_upgrade"]')
    out.append("")
    ids = set()
    for (uid, name, desc, rarity, stacks, hero, effects) in UPGRADES:
        assert uid not in ids, uid
        ids.add(uid)
        out.append('[sub_resource type="Resource" id="Resource_%s"]' % uid)
        out.append('script = ExtResource("2_upgrade")')
        out.append('id = &"%s"' % uid)
        out.append("display_name = %s" % q(name))
        out.append("description = %s" % q(desc))
        out.append("rarity = %d" % rarity)
        out.append("max_stacks = %d" % stacks)
        out.append('hero_id = &"%s"' % hero)
        out.append("effects = PackedStringArray(%s)" % ", ".join(q(e) for e in effects))
        out.append("")
    out.append("[resource]")
    out.append('script = ExtResource("1_library")')
    refs = ", ".join('SubResource("Resource_%s")' % u[0] for u in UPGRADES)
    out.append('upgrades = Array[ExtResource("2_upgrade")]([%s])' % refs)
    path = os.path.join(os.path.dirname(__file__), "..", "src", "upgrades", "data", "upgrade_library.tres")
    with open(path, "w") as f:
        f.write("\n".join(out) + "\n")
    print("wrote %d upgrades" % len(UPGRADES))


if __name__ == "__main__":
    main()
