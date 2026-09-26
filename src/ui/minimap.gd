class_name Minimap
extends Control
## Level map overlay, shown only while a player holds MAP (Tab / M, or Back /
## Select on a gamepad). The level keeps running underneath. Shows the tiles
## the team has seen (MapReveal), arena rooms by state, the exit and the
## current objective, points of interest, enemies and every hero.
## The seen tiles live in a 1-pixel-per-tile image that is repainted only
## where something changed, then drawn scaled up with nearest filtering.

const FADE_SPEED := 14.0
const PADDING := 6.0
const TITLE_HEIGHT := 12.0
const LEGEND_HEIGHT := 12.0
const MAX_SCALE := 4.0
## Share of the screen the map may cover.
const MAX_SCREEN_FRACTION := Vector2(0.88, 0.8)

const COLOR_BACKGROUND := Color(0.03, 0.03, 0.06, 0.84)
const COLOR_BORDER := Color(1, 1, 1, 0.25)
const COLOR_WALL := Color(0.22, 0.21, 0.3)
const COLOR_FLOOR := Color(0.45, 0.46, 0.58)
const COLOR_ARENA := Color(0.62, 0.45, 0.36)
const COLOR_ARENA_ACTIVE := Color(0.82, 0.3, 0.26)
const COLOR_ARENA_CLEARED := Color(0.4, 0.58, 0.42)
const COLOR_DOOR := Color(0.7, 0.52, 0.28)
const COLOR_DOOR_LOCKED := Color(0.95, 0.3, 0.2)
const COLOR_EXIT := Color(0.78, 0.52, 1.0)
const COLOR_WATER := Color(0.26, 0.47, 0.8)
const COLOR_CHASM := Color(0.06, 0.05, 0.1)
const COLOR_SPIKES := Color(0.62, 0.4, 0.4)
const COLOR_ENEMY := Color(1.0, 0.3, 0.25, 0.85)
const COLOR_OBJECTIVE := Color("ffe07a")
const COLOR_CHEST := Color(1.0, 0.8, 0.25)
const COLOR_SHRINE := Color(0.4, 0.95, 1.0)
const COLOR_NEST := Color(0.95, 0.25, 0.45)
const COLOR_USED := Color(0.45, 0.45, 0.5)

var world: World
## Debug / screenshots: keep the map up (--show-map).
var force_show := false
var _alpha := 0.0
var _time := 0.0
var _image: Image
var _texture: ImageTexture
var _grid_version := -1
var _room_states: Dictionary = {}  # room id -> LevelDirector.RoomState last painted


func setup(p_world: World) -> void:
	world = p_world
	_image = null


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	force_show = OS.get_cmdline_user_args().has("--show-map")


## True while any player holds the map button (and nothing has paused the game).
func is_requested() -> bool:
	if world == null or get_tree().paused:
		return false
	if force_show:
		return true
	for slot in InputRouter.assigned_slots():
		if InputRouter.get_player(slot).is_down(PlayerInput.Action.MAP):
			return true
	return false


func is_shown() -> bool:
	return visible and _alpha > 0.0


func _process(delta: float) -> void:
	_time += delta
	var target := 1.0 if is_requested() else 0.0
	_alpha = move_toward(_alpha, target, FADE_SPEED * delta)
	visible = _alpha > 0.0
	if not visible:
		return
	modulate.a = _alpha
	refresh()
	queue_redraw()


## Brings the map image up to date (new tiles seen, doors, arena states).
func refresh() -> void:
	var level := world.level
	var grid := world.grid
	var dirty := false
	if _image == null or _image.get_width() != grid.width or _image.get_height() != grid.height:
		_image = Image.create_empty(grid.width, grid.height, false, Image.FORMAT_RGBA8)
		_image.fill(Color(0, 0, 0, 0))
		_texture = ImageTexture.create_from_image(_image)
		_grid_version = -1
		_room_states.clear()
		for i in world.reveal.seen.size():
			if world.reveal.seen[i] != 0:
				_paint(i)
		world.reveal.fresh.clear()
		dirty = true
	for i in world.reveal.fresh:
		_paint(i)
		dirty = true
	world.reveal.fresh.clear()
	if _grid_version != grid.version:
		_grid_version = grid.version
		for door in level.door_cells:
			_paint(door.y * grid.width + door.x)
		dirty = true
	for room in world.director.rooms:
		if _room_states.get(room.id, -1) != room.state:
			_room_states[room.id] = room.state
			for c in room.cells:
				_paint(c.y * grid.width + c.x)
			dirty = true
	if dirty:
		_texture.update(_image)


func _paint(i: int) -> void:
	if world.reveal.seen[i] == 0:
		return
	var w := world.grid.width
	_image.set_pixel(i % w, i / w, _cell_color(i))


func _cell_color(i: int) -> Color:
	var level := world.level
	match level.map_kind[i]:
		Level.MapKind.VOID:
			return Color(0, 0, 0, 0)
		Level.MapKind.WALL:
			return COLOR_WALL
		Level.MapKind.DOOR:
			return COLOR_DOOR_LOCKED if world.grid.solid[i] != 0 else COLOR_DOOR
		Level.MapKind.EXIT:
			return COLOR_EXIT
		Level.MapKind.WATER:
			return COLOR_WATER
		Level.MapKind.CHASM:
			return COLOR_CHASM
		Level.MapKind.SPIKES:
			return COLOR_SPIKES
	var room_id := level.room_of_cell[i]
	if room_id != 0:
		var room := world.director.room_by_id(room_id)
		if room:
			match room.state:
				LevelDirector.RoomState.ACTIVE:
					return COLOR_ARENA_ACTIVE
				LevelDirector.RoomState.CLEARED:
					return COLOR_ARENA_CLEARED
		return COLOR_ARENA
	return COLOR_FLOOR


# --- drawing ---------------------------------------------------------------------------------

## Pixels per tile and the map's top-left corner on screen.
func map_scale() -> float:
	var grid := world.grid
	var room := get_viewport_rect().size * MAX_SCREEN_FRACTION \
		- Vector2(PADDING * 2.0, PADDING * 2.0 + TITLE_HEIGHT + LEGEND_HEIGHT)
	var fit := minf(room.x / grid.width, room.y / grid.height)
	return clampf(floorf(fit), 1.0, MAX_SCALE) if fit >= 1.0 else fit


func map_origin() -> Vector2:
	var size := Vector2(world.grid.width, world.grid.height) * map_scale()
	var view := get_viewport_rect().size
	return ((view - size) * 0.5 + Vector2(0, (TITLE_HEIGHT - LEGEND_HEIGHT) * 0.5)).floor()


## Screen position of a world position on the map.
func to_map(p: Vector2) -> Vector2:
	return map_origin() + p * LevelGrid.INV_TILE * map_scale()


func _draw() -> void:
	if world == null or _texture == null:
		return
	var s := map_scale()
	var origin := map_origin()
	var size := Vector2(world.grid.width, world.grid.height) * s
	var panel := Rect2(origin - Vector2(PADDING, PADDING + TITLE_HEIGHT),
		size + Vector2(PADDING * 2.0, PADDING * 2.0 + TITLE_HEIGHT + LEGEND_HEIGHT))
	draw_rect(panel, COLOR_BACKGROUND)
	draw_rect(panel, COLOR_BORDER, false, 1.0)
	var font := get_theme_default_font()
	var title := "MAP  -  %s" % world.level_data.display_name.to_upper()
	draw_string(font, panel.position + Vector2(PADDING, PADDING + 7), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 8,
		Color(0.9, 0.9, 0.95))
	draw_texture_rect(_texture, Rect2(origin, size), false)
	_draw_view_rect(s)
	_draw_enemies(s)
	_draw_points_of_interest(s)
	_draw_objective(s)
	_draw_heroes(s)
	_draw_legend(font, Vector2(panel.position.x + PADDING, panel.end.y - 4))


func _draw_view_rect(s: float) -> void:
	var view := world.camera.visible_rect()
	draw_rect(Rect2(to_map(view.position), view.size * LevelGrid.INV_TILE * s), Color(1, 1, 1, 0.3), false, 1.0)


func _draw_enemies(s: float) -> void:
	var horde := world.horde
	var d := maxf(1.0, floorf(s * 0.67))
	var size := Vector2(d, d)
	for i in horde.count:
		if horde.hp[i] <= 0.0 or not horde.is_mobile(i):
			continue
		var p := horde.pos[i]
		if world.reveal.is_seen_at(p):
			draw_rect(Rect2((to_map(p) - size * 0.5).floor(), size), COLOR_ENEMY)
	if world.boss and is_instance_valid(world.boss):
		var bp := to_map(world.boss.position)
		draw_circle(bp, 2.5 + s * 0.5 + sin(_time * 8.0), Color(1, 0.2, 0.15))


func _draw_points_of_interest(s: float) -> void:
	var level := world.level
	var exit := level.exit_center()
	if exit.is_finite() and (world.director.exit_open or world.reveal.is_seen_at(exit)):
		var r := 2.0 + s * 0.75
		if world.director.exit_open:
			r += 1.0 + sin(_time * 6.0)
		_diamond(to_map(exit), r, COLOR_EXIT)


func _draw_objective(s: float) -> void:
	var target := world.director.objective_target
	if not target.is_finite():
		return
	var r := 4.0 + s + 1.5 * sin(_time * 6.0)
	draw_arc(to_map(target), r, 0.0, TAU, 20, COLOR_OBJECTIVE, 1.0)


func _draw_heroes(s: float) -> void:
	var d := maxf(3.0, s + 1.0)
	for hero in world.heroes:
		var p := to_map(hero.position).floor()
		var c := hero.color
		if hero.is_downed():
			c = c.darkened(0.5) if int(_time * 4.0) % 2 == 0 else Color.WHITE
		var rect := Rect2(p - Vector2(d, d) * 0.5, Vector2(d, d)).grow(1.0)
		draw_rect(rect, Color(0, 0, 0, 0.9))
		draw_rect(rect.grow(-1.0), c)


func _draw_legend(font: Font, pos: Vector2) -> void:
	var x := pos.x
	var y := pos.y
	x = _legend_item(font, x, y, Color.WHITE, "Heroes", 0)
	x = _legend_item(font, x, y, COLOR_ENEMY, "Enemies", 0)
	x = _legend_item(font, x, y, COLOR_OBJECTIVE, "Objective", 1)
	x = _legend_item(font, x, y, COLOR_EXIT, "Exit", 2)
	x = _legend_item(font, x, y, COLOR_ARENA, "Arena", 0)


## Draws an icon (0 square, 1 ring, 2 diamond) and a label; returns the next x.
func _legend_item(font: Font, x: float, y: float, color: Color, text: String, icon: int) -> float:
	var center := Vector2(x + 3, y - 3)
	match icon:
		0:
			draw_rect(Rect2(center - Vector2(2, 2), Vector2(4, 4)), color)
		1:
			draw_arc(center, 3.0, 0.0, TAU, 12, color, 1.0)
		2:
			_diamond(center, 3.0, color)
	draw_string(font, Vector2(x + 9, y), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(0.75, 0.75, 0.8))
	return x + 9 + font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 8).x + 10


func _diamond(center: Vector2, r: float, color: Color) -> void:
	draw_colored_polygon(PackedVector2Array([
		center + Vector2(0, -r), center + Vector2(r, 0), center + Vector2(0, r), center + Vector2(-r, 0)]), color)
