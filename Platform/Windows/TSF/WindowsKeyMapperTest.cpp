#include "WindowsKeyMapper.h"

#define CHECK(condition)      \
    do {                      \
        if (!(condition)) {   \
            return __LINE__;  \
        }                     \
    } while (false)

int main() {
    FyMappedKey key{};
    CHECK(FyMapVirtualKey('N', false, false, false, false, false, &key));
    CHECK(key.key == 'n');
    CHECK(!FyMapVirtualKey('N', true, false, false, false, false, &key));
    CHECK(!FyMapVirtualKey('N', false, false, true, false, false, &key));
    CHECK(!FyMapVirtualKey(VK_SPACE, false, false, false, false, false, &key));
    CHECK(FyMapVirtualKey(VK_SPACE, false, false, false, false, true, &key));
    CHECK(key.key == 0x20);
    CHECK(FyMapVirtualKey(VK_BACK, false, false, false, false, true, &key));
    CHECK(key.key == 0x08);
    CHECK(FyMapVirtualKey(VK_NEXT, false, false, false, false, true, &key));
    CHECK(key.key == 0xFF56);
    CHECK(FyMapVirtualKey(VK_DOWN, false, false, false, false, true, &key));
    CHECK(key.key == 0xFF54);
    CHECK(FyMapVirtualKey('3', false, false, false, false, true, &key));
    CHECK(key.key == '3');
    CHECK(FyMapVirtualKey(VK_OEM_3, true, false, false, false, true, &key));
    CHECK(key.key == '~');
    CHECK(!FyMapVirtualKey(VK_OEM_3, false, false, false, false, true, &key));
    return 0;
}
