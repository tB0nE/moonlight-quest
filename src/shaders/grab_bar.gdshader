shader_type canvas_item;

uniform float highlight_alpha : hint_range(0.0, 1.0) = 0.08;

void fragment() {
	vec2 uv = UV;
	float radius = 0.35;
	float alpha = 0.0;
	float dx = abs(uv.x - 0.5);
	float half_w = 0.5 - radius;
	if (dx < half_w) {
		alpha = smoothstep(0.0, 0.04, uv.y) * smoothstep(1.0, 0.96, uv.y);
	} else {
		float dy = radius - sqrt(max(0.0, radius * radius - (dx - half_w) * (dx - half_w)));
		if (uv.y > dy && uv.y < (1.0 - dy)) {
			alpha = 1.0;
		}
	}
	COLOR = vec4(1.0, 1.0, 1.0, alpha * highlight_alpha);
}
