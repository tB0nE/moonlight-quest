#pragma once

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/callable.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/string.hpp>
#include <thread>
#include <memory>
#include "platform_http.h"

namespace godot {

class HttpRequester : public RefCounted {
    GDCLASS(HttpRequester, RefCounted);

private:
    static void _perform_async(std::shared_ptr<nightfall::PlatformHttp> client, String url, String method, PackedByteArray body, Dictionary headers, Dictionary ssl_options, Callable callback);

protected:
    static void _bind_methods();

public:
    HttpRequester();
    ~HttpRequester();

    void request(String url, String method, PackedByteArray body, Dictionary headers, Dictionary ssl_options, Callable callback);
};

} // namespace godot
