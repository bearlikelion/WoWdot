shader_type spatial;
render_mode cull_disabled;

uniform int layer_count = 1;
uniform sampler2D layer0 : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D layer1 : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D layer2 : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D layer3 : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
// RGB hold the blend weights of layers 1 to 3, each painted over the layers below it; A is the baked shadow.
uniform sampler2D alpha_map : filter_linear, repeat_disable;

void fragment() {
	vec4 blend = texture(alpha_map, UV2);
	vec3 color = texture(layer0, UV).rgb;
	if (layer_count > 1) {
		color = mix(color, texture(layer1, UV).rgb, blend.r);
	}
	if (layer_count > 2) {
		color = mix(color, texture(layer2, UV).rgb, blend.g);
	}
	if (layer_count > 3) {
		color = mix(color, texture(layer3, UV).rgb, blend.b);
	}
	// The stock client dims a shadowed texel to 0.7 in gamma space, which is 0.456 linear.
	ALBEDO = color * mix(1.0, 0.456, blend.a);
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}
