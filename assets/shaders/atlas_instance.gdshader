shader_type canvas_item;
// Draws one atlas cell per MultiMesh instance (see src/sim/instance_layer.gd).
// INSTANCE_CUSTOM: r = cell index, g = hit flash (0..1), b = tint code
// (0 none, 1 chilled/slowed, 2 frozen, 3 burning, 4 poisoned, 5 winding up an
// attack; HordeSim.Tint; 6 = enemy shot, ProjectileSim) plus 10 x the elite
// trait (Elites.Trait), a = alpha.

uniform vec2 atlas_cells = vec2(8.0, 8.0);

varying vec4 v_custom;

void vertex() {
	v_custom = INSTANCE_CUSTOM;
	float index = floor(INSTANCE_CUSTOM.r + 0.5);
	float col = mod(index, atlas_cells.x);
	float row = floor(index / atlas_cells.x);
	UV = (vec2(col, row) + UV) / atlas_cells;
}

// Elite outline colours by trait (Elites.COLORS): swift, volatile, splitting.
const vec3 ELITE_COLORS[3] = vec3[3](vec3(0.45, 0.95, 1.0), vec3(1.0, 0.55, 0.15), vec3(0.6, 1.0, 0.35));

void fragment() {
	vec4 c = COLOR;
	float code = floor(v_custom.b + 0.5);
	float elite = floor(code / 10.0);
	float tint = code - elite * 10.0;
	if (elite > 0.5 && c.a < 0.5) {
		// Elites glow: an outline in their trait's colour around the sprite.
		vec2 px = TEXTURE_PIXEL_SIZE;
		float around = texture(TEXTURE, UV + vec2(px.x, 0.0)).a + texture(TEXTURE, UV - vec2(px.x, 0.0)).a
			+ texture(TEXTURE, UV + vec2(0.0, px.y)).a + texture(TEXTURE, UV - vec2(0.0, px.y)).a;
		if (around > 0.5) {
			float pulse = 0.75 + 0.25 * sin(TIME * 6.0);
			c = vec4(ELITE_COLORS[int(elite) - 1] * pulse + vec3(0.25, 0.2, 0.0), 1.0);
		}
	}
	c.rgb = mix(c.rgb, vec3(1.0), v_custom.g);
	if (tint == 1.0) {
		c.rgb = c.rgb * vec3(0.55, 0.85, 1.35) + vec3(0.05, 0.12, 0.25);
	} else if (tint == 2.0) {
		c.rgb = mix(c.rgb, vec3(0.78, 0.93, 1.0), 0.55) + vec3(0.02, 0.06, 0.12);
	} else if (tint == 3.0) {
		c.rgb = c.rgb * vec3(1.25, 0.78, 0.5) + vec3(0.24, 0.07, 0.0);
	} else if (tint == 4.0) {
		c.rgb = c.rgb * vec3(0.72, 1.18, 0.6) + vec3(0.04, 0.14, 0.02);
	} else if (tint == 5.0) {
		// About to attack: pulses hot pink.
		float pulse = 0.5 + 0.5 * sin(TIME * 28.0);
		c.rgb = mix(c.rgb, vec3(1.0, 0.3, 0.62), 0.3 + 0.35 * pulse);
	} else if (tint == 6.0) {
		// Enemy shots throb so they stand out from everything else.
		c.rgb *= 1.0 + 0.35 * (0.5 + 0.5 * sin(TIME * 16.0));
	}
	c.a *= v_custom.a;
	COLOR = c;
}
