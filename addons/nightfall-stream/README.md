# Nightfall Stream v2 - Godot GDExtension

A focused Moonlight streaming GDExtension for Meta Quest 3/3S and Steam Frame,
purpose-built for Nightfall. Dual platform from day 1: Android arm64 (Quest)
and SteamOS arm64 (Steam Frame, Snapdragon).

## What This Replaces

Replaces the upstream [Moonlight-Godot](https://github.com/html5syt/Moonlight-Godot) plugin
(~5,400 lines hand-written C++, ~27K with docs, ~123K with miniaudio). The upstream
supports all platforms. This rewrite targets only VR headsets on arm64 Snapdragon
and strips everything irrelevant.

## Key Differences from Upstream

| Aspect | Upstream | Nightfall Stream v2 |
|--------|----------|---------------------|
| Platforms | Win/Mac/Linux/Android/iOS | Android arm64 + SteamOS arm64 |
| Audio | Godot AudioStream + miniaudio (96K) | Oboe (Android) / PipeWire (SteamOS) |
| Video decode | FFmpeg SW + HW | FFmpeg (MediaCodec HW on Android, dav1d SW on SteamOS) |
| AV1 | Not supported | Day 1 (MediaCodec HW + dav1d SW) |
| Texture upload | CPU copy via ImageTexture | Zero-copy GPU via AHardwareBuffer / RenderingDevice |
| Depth map bridge | PackedByteArray copies | Shared GPU texture |
| mTLS | cURL + mbedTLS | JNI HTTPS (Android) / cURL + OpenSSL (SteamOS) |
| mDNS | Bundled mDNS lib | NsdManager JNI (Android) / Avahi (SteamOS) |
| Reconnection | None | Exponential backoff auto-reconnect |
| Doc classes | 20K lines | None |
| Multi-instance | Supported (limited) | Single stream only |

## Architecture

```
nightfall-stream/
  src/
    core/            Stream lifecycle, connection management
    video/            Video decode + GPU texture upload
    audio/            Oboe / PipeWave audio pipeline
    input/            Input bridge (keyboard/mouse/gamepad)
    config/           Config/pairing/certificate storage
    network/          HTTP/mTLS + mDNS (platform backends)
  include/            Platform interface headers
  shaders/            YUV-RGB conversion compute shaders
```

### Platform Abstraction

Four platform interfaces in `include/`:

- `platform_decoder.h` - MediaCodec (Android) / FFmpeg SW (SteamOS)
- `platform_audio.h` - Oboe (Android) / PipeWire (SteamOS)
- `platform_http.h` - JNI HTTPS+mTLS (Android) / cURL+OpenSSL (SteamOS)
- `platform_mdns.h` - NsdManager (Android) / Avahi (SteamOS)

Compile-time dispatch via `NIGHTFALL_PLATFORM_android` / `NIGHTFALL_PLATFORM_steamos`.

## Build

### Android (Quest)
```bash
export VCPKG_ROOT=/path/to/vcpkg
export ANDROID_NDK_HOME=/path/to/ndk
export ANDROID_ABI=arm64-v8a
export VCPKG_DEFAULT_TRIPLET=arm64-android
cmake --preset android && cmake --build build/android --config Release
```

### SteamOS (Steam Frame)
```bash
export VCPKG_ROOT=/path/to/vcpkg
export VCPKG_DEFAULT_TRIPLET=arm64-linux
cmake --preset steamos-arm64 && cmake --build build/steamos-arm64 --config Release
```

## Dependencies (vcpkg)

- `ffmpeg` (avcodec, avformat, swresample, swscale, gpl, dav1d, opus) - Decode layer
- `moonlight-common-c` - Core Moonlight protocol (RTSP, encryption, frames)
- `openssl` - Certificate generation + mTLS
- `godot-cpp` - Godot C++ bindings
- `curl` (SteamOS only) - HTTP client
- Avahi (SteamOS only, system) - mDNS

## License

GPL v3 (same as Nightfall)
