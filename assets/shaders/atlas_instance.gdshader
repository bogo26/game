shader_type canvas_item;
// Draws one atlas cell per MultiMesh instance (see src/sim/instance_layer.gd).
// INSTANCE_CUSTOM: r = cell index, g = hit flash (0..1), b = frozen tint (0..1), a = alpha.

uniform vec2 atlas_cells = vec2(8.0, 8.0);

varying vec4 v_custom;

void vertex() {
	v_custom = INSTANCE_CUSTOM;
	float index = floor(INSTANCE_CUSTOM.r + 0.5);
	float col = mod(index, atlas_cells.x);
	float row = floor(index / atlas_cells.x);
	UV = (vec2(col, row) + UV) / atlas_cells;
}

void fragment() {
	vec4 c = COLOR;
	c.rgb = mix(c.rgb, vec3(1.0), v_custom.g);
	c.rgb = mix(c.rgb, c.rgb * vec3(0.55, 0.85, 1.35) + vec3(0.05, 0.12, 0.25), v_custom.b);
	c.a *= v_custom.a;
	COLOR = c;
}
