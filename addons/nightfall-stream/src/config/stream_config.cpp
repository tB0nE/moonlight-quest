#include "stream_config.h"
#include <godot_cpp/variant/utility_functions.hpp>

namespace godot {

void NightfallStreamConfig::_bind_methods() {
    ClassDB::bind_method(D_METHOD("set_width", "v"), &NightfallStreamConfig::set_width);
    ClassDB::bind_method(D_METHOD("get_width"), &NightfallStreamConfig::get_width);
    ADD_PROPERTY(PropertyInfo(Variant::INT, "width"), "set_width", "get_width");

    ClassDB::bind_method(D_METHOD("set_height", "v"), &NightfallStreamConfig::set_height);
    ClassDB::bind_method(D_METHOD("get_height"), &NightfallStreamConfig::get_height);
    ADD_PROPERTY(PropertyInfo(Variant::INT, "height"), "set_height", "get_height");

    ClassDB::bind_method(D_METHOD("set_fps", "v"), &NightfallStreamConfig::set_fps);
    ClassDB::bind_method(D_METHOD("get_fps"), &NightfallStreamConfig::get_fps);
    ADD_PROPERTY(PropertyInfo(Variant::INT, "fps"), "set_fps", "get_fps");

    ClassDB::bind_method(D_METHOD("set_bitrate", "v"), &NightfallStreamConfig::set_bitrate);
    ClassDB::bind_method(D_METHOD("get_bitrate"), &NightfallStreamConfig::get_bitrate);
    ADD_PROPERTY(PropertyInfo(Variant::INT, "bitrate"), "set_bitrate", "get_bitrate");

    ClassDB::bind_method(D_METHOD("set_packet_size", "v"), &NightfallStreamConfig::set_packet_size);
    ClassDB::bind_method(D_METHOD("get_packet_size"), &NightfallStreamConfig::get_packet_size);
    ADD_PROPERTY(PropertyInfo(Variant::INT, "packet_size"), "set_packet_size", "get_packet_size");

    ClassDB::bind_method(D_METHOD("set_streaming_remotely", "v"), &NightfallStreamConfig::set_streaming_remotely);
    ClassDB::bind_method(D_METHOD("get_streaming_remotely"), &NightfallStreamConfig::get_streaming_remotely);
    ADD_PROPERTY(PropertyInfo(Variant::INT, "streaming_remotely"), "set_streaming_remotely", "get_streaming_remotely");

    ClassDB::bind_method(D_METHOD("set_audio_configuration", "v"), &NightfallStreamConfig::set_audio_configuration);
    ClassDB::bind_method(D_METHOD("get_audio_configuration"), &NightfallStreamConfig::get_audio_configuration);
    ADD_PROPERTY(PropertyInfo(Variant::INT, "audio_configuration"), "set_audio_configuration", "get_audio_configuration");

    ClassDB::bind_method(D_METHOD("set_supported_video_formats", "v"), &NightfallStreamConfig::set_supported_video_formats);
    ClassDB::bind_method(D_METHOD("get_supported_video_formats"), &NightfallStreamConfig::get_supported_video_formats);
    ADD_PROPERTY(PropertyInfo(Variant::INT, "supported_video_formats"), "set_supported_video_formats", "get_supported_video_formats");

    ClassDB::bind_method(D_METHOD("set_client_refresh_rate_x100", "v"), &NightfallStreamConfig::set_client_refresh_rate_x100);
    ClassDB::bind_method(D_METHOD("get_client_refresh_rate_x100"), &NightfallStreamConfig::get_client_refresh_rate_x100);
    ADD_PROPERTY(PropertyInfo(Variant::INT, "client_refresh_rate_x100"), "set_client_refresh_rate_x100", "get_client_refresh_rate_x100");

    ClassDB::bind_method(D_METHOD("set_color_space", "v"), &NightfallStreamConfig::set_color_space);
    ClassDB::bind_method(D_METHOD("get_color_space"), &NightfallStreamConfig::get_color_space);
    ADD_PROPERTY(PropertyInfo(Variant::INT, "color_space"), "set_color_space", "get_color_space");

    ClassDB::bind_method(D_METHOD("set_color_range", "v"), &NightfallStreamConfig::set_color_range);
    ClassDB::bind_method(D_METHOD("get_color_range"), &NightfallStreamConfig::get_color_range);
    ADD_PROPERTY(PropertyInfo(Variant::INT, "color_range"), "set_color_range", "get_color_range");

    ClassDB::bind_method(D_METHOD("set_encryption_flags", "v"), &NightfallStreamConfig::set_encryption_flags);
    ClassDB::bind_method(D_METHOD("get_encryption_flags"), &NightfallStreamConfig::get_encryption_flags);
    ADD_PROPERTY(PropertyInfo(Variant::INT, "encryption_flags"), "set_encryption_flags", "get_encryption_flags");

    ClassDB::bind_method(D_METHOD("set_remote_input_aes_key", "b"), &NightfallStreamConfig::set_remote_input_aes_key);
    ClassDB::bind_method(D_METHOD("get_remote_input_aes_key"), &NightfallStreamConfig::get_remote_input_aes_key);
    ADD_PROPERTY(PropertyInfo(Variant::PACKED_BYTE_ARRAY, "remote_input_aes_key"), "set_remote_input_aes_key", "get_remote_input_aes_key");

    ClassDB::bind_method(D_METHOD("set_remote_input_aes_iv", "b"), &NightfallStreamConfig::set_remote_input_aes_iv);
    ClassDB::bind_method(D_METHOD("get_remote_input_aes_iv"), &NightfallStreamConfig::get_remote_input_aes_iv);
    ADD_PROPERTY(PropertyInfo(Variant::PACKED_BYTE_ARRAY, "remote_input_aes_iv"), "set_remote_input_aes_iv", "get_remote_input_aes_iv");

    ClassDB::bind_method(D_METHOD("get_surround_audio_info"), &NightfallStreamConfig::get_surround_audio_info);

    BIND_ENUM_CONSTANT(FORMAT_H264);
    BIND_ENUM_CONSTANT(FORMAT_H264_HIGH8_444);
    BIND_ENUM_CONSTANT(FORMAT_H265);
    BIND_ENUM_CONSTANT(FORMAT_H265_MAIN10);
    BIND_ENUM_CONSTANT(FORMAT_H265_REXT8_444);
    BIND_ENUM_CONSTANT(FORMAT_H265_REXT10_444);
    BIND_ENUM_CONSTANT(FORMAT_AV1_MAIN8);
    BIND_ENUM_CONSTANT(FORMAT_AV1_MAIN10);
    BIND_ENUM_CONSTANT(FORMAT_AV1_HIGH8_444);
    BIND_ENUM_CONSTANT(FORMAT_AV1_HIGH10_444);
    BIND_ENUM_CONSTANT(MASK_H264);
    BIND_ENUM_CONSTANT(MASK_H265);
    BIND_ENUM_CONSTANT(MASK_AV1);
    BIND_ENUM_CONSTANT(MASK_10BIT);
    BIND_ENUM_CONSTANT(MASK_YUV444);
    BIND_ENUM_CONSTANT(STREAM_LOCAL);
    BIND_ENUM_CONSTANT(STREAM_REMOTE);
    BIND_ENUM_CONSTANT(STREAM_AUTO);
    BIND_ENUM_CONSTANT(CS_REC_601);
    BIND_ENUM_CONSTANT(CS_REC_709);
    BIND_ENUM_CONSTANT(CS_REC_2020);
    BIND_ENUM_CONSTANT(CR_LIMITED);
    BIND_ENUM_CONSTANT(CR_FULL);
    BIND_ENUM_CONSTANT(ENC_NONE);
    BIND_ENUM_CONSTANT(ENC_AUDIO);
    BIND_ENUM_CONSTANT(ENC_VIDEO);
    BIND_ENUM_CONSTANT(ENC_ALL);
    BIND_ENUM_CONSTANT(AUDIO_CFG_STEREO);
    BIND_ENUM_CONSTANT(AUDIO_CFG_51_SURROUND);
    BIND_ENUM_CONSTANT(AUDIO_CFG_71_SURROUND);
}

void NightfallStreamOptions::_bind_methods() {
    ClassDB::bind_method(D_METHOD("set_disable_hw_acceleration", "v"), &NightfallStreamOptions::set_disable_hw_acceleration);
    ClassDB::bind_method(D_METHOD("get_disable_hw_acceleration"), &NightfallStreamOptions::get_disable_hw_acceleration);
    ADD_PROPERTY(PropertyInfo(Variant::BOOL, "disable_hw_acceleration"), "set_disable_hw_acceleration", "get_disable_hw_acceleration");

    ClassDB::bind_method(D_METHOD("set_prefer_hw_decoder", "v"), &NightfallStreamOptions::set_prefer_hw_decoder);
    ClassDB::bind_method(D_METHOD("get_prefer_hw_decoder"), &NightfallStreamOptions::get_prefer_hw_decoder);
    ADD_PROPERTY(PropertyInfo(Variant::BOOL, "prefer_hw_decoder"), "set_prefer_hw_decoder", "get_prefer_hw_decoder");

    ClassDB::bind_method(D_METHOD("set_verbose", "v"), &NightfallStreamOptions::set_verbose);
    ClassDB::bind_method(D_METHOD("get_verbose"), &NightfallStreamOptions::get_verbose);
    ADD_PROPERTY(PropertyInfo(Variant::BOOL, "verbose"), "set_verbose", "get_verbose");

    ClassDB::bind_method(D_METHOD("set_video_codec", "v"), &NightfallStreamOptions::set_video_codec);
    ClassDB::bind_method(D_METHOD("get_video_codec"), &NightfallStreamOptions::get_video_codec);
    ADD_PROPERTY(PropertyInfo(Variant::INT, "video_codec"), "set_video_codec", "get_video_codec");

    ClassDB::bind_method(D_METHOD("set_disable_video", "v"), &NightfallStreamOptions::set_disable_video);
    ClassDB::bind_method(D_METHOD("get_disable_video"), &NightfallStreamOptions::get_disable_video);
    ADD_PROPERTY(PropertyInfo(Variant::BOOL, "disable_video"), "set_disable_video", "get_disable_video");

    ClassDB::bind_method(D_METHOD("set_disable_audio", "v"), &NightfallStreamOptions::set_disable_audio);
    ClassDB::bind_method(D_METHOD("get_disable_audio"), &NightfallStreamOptions::get_disable_audio);
    ADD_PROPERTY(PropertyInfo(Variant::BOOL, "disable_audio"), "set_disable_audio", "get_disable_audio");
}

} // namespace godot
