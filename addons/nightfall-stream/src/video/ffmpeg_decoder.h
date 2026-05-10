#pragma once

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/string.hpp>
#include <atomic>
#include <vector>

extern "C" {
struct AVCodec;
struct AVCodecContext;
struct AVFrame;
struct AVPacket;
struct AVBufferRef;
#include <libavcodec/avcodec.h>
#include <libavutil/hwcontext.h>
#include <libavutil/pixfmt.h>
}

namespace godot {

class FfmpegDecoder : public RefCounted {
    GDCLASS(FfmpegDecoder, RefCounted);

public:
    enum CodecFamily {
        CODEC_FAMILY_H264 = 0,
        CODEC_FAMILY_H265 = 1,
        CODEC_FAMILY_AV1 = 2
    };

    struct DecodedFrameInfo {
        int width = 0;
        int height = 0;
        AVPixelFormat format = AV_PIX_FMT_NONE;
        AVColorSpace colorspace = AVCOL_SPC_BT709;
        AVColorRange color_range = AVCOL_RANGE_UNSPECIFIED;
        bool is_hw_frame = false;
    };

    FfmpegDecoder();
    ~FfmpegDecoder();

    int probe_video_format(int codec_preference, bool disable_hw);
    int setup(int video_format, int width, int height, bool disable_hw);
    void cleanup();

    AVFrame *get_sw_frame();

    String get_decoder_name() const;
    bool is_hw_decode() const;
    int get_video_width() const;
    int get_video_height() const;

    const AVCodec *get_codec() const { return v_codec; }
    AVCodecContext *get_codec_context() const { return v_codec_ctx; }

    static Vector<String> get_candidate_decoders(int codec_family);

private:
    const AVCodec *v_codec = nullptr;
    AVCodecContext *v_codec_ctx = nullptr;
    AVFrame *sw_frame = nullptr;
    AVFrame *decode_frame = nullptr;
    AVBufferRef *hw_device_ctx = nullptr;
    AVPixelFormat hw_pix_fmt = AV_PIX_FMT_NONE;
    bool is_hw_decode_active = false;
    int video_width = 0;
    int video_height = 0;

    Vector<AVHWDeviceType> _get_supported_hw_devices();
    int _try_open_decoder(const String &codec_name, int width, int height, AVHWDeviceType hw_type, bool disable_hw);

    static enum AVPixelFormat _get_hw_format_callback(AVCodecContext *ctx, const enum AVPixelFormat *pix_fmts);

protected:
    static void _bind_methods();
};

} // namespace godot
