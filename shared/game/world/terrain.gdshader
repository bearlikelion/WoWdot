shader_type spatial;
render_mode cull_disabled;

uniform sampler2DArray layers : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
// RGBA hold the array index of each chunk's four layers, one texel per chunk.
uniform sampler2D chunk_layers : filter_nearest, repeat_disable;
// RGB hold the blend weights of layers 1 to 3, each painted over the layers below it; A is the baked shadow.
uniform sampler2D alpha_map : filter_linear, repeat_disable;

void fragment() {
	vec4 blend = texture(alpha_map, UV2);
	vec4 slots = texelFetch(chunk_layers, min(ivec2(UV2 * 16.0), ivec2(15)), 0) * 255.0;
	vec3 color = texture(layers, vec3(UV, slots.r)).rgb;
	color = mix(color, texture(layers, vec3(UV, slots.g)).rgb, blend.r);
	color = mix(color, texture(layers, vec3(UV, slots.b)).rgb, blend.g);
	color = mix(color, texture(layers, vec3(UV, slots.a)).rgb, blend.b);
	// The stock client dims a shadowed texel to 0.7 in gamma space, which is 0.456 linear.
	ALBEDO = color * mix(1.0, 0.456, blend.a);
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}
