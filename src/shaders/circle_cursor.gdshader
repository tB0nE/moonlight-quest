shader_type canvas_item;

void fragment() {
	vec2 center = vec2(0.5, 0.5);
	float dist = distance(UV, center);
	float radius = 0.35;
	float edge = 0.05;
	float alpha = smoothstep(radius + edge, radius, dist) - smoothstep(radius, radius - edge, dist);
	COLOR = vec4(1.0, 1.0, 1.0, alpha);
}
