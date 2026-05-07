#include "opus_decoder.h"

#include <godot_cpp/variant/utility_functions.hpp>
#include <cstring>

using namespace godot;

OpusDecoderWrapper::OpusDecoderWrapper() {}

OpusDecoderWrapper::~OpusDecoderWrapper() {
    cleanup();
}

int OpusDecoderWrapper::init(int sample_rate, int channels, int streams, int coupled_streams, const PackedByteArray &mapping) {
    cleanup();

    if (channels <= 0 || streams <= 0 || coupled_streams < 0 || mapping.size() < channels) {
        UtilityFunctions::printerr("[OpusDecoder] Invalid init parameters");
        return -1;
    }

    unsigned char mapping_buf[8] = {};
    for (int i = 0; i < channels && i < 8; i++) {
        mapping_buf[i] = (unsigned char)mapping[i];
    }

    int error = OPUS_OK;
    decoder_ = opus_multistream_decoder_create(sample_rate, channels, streams, coupled_streams, mapping_buf, &error);

    if (error != OPUS_OK || !decoder_) {
        UtilityFunctions::printerr("[OpusDecoder] Init failed: ", error, " (", opus_strerror(error), ")");
        decoder_ = nullptr;
        return error;
    }

    sample_rate_ = sample_rate;
    channels_ = channels;
    samples_per_frame_ = sample_rate / 200;

    UtilityFunctions::print("[OpusDecoder] Initialized: ", sample_rate, "Hz, ", channels, "ch, ", streams, " streams, ", coupled_streams, " coupled");
    return 0;
}

void OpusDecoderWrapper::cleanup() {
    if (decoder_) {
        opus_multistream_decoder_destroy(decoder_);
        decoder_ = nullptr;
    }
}

int OpusDecoderWrapper::decode(const PackedByteArray &opus_data, int max_samples_per_frame) {
    if (!decoder_ || opus_data.is_empty()) return -1;

    int max_samples = max_samples_per_frame > 0 ? max_samples_per_frame : samples_per_frame_;
    int buf_size = max_samples * channels_;

    last_pcm_.resize(buf_size);

    int frames = opus_multistream_decode_float(
        decoder_,
        (const unsigned char *)opus_data.ptr(),
        (opus_int32)opus_data.size(),
        last_pcm_.ptrw(),
        max_samples,
        0
    );

    if (frames < 0) {
        UtilityFunctions::printerr("[OpusDecoder] Decode failed: ", frames, " (", opus_strerror(frames), ")");
        last_pcm_.resize(0);
        return frames;
    }

    last_pcm_.resize(frames * channels_);
    return frames;
}

String OpusDecoderWrapper::get_error_text(int error) const {
    return String(opus_strerror(error));
}

void OpusDecoderWrapper::_bind_methods() {
    ClassDB::bind_method(D_METHOD("init", "sample_rate", "channels", "streams", "coupled_streams", "mapping"), &OpusDecoderWrapper::init);
    ClassDB::bind_method(D_METHOD("cleanup"), &OpusDecoderWrapper::cleanup);
    ClassDB::bind_method(D_METHOD("decode", "opus_data", "max_samples_per_frame"), &OpusDecoderWrapper::decode, DEFVAL(0));
    ClassDB::bind_method(D_METHOD("get_last_pcm"), &OpusDecoderWrapper::get_last_pcm);
    ClassDB::bind_method(D_METHOD("get_sample_rate"), &OpusDecoderWrapper::get_sample_rate);
    ClassDB::bind_method(D_METHOD("get_channels"), &OpusDecoderWrapper::get_channels);
    ClassDB::bind_method(D_METHOD("get_samples_per_frame"), &OpusDecoderWrapper::get_samples_per_frame);
    ClassDB::bind_method(D_METHOD("get_error_text", "error"), &OpusDecoderWrapper::get_error_text);
}
