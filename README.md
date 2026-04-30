# Nightfall

A Godot 4 XR Moonlight streaming client for Meta Quest 3/3S with HEVC hardware decoding, stereoscopic 3D, passthrough, and AI-based 2D-to-3D conversion.

## Project Status
- [x] GDExtension compilation and loading
- [x] Moonlight pairing and streaming
- [x] OpenXR integration (Quest 3/3S)
- [x] HEVC hardware decoding via NDK MediaCodec
- [x] Stereo SBS shader (2D / SBS Stretch / SBS Crop / AI 3D modes)
- [x] AI 3D: MiDaS v2 TFLite depth estimation with DIBR stereo rendering
- [x] SBS auto-detection
- [x] XR pointer interaction with grab bars and corner resize
- [x] Gamepad/controller passthrough
- [x] Mouse/keyboard passthrough with stream capture mode
- [x] Numpad UI for IP entry and pairing
- [x] Passthrough (Meta OpenXR vendor plugin)
- [x] Resolution selector (Auto / 1080p / 1440p / 4K)
- [x] Refresh rate selector (60 / 90 / 120 Hz)
- [x] Host resolution auto-detect via Sunshine HTTP API
- [x] Bitrate auto-scaling by resolution
- [x] Stats overlay (decoder, fps, bitrate, queue, frame drops)

## How to Run (Desktop)

```bash
"/var/home/tyrone/.local/share/Steam/steamapps/common/Godot Engine/godot.x11.opt.tools.64" --xr-mode on --path .
```

## How to Build (Quest)

See [BUILD.md](BUILD.md) for full build instructions including GDExtension compilation, APK export, and Quest deployment.

## Pairing

1. Launch the app on Quest
2. Enter your Sunshine host IP using the numpad
3. Press **Pair & Start Stream**
4. Enter the displayed PIN in the Sunshine web UI
5. The stream starts automatically after pairing

The last used IP is saved and restored on next launch.

## Controls

### XR (Quest Headset)
- **Hand raycasts** point at the stream screen and UI panel
- **Trigger** clicks on UI elements or captures mouse to stream
- **Grab bars** (green on hover, blue when grabbed) let you reposition screens
- **Corner handles** resize the stream screen (16:9 locked, symmetric)
- **Ctrl+Alt+Shift** releases captured mouse back to pointer mode

### Desktop
- **Mouse** aims at screens (non-XR mode uses camera rotation)
- **Left click** interacts with UI or captures mouse to stream
- **Ctrl+Alt+Esc** releases captured mouse
- **Tab** toggles between Stream and Env modes
- **WASD** moves the XR origin in Env mode

### Gamepad
- All gamepad inputs (buttons, sticks, triggers) are forwarded to the remote host during streaming
- Multi-controller support with Xbox button mapping

## Stereo Modes

- **2D**: Standard display
- **SBS Stretch**: Side-by-side content stretched to full screen
- **SBS Crop**: Side-by-side content with letterbox bars cropped
- **AI 3D**: Real-time depth estimation (MiDaS v2 TFLite) with DIBR stereo rendering

Toggle modes with the **Mode** button. Enable **Auto-Detect** to automatically switch between 2D and SBS based on content analysis.

## AI 3D Pipeline

The AI 3D mode converts any 2D stream into stereoscopic 3D:

1. Video frame captured to 256x256 SubViewport
2. Frame submitted via JNI to `DepthEstimator.java` (async, non-blocking)
3. MiDaS v2 INT8 TFLite inference on background thread (NNAPI accelerated)
4. Depth map post-processed: contrast stretch + box blur + temporal smoothing
5. Result returned to GDScript, uploaded as ImageTexture
6. DIBR shader shifts pixels per-eye based on depth values

Parameters (matching Artemis/moonlight-android defaults):
- **Parallax depth** (0-1): Maximum pixel shift per eye
- **Convergence** (0-1): Zero-parallax depth plane
- **Balance shift** (0-1): Left/right eye balance

## Shader

`src/stereo_screen.gdshader` handles stereo rendering for all 4 modes using `VIEW_INDEX` (Multiview). Modes 1-2 split SBS content, mode 3 performs DIBR with the depth texture.
