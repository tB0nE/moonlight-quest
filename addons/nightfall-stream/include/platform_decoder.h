#pragma once

#include <cstdint>
#include <string>

namespace nightfall {

struct DecodedFrame {
    uint8_t* data[3] = {nullptr, nullptr, nullptr};
    int linesize[3] = {0, 0, 0};
    int width = 0;
    int height = 0;
    int format = 0;
    int colorspace = 0;
    int color_range = 0;
    int64_t pts = 0;
    bool is_hw_frame = false;
};

class PlatformDecoder {
public:
    virtual ~PlatformDecoder() = default;

    virtual bool initialize(int width, int height, const std::string& codec) = 0;
    virtual void shutdown() = 0;
    virtual bool submit_nal_unit(const uint8_t* data, size_t size, int64_t pts) = 0;
    virtual bool dequeue_frame(DecodedFrame& frame) = 0;
    virtual void release_frame(DecodedFrame& frame) = 0;
    virtual void flush() = 0;

    virtual std::string get_decoder_name() const = 0;
    virtual bool is_hardware_decode() const = 0;
    virtual int get_frames_dropped() const = 0;
    virtual int get_last_frame_latency_ms() const = 0;
};

} // namespace nightfall
