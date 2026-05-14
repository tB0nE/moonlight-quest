shader_type spatial;
render_mode unshaded, depth_draw_never;

uniform sampler2D albedo_texture : source_color, filter_linear, repeat_disable;
uniform int target_eye = 0;

void fragment() {
	if (int(VIEW_INDEX) != target_eye) {
		discard;
	}
	vec4 tex = texture(albedo_texture, UV);
	ALBEDO = tex.rgb;
	ALPHA = tex.a;
}
