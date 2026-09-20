shader_type canvas_item;

// Unit portraits show through a round hole in the frame art.
void fragment() {
	COLOR.a *= 1.0 - smoothstep(0.47, 0.5, distance(UV, vec2(0.5)));
}
