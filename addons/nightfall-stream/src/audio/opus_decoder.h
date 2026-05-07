#pragma once

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/string.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <cstdint>

extern "C" {
#include <opus_multistream.h>
}

namespace godot {

class OpusDecoderWrapper : public RefCounted {
    GDCLASS(OpusDecoderWrapper, RefCounted);

public:
    OpusDecoderWrapper();
    ~OpusDecoderWrapper();

    int init(int sample_rate, int channels, int streams, int coupled_streams, const PackedByteArray &mapping);
    void cleanup();

    int decode(const PackedByteArray &opus_data, int max_samples_per_frame);
    PackedFloat32Array get_last_pcm() const { return last_pcm_; }

    int get_sample_rate() const { return sample_rate_; }
    int get_channels() const { return channels_; }
    int get_samples_per_frame() const { return samples_per_frame_; }

    String get_error_text(int error) const;

protected:
    static void _bind_methods();

private:
    OpusMSDecoder *decoder_ = nullptr;
    PackedFloat32Array last_pcm_;
    int sample_rate_ = 48000;
    int channels_ = 0;
    int samples_per_frame_ = 0;
};

} // namespace godot
