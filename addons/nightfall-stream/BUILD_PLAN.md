# Nightfall Stream v2 - Build Plan

## Overview

Rewrite the Moonlight-Godot GDExtension as a focused, dual-platform streaming plugin
for Meta Quest 3/3S (Android arm64) and Steam Frame (SteamOS arm64, Snapdragon).

Total estimated effort: ~8 weeks.

The upstream plugin is ~5,400 lines of hand-written C++ (27K with doc_classes, 123K with miniaudio).
Our target is ~4,000 lines with dual platform support, platform abstraction layer, and
AV1 day 1.

## Guiding Principles

1. Dual platform from day 1: Android arm64 (Quest) + SteamOS arm64 (Steam Frame).
2. FFmpeg as the common decode layer. Android uses MediaCodec HW via FFmpeg (`ndk_codec=1`),
   SteamOS uses SW decode via FFmpeg (dav1d for AV1).
3. AV1 support from day 1. MediaCodec HW decode on Quest, dav1d SW on SteamOS.
4. Platform abstraction via compile-time dispatch (`NIGHTFALL_PLATFORM_android` /
   `NIGHTFALL_PLATFORM_steamos`). Four interfaces: decoder, audio, http, mdns.
5. Zero-copy GPU paths wherever possible. No CPU-side texture copies.
6. MoonlightConfigManager API compatibility so existing Nightfall GDScript code works unchanged.
7. Single active stream. No multi-instance support needed.
8. Auto-reconnect on stream drop.

## Platform Matrix

| Subsystem | Android (Quest) | SteamOS (Steam Frame) |
|-----------|----------------|----------------------|
| Video decode | FFmpeg + MediaCodec HW | FFmpeg SW (dav1d for AV1) |
| Audio output | Oboe (low-latency) | PipeWire |
| HTTP/mTLS | JNI HttpURLConnection | cURL + OpenSSL |
| mDNS | NsdManager (JNI) | Avahi (system lib) |
| GPU upload | AHardwareBuffer + VK external memory | Same (Adreno Vulkan) |
| Audio codec | Opus (via FFmpeg) | Opus (via FFmpeg) |

## Phase 0: Project Scaffolding (2 days) - IN PROGRESS

Set up the build system and project structure.

- [x] Create CMakeLists.txt with dual presets (android, steamos-arm64)
- [x] Configure vcpkg dependencies (ffmpeg, moonlight-common-c, openssl, godot-cpp)
- [x] Set up godot-cpp integration
- [x] Create .gdextension file pointing to output .so
- [x] Create register_types.cpp with NightfallStream stub
- [x] Create platform interface headers (decoder, audio, http, mdns)
- [ ] Verify build produces loadable .so on Quest
- [ ] Verify build compiles for SteamOS cross-compile target

### Dependencies (via vcpkg)
- `ffmpeg` (avcodec, avformat, swresample, swscale, gpl, dav1d, opus) - Decode layer
- `moonlight-common-c` - Core Moonlight protocol (RTSP, encryption, frames)
- `openssl` - Certificate generation + mTLS
- `godot-cpp` - Godot C++ bindings
- `curl` (SteamOS only) - HTTP client
- Avahi (SteamOS only, system pkg-config) - mDNS

### Dropped Dependencies
- `miniaudio` - 96K lines, replaced by Oboe (Android) + PipeWire (SteamOS)
- `doc_classes` - 20K lines of editor docs
- `mbedTLS` - replaced by OpenSSL (SteamOS) / platform TLS (Android)

## Phase 1: Core + Config (1 week)

Port the configuration and pairing layer with dual HTTP/mDNS backends.

### 1a: MoonlightConfigManager
- [ ] Port config_manager.cpp/h from upstream
- [ ] Simplify: remove Qt-style escaping, use plain INI
- [ ] Keep API identical: `get_hosts()`, `get_apps()`, certificate storage
- [ ] Test: existing Nightfall GDScript pairing flow works unchanged

### 1b: MoonlightComputerManager + Platform Backends
- [ ] Port computer_manager.cpp/h from upstream
- [ ] Implement `PlatformHttp` backends:
  - Android: `JniHttpClient` - `HttpURLConnection` via JNI, mTLS via `KeyStore`
  - SteamOS: `CurlHttpClient` - cURL + OpenSSL, mTLS via cert files
- [ ] Implement `PlatformMdns` backends:
  - Android: `NsdManagerMdns` - `NsdManager` via JNI
  - SteamOS: `AvahiMdns` - Avahi client library
- [ ] Port pairing flow (5-phase AES-ECB challenge-response)
- [ ] Test: pair with Sunshine, get app list (both platforms)

### 1c: Stream Configuration Structs
- [ ] Port stream_core_struct.cpp/h
- [ ] MoonlightStreamConfigurationResource, MoonlightAdditionalStreamOptions
- [ ] Keep API identical

## Phase 2: Video Pipeline (2.5 weeks) - THE HARD PART

The upstream uses FFmpeg, then copies decoded frames to CPU memory, then uploads
to GPU via ImageTexture. We replace the texture upload with zero-copy GPU paths
and keep FFmpeg as the common decode layer.

### 2a: FFmpeg Decode (Common Layer)
- [ ] Create `src/video/ffmpeg_decoder.cpp/h` - FFmpeg wrapper
- [ ] Android: configure with `ndk_codec=1` for MediaCodec HW decode
- [ ] SteamOS: configure for SW decode (dav1d for AV1, FFmpeg H.264/HEVC)
- [ ] HEVC (H.265), H.264, and AV1 codec support
- [ ] Port JNI handshake from upstream quest-hw-decode branch (Android)
- [ ] Implement decode thread: receive PDECODE_UNIT from moonlight-common-c,
  queue NAL units into FFmpeg, dequeue decoded frames

### 2b: Zero-Copy GPU Texture Upload
- [ ] Create `src/video/texture_uploader.cpp/h`
- [ ] Android: AHardwareBuffer path:
  - `AMediaCodec_getOutputImage()` -> AHardwareBuffer
  - `vkGetAndroidHardwareBufferPropertiesANDROID` -> Vulkan image
  - Wrap in Godot `Texture2DRD`
- [ ] SteamOS: same Vulkan external memory path (Adreno Vulkan available)
- [ ] Fallback: CPU copy via ImageTexture (same as upstream)
- [ ] Stats API: `get_decoder_name()`, `is_hw_decode()`, `get_video_width()`,
  `get_video_height()`, `get_frames_dropped()`, `get_last_frame_latency()`

### 2c: YUV-RGB Conversion
- [ ] Create `shaders/yuv_to_rgb.comp` - Vulkan compute shader
- [ ] Handle NV12 (HEVC/AV1 HW output) and YUV420P (H.264 HW output) formats
- [ ] Color space: BT.601, BT.709, BT.2020
- [ ] Color range: limited vs full
- [ ] Integrate with Godot's compute pipeline via RenderingDevice

### 2d: Depth Map Bridge (Improved)
- [ ] Create `src/video/depth_bridge.cpp/h`
- [ ] GPU texture sharing path: TFLite -> AHardwareBuffer -> Vulkan texture
- [ ] Keep API: `submit_depth_frame()`, `get_depth_map()`, `set_depth_model()`,
  `has_depth_model_v2()`
- [ ] Fallback: keep existing PackedByteArray approach

## Phase 3: Audio Pipeline (1 week)

### 3a: Oboe Integration (Android)
- [ ] Add oboe as a CMake subproject (single directory, no vcpkg needed)
- [ ] Create `src/audio/oboe_pipeline.cpp/h`
- [ ] 48kHz, stereo, float, LowLatency, Exclusive mode
- [ ] Opus decode via FFmpeg

### 3b: PipeWire Integration (SteamOS)
- [ ] Create `src/audio/pipewire_pipeline.cpp/h`
- [ ] PipeWire stream output with similar parameters
- [ ] Opus decode via FFmpeg

### 3c: Godot AudioStream (Fallback)
- [ ] Keep `AudioStreamMoonlight` / `AudioStreamPlaybackMoonlight` as fallback
- [ ] Simplify: stereo only, no multi-channel separation

### 3d: Audio Bypass API
- [ ] `start_native_audio_bypass()`, `stop_native_audio_bypass()`,
  `pause_native_audio_bypass()`, `resume_native_audio_bypass()`
- [ ] Oboe (Android) / PipeWire (SteamOS) under the hood

## Phase 4: Input Bridge (3 days)

Port the input layer. Mostly thin wrappers around moonlight-common-c Limelight APIs.

### 4a: Input Forwarding
- [ ] Create `src/input/input_bridge.cpp/h`
- [ ] Port all `send_*_event()` methods (mouse, keyboard, gamepad, touch, scroll)
- [ ] Port input enum definitions (stream_core_input_enum.h/cpp)
- [ ] Keep MoonlightInput class with identical enum values
- [ ] Same code for both platforms (no platform difference for input)

## Phase 5: Stream Lifecycle (1.5 weeks)

### 5a: StreamConnection
- [ ] Create `src/core/stream_connection.cpp/h`
- [ ] `LiStartConnection` / `LiStopConnection` lifecycle
- [ ] Wire Limelight callbacks (CONNECTION_LISTENER, DECODER_RENDERER, AUDIO_RENDERER)
- [ ] Signal emission: `connection_started`, `connection_terminated`, `log_message`

### 5b: Auto-Reconnection
- [ ] Exponential backoff: 1s, 2s, 4s, 8s, max 30s
- [ ] /resume instead of /launch if host reports active session
- [ ] `set_auto_reconnect(enabled, max_attempts)`

### 5c: Public API
- [ ] `NightfallStream` (extends Node, replaces MoonlightStreamCore)
- [ ] Methods:
  ```
  set_config_manager(cm)
  start_play_stream(host_id, app_id, config, options)
  stop_play_stream()
  set_render_target(texture_rect)
  get_audio_stream() -> AudioStream
  reset_audio_stream() / reset_render_target()
  # Stats
  get_decoder_name() -> String
  get_video_width() -> int / get_video_height() -> int
  is_hw_decode() -> bool
  get_frames_dropped() -> int
  get_last_frame_latency() -> int
  # Depth
  submit_depth_frame(data, w, h)
  get_depth_map() -> PackedByteArray
  set_depth_model(index) / has_depth_model_v2() -> bool
  # Audio bypass
  start_native_audio_bypass() -> bool
  stop_native_audio_bypass() / pause / resume
  # Input (all send_*_event methods)
  # Reconnection
  set_auto_reconnect(enabled, max_attempts)
  ```
- [ ] Signals:
  ```
  connection_started()
  connection_terminated(error_code, message)
  log_message(message)
  reconnect_attempt(attempt) / reconnect_failed()
  ```

## Phase 6: Godot Integration + Testing (1 week)

### 6a: Nightfall GDScript Migration
- [ ] Update main.gd: `MoonlightStreamCore` -> `NightfallStream`
- [ ] Update stream_manager.gd: adapt to new API
- [ ] Update host_discovery.gd: adapt mDNS
- [ ] Update depth_estimator.gd: test improved depth bridge
- [ ] Remove upstream moonlight-godot addon from project

### 6b: Testing Checklist
- [ ] Pair with Sunshine host (both platforms)
- [ ] Start/stop stream at 1080p60, 1440p90, 4K60
- [ ] HEVC hardware decode working
- [ ] H.264 hardware decode working
- [ ] AV1 decode working (MediaCodec HW on Quest, dav1d on SteamOS)
- [ ] Audio plays with low latency
- [ ] Keyboard/mouse/gamepad input forwarded
- [ ] Auto-reconnect on network drop
- [ ] Depth map bridge works with AI 3D modes
- [ ] State save/load still works

## File Structure

```
addons/nightfall-stream/
  README.md
  BUILD_PLAN.md
  CMakeLists.txt
  CMakePresets.json
  vcpkg.json
  vcpkg-configuration.json
  bin/
    nightfall-stream.gdextension
    android/                    # Quest .so files
    steamos/                    # Steam Frame .so files
  src/
    core/
      stream_connection.cpp     # RTSP lifecycle, Limelight callbacks
      stream_connection.h
      stream_stats.cpp          # Decoder stats API
      stream_stats.h
    video/
      ffmpeg_decoder.cpp        # FFmpeg decode wrapper (common)
      ffmpeg_decoder.h
      texture_uploader.cpp      # Zero-copy GPU upload
      texture_uploader.h
      depth_bridge.cpp          # Depth map GPU sharing
      depth_bridge.h
      yuv_shader.cpp            # YUV-RGB conversion setup
      yuv_shader.h
    audio/
      oboe_pipeline.cpp         # Oboe output (Android)
      oboe_pipeline.h
      pipewire_pipeline.cpp     # PipeWire output (SteamOS)
      pipewire_pipeline.h
      audio_stream.cpp          # Godot AudioStream fallback
      audio_stream.h
    input/
      input_bridge.cpp          # All send_*_event methods
      input_bridge.h
      input_enum.cpp            # Limelight enum wrappers
      input_enum.h
    config/
      config_manager.cpp        # Host/app/cert persistence
      config_manager.h
      computer_manager.cpp      # Pairing, app list, serverinfo
      computer_manager.h
    network/
      jni_http_client.cpp       # Android JNI HTTPS + mTLS
      jni_http_client.h
      curl_http_client.cpp      # SteamOS cURL + OpenSSL
      curl_http_client.h
      jni_mdns.cpp              # Android NsdManager mDNS
      jni_mdns.h
      avahi_mdns.cpp            # SteamOS Avahi mDNS
      avahi_mdns.h
    register_types.cpp          # GDExtension entry point
    register_types.h
    nightfall_stream.cpp        # Public Node class
    nightfall_stream.h
  include/
    platform_decoder.h          # Platform interface: video decode
    platform_audio.h            # Platform interface: audio output
    platform_http.h             # Platform interface: HTTP + mTLS
    platform_mdns.h             # Platform interface: mDNS
  shaders/
    yuv_to_rgb.comp             # Vulkan compute YUV conversion
  vcpkg-overlay/
    moonlight-common-c/         # Custom vcpkg port for moonlight-common-c
```

## Risk Assessment

| Phase | Risk | Mitigation |
|-------|------|-----------|
| 2b: Zero-copy GPU | Vulkan external memory may not work with Godot's RD | Keep CPU fallback path |
| 2a: FFmpeg + MediaCodec | FFmpeg `ndk_codec` config quirks | Port proven code from quest-hw-decode branch |
| 2a: AV1 | MediaCodec AV1 may not be on all Quests | H.264/HEVC fallback always available |
| 3b: PipeWire | PipeWire API complexity, SteamOS specifics | ALSA fallback if needed |
| 1b: JNI HTTP | mTLS via Android KeyStore | Test with Sunshine self-signed certs |
| 1b: Avahi | Avahi client threading model | Run in dedicated thread |
| 5b: Reconnect | /resume endpoint may not work if host state is stale | Fall back to /launch |

## What We Keep Unchanged from Upstream

- `moonlight-common-c` protocol library (RTSP/encryption/frame code)
- MoonlightConfigManager API (GDScript compatibility)
- MoonlightComputerManager pairing flow logic
- Input enum values and send_*_event method signatures
- MoonlightStreamConfigurationResource / MoonlightAdditionalStreamOptions APIs

## What We Drop Entirely

- miniaudio (96K lines, replaced by Oboe + PipeWire)
- doc_classes (20K lines of editor docs)
- mbedTLS (replaced by OpenSSL on SteamOS, platform TLS on Android)
- Multi-instance streaming
- SteamAudio integration
- iOS/macOS/Windows/x86_64 platform code
- Godot AudioStream multi-channel separation
