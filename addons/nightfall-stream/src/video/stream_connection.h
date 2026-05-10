#pragma once

#include "video/depth_bridge.h"
#include <godot_cpp/classes/node.hpp>
#include <godot_cpp/classes/shader_material.hpp>
#include <atomic>
#include <string>
#include <thread>
#include <mutex>
#include <condition_variable>
#include <vector>
#include <chrono>

extern "C" {
#include <Limelight.h>
#include <libavutil/pixfmt.h>
#include <libavutil/frame.h>
struct AVPacket;
struct AVFrame;
}

namespace godot {

class FfmpegDecoder;
class TextureUploader;
class AudioRenderer;
class InputBridge;

class StreamConnection : public Node {
    GDCLASS(StreamConnection, Node);

public:
    StreamConnection();
    ~StreamConnection();

    void start(const String &host, const Dictionary &server_info, const Dictionary &stream_config, bool disable_hw = false);
    void stop();
    bool is_streaming() const;
    int probe_video_format(int codec_preference, bool disable_hw);

    Ref<FfmpegDecoder> get_decoder() const;
    Ref<TextureUploader> get_texture_uploader() const;
    Ref<ShaderMaterial> get_shader_material() const;
    Ref<AudioRenderer> get_audio_renderer() const;
    Ref<InputBridge> get_input_bridge() const;
    Ref<DepthBridge> get_depth_bridge() const;

    int get_frames_dropped() const;
    int get_frames_decoded() const;
    int get_decode_queue_size() const;
    int get_last_frame_latency_us() const;

    String get_decoder_name() const;
    int get_video_width() const;
    int get_video_height() const;
    bool is_hw_decode() const;

    static String get_error_string(int error_code);

protected:
    static void _bind_methods();

private:
    static StreamConnection *active_instance_;

    static int _cb_decoder_setup(int videoFormat, int width, int height, int redrawRate, void *context, int drFlags);
    static void _cb_decoder_start();
    static void _cb_decoder_stop();
    static void _cb_decoder_cleanup();
    static int _cb_submit_decode_unit(PDECODE_UNIT decodeUnit);

    static void _cb_connection_started();
    static void _cb_connection_terminated(int errorCode);
    static void _cb_stage_starting(int stage);
    static void _cb_stage_complete(int stage);
    static void _cb_stage_failed(int stage, int errorCode);
    static void _cb_rumble(unsigned short controllerNumber, unsigned short lowFreqMotor, unsigned short highFreqMotor);
    static void _cb_connection_status_update(int connectionStatus);
    static void _cb_set_hdr_mode(bool hdrEnabled);
    static void _cb_rumble_triggers(uint16_t controllerNumber, uint16_t leftTriggerMotor, uint16_t rightTriggerMotor);
    static void _cb_set_motion_event_state(uint16_t controllerNumber, uint8_t motionType, uint16_t reportRateHz);
    static void _cb_set_controller_led(uint16_t controllerNumber, uint8_t r, uint8_t g, uint8_t b);
    static void _cb_log_message(const char *format, ...);

    void _connection_thread_func();
    void _decode_thread_func();
    void _clear_packet_queue();

    AVColorSpace _resolve_frame_colorspace(AVFrame *frame) const;

    std::atomic<bool> is_streaming_{false};
    std::atomic<bool> decoder_ready_{false};

    Ref<FfmpegDecoder> decoder_;
    Ref<TextureUploader> uploader_;
    Ref<AudioRenderer> audio_renderer_;
    Ref<InputBridge> input_bridge_;
    Ref<DepthBridge> depth_bridge_;

    std::atomic<int> frames_dropped_{0};
    std::atomic<int> frames_decoded_{0};
    std::atomic<int> last_frame_latency_us_{0};
    std::atomic<int64_t> last_submit_time_us_{0};

    std::vector<AVPacket *> packet_queue_;
    mutable std::mutex queue_mutex_;
    std::condition_variable queue_cv_;
    std::thread decode_thread_;
    std::thread connection_thread_;

    String host_address_;
    std::string host_address_std_;
    std::string rtsp_url_std_;
    std::string app_version_std_;
    std::string gfe_version_std_;
    SERVER_INFORMATION server_info_{};
    STREAM_CONFIGURATION stream_config_{};

    std::chrono::steady_clock::time_point last_idr_request_;
    int active_video_format_ = 0;
    AVColorSpace current_colorspace_ = AVCOL_SPC_BT709;
    AVColorRange current_color_range_ = AVCOL_RANGE_UNSPECIFIED;
};

} // namespace godot
