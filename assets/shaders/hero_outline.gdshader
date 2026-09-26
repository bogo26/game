shader_type canvas_item;
// Hero sprites: a 1 px outline in the player's colour around the opaque
// pixels, so every hero stands out from the horde and dark floors, and two
// players on the same hero can be told apart.

uniform vec4 outline_color : source_color = vec4(1.0);

varying vec4 v_modulate;

void vertex() {
	v_modulate = COLOR;
}

void fragment() {
	vec4 c = texture(TEXTURE, UV);
	if (c.a < 0.5) {
		vec2 px = TEXTURE_PIXEL_SIZE;
		float around = texture(TEXTURE, UV + vec2(px.x, 0.0)).a + texture(TEXTURE, UV - vec2(px.x, 0.0)).a
			+ texture(TEXTURE, UV + vec2(0.0, px.y)).a + texture(TEXTURE, UV - vec2(0.0, px.y)).a;
		if (around > 0.5) {
			c = outline_color;
		}
	}
	COLOR = c * v_modulate;
}
