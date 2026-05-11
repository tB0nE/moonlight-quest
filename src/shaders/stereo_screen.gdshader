shader_type spatial;
render_mode unshaded;

uniform sampler2D main_texture : source_color, filter_linear, repeat_disable;
uniform sampler2D depth_texture : hint_default_white, filter_linear_mipmap;
uniform int stereo_mode = 0;
uniform float convergence = 0.5;
uniform float balance_shift = 0.5;
uniform int filter_mode = 0;
uniform float sharpen = 0.0;

vec3 filtered_texture(sampler2D tex, vec2 uv) {
    vec2 texel = 1.0 / vec2(textureSize(tex, 0));
    vec3 original = texture(tex, uv).rgb;
    if (filter_mode == 0 && sharpen <= 0.0) {
        return original;
    }
    float s = float(filter_mode) * 0.5;
    vec3 blurred = original * 4.0;
    blurred += texture(tex, uv + vec2(-1.0, -1.0) * texel * s).rgb;
    blurred += texture(tex, uv + vec2( 1.0, -1.0) * texel * s).rgb;
    blurred += texture(tex, uv + vec2(-1.0,  1.0) * texel * s).rgb;
    blurred += texture(tex, uv + vec2( 1.0,  1.0) * texel * s).rgb;
    blurred += texture(tex, uv + vec2(-1.0,  0.0) * texel * s).rgb * 2.0;
    blurred += texture(tex, uv + vec2( 1.0,  0.0) * texel * s).rgb * 2.0;
    blurred += texture(tex, uv + vec2( 0.0, -1.0) * texel * s).rgb * 2.0;
    blurred += texture(tex, uv + vec2( 0.0,  1.0) * texel * s).rgb * 2.0;
    blurred /= 16.0;
    if (filter_mode == 0) {
        return original + sharpen * (original - blurred);
    }
    return blurred + sharpen * (original - blurred);
}

void fragment() {
    vec2 uv = UV;
    
    if (stereo_mode == 0) {
        ALBEDO = filtered_texture(main_texture, uv);
    } 
    else if (stereo_mode == 1) {
        if (int(VIEW_INDEX) == 0) {
            ALBEDO = filtered_texture(main_texture, vec2(uv.x * 0.5, uv.y));
        } else {
            ALBEDO = filtered_texture(main_texture, vec2(uv.x * 0.5 + 0.5, uv.y));
        }
    }
    else if (stereo_mode == 2) {
        if (int(VIEW_INDEX) == 0) {
            ALBEDO = filtered_texture(main_texture, vec2(uv.x * 0.5, uv.y * 0.5 + 0.25));
        } else {
            ALBEDO = filtered_texture(main_texture, vec2(uv.x * 0.5 + 0.5, uv.y * 0.5 + 0.25));
        }
    }
    else if (stereo_mode == 3 || stereo_mode == 4) {
        vec2 depth_texel = 1.0 / vec2(textureSize(depth_texture, 0));
        float parallax = 0.042;
        float half_parallax = parallax * 0.5;

        vec2 depth_uv = uv - vec2(half_parallax, 0.0);
        depth_uv = clamp(depth_uv, vec2(0.0), vec2(1.0));
        float depth = texture(depth_texture, depth_uv).r;

        float depth_diff = clamp(depth - convergence, -convergence, 1.0 - convergence);

        float dist_from_convergence = abs(depth - convergence);
        float zone_radius = 0.70;
        float fade_multiplier = smoothstep(0.0, zone_radius, dist_from_convergence);
        depth_diff *= fade_multiplier;

        float shift = parallax * depth_diff;

        bool is_left = (int(VIEW_INDEX) == 0);
        float eye_sign = is_left ? -1.0 : 1.0;

        if ((depth - convergence) < 0.0) {
            shift *= is_left ? balance_shift : (1.0 - balance_shift);
        } else {
            shift *= is_left ? (1.0 - balance_shift) : balance_shift;
        }

        float edge_width = 3.0 * depth_texel.x;
        float depth_left = texture(depth_texture, vec2(edge_width, 0.5)).r;
        float depth_right = texture(depth_texture, vec2(1.0 - edge_width, 0.5)).r;
        float max_edge_shift = max(abs(depth_left - convergence), abs(depth_right - convergence));
        float max_shift_possible = parallax * max_edge_shift;
        float vignette_bias = (convergence - 0.5) * 0.3;
        float vignette_start = mix(0.7 - vignette_bias, 1.0 - vignette_bias, clamp(max_shift_possible / 0.05, 0.0, 1.0));

        float h_dist = abs(uv.x - 0.5) * 2.0;
        float vignette = 1.0 - smoothstep(vignette_start, 1.0, pow(h_dist, 1.5));

        shift *= vignette;

        vec2 src_uv = vec2(clamp(uv.x - shift * eye_sign, 0.0, 1.0), uv.y);
        ALBEDO = filtered_texture(main_texture, src_uv);
    }
}
