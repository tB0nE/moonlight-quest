#pragma once

#include <godot_cpp/classes/resource.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <Limelight.h>

namespace godot {

class NightfallStreamConfig : public Resource {
    GDCLASS(NightfallStreamConfig, Resource);

protected:
    static void _bind_methods();

private:
    int width = 0;
    int height = 0;
    int fps = 0;
    int bitrate = 0;
    int packet_size = 0;
    int streaming_remotely = 0;
    int audio_configuration = 0;
    int supported_video_formats = 0;
    int client_refresh_rate_x100 = 0;
    int color_space = 0;
    int color_range = 0;
    int encryption_flags = 0;
    PackedByteArray remote_input_aes_key;
    PackedByteArray remote_input_aes_iv;

public:
    NightfallStreamConfig() {}

    enum VideoFormat {
        FORMAT_H264 = VIDEO_FORMAT_H264,
        FORMAT_H264_HIGH8_444 = VIDEO_FORMAT_H264_HIGH8_444,
        FORMAT_H265 = VIDEO_FORMAT_H265,
        FORMAT_H265_MAIN10 = VIDEO_FORMAT_H265_MAIN10,
        FORMAT_H265_REXT8_444 = VIDEO_FORMAT_H265_REXT8_444,
        FORMAT_H265_REXT10_444 = VIDEO_FORMAT_H265_REXT10_444,
        FORMAT_AV1_MAIN8 = VIDEO_FORMAT_AV1_MAIN8,
        FORMAT_AV1_MAIN10 = VIDEO_FORMAT_AV1_MAIN10,
        FORMAT_AV1_HIGH8_444 = VIDEO_FORMAT_AV1_HIGH8_444,
        FORMAT_AV1_HIGH10_444 = VIDEO_FORMAT_AV1_HIGH10_444,

        MASK_H264 = VIDEO_FORMAT_MASK_H264,
        MASK_H265 = VIDEO_FORMAT_MASK_H265,
        MASK_AV1 = VIDEO_FORMAT_MASK_AV1,
        MASK_10BIT = VIDEO_FORMAT_MASK_10BIT,
        MASK_YUV444 = VIDEO_FORMAT_MASK_YUV444
    };

    enum StreamMode {
        STREAM_LOCAL = STREAM_CFG_LOCAL,
        STREAM_REMOTE = STREAM_CFG_REMOTE,
        STREAM_AUTO = STREAM_CFG_AUTO
    };

    enum ColorSpace {
        CS_REC_601 = COLORSPACE_REC_601,
        CS_REC_709 = COLORSPACE_REC_709,
        CS_REC_2020 = COLORSPACE_REC_2020
    };

    enum ColorRange {
        CR_LIMITED = COLOR_RANGE_LIMITED,
        CR_FULL = COLOR_RANGE_FULL
    };

    enum EncryptionFlag {
        ENC_NONE = ENCFLG_NONE,
        ENC_AUDIO = ENCFLG_AUDIO,
        ENC_VIDEO = ENCFLG_VIDEO,
        ENC_ALL = ENCFLG_ALL
    };

    enum AudioConfigurationPreset {
        AUDIO_CFG_STEREO = AUDIO_CONFIGURATION_STEREO,
        AUDIO_CFG_51_SURROUND = AUDIO_CONFIGURATION_51_SURROUND,
        AUDIO_CFG_71_SURROUND = AUDIO_CONFIGURATION_71_SURROUND
    };

    void set_width(int v) { width = v; }
    int get_width() const { return width; }
    void set_height(int v) { height = v; }
    int get_height() const { return height; }
    void set_fps(int v) { fps = v; }
    int get_fps() const { return fps; }
    void set_bitrate(int v) { bitrate = v; }
    int get_bitrate() const { return bitrate; }
    void set_packet_size(int v) { packet_size = v; }
    int get_packet_size() const { return packet_size; }
    void set_streaming_remotely(int v) { streaming_remotely = v; }
    int get_streaming_remotely() const { return streaming_remotely; }
    void set_audio_configuration(int v) { audio_configuration = v; }
    int get_audio_configuration() const { return audio_configuration; }
    void set_supported_video_formats(int v) { supported_video_formats = v; }
    int get_supported_video_formats() const { return supported_video_formats; }
    void set_client_refresh_rate_x100(int v) { client_refresh_rate_x100 = v; }
    int get_client_refresh_rate_x100() const { return client_refresh_rate_x100; }
    void set_color_space(int v) { color_space = v; }
    int get_color_space() const { return color_space; }
    void set_color_range(int v) { color_range = v; }
    int get_color_range() const { return color_range; }
    void set_encryption_flags(int v) { encryption_flags = v; }
    int get_encryption_flags() const { return encryption_flags; }
    void set_remote_input_aes_key(const PackedByteArray &b) { remote_input_aes_key = b; }
    PackedByteArray get_remote_input_aes_key() const { return remote_input_aes_key; }
    void set_remote_input_aes_iv(const PackedByteArray &b) { remote_input_aes_iv = b; }
    PackedByteArray get_remote_input_aes_iv() const { return remote_input_aes_iv; }

    int get_surround_audio_info() const {
        int x = audio_configuration;
        int channelCount = (x >> 8) & 0xFF;
        int channelMask = (x >> 16) & 0xFFFF;
        return (channelMask << 16) | channelCount;
    }
};

class NightfallStreamOptions : public Resource {
    GDCLASS(NightfallStreamOptions, Resource);

protected:
    static void _bind_methods();

private:
    bool disable_hw_acceleration = false;
    bool prefer_hw_decoder = false;
    bool verbose = false;
    int video_codec = 1;
    bool disable_video = false;
    bool disable_audio = false;

public:
    NightfallStreamOptions() {}
    void set_disable_hw_acceleration(bool v) { disable_hw_acceleration = v; }
    bool get_disable_hw_acceleration() const { return disable_hw_acceleration; }
    void set_prefer_hw_decoder(bool v) { prefer_hw_decoder = v; }
    bool get_prefer_hw_decoder() const { return prefer_hw_decoder; }
    void set_verbose(bool v) { verbose = v; }
    bool get_verbose() const { return verbose; }
    void set_video_codec(int v) { video_codec = v; }
    int get_video_codec() const { return video_codec; }
    void set_disable_video(bool v) { disable_video = v; }
    bool get_disable_video() const { return disable_video; }
    void set_disable_audio(bool v) { disable_audio = v; }
    bool get_disable_audio() const { return disable_audio; }
};

} // namespace godot

VARIANT_ENUM_CAST(godot::NightfallStreamConfig::VideoFormat);
VARIANT_ENUM_CAST(godot::NightfallStreamConfig::StreamMode);
VARIANT_ENUM_CAST(godot::NightfallStreamConfig::ColorSpace);
VARIANT_ENUM_CAST(godot::NightfallStreamConfig::ColorRange);
VARIANT_ENUM_CAST(godot::NightfallStreamConfig::EncryptionFlag);
VARIANT_ENUM_CAST(godot::NightfallStreamConfig::AudioConfigurationPreset);
