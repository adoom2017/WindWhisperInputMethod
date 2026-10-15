#include "CandidateWindow.h"

#include <algorithm>
#include <cstdio>

#ifdef min
#undef min
#endif
#ifdef max
#undef max
#endif

// Exercise the production sizing and painting on a hidden window. No input
// method registration or visible desktop changes are needed for this test.
struct CandidateWindowTestAccess {
    static int Prepare(CandidateWindow &window, HDC dc, UINT dpi,
                       const std::wstring &text, bool selected,
                       CandidateWindowTheme theme) {
        window.dpi_ = dpi;
        window.items_ = {{text, L""}};
        window.highlighted_ = selected ? 0 : 1;
        window.page_count_ = 1;
        window.theme_ = theme;
        window.item_widths_ = window.MeasureItems(dc);
        const int width = MulDiv(8, dpi, 96) + window.item_widths_.front();
        SetWindowPos(window.hwnd_, nullptr, 0, 0, width, MulDiv(38, dpi, 96),
                     SWP_NOACTIVATE | SWP_NOZORDER);
        return width;
    }
    static void Paint(CandidateWindow &window, HDC dc) { window.Paint(dc); }
};

class Bitmap {
public:
    Bitmap(int width, int height) : width(width), height(height) {
        dc = CreateCompatibleDC(nullptr);
        BITMAPINFO info{};
        info.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
        info.bmiHeader.biWidth = width;
        info.bmiHeader.biHeight = -height;
        info.bmiHeader.biPlanes = 1;
        info.bmiHeader.biBitCount = 32;
        bitmap_ = CreateDIBSection(dc, &info, DIB_RGB_COLORS,
                                  reinterpret_cast<void **>(&pixels), nullptr, 0);
        previous_ = SelectObject(dc, bitmap_);
        PatBlt(dc, 0, 0, width, height, BLACKNESS);
    }
    ~Bitmap() {
        SelectObject(dc, previous_);
        DeleteObject(bitmap_);
        DeleteDC(dc);
    }
    bool IsInk(int x, int y, bool light) const {
        if (x < 0 || x >= width || y < 0 || y >= height) return false;
        const DWORD pixel = pixels[y * width + x];
        const int red = (pixel >> 16) & 255;
        const int green = (pixel >> 8) & 255;
        const int blue = pixel & 255;
        return light ? std::max({red, green, blue}) < 130
                     : std::min({red, green, blue}) > 130;
    }
    HDC dc{};
    DWORD *pixels{};
    int width, height;
private:
    HBITMAP bitmap_{};
    HGDIOBJ previous_{};
};

bool CheckCompleteText(CandidateWindow &window, UINT dpi,
                       const std::wstring &text, bool selected, bool light) {
    const auto scale = [dpi](int value) { return MulDiv(value, dpi, 96); };
    Bitmap actual(2048, scale(38));
    const int width = CandidateWindowTestAccess::Prepare(
        window, actual.dc, dpi, text, selected,
        light ? CandidateWindowTheme::Light : CandidateWindowTheme::Dark);
    CandidateWindowTestAccess::Paint(window, actual.dc);

    // Independent reference: render the whole phrase in a generously sized
    // rectangle, without ellipsis. Compare its glyph pixels with the real UI.
    Bitmap reference(2048, scale(38));
    const COLORREF background = light
        ? (selected ? RGB(0xE4, 0xED, 0xF1) : RGB(0xFA, 0xFA, 0xF8))
        : (selected ? RGB(0x33, 0x43, 0x4D) : RGB(0x25, 0x26, 0x29));
    const COLORREF foreground = light
        ? (selected ? RGB(0x16, 0x3F, 0x55) : RGB(0x1F, 0x20, 0x23))
        : (selected ? RGB(0xE3, 0xEE, 0xF4) : RGB(0xEC, 0xED, 0xEF));
    RECT background_rect{0, 0, reference.width, reference.height};
    HBRUSH brush = CreateSolidBrush(background);
    FillRect(reference.dc, &background_rect, brush);
    DeleteObject(brush);
    HFONT primary = CreateFontW(-scale(19), 0, 0, 0, FW_NORMAL, FALSE, FALSE,
        FALSE, DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS,
        CLEARTYPE_QUALITY, DEFAULT_PITCH | FF_DONTCARE, L"Microsoft YaHei UI");
    HFONT number = CreateFontW(-scale(15), 0, 0, 0,
        selected ? FW_SEMIBOLD : FW_NORMAL, FALSE, FALSE, FALSE, DEFAULT_CHARSET,
        OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS, CLEARTYPE_QUALITY,
        DEFAULT_PITCH | FF_DONTCARE, L"Microsoft YaHei UI");
    HGDIOBJ old_font = SelectObject(reference.dc, number);
    RECT number_bounds{};
    DrawTextW(reference.dc, L"1", 1, &number_bounds,
              DT_CALCRECT | DT_SINGLELINE | DT_NOPREFIX);
    SelectObject(reference.dc, primary);
    RECT text_bounds{};
    DrawTextW(reference.dc, text.c_str(), static_cast<int>(text.size()),
              &text_bounds, DT_CALCRECT | DT_SINGLELINE | DT_NOPREFIX);
    const int left = scale(4) + scale(8) + number_bounds.right + scale(5);
    RECT rect{left, scale(4), reference.width, scale(34)};
    SetBkMode(reference.dc, TRANSPARENT);
    SetTextColor(reference.dc, foreground);
    DrawTextW(reference.dc, text.c_str(), static_cast<int>(text.size()), &rect,
              DT_LEFT | DT_VCENTER | DT_SINGLELINE | DT_NOPREFIX);
    SelectObject(reference.dc, old_font);
    DeleteObject(number);
    DeleteObject(primary);
    GdiFlush();

    bool matches = left + text_bounds.right <= width - scale(8);
    int expected_ink = 0, actual_ink = 0;
    for (int y = scale(4); y < scale(34); ++y) {
        for (int x = left; x < left + text_bounds.right; ++x) {
            const bool expected = reference.IsInk(x, y, light);
            const bool observed = actual.IsInk(x, y, light);
            expected_ink += expected;
            actual_ink += observed;
            if (expected != observed) matches = false;
        }
    }
    if (!matches || expected_ink == 0) {
        std::fwprintf(stderr,
            L"Candidate clipped: dpi=%u selected=%d light=%d text=%ls width=%d ink=%d/%d\n",
            dpi, selected, light, text.c_str(), width, actual_ink, expected_ink);
        return false;
    }
    return true;
}

int wmain() {
    CandidateWindow window;
    if (!window.Create(GetModuleHandleW(nullptr))) return 1;
    int failures = 0;
    for (UINT dpi : {96u, 120u, 144u, 192u, 240u}) {
        for (bool selected : {false, true}) {
            for (bool light : {false, true}) {
                for (const auto *text : {L"母亲", L"为什么", L"中华人民共和国",
                         L"这是一条超过原有单项宽度限制的自定义词组"}) {
                    if (!CheckCompleteText(window, dpi, text, selected, light)) ++failures;
                }
            }
        }
    }
    return failures == 0 ? 0 : 1;
}
