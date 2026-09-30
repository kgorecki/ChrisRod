shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform vec4 paint_color : source_color = vec4(1.0);
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D orm_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D normal_tex : hint_default_black, filter_linear_mipmap, repeat_enable;
uniform float metallic : hint_range(0.0, 1.0) = 0.35;
uniform float roughness : hint_range(0.0, 1.0) = 0.42;
uniform float use_orm : hint_range(0.0, 1.0) = 0.0;
uniform float use_normal : hint_range(0.0, 1.0) = 0.0;
uniform float normal_scale = 1.0;

void fragment() {
	vec4 tex = texture(albedo_tex, UV);
	vec3 painted = paint_color.rgb * tex.rgb;
	ALBEDO = mix(tex.rgb, painted, tex.a);
	if (use_orm > 0.5) {
		vec3 orm = texture(orm_tex, UV).rgb;
		METALLIC = mix(orm.b, metallic, tex.a);
		ROUGHNESS = mix(orm.g, roughness, tex.a);
		AO = orm.r;
	} else {
		METALLIC = mix(0.05, metallic, tex.a);
		ROUGHNESS = mix(0.82, roughness, tex.a);
	}
	if (use_normal > 0.5) {
		NORMAL_MAP = texture(normal_tex, UV).rgb;
		NORMAL_MAP_DEPTH = normal_scale;
	}
}
