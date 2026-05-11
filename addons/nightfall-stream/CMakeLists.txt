cmake_minimum_required(VERSION 3.21)

set(LIBNAME "nightfall-stream" CACHE STRING "Library name")

if(NOT DEFINED CMAKE_TOOLCHAIN_FILE)
    if(DEFINED ENV{VCPKG_ROOT})
        set(CMAKE_TOOLCHAIN_FILE "$ENV{VCPKG_ROOT}/scripts/buildsystems/vcpkg.cmake" CACHE STRING "")
    endif()
endif()

project(${LIBNAME} LANGUAGES CXX)

set(CMAKE_POSITION_INDEPENDENT_CODE ON)

if(ANDROID)
    set(TARGET_PLATFORM "android")
    add_compile_definitions("pthread_cancel(x)=0")
    remove_definitions(-D_WIN32)
elseif(CMAKE_SYSTEM_NAME STREQUAL "SteamOS" OR NIGHTFALL_PLATFORM STREQUAL "steamos")
    set(TARGET_PLATFORM "steamos")
    set(CMAKE_SYSTEM_NAME "Linux")
else()
    set(TARGET_PLATFORM "linux")
endif()

if(ANDROID)
    if(ANDROID_ABI STREQUAL "arm64-v8a")
        set(ACTUAL_ARCH "arm64")
    elseif(ANDROID_ABI STREQUAL "x86_64")
        set(ACTUAL_ARCH "x86_64")
    else()
        set(ACTUAL_ARCH "${CMAKE_SYSTEM_PROCESSOR}")
    endif()
else()
    if(CMAKE_SYSTEM_PROCESSOR STREQUAL "AMD64" OR CMAKE_SYSTEM_PROCESSOR STREQUAL "amd64")
        set(ACTUAL_ARCH "x86_64")
    elseif(CMAKE_SYSTEM_PROCESSOR STREQUAL "aarch64")
        set(ACTUAL_ARCH "arm64")
    else()
        set(ACTUAL_ARCH "${CMAKE_SYSTEM_PROCESSOR}")
    endif()
endif()

set(PLATFORM_ID "${TARGET_PLATFORM}.${ACTUAL_ARCH}")

find_package(FFMPEG REQUIRED)
find_package(unofficial-godot-cpp CONFIG REQUIRED)
find_package(moonlight-common-c CONFIG REQUIRED)
find_package(OpenSSL REQUIRED)
find_package(CURL REQUIRED)
find_package(Opus REQUIRED)

if(TARGET_PLATFORM STREQUAL "steamos" OR TARGET_PLATFORM STREQUAL "linux")
    find_package(PkgConfig)
    if(PkgConfig_FOUND)
        pkg_check_modules(AVAHI QUIET avahi-client)
    endif()
endif()

if(DEFINED GODOTCPP_SUFFIX AND NOT GODOTCPP_SUFFIX STREQUAL "")
    set(GODOTCPP_SUFFIX_INTERNAL "${GODOTCPP_SUFFIX}")
elseif(DEFINED ENV{GODOTCPP_SUFFIX})
    set(GODOTCPP_SUFFIX_INTERNAL "$ENV{GODOTCPP_SUFFIX}")
else()
    get_target_property(PROP_SUFFIX unofficial::godot::cpp GODOTCPP_SUFFIX)
    if(PROP_SUFFIX AND NOT PROP_SUFFIX MATCHES "NOTFOUND")
        set(GODOTCPP_SUFFIX_INTERNAL "${PROP_SUFFIX}")
    else()
        if(CMAKE_BUILD_TYPE STREQUAL "Release")
            set(GODOTCPP_SUFFIX_INTERNAL ".${TARGET_PLATFORM}.template_release.${ACTUAL_ARCH}")
        else()
            set(GODOTCPP_SUFFIX_INTERNAL ".${TARGET_PLATFORM}.template_debug.${ACTUAL_ARCH}")
        endif()
    endif()
endif()

add_library(${LIBNAME} SHARED)

file(GLOB_RECURSE SOURCE_FILES CONFIGURE_DEPENDS "src/*.cpp" "src/*.h")
target_sources(${LIBNAME} PRIVATE ${SOURCE_FILES})

target_compile_features(${LIBNAME} PRIVATE cxx_std_17)
target_include_directories(${LIBNAME} PRIVATE src include)
target_include_directories(${LIBNAME} PRIVATE ${FFMPEG_INCLUDE_DIRS})

if(MSVC)
    set_property(TARGET ${LIBNAME} PROPERTY MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>")
    target_compile_options(${LIBNAME} PRIVATE /W4)
else()
    target_compile_options(${LIBNAME} PRIVATE -Wall -Wextra -Wno-unused-parameter)
endif()

target_compile_definitions(${LIBNAME} PRIVATE
    NIGHTFALL_PLATFORM_${TARGET_PLATFORM}
    $<$<CONFIG:Debug>:NIGHTFALL_DEBUG>
)

if(TARGET_PLATFORM STREQUAL "steamos" OR TARGET_PLATFORM STREQUAL "linux")
    target_compile_definitions(${LIBNAME} PRIVATE NIGHTFALL_PLATFORM_LINUX)
    if(AVAHI_FOUND)
        target_compile_definitions(${LIBNAME} PRIVATE NIGHTFALL_HAS_AVAHI)
    endif()
endif()

target_compile_definitions(${LIBNAME} PRIVATE CURL_STATICLIB)

target_link_libraries(${LIBNAME}
    PRIVATE
    unofficial::godot::cpp
    moonlight-common-c::moonlight-common-c
    CURL::libcurl
    OpenSSL::SSL OpenSSL::Crypto
    Opus::opus
    ${FFMPEG_LIBRARIES}
)

if(TARGET_PLATFORM STREQUAL "steamos" OR TARGET_PLATFORM STREQUAL "linux")
    target_link_libraries(${LIBNAME} PRIVATE atomic m pthread dl)
    if(AVAHI_FOUND)
        target_link_libraries(${LIBNAME} PRIVATE ${AVAHI_LIBRARIES})
        target_include_directories(${LIBNAME} PRIVATE ${AVAHI_INCLUDE_DIRS})
    endif()
    if(TARGET_PLATFORM STREQUAL "linux")
        set(CMAKE_SHARED_LINKER_FLAGS "${CMAKE_SHARED_LINKER_FLAGS} -Wl,-Bsymbolic")
    endif()
endif()

if(ANDROID)
    target_link_libraries(${LIBNAME} PRIVATE atomic m log)
endif()

if(WIN32)
    set_target_properties(${LIBNAME} PROPERTIES
        PREFIX ""
        OUTPUT_NAME "${LIBNAME}${GODOTCPP_SUFFIX_INTERNAL}"
        RUNTIME_OUTPUT_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/bin/${TARGET_PLATFORM}"
        LIBRARY_OUTPUT_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/bin/${TARGET_PLATFORM}"
    )
else()
    set_target_properties(${LIBNAME} PROPERTIES
        PREFIX "lib"
        OUTPUT_NAME "${LIBNAME}${GODOTCPP_SUFFIX_INTERNAL}"
        RUNTIME_OUTPUT_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/bin/${TARGET_PLATFORM}"
        LIBRARY_OUTPUT_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/bin/${TARGET_PLATFORM}"
    )
endif()

set(GODOT_ADDON_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../../addons/nightfall-stream/bin/${TARGET_PLATFORM}")
add_custom_command(TARGET ${LIBNAME} POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E make_directory "${GODOT_ADDON_DIR}"
    COMMAND ${CMAKE_COMMAND} -E copy_if_different
        "$<TARGET_FILE:${LIBNAME}>"
        "${GODOT_ADDON_DIR}/$<TARGET_FILE_NAME:${LIBNAME}>"
    COMMENT "Deploying to Godot addon directory..."
)
