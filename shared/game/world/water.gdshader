shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never;

const float FPS = 24.0;
// Stock liquid UVs step a quarter per 4.17 yard cell.
const float YARDS_PER_REPEAT = 16.6667;
const float SHININESS = 6.0;

// Stock combines in gamma, so every colour here is raw gamma.
uniform sampler2DArray ripples : hint_default_black, filter_linear_mipmap, repeat_enable;
uniform int frame_count = 1;
uniform vec3 lit = vec3(1.0);
uniform vec3 sheen = vec3(0.0);
uniform vec3 to_sun = vec3(0.0, 1.0, 0.0);
uniform vec3 shallow_color = vec3(0.16, 0.34, 0.45);
uniform vec3 deep_color = vec3(0.08, 0.22, 0.36);
uniform vec2 alphas = vec2(0.5, 1.0);
// Yards of water below the surface at which it reads fully deep.
uniform float depth_range = 4.7;
uniform sampler2D depth_texture : hint_depth_texture, filter_nearest;

vec3 to_linear(vec3 c) {
	return mix(pow((c + 0.055) / 1.055, vec3(2.4)), c / 12.92, lessThan(c, vec3(0.04045)));
}

void fragment() {
	vec3 world = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float frame = mod(floor(TIME * FPS), float(frame_count));
	vec4 detail = texture(ripples, vec3(world.xz / YARDS_PER_REPEAT, frame));
	float floor_depth = texture(depth_texture, SCREEN_UV).r;
	vec4 floor_view = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, floor_depth, 1.0);
	vec3 floor_world = (INV_VIEW_MATRIX * vec4(floor_view.xyz / floor_view.w, 1.0)).xyz;
	float depth = clamp((world.y - floor_world.y) / depth_range, 0.0, 1.0);
	vec3 half_way = normalize(normalize(to_sun) + normalize(CAMERA_POSITION_WORLD - world));
	vec3 specular = sheen * pow(max(half_way.y, 0.0), SHININESS);
	vec3 body = lit * mix(shallow_color, deep_color, depth);
	ALBEDO = to_linear(clamp(body + detail.rgb + (specular + 0.25) * detail.a, 0.0, 1.0));
	ALPHA = mix(alphas.x, alphas.y, depth);
}
