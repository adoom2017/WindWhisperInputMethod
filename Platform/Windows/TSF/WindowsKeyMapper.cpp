#include "WindowsKeyMapper.h"

#ifdef _WIN32
namespace {
constexpr uint32_t kKeyPageUp = 0xFF55;
constexpr uint32_t kKeyPageDown = 0xFF56;
constexpr uint32_t kModifierShift = 1u << 0;
constexpr uint32_t kModifierCapsLock = 1u << 1;
constexpr uint32_t kModifierControl = 1u << 2;
constexpr uint32_t kModifierAlt = 1u << 3;

bool IsFullWidthPrintableKey(WPARAM virtual_key) {
    if ((virtual_key >= '0' && virtual_key <= '9') ||
        virtual_key == VK_SPACE) {
        return true;
    }
    switch (virtual_key) {
    case VK_OEM_MINUS:
    case VK_OEM_PLUS:
    case VK_OEM_1:
    case VK_OEM_COMMA:
    case VK_OEM_PERIOD:
    case VK_OEM_2:
    case VK_OEM_3:
    case VK_OEM_4:
    case VK_OEM_5:
    case VK_OEM_6:
    case VK_OEM_7:
        return true;
    default:
        return false;
    }
}
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
    if (IsShiftKey(virtual_key) && !repeat) {
        pending_ = !other_modifier_down;
    }
}

bool FyShiftTapState::TestKeyUp(WPARAM virtual_key) const {
    return IsShiftKey(virtual_key) && pending_;
}

bool FyShiftTapState::KeyUp(WPARAM virtual_key) {
    if (!IsShiftKey(virtual_key)) {
        return false;
    }
    const bool toggle = pending_;
    pending_ = false;
    return toggle;
}

void FyShiftTapState::Reset() {
    pending_ = false;
}

bool FyMapVirtualKey(WPARAM virtual_key, bool shift, bool caps_lock,
                     bool control, bool alt, bool composing, bool full_width,
                     FyMappedKey *mapped, bool system_shortcut) {
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
    // Outside an active composition, only capture printable keys that need
    // full-width conversion. Control/navigation keys must remain available to
    // the host application (notably Backspace for deleting committed text).
    if (!composing && (!full_width || !IsFullWidthPrintableKey(virtual_key))) {
        return false;
    }
    if (virtual_key >= '0' && virtual_key <= '9') {
        static constexpr char shifted[] = ")!@#$%^&*(";
        mapped->key = shift ? shifted[virtual_key - '0']
                            : static_cast<uint32_t>(virtual_key);
        return true;
    }

    switch (virtual_key) {
    case VK_BACK:
        mapped->key = 0x08;
        return true;
    case VK_ESCAPE:
        mapped->key = 0x1B;
        return true;
    case VK_SPACE:
        mapped->key = 0x20;
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
    case VK_OEM_MINUS:
        mapped->key = shift ? '_' : '-';
        return true;
    case VK_OEM_PLUS:
        mapped->key = shift ? '+' : '=';
        return true;
    case VK_OEM_1:
        mapped->key = shift ? ':' : ';';
        return true;
    case VK_OEM_COMMA:
        mapped->key = shift ? '<' : ',';
        return true;
    case VK_OEM_PERIOD:
        mapped->key = shift ? '>' : '.';
        return true;
    case VK_OEM_2:
        mapped->key = shift ? '?' : '/';
        return true;
    case VK_OEM_3:
        mapped->key = shift ? '~' : '`';
        return true;
    case VK_OEM_4:
        mapped->key = shift ? '{' : '[';
        return true;
    case VK_OEM_5:
        mapped->key = shift ? '|' : '\\';
        return true;
    case VK_OEM_6:
        mapped->key = shift ? '}' : ']';
        return true;
    case VK_OEM_7:
        mapped->key = shift ? '"' : '\'';
        return true;
    default:
        return false;
    }
}
#endif
