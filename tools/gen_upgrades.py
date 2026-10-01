#!/usr/bin/env python3
"""Writes src/upgrades/data/upgrade_library.tres from the UPGRADES table.

Effect syntax (see src/upgrades/upgrade_data.gd):
  "stat <name> flat|pct <amount>"      stats: max_hp armor move_speed damage attack_speed
                                        crit_chance crit_damage pickup_range regen ult_charge
                                        life_on_kill revive_speed
  "ability <slot|all> <mod> <amount>"  slots: attack special movement ultimate all
Legendaries (LEGENDARIES, the mini boss's reward) have no effect lines: each
turns one ability into its form from tools/gen_hero_data.py (FORMS).
Run: python3 tools/gen_upgrades.py
"""
import os

from gen_hero_data import FORMS

COMMON, RARE, EPIC, LEGENDARY = 0, 1, 2, 3
SLOTS = {"attack": 0, "special": 1, "movement": 2, "ultimate": 3}

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
    # --- berserker ----------------------------------------------------------------------------
    ("berserker_cleaver", "Cleaver", "Axe Cleave: +10% damage, +15% reach", COMMON, 3, "berserker",
     ["ability attack damage_pct 0.1", "ability attack area_pct 0.15"]),
    ("berserker_bloodlust", "Bloodlust", "Blood Frenzy: +5% lifesteal, +1s", RARE, 3, "berserker",
     ["ability special lifesteal 0.05", "ability special duration 1"]),
    ("berserker_earthshaker", "Earthshaker", "Leap Slam: +0.3s stun, +25% area", RARE, 2, "berserker",
     ["ability movement stun_time 0.3", "ability movement area_pct 0.25"]),
    ("berserker_unstoppable", "Unstoppable", "Rampage lasts 3s longer", RARE, 2, "berserker",
     ["ability ultimate duration 3"]),
    # --- rogue --------------------------------------------------------------------------------
    ("rogue_precision", "Deadly Precision", "+8% critical hit chance", COMMON, 3, "rogue",
     ["stat crit_chance flat 0.08"]),
    ("rogue_fan", "Fan of Knives", "Knife Ring: +6 knives", COMMON, 3, "rogue",
     ["ability special count 6"]),
    ("rogue_shadow_dance", "Shadow Dance", "Shadow Step: -20% cooldown, +25% distance", RARE, 2, "rogue",
     ["ability movement cooldown_pct -0.2", "ability movement distance_pct 0.25"]),
    ("rogue_legion", "Legion of Shadows", "Shadow Clones: +2 clones", RARE, 2, "rogue",
     ["ability ultimate count 2"]),
    # --- engineer -----------------------------------------------------------------------------
    ("engineer_overclock", "Overclocked Turrets", "Turrets deal 30% more damage", COMMON, 3, "engineer",
     ["ability special damage_pct 0.3"]),
    ("engineer_extra_turret", "Extra Turret", "Deploy Turret: +1 turret", RARE, 2, "engineer",
     ["ability special max_active 1"]),
    ("engineer_afterburner", "Afterburner", "Rocket Boots: -20% cooldown, +20% distance", COMMON, 3, "engineer",
     ["ability movement cooldown_pct -0.2", "ability movement distance_pct 0.2"]),
    ("engineer_supercoil", "Supercoil", "Tesla Tower lasts 4s longer, +20% range", RARE, 2, "engineer",
     ["ability ultimate duration 4", "ability ultimate area_pct 0.2"]),
    # --- necromancer --------------------------------------------------------------------------
    ("necro_bone_horde", "Bone Horde", "Raise Dead: +2 skeletons, max +4", COMMON, 3, "necromancer",
     ["ability special count 2", "ability special max_active 4"]),
    ("necro_sturdy_bones", "Sturdy Bones", "Skeletons have 50% more HP", COMMON, 3, "necromancer",
     ["ability special minion_hp_pct 0.5", "ability ultimate minion_hp_pct 0.5"]),
    ("necro_soul_rend", "Soul Rend", "Soul Bolt: +1 pierce, +10% damage", COMMON, 3, "necromancer",
     ["ability attack pierce 1", "ability attack damage_pct 0.1"]),
    ("necro_endless_legion", "Endless Legion", "Army of the Dead: +6 skeletons", RARE, 2, "necromancer",
     ["ability ultimate count 6", "ability ultimate max_active 6"]),
]

# Elemental chains: three tiers each; every tier needs the one before it and
# the last is the big one. (id, name, description, element, tier, effects)
ELEMENTS = [
    ("fire_1", "Ember Strikes", "Attacks set enemies on fire: 50% of the hit per second for 3s",
     "fire", 1, ["ability attack fire 1"]),
    ("fire_2", "Wildfire", "Burns are 60% hotter and last 4s. Fire spreads to enemies they touch",
     "fire", 2, ["ability attack fire 1"]),
    ("fire_3", "Inferno", "Burning enemies explode when they die, setting everything nearby ablaze",
     "fire", 3, ["ability attack fire 1"]),
    ("ice_1", "Frostbite", "Attacks chill enemies: 40% slower for 2.5s",
     "ice", 1, ["ability attack ice 1"]),
    ("ice_2", "Permafrost", "Every 3rd hit on a chilled enemy freezes it solid for 1.5s",
     "ice", 2, ["ability attack ice 1"]),
    ("ice_3", "Shatter", "Frozen enemies take double damage and shatter when they die, freezing others",
     "ice", 3, ["ability attack ice 1"]),
    ("poison_1", "Venom", "Attacks poison: 25% of the hit per second for 4s, and slows. Stacks 4 times",
     "poison", 1, ["ability attack poison 1"]),
    ("poison_2", "Virulence", "Poison stacks up to 8 times and lasts 6s",
     "poison", 2, ["ability attack poison 1"]),
    ("poison_3", "Plague", "Poisoned enemies burst into toxic clouds that poison everything inside",
     "poison", 3, ["ability attack poison 1"]),
    ("lightning_1", "Static Charge", "Hits stagger enemies and zap the nearest one for 50% damage",
     "lightning", 1, ["ability attack lightning 1"]),
    ("lightning_2", "Arc Lightning", "Zaps chain through 3 enemies for 60% damage and stun them",
     "lightning", 2, ["ability attack lightning 1"]),
    ("lightning_3", "Thunderstrike", "Every 5th hit calls down a thunderbolt: triple damage, stun, chains 6",
     "lightning", 3, ["ability attack lightning 1"]),
]
# Tier -> (rarity, weight bonus): once a chain is started its next tier shows
# up about as often as a common card.
ELEMENT_TIERS = {1: (RARE, 1.0), 2: (RARE, 2.5), 3: (EPIC, 8.0)}


# The mini boss's reward: 3 per hero, each on a different ability; a player
# picks one of their hero's three. (id, name, card text)
# With four players a card holds about this much text.
CARD_TEXT_MAX = 88
LEGENDARIES = [
    ("knight_crescent_wave", "Crescent Wave",
     "Sword Slash: every 3rd swing also sends a crescent of light through a whole line"),
    ("knight_challenge", "Challenge",
     "Ground Slam: drag nearby enemies to your feet and stun them. -4% damage taken per enemy"),
    ("knight_juggernaut", "Juggernaut",
     "Shield Charge: carry everything in your path, then slam it all down (harder into walls)"),
    ("ranger_ricochet", "Ricochet",
     "Piercing Arrow: arrows glance off each enemy they hit to the next one, 3 times"),
    ("ranger_cluster_arrow", "Cluster Arrow",
     "Fan Volley: one heavy arrow that bursts into a ring of 12 arrows where it lands"),
    ("ranger_decoy", "Decoy",
     "Backflip: leave a straw decoy the horde goes after for 3s. It bursts into caltrops"),
    ("mage_frozen_orb", "Frozen Orb",
     "Frost Nova: hurl an ice orb that sprays slowing shards, then bursts into a Frost Nova"),
    ("mage_chronoshift", "Chronoshift",
     "Blink: leave an echo. 2.5s later you snap back to it and undo half the damage taken"),
    ("mage_singularity", "Singularity",
     "Meteor: a black hole drags enemies in for 3s, then collapses in the Meteor's blast"),
    ("cleric_prism_orbs", "Prism Orbs",
     "Holy Orb: orbs split in three each time they bounce off a wall (twice)"),
    ("cleric_bastion", "Bastion",
     "Sanctuary: a dome for 5s that stops enemy shots and pushes enemies out. Still heals"),
    ("cleric_judgement", "Judgement",
     "Divine Light: still revives and heals, then 12 pillars of light hit the toughest foes"),
    ("berserker_throwing_axe", "Throwing Axe",
     "Axe Cleave: every 3rd swing hurls your axe out through the horde and back"),
    ("berserker_bloodbath", "Bloodbath",
     "Blood Frenzy: while it lasts, your kills burst in blood, hurting enemies and healing you"),
    ("berserker_rebound", "Rebound",
     "Leap Slam: each landing bounces you onto the next enemy: 3 slams in a row, each bigger"),
    ("rogue_blade_vortex", "Blade Vortex",
     "Knife Ring: the knives whirl around you for 3s, cutting what comes close, then fly out"),
    ("rogue_shadowstrike", "Shadowstrike",
     "Shadow Step: appear behind the enemy nearest your aim and stab it: a sure crit"),
    ("rogue_shadow_hunt", "Shadow Hunt",
     "Shadow Clones: your clones hunt on their own, blinking between enemies to stab them"),
    ("engineer_flamethrower", "Flamethrower",
     "Rivet Gun: becomes a flamethrower. Fire through the whole pack, spreading as it burns"),
    ("engineer_mortar", "Mortar",
     "Deploy Turret: build mortars instead, lobbing shells at the biggest pack in range"),
    ("engineer_tesla_grid", "Tesla Grid",
     "Tesla Tower: links itself to you and your turrets with lightning that shocks enemies"),
    ("necro_haunt", "Haunt",
     "Soul Bolt: enemies it kills rise as wisps that seek another enemy and burst on it"),
    ("necro_bone_golem", "Bone Golem",
     "Raise Dead: fuse corpses into one golem that draws the horde. Cast again to feed it"),
    ("necro_lich_form", "Lich Form",
     "Army of the Dead: become a Lich for 10s: triple bolts, and your kills rise as skeletons"),
]

# Only useful with teammates: never offered to a solo player.
TEAM_ONLY = {"guardian_angel"}


def q(s):
    return '"%s"' % s.replace("\\", "\\\\").replace('"', '\\"')


def main():
    out = ['[gd_resource type="Resource" script_class="UpgradeLibrary" load_steps=%d format=3]'
           % (len(UPGRADES) + len(ELEMENTS) + len(LEGENDARIES) + 3), ""]
    out.append('[ext_resource type="Script" path="res://src/upgrades/upgrade_library.gd" id="1_library"]')
    out.append('[ext_resource type="Script" path="res://src/upgrades/upgrade_data.gd" id="2_upgrade"]')
    out.append("")
    ids = set()
    rows = [(uid, name, desc, rarity, stacks, hero, effects, {}) for
            (uid, name, desc, rarity, stacks, hero, effects) in UPGRADES]
    for (uid, name, desc, element, tier, effects) in ELEMENTS:
        rarity, bonus = ELEMENT_TIERS[tier]
        extra = {"element": element, "tier": tier, "weight_bonus": bonus}
        if tier > 1:
            extra["requires"] = "%s_%d" % (element, tier - 1)
        rows.append((uid, name, desc, rarity, 1, "", effects, extra))
    assert {u[0] for u in LEGENDARIES} == set(FORMS), "every legendary needs a form and every form a card"
    for (uid, name, desc) in LEGENDARIES:
        hero, slot = FORMS[uid][0], FORMS[uid][1]
        assert len(desc) <= CARD_TEXT_MAX, "%s: card text too long for a 4-player card" % uid
        rows.append((uid, name, desc, LEGENDARY, 1, hero, [], {"form_slot": SLOTS[slot]}))
    for (uid, name, desc, rarity, stacks, hero, effects, extra) in rows:
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
        if "requires" in extra:
            out.append('requires = &"%s"' % extra["requires"])
        if uid in TEAM_ONLY:
            out.append("team_only = true")
        if "element" in extra:
            out.append('element = &"%s"' % extra["element"])
            out.append("tier = %d" % extra["tier"])
            out.append("weight_bonus = %s" % repr(float(extra["weight_bonus"])))
        if "form_slot" in extra:
            out.append("form_slot = %d" % extra["form_slot"])
        out.append("")
    for (uid, _n, _d, _r, _s, _h, _e, extra) in rows:
        assert extra.get("requires", uid) in ids, "%s requires an unknown upgrade" % uid
    out.append("[resource]")
    out.append('script = ExtResource("1_library")')
    refs = ", ".join('SubResource("Resource_%s")' % u[0] for u in rows)
    out.append('upgrades = Array[ExtResource("2_upgrade")]([%s])' % refs)
    path = os.path.join(os.path.dirname(__file__), "..", "src", "upgrades", "data", "upgrade_library.tres")
    with open(path, "w") as f:
        f.write("\n".join(out) + "\n")
    print("wrote %d upgrades" % len(rows))


if __name__ == "__main__":
    main()
