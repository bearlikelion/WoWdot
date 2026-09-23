shader_type sky;

// The five stock sky bands, from straight up down to the horizon.
uniform vec3 sky_top : source_color;
uniform vec3 sky_middle : source_color;
uniform vec3 sky_lower : source_color;
uniform vec3 sky_above_horizon : source_color;
uniform vec3 sky_horizon : source_color;
uniform vec3 fog_color : source_color;
uniform vec3 disc_color : source_color;
uniform vec3 halo_color : source_color;
// Light.dbc's cloud bands: the glow facing the sun, then the shading slope and base.
uniform vec3 cloud_sun : source_color;
uniform vec3 cloud_slope : source_color;
uniform vec3 cloud_base : source_color;
uniform float cloud_glow : hint_range(0.0, 1.0) = 1.0;
uniform float cloud_density : hint_range(0.0, 1.0) = 0.5;
uniform float disc_size : hint_range(0.0, 0.2) = 0.04;
uniform float halo_size : hint_range(0.0, 1.0) = 0.35;
uniform vec2 wind = vec2(0.004, 0.0015);
uniform sampler2D cloud_noise : repeat_enable, filter_linear_mipmap;

vec3 gradient(float height) {
	vec3 color = mix(sky_horizon, sky_above_horizon, smoothstep(0.0, 0.08, height));
	color = mix(color, sky_lower, smoothstep(0.08, 0.2, height));
	color = mix(color, sky_middle, smoothstep(0.2, 0.45, height));
	return mix(color, sky_top, smoothstep(0.45, 0.9, height));
}

void sky() {
	float height = EYEDIR.y;
	vec3 color = height < 0.0 ? mix(sky_horizon, fog_color, smoothstep(0.0, -0.1, height)) : gradient(height);
	if (LIGHT0_ENABLED) {
		float angle = acos(clamp(dot(EYEDIR, LIGHT0_DIRECTION), -1.0, 1.0));
		// The disc and glare add onto the sky, so a warm sun still burns out to white.
		color += halo_color * pow(1.0 - smoothstep(0.0, halo_size, angle), 3.0) * 0.6;
		color += disc_color * (1.0 - smoothstep(disc_size * 0.85, disc_size, angle));
	}
	if (height > 0.0) {
		vec2 plane = EYEDIR.xz / (height + 0.12);
		float shape = texture(cloud_noise, plane * 0.22 + TIME * wind).r;
		float detail = texture(cloud_noise, plane * 0.7 + TIME * wind * 1.7).r;
		float threshold = mix(0.65, 0.3, cloud_density);
		float cover = smoothstep(threshold, threshold + 0.2, shape * 0.7 + detail * 0.3);
		cover *= smoothstep(0.0, 0.12, height);
		// Thicker cloud takes less of the slope, and it glows where it faces the sun.
		vec3 cloud = cloud_slope * (0.75 - 0.5 * cover) + cloud_base;
		if (LIGHT0_ENABLED) {
			cloud += cloud_sun * max(dot(EYEDIR, LIGHT0_DIRECTION), 0.0) * cloud_glow;
		}
		color = mix(color, min(cloud, vec3(1.0)), cover * 0.9);
	}
	COLOR = color;
}
