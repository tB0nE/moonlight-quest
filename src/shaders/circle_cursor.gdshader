shader_type canvas_item;

void fragment() {
	vec2 center = vec2(0.5, 0.5);
	float dist = distance(UV, center);
	float radius = 0.42;
	float edge = 0.015;
	float alpha = smoothstep(radius, radius - edge, dist);
	COLOR = vec4(1.0, 1.0, 1.0, alpha * 0.3);
}
