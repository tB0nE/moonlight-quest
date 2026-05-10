#include "audio_renderer.h"
#include "miniaudio_backend.h"

#include <godot_cpp/variant/utility_functions.hpp>
#include <cstring>
#ifdef __ANDROID__
#include <android/log.h>
#endif

using namespace godot;

AudioRenderer *AudioRenderer::active_instance_ = nullptr;

AudioRenderer::AudioRenderer() {
    opus_decoder_.instantiate();
}

AudioRenderer::~AudioRenderer() {
    cleanup();
}

int AudioRenderer::_cb_init(int audioConfiguration, const POPUS_MULTISTREAM_CONFIGURATION opusConfig, void *context, int arFlags) {
    auto *self = active_instance_;
    if (!self) return -1;
    return self->init(audioConfiguration, opusConfig, context, arFlags);
}

void AudioRenderer::_cb_start() {
    auto *self = active_instance_;
    if (self) self->start();
}

void AudioRenderer::_cb_stop() {
    auto *self = active_instance_;
    if (self) self->stop();
}

void AudioRenderer::_cb_cleanup() {
    auto *self = active_instance_;
    if (self) self->cleanup();
}

void AudioRenderer::_cb_decode_and_play_sample(char *sampleData, int sampleLength) {
    auto *self = active_instance_;
    if (self) self->decode_and_play_sample(sampleData, sampleLength);
}

int AudioRenderer::init(int audio_configuration, const POPUS_MULTISTREAM_CONFIGURATION opus_config, void * /*context*/, int /*ar_flags*/) {
    if (!opus_config) return -1;

    audio_configuration_ = audio_configuration;
    channels_ = opus_config->channelCount;
    sample_rate_ = opus_config->sampleRate;
    samples_per_frame_ = opus_config->samplesPerFrame;
    memcpy(channel_mapping_, opus_config->mapping, sizeof(channel_mapping_));

    __android_log_print(ANDROID_LOG_INFO, "AudioRenderer",
        "init: audioCfg=0x%x channels=%d sampleRate=%d samplesPerFrame=%d streams=%d coupledStreams=%d mapping=[%d,%d,%d,%d,%d,%d,%d,%d]",
        audio_configuration, channels_, sample_rate_, samples_per_frame_,
        opus_config->streams, opus_config->coupledStreams,
        opus_config->mapping[0], opus_config->mapping[1], opus_config->mapping[2], opus_config->mapping[3],
        opus_config->mapping[4], opus_config->mapping[5], opus_config->mapping[6], opus_config->mapping[7]);

    PackedByteArray mapping;
    mapping.resize(channels_);
    for (int i = 0; i < channels_; i++) {
        mapping[i] = (uint8_t)channel_mapping_[i];
    }

    int ret = opus_decoder_->init(sample_rate_, channels_, opus_config->streams, opus_config->coupledStreams, mapping);
    if (ret != 0) {
        UtilityFunctions::printerr("[AudioRenderer] Opus init failed: ", ret);
        return -1;
    }

    int output_channels = (channels_ > 2) ? 2 : channels_;
    int period_frames = samples_per_frame_;

    audio_backend_ = std::make_unique<nightfall::MiniaudioBackend>();
    if (!audio_backend_->initialize(sample_rate_, output_channels, period_frames)) {
        UtilityFunctions::printerr("[AudioRenderer] Audio backend init failed");
        return -1;
    }

    initialized_.store(true);
    UtilityFunctions::print("[AudioRenderer] Initialized: ", sample_rate_, "Hz ", channels_, "ch (output ", output_channels, "ch), ", samples_per_frame_, " spf");
    return 0;
}

void AudioRenderer::start() {
    running_.store(true);
    if (audio_backend_) audio_backend_->resume();
    UtilityFunctions::print("[AudioRenderer] Started");
}

void AudioRenderer::stop() {
    running_.store(false);
    if (audio_backend_) audio_backend_->pause();
    UtilityFunctions::print("[AudioRenderer] Stopped");
}

void AudioRenderer::cleanup() {
    running_.store(false);
    initialized_.store(false);

    if (audio_backend_) {
        audio_backend_->shutdown();
        audio_backend_.reset();
    }

    if (opus_decoder_.is_valid()) {
        opus_decoder_->cleanup();
    }
}

void AudioRenderer::decode_and_play_sample(const char *sample_data, int sample_length) {
    if (!initialized_.load() || !running_.load()) return;

    opus_data_buf_.resize(sample_length);
    memcpy(opus_data_buf_.ptrw(), sample_data, sample_length);

    int frames = opus_decoder_->decode(opus_data_buf_, samples_per_frame_);
    if (frames <= 0) return;

    if (!audio_backend_) return;

    const PackedFloat32Array &pcm = opus_decoder_->get_last_pcm();
    int total_samples = frames * channels_;
    if (pcm.size() < total_samples) return;

    const float *pcm_ptr = pcm.ptr();

    if (channels_ == 2) {
        audio_backend_->write_pcm(pcm_ptr, frames);
    } else if (channels_ > 2) {
        float stereo_buf[2048];
        for (int i = 0; i < frames && i < 1024; i++) {
            _downmix_to_stereo(pcm_ptr + i * channels_, stereo_buf + i * 2);
        }
        int out_frames = frames < 1024 ? frames : 1024;
        audio_backend_->write_pcm(stereo_buf, out_frames);
    } else {
        float stereo_buf[2048];
        for (int i = 0; i < frames && i < 1024; i++) {
            stereo_buf[i * 2] = pcm_ptr[i];
            stereo_buf[i * 2 + 1] = pcm_ptr[i];
        }
        int out_frames = frames < 1024 ? frames : 1024;
        audio_backend_->write_pcm(stereo_buf, out_frames);
    }
}

void AudioRenderer::_downmix_to_stereo(const float *multi, float *stereo) {
    float left = 0.0f;
    float right = 0.0f;

    if (channels_ >= 1) left += multi[0];
    if (channels_ >= 2) right += multi[1];

    if (channels_ >= 3) {
        float center = multi[2];
        left += center * 0.7071f;
        right += center * 0.7071f;
    }
    if (channels_ >= 4) {
        float lfe = multi[3];
        left += lfe * 0.5f;
        right += lfe * 0.5f;
    }
    if (channels_ >= 5) left += multi[4] * 0.7071f;
    if (channels_ >= 6) right += multi[5] * 0.7071f;
    if (channels_ >= 7) left += multi[6] * 0.7071f;
    if (channels_ >= 8) right += multi[7] * 0.7071f;

    stereo[0] = left;
    stereo[1] = right;
}

bool AudioRenderer::is_initialized() const {
    return initialized_.load();
}

int AudioRenderer::get_channels() const {
    return channels_;
}

int AudioRenderer::get_sample_rate() const {
    return sample_rate_;
}

float AudioRenderer::get_latency_ms() const {
    if (audio_backend_) {
        return (float)audio_backend_->get_latency_ms();
    }
    return 0.0f;
}

String AudioRenderer::get_backend_name() const {
    if (audio_backend_) {
        return String(audio_backend_->get_backend_name().c_str());
    }
    return "none";
}

void AudioRenderer::_bind_methods() {
    ClassDB::bind_method(D_METHOD("is_initialized"), &AudioRenderer::is_initialized);
    ClassDB::bind_method(D_METHOD("get_channels"), &AudioRenderer::get_channels);
    ClassDB::bind_method(D_METHOD("get_sample_rate"), &AudioRenderer::get_sample_rate);
    ClassDB::bind_method(D_METHOD("get_latency_ms"), &AudioRenderer::get_latency_ms);
    ClassDB::bind_method(D_METHOD("get_backend_name"), &AudioRenderer::get_backend_name);
}
