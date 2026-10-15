#include "WindowsKeyMapper.h"

#ifdef _WIN32
namespace {
constexpr uint32_t kKeyPageUp = 0xFF55;
constexpr uint32_t kKeyPageDown = 0xFF56;
constexpr uint32_t kModifierShift = 1u << 0;
constexpr uint32_t kModifierCapsLock = 1u << 1;
constexpr uint32_t kModifierControl = 1u << 2;
constexpr uint32_t kModifierAlt = 1u << 3;
}

bool FyShiftTapState::IsShiftKey(WPARAM virtual_key) {
    return virtual_key == VK_SHIFT || virtual_key == VK_LSHIFT ||
           virtual_key == VK_RSHIFT;
}

bool FyShiftTapState::TestKeyDown(WPARAM virtual_key) {
    if (!IsShiftKey(virtual_key)) {
        pending_ = false;
    }
    return IsShiftKey(virtual_key);
}

void FyShiftTapState::KeyDown(
    WPARAM virtual_key, bool repeat, bool other_modifier_down) {
    if (!IsShiftKey(virtual_key) || other_modifier_down) {
        pending_ = false;
        return;
    }
    if (IsShiftKey(virtual_key) && !repeat) {
        pending_ = !other_modifier_down;
    }
}

bool FyShiftTapState::TestKeyUp(WPARAM virtual_key) {
    if (!IsShiftKey(virtual_key)) pending_ = false;
    return IsShiftKey(virtual_key) && pending_;
}

bool FyShiftTapState::KeyUp(WPARAM virtual_key) {
    if (!IsShiftKey(virtual_key)) {
        pending_ = false;
        return false;
    }
    const bool toggle = pending_;
    pending_ = false;
    return toggle;
}

void FyShiftTapState::Reset() {
    pending_ = false;
}

// Keys the engine maps to Chinese punctuation (see punctuation_text in
// fy_engine.cpp); "." and ":" may stay half-width after a digit, which the
// engine decides once it has the key.
bool FyConvertsPunctuation(const FyPunctuationOptions &options, uint32_t character) {
    if (!options.chinese) return false;
    switch (character) {
    case ',': case '.': case '?': case '!': case ':': case ';':
    case '(': case ')': case '"': case '\'':
        return true;
    case '[': case ']': return options.bracket;
    case '<': case '>': return options.angle;
    case '\\': return options.backslash;
    case '^': return options.caret;
    case '_': return options.underscore;
    case '$': return options.yuan;
    default:
        return false;
    }
}

uint32_t FyPrintableCharacter(WPARAM virtual_key, bool shift) {
    if (virtual_key >= '0' && virtual_key <= '9') {
        static constexpr char shifted[] = ")!@#$%^&*(";
        return shift ? shifted[virtual_key - '0']
                     : static_cast<uint32_t>(virtual_key);
    }
    switch (virtual_key) {
    case VK_SPACE: return 0x20;
    case VK_OEM_MINUS: return shift ? '_' : '-';
    case VK_OEM_PLUS: return shift ? '+' : '=';
    case VK_OEM_1: return shift ? ':' : ';';
    case VK_OEM_COMMA: return shift ? '<' : ',';
    case VK_OEM_PERIOD: return shift ? '>' : '.';
    case VK_OEM_2: return shift ? '?' : '/';
    case VK_OEM_3: return shift ? '~' : '`';
    case VK_OEM_4: return shift ? '{' : '[';
    case VK_OEM_5: return shift ? '|' : '\\';
    case VK_OEM_6: return shift ? '}' : ']';
    case VK_OEM_7: return shift ? '"' : '\'';
    default: return 0;
    }
}

bool FyMapVirtualKey(WPARAM virtual_key, bool shift, bool caps_lock,
                     bool control, bool alt, bool composing, bool full_width,
                     const FyPunctuationOptions &punctuation, FyMappedKey *mapped,
                     bool system_shortcut) {
    if (!mapped) {
        return false;
    }
    *mapped = {};
    mapped->modifiers = (shift ? kModifierShift : 0) |
                        (caps_lock ? kModifierCapsLock : 0) |
                        (control ? kModifierControl : 0) |
                        (alt ? kModifierAlt : 0);

    if (control || alt || system_shortcut) {
        return false;
    }
    if (virtual_key >= 'A' && virtual_key <= 'Z') {
        if (shift) {
            return false;
        }
        mapped->key = static_cast<uint32_t>(virtual_key - 'A' + 'a');
        return true;
    }
    const uint32_t printable = FyPrintableCharacter(virtual_key, shift);
    // Outside an active composition, only capture printable keys that need
    // conversion. Control/navigation keys must remain available to the host
    // application (notably Backspace for deleting committed text).
    if (!composing &&
        !(printable &&
          (full_width || FyConvertsPunctuation(punctuation, printable)))) {
        return false;
    }
    if (printable) {
        mapped->key = printable;
        return true;
    }
    switch (virtual_key) {
    case VK_BACK:
        mapped->key = 0x08;
        return true;
    case VK_ESCAPE:
        mapped->key = 0x1B;
        return true;
    case VK_RETURN:
        mapped->key = 0x0D;
        return true;
    case VK_PRIOR:
        mapped->key = kKeyPageUp;
        return true;
    case VK_NEXT:
        mapped->key = kKeyPageDown;
        return true;
    case VK_LEFT:
        mapped->key = 0xFF51;
        return true;
    case VK_UP:
        mapped->key = 0xFF52;
        return true;
    case VK_RIGHT:
        mapped->key = 0xFF53;
        return true;
    case VK_DOWN:
        mapped->key = 0xFF54;
        return true;
    default:
        return false;
    }
}
#endif
