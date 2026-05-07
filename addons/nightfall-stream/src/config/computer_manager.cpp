#include "computer_manager.h"
#include <godot_cpp/classes/file_access.hpp>
#include <godot_cpp/classes/marshalls.hpp>
#include <godot_cpp/classes/project_settings.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

using namespace godot;

NightfallComputerManager::NightfallComputerManager() {
    http_requester = memnew(HttpRequester);
    owns_requester = true;
    owns_config_manager = false;
}

NightfallComputerManager::~NightfallComputerManager() {
    if (http_requester && owns_requester) {
        memdelete(http_requester);
    }
    if (config_manager && owns_config_manager) {
        memdelete(config_manager);
    }
}

void NightfallComputerManager::set_config_manager(Object *cm) {
    config_manager = Object::cast_to<NightfallConfigManager>(cm);
    owns_config_manager = false;
}

void NightfallComputerManager::set_http_requester(Object *req) {
    if (http_requester && owns_requester) {
        memdelete(http_requester);
    }
    http_requester = Object::cast_to<HttpRequester>(req);
    owns_requester = false;
}

NightfallConfigManager *_ensure_config(NightfallConfigManager *&cm, bool &owns) {
    if (!cm) {
        cm = memnew(NightfallConfigManager);
        owns = true;
    }
    return cm;
}

String NightfallComputerManager::start_pair(String ip, int port) {
    _ensure_config(config_manager, owns_config_manager);

    _reset_pairing();
    pair_ip = ip;
    pair_port = port;
    pair_https_port = cached_https_ports.get(ip, 47984);
    unique_id = _get_unique_id();
    current_uuid = _get_uuid();

    int pin_val = UtilityFunctions::randi() % 10000;
    pair_pin = String::num_int64(pin_val).pad_zeros(4);

    pair_salt = _generate_random_bytes(16);
    pair_aes_key = _calculate_aes_key(pair_salt, pair_pin);

    pair_state = PAIR_STAGE_0_PREFLIGHT;
    _step_pair();

    return pair_pin;
}

void NightfallComputerManager::_step_pair() {
    if (pair_state == PAIR_IDLE || pair_state == PAIR_FINISHED || pair_state == PAIR_ERROR)
        return;

    is_requesting = true;
    String base_url = "http://" + pair_ip + ":" + String::num_int64(pair_port) + "/pair";
    String common_params = "uniqueid=" + unique_id + "&uuid=" + current_uuid + "&devicename=nightfall&updateState=1";

    Dictionary ssl_opts;

    switch (pair_state) {
        case PAIR_STAGE_0_PREFLIGHT: {
            String url = "http://" + pair_ip + ":" + String::num_int64(pair_port) + "/serverinfo?uniqueid=" + unique_id + "&uuid=" + current_uuid;
            http_requester->request(url, "GET", PackedByteArray(), Dictionary(), Dictionary(), callable_mp(this, &NightfallComputerManager::_on_pair_request_completed).bind(0));
            break;
        }
        case PAIR_STAGE_1_GET_CERT: {
            Dictionary keys = config_manager->get_client_keys();
            String client_cert_pem = keys["certificate"];
            PackedByteArray cert_bytes = client_cert_pem.to_utf8_buffer();

            String url = base_url + "?" + common_params + "&phrase=getservercert&salt=" + _bytes_to_hex(pair_salt) + "&clientcert=" + _bytes_to_hex(cert_bytes);
            http_requester->request(url, "GET", PackedByteArray(), Dictionary(), ssl_opts, callable_mp(this, &NightfallComputerManager::_on_pair_request_completed).bind(1));
            break;
        }
        case PAIR_STAGE_2_CLIENT_CHALLENGE: {
            client_secret_random = _generate_random_bytes(16);
            PackedByteArray challenge_enc = _encrypt_aes_ecb(client_secret_random, pair_aes_key);

            String url = base_url + "?" + common_params + "&clientchallenge=" + _bytes_to_hex(challenge_enc);
            http_requester->request(url, "GET", PackedByteArray(), Dictionary(), ssl_opts, callable_mp(this, &NightfallComputerManager::_on_pair_request_completed).bind(2));
            break;
        }
        case PAIR_STAGE_3_SERVER_RESPONSE: {
            Dictionary keys = config_manager->get_client_keys();
            String cert_clean = String(keys["certificate"]).replace("-----BEGIN CERTIFICATE-----", "").replace("-----END CERTIFICATE-----", "").replace("\n", "").replace("\r", "");
            PackedByteArray cert_der = Marshalls::get_singleton()->base64_to_raw(cert_clean);
            PackedByteArray cert_sig = _extract_signature_from_der(cert_der);

            client_pairing_secret = _generate_random_bytes(16);

            PackedByteArray payload;
            payload.append_array(server_challenge);
            payload.append_array(cert_sig);
            payload.append_array(client_pairing_secret);

            PackedByteArray hash = _sha256(payload);
            PackedByteArray hash_enc = _encrypt_aes_ecb(hash, pair_aes_key);

            String url = base_url + "?" + common_params + "&serverchallengeresp=" + _bytes_to_hex(hash_enc);
            http_requester->request(url, "GET", PackedByteArray(), Dictionary(), ssl_opts, callable_mp(this, &NightfallComputerManager::_on_pair_request_completed).bind(3));
            break;
        }
        case PAIR_STAGE_4_CLIENT_SECRET: {
            PackedByteArray signature = _sign_data(client_pairing_secret);
            PackedByteArray payload = client_pairing_secret;
            payload.append_array(signature);

            String url = base_url + "?" + common_params + "&clientpairingsecret=" + _bytes_to_hex(payload);
            http_requester->request(url, "GET", PackedByteArray(), Dictionary(), ssl_opts, callable_mp(this, &NightfallComputerManager::_on_pair_request_completed).bind(4));
            break;
        }
        case PAIR_STAGE_5_HTTPS_CHALLENGE: {
            String https_url = "https://" + pair_ip + ":" + String::num_int64(pair_https_port) + "/pair";
            String url = https_url + "?" + common_params + "&phrase=pairchallenge";

            Dictionary stage5_ssl_opts = _get_ssl_options();
            http_requester->request(url, "GET", PackedByteArray(), Dictionary(), stage5_ssl_opts, callable_mp(this, &NightfallComputerManager::_on_pair_request_completed).bind(5));
            break;
        }
        default:
            break;
    }
}

void NightfallComputerManager::_on_pair_request_completed(int code, PackedByteArray body, Dictionary headers, String error, int step) {
    is_requesting = false;
    bool failed = false;
    String fail_msg;

    if (code <= 0 || code >= 400) {
        failed = true;
        fail_msg = "Network Error (" + String::num_int64(code) + "): " + error;
    }

    String xml;
    bool is_paired = false;
    if (!failed) {
        xml = body.get_string_from_utf8();
        if (step == 0) {
            is_paired = _extract_xml_value(xml, "PairStatus") == "1";
        } else {
            is_paired = _extract_xml_value(xml, "paired") == "1";
        }

        if (!is_paired && step != 1 && step != 0) {
            failed = true;
            fail_msg = _extract_xml_value(xml, "status_message");
            if (fail_msg.is_empty())
                fail_msg = "Pairing failed at step " + String::num_int64(step);
        }
    }

    if (failed) {
        String uuid = _get_uuid();
        String url = "http://" + pair_ip + ":" + String::num_int64(pair_port) + "/unpair?uniqueid=" + unique_id + "&uuid=" + uuid;
        http_requester->request(url, "GET", PackedByteArray(), Dictionary(), Dictionary(), Callable());

        pair_state = PAIR_ERROR;
        emit_signal("pair_completed", false, fail_msg);
        return;
    }

    switch (step) {
        case 0: {
            server_unique_id = _extract_xml_value(xml, "uniqueid");
            String https_port_str = _extract_xml_value(xml, "HttpsPort");
            if (!https_port_str.is_empty()) {
                pair_https_port = https_port_str.to_int();
                cached_https_ports[pair_ip] = pair_https_port;
            }

            bool known_and_paired = false;
            if (!server_unique_id.is_empty()) {
                Array hosts = config_manager->get_hosts();
                for (int i = 0; i < hosts.size(); i++) {
                    Dictionary h = hosts[i];
                    if (h.get("server_unique_id", "") == server_unique_id) {
                        known_and_paired = true;
                        if (h.get("localaddress", "") != pair_ip) {
                            Dictionary update_data;
                            update_data["localaddress"] = pair_ip;
                            config_manager->update_host(h["id"], update_data);
                        }
                        break;
                    }
                }
            }

            if (known_and_paired) {
                pair_state = PAIR_FINISHED;
                emit_signal("pair_completed", true, "Already paired");
                return;
            }

            pair_state = PAIR_STAGE_1_GET_CERT;
            _step_pair();
            break;
        }
        case 1: {
            String plaincert = _extract_xml_value(xml, "plaincert");
            if (plaincert.is_empty()) {
                String status_msg = _extract_xml_value(xml, "status_message");
                pair_state = PAIR_ERROR;
                emit_signal("pair_completed", false, status_msg.is_empty() ? "No server certificate received." : status_msg);
                return;
            }

            server_cert_pem = _hex_to_bytes(plaincert).get_string_from_ascii();

            pair_state = PAIR_STAGE_2_CLIENT_CHALLENGE;
            _step_pair();
            break;
        }
        case 2: {
            String resp_hex = _extract_xml_value(xml, "challengeresponse");
            if (resp_hex.is_empty()) {
                emit_signal("pair_completed", false, "Empty challenge response");
                return;
            }

            PackedByteArray resp_enc = _hex_to_bytes(resp_hex);
            PackedByteArray resp_dec = _decrypt_aes_ecb(resp_enc, pair_aes_key);

            if (resp_dec.size() < 48) {
                emit_signal("pair_completed", false, "Invalid server response size");
                return;
            }

            server_challenge = resp_dec.slice(32, 48);

            pair_state = PAIR_STAGE_3_SERVER_RESPONSE;
            _step_pair();
            break;
        }
        case 3: {
            String pairing_secret_hex = _extract_xml_value(xml, "pairingsecret");
            PackedByteArray pairing_secret = _hex_to_bytes(pairing_secret_hex);
            if (pairing_secret.size() >= 16) {
                server_secret = pairing_secret.slice(0, 16);
            }

            pair_state = PAIR_STAGE_4_CLIENT_SECRET;
            _step_pair();
            break;
        }
        case 4: {
            pair_state = PAIR_STAGE_5_HTTPS_CHALLENGE;
            _step_pair();
            break;
        }
        case 5: {
            Dictionary host_data;
            host_data["hostname"] = pair_ip;
            host_data["localaddress"] = pair_ip;
            host_data["uuid"] = current_uuid;
            host_data["srvcert"] = server_cert_pem;
            host_data["https_port"] = pair_https_port;
            host_data["server_unique_id"] = server_unique_id;
            config_manager->add_host(host_data);

            pair_state = PAIR_FINISHED;
            emit_signal("pair_completed", true, "Pairing successful");
            break;
        }
    }
}

void NightfallComputerManager::cancel_pair() {
    _ensure_config(config_manager, owns_config_manager);
    if (pair_state != PAIR_IDLE && pair_state != PAIR_FINISHED && pair_state != PAIR_ERROR) {
        String uuid = _get_uuid();
        String url = "http://" + pair_ip + ":" + String::num_int64(pair_port) + "/unpair?uniqueid=" + unique_id + "&uuid=" + uuid;
        http_requester->request(url, "GET", PackedByteArray(), Dictionary(), Dictionary(), Callable());
    }
    _reset_pairing();
}

void NightfallComputerManager::unpair(int host_id) {
    _ensure_config(config_manager, owns_config_manager);
    if (config_manager) {
        config_manager->remove_host(host_id);
    }
}

void NightfallComputerManager::_reset_pairing() {
    pair_state = PAIR_IDLE;
    is_requesting = false;
    server_unique_id = "";
    server_cert_pem = "";
    server_secret.clear();
    server_challenge.clear();
    client_secret_random.clear();
    client_pairing_secret.clear();
}

void NightfallComputerManager::connect_to_computer(String ip, int port, Callable callback) {
    _ensure_config(config_manager, owns_config_manager);
    String url = "http://" + ip + ":" + String::num_int64(port) + "/serverinfo?uniqueid=" + _get_unique_id() + "&uuid=" + _get_uuid();
    http_requester->request(url, "GET", PackedByteArray(), Dictionary(), Dictionary(),
            callable_mp(this, &NightfallComputerManager::_on_server_info_completed).bind(Variant(callback), Variant(ip)));
}

void NightfallComputerManager::_on_server_info_completed(int code, PackedByteArray body, Dictionary headers, String error, Callable callback, String ip) {
    Dictionary result;
    result["status"] = (code == 200) ? "online" : "offline";
    if (code == 200) {
        String xml = body.get_string_from_utf8();
        result["hostname"] = _extract_xml_value(xml, "hostname");
        result["uniqueid"] = _extract_xml_value(xml, "uniqueid");
        result["paired"] = _extract_xml_value(xml, "PairStatus") == "1";
        result["ip"] = ip;

        String port_str = _extract_xml_value(xml, "HttpsPort");
        int port = port_str.is_empty() ? 47984 : port_str.to_int();
        result["https_port"] = port;
        cached_https_ports[ip] = port;
    }
    if (callback.is_valid())
        callback.call(result);
}

void NightfallComputerManager::get_app_list(int host_id, Callable callback) {
    _ensure_config(config_manager, owns_config_manager);
    Array hosts = config_manager->get_hosts();
    String ip;
    int port = 47984;
    for (int i = 0; i < hosts.size(); i++) {
        Dictionary host = hosts[i];
        if ((int64_t)host["id"] == host_id) {
            ip = host.get("localaddress", "");
            port = host.get("https_port", 47984);
        }
    }
    if (ip.is_empty())
        return;

    String url = "https://" + ip + ":" + String::num_int64(port) + "/applist?uniqueid=" + unique_id + "&uuid=" + _get_uuid();
    http_requester->request(url, "GET", PackedByteArray(), Dictionary(), _get_ssl_options(),
            callable_mp(this, &NightfallComputerManager::_on_app_list_completed).bind(Variant(host_id), Variant(callback)));
}

void NightfallComputerManager::_on_app_list_completed(int code, PackedByteArray body, Dictionary headers, String error, int host_id, Callable callback) {
    if (code == 200) {
        Array existing_apps = config_manager->get_apps(host_id);
        Array existing_ids;
        for (int i = 0; i < existing_apps.size(); i++) {
            Dictionary app = existing_apps[i];
            existing_ids.append(app.get("id", 0));
        }

        String xml = body.get_string_from_utf8();
        int pos = 0;
        while (true) {
            int start = xml.find("<App>", pos);
            if (start == -1) break;
            int end = xml.find("</App>", start);
            if (end == -1) break;

            String app_xml = xml.substr(start, end - start + 6);
            Dictionary app_data;
            app_data["name"] = _extract_xml_value(app_xml, "AppTitle");
            int app_id = _extract_xml_value(app_xml, "ID").to_int();
            app_data["id"] = app_id;

            if (!existing_ids.has(app_id)) {
                config_manager->add_app(host_id, app_data);
                existing_ids.append(app_id);
            }

            pos = end + 6;
        }
    }
    if (callback.is_valid())
        callback.call(code == 200);
}

void NightfallComputerManager::get_app_cover(int host_id, int app_id, Callable callback) {
    _ensure_config(config_manager, owns_config_manager);
    Array hosts = config_manager->get_hosts();
    String ip;
    int port = 47984;
    for (int i = 0; i < hosts.size(); i++) {
        Dictionary host = hosts[i];
        if ((int64_t)host["id"] == host_id) {
            ip = host.get("localaddress", "");
            port = host.get("https_port", 47984);
        }
    }
    if (ip.is_empty()) return;

    String url = "https://" + ip + ":" + String::num_int64(port) + "/appasset?uniqueid=" + unique_id + "&uuid=" + _get_uuid() + "&appid=" + String::num_int64(app_id);
    http_requester->request(url, "GET", PackedByteArray(), Dictionary(), _get_ssl_options(),
            callable_mp(this, &NightfallComputerManager::_on_app_cover_completed).bind(Variant(callback)));
}

void NightfallComputerManager::_on_app_cover_completed(int code, PackedByteArray body, Dictionary headers, String error, Callable callback) {
    if (code == 200 && callback.is_valid()) {
        Ref<Image> img;
        img.instantiate();
        if (img->load_png_from_buffer(body) == OK || img->load_jpg_from_buffer(body) == OK) {
            Ref<ImageTexture> tex = ImageTexture::create_from_image(img);
            callback.call(tex);
            return;
        }
    }
    if (callback.is_valid())
        callback.call(Variant());
}

void NightfallComputerManager::establish_stream(int host_id, int app_id, Dictionary options, Callable callback) {
    _ensure_config(config_manager, owns_config_manager);
    Array hosts = config_manager->get_hosts();
    String ip;
    int port = 47984;
    for (int i = 0; i < hosts.size(); i++) {
        Dictionary host = hosts[i];
        if ((int64_t)host["id"] == host_id) {
            ip = host.get("localaddress", "");
            port = host.get("https_port", 47984);
            break;
        }
    }

    if (ip.is_empty()) {
        if (callback.is_valid()) {
            Dictionary err;
            err["status"] = "error";
            err["message"] = "Host not found";
            callback.call(err);
        }
        return;
    }

    Dictionary ctx;
    ctx["ip"] = ip;
    ctx["port"] = port;
    ctx["app_id"] = app_id;
    ctx["options"] = options;
    ctx["callback"] = callback;

    PackedByteArray rikey_bytes = _generate_random_bytes(16);
    ctx["rikey"] = _bytes_to_hex(rikey_bytes);
    ctx["rikey_raw"] = rikey_bytes;

    PackedByteArray rikeyid_bytes = _generate_random_bytes(4);
    int64_t rikeyid = rikeyid_bytes.decode_u32(0);
    ctx["rikeyid"] = rikeyid;

    String url = "https://" + ip + ":" + String::num_int64(port) + "/serverinfo?uniqueid=" + unique_id + "&uuid=" + _get_uuid();
    http_requester->request(url, "GET", PackedByteArray(), Dictionary(), _get_ssl_options(),
            callable_mp(this, &NightfallComputerManager::_on_launch_serverinfo_completed).bind(ctx));
}

void NightfallComputerManager::_on_launch_serverinfo_completed(int code, PackedByteArray body, Dictionary headers, String error, Dictionary ctx) {
    if (code != 200) {
        Callable cb = ctx["callback"];
        if (cb.is_valid()) {
            Dictionary res;
            res["status"] = "error";
            res["message"] = "Server check failed: " + error;
            cb.call(res);
        }
        return;
    }

    String xml = body.get_string_from_utf8();
    String current_game_str = _extract_xml_value(xml, "currentgame");
    int current_game = current_game_str.to_int();

    String scms_str = _extract_xml_value(xml, "ServerCodecModeSupport");
    if (!scms_str.is_empty()) {
        if (!ctx.has("options"))
            ctx["options"] = Dictionary();
        Dictionary opts = ctx["options"];
        opts["server_codec_mode_support"] = scms_str.to_int();

        String app_version = _extract_xml_value(xml, "appversion");
        String gfe_version = _extract_xml_value(xml, "GfeVersion");
        opts["app_version"] = app_version;
        opts["gfe_version"] = gfe_version;

        ctx["options"] = opts;
    }

    String app_version = _extract_xml_value(xml, "appversion");
    if (!app_version.is_empty()) {
        ctx["app_version"] = app_version;
    }

    String gfe_version = _extract_xml_value(xml, "GfeVersion");
    if (!gfe_version.is_empty()) {
        ctx["gfe_version"] = gfe_version;
    }

    String command = (current_game != 0) ? "resume" : "launch";

    _perform_launch_request(ctx, command);
}

void NightfallComputerManager::_perform_launch_request(Dictionary ctx, String command) {
    String ip = ctx["ip"];
    int port = ctx["port"];
    int app_id = ctx["app_id"];
    Dictionary options = ctx["options"];

    String rikey = ctx["rikey"];
    int64_t rikeyid = ctx["rikeyid"];

    options["rikey"] = rikey;
    options["rikeyid"] = rikeyid;
    options["ip"] = ip;

    String url = "https://" + ip + ":" + String::num_int64(port) + "/" + command + "?uniqueid=" + unique_id + "&uuid=" + _get_uuid();
    url += "&appid=" + String::num_int64(app_id);
    url += "&rikey=" + rikey;
    url += "&rikeyid=" + String::num_int64(rikeyid);

    if (options.has("limelight_query_parameters")) {
        String frag = options["limelight_query_parameters"];
        if (!frag.is_empty()) {
            url += frag;
        }
    }

    if (options.has("surroundAudioInfo") && !options.has("surround_audio_info")) {
        options["surround_audio_info"] = options["surroundAudioInfo"];
    }

    if (options.has("width") && options.has("height") && options.has("fps")) {
        String mode = String::num_int64(options["width"]) + "x" + String::num_int64(options["height"]) + "x" + String::num_int64(options["fps"]);
        url += "&mode=" + mode;
    }

    if (options.has("sops")) url += "&sops=" + String::num_int64(options["sops"]);
    if (options.has("surround_audio_info")) url += "&surroundAudioInfo=" + String::num_int64(options["surround_audio_info"]);
    if (options.has("surround_params")) url += "&surroundParams=" + String(options["surround_params"]);
    if (options.has("remote_controllers_bitmap")) url += "&remoteControllersBitmap=" + String::num_int64(options["remote_controllers_bitmap"]);
    if (options.has("gcmap")) url += "&gcmap=" + String::num_int64(options["gcmap"]);
    if (options.has("additional_states")) url += "&additionalStates=" + String::num_int64(options["additional_states"]);
    if (options.has("corever")) url += "&corever=" + String::num_int64(options["corever"]);
    if (options.has("continuous_audio")) url += "&continuousAudio=" + String::num_int64(options["continuous_audio"]);

    int hdr_mode = options.get("hdr_mode", 0);
    if (options.has("hdr_mode")) url += "&hdrMode=" + String::num_int64(hdr_mode);

    int local_audio = options.get("local_audio_play_mode", 1);
    url += "&localAudioPlayMode=" + String::num_int64(local_audio);

    if (hdr_mode == 1) {
        url += "&clientHdrCapVersion=" + String::num_int64(options.get("client_hdr_cap_version", 0));
        url += "&clientHdrCapSupportedFlagsInUint32=" + String::num_int64(options.get("client_hdr_cap_supported_flags", 0));
        url += "&clientHdrCapMetaDataId=" + String(options.get("client_hdr_cap_meta_data_id", "NV_STATIC_METADATA_TYPE_1"));
        url += "&clientHdrCapDisplayData=" + String(options.get("client_hdr_cap_display_data", "0x0x0x0x0x0x0x0x0x0x0"));
    }

    Array keys = options.keys();
    for (int i = 0; i < keys.size(); i++) {
        String key = keys[i];
        if (key == "width" || key == "height" || key == "fps" ||
                key == "sops" || key == "surround_audio_info" || key == "surround_params" ||
                key == "remote_controllers_bitmap" || key == "gcmap" || key == "additional_states" ||
                key == "corever" || key == "continuous_audio" ||
                key == "hdr_mode" || key == "local_audio_play_mode" ||
                key == "client_hdr_cap_version" || key == "client_hdr_cap_supported_flags" ||
                key == "client_hdr_cap_meta_data_id" || key == "client_hdr_cap_display_data" ||
                key == "limelight_query_parameters") {
            continue;
        }
        url += "&" + key + "=" + String(options[key]);
    }

    http_requester->request(url, "GET", PackedByteArray(), Dictionary(), _get_ssl_options(),
            callable_mp(this, &NightfallComputerManager::_on_launch_request_completed).bind(ctx));
}

void NightfallComputerManager::_on_launch_request_completed(int code, PackedByteArray body, Dictionary headers, String error, Dictionary ctx) {
    Callable cb = ctx["callback"];
    if (!cb.is_valid()) return;

    Dictionary response = ctx.duplicate();
    response.erase("callback");

    if (code == 200) {
        String xml = body.get_string_from_utf8();
        String session_url = _extract_xml_value(xml, "sessionUrl0");

        if (!session_url.is_empty()) {
            response["status"] = "success";
            response["session_url"] = session_url;

            Dictionary opts = ctx.get("options", Dictionary());
            opts["session_url"] = session_url;

            Array keys = opts.keys();
            for (int i = 0; i < keys.size(); i++) {
                response[keys[i]] = opts[keys[i]];
            }
        } else {
            response["status"] = "error";
            response["message"] = "Session URL not found in response. Game may be stuck.";
            response["xml_debug"] = xml;
        }
    } else {
        response["status"] = "error";
        response["message"] = "Launch/Resume failed (" + String::num_int64(code) + "): " + error;
    }

    cb.call(response);
}

void NightfallComputerManager::stop_stream(int host_id, Callable callback) {
    _ensure_config(config_manager, owns_config_manager);
    Array hosts = config_manager->get_hosts();
    String ip;
    int port = 47984;
    for (int i = 0; i < hosts.size(); i++) {
        Dictionary host = hosts[i];
        if ((int64_t)host["id"] == host_id) {
            ip = host.get("localaddress", "");
            port = host.get("https_port", 47984);
        }
    }

    String url = "https://" + ip + ":" + String::num_int64(port) + "/cancel?uniqueid=" + unique_id + "&uuid=" + _get_uuid();
    http_requester->request(url, "GET", PackedByteArray(), Dictionary(), _get_ssl_options(),
            callable_mp(this, &NightfallComputerManager::_on_simple_request_completed).bind(Variant(callback)));
}

void NightfallComputerManager::_on_simple_request_completed(int code, PackedByteArray body, Dictionary headers, String error, Callable callback) {
    if (callback.is_valid())
        callback.call(code == 200 ? body.get_string_from_utf8() : "");
}

PackedByteArray NightfallComputerManager::_generate_random_bytes(int size) {
    Ref<Crypto> c;
    c.instantiate();
    return c->generate_random_bytes(size);
}

PackedByteArray NightfallComputerManager::_calculate_aes_key(const PackedByteArray &salt, const String &pin) {
    PackedByteArray combined = salt;
    combined.append_array(pin.to_ascii_buffer());
    return _sha256(combined).slice(0, 16);
}

PackedByteArray NightfallComputerManager::_encrypt_aes_ecb(const PackedByteArray &data, const PackedByteArray &key) {
    Ref<AESContext> ctx;
    ctx.instantiate();
    ctx->start(AESContext::MODE_ECB_ENCRYPT, key);
    PackedByteArray out = ctx->update(data);
    ctx->finish();
    return out;
}

PackedByteArray NightfallComputerManager::_decrypt_aes_ecb(const PackedByteArray &data, const PackedByteArray &key) {
    Ref<AESContext> ctx;
    ctx.instantiate();
    ctx->start(AESContext::MODE_ECB_DECRYPT, key);
    PackedByteArray out = ctx->update(data);
    ctx->finish();
    return out;
}

PackedByteArray NightfallComputerManager::_sha256(const PackedByteArray &data) {
    Ref<HashingContext> ctx;
    ctx.instantiate();
    ctx->start(HashingContext::HASH_SHA256);
    ctx->update(data);
    return ctx->finish();
}

PackedByteArray NightfallComputerManager::_sign_data(const PackedByteArray &data) {
    Dictionary keys = config_manager->get_client_keys();
    Ref<Crypto> c;
    c.instantiate();
    Ref<CryptoKey> key;
    key.instantiate();
    if (key->load_from_string(keys["key"]) != OK)
        return PackedByteArray();

    PackedByteArray hash = _sha256(data);
    return c->sign(HashingContext::HASH_SHA256, hash, key);
}

PackedByteArray NightfallComputerManager::_extract_signature_from_der(const PackedByteArray &der) {
    int len = der.size();
    const uint8_t *data = der.ptr();
    int pos = 0;

    if (pos >= len || data[pos++] != 0x30)
        return PackedByteArray();

    if (pos >= len) return PackedByteArray();
    if (data[pos] & 0x80) {
        int len_bytes = data[pos] & 0x7F;
        pos += 1 + len_bytes;
    } else {
        pos++;
    }

    int child_count = 0;
    while (pos < len) {
        uint8_t tag = data[pos];

        if (child_count == 2) {
            if (tag == 0x03) {
                pos++;
                int val_len = 0;
                if (data[pos] & 0x80) {
                    int len_bytes = data[pos] & 0x7F;
                    pos++;
                    for (int i = 0; i < len_bytes; i++) {
                        val_len = (val_len << 8) | data[pos++];
                    }
                } else {
                    val_len = data[pos++];
                }

                if (val_len > 1) {
                    return der.slice(pos + 1, pos + val_len);
                }
                return PackedByteArray();
            }
            return PackedByteArray();
        }

        pos++;
        int val_len = 0;
        if (pos < len) {
            if (data[pos] & 0x80) {
                int len_bytes = data[pos] & 0x7F;
                pos++;
                for (int i = 0; i < len_bytes; i++) {
                    if (pos >= len) return PackedByteArray();
                    val_len = (val_len << 8) | data[pos++];
                }
            } else {
                val_len = data[pos++];
            }
        }
        pos += val_len;
        child_count++;
    }

    return PackedByteArray();
}

String NightfallComputerManager::_bytes_to_hex(const PackedByteArray &bytes) {
    return bytes.hex_encode().to_lower();
}

PackedByteArray NightfallComputerManager::_hex_to_bytes(const String &hex) {
    return hex.hex_decode();
}

String NightfallComputerManager::_extract_xml_value(const String &xml, const String &tag) {
    String start_tag = "<" + tag + ">";
    String end_tag = "</" + tag + ">";
    int start = xml.find(start_tag);
    if (start == -1) return "";
    start += start_tag.length();
    int end = xml.find(end_tag, start);
    if (end == -1) return "";
    return xml.substr(start, end - start);
}

String NightfallComputerManager::_get_unique_id() {
    if (config_manager->get_custom_data(NightfallConfigManager::TARGET_GLOBAL, 0, 0, "uniqueid", "").stringify().is_empty()) {
        String uid = _bytes_to_hex(_generate_random_bytes(8)).to_upper();
        config_manager->set_custom_data(NightfallConfigManager::TARGET_GLOBAL, 0, 0, "uniqueid", uid);
    }
    return config_manager->get_custom_data(NightfallConfigManager::TARGET_GLOBAL, 0, 0, "uniqueid", "").stringify();
}

String NightfallComputerManager::_get_uuid() {
    return _bytes_to_hex(_generate_random_bytes(16));
}

Dictionary NightfallComputerManager::_get_ssl_options() {
    Dictionary keys = config_manager->get_client_keys();
    Dictionary opts;

    opts["client_cert"] = keys["certificate"];
    opts["client_key"] = keys["key"];
    opts["verify_peer"] = false;

    return opts;
}

void NightfallComputerManager::_bind_methods() {
    ClassDB::bind_method(D_METHOD("set_config_manager", "cm"), &NightfallComputerManager::set_config_manager);
    ClassDB::bind_method(D_METHOD("set_http_requester", "req"), &NightfallComputerManager::set_http_requester);

    ClassDB::bind_method(D_METHOD("start_pair", "ip", "port"), &NightfallComputerManager::start_pair, DEFVAL(47989));
    ClassDB::bind_method(D_METHOD("cancel_pair"), &NightfallComputerManager::cancel_pair);
    ClassDB::bind_method(D_METHOD("unpair", "host_id"), &NightfallComputerManager::unpair);

    ClassDB::bind_method(D_METHOD("connect_to_computer", "ip", "port", "callback"), &NightfallComputerManager::connect_to_computer, DEFVAL(47989), DEFVAL(Callable()));
    ClassDB::bind_method(D_METHOD("get_app_list", "host_id", "callback"), &NightfallComputerManager::get_app_list, DEFVAL(Callable()));
    ClassDB::bind_method(D_METHOD("get_app_cover", "host_id", "app_id", "callback"), &NightfallComputerManager::get_app_cover);
    ClassDB::bind_method(D_METHOD("establish_stream", "host_id", "app_id", "options", "callback"), &NightfallComputerManager::establish_stream);
    ClassDB::bind_method(D_METHOD("stop_stream", "host_id", "callback"), &NightfallComputerManager::stop_stream);

    ADD_SIGNAL(MethodInfo("pair_completed", PropertyInfo(Variant::BOOL, "success"), PropertyInfo(Variant::STRING, "message")));
}
