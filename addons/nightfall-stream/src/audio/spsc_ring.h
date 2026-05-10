#pragma once

#include <atomic>
#include <cstddef>
#include <cstring>
#include <vector>

namespace nightfall {

template <typename T>
class SpscRingBuffer {
public:
    explicit SpscRingBuffer(size_t capacity)
        : buffer_(capacity + 1) {
    }

    size_t write_available() const {
        size_t w = write_pos_.load(std::memory_order_relaxed);
        size_t r = read_pos_.load(std::memory_order_acquire);
        return (w >= r) ? (buffer_.size() - 1 - (w - r)) : (r - w - 1);
    }

    size_t read_available() const {
        size_t w = write_pos_.load(std::memory_order_acquire);
        size_t r = read_pos_.load(std::memory_order_relaxed);
        return (w >= r) ? (w - r) : (buffer_.size() - 1 - r + w);
    }

    size_t write(const T *data, size_t count) {
        size_t w = write_pos_.load(std::memory_order_relaxed);
        size_t r = read_pos_.load(std::memory_order_acquire);
        size_t avail = (w >= r) ? (buffer_.size() - 1 - (w - r)) : (r - w - 1);
        size_t to_write = (count < avail) ? count : avail;

        size_t first = (to_write < buffer_.size() - w) ? to_write : buffer_.size() - w;
        std::memcpy(buffer_.data() + w, data, first * sizeof(T));
        size_t second = to_write - first;
        if (second > 0) {
            std::memcpy(buffer_.data(), data + first, second * sizeof(T));
        }

        size_t new_w = (w + to_write) % buffer_.size();
        write_pos_.store(new_w, std::memory_order_release);
        return to_write;
    }

    size_t read(T *data, size_t count) {
        size_t r = read_pos_.load(std::memory_order_relaxed);
        size_t w = write_pos_.load(std::memory_order_acquire);
        size_t avail = (w >= r) ? (w - r) : (buffer_.size() - 1 - r + w);
        size_t to_read = (count < avail) ? count : avail;

        size_t first = (to_read < buffer_.size() - r) ? to_read : buffer_.size() - r;
        std::memcpy(data, buffer_.data() + r, first * sizeof(T));
        size_t second = to_read - first;
        if (second > 0) {
            std::memcpy(data + first, buffer_.data(), second * sizeof(T));
        }

        size_t new_r = (r + to_read) % buffer_.size();
        read_pos_.store(new_r, std::memory_order_release);
        return to_read;
    }

    void reset() {
        write_pos_.store(0, std::memory_order_relaxed);
        read_pos_.store(0, std::memory_order_relaxed);
    }

    size_t capacity() const { return buffer_.size() - 1; }

private:
    std::vector<T> buffer_;
    alignas(64) std::atomic<size_t> write_pos_{0};
    alignas(64) std::atomic<size_t> read_pos_{0};
};

} // namespace nightfall
