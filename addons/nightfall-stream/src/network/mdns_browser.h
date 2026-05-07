#pragma once

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/string.hpp>

namespace godot {

class MdnsBrowser : public RefCounted {
    GDCLASS(MdnsBrowser, RefCounted);

private:
    PackedByteArray _build_ptr_query(const String &service_type);
    Array _parse_dns_response(const uint8_t *data, int len);
    String _read_dns_name(const uint8_t *data, int len, int offset, int &out_end);
    int _write_dns_name(uint8_t *buf, int offset, const String &name);

protected:
    static void _bind_methods();

public:
    MdnsBrowser();
    ~MdnsBrowser();

    Array browse(float timeout = 3.0);
};

} // namespace godot
