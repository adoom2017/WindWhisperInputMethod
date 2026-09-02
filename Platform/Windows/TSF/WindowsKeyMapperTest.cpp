#include "WindowsKeyMapper.h"

#define CHECK(condition)      \
    do {                      \
        if (!(condition)) {   \
            return __LINE__;  \
        }                     \
    } while (false)

int main() {
    FyShiftTapState shift;
    CHECK(shift.TestKeyDown(VK_SHIFT));
    shift.KeyDown(VK_SHIFT, false, false);
    CHECK(shift.TestKeyUp(VK_SHIFT));
    CHECK(shift.KeyUp(VK_SHIFT));

    CHECK(shift.TestKeyDown(VK_LSHIFT));
    shift.KeyDown(VK_LSHIFT, false, false);
    CHECK(!shift.TestKeyDown('A'));
    CHECK(!shift.TestKeyUp(VK_LSHIFT));
    CHECK(!shift.KeyUp(VK_LSHIFT));

    CHECK(shift.TestKeyDown(VK_RSHIFT));
    shift.KeyDown(VK_RSHIFT, false, true);
    CHECK(!shift.TestKeyUp(VK_RSHIFT));
    CHECK(!shift.KeyUp(VK_RSHIFT));

    CHECK(shift.TestKeyDown(VK_SHIFT));
    shift.KeyDown(VK_SHIFT, false, false);
    shift.Reset();
    CHECK(!shift.TestKeyUp(VK_SHIFT));

    FyMappedKey key{};
    CHECK(FyMapVirtualKey('N', false, false, false, false, false, false, &key));
    CHECK(key.key == 'n');
    CHECK(!FyMapVirtualKey('N', true, false, false, false, false, false, &key));
    CHECK(!FyMapVirtualKey('N', false, false, true, false, false, false, &key));
    CHECK(!FyMapVirtualKey(VK_SPACE, false, false, false, false, false, false, &key));
    CHECK(FyMapVirtualKey(VK_SPACE, false, false, false, false, true, false, &key));
    CHECK(key.key == 0x20);
    CHECK(FyMapVirtualKey(VK_BACK, false, false, false, false, true, false, &key));
    CHECK(key.key == 0x08);
    CHECK(FyMapVirtualKey(VK_NEXT, false, false, false, false, true, false, &key));
    CHECK(key.key == 0xFF56);
    CHECK(FyMapVirtualKey(VK_DOWN, false, false, false, false, true, false, &key));
    CHECK(key.key == 0xFF54);
    CHECK(FyMapVirtualKey('3', false, false, false, false, true, false, &key));
    CHECK(key.key == '3');
    CHECK(FyMapVirtualKey(VK_OEM_3, true, false, false, false, true, false, &key));
    CHECK(key.key == '~');
    CHECK(FyMapVirtualKey(VK_OEM_3, false, false, false, false, true, false, &key));
    CHECK(key.key == '`');
    CHECK(FyMapVirtualKey('1', true, false, false, false, true, false, &key));
    CHECK(key.key == '!');
    CHECK(FyMapVirtualKey(VK_OEM_COMMA, false, false, false, false, true, false, &key));
    CHECK(key.key == ',');
    CHECK(FyMapVirtualKey(VK_OEM_2, true, false, false, false, true, false, &key));
    CHECK(key.key == '?');

    // Full-width Chinese mode may capture printable punctuation while idle,
    // but Backspace and other editing keys must pass through to the app.
    CHECK(FyMapVirtualKey(VK_SPACE, false, false, false, false, false, true, &key));
    CHECK(key.key == 0x20);
    CHECK(FyMapVirtualKey('3', false, false, false, false, false, true, &key));
    CHECK(key.key == '3');
    CHECK(!FyMapVirtualKey(VK_BACK, false, false, false, false, false, true, &key));
    CHECK(!FyMapVirtualKey(VK_RETURN, false, false, false, false, false, true, &key));
    CHECK(!FyMapVirtualKey(VK_LEFT, false, false, false, false, false, true, &key));
    CHECK(!FyMapVirtualKey('R', false, false, false, false, false, true,
                           &key, true));
    CHECK(!FyMapVirtualKey('R', false, false, false, false, true, true,
                           &key, true));
    return 0;
}
