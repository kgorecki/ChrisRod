shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform vec4 paint_color : source_color = vec4(1.0);
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform float metallic : hint_range(0.0, 1.0) = 0.35;
uniform float roughness : hint_range(0.0, 1.0) = 0.42;

void fragment() {
	vec4 tex = texture(albedo_tex, UV);
	vec3 painted = paint_color.rgb * tex.rgb;
	ALBEDO = mix(tex.rgb, painted, tex.a);
	METALLIC = mix(0.05, metallic, tex.a);
	ROUGHNESS = mix(0.82, roughness, tex.a);
}
