#include "stream_connection.h"
#include "ffmpeg_decoder.h"
#include "texture_uploader.h"
#include "audio/audio_renderer.h"
#include "input/input_bridge.h"
#include "video/depth_bridge.h"

#include <godot_cpp/variant/utility_functions.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>

#include <cerrno>
#include <cstring>
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <unistd.h>

#ifdef __ANDROID__
#include <android/log.h>
#define NF_LOG(...) __android_log_print(ANDROID_LOG_INFO, "StreamConnection", __VA_ARGS__)
#else
#define NF_LOG(...) printf(__VA_ARGS__)
#endif

extern "C" {
#include <libavcodec/avcodec.h>
#include <libavutil/pixfmt.h>
}

using namespace godot;

StreamConnection *StreamConnection::active_instance_ = nullptr;

StreamConnection::StreamConnection() {
    decoder_.instantiate();
    uploader_.instantiate();
    audio_renderer_.instantiate();
    input_bridge_.instantiate();
    depth_bridge_.instantiate();
}

StreamConnection::~StreamConnection() {
    stop();
}

int StreamConnection::_cb_decoder_setup(int videoFormat, int width, int height, int redrawRate, void *context, int drFlags) {
    auto *self = active_instance_;
    if (!self) return -1;

    self->active_video_format_ = videoFormat;
    NF_LOG("[StreamConnection] Decoder setup: format=0x%x %dx%d@%dfps\n", videoFormat, width, height, redrawRate);

    int ret = self->decoder_->setup(videoFormat, width, height, false);
    if (ret != 0) return ret;

    int pix_fmt = AV_PIX_FMT_YUV420P;
    if (self->decoder_->is_hw_decode()) {
        pix_fmt = AV_PIX_FMT_NV12;
    }

    self->uploader_->setup(width, height,
                           pix_fmt,
                           (int)AVCOL_SPC_BT709,
                           (int)AVCOL_RANGE_UNSPECIFIED);

    self->decoder_ready_.store(true);
    return 0;
}

void StreamConnection::_cb_decoder_start() {
    NF_LOG("[StreamConnection] Decoder start\n");
}

void StreamConnection::_cb_decoder_stop() {
    NF_LOG("[StreamConnection] Decoder stop\n");
    auto *self = active_instance_;
    if (self) {
        self->decoder_ready_.store(false);
    }
}

void StreamConnection::_cb_decoder_cleanup() {
    NF_LOG("[StreamConnection] Decoder cleanup\n");
    auto *self = active_instance_;
    if (self) {
        self->decoder_->cleanup();
        self->uploader_->cleanup();
        self->decoder_ready_.store(false);
    }
}

int StreamConnection::_cb_submit_decode_unit(PDECODE_UNIT decodeUnit) {
    auto *self = active_instance_;
    if (!self || !self->is_streaming_.load()) return DR_OK;

    static int submit_count = 0;
    if (submit_count == 0) {
        NF_LOG("[StreamConnection] First submit: self=%p\n", self);
    }
    if (++submit_count <= 5 || submit_count % 300 == 0) {
        NF_LOG("[StreamConnection] Submit decode unit #%d: fullLen=%d\n", submit_count, decodeUnit->fullLength);
    }

    AVPacket *pkt = av_packet_alloc();
    if (!pkt) return DR_OK;

    int ret = av_new_packet(pkt, decodeUnit->fullLength);
    if (ret < 0) {
        av_packet_free(&pkt);
        return DR_OK;
    }

    int offset = 0;
    PLENTRY entry = decodeUnit->bufferList;
    while (entry != nullptr) {
        if (offset + entry->length <= decodeUnit->fullLength) {
            memcpy(pkt->data + offset, entry->data, entry->length);
            offset += entry->length;
        }
        entry = entry->next;
    }

    pkt->pts = decodeUnit->presentationTimeUs;

    {
        std::lock_guard<std::mutex> lock(self->queue_mutex_);
        if (self->packet_queue_.size() > 512) {
            av_packet_free(&pkt);
            self->frames_dropped_.fetch_add(1);
            return DR_OK;
        }
        if (!self->decoder_->is_hw_decode() && self->packet_queue_.size() > 128) {
            self->_clear_packet_queue();
            LiRequestIdrFrame();
            av_packet_free(&pkt);
            self->frames_dropped_.fetch_add(1);
            return DR_NEED_IDR;
        }
        self->packet_queue_.push_back(pkt);
    }
    self->queue_cv_.notify_one();

    return DR_OK;
}

void StreamConnection::_cb_connection_started() {
    NF_LOG("[StreamConnection] Connection started\n");
    auto *self = active_instance_;
    if (self) {
        self->is_streaming_.store(true);
        self->call_deferred("emit_signal", "stream_started");
    }
}

void StreamConnection::_cb_connection_terminated(int errorCode) {
    NF_LOG("[StreamConnection] Connection terminated: %d\n", errorCode);
    auto *self = active_instance_;
    if (self) {
        self->is_streaming_.store(false);
        self->queue_cv_.notify_all();
        self->call_deferred("emit_signal", "stream_terminated", errorCode);
    }
}

void StreamConnection::_cb_stage_starting(int stage) {
    NF_LOG("[StreamConnection] Stage starting: %s\n", LiGetStageName(stage));
    auto *self = active_instance_;
    if (self) {
        self->call_deferred("emit_signal", "stage_starting", String(LiGetStageName(stage)));
    }
}

void StreamConnection::_cb_stage_complete(int stage) {
    NF_LOG("[StreamConnection] Stage complete: %s\n", LiGetStageName(stage));
    auto *self = active_instance_;
    if (self) {
        self->call_deferred("emit_signal", "stage_complete", String(LiGetStageName(stage)));
    }
}

void StreamConnection::_cb_stage_failed(int stage, int errorCode) {
    NF_LOG("[StreamConnection] Stage failed: %s (error %d)\n", LiGetStageName(stage), errorCode);
    auto *self = active_instance_;
    if (self) {
        self->call_deferred("emit_signal", "stage_failed", String(LiGetStageName(stage)), errorCode);
    }
}

void StreamConnection::_cb_rumble(unsigned short controllerNumber, unsigned short lowFreqMotor, unsigned short highFreqMotor) {
    auto *self = active_instance_;
    if (self) {
        self->call_deferred("emit_signal", "controller_rumble", (int)controllerNumber, (int)lowFreqMotor, (int)highFreqMotor);
    }
}

void StreamConnection::_cb_connection_status_update(int connectionStatus) {
    auto *self = active_instance_;
    if (self) {
        self->call_deferred("emit_signal", "connection_status_update", connectionStatus);
    }
}

void StreamConnection::_cb_set_hdr_mode(bool hdrEnabled) {
    auto *self = active_instance_;
    if (self) {
        self->call_deferred("emit_signal", "hdr_mode_changed", hdrEnabled);
    }
}

void StreamConnection::_cb_rumble_triggers(uint16_t controllerNumber, uint16_t leftTriggerMotor, uint16_t rightTriggerMotor) {
    auto *self = active_instance_;
    if (self) {
        self->call_deferred("emit_signal", "controller_trigger_rumble", (int)controllerNumber, (int)leftTriggerMotor, (int)rightTriggerMotor);
    }
}

void StreamConnection::_cb_set_motion_event_state(uint16_t controllerNumber, uint8_t motionType, uint16_t reportRateHz) {
    auto *self = active_instance_;
    if (self) {
        self->call_deferred("emit_signal", "motion_event_requested", (int)controllerNumber, (int)motionType, (int)reportRateHz);
    }
}

void StreamConnection::_cb_set_controller_led(uint16_t controllerNumber, uint8_t r, uint8_t g, uint8_t b) {
    auto *self = active_instance_;
    if (self) {
        self->call_deferred("emit_signal", "controller_led_set", (int)controllerNumber, (int)r, (int)g, (int)b);
    }
}

void StreamConnection::_connection_thread_func() {
    DECODER_RENDERER_CALLBACKS drCallbacks{};
    LiInitializeVideoCallbacks(&drCallbacks);
    drCallbacks.setup = _cb_decoder_setup;
    drCallbacks.start = _cb_decoder_start;
    drCallbacks.stop = _cb_decoder_stop;
    drCallbacks.cleanup = _cb_decoder_cleanup;
    drCallbacks.submitDecodeUnit = _cb_submit_decode_unit;
    drCallbacks.capabilities = 0;

    AUDIO_RENDERER_CALLBACKS arCallbacks{};
    LiInitializeAudioCallbacks(&arCallbacks);
    arCallbacks.init = AudioRenderer::_cb_init;
    arCallbacks.start = AudioRenderer::_cb_start;
    arCallbacks.stop = AudioRenderer::_cb_stop;
    arCallbacks.cleanup = AudioRenderer::_cb_cleanup;
    arCallbacks.decodeAndPlaySample = AudioRenderer::_cb_decode_and_play_sample;
    arCallbacks.capabilities = CAPABILITY_SUPPORTS_ARBITRARY_AUDIO_DURATION;

    CONNECTION_LISTENER_CALLBACKS clCallbacks{};
    LiInitializeConnectionCallbacks(&clCallbacks);
    clCallbacks.stageStarting = _cb_stage_starting;
    clCallbacks.stageComplete = _cb_stage_complete;
    clCallbacks.stageFailed = _cb_stage_failed;
    clCallbacks.connectionStarted = _cb_connection_started;
    clCallbacks.connectionTerminated = _cb_connection_terminated;
    clCallbacks.rumble = _cb_rumble;
    clCallbacks.connectionStatusUpdate = _cb_connection_status_update;
    clCallbacks.setHdrMode = _cb_set_hdr_mode;
    clCallbacks.rumbleTriggers = _cb_rumble_triggers;
    clCallbacks.setMotionEventState = _cb_set_motion_event_state;
    clCallbacks.setControllerLED = _cb_set_controller_led;

    NF_LOG("[StreamConnection] Starting connection to %s %dx%d@%dfps\n",
           server_info_.address ? server_info_.address : "(null)", stream_config_.width, stream_config_.height, stream_config_.fps);

    if (!server_info_.address || strlen(server_info_.address) == 0) {
        NF_LOG("[StreamConnection] ERROR: server address is empty! host_address_std_=%s\n", host_address_std_.c_str());
    }

    NF_LOG("[StreamConnection] server_info: address=%s rtsp=%s appVer=%s gfeVer=%s codecMode=%d\n",
           server_info_.address ? server_info_.address : "(null)",
           server_info_.rtspSessionUrl ? server_info_.rtspSessionUrl : "(null)",
           server_info_.serverInfoAppVersion ? server_info_.serverInfoAppVersion : "(null)",
           server_info_.serverInfoGfeVersion ? server_info_.serverInfoGfeVersion : "(null)",
           server_info_.serverCodecModeSupport);

    NF_LOG("[StreamConnection] stream_config: %dx%d@%dfps bitrate=%d packetSize=%d streamingRemotely=%d audioConfig=0x%x videoFormats=0x%x encryption=0x%x colorSpace=%d colorRange=%d\n",
           stream_config_.width, stream_config_.height, stream_config_.fps,
           stream_config_.bitrate, stream_config_.packetSize, stream_config_.streamingRemotely,
           stream_config_.audioConfiguration, stream_config_.supportedVideoFormats,
           stream_config_.encryptionFlags, stream_config_.colorSpace, stream_config_.colorRange);

    int test_sock = socket(AF_INET, SOCK_STREAM, 0);
    if (test_sock >= 0) {
        struct sockaddr_in addr;
        memset(&addr, 0, sizeof(addr));
        addr.sin_family = AF_INET;
        addr.sin_port = htons(48010);
        inet_pton(AF_INET, host_address_std_.c_str(), &addr.sin_addr);
        int cr = ::connect(test_sock, (struct sockaddr*)&addr, sizeof(addr));
        NF_LOG("[StreamConnection] Pre-flight TCP test to %s:48010: sock=%d connect=%d errno=%d\n",
               host_address_std_.c_str(), test_sock, cr, errno);
        close(test_sock);
    } else {
        NF_LOG("[StreamConnection] Pre-flight TCP test: socket() failed errno=%d\n", errno);
    }

    int ret = LiStartConnection(&server_info_, &stream_config_, &clCallbacks, &drCallbacks, &arCallbacks, nullptr, 0, nullptr, 0);

    NF_LOG("[StreamConnection] LiStartConnection returned: %d (errno=%d)\n", ret, errno);

    if (ret != 0) {
        is_streaming_.store(false);
        queue_cv_.notify_all();
        call_deferred("emit_signal", "stream_terminated", ret);
    }
}

void StreamConnection::_decode_thread_func() {
    AVPacket *pkt = nullptr;
    NF_LOG("[StreamConnection] Decode thread started this=%p\n", this);

    {
        std::unique_lock<std::mutex> lock(queue_mutex_);
        queue_cv_.wait_for(lock, std::chrono::milliseconds(10000), [this] {
            return is_streaming_.load() || !packet_queue_.empty();
        });
        if (!is_streaming_.load()) {
            NF_LOG("[StreamConnection] Decode thread: stream never started, exiting\n");
            return;
        }
    }

    NF_LOG("[StreamConnection] Decode thread: stream active, starting decode loop\n");

    while (true) {
        {
            std::unique_lock<std::mutex> lock(queue_mutex_);
            queue_cv_.wait_for(lock, std::chrono::milliseconds(5), [this] {
                return !packet_queue_.empty() || !is_streaming_.load();
            });

            if (!is_streaming_.load() && packet_queue_.empty()) {
                NF_LOG("[StreamConnection] Decode thread exiting: streaming=%d queue=%d\n",
                    is_streaming_.load(), (int)packet_queue_.size());
                break;
            }

            if (packet_queue_.empty()) continue;

            pkt = packet_queue_.front();
            packet_queue_.erase(packet_queue_.begin());
        }

        if (!pkt) continue;

        {
            AVCodecContext *ctx = decoder_->get_codec_context();
            if (!ctx) {
                av_packet_free(&pkt);
                continue;
            }

            int send_ret = avcodec_send_packet(ctx, pkt);
            av_packet_free(&pkt);

            if (send_ret < 0 && send_ret != AVERROR(EAGAIN) && send_ret != AVERROR_EOF) {
                continue;
            }

            while (true) {
                AVFrame *tmp = av_frame_alloc();
                int recv_ret = avcodec_receive_frame(ctx, tmp);

                if (recv_ret == AVERROR(EAGAIN) || recv_ret == AVERROR_EOF) {
                    av_frame_free(&tmp);
                    break;
                }
                if (recv_ret < 0) {
                    av_frame_free(&tmp);
                    static int recv_fail_count = 0;
                    if (++recv_fail_count <= 5) {
                        NF_LOG("[StreamConnection] Receive frame failed: %d\n", recv_ret);
                    }
                    break;
                }

                static int decode_ok_count = 0;
                if (++decode_ok_count <= 5 || decode_ok_count % 300 == 0) {
                    NF_LOG("[StreamConnection] Decoded frame #%d: %dx%d format=%d\n", decode_ok_count, tmp->width, tmp->height, tmp->format);
                }

                bool skip = false;
                {
                    std::lock_guard<std::mutex> lock(queue_mutex_);
                    if (packet_queue_.size() > 12) {
                        skip = true;
                    }
                }

                if (!skip) {
                    uploader_->update_from_frame(tmp);
                }

                av_frame_free(&tmp);
            }
        }
    }

    {
        std::lock_guard<std::mutex> lock(queue_mutex_);
        _clear_packet_queue();
    }
}

void StreamConnection::_clear_packet_queue() {
    for (auto *p : packet_queue_) {
        av_packet_free(&p);
    }
    packet_queue_.clear();
}

void StreamConnection::start(const String &host, const Dictionary &server_info, const Dictionary &stream_config, bool disable_hw) {
    NF_LOG("[StreamConnection] start() called: is_streaming=%d conn_thread_joinable=%d\n", is_streaming_.load(), connection_thread_.joinable());

    if (connection_thread_.joinable()) {
        NF_LOG("[StreamConnection] Joining previous connection thread\n");
        is_streaming_.store(false);
        decoder_ready_.store(false);
        queue_cv_.notify_all();
        LiInterruptConnection();
        connection_thread_.join();
        LiStopConnection();
    }

    if (decode_thread_.joinable()) {
        decode_thread_.join();
    }

    {
        std::lock_guard<std::mutex> lock(queue_mutex_);
        _clear_packet_queue();
    }

    host_address_ = host;

    LiInitializeServerInformation(&server_info_);
    host_address_std_ = host.utf8().get_data();
    server_info_.address = host_address_std_.c_str();

    if (server_info.has("rtsp_session_url")) {
        rtsp_url_std_ = String(server_info["rtsp_session_url"]).utf8().get_data();
        server_info_.rtspSessionUrl = rtsp_url_std_.c_str();
    }
    if (server_info.has("server_app_version")) {
        app_version_std_ = String(server_info["server_app_version"]).utf8().get_data();
        server_info_.serverInfoAppVersion = app_version_std_.c_str();
    }
    if (server_info.has("server_gfe_version")) {
        gfe_version_std_ = String(server_info["server_gfe_version"]).utf8().get_data();
        server_info_.serverInfoGfeVersion = gfe_version_std_.c_str();
    }
    if (server_info.has("server_codec_mode_support")) {
        server_info_.serverCodecModeSupport = (int)server_info["server_codec_mode_support"];
    }

    LiInitializeStreamConfiguration(&stream_config_);
    stream_config_.width = (int)stream_config.get("width", 1920);
    stream_config_.height = (int)stream_config.get("height", 1080);
    stream_config_.fps = (int)stream_config.get("fps", 60);
    stream_config_.bitrate = (int)stream_config.get("bitrate", 20000);
    stream_config_.packetSize = (int)stream_config.get("packet_size", 1024);
    stream_config_.streamingRemotely = (int)stream_config.get("streaming_remotely", STREAM_CFG_AUTO);
    stream_config_.audioConfiguration = (int)stream_config.get("audio_configuration", AUDIO_CONFIGURATION_STEREO);
    stream_config_.supportedVideoFormats = (int)stream_config.get("supported_video_formats", VIDEO_FORMAT_MASK_H264);
    stream_config_.clientRefreshRateX100 = (int)stream_config.get("client_refresh_rate_x100", 0);
    stream_config_.colorSpace = (int)stream_config.get("color_space", COLORSPACE_REC_709);
    stream_config_.colorRange = (int)stream_config.get("color_range", COLOR_RANGE_LIMITED);
    stream_config_.encryptionFlags = (int)stream_config.get("encryption_flags", ENCFLG_ALL);

    if (stream_config.has("remote_input_aes_key")) {
        PackedByteArray key = stream_config["remote_input_aes_key"];
        if (key.size() == 16) {
            memcpy(stream_config_.remoteInputAesKey, key.ptr(), 16);
        }
    }
    if (stream_config.has("remote_input_aes_iv")) {
        PackedByteArray iv = stream_config["remote_input_aes_iv"];
        if (iv.size() == 16) {
            memcpy(stream_config_.remoteInputAesIv, iv.ptr(), 16);
        }
    }

    active_instance_ = this;
    AudioRenderer::active_instance_ = audio_renderer_.ptr();
    last_idr_request_ = std::chrono::steady_clock::now();

    connection_thread_ = std::thread(&StreamConnection::_connection_thread_func, this);
    decode_thread_ = std::thread(&StreamConnection::_decode_thread_func, this);
}

void StreamConnection::stop() {
    if (!is_streaming_.load() && !connection_thread_.joinable()) return;

    is_streaming_.store(false);
    decoder_ready_.store(false);
    queue_cv_.notify_all();

    LiInterruptConnection();

    if (connection_thread_.joinable()) {
        connection_thread_.join();
    }

    LiStopConnection();

    if (decode_thread_.joinable()) {
        decode_thread_.join();
    }

    {
        std::lock_guard<std::mutex> lock(queue_mutex_);
        _clear_packet_queue();
    }

    if (audio_renderer_.is_valid()) {
        audio_renderer_->cleanup();
    }

    active_instance_ = nullptr;
    AudioRenderer::active_instance_ = nullptr;
}

bool StreamConnection::is_streaming() const {
    return is_streaming_.load();
}

int StreamConnection::probe_video_format(int codec_preference, bool disable_hw) {
    if (!decoder_.is_valid()) return VIDEO_FORMAT_MASK_H264;
    return decoder_->probe_video_format(codec_preference, disable_hw);
}

Ref<FfmpegDecoder> StreamConnection::get_decoder() const {
    return decoder_;
}

Ref<TextureUploader> StreamConnection::get_texture_uploader() const {
    return uploader_;
}

Ref<ShaderMaterial> StreamConnection::get_shader_material() const {
    if (uploader_.is_valid()) {
        return uploader_->get_shader_material();
    }
    return nullptr;
}

Ref<AudioRenderer> StreamConnection::get_audio_renderer() const {
    return audio_renderer_;
}

Ref<InputBridge> StreamConnection::get_input_bridge() const {
    return input_bridge_;
}

Ref<DepthBridge> StreamConnection::get_depth_bridge() const {
    return depth_bridge_;
}

int StreamConnection::get_frames_dropped() const {
    return frames_dropped_.load();
}

int StreamConnection::get_last_frame_latency_us() const {
    return last_frame_latency_us_.load();
}

void StreamConnection::_bind_methods() {
    ClassDB::bind_method(D_METHOD("start", "host", "server_info", "stream_config", "disable_hw"), &StreamConnection::start, DEFVAL(false));
    ClassDB::bind_method(D_METHOD("stop"), &StreamConnection::stop);
    ClassDB::bind_method(D_METHOD("is_streaming"), &StreamConnection::is_streaming);
    ClassDB::bind_method(D_METHOD("probe_video_format", "codec_preference", "disable_hw"), &StreamConnection::probe_video_format);
    ClassDB::bind_method(D_METHOD("get_decoder"), &StreamConnection::get_decoder);
    ClassDB::bind_method(D_METHOD("get_texture_uploader"), &StreamConnection::get_texture_uploader);
    ClassDB::bind_method(D_METHOD("get_shader_material"), &StreamConnection::get_shader_material);
    ClassDB::bind_method(D_METHOD("get_audio_renderer"), &StreamConnection::get_audio_renderer);
    ClassDB::bind_method(D_METHOD("get_input_bridge"), &StreamConnection::get_input_bridge);
    ClassDB::bind_method(D_METHOD("get_depth_bridge"), &StreamConnection::get_depth_bridge);
    ClassDB::bind_method(D_METHOD("get_frames_dropped"), &StreamConnection::get_frames_dropped);
    ClassDB::bind_method(D_METHOD("get_last_frame_latency_us"), &StreamConnection::get_last_frame_latency_us);

    ADD_SIGNAL(MethodInfo("stream_started"));
    ADD_SIGNAL(MethodInfo("stream_terminated", PropertyInfo(Variant::INT, "error_code")));
    ADD_SIGNAL(MethodInfo("stage_starting", PropertyInfo(Variant::STRING, "stage_name")));
    ADD_SIGNAL(MethodInfo("stage_complete", PropertyInfo(Variant::STRING, "stage_name")));
    ADD_SIGNAL(MethodInfo("stage_failed", PropertyInfo(Variant::STRING, "stage_name"), PropertyInfo(Variant::INT, "error_code")));
    ADD_SIGNAL(MethodInfo("controller_rumble", PropertyInfo(Variant::INT, "controller"), PropertyInfo(Variant::INT, "low_freq"), PropertyInfo(Variant::INT, "high_freq")));
    ADD_SIGNAL(MethodInfo("controller_trigger_rumble", PropertyInfo(Variant::INT, "controller"), PropertyInfo(Variant::INT, "left_motor"), PropertyInfo(Variant::INT, "right_motor")));
    ADD_SIGNAL(MethodInfo("motion_event_requested", PropertyInfo(Variant::INT, "controller"), PropertyInfo(Variant::INT, "motion_type"), PropertyInfo(Variant::INT, "rate_hz")));
    ADD_SIGNAL(MethodInfo("controller_led_set", PropertyInfo(Variant::INT, "controller"), PropertyInfo(Variant::INT, "r"), PropertyInfo(Variant::INT, "g"), PropertyInfo(Variant::INT, "b")));
    ADD_SIGNAL(MethodInfo("connection_status_update", PropertyInfo(Variant::INT, "status")));
    ADD_SIGNAL(MethodInfo("hdr_mode_changed", PropertyInfo(Variant::BOOL, "hdr_enabled")));
}
