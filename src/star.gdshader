shader_type spatial;
render_mode unshaded, depth_draw_never, cull_disabled;

void fragment() {
	vec3 idx3 = fract(CUSTOM.rgb * 13.37);
	float seed = fract(dot(idx3.rg, vec2(12.9898, 78.233)));
	
	float color_sel = fract(seed * 4.32);
	vec3 tint;
	if (color_sel < 0.25) {
		tint = vec3(1.0, 0.72, 0.72);
	} else if (color_sel < 0.5) {
		tint = vec3(0.72, 0.82, 1.0);
	} else if (color_sel < 0.75) {
		tint = vec3(1.0, 0.94, 0.72);
	} else {
		tint = vec3(1.0, 1.0, 1.0);
	}
	
	float flicker_sel = fract(seed * 7.13);
	float flicker = 1.0;
	if (flicker_sel < 0.4) {
		flicker = 1.0;
	} else if (flicker_sel < 0.75) {
		flicker = 0.7 + 0.3 * sin(TIME * 1.5 + seed * 6.28);
	} else {
		flicker = 0.5 + 0.5 * sin(TIME * 8.0 + seed * 6.28);
	}
	
	ALBEDO = tint;
	EMISSION = tint * 2.0 * flicker;
	ALPHA = flicker;
}
