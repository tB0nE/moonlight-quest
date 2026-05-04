shader_type spatial;
render_mode unshaded;

uniform sampler2D main_texture : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D depth_texture : hint_default_white, filter_linear_mipmap;
uniform int stereo_mode = 0;
uniform float parallax_depth = 0.5;
uniform float convergence = 0.5;
uniform float balance_shift = 0.5;
uniform bool fxaa_enabled = true;

vec3 fxaa(sampler2D tex, vec2 uv, vec2 pixel_size) {
    vec3 rgb_nw = texture(tex, uv + vec2(-1.0, -1.0) * pixel_size).rgb;
    vec3 rgb_ne = texture(tex, uv + vec2(1.0, -1.0) * pixel_size).rgb;
    vec3 rgb_sw = texture(tex, uv + vec2(-1.0, 1.0) * pixel_size).rgb;
    vec3 rgb_se = texture(tex, uv + vec2(1.0, 1.0) * pixel_size).rgb;
    vec3 rgb_m = texture(tex, uv).rgb;

    vec3 luma = vec3(0.299, 0.587, 0.114);
    float luma_nw = dot(rgb_nw, luma);
    float luma_ne = dot(rgb_ne, luma);
    float luma_sw = dot(rgb_sw, luma);
    float luma_se = dot(rgb_se, luma);
    float luma_m = dot(rgb_m, luma);

    float luma_min = min(luma_m, min(min(luma_nw, luma_ne), min(luma_sw, luma_se)));
    float luma_max = max(luma_m, max(max(luma_nw, luma_ne), max(luma_sw, luma_se)));

    vec2 dir;
    dir.x = -((luma_nw + luma_ne) - (luma_sw + luma_se));
    dir.y = ((luma_nw + luma_sw) - (luma_ne + luma_se));

    float dir_reduce = max((luma_nw + luma_ne + luma_sw + luma_se) * 0.25 * 0.125, 0.0078125);
    float rcp_dir_min = 1.0 / (min(abs(dir.x), abs(dir.y)) + dir_reduce);

    dir = min(vec2(8.0), max(vec2(-8.0), dir * rcp_dir_min)) * pixel_size;

    vec3 rgb_a = 0.5 * (
        texture(tex, uv + dir * (1.0 / 3.0 - 0.5)).rgb +
        texture(tex, uv + dir * (2.0 / 3.0 - 0.5)).rgb
    );
    vec3 rgb_b = rgb_a * 0.5 + 0.25 * (
        texture(tex, uv + dir * -0.5).rgb +
        texture(tex, uv + dir * 0.5).rgb
    );

    float luma_b = dot(rgb_b, luma);

    float subpixel_offset = clamp(smoothstep(luma_min, luma_max, luma_m) - 0.5, 0.0, 1.0);
    subpixel_offset *= 0.5;
    vec3 rgb_sub = mix(rgb_a, rgb_b, step(luma_b, luma_min) + step(luma_max, luma_b));

    if (luma_b < luma_min || luma_b > luma_max) {
        return rgb_a;
    }
    return mix(rgb_b, rgb_a, subpixel_offset);
}

void fragment() {
    vec2 uv = UV;
    vec2 pixel_size = 1.0 / vec2(textureSize(main_texture, 0));

    if (stereo_mode == 0) {
        vec3 color = texture(main_texture, uv).rgb;
        if (fxaa_enabled) {
            color = fxaa(main_texture, uv, pixel_size);
        }
        ALBEDO = color;
    }
    else if (stereo_mode == 1) {
        vec2 sbs_uv;
        if (int(VIEW_INDEX) == 0) {
            sbs_uv = vec2(uv.x * 0.5, uv.y);
        } else {
            sbs_uv = vec2(uv.x * 0.5 + 0.5, uv.y);
        }
        vec3 color = texture(main_texture, sbs_uv).rgb;
        if (fxaa_enabled) {
            vec2 sbs_pixel = pixel_size;
            sbs_pixel.x *= 2.0;
            color = fxaa(main_texture, sbs_uv, sbs_pixel);
        }
        ALBEDO = color;
    }
    else if (stereo_mode == 2) {
        vec2 sbs_uv;
        if (int(VIEW_INDEX) == 0) {
            sbs_uv = vec2(uv.x * 0.5, uv.y * 0.5 + 0.25);
        } else {
            sbs_uv = vec2(uv.x * 0.5 + 0.5, uv.y * 0.5 + 0.25);
        }
        vec3 color = texture(main_texture, sbs_uv).rgb;
        if (fxaa_enabled) {
            vec2 sbs_pixel = pixel_size;
            sbs_pixel.x *= 2.0;
            sbs_pixel.y *= 2.0;
            color = fxaa(main_texture, sbs_uv, sbs_pixel);
        }
        ALBEDO = color;
    }
    else if (stereo_mode == 3) {
        float depth = texture(depth_texture, uv).r;

        float depth_diff;
        if (depth < convergence) {
            depth_diff = (depth - convergence) / max(convergence, 0.001);
        } else {
            depth_diff = (depth - convergence) / max(1.0 - convergence, 0.001);
        }

        float parallax = parallax_depth * 0.7 * 0.06;
        float shift = parallax * depth_diff;

        bool is_left = (int(VIEW_INDEX) == 0);
        float eye_sign = is_left ? -1.0 : 1.0;

        if ((depth - convergence) < 0.0) {
            shift *= is_left ? balance_shift : (1.0 - balance_shift);
        } else {
            shift *= is_left ? (1.0 - balance_shift) : balance_shift;
        }

        float h_dist = abs(uv.x - 0.5) * 2.0;
        float vignette = 1.0 - smoothstep(0.7, 1.0, pow(h_dist, 1.5));

        vec2 src_uv = vec2(clamp(uv.x - shift * eye_sign, 0.0, 1.0), uv.y);
        vec3 color = texture(main_texture, src_uv).rgb;

        if (fxaa_enabled) {
            color = fxaa(main_texture, src_uv, pixel_size);
        }

        ALBEDO = mix(texture(main_texture, uv).rgb, color, vignette);
    }
}
