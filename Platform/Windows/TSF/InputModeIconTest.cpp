#include "InputModeIcon.h"
#include <algorithm>
#include <filesystem>
#include <fstream>
#include <vector>

#define CHECK(condition) do { if (!(condition)) return __LINE__; } while (false)

std::vector<BYTE> ReadPixels(HICON icon, int size) {
    ICONINFO icon_info{};
    if (!GetIconInfo(icon, &icon_info)) return {};
    BITMAPINFO info{};
    info.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
    info.bmiHeader.biWidth = size;
    info.bmiHeader.biHeight = -size;
    info.bmiHeader.biPlanes = 1;
    info.bmiHeader.biBitCount = 32;
    std::vector<BYTE> pixels(size * size * 4);
    HDC dc = CreateCompatibleDC(nullptr);
    const int rows = GetDIBits(dc, icon_info.hbmColor, 0, size, pixels.data(), &info, DIB_RGB_COLORS);
    DeleteDC(dc);
    DeleteObject(icon_info.hbmColor);
    DeleteObject(icon_info.hbmMask);
    if (rows != size) return {};
    return pixels;
}

// Optional offscreen visual fixture: no installation or system theme changes.
bool SavePreview(const std::filesystem::path &path, const wchar_t *profile) {
    constexpr int width = 720, height = 160;
    BITMAPINFO info{};
    info.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
    info.bmiHeader.biWidth = width;
    info.bmiHeader.biHeight = -height;
    info.bmiHeader.biPlanes = 1;
    info.bmiHeader.biBitCount = 32;
    void *pixels = nullptr;
    HDC dc = CreateCompatibleDC(nullptr);
    HBITMAP bitmap = CreateDIBSection(dc, &info, DIB_RGB_COLORS, &pixels, nullptr, 0);
    if (!dc || !bitmap) return false;
    HGDIOBJ previous = SelectObject(dc, bitmap);
    for (int row = 0; row < 2; ++row) {
        const bool light = row == 0;
        RECT background{0, row * 80, width, (row + 1) * 80};
        HBRUSH brush = CreateSolidBrush(light ? RGB(230, 238, 245) : RGB(32, 32, 32));
        FillRect(dc, &background, brush);
        DeleteObject(brush);
        int x = 24;
        for (int size : {32, 24, 20, 16}) {
            const COLORREF color = fengyu::InputModeIconColor(light, false, 0);
            for (bool english : {false, true}) {
                HICON icon = fengyu::CreateInputModeIcon(english, color, size, size);
                DrawIconEx(dc, x, row * 80 + (80 - size) / 2, icon, size, size, 0, nullptr, DI_NORMAL);
                DestroyIcon(icon);
                x += 42;
            }
            HICON icon = static_cast<HICON>(LoadImageW(nullptr, profile, IMAGE_ICON, size, size, LR_LOADFROMFILE));
            if (icon) {
                DrawIconEx(dc, x, row * 80 + (80 - size) / 2, icon, size, size, 0, nullptr, DI_NORMAL);
                DestroyIcon(icon);
            }
            x += 86;
        }
    }
    GdiFlush();
    BITMAPFILEHEADER header{};
    header.bfType = 0x4D42;
    header.bfOffBits = sizeof(header) + sizeof(BITMAPINFOHEADER);
    header.bfSize = header.bfOffBits + width * height * 4;
    std::ofstream file(path, std::ios::binary);
    file.write(reinterpret_cast<const char *>(&header), sizeof(header));
    file.write(reinterpret_cast<const char *>(&info.bmiHeader), sizeof(BITMAPINFOHEADER));
    file.write(static_cast<const char *>(pixels), width * height * 4);
    SelectObject(dc, previous);
    DeleteObject(bitmap);
    DeleteDC(dc);
    return static_cast<bool>(file);
}

int wmain(int argc, wchar_t **argv) {
    CHECK(fengyu::InputModeIconColor(true, false, 0) == RGB(28, 28, 28));
    CHECK(fengyu::InputModeIconColor(false, false, 0) == RGB(255, 255, 255));
    CHECK(fengyu::InputModeIconColor(true, true, RGB(255, 255, 0)) == RGB(255, 255, 0));
    for (int size : {16, 20, 24, 32, 40, 48}) {
        for (bool english : {false, true}) {
            HICON light = fengyu::CreateInputModeIcon(english, RGB(28, 28, 28), size, size);
            HICON dark = fengyu::CreateInputModeIcon(english, RGB(255, 255, 255), size, size);
            CHECK(light && dark);
            const auto light_pixels = ReadPixels(light, size);
            const auto dark_pixels = ReadPixels(dark, size);
            DestroyIcon(light);
            DestroyIcon(dark);
            CHECK(light_pixels.size() == size * size * 4);
            CHECK(light_pixels.size() == dark_pixels.size());
            int covered = 0;
            for (size_t i = 0; i < light_pixels.size(); i += 4) {
                const BYTE alpha = light_pixels[i + 3];
                CHECK(alpha == dark_pixels[i + 3]);
                for (size_t channel = 0; channel < 3; ++channel) {
                    CHECK(light_pixels[i + channel] == 28 * alpha / 255);
                    CHECK(dark_pixels[i + channel] == alpha);
                }
                if (alpha > 128) ++covered;
            }
            CHECK(covered > size);
        }
    }
    if (argc == 3) CHECK(SavePreview(argv[1], argv[2]));
    return 0;
}
