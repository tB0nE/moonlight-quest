#include "http_requester.h"
#include "curl_http_client.h"
#include <godot_cpp/variant/utility_functions.hpp>

using namespace godot;

HttpRequester::HttpRequester() {
}

HttpRequester::~HttpRequester() {}

void HttpRequester::request(String url, String method, PackedByteArray body, Dictionary headers, Dictionary ssl_options, Callable callback) {
    auto client = std::make_shared<nightfall::CurlHttpClient>();

    if (ssl_options.has("client_cert") && ssl_options.has("client_key")) {
        String cert = ssl_options["client_cert"];
        String key = ssl_options["client_key"];
        if (!cert.is_empty() && !key.is_empty()) {
            client->set_client_cert(cert.utf8().get_data(), key.utf8().get_data());
        }
    }

    if (ssl_options.has("server_cert")) {
        String ca = ssl_options["server_cert"];
        if (!ca.is_empty()) {
            client->set_server_cert_pin(ca.utf8().get_data());
        }
    }

    bool verify_peer = ssl_options.get("verify_peer", true);
    client->set_verify_peer(verify_peer);
    if (!verify_peer) {
        client->set_server_cert_pin("");
    }

    client->set_timeout_ms(15000);

    std::thread([=]() {
        _perform_async(client, url, method, body, headers, ssl_options, callback);
    }).detach();
}

void HttpRequester::_perform_async(std::shared_ptr<nightfall::PlatformHttp> client, String url, String method, PackedByteArray body, Dictionary headers, Dictionary ssl_options, Callable callback) {
    std::string url_std = url.utf8().get_data();
    std::string method_std = method.to_upper().utf8().get_data();

    nightfall::HttpResponse resp;

    if (method_std == "GET") {
        resp = client->get(url_std);
    } else if (method_std == "POST") {
        std::vector<uint8_t> body_vec;
        if (body.size() > 0) {
            body_vec.assign(body.ptr(), body.ptr() + body.size());
        }
        resp = client->post(url_std, "application/octet-stream", body_vec);
    } else {
        resp.status_code = -1;
        resp.body = "Unsupported method";
    }

    PackedByteArray resp_body;
    resp_body.resize(static_cast<int>(resp.data.size()));
    if (!resp.data.empty()) {
        memcpy(resp_body.ptrw(), resp.data.data(), resp.data.size());
    }

    String error_text;
    if (resp.status_code <= 0) {
        error_text = String(resp.body.c_str());
    }

    callback.call_deferred(resp.status_code, resp_body, Dictionary(), error_text);
}

void HttpRequester::_bind_methods() {
    ClassDB::bind_method(D_METHOD("request", "url", "method", "body", "headers", "ssl_options", "callback"), &HttpRequester::request);
}
