#include "ffmpeg_decoder.h"
#include <Limelight.h>
#include <godot_cpp/classes/os.hpp>
#include <godot_cpp/variant/utility_functions.hpp>
#include "nf_log.h"

#ifdef __ANDROID__
#include <dlfcn.h>
#include <jni.h>
extern "C" {
#include <libavcodec/jni.h>
}

extern "C" JNIEXPORT void JNICALL Java_com_godot_game_GodotApp_initializeMoonlightJNI(JNIEnv *env, jclass clazz) {
    JavaVM *vm = nullptr;
    if (env->GetJavaVM(&vm) == 0) {
        av_jni_set_java_vm(vm, nullptr);
        NF_LOG("FfmpegDecoder", "JNI: Set JavaVM to %p", vm);
    }
}

extern "C" JNIEXPORT void JNICALL Java_com_godot_game_GodotApp_setAndroidContext(JNIEnv *env, jclass clazz, jobject context) {
    if (context) {
        jobject global_ref = env->NewGlobalRef(context);
        if (global_ref) {
            av_jni_set_android_app_ctx(global_ref, nullptr);
            NF_LOG("FfmpegDecoder", "JNI: Set Android app context to %p (global ref)", global_ref);
        } else {
            NF_LOGE("FfmpegDecoder", "JNI: Failed to create global ref for app context");
        }
    } else {
        NF_LOGE("FfmpegDecoder", "JNI: Android app context is NULL!");
    }
}

#endif

using namespace godot;

FfmpegDecoder::FfmpegDecoder() {
    sw_frame = av_frame_alloc();
    decode_frame = av_frame_alloc();
}

FfmpegDecoder::~FfmpegDecoder() {
    cleanup();
    if (sw_frame) {
        av_frame_free(&sw_frame);
        sw_frame = nullptr;
    }
    if (decode_frame) {
        av_frame_free(&decode_frame);
        decode_frame = nullptr;
    }
}

Vector<AVHWDeviceType> FfmpegDecoder::_get_supported_hw_devices() {
    Vector<AVHWDeviceType> types;
#if defined(__ANDROID__)
#elif defined(_WIN32)
    types.push_back(AV_HWDEVICE_TYPE_VULKAN);
    types.push_back(AV_HWDEVICE_TYPE_D3D11VA);
#elif defined(__APPLE__)
    types.push_back(AV_HWDEVICE_TYPE_VIDEOTOOLBOX);
#elif defined(__linux__)
    types.push_back(AV_HWDEVICE_TYPE_VULKAN);
    types.push_back(AV_HWDEVICE_TYPE_VAAPI);
#endif
    return types;
}

Vector<String> FfmpegDecoder::get_candidate_decoders(int codec_family) {
    Vector<String> candidates;

#if defined(__ANDROID__)
    String base_codec_name;
    if (codec_family == CODEC_FAMILY_H264) base_codec_name = "h264";
    else if (codec_family == CODEC_FAMILY_H265) base_codec_name = "hevc";
    else if (codec_family == CODEC_FAMILY_AV1) base_codec_name = "av1";

    if (!base_codec_name.is_empty()) {
        Vector<String> codec_names;

        typedef jint (*JNI_GetCreatedJavaVMs_t)(JavaVM **, jsize, jsize *);
        JNI_GetCreatedJavaVMs_t jni_get_created = (JNI_GetCreatedJavaVMs_t)dlsym(RTLD_DEFAULT, "JNI_GetCreatedJavaVMs");
        if (jni_get_created) {
            JavaVM *vm = nullptr;
            jsize vm_count = 0;
            if (jni_get_created(&vm, 1, &vm_count) == JNI_OK && vm_count > 0 && vm) {
                JNIEnv *env = nullptr;
                bool attached = false;
                jint ret = vm->GetEnv(reinterpret_cast<void **>(&env), JNI_VERSION_1_6);
                if (ret == JNI_EDETACHED) {
                    ret = vm->AttachCurrentThread(&env, nullptr);
                    attached = (ret == JNI_OK);
                }
                if (env) {
                    jclass cls = env->FindClass("android/media/MediaCodecList");
                    if (cls) {
                        jmethodID mid = env->GetStaticMethodID(cls, "getCodecInfos", "()[Landroid/media/MediaCodecInfo;");
                        if (mid) {
                            jobjectArray arr = (jobjectArray)env->CallStaticObjectMethod(cls, mid);
                            if (arr) {
                                jsize len = env->GetArrayLength(arr);
                                for (jsize i = 0; i < len; i++) {
                                    jobject info = env->GetObjectArrayElement(arr, i);
                                    if (!info) continue;
                                    jclass infoCls = env->GetObjectClass(info);
                                    jmethodID nameMid = env->GetMethodID(infoCls, "getName", "()Ljava/lang/String;");
                                    if (nameMid) {
                                        jstring jname = (jstring)env->CallObjectMethod(info, nameMid);
                                        if (jname) {
                                            const char *cname = env->GetStringUTFChars(jname, nullptr);
                                            if (cname) {
                                                codec_names.push_back(String(cname));
                                                env->ReleaseStringUTFChars(jname, cname);
                                            }
                                            env->DeleteLocalRef(jname);
                                        }
                                    }
                                    env->DeleteLocalRef(info);
                                }
                            }
                        }
                        env->DeleteLocalRef(cls);
                    }
                    if (attached) vm->DetachCurrentThread();
                }
            }
        }

        for (int i = 0; i < codec_names.size(); i++) {
            String kn = codec_names[i].to_lower();
            bool matches_family = false;
            if (codec_family == CODEC_FAMILY_H264 && (kn.find("avc") != -1 || kn.find("h264") != -1))
                matches_family = true;
            else if (codec_family == CODEC_FAMILY_H265 && (kn.find("hevc") != -1 || kn.find("h265") != -1))
                matches_family = true;
            else if (codec_family == CODEC_FAMILY_AV1 && kn.find("av1") != -1)
                matches_family = true;

            if (matches_family && (kn.find("low_latency") != -1 || kn.find("low-latency") != -1)) {
                candidates.push_back(base_codec_name + "_mediacodec_lowlat:" + codec_names[i]);
            }
        }

        candidates.push_back(base_codec_name + "_mediacodec");
    }
#endif

    if (codec_family == CODEC_FAMILY_H264) {
        candidates.push_back("h264");
    } else if (codec_family == CODEC_FAMILY_H265) {
        candidates.push_back("hevc");
    } else if (codec_family == CODEC_FAMILY_AV1) {
        candidates.push_back("libdav1d");
        candidates.push_back("av1");
    }
    return candidates;
}

enum AVPixelFormat FfmpegDecoder::_get_hw_format_callback(AVCodecContext *ctx, const enum AVPixelFormat *pix_fmts) {
    FfmpegDecoder *self = static_cast<FfmpegDecoder *>(ctx->opaque);
    if (self && self->hw_pix_fmt != AV_PIX_FMT_NONE) {
        for (const enum AVPixelFormat *p = pix_fmts; *p != AV_PIX_FMT_NONE; p++) {
            if (*p == self->hw_pix_fmt)
                return *p;
        }
    }
    return avcodec_default_get_format(ctx, pix_fmts);
}

int FfmpegDecoder::_try_open_decoder(const String &codec_name, int width, int height, AVHWDeviceType hw_type, bool disable_hw) {
    String base_name = codec_name;
    int sep = codec_name.find(":");
    if (sep != -1) {
        base_name = codec_name.substr(0, sep);
    }
    if (base_name.ends_with("_lowlat")) {
        base_name = base_name.substr(0, base_name.length() - 7);
    }

    NF_LOG("FfmpegDecoder",
        "_try_open: base='%s' full='%s' hw=%s w=%d h=%d",
        base_name.utf8().get_data(), codec_name.utf8().get_data(),
        (hw_type == AV_HWDEVICE_TYPE_NONE) ? "NONE" : av_hwdevice_get_type_name(hw_type),
        width, height);

    const AVCodec *codec = avcodec_find_decoder_by_name(base_name.utf8().get_data());
    if (!codec) {
        NF_LOG("FfmpegDecoder",
            "avcodec_find_decoder_by_name FAILED for '%s'", base_name.utf8().get_data());
        return -1;
    }

    AVCodecContext *ctx = avcodec_alloc_context3(codec);
    if (!ctx)
        return -1;

    ctx->opaque = this;
    ctx->width = width;
    ctx->height = height;
    ctx->coded_width = width;
    ctx->coded_height = height;

    bool is_mediacodec = codec_name.find("_mediacodec") != -1;

    if (!is_mediacodec) {
        ctx->flags |= AV_CODEC_FLAG_LOW_DELAY;
        ctx->delay = 0;
        ctx->flags |= AV_CODEC_FLAG_OUTPUT_CORRUPT;
        ctx->flags2 |= AV_CODEC_FLAG2_SHOW_ALL;
        ctx->flags2 |= AV_CODEC_FLAG2_FAST;
        ctx->err_recognition = AV_EF_EXPLODE;
    }

    bool enforce_sw_pix_fmt = hw_type == AV_HWDEVICE_TYPE_NONE &&
            codec_name.find("av1") == -1 && codec_name.find("dav1d") == -1 &&
            !is_mediacodec;
    if (enforce_sw_pix_fmt) {
        ctx->pix_fmt = AV_PIX_FMT_YUV420P;
    }

    hw_pix_fmt = AV_PIX_FMT_NONE;
    if (hw_type != AV_HWDEVICE_TYPE_NONE) {
        int err = av_hwdevice_ctx_create(&hw_device_ctx, hw_type, nullptr, nullptr, 0);
        if (err < 0) {
            avcodec_free_context(&ctx);
            return -1;
        }
        ctx->hw_device_ctx = av_buffer_ref(hw_device_ctx);
        ctx->get_format = _get_hw_format_callback;

        if (hw_type == AV_HWDEVICE_TYPE_MEDIACODEC)
            hw_pix_fmt = AV_PIX_FMT_MEDIACODEC;
        else if (hw_type == AV_HWDEVICE_TYPE_VULKAN)
            hw_pix_fmt = AV_PIX_FMT_VULKAN;
        else if (hw_type == AV_HWDEVICE_TYPE_VAAPI)
            hw_pix_fmt = AV_PIX_FMT_VAAPI;
    }

    int thread_count = OS::get_singleton()->get_processor_count() - 1;
    if (thread_count < 1) thread_count = 1;

    if (hw_type != AV_HWDEVICE_TYPE_NONE) {
        ctx->thread_count = 1;
        ctx->thread_type = 0;
    } else {
        if (codec->capabilities & AV_CODEC_CAP_SLICE_THREADS) {
            ctx->thread_type = FF_THREAD_SLICE;
            ctx->thread_count = thread_count;
        } else {
            ctx->thread_count = 1;
        }
    }

    AVDictionary *opts = nullptr;
    if (is_mediacodec) {
        av_dict_set(&opts, "ndk_codec", "1", 0);
    }

    String special_component;
    if (sep != -1) {
        special_component = codec_name.substr(sep + 1, codec_name.length() - (sep + 1));
    }
    if (special_component != String()) {
        av_dict_set(&opts, "mediacodec_name", special_component.utf8().get_data(), 0);
    }

    int ret = avcodec_open2(ctx, codec, &opts);

    NF_LOG("FfmpegDecoder",
        "avcodec_open2 => %d base=%s full=%s hw=%s w=%d h=%d",
        ret, base_name.utf8().get_data(), codec_name.utf8().get_data(),
        (hw_type == AV_HWDEVICE_TYPE_NONE) ? "NONE" : av_hwdevice_get_type_name(hw_type),
        width, height);

    if (opts) av_dict_free(&opts);

    if (ret < 0) {
        if (hw_device_ctx) {
            av_buffer_unref(&hw_device_ctx);
            hw_device_ctx = nullptr;
        }
        avcodec_free_context(&ctx);
        return -1;
    }

    v_codec = codec;
    v_codec_ctx = ctx;
    return 0;
}

int FfmpegDecoder::probe_video_format(int codec_preference, bool disable_hw) {
    int supported_mask = 0;
    int test_w = 1280;
    int test_h = 720;

    Vector<AVHWDeviceType> hw_devices;
    if (!disable_hw) {
        hw_devices = _get_supported_hw_devices();
    }
    hw_devices.push_back(AV_HWDEVICE_TYPE_NONE);

    auto test_family = [&](int family) -> bool {
        Vector<String> candidates = get_candidate_decoders(family);
        for (int i = 0; i < candidates.size(); i++) {
            if (disable_hw && candidates[i].find("_mediacodec") != -1) continue;
            for (int j = 0; j < hw_devices.size(); j++) {
                if (_try_open_decoder(candidates[i], test_w, test_h, hw_devices[j], disable_hw) == 0) {
                    cleanup();
                    return true;
                }
            }
        }
        return false;
    };

    bool h264_ok = test_family(CODEC_FAMILY_H264);
    bool hevc_ok = (codec_preference == CODEC_FAMILY_H265 || codec_preference == 0) && test_family(CODEC_FAMILY_H265);
    bool av1_ok = (codec_preference == CODEC_FAMILY_AV1 || codec_preference == 0) && test_family(CODEC_FAMILY_AV1);

    if (codec_preference == CODEC_FAMILY_AV1 && av1_ok)
        supported_mask |= VIDEO_FORMAT_MASK_AV1;
    else if (codec_preference == CODEC_FAMILY_H265 && hevc_ok)
        supported_mask |= VIDEO_FORMAT_MASK_H265;
    else if (h264_ok)
        supported_mask |= VIDEO_FORMAT_MASK_H264;

    if (codec_preference == 0) {
        if (h264_ok) supported_mask |= VIDEO_FORMAT_MASK_H264;
        if (hevc_ok) supported_mask |= VIDEO_FORMAT_MASK_H265;
        if (av1_ok) supported_mask |= VIDEO_FORMAT_MASK_AV1;
    }
    if (supported_mask == 0)
        supported_mask = VIDEO_FORMAT_MASK_H264;

    return supported_mask;
}

int FfmpegDecoder::setup(int video_format, int width, int height, bool disable_hw) {
    cleanup();

    int family = -1;
    if (video_format & VIDEO_FORMAT_MASK_H264) family = CODEC_FAMILY_H264;
    else if (video_format & VIDEO_FORMAT_MASK_H265) family = CODEC_FAMILY_H265;
    else if (video_format & VIDEO_FORMAT_MASK_AV1) family = CODEC_FAMILY_AV1;
    if (family == -1) return -1;

    Vector<String> candidates = get_candidate_decoders(family);
    Vector<AVHWDeviceType> hw_devices;
    if (!disable_hw) hw_devices = _get_supported_hw_devices();
    hw_devices.push_back(AV_HWDEVICE_TYPE_NONE);

    NF_LOG("FfmpegDecoder",
        "setup: family=%d w=%d h=%d candidates=%d hw_devices=%d",
        family, width, height, candidates.size(), hw_devices.size());
    for (int i = 0; i < candidates.size(); i++) {
        NF_LOG("FfmpegDecoder",
            "  candidate[%d]: %s", i, candidates[i].utf8().get_data());
    }

    bool opened = false;
    String opened_name;
    String opened_hw = "Software";

    for (int i = 0; i < candidates.size(); i++) {
        if (disable_hw && candidates[i].find("_mediacodec") != -1) continue;
        for (int j = 0; j < hw_devices.size(); j++) {
            if (_try_open_decoder(candidates[i], width, height, hw_devices[j], disable_hw) == 0) {
                opened_name = candidates[i];
                if (hw_devices[j] != AV_HWDEVICE_TYPE_NONE)
                    opened_hw = String(av_hwdevice_get_type_name(hw_devices[j]));
                else if (candidates[i].find("_mediacodec") != -1)
                    opened_hw = "MediaCodec (Buffer)";
                opened = true;
                break;
            }
        }
        if (opened) break;
    }

    if (!opened) {
        UtilityFunctions::printerr("[FfmpegDecoder] No usable decoder found!");
        return -1;
    }

    UtilityFunctions::print("[FfmpegDecoder] Decoder: ", opened_name, " (", opened_hw, ") ", width, "x", height);

    video_width = width;
    video_height = height;
    is_hw_decode_active = (opened_name.find("_mediacodec") != -1) || (hw_device_ctx != nullptr);

    return 0;
}

void FfmpegDecoder::cleanup() {
    if (hw_device_ctx) {
        av_buffer_unref(&hw_device_ctx);
        hw_device_ctx = nullptr;
    }
    hw_pix_fmt = AV_PIX_FMT_NONE;
    if (v_codec_ctx) {
        avcodec_free_context(&v_codec_ctx);
        v_codec_ctx = nullptr;
    }
    v_codec = nullptr;
    is_hw_decode_active = false;
}

bool FfmpegDecoder::submit_packet(AVPacket *pkt) {
    if (!v_codec_ctx) return false;
    int ret = avcodec_send_packet(v_codec_ctx, pkt);
    return ret >= 0;
}

bool FfmpegDecoder::receive_frame(AVFrame *frame) {
    if (!v_codec_ctx) return false;
    int ret = avcodec_receive_frame(v_codec_ctx, frame);
    return ret == 0;
}

AVFrame *FfmpegDecoder::get_sw_frame() {
    return sw_frame;
}

String FfmpegDecoder::get_decoder_name() const {
    if (v_codec) return String(v_codec->name);
    return "";
}

bool FfmpegDecoder::is_hw_decode() const {
    return is_hw_decode_active;
}

int FfmpegDecoder::get_video_width() const { return video_width; }
int FfmpegDecoder::get_video_height() const { return video_height; }

AVFrame *FfmpegDecoder::decode_next_frame(AVPacket *pkt) {
    if (!v_codec_ctx || !pkt) return nullptr;

    int ret = avcodec_send_packet(v_codec_ctx, pkt);
    if (ret < 0 && ret != AVERROR(EAGAIN) && ret != AVERROR_EOF) return nullptr;

    av_frame_unref(decode_frame);
    ret = avcodec_receive_frame(v_codec_ctx, decode_frame);
    if (ret == AVERROR(EAGAIN) || ret == AVERROR_EOF) return nullptr;
    if (ret < 0) return nullptr;

    static int log_count = 0;
    if (++log_count <= 3) {
        NF_LOG("FfmpegDecoder",
            "decoded frame: fmt=%d w=%d h=%d linesize[0]=%d linesize[1]=%d data[0]=%p data[1]=%p",
            decode_frame->format, decode_frame->width, decode_frame->height,
            decode_frame->linesize[0], decode_frame->linesize[1],
            decode_frame->data[0], decode_frame->data[1]);
    }

    if (decode_frame->format == hw_pix_fmt && hw_device_ctx) {
        av_frame_unref(sw_frame);
        ret = av_hwframe_transfer_data(sw_frame, decode_frame, 0);
        if (ret < 0) return nullptr;
        av_frame_copy_props(sw_frame, decode_frame);
        return sw_frame;
    }

    return decode_frame;
}

void FfmpegDecoder::_bind_methods() {
    ClassDB::bind_method(D_METHOD("probe_video_format", "codec_preference", "disable_hw"), &FfmpegDecoder::probe_video_format);
    ClassDB::bind_method(D_METHOD("setup", "video_format", "width", "height", "disable_hw"), &FfmpegDecoder::setup);
    ClassDB::bind_method(D_METHOD("cleanup"), &FfmpegDecoder::cleanup);
    ClassDB::bind_method(D_METHOD("get_decoder_name"), &FfmpegDecoder::get_decoder_name);
    ClassDB::bind_method(D_METHOD("is_hw_decode"), &FfmpegDecoder::is_hw_decode);
    ClassDB::bind_method(D_METHOD("get_video_width"), &FfmpegDecoder::get_video_width);
    ClassDB::bind_method(D_METHOD("get_video_height"), &FfmpegDecoder::get_video_height);
}
