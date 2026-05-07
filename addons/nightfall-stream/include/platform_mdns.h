#pragma once

#include <cstdint>
#include <functional>
#include <string>
#include <vector>

namespace nightfall {

struct MdnsService {
    std::string name;
    std::string host;
    uint16_t port = 0;
    std::string ip;
};

class PlatformMdns {
public:
    virtual ~PlatformMdns() = default;

    using ServiceCallback = std::function<void(const MdnsService&)>;
    using ErrorCallback = std::function<void(const std::string&)>;

    virtual bool start_browse(const std::string& service_type, ServiceCallback on_found, ErrorCallback on_error) = 0;
    virtual void stop_browse() = 0;

    virtual std::string get_backend_name() const = 0;
};

} // namespace nightfall
