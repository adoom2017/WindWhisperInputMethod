#include "InputModeIcon.h"

namespace fengyu {
COLORREF InputModeIconColor(bool system_light, bool high_contrast,
                            COLORREF system_text) {
    if (high_contrast) return system_text;
    return system_light ? RGB(28, 28, 28) : RGB(255, 255, 255);
}

COLORREF ReadInputModeIconColor() {
    HIGHCONTRASTW contrast{sizeof(contrast)};
    const bool high_contrast =
        SystemParametersInfoW(SPI_GETHIGHCONTRAST, sizeof(contrast), &contrast, 0) &&
        (contrast.dwFlags & HCF_HIGHCONTRASTON) != 0;
    DWORD light = 0;
    DWORD size = sizeof(light);
    const LSTATUS result = RegGetValueW(
        HKEY_CURRENT_USER,
        L"Software\\Microsoft\\Windows\\CurrentVersion\\Themes\\Personalize",
        L"SystemUsesLightTheme", RRF_RT_REG_DWORD, nullptr, &light, &size);
    if (result != ERROR_SUCCESS || high_contrast) return GetSysColor(COLOR_WINDOWTEXT);
    return InputModeIconColor(light != 0, false, GetSysColor(COLOR_WINDOWTEXT));
}

HICON CreateInputModeIcon(bool ascii_mode, COLORREF foreground,
                          int width, int height) {
    if (width < 8 || height < 8 || width > 256 || height > 256) return nullptr;
    BITMAPINFO info{};
    info.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
    info.bmiHeader.biWidth = width;
    info.bmiHeader.biHeight = -height;
    info.bmiHeader.biPlanes = 1;
    info.bmiHeader.biBitCount = 32;
    info.bmiHeader.biCompression = BI_RGB;
    void *pixels = nullptr;
    HDC memory = CreateCompatibleDC(nullptr);
    HBITMAP color = memory ? CreateDIBSection(
        memory, &info, DIB_RGB_COLORS, &pixels, nullptr, 0) : nullptr;
    HBITMAP mask = CreateBitmap(width, height, 1, 1, nullptr);
    if (!memory || !color || !mask || !pixels) {
        if (mask) DeleteObject(mask);
        if (color) DeleteObject(color);
        if (memory) DeleteDC(memory);
        return nullptr;
    }

    HGDIOBJ old_bitmap = SelectObject(memory, color);
    RECT bounds{0, 0, width, height};
    FillRect(memory, &bounds, static_cast<HBRUSH>(GetStockObject(BLACK_BRUSH)));
    HFONT font = CreateFontW(
        -(height - 2), 0, 0, 0, FW_SEMIBOLD, FALSE, FALSE, FALSE,
        DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS,
        ANTIALIASED_QUALITY, DEFAULT_PITCH | FF_DONTCARE, L"Microsoft YaHei UI");
    HGDIOBJ old_font = font ? SelectObject(memory, font) : nullptr;
    SetBkMode(memory, TRANSPARENT);
    // Draw white coverage first, even when the final glyph will be black.
    SetTextColor(memory, RGB(255, 255, 255));
    DrawTextW(memory, ascii_mode ? L"英" : L"中", 1, &bounds,
              DT_CENTER | DT_VCENTER | DT_SINGLELINE | DT_NOPREFIX);
    GdiFlush();
    auto *rgba = static_cast<BYTE *>(pixels);
    for (int index = 0; index < width * height; ++index) {
        const BYTE alpha = rgba[index * 4];
        // Windows alpha icons require premultiplied BGRA, including edges.
        rgba[index * 4] = static_cast<BYTE>(GetBValue(foreground) * alpha / 255);
        rgba[index * 4 + 1] = static_cast<BYTE>(GetGValue(foreground) * alpha / 255);
        rgba[index * 4 + 2] = static_cast<BYTE>(GetRValue(foreground) * alpha / 255);
        rgba[index * 4 + 3] = alpha;
    }
    if (old_font) SelectObject(memory, old_font);
    if (font) DeleteObject(font);
    SelectObject(memory, old_bitmap);
    HGDIOBJ old_mask = SelectObject(memory, mask);
    PatBlt(memory, 0, 0, width, height, BLACKNESS);
    SelectObject(memory, old_mask);
    ICONINFO icon_info{};
    icon_info.fIcon = TRUE;
    icon_info.hbmColor = color;
    icon_info.hbmMask = mask;
    HICON icon = CreateIconIndirect(&icon_info);
    DeleteObject(mask);
    DeleteObject(color);
    DeleteDC(memory);
    return icon;
}
}
