#pragma once

#ifdef __ANDROID__
#include <android/log.h>
#define NF_LOG(tag, fmt, ...) __android_log_print(ANDROID_LOG_INFO, tag, fmt, ##__VA_ARGS__)
#define NF_LOGE(tag, fmt, ...) __android_log_print(ANDROID_LOG_ERROR, tag, fmt, ##__VA_ARGS__)
#else
#include <cstdio>
#define NF_LOG(tag, fmt, ...) printf("[%s] " fmt "\n", tag, ##__VA_ARGS__)
#define NF_LOGE(tag, fmt, ...) fprintf(stderr, "[%s] " fmt "\n", tag, ##__VA_ARGS__)
#endif
