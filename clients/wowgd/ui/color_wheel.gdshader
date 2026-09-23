shader_type canvas_item;

// The ColorSelect wheel: hue round the circle, saturation out from the middle.
uniform float value : hint_range(0.0, 1.0) = 1.0;

vec3 hsv_to_rgb(vec3 hsv) {
	vec3 k = clamp(abs(mod(hsv.x * 6.0 + vec3(0.0, 4.0, 2.0), 6.0) - 3.0) - 1.0, 0.0, 1.0);
	return hsv.z * mix(vec3(1.0), k, hsv.y);
}

void fragment() {
	vec2 point = UV * 2.0 - 1.0;
	float radius = length(point);
	float hue = fract(atan(-point.y, point.x) / TAU);
	float edge = 1.0 - smoothstep(0.98, 1.0, radius);
	COLOR = vec4(hsv_to_rgb(vec3(hue, min(radius, 1.0), value)), edge);
}
