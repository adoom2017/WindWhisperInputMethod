#include "CandidateWindow.h"
#ifdef _WIN32
#include <dwmapi.h>

#include <algorithm>
#include <numeric>
#ifdef min
#undef min
#endif
#ifdef max
#undef max
#endif

namespace {
constexpr wchar_t kWindowClass[] = L"WindWhisperCandidateWindow";

// Values mirror docs/DESIGN_SYSTEM.md. The window is a flat surface with a
// single highlight block; no gradients, sheens or accent bars.
struct ThemePalette {
    COLORREF surface;
    COLORREF border;
    COLORREF text;
    COLORREF secondary;
    COLORREF tertiary;
    COLORREF accent;
    COLORREF highlight;
    COLORREF highlight_text;
};

constexpr ThemePalette kLightPalette{
    RGB(0xFA, 0xFA, 0xF8), RGB(0xDE, 0xDE, 0xD9), RGB(0x1F, 0x20, 0x23),
    RGB(0x6E, 0x70, 0x76), RGB(0x85, 0x87, 0x8D), RGB(0x2F, 0x6B, 0x8A),
    RGB(0xE4, 0xED, 0xF1), RGB(0x16, 0x3F, 0x55)};
constexpr ThemePalette kDarkPalette{
    RGB(0x25, 0x26, 0x29), RGB(0x3A, 0x3C, 0x40), RGB(0xEC, 0xED, 0xEF),
    RGB(0x9A, 0x9D, 0xA3), RGB(0x7E, 0x81, 0x87), RGB(0x86, 0xB6, 0xCF),
    RGB(0x33, 0x43, 0x4D), RGB(0xE3, 0xEE, 0xF4)};

// Defined locally so the code builds with SDKs older than Windows 11.
constexpr DWORD kDwmWindowCornerPreference = 33;
constexpr DWORD kDwmBorderColor = 34;
constexpr DWORD kDwmCornerRound = 2;

// Layout metrics in device-independent pixels.
constexpr int kPanelPadding = 4;
constexpr int kItemHeight = 30;
constexpr int kItemPadding = 8;
constexpr int kItemGap = 2;
constexpr int kIndexGap = 5;
constexpr int kCommentGap = 6;
constexpr int kMinItemWidth = 40;
constexpr int kMaxItemWidth = 240;
constexpr int kPagerWidth = 76;
constexpr int kHighlightRadius = 10;  // RoundRect takes the ellipse diameter.
constexpr int kPrimaryFontSize = 19;
constexpr int kSecondaryFontSize = 15;

bool HighContrastEnabled() {
    HIGHCONTRASTW contrast{sizeof(contrast)};
    return SystemParametersInfoW(SPI_GETHIGHCONTRAST, sizeof(contrast),
                                 &contrast, 0) &&
           (contrast.dwFlags & HCF_HIGHCONTRASTON) != 0;
}

ThemePalette ResolvePalette(CandidateWindowTheme theme) {
    if (HighContrastEnabled()) {
        return ThemePalette{GetSysColor(COLOR_WINDOW),     GetSysColor(COLOR_WINDOWTEXT),
                            GetSysColor(COLOR_WINDOWTEXT), GetSysColor(COLOR_WINDOWTEXT),
                            GetSysColor(COLOR_GRAYTEXT),   GetSysColor(COLOR_HIGHLIGHTTEXT),
                            GetSysColor(COLOR_HIGHLIGHT),  GetSysColor(COLOR_HIGHLIGHTTEXT)};
    }
    return theme == CandidateWindowTheme::Light ? kLightPalette : kDarkPalette;
}

int Scale(int value, UINT dpi) {
    return MulDiv(value, static_cast<int>(dpi), 96);
}

HFONT CreateUiFont(UINT dpi, int logical_height, int weight = FW_NORMAL,
                   const wchar_t *face = L"Microsoft YaHei UI") {
    return CreateFontW(
        -Scale(logical_height, dpi), 0, 0, 0, weight, FALSE, FALSE, FALSE,
        DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS,
        CLEARTYPE_QUALITY, DEFAULT_PITCH | FF_DONTCARE, face);
}

int TextWidth(HDC dc, HFONT font, const std::wstring &text) {
    if (text.empty()) return 0;
    HGDIOBJ previous = SelectObject(dc, font);
    SIZE size{};
    GetTextExtentPoint32W(dc, text.c_str(), static_cast<int>(text.size()), &size);
    SelectObject(dc, previous);
    return size.cx;
}

void FillRoundRect(HDC dc, const RECT &rect, int diameter, COLORREF color) {
    HBRUSH brush = CreateSolidBrush(color);
    HPEN pen = CreatePen(PS_SOLID, 1, color);
    HGDIOBJ old_brush = SelectObject(dc, brush);
    HGDIOBJ old_pen = SelectObject(dc, pen);
    RoundRect(dc, rect.left, rect.top, rect.right, rect.bottom, diameter, diameter);
    SelectObject(dc, old_pen);
    SelectObject(dc, old_brush);
    DeleteObject(pen);
    DeleteObject(brush);
}

void DrawTextIn(HDC dc, HFONT font, COLORREF color, const std::wstring &text,
                RECT rect, UINT format) {
    if (text.empty() || rect.right <= rect.left) return;
    HGDIOBJ previous = SelectObject(dc, font);
    SetTextColor(dc, color);
    DrawTextW(dc, text.c_str(), static_cast<int>(text.size()), &rect,
              format | DT_SINGLELINE | DT_VCENTER | DT_NOPREFIX);
    SelectObject(dc, previous);
}

std::wstring PageLabel(size_t page, size_t page_count) {
    return std::to_wstring(page + 1) + L"/" + std::to_wstring(page_count);
}
}  // namespace

void CandidateWindow::SetTheme(CandidateWindowTheme theme) {
    theme_ = theme;
    if (hwnd_) {
        ApplyFrameStyle();
        if (IsWindowVisible(hwnd_)) InvalidateRect(hwnd_, nullptr, FALSE);
    }
}

bool CandidateWindow::Create(HINSTANCE instance, HWND owner) {
    if (hwnd_ && !IsWindow(hwnd_)) hwnd_ = nullptr;
    if (hwnd_ && GetWindow(hwnd_, GW_OWNER) != owner) {
        // Establish ownership at creation, as in the Windows IME sample.
        Hide();
        DestroyWindow(hwnd_);
        hwnd_ = nullptr;
    }
    if (hwnd_) {
        return true;
    }
    last_error_ = ERROR_SUCCESS;
    WNDCLASSW window_class{};
    window_class.style = CS_IME | CS_DROPSHADOW;
    window_class.lpfnWndProc = &CandidateWindow::WndProc;
    window_class.hInstance = instance;
    window_class.hCursor = LoadCursorW(nullptr, MAKEINTRESOURCEW(32512));
    window_class.hbrBackground = nullptr;
    window_class.lpszClassName = kWindowClass;
    if (!RegisterClassW(&window_class) &&
        GetLastError() != ERROR_CLASS_ALREADY_EXISTS) {
        last_error_ = GetLastError();
        return false;
    }
    hwnd_ = CreateWindowExW(
        WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE | WS_EX_TOPMOST, kWindowClass,
        L"WindWhisper candidates", WS_POPUP | WS_CLIPSIBLINGS, 0, 0, 1, 1, owner, nullptr,
        instance, this);
    if (!hwnd_) {
        last_error_ = GetLastError();
        return false;
    }
    ApplyFrameStyle();
    return true;
}

// Windows 11 draws antialiased rounded corners and the border through DWM.
// Earlier versions reject the attribute; the window then stays square, like
// native Windows 10 popups, and Paint() draws the border itself.
void CandidateWindow::ApplyFrameStyle() {
    const DWORD corner = kDwmCornerRound;
    dwm_frame_ = SUCCEEDED(DwmSetWindowAttribute(
        hwnd_, kDwmWindowCornerPreference, &corner, sizeof(corner)));
    if (dwm_frame_) {
        const COLORREF border = ResolvePalette(theme_).border;
        DwmSetWindowAttribute(hwnd_, kDwmBorderColor, &border, sizeof(border));
    }
}

CandidateWindow::~CandidateWindow() {
    if (hwnd_) {
        Hide();
        DestroyWindow(hwnd_);
        hwnd_ = nullptr;
    }
}

// Natural width of each candidate cell; ShowAt and Paint share it so the
// window size and the drawn cells never disagree.
std::vector<int> CandidateWindow::MeasureItems(HDC dc) const {
    HFONT primary = CreateUiFont(dpi_, kPrimaryFontSize);
    HFONT secondary = CreateUiFont(dpi_, kSecondaryFontSize);
    std::vector<int> widths;
    widths.reserve(items_.size());
    for (size_t index = 0; index < items_.size(); ++index) {
        const auto &item = items_[index];
        int width = Scale(kItemPadding * 2 + kIndexGap, dpi_) +
                    TextWidth(dc, secondary, std::to_wstring(index + 1)) +
                    TextWidth(dc, primary, item.text);
        if (!item.comment.empty()) {
            width += Scale(kCommentGap, dpi_) + TextWidth(dc, secondary, item.comment);
        }
        widths.push_back(std::clamp(width, Scale(kMinItemWidth, dpi_),
                                    Scale(kMaxItemWidth, dpi_)));
    }
    DeleteObject(secondary);
    DeleteObject(primary);
    return widths;
}

void CandidateWindow::ShowAt(
    POINT point, UINT dpi, const std::vector<CandidateWindowItem> &items,
    size_t highlighted, size_t page, size_t page_count) {
    if (!hwnd_) {
        last_error_ = ERROR_INVALID_WINDOW_HANDLE;
        return;
    }
    const bool was_visible = IsWindowVisible(hwnd_) != FALSE;
    last_error_ = ERROR_SUCCESS;
    dpi_ = dpi == 0 ? 96 : dpi;
    highlighted_ = highlighted;
    page_ = page;
    page_count_ = page_count;
    items_ = items;
    item_widths_.clear();
    HDC dc = GetDC(hwnd_);
    if (dc) {
        item_widths_ = MeasureItems(dc);
        ReleaseDC(hwnd_, dc);
    }

    MONITORINFO monitor_info{sizeof(monitor_info)};
    GetMonitorInfoW(MonitorFromPoint(point, MONITOR_DEFAULTTONEAREST),
                    &monitor_info);
    const int max_width = monitor_info.rcWork.right - monitor_info.rcWork.left;
    const int gaps = Scale(kItemGap, dpi_) *
                     static_cast<int>(item_widths_.empty() ? 0 : item_widths_.size() - 1);
    const int fixed = Scale(kPanelPadding * 2, dpi_) + gaps +
                      (page_count_ > 1 ? Scale(kPagerWidth, dpi_) : 0);
    // Shrink the longest cells first when the row would leave the monitor;
    // Paint() ellipsizes text that no longer fits.
    const int available = std::max(0, max_width - fixed);
    while (std::accumulate(item_widths_.begin(), item_widths_.end(), 0) > available) {
        auto widest = std::max_element(item_widths_.begin(), item_widths_.end());
        if (widest == item_widths_.end() || *widest <= Scale(kMinItemWidth, dpi_)) break;
        *widest = std::max(Scale(kMinItemWidth, dpi_), *widest - Scale(8, dpi_));
    }
    const int width = std::min(
        max_width, fixed + std::accumulate(item_widths_.begin(), item_widths_.end(), 0));
    const int height = Scale(kPanelPadding * 2 + kItemHeight, dpi_);

    point.x = std::clamp(point.x, monitor_info.rcWork.left,
                         monitor_info.rcWork.right - width);
    if (point.y + height > monitor_info.rcWork.bottom) {
        point.y = std::max(monitor_info.rcWork.top, point.y - height - Scale(24, dpi_));
    }
    ApplyFrameStyle();
    if (!SetWindowPos(hwnd_, HWND_TOPMOST, point.x, point.y, width, height,
                       SWP_NOACTIVATE | SWP_SHOWWINDOW)) {
        last_error_ = GetLastError();
        return;
    }
    NotifyWinEvent(was_visible ? EVENT_OBJECT_IME_CHANGE : EVENT_OBJECT_IME_SHOW,
                    hwnd_, OBJID_CLIENT, CHILDID_SELF);
    InvalidateRect(hwnd_, nullptr, FALSE);
}

void CandidateWindow::Hide() {
    if (hwnd_) {
        const bool was_visible = IsWindowVisible(hwnd_) != FALSE;
        ShowWindow(hwnd_, SW_HIDE);
        if (was_visible) {
            NotifyWinEvent(EVENT_OBJECT_IME_HIDE, hwnd_, OBJID_CLIENT, CHILDID_SELF);
        }
        items_.clear();
        item_widths_.clear();
    }
}

void CandidateWindow::Paint(HDC dc) {
    const ThemePalette palette = ResolvePalette(theme_);
    RECT client{};
    GetClientRect(hwnd_, &client);
    HDC buffer = CreateCompatibleDC(dc);
    HBITMAP bitmap = CreateCompatibleBitmap(
        dc, std::max<LONG>(1, client.right), std::max<LONG>(1, client.bottom));
    HGDIOBJ old_bitmap = SelectObject(buffer, bitmap);

    HBRUSH surface = CreateSolidBrush(palette.surface);
    FillRect(buffer, &client, surface);
    DeleteObject(surface);
    if (!dwm_frame_) {
        HBRUSH border = CreateSolidBrush(palette.border);
        FrameRect(buffer, &client, border);
        DeleteObject(border);
    }

    SetBkMode(buffer, TRANSPARENT);
    HFONT primary = CreateUiFont(dpi_, kPrimaryFontSize);
    HFONT secondary = CreateUiFont(dpi_, kSecondaryFontSize);
    HFONT index_bold = CreateUiFont(dpi_, kSecondaryFontSize, FW_SEMIBOLD);
    const int padding = Scale(kItemPadding, dpi_);
    const int pager_left = page_count_ > 1 ? client.right - Scale(kPagerWidth, dpi_)
                                           : client.right;
    int x = Scale(kPanelPadding, dpi_);
    for (size_t index = 0; index < items_.size() && index < item_widths_.size(); ++index) {
        const auto &item = items_[index];
        const bool highlighted = index == highlighted_;
        RECT cell{x, Scale(kPanelPadding, dpi_),
                  std::min<LONG>(pager_left, x + item_widths_[index]),
                  client.bottom - Scale(kPanelPadding, dpi_)};
        if (cell.right <= cell.left) break;
        if (highlighted) {
            FillRoundRect(buffer, cell, Scale(kHighlightRadius, dpi_), palette.highlight);
        }

        const std::wstring number = std::to_wstring(index + 1);
        HFONT index_font = highlighted ? index_bold : secondary;
        RECT number_rect = cell;
        number_rect.left += padding;
        number_rect.right = number_rect.left + TextWidth(buffer, index_font, number);
        DrawTextIn(buffer, index_font, highlighted ? palette.accent : palette.tertiary,
                   number, number_rect, DT_LEFT);

        // The candidate keeps priority; the comment follows directly and
        // is the first to be cut when the cell is narrow.
        const int content_left = number_rect.right + Scale(kIndexGap, dpi_);
        const int content_right = cell.right - padding;
        const int text_width = TextWidth(buffer, primary, item.text);
        RECT text_rect{content_left, cell.top,
                       std::min(content_right, content_left + text_width), cell.bottom};
        DrawTextIn(buffer, primary, highlighted ? palette.highlight_text : palette.text,
                   item.text, text_rect, DT_LEFT | DT_END_ELLIPSIS);
        if (!item.comment.empty()) {
            RECT comment_rect{text_rect.right + Scale(kCommentGap, dpi_), cell.top,
                              content_right, cell.bottom};
            DrawTextIn(buffer, secondary, palette.secondary, item.comment, comment_rect,
                       DT_LEFT | DT_END_ELLIPSIS);
        }
        x = cell.right + Scale(kItemGap, dpi_);
    }

    if (page_count_ > 1) {
        RECT divider{pager_left, Scale(11, dpi_), pager_left + std::max(1, Scale(1, dpi_)),
                     client.bottom - Scale(11, dpi_)};
        HBRUSH divider_brush = CreateSolidBrush(palette.border);
        FillRect(buffer, &divider, divider_brush);
        DeleteObject(divider_brush);

        HFONT arrows = CreateUiFont(dpi_, 18, FW_NORMAL, L"Segoe UI");
        const int third = Scale(kPagerWidth, dpi_) / 4;
        RECT previous{pager_left, 0, pager_left + third, client.bottom};
        RECT label{previous.right, 0, client.right - third, client.bottom};
        RECT next{label.right, 0, client.right - Scale(kPanelPadding, dpi_), client.bottom};
        DrawTextIn(buffer, arrows, page_ > 0 ? palette.secondary : palette.tertiary,
                   L"‹", previous, DT_CENTER);
        DrawTextIn(buffer, secondary, palette.secondary, PageLabel(page_, page_count_),
                   label, DT_CENTER);
        DrawTextIn(buffer, arrows,
                   page_ + 1 < page_count_ ? palette.secondary : palette.tertiary,
                   L"›", next, DT_CENTER);
        DeleteObject(arrows);
    }

    DeleteObject(index_bold);
    DeleteObject(secondary);
    DeleteObject(primary);
    BitBlt(dc, 0, 0, client.right, client.bottom, buffer, 0, 0, SRCCOPY);
    SelectObject(buffer, old_bitmap);
    DeleteObject(bitmap);
    DeleteDC(buffer);
}

LRESULT CALLBACK CandidateWindow::WndProc(
    HWND window, UINT message, WPARAM w_param, LPARAM l_param) {
    auto *self = reinterpret_cast<CandidateWindow *>(
        GetWindowLongPtrW(window, GWLP_USERDATA));
    if (message == WM_NCCREATE) {
        const auto *create = reinterpret_cast<const CREATESTRUCTW *>(l_param);
        self = static_cast<CandidateWindow *>(create->lpCreateParams);
        SetWindowLongPtrW(window, GWLP_USERDATA,
                          reinterpret_cast<LONG_PTR>(self));
        self->hwnd_ = window;
    }
    if (self && message == WM_PAINT) {
        PAINTSTRUCT paint{};
        HDC dc = BeginPaint(window, &paint);
        self->Paint(dc);
        EndPaint(window, &paint);
        return 0;
    }
    if (self && (message == WM_SETTINGCHANGE || message == WM_SYSCOLORCHANGE)) {
        self->ApplyFrameStyle();
        InvalidateRect(window, nullptr, FALSE);
    }
    if (message == WM_NCHITTEST) {
        return HTTRANSPARENT;
    }
    if (message == WM_ERASEBKGND) return 1;
    return DefWindowProcW(window, message, w_param, l_param);
}
#endif
