class_name InstanceLayer
extends MultiMeshInstance2D
## Draws up to `capacity` atlas cells in a single draw call. Sims write
## STRIDE floats per instance into `buffer`, then call commit(visible_count).
## The buffer starts as identity transforms with alpha 1, so sims can skip
## writing fields they never change (e.g. rotation for enemies).
## Per-instance layout (MultiMesh TRANSFORM_2D + custom data):
##   [0..7]  transform rows: x.x, y.x, 0, origin.x, x.y, y.y, 0, origin.y
##   [8..11] custom: atlas cell index, hit flash, frozen tint, alpha

const STRIDE := 12
const SHADER := preload("res://assets/shaders/atlas_instance.gdshader")

var capacity := 0
var buffer := PackedFloat32Array()


## `anchor` is the pixel inside a cell that sits on the instance position
## (e.g. an enemy's feet), so sims can write world positions directly.
func setup(atlas: Texture2D, cell_size: Vector2i, anchor: Vector2, p_capacity: int) -> void:
	capacity = p_capacity
	texture = atlas
	var x0 := -anchor.x
	var y0 := -anchor.y
	var x1 := x0 + cell_size.x
	var y1 := y0 + cell_size.y
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector2Array([
		Vector2(x0, y0), Vector2(x1, y0), Vector2(x1, y1), Vector2(x0, y1)])
	arrays[Mesh.ARRAY_TEX_UV] = PackedVector2Array([
		Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)])
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2, 0, 2, 3])
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_2D
	mm.use_custom_data = true
	mm.mesh = mesh
	mm.instance_count = capacity
	mm.visible_instance_count = 0
	# Skip per-frame bounds recomputation; the layer covers the whole level.
	mm.custom_aabb = AABB(Vector3(-100000, -100000, -1), Vector3(200000, 200000, 2))
	multimesh = mm

	var mat := ShaderMaterial.new()
	mat.shader = SHADER
	mat.set_shader_parameter("atlas_cells", Vector2(
		float(atlas.get_width()) / cell_size.x, float(atlas.get_height()) / cell_size.y))
	material = mat
	buffer.resize(capacity * STRIDE)
	# Identity transform + opaque, no flash/tint: sims only rewrite what changes.
	for i in capacity:
		var o := i * STRIDE
		buffer[o] = 1.0
		buffer[o + 5] = 1.0
		buffer[o + 11] = 1.0


func commit(visible_count: int) -> void:
	multimesh.buffer = buffer
	multimesh.visible_instance_count = mini(visible_count, capacity)
