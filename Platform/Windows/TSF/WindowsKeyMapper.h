#pragma once

#ifdef _WIN32
#include <windows.h>

#include <cstdint>

struct FyMappedKey {
    uint32_t key = 0;
    uint32_t modifiers = 0;
};

bool FyMapVirtualKey(WPARAM virtual_key, bool shift, bool caps_lock,
                     bool control, bool alt, bool composing,
                     FyMappedKey *mapped);
#endif
