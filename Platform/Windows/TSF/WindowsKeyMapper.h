#pragma once

#ifdef _WIN32
#include <windows.h>

#include <cstdint>

struct FyMappedKey {
    uint32_t key = 0;
    uint32_t modifiers = 0;
};

class FyShiftTapState {
public:
    static bool IsShiftKey(WPARAM virtual_key);
    bool TestKeyDown(WPARAM virtual_key);
    void KeyDown(WPARAM virtual_key, bool repeat, bool other_modifier_down);
    bool TestKeyUp(WPARAM virtual_key) const;
    bool KeyUp(WPARAM virtual_key);
    void Reset();

private:
    bool pending_ = false;
};

bool FyMapVirtualKey(WPARAM virtual_key, bool shift, bool caps_lock,
                     bool control, bool alt, bool composing,
                     FyMappedKey *mapped);
#endif
