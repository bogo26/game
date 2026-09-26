shader_type canvas_item;
// Draws one atlas cell per MultiMesh instance (see src/sim/instance_layer.gd).
// INSTANCE_CUSTOM: r = cell index, g = hit flash (0..1), b = status tint code
// (0 none, 1 chilled/slowed, 2 frozen, 3 burning, 4 poisoned; HordeSim.Tint), a = alpha.

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
	float tint = floor(v_custom.b + 0.5);
	if (tint == 1.0) {
		c.rgb = c.rgb * vec3(0.55, 0.85, 1.35) + vec3(0.05, 0.12, 0.25);
	} else if (tint == 2.0) {
		c.rgb = mix(c.rgb, vec3(0.78, 0.93, 1.0), 0.55) + vec3(0.02, 0.06, 0.12);
	} else if (tint == 3.0) {
		c.rgb = c.rgb * vec3(1.25, 0.78, 0.5) + vec3(0.24, 0.07, 0.0);
	} else if (tint == 4.0) {
		c.rgb = c.rgb * vec3(0.72, 1.18, 0.6) + vec3(0.04, 0.14, 0.02);
	}
	c.a *= v_custom.a;
	COLOR = c;
}
