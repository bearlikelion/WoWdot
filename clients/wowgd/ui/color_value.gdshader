shader_type canvas_item;

// The ColorSelect value bar: the picked hue and saturation fading to black downwards.
uniform vec3 top_color : source_color = vec3(1.0);

void fragment() {
	COLOR = vec4(top_color * (1.0 - UV.y), 1.0);
}
