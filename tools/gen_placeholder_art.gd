extends SceneTree
## Generates deterministic placeholder pixel art into res://assets so the game
## is playable before the real art pass (milestone 8).
##   godot --headless --path . -s res://tools/gen_placeholder_art.gd
##   ./tools/dev.sh import
## Outputs:
##   assets/tiles/tiles_<theme>.png        16x16 tiles per level theme (see THEMES, Level.Tile)
##   assets/sprites/heroes/<id>.png        8 frames of 16x16 (see HERO_FRAMES)
##   assets/sprites/enemies/horde_atlas.png 32x32 cells; one row per enemy kind,
##                                          cols 0-3 walk, 4-5 action (see ENEMY_ROWS)
##   assets/sprites/fx/fx_atlas.png         16x16 cells; row 0 projectiles, row 1 pickups,
##                                          row 2 particles, row 3 more projectiles
##   assets/fonts/pixel5x8.png + .fnt       proportional 5x8 pixel font (BMFont), ASCII 32-126
##   assets/sprites/enemies/boss_demon.png  4 frames of 64x64: walk0, walk1, windup, charge
##   assets/sprites/enemies/bone_colossus.png 4 frames of 64x64: walk0, walk1, windup, leap
##   assets/sprites/props/chest.png         2 frames of 16x16: closed, open
##   assets/sprites/props/shrine.png        2 frames of 16x24: active, used (orb is white: tinted in game)
##   assets/sprites/fx/glow.png             64x64 soft light (torch glow)
##   assets/icon.png                        256x256 app icon (knight vs. the horde)

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
const ENEMY_ROWS := ["swarmer", "brute", "spitter", "exploder", "skeleton", "barrel", "urn", "nest",
	"bat", "drowned", "bone_archer", "revenant", "bone_pile", "sporecap", "frost_boar", "salamander", "imp"]
## Flyers get a soft shadow on the ground under them.
const FLYERS := ["bat", "imp"]
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
	_gen_boss()
	_gen_colossus()
	_gen_props()
	_gen_icon()
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
## One 128x80 tile sheet per level theme, same layout (see Level.Tile / Level.Decor):
##   row 0: floor0-3, floor shadow, wall top, wall face, void
##   row 1: door, exit, spawn marker, arena floor, spikes down / warn / up, water edge
##   row 2: water x3 (animated), chasm edge, chasm x3 (animated), -
##   row 3: floor decor: bones, skull, cobweb L / R, rubble, puddle, moss, cracks
##   row 4: wall decor: torch x3 (animated), banner, chains, wall crack
const THEMES := {
	"crypt": {"style": "slab", "floor": "2e2b40", "arena": "352a3a", "moss": "34503a",
		"wall_top": "4a4666", "wall_hi": "615d84", "wall_lo": "2c2940", "brick": "3d3957", "mortar": "24223a",
		"face_hi": "5a5680", "water": "22406a", "water_hi": "4e7cb4", "pit": "07060c", "pit_hi": "30284a",
		"lava": false, "banner": "5a3a9a", "banner_hi": "c8a040"},
	"flooded": {"style": "slab", "floor": "26383a", "arena": "2c3438", "moss": "3c6e46",
		"wall_top": "3e5a58", "wall_hi": "5a7e78", "wall_lo": "223634", "brick": "34504c", "mortar": "1c2e2c",
		"face_hi": "56786e", "water": "1f4f6e", "water_hi": "5fa6c8", "pit": "061420", "pit_hi": "1e4a60",
		"lava": false, "banner": "2a7a6a", "banner_hi": "d0e0a0"},
	"bones": {"style": "dirt", "floor": "3a3027", "arena": "40302a", "moss": "4e4a2a",
		"wall_top": "5c4c3e", "wall_hi": "7a6652", "wall_lo": "33281f", "brick": "4a3c30", "mortar": "281e16",
		"face_hi": "6e5a48", "water": "3a3f26", "water_hi": "6a7040", "pit": "050403", "pit_hi": "2e241a",
		"lava": false, "banner": "7a3a24", "banner_hi": "e0d0b0"},
	# The mini boss's lair: walls of stacked bone over a dark floor.
	"ossuary": {"style": "slab", "floor": "2c2826", "arena": "36292a", "moss": "4a4436",
		"wall_top": "8a8070", "wall_hi": "b0a690", "wall_lo": "4e473c", "brick": "7a7060", "mortar": "3a342c",
		"face_hi": "a09680", "water": "2a2a30", "water_hi": "5a5a70", "pit": "050404", "pit_hi": "3a2e26",
		"lava": false, "banner": "5a2a2a", "banner_hi": "d8ccb0"},
	# Levels 4-6: glowing fungus and toxic pools, ice and slush, iron and lava.
	"fungal": {"style": "dirt", "floor": "2a2236", "arena": "32263c", "moss": "3fae8e",
		"wall_top": "3e3252", "wall_hi": "5a4a74", "wall_lo": "221a30", "brick": "342a46", "mortar": "1c1628",
		"face_hi": "524468", "water": "2c5a2a", "water_hi": "7ec84a", "pit": "04030a", "pit_hi": "2a1e3a",
		"lava": false, "banner": "6a2a7a", "banner_hi": "8af0c0"},
	"frost": {"style": "slab", "floor": "2c3a4c", "arena": "34405a", "moss": "8ab8d8",
		"wall_top": "5a7894", "wall_hi": "8ab0cc", "wall_lo": "34485e", "brick": "4c6680", "mortar": "283a4c",
		"face_hi": "7898b4", "water": "3a6a92", "water_hi": "b8e4ff", "pit": "040812", "pit_hi": "2a4a6e",
		"lava": false, "banner": "2a4a8a", "banner_hi": "d8f0ff"},
	"forge": {"style": "slab", "floor": "2a2624", "arena": "36282a", "moss": "3a302c",
		"wall_top": "4a423e", "wall_hi": "6a5e56", "wall_lo": "282220", "brick": "3e3632", "mortar": "1c1614",
		"face_hi": "5e524a", "water": "3a3020", "water_hi": "7a6a40", "pit": "b03c0c", "pit_hi": "ffb030",
		"lava": true, "banner": "8a4a1a", "banner_hi": "f0a030"},
	"throne": {"style": "slab", "floor": "2b1b22", "arena": "3a1c20", "moss": "4a2a2a",
		"wall_top": "4c2a32", "wall_hi": "6c3e48", "wall_lo": "2a141a", "brick": "3e222a", "mortar": "1e0c10",
		"face_hi": "643842", "water": "4a1018", "water_hi": "a0303a", "pit": "a8300c", "pit_hi": "ffc040",
		"lava": true, "banner": "a02020", "banner_hi": "f0c040"},
}
const TILE_SHEET := "res://assets/tiles/tiles_%s.png"


func _gen_tiles() -> void:
	for theme: String in THEMES:
		_gen_tile_sheet(theme, THEMES[theme])
	_gen_glow()


func _gen_tile_sheet(theme: String, t: Dictionary) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1337
	var img := _img(128, 80)
	var floor_base := Color(t["floor"])
	# Row 0: floor0..3, floor_shadow, wall_top, wall_face, void
	for v in 4:
		_floor_tile(img, v * 16, 0, floor_base, rng, v, t)
	_floor_tile(img, 64, 0, floor_base, rng, 0, t)
	for y in 4:
		for x in 16:
			var c := img.get_pixel(64 + x, y)
			img.set_pixel(64 + x, y, c.darkened(0.45 - y * 0.1))
	_wall_top(img, 80, 0, rng, t)
	_wall_face(img, 96, 0, rng, t)
	_rect(img, 112, 0, 16, 16, Color("0c0b12"))
	# Row 1: door, exit portal, spawn marker (debug), arena floor, spikes x3, water edge
	_door(img, 0, 16)
	_portal(img, 16, 16, floor_base)
	_floor_tile(img, 32, 16, floor_base, rng, 0, t)
	_rect(img, 38, 22, 4, 4, Color("a03040"))
	_floor_tile(img, 48, 16, Color(t["arena"]), rng, 1, t)
	for state in 3:
		_floor_tile(img, 64 + state * 16, 16, floor_base, rng, 0, t)
		_spikes(img, 64 + state * 16, 16, state)
	_water(img, 112, 16, 0, t)
	_water_lip(img, 112, 16, floor_base, t)
	# Row 2: water x3, chasm edge, chasm x3
	for f in 3:
		_water(img, f * 16, 32, f, t)
	_chasm(img, 48, 32, 0, t)
	_chasm_edge(img, 48, 32, floor_base, rng, t)
	for f in 3:
		_chasm(img, 64 + f * 16, 32, f, t)
	# Row 3: floor decor
	_decor_bones(img, 0, 48)
	_decor_skull(img, 16, 48)
	_decor_cobweb(img, 32, 48, false)
	_decor_cobweb(img, 48, 48, true)
	_decor_rubble(img, 64, 48, t, rng)
	_decor_puddle(img, 80, 48, t)
	_decor_moss(img, 96, 48, t, rng)
	_decor_cracks(img, 112, 48, floor_base, rng)
	# Row 4: wall decor
	for f in 3:
		_decor_torch(img, f * 16, 64, f)
	_decor_banner(img, 48, 64, t)
	_decor_chains(img, 64, 64)
	_decor_wall_crack(img, 80, 64, t)
	_save(img, TILE_SHEET % theme)


func _floor_tile(img: Image, ox: int, oy: int, base: Color, rng: RandomNumberGenerator, variant: int,
		t: Dictionary) -> void:
	var dirt: bool = t["style"] == "dirt"
	for y in 16:
		for x in 16:
			var n := rng.randf_range(-0.035, 0.035)
			var c := Color(base.r + n, base.g + n, base.b + n)
			if dirt:
				# Packed earth: blotchy, no seams.
				if rng.randf() < 0.08:
					c = c.darkened(0.18)
				elif rng.randf() < 0.05:
					c = c.lightened(0.1)
			else:
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
				_px(img, ox + rng.randi_range(1, 14), oy + rng.randi_range(9, 14), Color(t["moss"]))


func _wall_top(img: Image, ox: int, oy: int, rng: RandomNumberGenerator, t: Dictionary) -> void:
	var base := Color(t["wall_top"])
	for y in 16:
		for x in 16:
			var n := rng.randf_range(-0.02, 0.02)
			img.set_pixel(ox + x, oy + y, Color(base.r + n, base.g + n, base.b + n))
	_rect(img, ox, oy, 16, 1, Color(t["wall_hi"]))
	_rect(img, ox, oy + 15, 16, 1, Color(t["wall_lo"]))


func _wall_face(img: Image, ox: int, oy: int, rng: RandomNumberGenerator, t: Dictionary) -> void:
	var brick := Color(t["brick"])
	var mortar := Color(t["mortar"])
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
	_rect(img, ox, oy, 16, 1, Color(t["face_hi"]))


func _door(img: Image, ox: int, oy: int) -> void:
	for y in 16:
		for x in 16:
			var c := Color("6a4a2a") if x % 4 != 3 else Color("4a3018")
			img.set_pixel(ox + x, oy + y, c)
	_rect(img, ox, oy + 3, 16, 2, Color("3a3a48"))
	_rect(img, ox, oy + 11, 16, 2, Color("3a3a48"))
	_rect(img, ox, oy, 16, 1, Color("2a1a0e"))


func _portal(img: Image, ox: int, oy: int, floor_base: Color) -> void:
	var center := Vector2(7.5, 7.5)
	for y in 16:
		for x in 16:
			var d := Vector2(x, y).distance_to(center)
			var ang := atan2(y - center.y, x - center.x)
			var swirl := sin(ang * 3.0 + d * 0.9)
			var c := floor_base
			if d < 7.5:
				var t := 1.0 - d / 7.5
				c = Color("5a2a9a").lerp(Color("e0a0ff"), clampf(t * 0.8 + swirl * 0.2, 0.0, 1.0))
			img.set_pixel(ox + x, oy + y, c)


## Spike trap plate: 0 retracted (holes), 1 warning (tips), 2 up.
func _spikes(img: Image, ox: int, oy: int, state: int) -> void:
	var plate := Color("4c4a56")
	_rect(img, ox + 1, oy + 1, 14, 14, plate.darkened(0.35))
	_rect(img, ox + 2, oy + 2, 12, 12, plate)
	_rect(img, ox + 2, oy + 2, 12, 1, plate.lightened(0.2))
	var steel := Color("d8dce6")
	var shade := Color("8a8e9c")
	for hy in 3:
		for hx in 3:
			var cx := ox + 4 + hx * 4
			var cy := oy + 5 + hy * 4
			_rect(img, cx - 1, cy, 2, 1, Color("16141c"))
			if state == 1:
				_px(img, cx - 1, cy - 1, steel)
			elif state == 2:
				# A spike standing in the hole (3/4 view: rises upward).
				_rect(img, cx - 1, cy - 3, 2, 3, shade)
				_px(img, cx - 1, cy - 3, steel)
				_px(img, cx - 1, cy - 4, steel)
				_px(img, cx, cy - 2, steel)


func _water(img: Image, ox: int, oy: int, frame: int, t: Dictionary) -> void:
	var base := Color(t["water"])
	var hi := Color(t["water_hi"])
	for y in 16:
		for x in 16:
			var wave := sin((x + frame * 5.3) * 0.8 + y * 1.7) + sin((y * 1.3 - frame * 4.1) * 0.9 + x * 0.4)
			var c := base
			if wave > 1.45:
				c = hi
			elif wave > 1.1:
				c = base.lerp(hi, 0.45)
			elif wave < -1.4:
				c = base.darkened(0.2)
			img.set_pixel(ox + x, oy + y, c)


## Stone rim where floor meets water below it.
func _water_lip(img: Image, ox: int, oy: int, floor_base: Color, t: Dictionary) -> void:
	_rect(img, ox, oy, 16, 2, floor_base.darkened(0.1))
	_rect(img, ox, oy + 2, 16, 1, floor_base.darkened(0.45))
	_rect(img, ox, oy + 3, 16, 1, Color(t["water_hi"]).lerp(Color(t["water"]), 0.4))


func _chasm(img: Image, ox: int, oy: int, frame: int, t: Dictionary) -> void:
	var base := Color(t["pit"])
	var hi := Color(t["pit_hi"])
	var lava: bool = t["lava"]
	var rng := RandomNumberGenerator.new()
	rng.seed = 99 + frame
	for y in 16:
		for x in 16:
			var c := base
			if lava:
				var glow := sin(x * 0.7 + frame * 2.1) * 0.5 + sin(y * 0.9 - frame * 1.7 + x * 0.3) * 0.5
				c = base.lerp(hi, clampf(glow * 0.5 + 0.25, 0.0, 0.8))
			img.set_pixel(ox + x, oy + y, c)
	# Drifting specks (dust in the dark, bubbles in lava).
	for i in 5:
		var px := (i * 7 + frame * 3) % 16
		var py := (i * 5 + 3 - frame * 2 + 16) % 16
		_px(img, ox + px, oy + py, hi if not lava else Color("fff0a0"))


## The far side of a chasm: the rock face dropping away under the floor.
func _chasm_edge(img: Image, ox: int, oy: int, floor_base: Color, rng: RandomNumberGenerator, t: Dictionary) -> void:
	var rock := floor_base.darkened(0.35)
	var lava: bool = t["lava"]
	for y in 9:
		for x in 16:
			var c := rock.darkened(y * 0.07)
			if (x * 3 + y) % 5 == 0:
				c = c.darkened(0.25)
			if rng.randf() < 0.08:
				c = c.lightened(0.12)
			if lava and y >= 6:
				c = c.lerp(Color(t["pit_hi"]), 0.25 * (y - 5))
			img.set_pixel(ox + x, oy + y, c)
	_rect(img, ox, oy, 16, 1, floor_base.lightened(0.08))


func _decor_bones(img: Image, ox: int, oy: int) -> void:
	var bone := Color("d8d2bc")
	var shade := Color("9a947e")
	for i in 7:
		_px(img, ox + 4 + i, oy + 6 + i / 2, bone)
		_px(img, ox + 11 - i, oy + 6 + i / 2, shade if i % 2 == 0 else bone)
	_rect(img, ox + 3, oy + 5, 2, 2, bone)
	_rect(img, ox + 11, oy + 5, 2, 2, bone)
	_rect(img, ox + 3, oy + 9, 2, 1, shade)
	_rect(img, ox + 11, oy + 9, 2, 1, shade)


func _decor_skull(img: Image, ox: int, oy: int) -> void:
	var bone := Color("e2dcc6")
	_rect(img, ox + 5, oy + 5, 6, 5, bone)
	_rect(img, ox + 6, oy + 10, 4, 2, bone.darkened(0.2))
	_rect(img, ox + 6, oy + 7, 1, 2, Color("1a1420"))
	_rect(img, ox + 9, oy + 7, 1, 2, Color("1a1420"))
	_px(img, ox + 7, oy + 11, Color("1a1420"))
	_outline(img, Rect2i(ox, oy, 16, 16))


func _decor_cobweb(img: Image, ox: int, oy: int, mirror: bool) -> void:
	var web := Color(0.85, 0.85, 0.9, 0.55)
	for i in 12:
		var x := i if not mirror else 15 - i
		_px(img, ox + x, oy, web)  # along the top edge
	for i in 10:
		var x := 0 if not mirror else 15
		_px(img, ox + x, oy + i, web)  # along the side
	for i in 9:
		var x := i if not mirror else 15 - i
		_px(img, ox + x, oy + i, web)  # diagonal
	for r in [4, 8]:
		for a in 10:
			var ang := PI * 0.5 * a / 9.0
			var x := int(round(cos(ang) * r))
			var y := int(round(sin(ang) * r))
			_px(img, ox + (x if not mirror else 15 - x), oy + y, web)


func _decor_rubble(img: Image, ox: int, oy: int, t: Dictionary, rng: RandomNumberGenerator) -> void:
	var stone := Color(t["wall_top"])
	for i in 5:
		var x := ox + rng.randi_range(2, 11)
		var y := oy + rng.randi_range(4, 12)
		var w := rng.randi_range(2, 3)
		_rect(img, x, y, w, 2, stone)
		_rect(img, x, y, w, 1, stone.lightened(0.25))
	_outline(img, Rect2i(ox, oy, 16, 16), Color(0.05, 0.04, 0.08, 0.8))


func _decor_puddle(img: Image, ox: int, oy: int, t: Dictionary) -> void:
	var water := Color(t["water"])
	for y in range(5, 12):
		var half := 6 - absi(y - 8)
		_rect(img, ox + 8 - half, oy + y, half * 2, 1, Color(water, 0.85))
	_rect(img, ox + 5, oy + 7, 3, 1, Color(t["water_hi"]))


func _decor_moss(img: Image, ox: int, oy: int, t: Dictionary, rng: RandomNumberGenerator) -> void:
	var moss := Color(t["moss"])
	for i in 22:
		var a := rng.randf() * TAU
		var d := rng.randf() * 5.5
		_px(img, ox + 8 + int(cos(a) * d), oy + 8 + int(sin(a) * d * 0.7),
			moss.lightened(0.15) if i % 4 == 0 else moss)


func _decor_cracks(img: Image, ox: int, oy: int, floor_base: Color, rng: RandomNumberGenerator) -> void:
	var dark := floor_base.darkened(0.55)
	var x := 3
	var y := 3
	for i in 12:
		_px(img, ox + x, oy + y, dark)
		x = clampi(x + 1, 0, 15)
		if rng.randf() < 0.5:
			y = clampi(y + 1, 0, 15)
	_px(img, ox + 8, oy + 7, dark)
	_px(img, ox + 9, oy + 9, dark)
	_px(img, ox + 9, oy + 10, dark)


## Wall-mounted torch (drawn over a wall face tile): bracket, handle, flame.
func _decor_torch(img: Image, ox: int, oy: int, frame: int) -> void:
	_rect(img, ox + 6, oy + 10, 4, 2, Color("2a2a30"))
	_rect(img, ox + 7, oy + 6, 2, 5, Color("6a4a2a"))
	_px(img, ox + 7, oy + 6, Color("8a6a3a"))
	var sway: int = [0, 1, -1][frame]
	var tall: int = [0, 1, 0][frame]
	_rect(img, ox + 6 + maxi(sway, 0), oy + 2 - tall, 4 - absi(sway), 4 + tall, Color("ff8a2a"))
	_rect(img, ox + 7, oy + 3 - tall, 2, 3 + tall, Color("ffd04a"))
	_px(img, ox + 7 + maxi(sway, 0), oy + 1 - tall, Color("ffb040"))
	_px(img, ox + 8, oy + 4, Color("fff4c0"))


func _decor_banner(img: Image, ox: int, oy: int, t: Dictionary) -> void:
	var cloth := Color(t["banner"])
	var trim := Color(t["banner_hi"])
	_rect(img, ox + 3, oy + 1, 10, 1, Color("5a4a3a"))
	_rect(img, ox + 4, oy + 2, 8, 10, cloth)
	_rect(img, ox + 4, oy + 2, 1, 10, cloth.darkened(0.25))
	_rect(img, ox + 5, oy + 12, 2, 2, cloth)
	_rect(img, ox + 9, oy + 12, 2, 2, cloth)
	_rect(img, ox + 7, oy + 5, 2, 4, trim)
	_rect(img, ox + 6, oy + 6, 4, 1, trim)


func _decor_chains(img: Image, ox: int, oy: int) -> void:
	for x in [4, 11]:
		for y in range(0, 12):
			_px(img, ox + x + (y % 2), oy + y, Color("7a7a86") if y % 2 == 0 else Color("4a4a56"))
	_rect(img, ox + 3, oy + 12, 3, 2, Color("5a5a66"))
	_rect(img, ox + 10, oy + 12, 3, 2, Color("5a5a66"))


func _decor_wall_crack(img: Image, ox: int, oy: int, t: Dictionary) -> void:
	var dark := Color(t["mortar"]).darkened(0.4)
	var x := 9
	for y in range(1, 13):
		_px(img, ox + x, oy + y, dark)
		if y % 3 == 0:
			x += 1 if y % 2 == 0 else -1
			_px(img, ox + x + 1, oy + y, dark)


## Soft white light blob, tinted and blended additively in game (torch light).
func _gen_glow() -> void:
	var img := _img(64, 64)
	for y in 64:
		for x in 64:
			var d := Vector2(x + 0.5, y + 0.5).distance_to(Vector2(32, 32)) / 32.0
			var a := clampf(1.0 - d, 0.0, 1.0)
			a = a * a
			# Banded (dithered-looking) falloff keeps it pixel-art friendly.
			a = floorf(a * 6.0) / 6.0
			img.set_pixel(x, y, Color(1, 1, 1, a))
	_save(img, "res://assets/sprites/fx/glow.png")


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
	var img := _img(256, ENEMY_ROWS.size() * 32)
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
				"barrel":
					_draw_barrel(img, ox, oy, col)
				"urn":
					_draw_urn(img, ox, oy, col)
				"nest":
					_draw_nest(img, ox, oy, col)
				"bat":
					_draw_bat(img, ox, oy, col)
				"drowned":
					_draw_drowned(img, ox, oy, col)
				"bone_archer":
					_draw_bone_archer(img, ox, oy, col)
				"revenant":
					_draw_revenant(img, ox, oy, col)
				"bone_pile":
					_draw_bone_pile(img, ox, oy, col)
				"sporecap":
					_draw_sporecap(img, ox, oy, col)
				"frost_boar":
					_draw_frost_boar(img, ox, oy, col)
				"salamander":
					_draw_salamander(img, ox, oy, col)
				"imp":
					_draw_imp(img, ox, oy, col)
			_outline(img, Rect2i(ox, oy, 32, 32))
			if ENEMY_ROWS[row] in FLYERS and (col < 4 or ENEMY_ROWS[row] == "imp"):
				_rect(img, ox + 13, oy + 23, 6, 1, Color(0, 0, 0, 0.3))
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


## Explosive barrel: red staves, iron hoops, a hazard mark. One frame.
func _draw_barrel(img: Image, ox: int, oy: int, col: int) -> void:
	if col > 0:
		return
	var wood := Color("b8402a")
	var dark := Color("7a2418")
	_rect(img, ox + 11, oy + 12, 10, 12, wood)
	_rect(img, ox + 12, oy + 11, 8, 1, wood.lightened(0.15))
	_rect(img, ox + 11, oy + 12, 2, 12, dark)
	_rect(img, ox + 19, oy + 12, 2, 12, wood.lightened(0.12))
	for y in [13, 21]:
		_rect(img, ox + 11, oy + y, 10, 1, Color("3a3440"))
	_rect(img, ox + 15, oy + 15, 2, 4, Color("f2d24a"))
	_px(img, ox + 15, oy + 20, Color("f2d24a"))
	_px(img, ox + 16, oy + 20, Color("f2d24a"))
	_rect(img, ox + 12, oy + 11, 8, 1, Color("5a2a1a"))


## Clay urn: breaks for loot. One frame.
func _draw_urn(img: Image, ox: int, oy: int, col: int) -> void:
	if col > 0:
		return
	var clay := Color("b07a4a")
	var dark := Color("7a4e2c")
	_rect(img, ox + 12, oy + 16, 9, 8, clay)
	_rect(img, ox + 13, oy + 15, 7, 1, clay)
	_rect(img, ox + 14, oy + 13, 5, 2, clay.darkened(0.1))
	_rect(img, ox + 13, oy + 12, 7, 1, clay.lightened(0.1))
	_rect(img, ox + 12, oy + 16, 2, 8, dark)
	_rect(img, ox + 12, oy + 19, 9, 1, Color("5a8a9a"))
	_px(img, ox + 18, oy + 17, clay.lightened(0.35))


## Spawner nest: a mound of bones and flesh around a glowing core.
## Frames 0-3 idle pulse, 4-5 spawning.
func _draw_nest(img: Image, ox: int, oy: int, col: int) -> void:
	if col > 5:
		return
	var flesh := Color("6a2a3e")
	var dark := Color("40182a")
	var bone := Color("d8d0b8")
	var bulge := 1 if col >= 4 else 0
	for y in range(12 - bulge, 24):
		var half := 9 - absi(y - 19) / 2 + (bulge if y < 18 else 0)
		_rect(img, ox + 16 - half, oy + y, half * 2, 1, flesh if y < 21 else dark)
	for b in [[8, 20], [21, 19], [11, 15], [20, 14], [15, 13]]:
		_rect(img, ox + b[0], oy + b[1], 3, 1, bone)
		_px(img, ox + b[0], oy + b[1] - 1, bone)
	var glow := [0.0, 0.35, 0.7, 0.35, 1.0, 0.8][col] as float
	var core := Color("e04a8a").lerp(Color("ffd0f0"), glow)
	_rect(img, ox + 14, oy + 16 - bulge, 4, 3, core)
	_px(img, ox + 15, oy + 17 - bulge, Color.WHITE if glow > 0.6 else core.lightened(0.3))


## Draws `rows` of [y, x from, x to] (cell coordinates) and their mirror
## image around the cell's middle (x -> 31 - x): wings.
func _mirrored_rows(img: Image, ox: int, oy: int, rows: Array, c: Color) -> void:
	for r: Array in rows:
		var w := int(r[2]) - int(r[1]) + 1
		_rect(img, ox + int(r[1]), oy + int(r[0]), w, 1, c)
		_rect(img, ox + 31 - int(r[2]), oy + int(r[0]), w, 1, c)


## Bat (Crypt Entrance): a furry little body on wide wings, flying over its
## shadow. Frames 0-3 flap: up, level, down, level.
func _draw_bat(img: Image, ox: int, oy: int, col: int) -> void:
	if col > 3:
		return
	var fur := Color("4a3048")
	var wing := Color("70487e")
	var flap: int = [0, 1, 2, 1][col]
	var y0 := 11 + (1 if flap == 2 else 0)
	var rows: Array = [
		[[y0 - 3, 8, 9], [y0 - 2, 8, 11], [y0 - 1, 9, 13], [y0, 10, 13], [y0 + 1, 11, 13], [y0 + 2, 12, 13]],
		[[y0 + 2, 8, 13], [y0 + 3, 7, 13], [y0 + 4, 8, 9], [y0 + 4, 11, 13]],
		[[y0 + 3, 11, 13], [y0 + 4, 9, 13], [y0 + 5, 8, 12], [y0 + 6, 7, 10], [y0 + 7, 7, 8]],
	][flap]
	_mirrored_rows(img, ox, oy, rows, wing)
	_rect(img, ox + 14, oy + y0, 4, 7, fur)
	_px(img, ox + 14, oy + y0 - 1, fur)
	_px(img, ox + 17, oy + y0 - 1, fur)
	_rect(img, ox + 15, oy + y0 + 4, 2, 2, Color("6a4a60"))
	_px(img, ox + 15, oy + y0 + 1, Color("f04040"))
	_px(img, ox + 16, oy + y0 + 1, Color("f04040"))
	_px(img, ox + 15, oy + y0 + 7, Color("2a1a28"))
	_px(img, ox + 16, oy + y0 + 7, Color("2a1a28"))


## Drowned (Flooded Halls): a hunched, waterlogged corpse, weed for hair,
## reaching out. Frames 0-3 shamble; 4-5 swim (legs lost in a wake of foam).
func _draw_drowned(img: Image, ox: int, oy: int, col: int) -> void:
	var skin := Color("7fa89a")
	var skin_dark := Color("587e72")
	var rags := Color("3e4e60")
	var weed := Color("2e5a36")
	var swim := col >= 4
	var w := _walk(col)
	var b := w.x if not swim else col - 4
	if swim:
		_rect(img, ox + 11, oy + 21, 10, 1, Color("c8ecf4"))
		_rect(img, ox + 10, oy + 22, 3, 1, Color("9ad4e4"))
		_rect(img, ox + 19, oy + 22, 3, 1, Color("9ad4e4"))
		_px(img, ox + 9 + (col - 4) * 2, oy + 20, Color("c8ecf4"))
		_px(img, ox + 22 - (col - 4) * 2, oy + 20, Color("c8ecf4"))
	else:
		_rect(img, ox + 13, oy + 19, 2, 5 - maxi(w.y, 0), rags.darkened(0.3))
		_rect(img, ox + 17, oy + 19, 2, 5 - maxi(-w.y, 0), rags.darkened(0.3))
	_rect(img, ox + 12, oy + 12 + b, 8, 8 if not swim else 9 - b, rags)
	_rect(img, ox + 14, oy + 14 + b, 2, 2, skin_dark)
	_px(img, ox + 18, oy + 17 + b, skin_dark)
	_rect(img, ox + 10, oy + 13 + b, 2, 4, skin_dark)
	_rect(img, ox + 19, oy + 13 + b, 4, 2, skin)
	_px(img, ox + 22, oy + 15 + b, skin_dark)
	_rect(img, ox + 13, oy + 6 + b, 6, 6, skin)
	_rect(img, ox + 13, oy + 11 + b, 6, 1, skin_dark)
	_rect(img, ox + 12, oy + 5 + b, 8, 2, weed)
	_rect(img, ox + 12, oy + 7 + b, 1, 5, weed)
	_px(img, ox + 14, oy + 7 + b, weed)
	_px(img, ox + 16, oy + 8 + b, Color("e0fff0"))
	_px(img, ox + 18, oy + 8 + b, Color("e0fff0"))
	_px(img, ox + 17, oy + 10 + b, Color("2a3a3a"))
	_px(img, ox + 21, oy + 16 + b, Color("9ad4e4"))


## Bone archer (Bone Pits): a skeleton in a tattered red hood with a bow.
## Frames 0-3 walk; 4 draws (an arrow nocked, its tip glinting), 5 looses.
func _draw_bone_archer(img: Image, ox: int, oy: int, col: int) -> void:
	var bone := Color("e8e4d4")
	var shade := Color("a8a494")
	var hood := Color("8a2a2a")
	var hood_dark := Color("5e1a1c")
	var wood := Color("8a5a2a")
	var string := Color("d8d0c0")
	var w := _walk(col)
	var b := w.x
	_rect(img, ox + 14, oy + 19, 1, 5 - maxi(w.y, 0), bone)
	_rect(img, ox + 17, oy + 19, 1, 5 - maxi(-w.y, 0), bone)
	_rect(img, ox + 13, oy + 18 + b, 6, 1, shade)
	_rect(img, ox + 15, oy + 12 + b, 2, 6, bone)
	_rect(img, ox + 13, oy + 13 + b, 6, 1, bone)
	_rect(img, ox + 13, oy + 15 + b, 6, 1, bone)
	_rect(img, ox + 11, oy + 8 + b, 2, 7, hood_dark)
	_rect(img, ox + 12, oy + 5 + b, 8, 3, hood)
	_rect(img, ox + 12, oy + 8 + b, 1, 4, hood)
	_rect(img, ox + 13, oy + 7 + b, 6, 5, bone)
	_px(img, ox + 15, oy + 9 + b, EYE)
	_px(img, ox + 17, oy + 9 + b, EYE)
	_rect(img, ox + 14, oy + 11 + b, 4, 1, shade)
	_rect(img, ox + 17, oy + 13 + b, 4, 1, bone)
	# The bow: a stave with curled tips, its string pulled back on the draw.
	_rect(img, ox + 21, oy + 9 + b, 1, 9, wood)
	_px(img, ox + 20, oy + 8 + b, wood)
	_px(img, ox + 20, oy + 18 + b, wood)
	if col == 4:
		for k in 5:
			_px(img, ox + 19 - k, oy + 9 + k + b, string)
			_px(img, ox + 19 - k, oy + 17 - k + b, string)
		_rect(img, ox + 15, oy + 13 + b, 8, 1, Color("c8a070"))
		_px(img, ox + 23, oy + 13 + b, Color("ff3d8b"))
	else:
		_rect(img, ox + 19, oy + 9 + b, 1, 9, string)


## Revenant (the Ossuary): an armoured skeleton warrior with a shield and a
## notched sword, eyes burning green. Frames 0-3 walk.
func _draw_revenant(img: Image, ox: int, oy: int, col: int) -> void:
	if col > 3:
		return
	var bone := Color("dcd8c8")
	var shade := Color("9c988a")
	var iron := Color("5a6270")
	var iron_dark := Color("3c424e")
	var glow := Color("7af0b0")
	var w := _walk(col)
	var b := w.x
	_rect(img, ox + 13, oy + 19, 2, 5 - maxi(w.y, 0), iron_dark)
	_rect(img, ox + 17, oy + 19, 2, 5 - maxi(-w.y, 0), iron_dark)
	_rect(img, ox + 12, oy + 11 + b, 8, 8, iron)
	_rect(img, ox + 12, oy + 11 + b, 8, 1, iron.lightened(0.25))
	_rect(img, ox + 15, oy + 12 + b, 2, 6, iron_dark)
	_rect(img, ox + 12, oy + 18 + b, 8, 1, iron_dark)
	_rect(img, ox + 13, oy + 5 + b, 6, 6, bone)
	_rect(img, ox + 12, oy + 4 + b, 8, 3, iron)
	_px(img, ox + 16, oy + 3 + b, iron_dark)
	_px(img, ox + 15, oy + 7 + b, glow)
	_px(img, ox + 17, oy + 7 + b, glow)
	_rect(img, ox + 14, oy + 10 + b, 4, 1, shade)
	_rect(img, ox + 8, oy + 12 + b, 4, 7, iron_dark)
	_rect(img, ox + 9, oy + 13 + b, 2, 5, Color("7a3a2a"))
	_rect(img, ox + 20, oy + 13 + b, 2, 2, bone)
	_rect(img, ox + 22, oy + 7 + b, 1, 8, Color("c8ccd4"))
	_px(img, ox + 22, oy + 9 + b, Color("7a7e88"))
	_rect(img, ox + 21, oy + 14 + b, 3, 1, iron_dark)


## Bone pile: what a revenant leaves behind, eyes still smouldering. Frame 0
## lies still; 4-5 rattle, eyes blazing, just before it gets back up.
func _draw_bone_pile(img: Image, ox: int, oy: int, col: int) -> void:
	if col in [1, 2, 3]:
		return
	var bone := Color("dcd8c8")
	var shade := Color("9c988a")
	var iron := Color("5a6270")
	var rattle := col >= 4
	var j := (1 if col == 5 else -1) if rattle else 0
	_rect(img, ox + 10, oy + 21, 12, 3, shade)
	_rect(img, ox + 11, oy + 20, 10, 1, bone)
	for k in 5:
		_rect(img, ox + 10 + k * 2 + (j if k % 2 == 0 else 0), oy + 19 + k % 2, 2, 1, bone)
	_rect(img, ox + 8, oy + 22, 8, 1, Color("c8ccd4"))
	var sy := 17 - (1 if rattle else 0)
	_rect(img, ox + 14 + j, oy + sy, 5, 4, bone)
	_rect(img, ox + 14 + j, oy + sy - 1, 5, 2, iron)
	var eye := Color("b0ffd8") if rattle else Color("4ab884")
	_px(img, ox + 15 + j, oy + sy + 2, eye)
	_px(img, ox + 17 + j, oy + sy + 2, eye)


## Sporecap (Fungal Caverns): a waddling mushroom, a big spotted pink cap on a
## pale stalk with a face. Frames 0-3 waddle.
func _draw_sporecap(img: Image, ox: int, oy: int, col: int) -> void:
	if col > 3:
		return
	var cap := Color("d8487e")
	var cap_dark := Color("9a2a5a")
	var spot := Color("ffd0e6")
	var stalk := Color("e8dcc4")
	var stalk_dark := Color("b8a88a")
	var w := _walk(col)
	var b := w.x
	_rect(img, ox + 13, oy + 22, 2, 2 - maxi(w.y, 0), stalk_dark)
	_rect(img, ox + 17, oy + 22, 2, 2 - maxi(-w.y, 0), stalk_dark)
	_rect(img, ox + 12, oy + 15 + b, 8, 7 - b, stalk)
	_rect(img, ox + 12, oy + 20, 8, 1, stalk_dark)
	_px(img, ox + 15, oy + 17 + b, EYE)
	_px(img, ox + 17, oy + 17 + b, EYE)
	_rect(img, ox + 15, oy + 19, 3, 1, stalk_dark)
	var halves := [3, 5, 6, 7, 7, 8, 8, 8]
	for y in 8:
		var half: int = halves[y]
		_rect(img, ox + 16 - half, oy + 8 + y + b, half * 2, 1, cap)
	_rect(img, ox + 8, oy + 15 + b, 16, 1, cap_dark)
	for sp: Array in [[11, 12], [14, 10], [18, 9], [20, 12], [16, 13]]:
		_rect(img, ox + int(sp[0]), oy + int(sp[1]) + b, 2, 1, spot)


## Frost boar (Frozen Vaults): a shaggy blue-grey boar with an icy mane and
## white tusks. Frames 0-3 trot; 4 lines up a charge (head down, pawing,
## breath steaming), 5 charges (legs stretched out).
func _draw_frost_boar(img: Image, ox: int, oy: int, col: int) -> void:
	var fur := Color("7e98b4")
	var fur_dark := Color("54708e")
	var mane := Color("dcefff")
	var tusk := Color("f4f0e0")
	var w := _walk(col)
	var b := w.x if col < 4 else 0
	var legs := [7, 10, 17, 20]
	for k in 4:
		var lift := 0
		if col < 4:
			lift = maxi(w.y if k % 2 == 0 else -w.y, 0)
		elif col == 4 and k == 3:
			lift = 2  # pawing the ground
		var lx: int = legs[k]
		if col == 5:
			lx += -1 if k < 2 else 1
		_rect(img, ox + lx, oy + 20, 2, 4 - lift, fur_dark)
	_rect(img, ox + 7, oy + 12 + b, 14, 8, fur)
	_rect(img, ox + 6, oy + 13 + b, 16, 6, fur)
	_rect(img, ox + 7, oy + 18 + b, 14, 2, fur_dark)
	for k in 6:
		_rect(img, ox + 8 + k * 2, oy + 10 + b + k % 2, 1, 3 - k % 2, mane)
	var hy := 13 + b + (1 if col == 4 else 0)
	_rect(img, ox + 20, oy + hy, 5, 5, fur)
	_rect(img, ox + 24, oy + hy + 2, 2, 3, fur_dark)
	_px(img, ox + 22, oy + hy + 1, EYE)
	_px(img, ox + 21, oy + hy - 1, fur_dark)
	_px(img, ox + 25, oy + hy + 4, tusk)
	_px(img, ox + 26, oy + hy + 3, tusk)
	_px(img, ox + 26, oy + hy + 2, tusk)
	if col == 4:
		_px(img, ox + 27, oy + hy + 1, Color("e8f4ff"))
		_px(img, ox + 28, oy + hy, Color("e8f4ff"))


## Salamander (Molten Forge): a long fire lizard with a glowing belly.
## Frames 0-3 crawl; 4 winds up (head up, fire in its mouth), 5 spits.
func _draw_salamander(img: Image, ox: int, oy: int, col: int) -> void:
	var skin := Color("d8582a")
	var dark := Color("983418")
	var glow := Color("ffc040")
	var hot := Color("fff0a0")
	var crawl: int = [0, 1, 0, -1, 0, 0][col]
	_rect(img, ox + 4, oy + 19, 5, 2, skin)
	_px(img, ox + 3, oy + 18, skin)
	_px(img, ox + 3, oy + 17, dark)
	_rect(img, ox + 8, oy + 16, 14, 5, skin)
	_rect(img, ox + 9, oy + 20, 12, 1, glow)
	for k in 4:
		_px(img, ox + 10 + k * 3, oy + 17 + k % 2, glow)
	for k in 4:
		var lx: int = [9, 12, 17, 20][k]
		var step := crawl if k % 2 == 0 else -crawl
		_rect(img, ox + lx + step, oy + 21, 2, 3, dark)
	var hy := 15 - (2 if col >= 4 else 0)
	_rect(img, ox + 21, oy + hy, 6, 4, skin)
	_rect(img, ox + 21, oy + hy + 3, 6, 1, dark)
	_px(img, ox + 24, oy + hy + 1, EYE)
	if col == 4:
		_rect(img, ox + 25, oy + hy + 2, 2, 2, glow)
		_px(img, ox + 26, oy + hy + 2, hot)
	elif col == 5:
		_rect(img, ox + 27, oy + hy + 1, 2, 2, hot)


## Imp (Demon's Throne): a little red devil with horns, bat wings and a barbed
## tail, flying over its shadow. Frames 0-3 hover; 4-5 blink away (sparkling).
func _draw_imp(img: Image, ox: int, oy: int, col: int) -> void:
	var skin := Color("c8303c")
	var dark := Color("8a1a28")
	var wing := Color("5a1a2a")
	var horn := Color("f0e0c0")
	var flap: int = [0, 1, 2, 1, 0, 2][col]
	var y0: int = 7 + [0, 0, 1, 1, 0, 1][col]
	var rows: Array = [
		[[y0 + 1, 8, 9], [y0 + 2, 8, 12], [y0 + 3, 9, 12], [y0 + 4, 10, 12]],
		[[y0 + 4, 7, 12], [y0 + 5, 7, 12], [y0 + 6, 9, 12]],
		[[y0 + 6, 10, 12], [y0 + 7, 8, 12], [y0 + 8, 8, 10]],
	][flap]
	_mirrored_rows(img, ox, oy, rows, wing)
	_rect(img, ox + 13, oy + y0 + 6, 6, 6, skin)
	_rect(img, ox + 14, oy + y0 + 8, 4, 3, dark)
	_rect(img, ox + 14, oy + y0 + 12, 1, 2, dark)
	_rect(img, ox + 17, oy + y0 + 12, 1, 2, dark)
	_rect(img, ox + 13, oy + y0, 6, 6, skin)
	_px(img, ox + 13, oy + y0 - 1, horn)
	_px(img, ox + 12, oy + y0 - 2, horn)
	_px(img, ox + 18, oy + y0 - 1, horn)
	_px(img, ox + 19, oy + y0 - 2, horn)
	_px(img, ox + 15, oy + y0 + 2, Color("ffe040"))
	_px(img, ox + 17, oy + y0 + 2, Color("ffe040"))
	_rect(img, ox + 15, oy + y0 + 4, 3, 1, dark)
	for tp: Array in [[19, 10], [20, 11], [21, 11], [22, 10], [22, 9], [23, 10]]:
		_px(img, ox + int(tp[0]), oy + y0 + int(tp[1]), dark)
	if col >= 4:
		for sp: Array in [[10, 3], [21, 1], [11, 12], [20, 13], [16, -3]]:
			_px(img, ox + int(sp[0]) + (col - 4), oy + y0 + int(sp[1]), Color("ff9ac4"))


# --- props (chests, shrines: node sprites) ---------------------------------------------

func _gen_props() -> void:
	var chest := _img(32, 16)
	for f in 2:
		_draw_chest(chest, f * 16, f == 1)
		_outline(chest, Rect2i(f * 16, 0, 16, 16))
	_save(chest, "res://assets/sprites/props/chest.png")
	var shrine := _img(32, 24)
	for f in 2:
		_draw_shrine(shrine, f * 16, f == 1)
		_outline(shrine, Rect2i(f * 16, 0, 16, 24))
	_save(shrine, "res://assets/sprites/props/shrine.png")


func _draw_chest(img: Image, ox: int, open: bool) -> void:
	var wood := Color("8a5a2a")
	var gold := Color("f2c84a")
	_rect(img, ox + 2, 8, 12, 7, wood)
	_rect(img, ox + 2, 8, 12, 1, wood.lightened(0.2))
	_rect(img, ox + 2, 14, 12, 1, wood.darkened(0.3))
	_rect(img, ox + 2, 8, 1, 7, gold)
	_rect(img, ox + 13, 8, 1, 7, gold)
	if open:
		_rect(img, ox + 3, 7, 10, 2, Color("ffe890"))
		_rect(img, ox + 4, 6, 3, 1, Color("fff8d0"))
		_rect(img, ox + 2, 2, 12, 4, wood.darkened(0.15))
		_rect(img, ox + 2, 2, 12, 1, gold)
	else:
		_rect(img, ox + 2, 4, 12, 4, wood.lightened(0.08))
		_rect(img, ox + 2, 4, 12, 1, wood.lightened(0.3))
		_rect(img, ox + 2, 7, 12, 1, gold)
		_rect(img, ox + 7, 7, 2, 3, gold.darkened(0.2))
		_px(img, ox + 7, 9, Color("2a1a0e"))


func _draw_shrine(img: Image, ox: int, used: bool) -> void:
	var stone := Color("7a7890")
	_rect(img, ox + 3, 17, 10, 6, stone)
	_rect(img, ox + 3, 17, 10, 1, stone.lightened(0.25))
	_rect(img, ox + 2, 22, 12, 2, stone.darkened(0.3))
	_rect(img, ox + 5, 14, 6, 3, stone.darkened(0.1))
	var orb := Color(0.35, 0.35, 0.4) if used else Color.WHITE
	for y in range(3, 12):
		var half := 3 - absi(y - 7) / 2
		_rect(img, ox + 8 - half, y, half * 2, 1, orb)
	if used:
		_px(img, ox + 7, 6, Color(0.15, 0.15, 0.2))
		_px(img, ox + 8, 7, Color(0.15, 0.15, 0.2))
		_px(img, ox + 8, 8, Color(0.15, 0.15, 0.2))
	else:
		_px(img, ox + 6, 5, Color(1, 1, 1))
		_rect(img, ox + 9, 8, 1, 2, Color(0.8, 0.8, 0.85))


# --- fx atlas: projectiles (row 0, pointing right) and pickups (row 1) ----------------

func _gen_fx_atlas() -> void:
	var img := _img(128, 64)
	for i in PROJECTILES.size():
		_draw_projectile(img, i * 16, 0, PROJECTILES[i])
	for i in PICKUPS.size():
		_draw_pickup(img, i * 16, 16, PICKUPS[i])
	_draw_shard(img, 0, 48)
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
		"orb":  # holy: pale gold, never mistaken for enemy fire
			_rect(img, ox + 5, oy + 5, 6, 6, Color("ffe68a"))
			_rect(img, ox + 6, oy + 6, 4, 4, Color("fff6cc"))
			_px(img, ox + 7, oy + 7, Color("ffffff"))
		"spit":  # enemy shots are all hot pink (see FxLayer.DANGER)
			_rect(img, ox + 3, oy + 7, 3, 2, Color("a8185a"))
			_rect(img, ox + 6, oy + 5, 5, 5, Color("ff3d8b"))
			_rect(img, ox + 7, oy + 6, 3, 3, Color("ff9ac4"))
			_px(img, ox + 8, oy + 7, Color("ffffff"))
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
		"fire":  # the boss's fireballs: a bigger hot pink orb
			_rect(img, ox + 5, oy + 4, 7, 8, Color("e0205a"))
			_rect(img, ox + 4, oy + 5, 9, 6, Color("e0205a"))
			_rect(img, ox + 5, oy + 5, 7, 6, Color("ff3d8b"))
			_rect(img, ox + 6, oy + 6, 5, 4, Color("ff9ac4"))
			_rect(img, ox + 7, oy + 7, 3, 2, Color("ffffff"))
	_outline(img, Rect2i(ox, oy, 16, 16))


## The bone archers' shot (row 3): a hot pink shard - every enemy shot is hot pink.
func _draw_shard(img: Image, ox: int, oy: int) -> void:
	_rect(img, ox + 3, oy + 7, 8, 1, Color("a8185a"))
	_rect(img, ox + 2, oy + 6, 2, 1, Color("ff3d8b"))
	_rect(img, ox + 2, oy + 8, 2, 1, Color("ff3d8b"))
	_rect(img, ox + 10, oy + 6, 3, 3, Color("ff3d8b"))
	_px(img, ox + 13, oy + 7, Color("ff9ac4"))
	_px(img, ox + 11, oy + 7, Color("ffffff"))
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
## Button icons in the private-use range from U+E000 (see PlayerInput.glyph()),
## 8 px tall so they sit inline with text: Xbox, PlayStation, Nintendo, mouse.
const ICON_FIRST := 0xE000
const FONT_ICONS := [
	["disc", "A"], ["disc", "B"], ["disc", "X"], ["disc", "Y"], ["pill", "LB"], ["pill", "RB"],
	["pill", "LT"], ["pill", "RT"], ["menu", ""], ["view", ""],
	["ps_cross", ""], ["ps_circle", ""], ["ps_square", ""], ["ps_triangle", ""], ["pill", "L1"], ["pill", "R1"],
	["pill", "L2"], ["pill", "R2"], ["menu", ""], ["view", ""],
	["disc", "A"], ["disc", "B"], ["disc", "X"], ["disc", "Y"], ["pill", "L"], ["pill", "R"],
	["pill", "ZL"], ["pill", "ZR"], ["disc", "+"], ["disc", "-"],
	["mouse", "L"], ["mouse", "R"],
]
## 3x5 letters knocked out of the icons; each row's bits: 4 left, 2 middle, 1 right.
const MINI_LETTERS := {
	"A": [2, 5, 7, 5, 5], "B": [6, 5, 6, 5, 6], "X": [5, 5, 2, 5, 5], "Y": [5, 5, 2, 2, 2],
	"L": [4, 4, 4, 4, 7], "R": [6, 5, 6, 5, 5], "T": [7, 2, 2, 2, 2], "Z": [7, 1, 2, 4, 7],
	"1": [2, 6, 2, 2, 7], "2": [6, 1, 2, 4, 7], "+": [0, 2, 7, 2, 0], "-": [0, 0, 7, 0, 0],
}
const PS_TRIANGLE: Array[String] = ["...#...", "..#.#..", "..#.#..", ".#...#.", ".#...#.", "#.....#", "#######"]
const MOUSE: Array[String] = [".###.", "#?#?#", "#?#?#", "#####", "#...#", "#...#", ".###."]


func _gen_font() -> void:
	var img := _img(128, 96)
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
	# Button icons, packed in rows under the letters.
	var x := 0
	var y := 6 * FONT_CELL.y + 2  # under the 6 rows of letters
	for k in FONT_ICONS.size():
		var icon := _font_icon(FONT_ICONS[k][0], FONT_ICONS[k][1])
		if x + icon.get_width() > img.get_width():
			x = 0
			y += 10
		img.blit_rect(icon, Rect2i(Vector2i.ZERO, icon.get_size()), Vector2i(x, y))
		chars.append("char id=%d x=%d y=%d width=%d height=8 xoffset=0 yoffset=0 xadvance=%d page=0 chnl=15" % [
			ICON_FIRST + k, x, y, icon.get_width(), icon.get_width() + 1])
		x += icon.get_width() + 1
	_save(img, "res://assets/fonts/pixel5x8.png")
	var fnt := PackedStringArray([
		'info face="Pixel5x8" size=8 bold=0 italic=0 charset="" unicode=1 stretchH=100 smooth=0 aa=1 padding=0,0,0,0 spacing=1,1',
		"common lineHeight=10 base=7 scaleW=128 scaleH=96 pages=1 packed=0",
		'page id=0 file="pixel5x8.png"',
		"chars count=%d" % chars.size(),
	])
	fnt.append_array(chars)
	var file := FileAccess.open("res://assets/fonts/pixel5x8.fnt", FileAccess.WRITE)
	file.store_string("\n".join(fnt) + "\n")


## One button icon, white on transparent, 8 px tall.
func _font_icon(kind: String, text: String) -> Image:
	var width := 7
	if kind == "pill":
		width = 3 + 4 * text.length()
	elif kind == "mouse":
		width = 5
	var icon := Image.create_empty(width, 8, false, Image.FORMAT_RGBA8)
	var on := Color.WHITE
	match kind:
		"disc", "menu", "view":
			for py in 7:
				for px in 7:
					if (px - 3) * (px - 3) + (py - 3) * (py - 3) <= 10:
						icon.set_pixel(px, py, on)
			match kind:
				"disc":
					_knock_letter(icon, text, 2, 1)
				"menu":  # three lines (Start / Options)
					for row: int in [1, 3, 5]:
						for px in range(2, 5):
							icon.set_pixel(px, row, Color.TRANSPARENT)
				"view":  # a little window (Back / Create)
					for py in range(2, 5):
						for px in range(2, 5):
							if px != 3 or py != 3:
								icon.set_pixel(px, py, Color.TRANSPARENT)
		"pill":
			for py in 7:
				for px in width:
					var corner := (px == 0 or px == width - 1) and (py == 0 or py == 6)
					if not corner:
						icon.set_pixel(px, py, on)
			for k in text.length():
				_knock_letter(icon, text[k], 2 + k * 4, 1)
		"ps_cross":
			for k in 7:
				icon.set_pixel(k, k, on)
				icon.set_pixel(6 - k, k, on)
		"ps_circle":
			for py in 7:
				for px in 7:
					var d := (px - 3) * (px - 3) + (py - 3) * (py - 3)
					if d <= 10 and d >= 5:
						icon.set_pixel(px, py, on)
		"ps_square":
			for k in 7:
				icon.set_pixel(k, 0, on)
				icon.set_pixel(k, 6, on)
				icon.set_pixel(0, k, on)
				icon.set_pixel(6, k, on)
		"ps_triangle":
			for py in PS_TRIANGLE.size():
				for px in PS_TRIANGLE[py].length():
					if PS_TRIANGLE[py][px] == "#":
						icon.set_pixel(px, py, on)
		"mouse":
			for py in MOUSE.size():
				for px in MOUSE[py].length():
					var c := MOUSE[py][px]
					var pressed := c == "?" and ((px < 2 and text == "L") or (px > 2 and text == "R"))
					if c == "#" or pressed:
						icon.set_pixel(px, py, on)
	return icon


func _knock_letter(icon: Image, letter: String, x0: int, y0: int) -> void:
	var rows: Array = MINI_LETTERS.get(letter, [])
	for r in rows.size():
		for c in 3:
			if int(rows[r]) & (4 >> c):
				icon.set_pixel(x0 + c, y0 + r, Color.TRANSPARENT)


# --- boss (64x64 frames: walk0, walk1, windup, charge; feet at y=58) -------------------

func _gen_boss() -> void:
	var img := _img(256, 64)
	for f in 4:
		_draw_demon(img, f * 64, f)
		_outline(img, Rect2i(f * 64, 0, 64, 64))
	_save(img, "res://assets/sprites/enemies/boss_demon.png")


func _draw_demon(img: Image, ox: int, frame: int) -> void:
	var skin := Color("b8322a")
	var dark := Color("7a1e1a")
	var belly := Color("d8704a")
	var horn := Color("e8dcc0")
	var eye := Color("fff060") if frame != 2 else Color("ffffff")
	var bob := 1 if frame == 1 else 0
	var lean := 3 if frame == 3 else 0
	# Wings
	var wing := Color("4a1a2a")
	for i in 10:
		_rect(img, ox + 8 + i, 18 + i + bob, 3, 14 - i, wing)
		_rect(img, ox + 53 - i, 18 + i + bob, 3, 14 - i, wing)
	# Legs
	var step := 2 if frame == 1 else 0
	_rect(img, ox + 22 + lean, 46, 7, 12 - step, dark)
	_rect(img, ox + 36 + lean, 46, 7, 12 - (2 - step), dark)
	_rect(img, ox + 20 + lean, 56 - step, 10, 3, Color("2a1010"))
	_rect(img, ox + 35 + lean, 56 - (2 - step), 10, 3, Color("2a1010"))
	# Body
	_rect(img, ox + 18 + lean, 24 + bob, 29, 24, skin)
	_rect(img, ox + 24 + lean, 30 + bob, 17, 14, belly)
	_rect(img, ox + 18 + lean, 44 + bob, 29, 4, dark)
	# Arms (raised in windup)
	if frame == 2:
		_rect(img, ox + 12, 8, 6, 20, skin)
		_rect(img, ox + 47, 8, 6, 20, skin)
		_rect(img, ox + 11, 4, 8, 6, Color("ff9a3a"))
		_rect(img, ox + 46, 4, 8, 6, Color("ff9a3a"))
	else:
		_rect(img, ox + 12 + lean, 26 + bob, 6, 18, skin)
		_rect(img, ox + 47 + lean, 26 + bob, 6, 18, skin)
		_rect(img, ox + 11 + lean, 42 + bob, 8, 5, dark)
		_rect(img, ox + 46 + lean, 42 + bob, 8, 5, dark)
	# Head
	_rect(img, ox + 24 + lean, 10 + bob, 17, 15, skin)
	_rect(img, ox + 24 + lean, 21 + bob, 17, 4, dark)
	_rect(img, ox + 27 + lean, 15 + bob, 3, 2, eye)
	_rect(img, ox + 35 + lean, 15 + bob, 3, 2, eye)
	_rect(img, ox + 28 + lean, 21 + bob, 9, 2, Color("2a0a0a"))
	_px(img, ox + 29 + lean, 22 + bob, horn)
	_px(img, ox + 35 + lean, 22 + bob, horn)
	# Horns
	for i in 6:
		_rect(img, ox + 21 - i / 2 + lean, 10 - i + bob, 3, 1, horn)
		_rect(img, ox + 41 + i / 2 + lean, 10 - i + bob, 3, 1, horn)


# --- mini boss (64x64 frames: walk0, walk1, windup, leap; feet at y=58) ------------------

func _gen_colossus() -> void:
	var img := _img(256, 64)
	for f in 4:
		_draw_colossus(img, f * 64, f)
		_outline(img, Rect2i(f * 64, 0, 64, 64))
	_save(img, "res://assets/sprites/enemies/bone_colossus.png")


## A hunched giant of bones with glowing eyes and a femur club.
func _draw_colossus(img: Image, ox: int, frame: int) -> void:
	var bone := Color("e0d6bc")
	var hi := Color("f4ecd6")
	var shade := Color("a89c80")
	var dark := Color("4a4238")
	var glow := Color("9cff5a")
	var club := Color("cbbb96")
	var bob := 1 if frame == 1 else 0
	var leap := frame == 3
	# Legs (stepping in turn, tucked in a leap) and big bone feet.
	var lift_l := 2 if frame == 1 else 0
	var lift_r := 0 if leap or frame == 1 else 2
	var bottom := 51 if leap else 55
	for leg: Array in [[22, lift_l], [37, lift_r]]:
		var x: int = leg[0]
		var lift: int = leg[1]
		_rect(img, ox + x, 44, 6, bottom - 44 - lift, shade)
		_rect(img, ox + x + 1, 44, 2, bottom - 44 - lift, bone)
		_rect(img, ox + x - 1, 48, 8, 2, bone)  # knee
		_rect(img, ox + x - 3, bottom + 1 - lift, 10, 3, bone)
		_rect(img, ox + x - 3, bottom + 3 - lift, 10, 1, shade)
	# Pelvis and spine.
	_rect(img, ox + 21, 41 + bob, 23, 5, bone)
	_rect(img, ox + 25, 43 + bob, 3, 2, dark)
	_rect(img, ox + 37, 43 + bob, 3, 2, dark)
	_rect(img, ox + 31, 34 + bob, 3, 8, shade)
	# Ribcage: bone bars with dark gaps either side of the sternum.
	_rect(img, ox + 17, 22 + bob, 31, 16, bone)
	for y in [25, 28, 31, 34]:
		_rect(img, ox + 19, y + bob, 12, 1, dark)
		_rect(img, ox + 34, y + bob, 12, 1, dark)
	_rect(img, ox + 44, 23 + bob, 3, 14, shade)
	_rect(img, ox + 18, 23 + bob, 1, 14, hi)
	# Shoulders with knobs.
	_rect(img, ox + 12, 19 + bob, 41, 5, bone)
	_rect(img, ox + 12, 19 + bob, 41, 1, hi)
	_rect(img, ox + 9, 17 + bob, 8, 7, bone)
	_rect(img, ox + 48, 17 + bob, 8, 7, bone)
	_rect(img, ox + 9, 17 + bob, 8, 1, hi)
	_rect(img, ox + 48, 17 + bob, 8, 1, hi)
	# Arms and the club.
	if frame == 2:  # wind-up: the club raised over its head in both hands
		_rect(img, ox + 13, 8, 4, 12, bone)
		_rect(img, ox + 47, 8, 4, 12, bone)
		_rect(img, ox + 12, 5, 6, 4, shade)
		_rect(img, ox + 46, 5, 6, 4, shade)
		_rect(img, ox + 8, 3, 48, 3, club)
		_rect(img, ox + 3, 1, 7, 7, club)
		_rect(img, ox + 54, 1, 7, 7, club)
		_rect(img, ox + 4, 2, 2, 2, bone)
		_rect(img, ox + 55, 2, 2, 2, bone)
	elif leap:  # airborne: arms flung up, the club held high behind it
		_rect(img, ox + 11, 9, 4, 11, bone)
		_rect(img, ox + 10, 6, 6, 4, shade)
		_rect(img, ox + 49, 9, 4, 11, bone)
		_rect(img, ox + 48, 6, 6, 4, shade)
		_rect(img, ox + 50, 2, 3, 6, club)
		_rect(img, ox + 48, 1, 7, 4, club)
	else:  # hanging claws; the club dragging at its side
		_rect(img, ox + 10, 23 + bob, 4, 11, bone)
		_rect(img, ox + 9, 34 + bob, 4, 9, shade)
		_rect(img, ox + 8, 43 + bob, 7, 4, bone)
		_rect(img, ox + 51, 23 + bob, 4, 11, bone)
		_rect(img, ox + 51, 34 + bob, 4, 7, shade)
		_rect(img, ox + 51, 38 + bob, 3, 12, club)
		_rect(img, ox + 48, 49 + bob, 9, 7, club)
		_rect(img, ox + 49, 50 + bob, 2, 2, bone)
	# Skull: glowing eyes, a jaw of teeth and a crown of bone spikes.
	_rect(img, ox + 24, 7 + bob, 17, 10, bone)
	_rect(img, ox + 24, 7 + bob, 17, 1, hi)
	_rect(img, ox + 26, 17 + bob, 13, 4, shade)
	_rect(img, ox + 27, 10 + bob, 4, 4, dark)
	_rect(img, ox + 34, 10 + bob, 4, 4, dark)
	var eye := Color.WHITE if frame == 2 else glow
	_rect(img, ox + 28, 11 + bob, 2, 2, eye)
	_rect(img, ox + 35, 11 + bob, 2, 2, eye)
	_rect(img, ox + 32, 14 + bob, 1, 2, dark)
	for x in range(27, 38, 2):
		_px(img, ox + x, 18 + bob, dark)
	for x in [27, 32, 37]:
		_rect(img, ox + x, 4 + bob, 1, 3, bone)
		_px(img, ox + x, 3 + bob, hi)


# --- app icon (drawn at 32x32, scaled x8 with nearest filtering) ----------------------

func _gen_icon() -> void:
	var small := _img(32, 32)
	# Background: dungeon floor disc.
	for y in 32:
		for x in 32:
			var d := Vector2(x + 0.5, y + 0.5).distance_to(Vector2(16, 16))
			if d < 15.5:
				small.set_pixel(x, y, Color("2e2b40") if (x + y) % 7 != 0 else Color("262436"))
	# Two goblins behind, the knight in front.
	var goblin := _img(256, 256)
	_draw_swarmer(goblin, 0, 0, 0)
	_outline(goblin, Rect2i(0, 0, 32, 32))
	small.blend_rect(goblin, Rect2i(8, 8, 18, 18), Vector2i(1, 4))
	small.blend_rect(goblin, Rect2i(8, 8, 18, 18), Vector2i(14, 4))
	var knight := _img(16, 16)
	_draw_hero(knight, 0, "idle0", HEROES["knight"])
	_outline(knight, Rect2i(0, 0, 16, 16))
	small.blend_rect(knight, Rect2i(0, 0, 16, 16), Vector2i(8, 12))
	# Ring.
	for a in 64:
		var p := Vector2(16, 16) + Vector2.from_angle(TAU * a / 64.0) * 15.0
		small.set_pixel(int(p.x), int(p.y), Color("f2c63c"))
	small.resize(256, 256, Image.INTERPOLATE_NEAREST)
	_save(small, "res://assets/icon.png")
