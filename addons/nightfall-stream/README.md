# Nightfall Stream - Godot GDExtension

Moonlight streaming plugin for Meta Quest 3/3S (Android arm64) and Linux (x86_64 desktop dev).
Built for [Nightfall](https://github.com/tB0nE/nightfall).

## Current Implementation

| Subsystem | Android (Quest) | Linux (Desktop Dev) |
|-----------|----------------|---------------------|
| Video decode | FFmpeg + MediaCodec HW (HEVC) | FFmpeg SW |
| Audio output | miniaudio (AAudio/PulseAudio) | miniaudio (PulseAudio) |
| HTTP/mTLS | cURL + OpenSSL | cURL + OpenSSL |
| mDNS | Raw UDP sockets | Raw UDP sockets |
| GPU upload | RenderingDevice (CPU copy) | RenderingDevice (CPU copy) |

## Build

### Android (Quest)
```bash
export VCPKG_ROOT=~/Development/Personal/vcpkg
export ANDROID_NDK_HOME=/path/to/ndk/27.0.12077973
export ANDROID_ABI=arm64-v8a
export VCPKG_DEFAULT_TRIPLET=arm64-android
cmake --preset android
ninja -C build_android
```

### Linux (Desktop)
```bash
export VCPKG_ROOT=~/Development/Personal/vcpkg
export VCPKG_DEFAULT_TRIPLET=x64-linux
cmake --preset linux
ninja -C build/linux
```

## Dependencies (via vcpkg)

- `ffmpeg` (avcodec, avformat, swresample, swscale, gpl, dav1d, opus)
- `moonlight-common-c` — Core Moonlight protocol (RTSP, encryption, frames)
- `openssl` — Certificate generation + mTLS
- `godot-cpp` — Godot C++ bindings
- `curl` — HTTP client

## License

GPL v3 (same as Nightfall)
