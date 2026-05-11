#include "depth_bridge.h"
#include "nf_log.h"

#ifdef __ANDROID__
#include <dlfcn.h>
#include <jni.h>

static JNIEnv *get_jni_env() {
    typedef jint (*JNI_GetCreatedJavaVMs_t)(JavaVM **, jsize, jsize *);
    JNI_GetCreatedJavaVMs_t jni_get_created = (JNI_GetCreatedJavaVMs_t)dlsym(RTLD_DEFAULT, "JNI_GetCreatedJavaVMs");
    if (!jni_get_created) return nullptr;
    JavaVM *vm = nullptr;
    jsize vm_count = 0;
    jint result = jni_get_created(&vm, 1, &vm_count);
    if (result != JNI_OK || vm_count == 0) return nullptr;
    JNIEnv *env;
    result = vm->AttachCurrentThread(&env, NULL);
    if (result != JNI_OK) return nullptr;
    return env;
}
#endif

using namespace godot;

DepthBridge::DepthBridge() {}
DepthBridge::~DepthBridge() {}

void DepthBridge::submit_depth_frame(const PackedByteArray &frame_data, int width, int height) {
#ifdef __ANDROID__
    JNIEnv *env = get_jni_env();
    if (!env) return;

    jclass app_class = env->FindClass("com/godot/game/GodotApp");
    if (!app_class) return;

    jmethodID method = env->GetStaticMethodID(app_class, "submitDepthFrame", "([BII)V");
    if (!method) {
        env->DeleteLocalRef(app_class);
        return;
    }

    jbyteArray input_array = env->NewByteArray(frame_data.size());
    env->SetByteArrayRegion(input_array, 0, frame_data.size(), reinterpret_cast<const jbyte *>(frame_data.ptr()));
    env->CallStaticVoidMethod(app_class, method, input_array, width, height);
    env->DeleteLocalRef(input_array);
    env->DeleteLocalRef(app_class);
#endif
}

PackedByteArray DepthBridge::get_depth_map() {
    PackedByteArray empty;
#ifdef __ANDROID__
    JNIEnv *env = get_jni_env();
    if (!env) return empty;

    jclass app_class = env->FindClass("com/godot/game/GodotApp");
    if (!app_class) return empty;

    jmethodID method = env->GetStaticMethodID(app_class, "getLatestDepthMap", "()[B");
    if (!method) {
        env->DeleteLocalRef(app_class);
        return empty;
    }

    jbyteArray result_array = (jbyteArray)env->CallStaticObjectMethod(app_class, method);

    PackedByteArray depth_data;
    if (result_array) {
        jsize len = env->GetArrayLength(result_array);
        if (len > 0) {
            depth_data.resize(len);
            jbyte *bytes = env->GetByteArrayElements(result_array, nullptr);
            memcpy(depth_data.ptrw(), bytes, len);
            env->ReleaseByteArrayElements(result_array, bytes, JNI_ABORT);
        }
        env->DeleteLocalRef(result_array);
    }

    env->DeleteLocalRef(app_class);
    return depth_data;
#else
    return empty;
#endif
}

void DepthBridge::set_depth_model(int model_index) {
#ifdef __ANDROID__
    JNIEnv *env = get_jni_env();
    if (!env) return;

    jclass app_class = env->FindClass("com/godot/game/GodotApp");
    if (!app_class) return;

    jmethodID method = env->GetStaticMethodID(app_class, "setDepthModel", "(I)V");
    if (!method) {
        env->DeleteLocalRef(app_class);
        return;
    }

    env->CallStaticVoidMethod(app_class, method, (jint)model_index);
    env->DeleteLocalRef(app_class);
#endif
}

void DepthBridge::_bind_methods() {
    ClassDB::bind_method(D_METHOD("submit_depth_frame", "frame_data", "width", "height"), &DepthBridge::submit_depth_frame);
    ClassDB::bind_method(D_METHOD("get_depth_map"), &DepthBridge::get_depth_map);
    ClassDB::bind_method(D_METHOD("set_depth_model", "model_index"), &DepthBridge::set_depth_model);
}
