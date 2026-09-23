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
// Light.dbc's cloud bands, left in the gamma space the stock client adds them in.
uniform vec3 cloud_sun;
uniform vec3 cloud_slope;
uniform vec3 cloud_base;
uniform float cloud_glow : hint_range(0.0, 1.0) = 1.0;
uniform float cloud_storm : hint_range(0.0, 1.0) = 0.0;
uniform float cloud_density : hint_range(0.0, 1.0) = 0.5;
uniform float disc_size : hint_range(0.0, 0.2) = 0.04;
uniform float halo_size : hint_range(0.0, 1.0) = 0.35;
uniform vec2 wind = vec2(0.004, 0.0015);
uniform sampler2D cloud_noise : repeat_enable, filter_linear_mipmap;

// The stock cloud dome spans 45 degrees down from the zenith as a 128 cell tile.
vec2 dome_cells(vec3 direction) {
	float polar = acos(clamp(direction.y, -1.0, 1.0));
	vec2 across = length(direction.xz) > 0.0001 ? normalize(direction.xz) : vec2(0.0);
	return across * polar / (PI / 4.0) * 64.0;
}

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
	// The dome's rings are opaque down to ring 9, half at ring 10 and clear from ring 11.
	float ring = acos(clamp(height, -1.0, 1.0)) / (PI / 4.0) * 12.0;
	float dome = ring < 9.0 ? 1.0 : ring < 10.0 ? mix(1.0, 0.5, ring - 9.0)
			: max(0.5 * (11.0 - ring), 0.0);
	if (dome > 0.0) {
		vec2 cells = dome_cells(EYEDIR);
		float shape = texture(cloud_noise, cells / 128.0 + TIME * wind).r;
		float detail = texture(cloud_noise, cells / 40.0 + TIME * wind * 1.7).r;
		// The stock tone curve: coverage past the density threshold thickens slowly, 1 - 0.96^i.
		float over = (shape * 0.7 + detail * 0.3 - (1.0 - cloud_density)) * 255.0;
		float cover = over > 0.0 ? 1.0 - pow(0.96, over * 0.6015625) : 0.0;
		// Thicker cloud takes less of the slope, and it glows as it faces the sun.
		vec3 cloud = cloud_slope * (0.75 - 0.5 * cover) + cloud_base;
		if (LIGHT0_ENABLED) {
			float lift = cloud_storm * 192.0 + 64.0;
			vec2 toward = dome_cells(LIGHT0_DIRECTION) - cells;
			cloud += cloud_sun * lift / sqrt(dot(toward, toward) + lift * lift) * cloud_glow;
		}
		vec3 sky_gamma = pow(max(color, vec3(0.0)), vec3(1.0 / 2.2));
		color = pow(mix(sky_gamma, min(cloud, vec3(1.0)), cover * dome), vec3(2.2));
	}
	COLOR = color;
}
