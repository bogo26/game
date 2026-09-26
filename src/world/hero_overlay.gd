class_name HeroOverlay
extends Node2D
## Drawn above everything else in the world:
## - each hero's aim reticle
## - a "P1" tag over the head at level start, after a revive and while downed
## - for a downed hero: a pulsing "!", a dashed circle showing where a teammate
##   must stand to revive them, and the revive progress as a ring

const FONT := preload("res://assets/fonts/pixel5x8.fnt")
## Baseline of the tag, relative to the hero's feet.
const TAG_OFFSET := Vector2(0, -17)
const REVIVE_COLOR := Color(0.5, 1.0, 0.55)

var world: World
var _time := 0.0


func _process(delta: float) -> void:
	_time += delta
	queue_redraw()


func _draw() -> void:
	if world == null:
		return
	for hero in world.heroes:
		if hero.is_downed():
			_draw_downed(hero)
		else:
			var reticle := (hero.position + Hero.SPRITE_FEET_OFFSET + hero.aim_dir * Hero.RETICLE_DISTANCE).round()
			draw_rect(Rect2(reticle - Vector2(1, 1), Vector2(3, 3)), hero.color)
			draw_rect(Rect2(reticle, Vector2(1, 1)), Color.WHITE)
		if hero.tag_time > 0.0 or hero.is_downed():
			_text(hero.position + TAG_OFFSET - Vector2(0, hero.air_height), "P%d" % (hero.slot + 1), 8, hero.color)


func _draw_downed(hero: Hero) -> void:
	var pulse := 0.5 + 0.5 * sin(_time * 8.0)
	var p := hero.position.round()
	# Where to stand to revive.
	var circle := Color(hero.color, 0.45 + 0.35 * pulse)
	var segments := 16
	var step := TAU / segments
	var turn := _time * 0.8
	for k in range(0, segments, 2):
		draw_arc(p, Hero.REVIVE_RADIUS, turn + k * step, turn + (k + 1) * step, 3, circle, -1.0, false)
	# Revive progress.
	if hero.revive_progress > 0.0:
		var share := clampf(hero.revive_progress / Hero.REVIVE_TIME, 0.0, 1.0)
		draw_arc(p + Vector2(0, -3), 9.0, -PI * 0.5, -PI * 0.5 + TAU * share, 24, REVIVE_COLOR, 2.0, false)
	# "Help me!"
	_text(p + TAG_OFFSET + Vector2(0, -9), "!", 16, Color(hero.color.lightened(0.3), 0.6 + 0.4 * pulse))


func _text(at: Vector2, text: String, size: int, color: Color) -> void:
	var width := FONT.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var pos := (at - Vector2(width * 0.5, 0.0)).round()
	draw_string(FONT, pos + Vector2(1, 1), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(0, 0, 0, 0.85 * color.a))
	draw_string(FONT, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)
