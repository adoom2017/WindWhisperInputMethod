#pragma once
#include <windows.h>

namespace fengyu {
// Taskbar/system theme, independent of the application and candidate theme.
COLORREF InputModeIconColor(bool system_light, bool high_contrast,
                            COLORREF system_text);
COLORREF ReadInputModeIconColor();
HICON CreateInputModeIcon(bool ascii_mode, COLORREF foreground,
                          int width, int height);
}
