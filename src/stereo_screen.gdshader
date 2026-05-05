shader_type spatial;
render_mode unshaded;

uniform sampler2D main_texture : source_color, filter_linear;
uniform sampler2D depth_texture : hint_default_white, filter_linear_mipmap;
uniform int stereo_mode = 0;
uniform float parallax_depth = 0.5;
uniform float convergence = 0.5;
uniform float balance_shift = 0.5;
uniform int filter_mode = 0;

vec3 filtered_texture(sampler2D tex, vec2 uv) {
    if (filter_mode == 0) {
        return texture(tex, uv).rgb;
    }
    float s = float(filter_mode) * 0.5;
    vec2 texel = 1.0 / vec2(textureSize(tex, 0));
    vec3 c = texture(tex, uv).rgb * 4.0;
    c += texture(tex, uv + vec2(-1.0, -1.0) * texel * s).rgb;
    c += texture(tex, uv + vec2( 1.0, -1.0) * texel * s).rgb;
    c += texture(tex, uv + vec2(-1.0,  1.0) * texel * s).rgb;
    c += texture(tex, uv + vec2( 1.0,  1.0) * texel * s).rgb;
    c += texture(tex, uv + vec2(-1.0,  0.0) * texel * s).rgb * 2.0;
    c += texture(tex, uv + vec2( 1.0,  0.0) * texel * s).rgb * 2.0;
    c += texture(tex, uv + vec2( 0.0, -1.0) * texel * s).rgb * 2.0;
    c += texture(tex, uv + vec2( 0.0,  1.0) * texel * s).rgb * 2.0;
    return c / 16.0;
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
        vec3 color = filtered_texture(main_texture, src_uv);
        
        ALBEDO = mix(filtered_texture(main_texture, uv), color, vignette);
    }
}
