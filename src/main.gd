extends Node2D
## Entry scene. Milestone 1 placeholder: proves the pixel-perfect viewport,
## autoloads and perf overlay are wired up. Replaced by the menu flow later.


func _ready() -> void:
	var title := Label.new()
	title.text = "HORDE CRAWLER\nsetup OK - press F3 for perf overlay"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.position = Vector2(0, 150)
	title.size = Vector2(640, 60)
	add_child(title)


func _draw() -> void:
	# 1px checker border to eyeball integer scaling.
	var size := get_viewport_rect().size
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.9, 0.3, 0.3), false, 1.0)
	for x in range(0, int(size.x), 32):
		draw_rect(Rect2(x, 0, 16, 4), Color(0.3, 0.9, 0.4))
