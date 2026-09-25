extends SceneTree
## Generates deterministic placeholder pixel art into res://assets so the game
## is playable before the real art pass (milestone 8).
##   godot --headless --path . -s res://tools/gen_placeholder_art.gd
##   ./tools/dev.sh import
## Outputs:
##   assets/tiles/dungeon_tiles.png        16x16 tiles, see Tiles enum in level.gd
##   assets/sprites/heroes/<id>.png        8 frames of 16x16 (see HERO_FRAMES)

const OUTLINE := Color("140c1c")
const SKIN := Color("f0c8a0")
const SKIN_DARK := Color("c89878")
const EYE := Color("1a1420")

## Frame order in every hero sheet.
const HERO_FRAMES := ["idle0", "idle1", "run0", "run1", "run2", "run3", "dash", "downed"]

const HEROES := {
	"knight": {"body": "8a9bb0", "body_dark": "5b6b82", "head": "b8c4d4", "head_dark": "7d8aa0",
		"accent": "3c6fd0", "weapon": "dfe6ee", "style": "helmet", "gear": "sword"},
	"ranger": {"body": "3f8f4a", "body_dark": "2b6435", "head": "4fa85a", "head_dark": "2e6e38",
		"accent": "8a5a2b", "weapon": "a0703a", "style": "hood", "gear": "bow"},
	"mage": {"body": "6a3fb0", "body_dark": "4a2a80", "head": "7a4ad0", "head_dark": "52308f",
		"accent": "f2d24a", "weapon": "9a6a3a", "style": "wizard", "gear": "staff"},
	"cleric": {"body": "e8e4d8", "body_dark": "b8b0a0", "head": "f2d24a", "head_dark": "c8a830",
		"accent": "fff4a0", "weapon": "c8c8d0", "style": "halo", "gear": "mace"},
	"berserker": {"body": "8a3a2a", "body_dark": "5e2418", "head": "d8642a", "head_dark": "a04418",
		"accent": "c8c8d0", "weapon": "8a6040", "style": "hair", "gear": "axe"},
	"rogue": {"body": "3a3a4c", "body_dark": "25252f", "head": "2c2c3a", "head_dark": "1c1c26",
		"accent": "a03040", "weapon": "d0d8e0", "style": "mask", "gear": "dagger"},
	"engineer": {"body": "5a6a7a", "body_dark": "3c4854", "head": "f29a2a", "head_dark": "c07018",
		"accent": "5ad0e0", "weapon": "b0b8c0", "style": "hardhat", "gear": "wrench"},
	"necromancer": {"body": "2e2640", "body_dark": "1c1628", "head": "3a3050", "head_dark": "241c34",
		"accent": "5af0d0", "weapon": "e8e0d0", "style": "hood_glow", "gear": "skull_staff"},
}


func _initialize() -> void:
	_gen_tiles()
	for id: String in HEROES:
		_gen_hero(id, HEROES[id])
	print("placeholder art generated")
	quit()


# --- helpers -------------------------------------------------------------------

func _img(w: int, h: int) -> Image:
	var img := Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	return img


func _px(img: Image, x: int, y: int, c: Color) -> void:
	if x >= 0 and y >= 0 and x < img.get_width() and y < img.get_height():
		img.set_pixel(x, y, c)


func _rect(img: Image, x: int, y: int, w: int, h: int, c: Color) -> void:
	for yy in range(y, y + h):
		for xx in range(x, x + w):
			_px(img, xx, yy, c)


## Adds a 1px outline around opaque pixels inside `area`.
func _outline(img: Image, area: Rect2i, color: Color = OUTLINE) -> void:
	var to_set: Array[Vector2i] = []
	for y in range(area.position.y, area.end.y):
		for x in range(area.position.x, area.end.x):
			if img.get_pixel(x, y).a > 0.0:
				continue
			for d: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
				var n := Vector2i(x, y) + d
				if area.has_point(n) and img.get_pixel(n.x, n.y).a > 0.0:
					to_set.append(Vector2i(x, y))
					break
	for p in to_set:
		img.set_pixel(p.x, p.y, color)


func _save(img: Image, path: String) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var err := img.save_png(path)
	if err != OK:
		push_error("failed to save %s: %s" % [path, error_string(err)])


# --- tiles -----------------------------------------------------------------------

func _gen_tiles() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1337
	var img := _img(128, 32)
	var floor_base := Color("2e2b40")
	# Row 0: floor0..3, floor_shadow, wall_top, wall_face, void
	for v in 4:
		_floor_tile(img, v * 16, 0, floor_base, rng, v)
	_floor_tile(img, 64, 0, floor_base, rng, 0)
	for y in 4:
		for x in 16:
			var c := img.get_pixel(64 + x, y)
			img.set_pixel(64 + x, y, c.darkened(0.45 - y * 0.1))
	_wall_top(img, 80, 0, rng)
	_wall_face(img, 96, 0, rng)
	_rect(img, 112, 0, 16, 16, Color("0c0b12"))
	# Row 1: door, exit portal, spawn marker (debug), arena floor tint
	_door(img, 0, 16)
	_portal(img, 16, 16)
	_floor_tile(img, 32, 16, floor_base, rng, 0)
	_rect(img, 38, 22, 4, 4, Color("a03040"))
	_floor_tile(img, 48, 16, Color("352a3a"), rng, 1)
	_save(img, "res://assets/tiles/dungeon_tiles.png")


func _floor_tile(img: Image, ox: int, oy: int, base: Color, rng: RandomNumberGenerator, variant: int) -> void:
	for y in 16:
		for x in 16:
			var n := rng.randf_range(-0.035, 0.035)
			var c := Color(base.r + n, base.g + n, base.b + n)
			# Stone slab seams every 8px, offset per row of slabs.
			var seam_x := (x + (8 if y >= 8 else 0)) % 16 == 0
			if y % 8 == 0 or seam_x:
				c = c.darkened(0.25)
			img.set_pixel(ox + x, oy + y, c)
	match variant:
		1:  # crack
			var cx := 4
			for y in range(3, 12):
				_px(img, ox + cx, oy + y, base.darkened(0.5))
				if rng.randf() < 0.4:
					cx = clampi(cx + (1 if rng.randf() < 0.5 else -1), 2, 13)
		2:  # pebbles
			for i in 4:
				var px := ox + rng.randi_range(2, 13)
				var py := oy + rng.randi_range(2, 13)
				_px(img, px, py, base.lightened(0.25))
				_px(img, px + 1, py + 1, base.darkened(0.3))
		3:  # moss
			for i in 10:
				_px(img, ox + rng.randi_range(1, 14), oy + rng.randi_range(9, 14), Color("34503a"))


func _wall_top(img: Image, ox: int, oy: int, rng: RandomNumberGenerator) -> void:
	var base := Color("4a4666")
	for y in 16:
		for x in 16:
			var n := rng.randf_range(-0.02, 0.02)
			img.set_pixel(ox + x, oy + y, Color(base.r + n, base.g + n, base.b + n))
	_rect(img, ox, oy, 16, 1, Color("615d84"))
	_rect(img, ox, oy + 15, 16, 1, Color("2c2940"))


func _wall_face(img: Image, ox: int, oy: int, rng: RandomNumberGenerator) -> void:
	var brick := Color("3d3957")
	var mortar := Color("24223a")
	for y in 16:
		for x in 16:
			var row := y / 4
			var offset := 4 if row % 2 == 1 else 0
			var is_mortar := y % 4 == 3 or (x + offset) % 8 == 7
			var n := rng.randf_range(-0.03, 0.03)
			var c := mortar if is_mortar else Color(brick.r + n, brick.g + n, brick.b + n)
			if y >= 13:
				c = c.darkened(0.35)
			img.set_pixel(ox + x, oy + y, c)
	_rect(img, ox, oy, 16, 1, Color("5a5680"))


func _door(img: Image, ox: int, oy: int) -> void:
	for y in 16:
		for x in 16:
			var c := Color("6a4a2a") if x % 4 != 3 else Color("4a3018")
			img.set_pixel(ox + x, oy + y, c)
	_rect(img, ox, oy + 3, 16, 2, Color("3a3a48"))
	_rect(img, ox, oy + 11, 16, 2, Color("3a3a48"))
	_rect(img, ox, oy, 16, 1, Color("2a1a0e"))


func _portal(img: Image, ox: int, oy: int) -> void:
	var center := Vector2(7.5, 7.5)
	for y in 16:
		for x in 16:
			var d := Vector2(x, y).distance_to(center)
			var ang := atan2(y - center.y, x - center.x)
			var swirl := sin(ang * 3.0 + d * 0.9)
			var c := Color("2e2b40")
			if d < 7.5:
				var t := 1.0 - d / 7.5
				c = Color("5a2a9a").lerp(Color("e0a0ff"), clampf(t * 0.8 + swirl * 0.2, 0.0, 1.0))
			img.set_pixel(ox + x, oy + y, c)


# --- heroes ----------------------------------------------------------------------

func _gen_hero(id: String, look: Dictionary) -> void:
	var img := _img(16 * HERO_FRAMES.size(), 16)
	for f in HERO_FRAMES.size():
		var frame: String = HERO_FRAMES[f]
		if frame == "downed":
			_draw_downed(img, f * 16, look)
		else:
			_draw_hero(img, f * 16, frame, look)
		_outline(img, Rect2i(f * 16, 0, 16, 16))
	_save(img, "res://assets/sprites/heroes/%s.png" % id)


func _draw_hero(img: Image, ox: int, frame: String, look: Dictionary) -> void:
	var body := Color(look["body"])
	var body_dark := Color(look["body_dark"])
	var bob := 1 if frame in ["idle1", "run1", "run3"] else 0
	var lean := 1 if frame == "dash" else 0
	var back_lift := 1 if frame == "run0" else 0
	var front_lift := 1 if frame == "run2" else 0
	var x0 := ox + lean
	# Legs
	if frame == "dash":
		_rect(img, ox + 4, 12, 3, 2, body_dark)
		_rect(img, ox + 8, 12, 2, 3, body_dark)
	else:
		_rect(img, ox + 6, 12, 2, 3 - back_lift, body_dark)
		_rect(img, ox + 8, 12, 2, 3 - front_lift, body_dark.lightened(0.1))
	# Torso
	_rect(img, x0 + 5, 8 + bob, 6, 4, body)
	_rect(img, x0 + 5, 11 + bob, 6, 1, body_dark)
	_rect(img, x0 + 7, 8 + bob, 1, 3, body_dark)
	# Front arm
	_rect(img, x0 + 10, 9 + bob, 1, 2, body_dark)
	_px(img, x0 + 11, 10 + bob, SKIN)
	# Head
	_draw_head(img, x0, bob, look)
	_draw_gear(img, x0, bob, look)


func _draw_head(img: Image, x0: int, bob: int, look: Dictionary) -> void:
	var head := Color(look["head"])
	var head_dark := Color(look["head_dark"])
	var accent := Color(look["accent"])
	var y := 2 + bob
	# Face base
	_rect(img, x0 + 5, y, 6, 6, SKIN)
	_rect(img, x0 + 5, y + 5, 6, 1, SKIN_DARK)
	_px(img, x0 + 8, y + 3, EYE)
	_px(img, x0 + 10, y + 3, EYE)
	match look["style"]:
		"helmet":
			_rect(img, x0 + 5, y, 6, 6, head)
			_rect(img, x0 + 7, y + 3, 4, 1, EYE)
			_rect(img, x0 + 5, y + 5, 6, 1, head_dark)
			_rect(img, x0 + 6, y - 1, 2, 1, accent)
		"hood":
			_rect(img, x0 + 5, y, 6, 2, head)
			_rect(img, x0 + 5, y, 1, 6, head)
			_rect(img, x0 + 4, y + 1, 1, 3, head_dark)
		"wizard":
			_rect(img, x0 + 4, y, 8, 1, head_dark)
			_rect(img, x0 + 5, y - 1, 5, 1, head)
			_rect(img, x0 + 6, y - 2, 3, 1, head)
			_px(img, x0 + 6, y - 3, head)
			_px(img, x0 + 8, y - 1, accent)
			_rect(img, x0 + 7, y + 4, 4, 2, Color("e8e8f0"))
		"halo":
			_rect(img, x0 + 5, y, 6, 2, head)
			_rect(img, x0 + 5, y, 1, 4, head)
			_rect(img, x0 + 6, y - 2, 4, 1, accent)
		"hair":
			_rect(img, x0 + 5, y, 6, 2, head)
			_px(img, x0 + 5, y - 1, head)
			_px(img, x0 + 7, y - 1, head)
			_px(img, x0 + 9, y - 1, head)
			_rect(img, x0 + 4, y + 1, 1, 3, head_dark)
			_rect(img, x0 + 8, y + 5, 3, 1, head_dark)
		"mask":
			_rect(img, x0 + 5, y, 6, 3, head)
			_rect(img, x0 + 5, y, 1, 6, head)
			_rect(img, x0 + 6, y + 4, 5, 2, accent)
		"hardhat":
			_rect(img, x0 + 4, y + 1, 8, 1, head_dark)
			_rect(img, x0 + 5, y - 1, 6, 2, head)
			_rect(img, x0 + 7, y + 2, 4, 1, accent)
		"hood_glow":
			_rect(img, x0 + 5, y, 6, 6, head)
			_rect(img, x0 + 6, y + 2, 5, 4, Color("0e0a16"))
			_px(img, x0 + 8, y + 3, accent)
			_px(img, x0 + 10, y + 3, accent)
			_px(img, x0 + 4, y + 2, head_dark)


func _draw_gear(img: Image, x0: int, bob: int, look: Dictionary) -> void:
	var weapon := Color(look["weapon"])
	var accent := Color(look["accent"])
	match look["gear"]:
		"sword":
			_rect(img, x0 + 12, 4 + bob, 1, 6, weapon)
			_rect(img, x0 + 11, 10 + bob, 3, 1, Color("8a6a3a"))
			_px(img, x0 + 12, 11 + bob, Color("6a4a2a"))
			_rect(img, x0 + 3, 8 + bob, 2, 4, accent)
		"bow":
			_rect(img, x0 + 13, 5 + bob, 1, 8, weapon)
			_px(img, x0 + 12, 4 + bob, weapon)
			_px(img, x0 + 12, 13 + bob, weapon)
			_rect(img, x0 + 12, 5 + bob, 1, 8, Color("e0e0e0", 0.6))
		"staff":
			_rect(img, x0 + 12, 3 + bob, 1, 11, weapon)
			_rect(img, x0 + 11, 1 + bob, 3, 2, accent)
		"mace":
			_rect(img, x0 + 12, 8 + bob, 1, 4, Color("8a6a3a"))
			_rect(img, x0 + 11, 6 + bob, 3, 2, weapon)
		"axe":
			_rect(img, x0 + 12, 4 + bob, 1, 9, weapon)
			_rect(img, x0 + 13, 4 + bob, 2, 4, accent)
		"dagger":
			_rect(img, x0 + 12, 8 + bob, 1, 3, weapon)
			_px(img, x0 + 12, 11 + bob, accent)
			_rect(img, x0 + 3, 9 + bob, 1, 3, weapon)
		"wrench":
			_rect(img, x0 + 12, 8 + bob, 1, 5, weapon)
			_rect(img, x0 + 11, 6 + bob, 3, 2, weapon)
			_px(img, x0 + 12, 6 + bob, Color(0, 0, 0, 0))
			_rect(img, x0 + 3, 8 + bob, 2, 3, Color("8a6a3a"))
		"skull_staff":
			_rect(img, x0 + 12, 4 + bob, 1, 10, Color("4a3a2a"))
			_rect(img, x0 + 11, 1 + bob, 3, 3, weapon)
			_px(img, x0 + 11, 2 + bob, accent)
			_px(img, x0 + 13, 2 + bob, accent)


func _draw_downed(img: Image, ox: int, look: Dictionary) -> void:
	var body := Color(look["body"]).darkened(0.25)
	var body_dark := Color(look["body_dark"]).darkened(0.25)
	var head := Color(look["head"]).darkened(0.25)
	_rect(img, ox + 2, 11, 3, 3, body_dark)
	_rect(img, ox + 5, 10, 6, 4, body)
	_rect(img, ox + 11, 9, 4, 5, SKIN.darkened(0.2))
	_rect(img, ox + 11, 9, 4, 2, head)
	_px(img, ox + 12, 12, EYE)
	_px(img, ox + 14, 12, EYE)
