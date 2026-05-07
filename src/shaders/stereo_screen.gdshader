shader_type spatial;
render_mode unshaded;

uniform sampler2D main_texture : source_color, filter_linear, repeat_disable;
uniform sampler2D depth_texture : hint_default_white, filter_linear_mipmap;
uniform int stereo_mode = 0;
uniform float parallax_depth = 0.5;
uniform float depth_gain = 1.0;
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
        float depth = texture(depth_texture, uv).r;
        
        float depth_diff;
        if (depth < convergence) {
            depth_diff = (depth - convergence) / max(convergence, 0.001);
        } else {
            depth_diff = (depth - convergence) / max(1.0 - convergence, 0.001);
        }
        depth_diff *= depth_gain;
        
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
