#pragma once

#include "platform_audio.h"
#include "spsc_ring.h"

struct ma_device;

namespace nightfall {

class MiniaudioBackend : public PlatformAudio {
public:
    MiniaudioBackend();
    ~MiniaudioBackend() override;

    bool initialize(int sample_rate, int channels, int buffer_frames) override;
    void shutdown() override;
    bool write_pcm(const float *data, size_t frames) override;
    void pause() override;
    void resume() override;
    int get_latency_ms() const override;
    std::string get_backend_name() const override;

private:
    static void _ma_data_callback(ma_device *pDevice, void *pOutput, const void *pInput, uint32_t frameCount);

    ma_device *device_ = nullptr;
    SpscRingBuffer<float> *ring_ = nullptr;
    int sample_rate_ = 48000;
    int channels_ = 2;
    std::atomic<bool> paused_{false};
    std::atomic<bool> initialized_{false};
};

} // namespace nightfall
