extends Node
## Global signal bus. Systems emit here so UI/audio/FX can react without
## holding references to each other. Keep payloads small and typed.

# --- Players / devices -------------------------------------------------------
signal player_joined(slot: int)
signal player_left(slot: int)
signal player_device_lost(slot: int)
signal player_device_restored(slot: int)

# --- Heroes ------------------------------------------------------------------
signal hero_damaged(slot: int, amount: float)
signal hero_downed(slot: int)
signal hero_revived(slot: int)
signal all_heroes_downed

# --- Horde -------------------------------------------------------------------
signal enemy_killed(position: Vector2, enemy_type: int, killer_slot: int)

# --- Progression -------------------------------------------------------------
signal xp_changed(current: int, needed: int, team_level: int)
signal team_level_up(team_level: int)

# --- Run flow ----------------------------------------------------------------
signal level_started(level_index: int)
signal level_completed(level_index: int)
signal run_finished(victory: bool)
