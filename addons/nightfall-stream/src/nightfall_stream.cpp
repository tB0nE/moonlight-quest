#include "nightfall_stream.h"
#include "video/stream_connection.h"
#include "video/ffmpeg_decoder.h"
#include "video/texture_uploader.h"
#include "audio/audio_renderer.h"
#include "input/input_bridge.h"
#include "config/computer_manager.h"
#include "config/config_manager.h"
#include "network/http_requester.h"

#include <godot_cpp/classes/timer.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

#include "nf_log.h"

using namespace godot;

NightfallStream::NightfallStream() {}

NightfallStream::~NightfallStream() {
    stop_stream();
}

void NightfallStream::_ready() {
    set_process(true);
    config_manager_.instantiate();
    computer_manager_.instantiate();
    computer_manager_->set_config_manager(config_manager_.ptr());

    auto *http_req = memnew(HttpRequester);
    computer_manager_->set_http_requester(http_req);

    stream_connection_ = memnew(StreamConnection);
    add_child(stream_connection_);

    computer_manager_->set_parent_node(this);

    stream_connection_->connect("stream_started", callable_mp(this, &NightfallStream::_on_stream_started));
    stream_connection_->connect("stream_terminated", callable_mp(this, &NightfallStream::_on_stream_terminated));
    stream_connection_->connect("stage_starting", callable_mp(this, &NightfallStream::_on_stage_starting));
    stream_connection_->connect("stage_complete", callable_mp(this, &NightfallStream::_on_stage_complete));
    stream_connection_->connect("stage_failed", callable_mp(this, &NightfallStream::_on_stage_failed));
    stream_connection_->connect("connection_status_update", callable_mp(this, &NightfallStream::_on_connection_status_update));
    stream_connection_->connect("log_message", callable_mp(this, &NightfallStream::_on_log_message));
}

void NightfallStream::_process(double /*delta*/) {
}

String NightfallStream::get_version() const {
    return "2.0.0-alpha";
}

int NightfallStream::get_state() const {
    return (int)state_;
}

void NightfallStream::start_stream(const String &host, const Dictionary &server_info, const Dictionary &stream_config, bool disable_hw) {
    NF_LOGE("NightfallStream", "start_stream: host=%s server_info_keys=%d stream_config_keys=%d state=%d stream_conn=%p",
        host.utf8().get_data(), server_info.size(), stream_config.size(), (int)state_, (void*)stream_connection_);
    if (state_ == STATE_CONNECTING || state_ == STATE_CONNECTED) {
        stop_stream();
    }

    last_host_ = host;
    last_server_info_ = server_info.duplicate();
    last_stream_config_ = stream_config.duplicate();
    last_disable_hw_ = disable_hw;

    state_ = STATE_CONNECTING;
    _reset_reconnect();
    emit_signal("state_changed", (int)state_);

    stream_connection_->start(host, server_info, stream_config, disable_hw);
}

void NightfallStream::stop_stream() {
    if (state_ == STATE_IDLE) return;

    state_ = STATE_STOPPING;
    _reset_reconnect();
    emit_signal("state_changed", (int)state_);

    stream_connection_->stop();

    state_ = STATE_IDLE;
    emit_signal("state_changed", (int)state_);
}

int NightfallStream::probe_video_format(int codec_preference, bool disable_hw) {
    if (!stream_connection_) return 1;
    return stream_connection_->probe_video_format(codec_preference, disable_hw);
}

void NightfallStream::set_auto_reconnect(bool enabled) {
    auto_reconnect_ = enabled;
}

bool NightfallStream::get_auto_reconnect() const {
    return auto_reconnect_;
}

void NightfallStream::set_max_reconnect_attempts(int attempts) {
    max_reconnect_attempts_ = attempts;
}

int NightfallStream::get_max_reconnect_attempts() const {
    return max_reconnect_attempts_;
}

void NightfallStream::set_reconnect_delay_ms(int ms) {
    reconnect_delay_ms_ = ms;
}

int NightfallStream::get_reconnect_delay_ms() const {
    return reconnect_delay_ms_;
}

Ref<FfmpegDecoder> NightfallStream::get_decoder() const {
    if (stream_connection_) return stream_connection_->get_decoder();
    return nullptr;
}

Ref<TextureUploader> NightfallStream::get_texture_uploader() const {
    if (stream_connection_) return stream_connection_->get_texture_uploader();
    return nullptr;
}

Ref<ShaderMaterial> NightfallStream::get_shader_material() const {
    if (stream_connection_) return stream_connection_->get_shader_material();
    return nullptr;
}

Ref<AudioRenderer> NightfallStream::get_audio_renderer() const {
    if (stream_connection_) return stream_connection_->get_audio_renderer();
    return nullptr;
}

Ref<InputBridge> NightfallStream::get_input_bridge() const {
    if (stream_connection_) return stream_connection_->get_input_bridge();
    return nullptr;
}

Ref<DepthBridge> NightfallStream::get_depth_bridge() const {
    if (stream_connection_) return stream_connection_->get_depth_bridge();
    return nullptr;
}

int NightfallStream::get_frames_dropped() const {
    if (stream_connection_) return stream_connection_->get_frames_dropped();
    return 0;
}

int NightfallStream::get_frames_decoded() const {
    if (stream_connection_) return stream_connection_->get_frames_decoded();
    return 0;
}

int NightfallStream::get_decode_queue_size() const {
    if (stream_connection_) return stream_connection_->get_decode_queue_size();
    return 0;
}

int NightfallStream::get_last_frame_latency_us() const {
    if (stream_connection_) return stream_connection_->get_last_frame_latency_us();
    return 0;
}

String NightfallStream::get_decoder_name() const {
    if (stream_connection_) return stream_connection_->get_decoder_name();
    return "";
}

int NightfallStream::get_video_width() const {
    if (stream_connection_) return stream_connection_->get_video_width();
    return 0;
}

int NightfallStream::get_video_height() const {
    if (stream_connection_) return stream_connection_->get_video_height();
    return 0;
}

bool NightfallStream::is_hw_decode() const {
    if (stream_connection_) return stream_connection_->is_hw_decode();
    return false;
}

String NightfallStream::get_error_string(int error_code) {
    return StreamConnection::get_error_string(error_code);
}

Object *NightfallStream::get_computer_manager() const {
    return computer_manager_.ptr();
}

Object *NightfallStream::get_config_manager() const {
    return config_manager_.ptr();
}

Object *NightfallStream::get_stream_connection() const {
    return stream_connection_;
}

void NightfallStream::_on_pair_completed(bool success, const String &msg) {
    NF_LOGE("NightfallStream", "_on_pair_completed: success=%d msg=%s", success, msg.utf8().get_data());
    emit_signal("pair_completed", success, msg);
}

void NightfallStream::_on_stream_started() {
    NF_LOGE("NightfallStream", "_on_stream_started CALLED");
    state_ = STATE_CONNECTED;
    _reset_reconnect();
    emit_signal("state_changed", (int)state_);
    emit_signal("stream_started");
}

void NightfallStream::_on_stream_terminated(int error_code, const String &error_message) {
    if (state_ == STATE_STOPPING) return;

    state_ = STATE_DISCONNECTED;
    emit_signal("state_changed", (int)state_);
    emit_signal("stream_terminated", error_code, error_message);

    if (error_code == 0) return;

    if (auto_reconnect_ && reconnect_attempts_ < max_reconnect_attempts_) {
        state_ = STATE_RECONNECTING;
        emit_signal("state_changed", (int)state_);
        emit_signal("reconnect_attempt", reconnect_attempts_ + 1, max_reconnect_attempts_);
        _attempt_reconnect();
    }
}

void NightfallStream::_on_stage_starting(const String &stage_name) {
    current_stage_ = stage_name;
    emit_signal("stage_starting", stage_name);
}

void NightfallStream::_on_stage_complete(const String &stage_name) {
    emit_signal("stage_complete", stage_name);
}

void NightfallStream::_on_stage_failed(const String &stage_name, int error_code) {
    emit_signal("stage_failed", stage_name, error_code);

    if (auto_reconnect_ && reconnect_attempts_ < max_reconnect_attempts_) {
        state_ = STATE_RECONNECTING;
        emit_signal("state_changed", (int)state_);
        emit_signal("reconnect_attempt", reconnect_attempts_ + 1, max_reconnect_attempts_);
        _attempt_reconnect();
    }
}

void NightfallStream::_on_connection_status_update(int status) {
    emit_signal("connection_status_update", status);
}

void NightfallStream::_on_log_message(const String &message) {
    emit_signal("log_message", message);
}

void NightfallStream::_attempt_reconnect() {
    reconnect_attempts_++;

    UtilityFunctions::print("[NightfallStream] Reconnect attempt ", reconnect_attempts_, "/", max_reconnect_attempts_, " in ", reconnect_delay_ms_, "ms");

    call_deferred("emit_signal", "reconnect_scheduled", reconnect_attempts_, max_reconnect_attempts_, reconnect_delay_ms_);

    Timer *timer = memnew(Timer);
    timer->set_wait_time((double)reconnect_delay_ms_ / 1000.0);
    timer->set_one_shot(true);
    add_child(timer);
    timer->connect("timeout", callable_mp(this, &NightfallStream::_do_reconnect));
    timer->start();
}

void NightfallStream::_do_reconnect() {
    if (state_ != STATE_RECONNECTING) return;
    NF_LOGE("NightfallStream", "_do_reconnect: last_host_=%s last_server_info_keys=%d last_stream_config_keys=%d",
        last_host_.utf8().get_data(), last_server_info_.size(), last_stream_config_.size());
    start_stream(last_host_, last_server_info_, last_stream_config_, last_disable_hw_);
}

void NightfallStream::_reset_reconnect() {
    reconnect_attempts_ = 0;
}

void NightfallStream::_bind_methods() {
    BIND_CONSTANT(STATE_IDLE);
    BIND_CONSTANT(STATE_CONNECTING);
    BIND_CONSTANT(STATE_CONNECTED);
    BIND_CONSTANT(STATE_DISCONNECTED);
    BIND_CONSTANT(STATE_RECONNECTING);
    BIND_CONSTANT(STATE_STOPPING);

    ClassDB::bind_method(D_METHOD("get_version"), &NightfallStream::get_version);
    ClassDB::bind_method(D_METHOD("get_state"), &NightfallStream::get_state);

    ClassDB::bind_method(D_METHOD("start_stream", "host", "server_info", "stream_config", "disable_hw"), &NightfallStream::start_stream, DEFVAL(false));
    ClassDB::bind_method(D_METHOD("stop_stream"), &NightfallStream::stop_stream);
    ClassDB::bind_method(D_METHOD("probe_video_format", "codec_preference", "disable_hw"), &NightfallStream::probe_video_format);

    ClassDB::bind_method(D_METHOD("set_auto_reconnect", "enabled"), &NightfallStream::set_auto_reconnect);
    ClassDB::bind_method(D_METHOD("get_auto_reconnect"), &NightfallStream::get_auto_reconnect);
    ClassDB::bind_method(D_METHOD("set_max_reconnect_attempts", "attempts"), &NightfallStream::set_max_reconnect_attempts);
    ClassDB::bind_method(D_METHOD("get_max_reconnect_attempts"), &NightfallStream::get_max_reconnect_attempts);
    ClassDB::bind_method(D_METHOD("set_reconnect_delay_ms", "ms"), &NightfallStream::set_reconnect_delay_ms);
    ClassDB::bind_method(D_METHOD("get_reconnect_delay_ms"), &NightfallStream::get_reconnect_delay_ms);

    ClassDB::bind_method(D_METHOD("get_decoder"), &NightfallStream::get_decoder);
    ClassDB::bind_method(D_METHOD("get_texture_uploader"), &NightfallStream::get_texture_uploader);
    ClassDB::bind_method(D_METHOD("get_shader_material"), &NightfallStream::get_shader_material);
    ClassDB::bind_method(D_METHOD("get_audio_renderer"), &NightfallStream::get_audio_renderer);
    ClassDB::bind_method(D_METHOD("get_input_bridge"), &NightfallStream::get_input_bridge);
    ClassDB::bind_method(D_METHOD("get_depth_bridge"), &NightfallStream::get_depth_bridge);
    ClassDB::bind_method(D_METHOD("get_frames_dropped"), &NightfallStream::get_frames_dropped);
    ClassDB::bind_method(D_METHOD("get_frames_decoded"), &NightfallStream::get_frames_decoded);
    ClassDB::bind_method(D_METHOD("get_decode_queue_size"), &NightfallStream::get_decode_queue_size);
    ClassDB::bind_method(D_METHOD("get_last_frame_latency_us"), &NightfallStream::get_last_frame_latency_us);
    ClassDB::bind_method(D_METHOD("get_decoder_name"), &NightfallStream::get_decoder_name);
    ClassDB::bind_method(D_METHOD("get_video_width"), &NightfallStream::get_video_width);
    ClassDB::bind_method(D_METHOD("get_video_height"), &NightfallStream::get_video_height);
    ClassDB::bind_method(D_METHOD("is_hw_decode"), &NightfallStream::is_hw_decode);
    ClassDB::bind_static_method("NightfallStream", D_METHOD("get_error_string", "error_code"), &NightfallStream::get_error_string);
    ClassDB::bind_method(D_METHOD("get_computer_manager"), &NightfallStream::get_computer_manager);
    ClassDB::bind_method(D_METHOD("get_config_manager"), &NightfallStream::get_config_manager);
    ClassDB::bind_method(D_METHOD("get_stream_connection"), &NightfallStream::get_stream_connection);
    ClassDB::bind_method(D_METHOD("_on_pair_completed", "success", "message"), &NightfallStream::_on_pair_completed);
    ClassDB::bind_method(D_METHOD("_on_log_message", "message"), &NightfallStream::_on_log_message);

    ADD_PROPERTY(PropertyInfo(Variant::BOOL, "auto_reconnect"), "set_auto_reconnect", "get_auto_reconnect");
    ADD_PROPERTY(PropertyInfo(Variant::INT, "max_reconnect_attempts"), "set_max_reconnect_attempts", "get_max_reconnect_attempts");
    ADD_PROPERTY(PropertyInfo(Variant::INT, "reconnect_delay_ms"), "set_reconnect_delay_ms", "get_reconnect_delay_ms");

    ADD_SIGNAL(MethodInfo("state_changed", PropertyInfo(Variant::INT, "state")));
    ADD_SIGNAL(MethodInfo("stream_started"));
    ADD_SIGNAL(MethodInfo("stream_terminated", PropertyInfo(Variant::INT, "error_code"), PropertyInfo(Variant::STRING, "error_message")));
    ADD_SIGNAL(MethodInfo("stage_starting", PropertyInfo(Variant::STRING, "stage_name")));
    ADD_SIGNAL(MethodInfo("stage_complete", PropertyInfo(Variant::STRING, "stage_name")));
    ADD_SIGNAL(MethodInfo("stage_failed", PropertyInfo(Variant::STRING, "stage_name"), PropertyInfo(Variant::INT, "error_code")));
    ADD_SIGNAL(MethodInfo("connection_status_update", PropertyInfo(Variant::INT, "status")));
    ADD_SIGNAL(MethodInfo("reconnect_scheduled", PropertyInfo(Variant::INT, "attempt"), PropertyInfo(Variant::INT, "max_attempts"), PropertyInfo(Variant::INT, "delay_ms")));
    ADD_SIGNAL(MethodInfo("reconnect_attempt", PropertyInfo(Variant::INT, "attempt"), PropertyInfo(Variant::INT, "max_attempts")));
    ADD_SIGNAL(MethodInfo("pair_completed", PropertyInfo(Variant::BOOL, "success"), PropertyInfo(Variant::STRING, "message")));
    ADD_SIGNAL(MethodInfo("log_message", PropertyInfo(Variant::STRING, "message")));
}
