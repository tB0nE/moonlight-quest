#include "miniaudio_backend.h"

#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Wall"
#pragma GCC diagnostic ignored "-Wextra"
#define MINIAUDIO_IMPLEMENTATION
#include <miniaudio.h>
#pragma GCC diagnostic pop

#include "nf_log.h"

namespace nightfall {

MiniaudioBackend::MiniaudioBackend() {}

MiniaudioBackend::~MiniaudioBackend() {
    shutdown();
}

void MiniaudioBackend::_ma_data_callback(ma_device *pDevice, void *pOutput, const void * /*pInput*/, uint32_t frameCount) {
    auto *self = static_cast<MiniaudioBackend *>(pDevice->pUserData);
    if (!self || !self->ring_ || self->paused_.load(std::memory_order_relaxed)) {
        memset(pOutput, 0, frameCount * self->channels_ * sizeof(float));
        return;
    }

    size_t total_samples = (size_t)frameCount * self->channels_;
    size_t read = self->ring_->read(static_cast<float *>(pOutput), total_samples);

    if (read < total_samples) {
        memset(static_cast<float *>(pOutput) + read, 0, (total_samples - read) * sizeof(float));
    }
}

bool MiniaudioBackend::initialize(int sample_rate, int channels, int buffer_frames) {
    if (initialized_.load()) return true;

    sample_rate_ = sample_rate;
    channels_ = channels;

    size_t ring_size = (size_t)(sample_rate * channels * 0.2);
    size_t pow2 = 1;
    while (pow2 < ring_size) pow2 <<= 1;
    ring_ = new SpscRingBuffer<float>(pow2);

    device_ = new ma_device();
    ma_device_config config = ma_device_config_init(ma_device_type_playback);
    config.playback.format = ma_format_f32;
    config.playback.channels = (ma_uint32)channels;
    config.sampleRate = (ma_uint32)sample_rate;
    config.periodSizeInFrames = (ma_uint32)buffer_frames;
    config.dataCallback = _ma_data_callback;
    config.pUserData = this;

    ma_result result = ma_device_init(nullptr, &config, device_);
    if (result != MA_SUCCESS) {
        NF_LOG("MiniaudioBackend", "Init failed: %d", result);
        delete device_;
        device_ = nullptr;
        delete ring_;
        ring_ = nullptr;
        return false;
    }

    result = ma_device_start(device_);
    if (result != MA_SUCCESS) {
        NF_LOG("MiniaudioBackend", "Start failed: %d", result);
        ma_device_uninit(device_);
        delete device_;
        device_ = nullptr;
        delete ring_;
        ring_ = nullptr;
        return false;
    }

    initialized_.store(true);
    NF_LOG("MiniaudioBackend", "Initialized: %dHz %dch, period=%d, backend=%s",
           sample_rate, channels, buffer_frames, ma_get_backend_name(device_->pContext->backend));
    return true;
}

void MiniaudioBackend::shutdown() {
    if (!initialized_.load()) return;

    initialized_.store(false);

    if (device_) {
        ma_device_stop(device_);
        ma_device_uninit(device_);
        delete device_;
        device_ = nullptr;
    }

    if (ring_) {
        delete ring_;
        ring_ = nullptr;
    }
}

bool MiniaudioBackend::write_pcm(const float *data, size_t frames) {
    if (!ring_ || !initialized_.load()) return false;
    size_t samples = frames * (size_t)channels_;
    size_t written = ring_->write(data, samples);
    return written == samples;
}

void MiniaudioBackend::pause() {
    paused_.store(true);
    if (device_) ma_device_stop(device_);
}

void MiniaudioBackend::resume() {
    paused_.store(false);
    if (device_) ma_device_start(device_);
}

int MiniaudioBackend::get_latency_ms() const {
    if (!ring_ || !initialized_.load()) return 0;
    size_t avail = ring_->read_available();
    int frames = (int)(avail / (size_t)channels_);
    if (sample_rate_ > 0) {
        return frames * 1000 / sample_rate_;
    }
    return 0;
}

std::string MiniaudioBackend::get_backend_name() const {
    if (device_ && device_->pContext) {
        return ma_get_backend_name(device_->pContext->backend);
    }
    return "miniaudio";
}

} // namespace nightfall
