shader_type canvas_item;
// Blends a sprite toward a colour (hit flashes, attack wind-ups). A modulate
// can't do this: multiplying strongly coloured pixels (a red demon) by pink
// just gives red.

uniform vec4 flash_color : source_color = vec4(1.0);
uniform float flash_amount : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	vec4 c = COLOR;
	c.rgb = mix(c.rgb, flash_color.rgb, flash_amount);
	COLOR = c;
}
