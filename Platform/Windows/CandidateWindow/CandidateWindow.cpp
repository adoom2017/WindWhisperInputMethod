#include "CandidateWindow.h"
#ifdef _WIN32
#include <algorithm>
#ifdef min
#undef min
#endif
#ifdef max
#undef max
#endif

namespace {
constexpr wchar_t kWindowClass[] = L"WindWhisperCandidateWindow";
struct ThemePalette {
    COLORREF background;
    COLORREF surface_top;
    COLORREF sheen;
    COLORREF highlight;
    COLORREF highlight_bottom;
    COLORREF border;
    COLORREF divider;
    COLORREF accent;
    COLORREF foreground;
    COLORREF secondary;
    COLORREF disabled;
};

constexpr ThemePalette kDarkPalette{
    RGB(29, 34, 43), RGB(57, 65, 78), RGB(100, 112, 132),
    RGB(66, 77, 94), RGB(29, 34, 43), RGB(76, 87, 105),
    RGB(69, 79, 95), RGB(255, 145, 122), RGB(248, 250, 255),
    RGB(200, 211, 226), RGB(123, 135, 152)};
constexpr ThemePalette kLightPalette{
    RGB(207, 221, 237), RGB(249, 253, 255), RGB(255, 255, 255),
    RGB(242, 249, 255), RGB(180, 204, 230), RGB(153, 174, 198),
    RGB(177, 196, 218), RGB(191, 66, 48), RGB(25, 37, 54),
    RGB(71, 89, 112), RGB(139, 154, 174)};

// A bounded, opaque glass finish keeps glyph contrast independent of the
// host application's background and works without compositor-specific APIs.
void FillGlassGradient(HDC dc, const RECT &rect, COLORREF top, COLORREF bottom) {
    const int height = std::max<LONG>(1, rect.bottom - rect.top);
    HGDIOBJ old = SelectObject(dc, GetStockObject(DC_BRUSH));
    for (int y = 0; y < height; ++y) {
        const auto channel = [&](int a, int b) {
            return a + (b - a) * y / std::max(1, height - 1);
        };
        SetDCBrushColor(dc, RGB(channel(GetRValue(top), GetRValue(bottom)),
                               channel(GetGValue(top), GetGValue(bottom)),
                               channel(GetBValue(top), GetBValue(bottom))));
        RECT line{rect.left, rect.top + y, rect.right, rect.top + y + 1};
        FillRect(dc, &line, static_cast<HBRUSH>(GetStockObject(DC_BRUSH)));
    }
    SelectObject(dc, old);
}

int Scale(int value, UINT dpi) {
    return MulDiv(value, static_cast<int>(dpi), 96);
}

HFONT CreateCandidateFont(UINT dpi, int logical_height = 19,
                          int weight = FW_NORMAL) {
    return CreateFontW(
        -Scale(logical_height, dpi), 0, 0, 0, weight, FALSE, FALSE, FALSE,
        DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS,
        CLEARTYPE_QUALITY, DEFAULT_PITCH | FF_DONTCARE, L"Microsoft YaHei UI");
}
}

void CandidateWindow::SetTheme(CandidateWindowTheme theme) {
    theme_ = theme;
    if (hwnd_ && IsWindowVisible(hwnd_)) {
        InvalidateRect(hwnd_, nullptr, FALSE);
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
    window_class.style = CS_IME;
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
    if (!hwnd_) last_error_ = GetLastError();
    return hwnd_ != nullptr;
}

CandidateWindow::~CandidateWindow() {
    if (hwnd_) {
        Hide();
        DestroyWindow(hwnd_);
        hwnd_ = nullptr;
    }
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
    const int height = Scale(52, dpi_);
    const int item_padding = Scale(12, dpi_);
    int width = Scale(12, dpi_);
    HDC dc = GetDC(hwnd_);
    if (dc) {
        HFONT font = CreateCandidateFont(dpi_);
        HGDIOBJ previous = SelectObject(dc, font);
        for (size_t index = 0; index < items_.size(); ++index) {
            const auto &item = items_[index];
            SIZE size{};
            const std::wstring label = std::to_wstring(index + 1) + L" " + item.text;
            GetTextExtentPoint32W(dc, label.c_str(),
                                  static_cast<int>(label.size()), &size);
            int item_width = size.cx + item_padding * 2;
            if (!item.comment.empty()) {
                SIZE comment_size{};
                GetTextExtentPoint32W(dc, item.comment.c_str(),
                                      static_cast<int>(item.comment.size()),
                                      &comment_size);
                item_width += comment_size.cx + Scale(8, dpi_);
            }
            width += item_width;
        }
        SelectObject(dc, previous);
        DeleteObject(font);
        ReleaseDC(hwnd_, dc);
    }
    if (page_count_ > 1) {
        width += Scale(92, dpi_);
    }

    MONITORINFO monitor_info{sizeof(monitor_info)};
    GetMonitorInfoW(MonitorFromPoint(point, MONITOR_DEFAULTTONEAREST),
                    &monitor_info);
    const int max_width = monitor_info.rcWork.right - monitor_info.rcWork.left;
    width = std::min(width, max_width);
    point.x = std::clamp(point.x, monitor_info.rcWork.left,
                         monitor_info.rcWork.right - width);
    if (point.y + height > monitor_info.rcWork.bottom) {
        point.y = std::max(monitor_info.rcWork.top, point.y - height - Scale(24, dpi_));
    }
    const int radius = Scale(18, dpi_);
    SetWindowRgn(hwnd_, CreateRoundRectRgn(0, 0, width + 1, height + 1,
                                           radius, radius), FALSE);
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
    }
}

void CandidateWindow::Paint(HDC dc) {
    const ThemePalette &palette = theme_ == CandidateWindowTheme::Light
                                      ? kLightPalette
                                      : kDarkPalette;
    RECT client{};
    GetClientRect(hwnd_, &client);
    HDC buffer = CreateCompatibleDC(dc);
    HBITMAP bitmap = CreateCompatibleBitmap(
        dc, std::max<LONG>(1, client.right), std::max<LONG>(1, client.bottom));
    HGDIOBJ old_bitmap = SelectObject(buffer, bitmap);

    FillGlassGradient(buffer, client, palette.surface_top, palette.background);
    HPEN border = CreatePen(PS_SOLID, Scale(1, dpi_), palette.border);
    HGDIOBJ old_pen = SelectObject(buffer, border);
    HGDIOBJ old_brush = SelectObject(buffer, GetStockObject(NULL_BRUSH));
    RoundRect(buffer, 0, 0, client.right, client.bottom,
              Scale(18, dpi_), Scale(18, dpi_));
    SelectObject(buffer, old_brush);
    SelectObject(buffer, old_pen);
    DeleteObject(border);

    HPEN sheen = CreatePen(PS_SOLID, 1, palette.sheen);
    old_pen = SelectObject(buffer, sheen);
    old_brush = SelectObject(buffer, GetStockObject(NULL_BRUSH));
    const int inset = Scale(1, dpi_);
    RoundRect(buffer, inset, inset, client.right - inset,
              client.bottom - inset, Scale(16, dpi_), Scale(16, dpi_));
    SelectObject(buffer, old_brush);
    SelectObject(buffer, old_pen);
    DeleteObject(sheen);

    SetBkMode(buffer, TRANSPARENT);
    HFONT font = CreateCandidateFont(dpi_);
    HGDIOBJ previous = SelectObject(buffer, font);
    const int horizontal_padding = Scale(12, dpi_);
    int x = Scale(8, dpi_);
    for (size_t index = 0; index < items_.size(); ++index) {
        const std::wstring number = std::to_wstring(index + 1);
        SIZE number_size{};
        SIZE text_size{};
        SIZE comment_size{};
        GetTextExtentPoint32W(buffer, number.c_str(),
                              static_cast<int>(number.size()), &number_size);
        GetTextExtentPoint32W(buffer, items_[index].text.c_str(),
                              static_cast<int>(items_[index].text.size()),
                              &text_size);
        if (!items_[index].comment.empty()) {
            GetTextExtentPoint32W(buffer, items_[index].comment.c_str(),
                                  static_cast<int>(items_[index].comment.size()),
                                  &comment_size);
        }
        const int comment_gap = items_[index].comment.empty() ? 0 : Scale(8, dpi_);
        const int item_width = horizontal_padding * 2 + number_size.cx +
                               Scale(7, dpi_) + text_size.cx + comment_gap +
                               comment_size.cx;
        RECT item_rect{x, Scale(5, dpi_),
                       std::min<LONG>(client.right, x + item_width),
                       client.bottom - Scale(5, dpi_)};
        if (index == highlighted_) {
            const int saved = SaveDC(buffer);
            HRGN clip = CreateRoundRectRgn(
                item_rect.left, item_rect.top, item_rect.right,
                item_rect.bottom, Scale(12, dpi_), Scale(12, dpi_));
            SelectClipRgn(buffer, clip);
            FillGlassGradient(buffer, item_rect, palette.highlight,
                              palette.highlight_bottom);
            RestoreDC(buffer, saved);
            DeleteObject(clip);
            HPEN rim = CreatePen(PS_SOLID, 1, palette.sheen);
            HGDIOBJ saved_pen = SelectObject(buffer, rim);
            HGDIOBJ saved_brush = SelectObject(buffer, GetStockObject(NULL_BRUSH));
            RoundRect(buffer, item_rect.left, item_rect.top,
                      item_rect.right, item_rect.bottom,
                      Scale(12, dpi_), Scale(12, dpi_));
            SelectObject(buffer, saved_brush);
            SelectObject(buffer, saved_pen);
            DeleteObject(rim);
            RECT accent{item_rect.left, item_rect.top + Scale(8, dpi_),
                        item_rect.left + Scale(4, dpi_),
                        item_rect.bottom - Scale(8, dpi_)};
            HBRUSH accent_brush = CreateSolidBrush(palette.accent);
            FillRect(buffer, &accent, accent_brush);
            DeleteObject(accent_brush);
        }

        RECT number_rect = item_rect;
        number_rect.left += horizontal_padding;
        number_rect.right = number_rect.left + number_size.cx;
        SetTextColor(buffer, palette.secondary);
        DrawTextW(buffer, number.c_str(), -1, &number_rect,
                  DT_SINGLELINE | DT_VCENTER | DT_NOPREFIX);

        RECT text_rect = item_rect;
        text_rect.left = number_rect.right + Scale(7, dpi_);
        text_rect.right = text_rect.left + text_size.cx;
        SetTextColor(buffer, palette.foreground);
        DrawTextW(buffer, items_[index].text.c_str(), -1, &text_rect,
                  DT_SINGLELINE | DT_VCENTER | DT_NOPREFIX);
        if (!items_[index].comment.empty()) {
            RECT comment_rect = item_rect;
            comment_rect.left = text_rect.right + comment_gap;
            SetTextColor(buffer, palette.secondary);
            DrawTextW(buffer, items_[index].comment.c_str(), -1, &comment_rect,
                      DT_SINGLELINE | DT_VCENTER | DT_NOPREFIX);
        }
        x += item_width;
    }

    if (page_count_ > 1) {
        const int controls_left = client.right - Scale(92, dpi_);
        HPEN divider = CreatePen(PS_SOLID, Scale(1, dpi_), palette.divider);
        HGDIOBJ previous_pen = SelectObject(buffer, divider);
        MoveToEx(buffer, controls_left, Scale(7, dpi_), nullptr);
        LineTo(buffer, controls_left, client.bottom - Scale(7, dpi_));
        SelectObject(buffer, previous_pen);
        DeleteObject(divider);

        const auto draw_triangle = [&](int center_x, bool points_right,
                                       bool enabled) {
            const int radius = Scale(5, dpi_);
            POINT triangle[3]{};
            if (points_right) {
                triangle[0] = {center_x - radius, client.bottom / 2 - radius};
                triangle[1] = {center_x - radius, client.bottom / 2 + radius};
                triangle[2] = {center_x + radius, client.bottom / 2};
            } else {
                triangle[0] = {center_x + radius, client.bottom / 2 - radius};
                triangle[1] = {center_x + radius, client.bottom / 2 + radius};
                triangle[2] = {center_x - radius, client.bottom / 2};
            }
            const COLORREF color = enabled ? palette.foreground : palette.disabled;
            HBRUSH brush = CreateSolidBrush(color);
            HPEN pen = CreatePen(PS_SOLID, 1, color);
            HGDIOBJ saved_brush = SelectObject(buffer, brush);
            HGDIOBJ saved_pen = SelectObject(buffer, pen);
            Polygon(buffer, triangle, 3);
            SelectObject(buffer, saved_pen);
            SelectObject(buffer, saved_brush);
            DeleteObject(pen);
            DeleteObject(brush);
        };
        draw_triangle(controls_left + Scale(24, dpi_), false, page_ > 0);
        draw_triangle(controls_left + Scale(61, dpi_), true,
                      page_ + 1 < page_count_);
    }

    SelectObject(buffer, previous);
    DeleteObject(font);
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
    if (message == WM_NCHITTEST) {
        return HTTRANSPARENT;
    }
    if (message == WM_ERASEBKGND) return 1;
    return DefWindowProcW(window, message, w_param, l_param);
}
#endif
