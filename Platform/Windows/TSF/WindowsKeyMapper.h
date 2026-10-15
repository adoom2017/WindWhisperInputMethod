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
    bool TestKeyUp(WPARAM virtual_key);
    bool KeyUp(WPARAM virtual_key);
    void Reset();

private:
    bool pending_ = false;
};

// Mirrors the engine's punctuation options ("ascii_punct" and "punct_*").
struct FyPunctuationOptions {
    bool chinese = true;
    bool bracket = true;
    bool angle = true;
    bool backslash = true;
    bool caret = true;
    bool underscore = true;
    bool yuan = false;
};

// True when Chinese punctuation mode converts this ASCII character.
bool FyConvertsPunctuation(const FyPunctuationOptions &options, uint32_t character);

// Returns the ASCII character a printable key produces on a US layout, or 0.
uint32_t FyPrintableCharacter(WPARAM virtual_key, bool shift);

// While idle, a printable key is captured only when the engine converts it:
// full-width mode converts every printable key, Chinese punctuation mode
// converts the enabled writing punctuation. Everything else stays with the host.
bool FyMapVirtualKey(WPARAM virtual_key, bool shift, bool caps_lock,
                     bool control, bool alt, bool composing, bool full_width,
                     const FyPunctuationOptions &punctuation, FyMappedKey *mapped,
                     bool system_shortcut = false);
#endif
