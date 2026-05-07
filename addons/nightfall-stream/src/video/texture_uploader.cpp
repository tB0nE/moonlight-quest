#include "texture_uploader.h"
#include "yuv_shader.h"
#include <godot_cpp/variant/utility_functions.hpp>

using namespace godot;

TextureUploader::TextureUploader() {
    texture_mutex.instantiate();
}

TextureUploader::~TextureUploader() {
    cleanup();
}

void TextureUploader::setup(int width, int height, int format, int colorspace, int color_range) {
    RenderingServer *rs = RenderingServer::get_singleton();
    if (rs) {
        rs->call_on_render_thread(callable_mp(this, &TextureUploader::_render_thread_setup).bind(width, height, format, colorspace, color_range));
    }
}

void TextureUploader::_render_thread_setup(int width, int height, int format, int colorspace, int color_range) {
    std::lock_guard<godot::Mutex> lock(*(texture_mutex.ptr()));
    AVPixelFormat av_format = (AVPixelFormat)format;
    AVColorSpace av_colorspace = (AVColorSpace)colorspace;
    AVColorRange av_color_range = (AVColorRange)color_range;

    RenderingServer *rs = RenderingServer::get_singleton();
    if (rd) {
        for (int i = 0; i < 3; i++) {
            rd_texture_wrappers[i].unref();
            if (rs_texture_rid[i].is_valid()) {
                rs->free_rid(rs_texture_rid[i]);
                rs_texture_rid[i] = RID();
            }
            if (rd_texture_rid[i].is_valid()) {
                rd->free_rid(rd_texture_rid[i]);
                rd_texture_rid[i] = RID();
            }
        }
    }

    is_nv12 = (av_format == AV_PIX_FMT_NV12);
    bool is_yuv420p = (av_format == AV_PIX_FMT_YUV420P);

    if (!is_nv12 && !is_yuv420p) {
        if (av_format == AV_PIX_FMT_NONE) {
            is_nv12 = true;
        } else {
            use_shader_conversion = false;
            return;
        }
    }

    use_shader_conversion = true;
    current_width = width;
    current_height = height;

    int y_w = width;
    int y_h = height;
    int uv_w = width / 2;
    int uv_h = height / 2;

    rd = rs->get_rendering_device();
    if (rd) {
        auto create_rd_texture = [&](int idx, int w, int h, RenderingDevice::DataFormat fmt) {
            Ref<RDTextureFormat> tf;
            tf.instantiate();
            tf->set_width(w);
            tf->set_height(h);
            tf->set_depth(1);
            tf->set_array_layers(1);
            tf->set_format(fmt);
            tf->set_usage_bits(RenderingDevice::TEXTURE_USAGE_SAMPLING_BIT | RenderingDevice::TEXTURE_USAGE_CAN_UPDATE_BIT | RenderingDevice::TEXTURE_USAGE_CAN_COPY_FROM_BIT);
            tf->set_texture_type(RenderingDevice::TEXTURE_TYPE_2D);

            Ref<RDTextureView> tv;
            tv.instantiate();

            PackedByteArray data;
            data.resize(w * h * (fmt == RenderingDevice::DATA_FORMAT_R8G8_UNORM ? 2 : 1));
            if (fmt == RenderingDevice::DATA_FORMAT_R8G8_UNORM || idx > 0)
                data.fill(128);
            else
                data.fill(0);

            TypedArray<PackedByteArray> data_array;
            data_array.push_back(data);

            rd_texture_rid[idx] = rd->texture_create(tf, tv, data_array);
            rs_texture_rid[idx] = rs->texture_rd_create(rd_texture_rid[idx]);

            if (rd_texture_wrappers[idx].is_null()) {
                rd_texture_wrappers[idx].instantiate();
            }
            rd_texture_wrappers[idx]->set_texture_rd_rid(rd_texture_rid[idx]);
        };

        create_rd_texture(0, y_w, y_h, RenderingDevice::DATA_FORMAT_R8_UNORM);
        create_rd_texture(1, uv_w, uv_h, RenderingDevice::DATA_FORMAT_R8_UNORM);
        create_rd_texture(2, uv_w, uv_h, RenderingDevice::DATA_FORMAT_R8_UNORM);
    } else {
        plane_images[0] = Image::create(y_w, y_h, false, Image::FORMAT_L8);
        plane_images[0]->fill(Color(0, 0, 0));
        plane_textures[0] = ImageTexture::create_from_image(plane_images[0]);

        plane_images[1] = Image::create(uv_w, uv_h, false, Image::FORMAT_L8);
        plane_images[1]->fill(Color(0.5, 0.5, 0.5));
        plane_textures[1] = ImageTexture::create_from_image(plane_images[1]);

        plane_images[2] = Image::create(uv_w, uv_h, false, Image::FORMAT_L8);
        plane_images[2]->fill(Color(0.5, 0.5, 0.5));
        plane_textures[2] = ImageTexture::create_from_image(plane_images[2]);
    }

    if (yuv_shader.is_null()) {
        yuv_shader.instantiate();
        yuv_shader->set_code(YUV_SHADER_CODE);
    }
    if (shader_material.is_null()) {
        shader_material.instantiate();
        shader_material->set_shader(yuv_shader);
    }

    int matrix_type = 1;
    if (av_colorspace == AVCOL_SPC_BT470BG || av_colorspace == AVCOL_SPC_SMPTE170M)
        matrix_type = 0;
    else if (av_colorspace == AVCOL_SPC_BT2020_NCL || av_colorspace == AVCOL_SPC_BT2020_CL)
        matrix_type = 2;
    else if (width < 1280 && height < 720)
        matrix_type = 0;

    int range_val = (av_color_range == AVCOL_RANGE_JPEG) ? 1 : 0;
    bool shader_semi = is_nv12;
    if (rd && is_nv12) shader_semi = false;

    if (shader_material.is_valid()) {
        shader_material->set_shader_parameter("is_semi_planar", shader_semi);
        shader_material->set_shader_parameter("color_matrix_type", matrix_type);
        shader_material->set_shader_parameter("color_range", range_val);
        shader_material->set_shader_parameter("swap_uv", false);

        if (rd) {
            shader_material->set_shader_parameter("tex_y", rd_texture_wrappers[0]);
            shader_material->set_shader_parameter("tex_u", rd_texture_wrappers[1]);
            shader_material->set_shader_parameter("tex_v", rd_texture_wrappers[2]);
        } else {
            shader_material->set_shader_parameter("tex_y", plane_textures[0]);
            shader_material->set_shader_parameter("tex_u", plane_textures[1]);
            shader_material->set_shader_parameter("tex_v", plane_textures[2]);
        }
    }
}

void TextureUploader::update_from_frame(AVFrame *frame) {
    if (!frame || !use_shader_conversion) return;

    RenderingServer *rs = RenderingServer::get_singleton();

    if (rd) {
        std::lock_guard<godot::Mutex> lock(*(texture_mutex.ptr()));

        auto upload_rd = [&](int idx, int av_idx, int w, int h, int bpp) {
            int src_stride = frame->linesize[av_idx];
            int dst_stride = w * bpp;
            int required_size = dst_stride * h;

            if (rd_texture_buffers[idx].size() != required_size)
                rd_texture_buffers[idx].resize(required_size);

            uint8_t *dst = rd_texture_buffers[idx].ptrw();
            uint8_t *src = frame->data[av_idx];

            if (src_stride == dst_stride) {
                memcpy(dst, src, required_size);
            } else {
                for (int i = 0; i < h; i++)
                    memcpy(dst + i * dst_stride, src + i * src_stride, dst_stride);
            }
        };

        upload_rd(0, 0, frame->width, frame->height, 1);

        if (is_nv12) {
            int uv_w = frame->width / 2;
            int uv_h = frame->height / 2;
            int src_stride = frame->linesize[1];
            int dst_stride = uv_w;
            int required_size = dst_stride * uv_h;

            if (rd_texture_buffers[1].size() != required_size)
                rd_texture_buffers[1].resize(required_size);
            if (rd_texture_buffers[2].size() != required_size)
                rd_texture_buffers[2].resize(required_size);

            uint8_t *dst_u = rd_texture_buffers[1].ptrw();
            uint8_t *dst_v = rd_texture_buffers[2].ptrw();
            uint8_t *src = frame->data[1];

            for (int row = 0; row < uv_h; row++) {
                uint8_t *srow = src + row * src_stride;
                uint8_t *drow_u = dst_u + row * dst_stride;
                uint8_t *drow_v = dst_v + row * dst_stride;
                for (int x = 0; x < uv_w; x++) {
                    drow_u[x] = srow[x * 2 + 0];
                    drow_v[x] = srow[x * 2 + 1];
                }
            }
        } else {
            upload_rd(1, 1, frame->width / 2, frame->height / 2, 1);
            upload_rd(2, 2, frame->width / 2, frame->height / 2, 1);
        }

        pending_gpu_update.store(true);
        rs->call_on_render_thread(callable_mp(this, &TextureUploader::perform_gpu_update));
        return;
    }

    auto upload_plane = [&](int gl_idx, int av_idx, int w, int h, int bpp) {
        Ref<Image> img = plane_images[gl_idx];
        Ref<ImageTexture> tex = plane_textures[gl_idx];
        if (img.is_null() || img->is_empty() || tex.is_null()) return;

        int src_stride = frame->linesize[av_idx];
        int dst_stride = w * bpp;
        int required_size = dst_stride * h;

        if (plane_buffers[gl_idx].size() != required_size)
            plane_buffers[gl_idx].resize(required_size);

        uint8_t *dst = plane_buffers[gl_idx].ptrw();
        uint8_t *src = frame->data[av_idx];

        if (src_stride == dst_stride) {
            memcpy(dst, src, required_size);
        } else {
            for (int i = 0; i < h; i++)
                memcpy(dst + i * dst_stride, src + i * src_stride, dst_stride);
        }

        img->set_data(w, h, false, (bpp == 2) ? Image::FORMAT_RG8 : Image::FORMAT_L8, plane_buffers[gl_idx]);
        if (img->is_empty()) return;
        rs->texture_2d_update(tex->get_rid(), img, 0);
    };

    upload_plane(0, 0, frame->width, frame->height, 1);
    if (is_nv12) {
        upload_plane(1, 1, frame->width / 2, frame->height / 2, 2);
    } else {
        upload_plane(1, 1, frame->width / 2, frame->height / 2, 1);
        upload_plane(2, 2, frame->width / 2, frame->height / 2, 1);
    }
}

void TextureUploader::perform_gpu_update() {
    if (!rd) return;
    std::lock_guard<godot::Mutex> lock(*(texture_mutex.ptr()));
    if (pending_gpu_update.exchange(false)) {
        if (rd_texture_rid[0].is_valid())
            rd->texture_update(rd_texture_rid[0], 0, rd_texture_buffers[0]);
        if (rd_texture_rid[1].is_valid())
            rd->texture_update(rd_texture_rid[1], 0, rd_texture_buffers[1]);
        if (rd_texture_rid[2].is_valid())
            rd->texture_update(rd_texture_rid[2], 0, rd_texture_buffers[2]);
    }
}

void TextureUploader::cleanup() {
    RenderingServer *rs = RenderingServer::get_singleton();
    if (!rs) return;
    rs->call_on_render_thread(callable_mp(this, &TextureUploader::_render_thread_cleanup));
}

void TextureUploader::_render_thread_cleanup() {
    std::lock_guard<godot::Mutex> lock(*(texture_mutex.ptr()));
    RenderingServer *rs = RenderingServer::get_singleton();
    if (rd) {
        for (int i = 0; i < 3; i++) {
            rd_texture_wrappers[i].unref();
            if (rs_texture_rid[i].is_valid()) {
                rs->free_rid(rs_texture_rid[i]);
                rs_texture_rid[i] = RID();
            }
            if (rd_texture_rid[i].is_valid()) {
                rd->free_rid(rd_texture_rid[i]);
                rd_texture_rid[i] = RID();
            }
        }
        rd = nullptr;
    }
    use_shader_conversion = false;
}

void TextureUploader::_bind_methods() {
    ClassDB::bind_method(D_METHOD("setup", "width", "height", "format", "colorspace", "color_range"), &TextureUploader::setup);
    ClassDB::bind_method(D_METHOD("cleanup"), &TextureUploader::cleanup);
    ClassDB::bind_method(D_METHOD("get_shader_material"), &TextureUploader::get_shader_material);
    ClassDB::bind_method(D_METHOD("perform_gpu_update"), &TextureUploader::perform_gpu_update);
}
