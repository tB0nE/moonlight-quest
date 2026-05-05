shader_type spatial;
render_mode unshaded, depth_draw_never, cull_disabled;

uniform sampler2D main_texture : source_color, filter_linear;
uniform vec2 quad_corners[4];

varying vec2 screen_uv;

vec3 barycentric(vec2 p, vec2 a, vec2 b, vec2 c) {
    vec2 v0 = b - a;
    vec2 v1 = c - a;
    vec2 v2 = p - a;
    float d00 = dot(v0, v0);
    float d01 = dot(v0, v1);
    float d11 = dot(v1, v1);
    float d20 = dot(v2, v0);
    float d21 = dot(v2, v1);
    float denom = d00 * d11 - d01 * d01;
    float v = (d11 * d20 - d01 * d21) / denom;
    float w = (d00 * d21 - d01 * d20) / denom;
    float u = 1.0 - v - w;
    return vec3(u, v, w);
}

void vertex() {
    screen_uv = SCREEN_UV;
}

void fragment() {
    vec2 suv = SCREEN_UV;
    suv.y = 1.0 - suv.y;

    vec2 tl = quad_corners[0];
    vec2 tr = quad_corners[1];
    vec2 bl = quad_corners[2];
    vec2 br = quad_corners[3];

    vec3 bary_top = barycentric(suv, tl, tr, bl);
    vec3 bary_bot = barycentric(suv, br, tr, bl);

    vec2 stream_uv;
    bool in_tri = false;

    if (bary_top.x >= 0.0 && bary_top.y >= 0.0 && bary_top.z >= 0.0) {
        vec2 uv_tl = vec2(0.0, 0.0);
        vec2 uv_tr = vec2(1.0, 0.0);
        vec2 uv_bl = vec2(0.0, 1.0);
        stream_uv = bary_top.x * uv_tl + bary_top.y * uv_tr + bary_top.z * uv_bl;
        in_tri = true;
    } else if (bary_bot.x >= 0.0 && bary_bot.y >= 0.0 && bary_bot.z >= 0.0) {
        vec2 uv_br = vec2(1.0, 1.0);
        vec2 uv_tr = vec2(1.0, 0.0);
        vec2 uv_bl = vec2(0.0, 1.0);
        stream_uv = bary_bot.x * uv_br + bary_bot.y * uv_tr + bary_bot.z * uv_bl;
        in_tri = true;
    }

    if (!in_tri) {
        discard;
    }

    ALBEDO = texture(main_texture, stream_uv).rgb;
}
