# Building Nightfall

## Prerequisites

- **Godot 4.6.2** (editor + export templates)
- **Android NDK 27.0.12077973**
- **JDK 17**
- **vcpkg** (for GDExtension dependency management)
- **Ninja** (build system, used by CMake)
- **ADB** (for Quest deployment)

## 0. Install Godot Plugins

Open the project in the Godot editor and install the **GodotOpenXRVendors** plugin from the Asset Library (or enable it in Project → Install Plugins). This provides Meta Quest OpenXR vendor extensions.

## 1. Clone and Build the GDExtension

The Moonlight GDExtension must be built from source. We maintain a fork with Quest hardware decoding patches:

```bash
# Clone our fork (quest-hw-decode branch has all patches applied)
git clone -b quest-hw-decode https://github.com/tB0nE/Moonlight-Godot.git ~/Development/Personal/moonlight-godot-src
```

The `quest-hw-decode` branch includes:
- JNI handshake for passing JavaVM/Android context to FFmpeg
- `ndk_codec=1` option forcing NDK MediaCodec path (HEVC hardware decode)
- Skip incompatible low-delay flags for MediaCodec
- Stats API (decoder name, frame counts, HW/SW status)
- Depth estimation JNI bridge (`submit_depth_frame` / `get_depth_map`)

### Install vcpkg

```bash
git clone https://github.com/microsoft/vcpkg.git ~/Development/Personal/vcpkg
~/Development/Personal/vcpkg/bootstrap-vcpkg.sh
```

### Android (Quest) Build

```bash
cd ~/Development/Personal/moonlight-godot-src
cp CmakeLists.txt CMakeLists.txt  # fix case in filename

export VCPKG_ROOT=~/Development/Personal/vcpkg
export VCPKG_DEFAULT_TRIPLET=arm64-android
export ANDROID_NDK_HOME=/path/to/ndk/27.0.12077973
export ANDROID_ABI=arm64-v8a

cmake --preset android
ninja -C build/android
```

This produces `build/android/bin/android/libmoonlight-godot.android.template_debug.arm64.so`.

Copy to the project:

```bash
cp build/android/bin/android/libmoonlight-godot.android.template_debug.arm64.so \
   <project-root>/addons/moonlight-godot/bin/android/
```

> **Important**: Use cmake + ninja. Manual clang++ compilation can produce a `.so` that depends on `libc++_shared.so` which isn't in the APK, causing `UnsatisfiedLinkError` crashes.

### Release Build

For release, rebuild with CMAKE_BUILD_TYPE=Release and strip:

```bash
cmake --preset android -DCMAKE_BUILD_TYPE=Release
ninja -C build/android
<path-to-ndk>/toolchains/llvm/prebuilt/linux-x86_64/bin/llvm-strip \
  --strip-debug build/android/bin/android/libmoonlight-godot.android.template_release.arm64.so \
  -o <project-root>/addons/moonlight-godot/bin/android/libmoonlight-godot.android.template_release.arm64.so
```

> **Size comparison**: Debug ~162MB, Release (stripped) ~35MB.

### Linux (Desktop) Build

```bash
cd ~/Development/Personal/moonlight-godot-src
cp CmakeLists.txt CMakeLists.txt
cmake --preset linux
ninja -C build/linux
cp build/linux/libmoonlight-godot.*.so <project-root>/addons/moonlight-godot/bin/linux/
```

## 2. Export the APK

The `build.sh` script handles everything:

```bash
# Debug build
./build.sh --debug

# Release build (requires .env with keystore credentials)
./build.sh --release

# Build and install via ADB
./build.sh --debug --install
./build.sh --release --install
```

What `build.sh` does:
1. Wipes `android/build/` and extracts Godot Android template
2. Copies `GodotApp.java` and `DepthEstimator.java`
3. Copies MiDaS TFLite model to assets
4. Patches `build.gradle` with `tensorflow-lite:2.16.1` dependency
5. Copies Meta OpenXR vendor plugin AAR
6. Exports APK via Godot headless
7. Cleans up `android/build/` (prevents Godot editor duplicate class errors)
8. Optionally installs via ADB

## 3. Deploy to Quest

```bash
adb install -r Nightfall-Android-arm64-v8a-debug.apk
```

## Project Structure

```
├── main.gd              # Coordinator: state, _ready, _process, _input, XR setup
├── main.tscn            # Scene tree
├── build.sh             # Build script (export + install)
├── project.godot        # Godot project config
├── export_presets.cfg   # Debug + Release Android export presets
├── src/
│   ├── stream_manager.gd     # Pairing, streaming lifecycle, audio, texture binding, stats
│   ├── xr_interaction.gd     # Raycasts, grab bars, corner resize, UI clicks
│   ├── input_handler.gd      # Keyboard/mouse/controller forwarding, stream mouse capture
│   ├── ui_controller.gd      # Numpad, mode toggle, stereo shader, UI updates
│   ├── auto_detect.gd        # SBS auto-detection logic
│   ├── depth_estimator.gd    # AI 3D: SubViewport capture, JNI depth pipeline, texture update
│   ├── stereo_screen.gdshader  # 2D + SBS Stretch + SBS Crop + AI 3D DIBR shader
│   ├── openxr_action_map.tres  # OpenXR controller bindings
│   └── icon.svg               # App icon
├── addons/
│   ├── moonlight-godot/       # GDExtension (built from fork)
│   └── godotopenxrvendors/    # Meta OpenXR vendor plugin v5.0.0
├── android/
│   └── src/main/
│       ├── java/com/godot/game/  # GodotApp.java, DepthEstimator.java
│       └── assets/               # midas-midas-v2-w8a8.tflite
├── BUILD.md
└── README.md
```

## Export Presets

| Preset | Package | OpenGL Debug | Compress libs | Show in Launcher |
|---|---|---|---|---|
| `NightfallDev` | `app.nightfall.quest.debug` | yes | no | no |
| `NightfallRelease` | `app.nightfall.quest` | no | yes | yes |

Both presets can coexist on the same device since they use different package names.

## Key Architecture Notes

- **Fork**: `https://github.com/tB0nE/Moonlight-Godot` (branch: `quest-hw-decode`) — upstream is `html5syt/Moonlight-Godot`
- **GDExtension Source**: Persistent copy at `~/Development/Personal/moonlight-godot-src/`
- **vcpkg**: Persistent copy at `~/Development/Personal/vcpkg/`
- **JNI Handshake**: `GodotApp.java` loads the GDExtension library in a static block and calls `initializeMoonlightJNI()` to pass the JavaVM to FFmpeg for MediaCodec. This must happen before Godot initializes.
- **Android App Context**: `setAndroidContext()` passes the Android app context to FFmpeg via `av_jni_set_android_app_ctx()` with a JNI global reference.
- **MediaCodec**: Uses NDK `AMediaCodec` API (not Java JNI wrapper) via `ndk_codec=1` FFmpeg option.
- **AI 3D Async Pipeline**: `submit_depth_frame()` submits frames to a Java ExecutorService (non-blocking). `get_depth_map()` returns the latest cached result instantly via `AtomicReference`. Main thread never blocks on inference.
- **Build Cleanup**: `build.sh` removes `android/build/` after export to prevent Godot from scanning stale `.gdc`/`.gdextension` artifacts which cause duplicate class registration errors.
- **Full Rebuild Required**: All `.cpp` files must be recompiled together when `stream_core.h` changes. Partial rebuilds cause class layout mismatches (ODR violation) leading to SIGSEGV in audio init.
- **Module Architecture**: `main.gd` is a thin coordinator holding shared state. Logic is split into `src/` modules (RefCounted classes) that receive a reference to the main node.
