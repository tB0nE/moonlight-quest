shader_type spatial;
render_mode unshaded, depth_draw_never, cull_disabled;

uniform sampler2D main_texture : source_color, filter_linear, repeat_disable;
uniform float filter_mode = 3.0;

void fragment() {
	vec2 texel = 1.0 / vec2(textureSize(main_texture, 0));
	float s = filter_mode * 0.5;
	vec3 original = texture(main_texture, UV).rgb;
	if (s <= 0.0) {
		ALBEDO = original;
		ALPHA = texture(main_texture, UV).a;
		return;
	}
	vec3 blurred = original * 4.0;
	blurred += texture(main_texture, UV + vec2(-1.0, -1.0) * texel * s).rgb;
	blurred += texture(main_texture, UV + vec2( 1.0, -1.0) * texel * s).rgb;
	blurred += texture(main_texture, UV + vec2(-1.0,  1.0) * texel * s).rgb;
	blurred += texture(main_texture, UV + vec2( 1.0,  1.0) * texel * s).rgb;
	blurred += texture(main_texture, UV + vec2(-1.0,  0.0) * texel * s).rgb * 2.0;
	blurred += texture(main_texture, UV + vec2( 1.0,  0.0) * texel * s).rgb * 2.0;
	blurred += texture(main_texture, UV + vec2( 0.0, -1.0) * texel * s).rgb * 2.0;
	blurred += texture(main_texture, UV + vec2( 0.0,  1.0) * texel * s).rgb * 2.0;
	blurred /= 16.0;
	ALBEDO = blurred;
	ALPHA = texture(main_texture, UV).a;
}
