#pragma once

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/classes/image.hpp>
#include <godot_cpp/classes/image_texture.hpp>
#include <godot_cpp/classes/rd_texture_format.hpp>
#include <godot_cpp/classes/rd_texture_view.hpp>
#include <godot_cpp/classes/rendering_device.hpp>
#include <godot_cpp/classes/rendering_server.hpp>
#include <godot_cpp/classes/shader.hpp>
#include <godot_cpp/classes/shader_material.hpp>
#include <godot_cpp/classes/texture2drd.hpp>
#include <godot_cpp/classes/mutex.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <atomic>

extern "C" {
#include <libavutil/pixfmt.h>
#include <libavutil/frame.h>
}

namespace godot {

class TextureUploader : public RefCounted {
    GDCLASS(TextureUploader, RefCounted);

public:
    TextureUploader();
    ~TextureUploader();

    void setup(int width, int height, int format, int colorspace, int color_range);
    void cleanup();
    void update_from_frame(AVFrame *frame);
    void update_colorspace(int colorspace, int color_range);
    void perform_gpu_update();

    Ref<ShaderMaterial> get_shader_material() const { return shader_material; }

protected:
    static void _bind_methods();

private:
    void _render_thread_setup(int width, int height, int format, int colorspace, int color_range);
    void _render_thread_cleanup();

    RenderingDevice *rd = nullptr;
    RID rd_texture_rid[3];
    RID rs_texture_rid[3];
    Ref<Texture2DRD> rd_texture_wrappers[3];
    PackedByteArray rd_texture_buffers[3];

    Ref<Image> plane_images[3];
    Ref<ImageTexture> plane_textures[3];
    PackedByteArray plane_buffers[3];

    Ref<ShaderMaterial> shader_material;
    Ref<Shader> yuv_shader;
    bool use_shader_conversion = false;
    bool is_nv12 = false;
    std::atomic<bool> pending_gpu_update{false};
    Ref<Mutex> texture_mutex;

    int current_width = 0;
    int current_height = 0;
};

} // namespace godot
