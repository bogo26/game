class_name HeroOverlay
extends Node2D
## Drawn above everything else in the world: each hero's aim reticle and, at
## the start of a level, after a revive and while downed, a "P1" tag in the
## player's colour over their head.

const FONT := preload("res://assets/fonts/pixel5x8.fnt")
## Baseline of the tag, relative to the hero's feet.
const TAG_OFFSET := Vector2(0, -17)

var world: World


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if world == null:
		return
	for hero in world.heroes:
		if not hero.is_downed():
			var reticle := (hero.position + Hero.SPRITE_FEET_OFFSET + hero.aim_dir * Hero.RETICLE_DISTANCE).round()
			draw_rect(Rect2(reticle - Vector2(1, 1), Vector2(3, 3)), hero.color)
			draw_rect(Rect2(reticle, Vector2(1, 1)), Color.WHITE)
		if hero.tag_time > 0.0 or hero.is_downed():
			var text := "P%d" % (hero.slot + 1)
			var width := FONT.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 8).x
			var at := (hero.position + TAG_OFFSET - Vector2(width * 0.5, 0.0) - Vector2(0, hero.air_height)).round()
			draw_string(FONT, at + Vector2(1, 1), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(0, 0, 0, 0.85))
			draw_string(FONT, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, hero.color)
