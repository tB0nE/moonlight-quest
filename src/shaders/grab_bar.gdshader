shader_type canvas_item;

uniform float highlight_alpha : hint_range(0.0, 1.0) = 0.08;

void fragment() {
	vec2 uv = UV;
	float width = 0.4;
	float radius = 0.15;
	float alpha = 0.0;
	if (uv.x > (0.5 - width) && uv.x < (0.5 + width)) {
		float dx = abs(uv.x - 0.5);
		if (dx < (width - radius)) {
			alpha = smoothstep(0.0, 0.02, uv.y) * smoothstep(1.0, 0.98, uv.y);
		} else {
			float dy = radius - sqrt(radius * radius - (dx - (width - radius)) * (dx - (width - radius)));
			if (uv.y > dy && uv.y < (1.0 - dy)) {
				alpha = 1.0;
			}
		}
	}
	COLOR = vec4(1.0, 1.0, 1.0, alpha * highlight_alpha);
}
