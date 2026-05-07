#pragma once

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/string.hpp>
#include <cstdint>

namespace godot {

class InputBridge : public RefCounted {
    GDCLASS(InputBridge, RefCounted);

public:
    static constexpr int MBTN_PRESS = 7;
    static constexpr int MBTN_RELEASE = 8;
    static constexpr int MBTN_LEFT = 1;
    static constexpr int MBTN_MIDDLE = 2;
    static constexpr int MBTN_RIGHT = 3;

    static constexpr int KA_DOWN = 3;
    static constexpr int KA_UP = 4;
    static constexpr int MOD_SHIFT = 0x01;
    static constexpr int MOD_CTRL = 0x02;
    static constexpr int MOD_ALT = 0x04;
    static constexpr int MOD_META = 0x08;

    static constexpr int FLAG_UP = 0x0001;
    static constexpr int FLAG_DOWN = 0x0002;
    static constexpr int FLAG_LEFT = 0x0004;
    static constexpr int FLAG_RIGHT = 0x0008;
    static constexpr int FLAG_PLAY = 0x0010;
    static constexpr int FLAG_BACK = 0x0020;
    static constexpr int FLAG_LS_CLK = 0x0040;
    static constexpr int FLAG_RS_CLK = 0x0080;
    static constexpr int FLAG_LB = 0x0100;
    static constexpr int FLAG_RB = 0x0200;
    static constexpr int FLAG_SPECIAL = 0x0400;
    static constexpr int FLAG_A = 0x1000;
    static constexpr int FLAG_B = 0x2000;
    static constexpr int FLAG_X = 0x4000;
    static constexpr int FLAG_Y = 0x8000;

    static constexpr int FLAG_PADDLE1 = 0x010000;
    static constexpr int FLAG_PADDLE2 = 0x020000;
    static constexpr int FLAG_PADDLE3 = 0x040000;
    static constexpr int FLAG_PADDLE4 = 0x080000;
    static constexpr int FLAG_TOUCHPAD = 0x100000;
    static constexpr int FLAG_MISC = 0x200000;

    static constexpr int CTYPE_XBOX = 1;
    static constexpr int CTYPE_PS = 2;
    static constexpr int CTYPE_NINTENDO = 3;

    static constexpr int CCAP_ANALOG_TRIGGERS = 0x01;
    static constexpr int CCAP_RUMBLE = 0x02;
    static constexpr int CCAP_TRIGGER_RUMBLE = 0x04;
    static constexpr int CCAP_TOUCHPAD = 0x08;
    static constexpr int CCAP_ACCEL = 0x10;
    static constexpr int CCAP_GYRO = 0x20;
    static constexpr int CCAP_BATTERY_STATE = 0x40;
    static constexpr int CCAP_RGB_LED = 0x80;

    static constexpr int MOTION_ACCEL = 1;
    static constexpr int MOTION_GYRO = 2;

    static constexpr int TOUCH_HOVER = 0;
    static constexpr int TOUCH_DOWN = 1;
    static constexpr int TOUCH_UP = 2;
    static constexpr int TOUCH_MOVE = 3;
    static constexpr int TOUCH_CANCEL = 4;

    static constexpr int BATTERY_UNKNOWN = 0;
    static constexpr int BATTERY_DISCHARGING = 2;
    static constexpr int BATTERY_CHARGING = 3;
    static constexpr int BATTERY_FULL = 5;

    InputBridge();
    ~InputBridge();

    int send_mouse_move(int delta_x, int delta_y);
    int send_mouse_position(int x, int y, int ref_w, int ref_h);
    int send_mouse_button_pressed(int button);
    int send_mouse_button_released(int button);
    int send_keyboard_event(int godot_key, int key_action, int modifiers);
    int send_utf8_text(const String &text);
    int send_controller_event(int button_flags, int left_trigger, int right_trigger, int left_stick_x, int left_stick_y, int right_stick_x, int right_stick_y);
    int send_multi_controller_event(int controller_number, int active_gamepad_mask, int button_flags, int left_trigger, int right_trigger, int left_stick_x, int left_stick_y, int right_stick_x, int right_stick_y);
    int send_controller_arrival(int controller_number, int active_gamepad_mask, int type, int supported_button_flags, int capabilities);
    int send_controller_motion(int controller_number, int motion_type, float x, float y, float z);
    int send_controller_battery(int controller_number, int battery_state, int battery_percentage);
    int send_scroll(int clicks);
    int send_high_res_scroll(int amount);
    int get_host_feature_flags();

    static int godot_key_to_vk(int godot_key);

protected:
    static void _bind_methods();
};

} // namespace godot
