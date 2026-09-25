extends SceneTree
## Generates deterministic placeholder pixel art into res://assets so the game
## is playable before the real art pass (milestone 8).
##   godot --headless --path . -s res://tools/gen_placeholder_art.gd
##   ./tools/dev.sh import
## Outputs:
##   assets/tiles/dungeon_tiles.png        16x16 tiles, see Tiles enum in level.gd
##   assets/sprites/heroes/<id>.png        8 frames of 16x16 (see HERO_FRAMES)
##   assets/sprites/enemies/horde_atlas.png 32x32 cells; one row per enemy kind,
##                                          cols 0-3 walk, 4-5 action (see ENEMY_ROWS)
##   assets/sprites/fx/fx_atlas.png         16x16 cells; row 0 projectiles, row 1 pickups
##   assets/fonts/pixel5x8.png + .fnt       proportional 5x8 pixel font (BMFont), ASCII 32-126

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


## Row index of each enemy kind in the horde atlas (EnemyData.atlas_row).
const ENEMY_ROWS := ["swarmer", "brute", "spitter", "exploder", "skeleton"]
## Column index of each projectile / pickup in row 0 / row 1 of the fx atlas.
const PROJECTILES := ["arrow", "bolt", "orb", "spit", "knife", "rivet", "soul", "fire"]
const PICKUPS := ["gem_small", "gem_medium", "gem_large", "heart"]


func _initialize() -> void:
	_gen_tiles()
	for id: String in HEROES:
		_gen_hero(id, HEROES[id])
	_gen_horde_atlas()
	_gen_fx_atlas()
	_gen_font()
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


# --- enemies (32x32 cells, feet at y=24, centred on x=16) -------------------------

func _gen_horde_atlas() -> void:
	var img := _img(256, 256)
	for row in ENEMY_ROWS.size():
		for col in 6:
			var ox := col * 32
			var oy := row * 32
			match ENEMY_ROWS[row]:
				"swarmer":
					_draw_swarmer(img, ox, oy, col)
				"brute":
					_draw_brute(img, ox, oy, col)
				"spitter":
					_draw_spitter(img, ox, oy, col)
				"exploder":
					_draw_exploder(img, ox, oy, col)
				"skeleton":
					_draw_skeleton(img, ox, oy, col)
			_outline(img, Rect2i(ox, oy, 32, 32))
	_save(img, "res://assets/sprites/enemies/horde_atlas.png")


func _walk(col: int) -> Vector2i:
	## (bob, leg phase) for walk frames 0-3; action frames reuse frame 0.
	match col:
		1:
			return Vector2i(1, 1)
		2:
			return Vector2i(0, 0)
		3:
			return Vector2i(1, -1)
	return Vector2i(0, 0)


func _draw_swarmer(img: Image, ox: int, oy: int, col: int) -> void:
	var skin := Color("5aa83c")
	var dark := Color("3a7426")
	var w := _walk(col)
	var b := w.x
	_rect(img, ox + 13, oy + 21, 2, 3 - maxi(w.y, 0), dark)
	_rect(img, ox + 17, oy + 21, 2, 3 - maxi(-w.y, 0), dark)
	_rect(img, ox + 12, oy + 16 + b, 8, 5, Color("7a5a3a"))
	_rect(img, ox + 11, oy + 10 + b, 10, 7, skin)
	_px(img, ox + 10, oy + 11 + b, skin)
	_px(img, ox + 9, oy + 10 + b, skin)
	_px(img, ox + 21, oy + 11 + b, skin)
	_px(img, ox + 22, oy + 10 + b, skin)
	_px(img, ox + 17, oy + 12 + b, Color("f04030"))
	_px(img, ox + 19, oy + 12 + b, Color("f04030"))
	_rect(img, ox + 16, oy + 15 + b, 4, 1, dark)
	if col >= 4:
		_rect(img, ox + 21, oy + 14 + b, 3, 1, Color("c8c8d0"))


func _draw_brute(img: Image, ox: int, oy: int, col: int) -> void:
	var skin := Color("8a6a9a")
	var dark := Color("5e4470")
	var w := _walk(col)
	var b := w.x
	_rect(img, ox + 10, oy + 20, 4, 4 - maxi(w.y, 0), dark)
	_rect(img, ox + 18, oy + 20, 4, 4 - maxi(-w.y, 0), dark)
	_rect(img, ox + 8, oy + 9 + b, 16, 12, skin)
	_rect(img, ox + 8, oy + 18 + b, 16, 3, Color("6a4a2a"))
	_rect(img, ox + 11, oy + 3 + b, 10, 7, skin)
	_px(img, ox + 17, oy + 6 + b, Color("f0e040"))
	_px(img, ox + 19, oy + 6 + b, Color("f0e040"))
	_px(img, ox + 16, oy + 9 + b, Color("f0f0e0"))
	_px(img, ox + 20, oy + 9 + b, Color("f0f0e0"))
	_rect(img, ox + 5, oy + 10 + b, 3, 8, dark)
	var club_y := 6 if col >= 4 else 9
	_rect(img, ox + 24, oy + club_y + b, 3, 10, Color("7a5a3a"))
	_rect(img, ox + 23, oy + club_y - 2 + b, 5, 3, Color("5a3a1a"))


func _draw_spitter(img: Image, ox: int, oy: int, col: int) -> void:
	var body := Color("9a4ac0")
	var dark := Color("6a2a8a")
	var hover: int = [0, -1, -2, -1, 0, 0][col]
	var y0: int = oy + 10 + hover
	_rect(img, ox + 11, y0, 10, 9, body)
	_rect(img, ox + 10, y0 + 2, 12, 5, body)
	_rect(img, ox + 12, y0 + 9, 2, 3, dark)
	_rect(img, ox + 16, y0 + 9, 2, 2, dark)
	_rect(img, ox + 19, y0 + 9, 1, 3, dark)
	_rect(img, ox + 14, y0 + 2, 5, 4, Color("f0f0f0"))
	_rect(img, ox + 16, y0 + 3, 2, 2, Color("1a1420"))
	_px(img, ox + 12, oy + 23, Color(0, 0, 0, 0.3))
	if col >= 4:
		_rect(img, ox + 14, y0 + 7, 5, 2, Color("7af05a"))


func _draw_exploder(img: Image, ox: int, oy: int, col: int) -> void:
	var shell := Color("e07a2a") if col < 4 else Color("ff4a3a")
	var dark := Color("8a3a1a")
	var w := _walk(col)
	for i in 3:
		var lift := 1 if (i + (col % 2)) % 2 == 0 and col < 4 else 0
		_rect(img, ox + 11 + i * 4, oy + 21 - lift, 1, 3, Color("2a1a14"))
	_rect(img, ox + 10, oy + 13 + w.x, 12, 8, shell)
	_rect(img, ox + 12, oy + 11 + w.x, 8, 2, shell)
	_rect(img, ox + 10, oy + 19 + w.x, 12, 2, dark)
	_rect(img, ox + 15, oy + 14 + w.x, 2, 5, dark)
	_rect(img, ox + 16, oy + 8 + w.x, 1, 3, Color("4a3a2a"))
	_px(img, ox + 16, oy + 7 + w.x, Color("fff080") if col % 2 == 0 else Color("ff8030"))
	if col >= 4:
		_rect(img, ox + 12, oy + 15 + w.x, 3, 3, Color("fff080"))
		_rect(img, ox + 18, oy + 15 + w.x, 3, 3, Color("fff080"))


func _draw_skeleton(img: Image, ox: int, oy: int, col: int) -> void:
	var bone := Color("e8e4d4")
	var shade := Color("a8a494")
	var w := _walk(col)
	var b := w.x
	_rect(img, ox + 14, oy + 20, 1, 4 - maxi(w.y, 0), bone)
	_rect(img, ox + 17, oy + 20, 1, 4 - maxi(-w.y, 0), bone)
	_rect(img, ox + 13, oy + 19 + b, 6, 1, shade)
	_rect(img, ox + 15, oy + 13 + b, 2, 6, bone)
	_rect(img, ox + 13, oy + 14 + b, 6, 1, bone)
	_rect(img, ox + 13, oy + 16 + b, 6, 1, bone)
	_rect(img, ox + 12, oy + 7 + b, 7, 6, bone)
	_px(img, ox + 15, oy + 9 + b, Color("1a1420"))
	_px(img, ox + 17, oy + 9 + b, Color("1a1420"))
	_rect(img, ox + 14, oy + 12 + b, 4, 1, shade)
	_rect(img, ox + 20, oy + 12 + b, 1, 6, Color("9a7a5a"))
	if col >= 4:
		_rect(img, ox + 20, oy + 8 + b, 1, 5, Color("c8c8d0"))


# --- fx atlas: projectiles (row 0, pointing right) and pickups (row 1) ----------------

func _gen_fx_atlas() -> void:
	var img := _img(128, 64)
	for i in PROJECTILES.size():
		_draw_projectile(img, i * 16, 0, PROJECTILES[i])
	for i in PICKUPS.size():
		_draw_pickup(img, i * 16, 16, PICKUPS[i])
	# Row 2: soft round particles (white, tinted in shader) of sizes 1..8.
	for i in 8:
		var r := float(i + 1) * 0.9
		for y in 16:
			for x in 16:
				var d := Vector2(x + 0.5, y + 0.5).distance_to(Vector2(8, 8))
				if d <= r:
					_px(img, i * 16 + x, 32 + y, Color(1, 1, 1, 1.0 if d < r - 0.8 else 0.6))
	_save(img, "res://assets/sprites/fx/fx_atlas.png")


func _draw_projectile(img: Image, ox: int, oy: int, kind: String) -> void:
	match kind:
		"arrow":
			_rect(img, ox + 3, oy + 7, 9, 1, Color("c8a070"))
			_rect(img, ox + 12, oy + 6, 2, 3, Color("d8dce4"))
			_px(img, ox + 14, oy + 7, Color("d8dce4"))
			_rect(img, ox + 2, oy + 6, 2, 1, Color("e04848"))
			_rect(img, ox + 2, oy + 8, 2, 1, Color("e04848"))
		"bolt":
			_rect(img, ox + 6, oy + 6, 5, 4, Color("b070ff"))
			_rect(img, ox + 7, oy + 7, 3, 2, Color("f0e0ff"))
			_rect(img, ox + 3, oy + 7, 3, 2, Color("7040c0"))
		"orb":
			_rect(img, ox + 5, oy + 5, 6, 6, Color("f2d24a"))
			_rect(img, ox + 6, oy + 6, 3, 3, Color("fffae0"))
		"spit":
			_rect(img, ox + 6, oy + 6, 4, 4, Color("7af05a"))
			_rect(img, ox + 3, oy + 7, 3, 2, Color("4aa83a"))
			_px(img, ox + 8, oy + 7, Color("e0ffd0"))
		"knife":
			_rect(img, ox + 5, oy + 7, 7, 1, Color("d8dce4"))
			_rect(img, ox + 3, oy + 7, 2, 1, Color("6a4a2a"))
			_px(img, ox + 12, oy + 7, Color("ffffff"))
		"rivet":
			_rect(img, ox + 6, oy + 7, 5, 2, Color("b0b8c0"))
			_px(img, ox + 11, oy + 7, Color("e0e8f0"))
		"soul":
			_rect(img, ox + 6, oy + 5, 5, 6, Color("5af0d0"))
			_rect(img, ox + 7, oy + 6, 3, 4, Color("d0fff4"))
			_rect(img, ox + 3, oy + 7, 3, 2, Color("2a9a8a"))
		"fire":
			_rect(img, ox + 5, oy + 5, 6, 6, Color("ff7a2a"))
			_rect(img, ox + 6, oy + 6, 4, 4, Color("ffd04a"))
			_px(img, ox + 7, oy + 7, Color("fff8d0"))
	_outline(img, Rect2i(ox, oy, 16, 16))


func _draw_pickup(img: Image, ox: int, oy: int, kind: String) -> void:
	var colors := {"gem_small": Color("5ab0f0"), "gem_medium": Color("5af08a"), "gem_large": Color("f05a8a")}
	if kind == "heart":
		_rect(img, ox + 5, oy + 6, 3, 2, Color("e84a4a"))
		_rect(img, ox + 9, oy + 6, 3, 2, Color("e84a4a"))
		_rect(img, ox + 5, oy + 8, 7, 2, Color("e84a4a"))
		_rect(img, ox + 6, oy + 10, 5, 1, Color("e84a4a"))
		_px(img, ox + 8, oy + 11, Color("e84a4a"))
		_px(img, ox + 6, oy + 7, Color("ffb0b0"))
	else:
		var c: Color = colors[kind]
		var size := {"gem_small": 2, "gem_medium": 3, "gem_large": 4}[kind] as int
		for dy in range(-size, size + 1):
			var half := size - absi(dy)
			_rect(img, ox + 8 - half, oy + 8 + dy, half * 2 + 1, 1, c)
		_px(img, ox + 7, oy + 7, c.lightened(0.6))
	_outline(img, Rect2i(ox, oy, 16, 16))


# --- pixel font ------------------------------------------------------------------------
## Classic 5x7 (+descender row) glyphs, ASCII 32..126, 5 column bytes each (bit 0 = top).
const FONT_GLYPHS: PackedByteArray = [
	0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x5F, 0x00, 0x00, 0x00, 0x07, 0x00, 0x07, 0x00, 0x14, 0x7F, 0x14, 0x7F, 0x14,
	0x24, 0x2A, 0x7F, 0x2A, 0x12, 0x23, 0x13, 0x08, 0x64, 0x62, 0x36, 0x49, 0x56, 0x20, 0x50, 0x00, 0x08, 0x07, 0x03, 0x00,
	0x00, 0x1C, 0x22, 0x41, 0x00, 0x00, 0x41, 0x22, 0x1C, 0x00, 0x2A, 0x1C, 0x7F, 0x1C, 0x2A, 0x08, 0x08, 0x3E, 0x08, 0x08,
	0x00, 0x80, 0x70, 0x30, 0x00, 0x08, 0x08, 0x08, 0x08, 0x08, 0x00, 0x00, 0x60, 0x60, 0x00, 0x20, 0x10, 0x08, 0x04, 0x02,
	0x3E, 0x51, 0x49, 0x45, 0x3E, 0x00, 0x42, 0x7F, 0x40, 0x00, 0x72, 0x49, 0x49, 0x49, 0x46, 0x21, 0x41, 0x49, 0x4D, 0x33,
	0x18, 0x14, 0x12, 0x7F, 0x10, 0x27, 0x45, 0x45, 0x45, 0x39, 0x3C, 0x4A, 0x49, 0x49, 0x31, 0x41, 0x21, 0x11, 0x09, 0x07,
	0x36, 0x49, 0x49, 0x49, 0x36, 0x46, 0x49, 0x49, 0x29, 0x1E, 0x00, 0x00, 0x14, 0x00, 0x00, 0x00, 0x40, 0x34, 0x00, 0x00,
	0x00, 0x08, 0x14, 0x22, 0x41, 0x14, 0x14, 0x14, 0x14, 0x14, 0x00, 0x41, 0x22, 0x14, 0x08, 0x02, 0x01, 0x59, 0x09, 0x06,
	0x3E, 0x41, 0x5D, 0x59, 0x4E, 0x7C, 0x12, 0x11, 0x12, 0x7C, 0x7F, 0x49, 0x49, 0x49, 0x36, 0x3E, 0x41, 0x41, 0x41, 0x22,
	0x7F, 0x41, 0x41, 0x41, 0x3E, 0x7F, 0x49, 0x49, 0x49, 0x41, 0x7F, 0x09, 0x09, 0x09, 0x01, 0x3E, 0x41, 0x41, 0x51, 0x73,
	0x7F, 0x08, 0x08, 0x08, 0x7F, 0x00, 0x41, 0x7F, 0x41, 0x00, 0x20, 0x40, 0x41, 0x3F, 0x01, 0x7F, 0x08, 0x14, 0x22, 0x41,
	0x7F, 0x40, 0x40, 0x40, 0x40, 0x7F, 0x02, 0x1C, 0x02, 0x7F, 0x7F, 0x04, 0x08, 0x10, 0x7F, 0x3E, 0x41, 0x41, 0x41, 0x3E,
	0x7F, 0x09, 0x09, 0x09, 0x06, 0x3E, 0x41, 0x51, 0x21, 0x5E, 0x7F, 0x09, 0x19, 0x29, 0x46, 0x26, 0x49, 0x49, 0x49, 0x32,
	0x03, 0x01, 0x7F, 0x01, 0x03, 0x3F, 0x40, 0x40, 0x40, 0x3F, 0x1F, 0x20, 0x40, 0x20, 0x1F, 0x3F, 0x40, 0x38, 0x40, 0x3F,
	0x63, 0x14, 0x08, 0x14, 0x63, 0x03, 0x04, 0x78, 0x04, 0x03, 0x61, 0x59, 0x49, 0x4D, 0x43, 0x00, 0x7F, 0x41, 0x41, 0x41,
	0x02, 0x04, 0x08, 0x10, 0x20, 0x00, 0x41, 0x41, 0x41, 0x7F, 0x04, 0x02, 0x01, 0x02, 0x04, 0x40, 0x40, 0x40, 0x40, 0x40,
	0x00, 0x03, 0x07, 0x08, 0x00, 0x20, 0x54, 0x54, 0x78, 0x40, 0x7F, 0x28, 0x44, 0x44, 0x38, 0x38, 0x44, 0x44, 0x44, 0x28,
	0x38, 0x44, 0x44, 0x28, 0x7F, 0x38, 0x54, 0x54, 0x54, 0x18, 0x00, 0x08, 0x7E, 0x09, 0x02, 0x18, 0xA4, 0xA4, 0x9C, 0x78,
	0x7F, 0x08, 0x04, 0x04, 0x78, 0x00, 0x44, 0x7D, 0x40, 0x00, 0x20, 0x40, 0x40, 0x3D, 0x00, 0x7F, 0x10, 0x28, 0x44, 0x00,
	0x00, 0x41, 0x7F, 0x40, 0x00, 0x7C, 0x04, 0x78, 0x04, 0x78, 0x7C, 0x08, 0x04, 0x04, 0x78, 0x38, 0x44, 0x44, 0x44, 0x38,
	0xFC, 0x18, 0x24, 0x24, 0x18, 0x18, 0x24, 0x24, 0x18, 0xFC, 0x7C, 0x08, 0x04, 0x04, 0x08, 0x48, 0x54, 0x54, 0x54, 0x24,
	0x04, 0x04, 0x3F, 0x44, 0x24, 0x3C, 0x40, 0x40, 0x20, 0x7C, 0x1C, 0x20, 0x40, 0x20, 0x1C, 0x3C, 0x40, 0x30, 0x40, 0x3C,
	0x44, 0x28, 0x10, 0x28, 0x44, 0x4C, 0x90, 0x90, 0x90, 0x7C, 0x44, 0x64, 0x54, 0x4C, 0x44, 0x00, 0x08, 0x36, 0x41, 0x00,
	0x00, 0x00, 0x77, 0x00, 0x00, 0x00, 0x41, 0x36, 0x08, 0x00, 0x02, 0x01, 0x02, 0x04, 0x02,
]
const FONT_CELL := Vector2i(6, 9)
const FONT_COLUMNS := 16


func _gen_font() -> void:
	var img := _img(128, 64)
	var chars := PackedStringArray()
	for index in 95:
		var code := 32 + index
		var cx := (index % FONT_COLUMNS) * FONT_CELL.x
		var cy := (index / FONT_COLUMNS) * FONT_CELL.y
		var first := -1
		var last := -1
		for col in 5:
			var bits := FONT_GLYPHS[index * 5 + col]
			if bits != 0:
				if first == -1:
					first = col
				last = col
			for row in 8:
				if bits & (1 << row):
					img.set_pixel(cx + col, cy + row, Color.WHITE)
		var width := 0 if first == -1 else last - first + 1
		var advance := 3 if first == -1 else width + 1
		chars.append("char id=%d x=%d y=%d width=%d height=8 xoffset=0 yoffset=0 xadvance=%d page=0 chnl=15" % [
			code, cx + maxi(first, 0), cy, width, advance])
	_save(img, "res://assets/fonts/pixel5x8.png")
	var fnt := PackedStringArray([
		'info face="Pixel5x8" size=8 bold=0 italic=0 charset="" unicode=1 stretchH=100 smooth=0 aa=1 padding=0,0,0,0 spacing=1,1',
		"common lineHeight=10 base=7 scaleW=128 scaleH=64 pages=1 packed=0",
		'page id=0 file="pixel5x8.png"',
		"chars count=95",
	])
	fnt.append_array(chars)
	var file := FileAccess.open("res://assets/fonts/pixel5x8.fnt", FileAccess.WRITE)
	file.store_string("\n".join(fnt) + "\n")
