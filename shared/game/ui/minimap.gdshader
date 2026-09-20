shader_type canvas_item;

uniform vec2 size = vec2(140.0);
varying vec2 local;

void vertex() {
	local = VERTEX;
}

// The minimap is round; everything it draws is cut to the circle inside its rectangle.
void fragment() {
	COLOR.a *= 1.0 - smoothstep(0.49, 0.5, distance(local / size, vec2(0.5)));
}
