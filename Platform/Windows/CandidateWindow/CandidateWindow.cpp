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
constexpr COLORREF kBackground = RGB(43, 43, 43);
constexpr COLORREF kHighlight = RGB(57, 57, 57);
constexpr COLORREF kBorder = RGB(103, 103, 103);
constexpr COLORREF kDivider = RGB(72, 72, 72);
constexpr COLORREF kAccent = RGB(255, 112, 88);
constexpr COLORREF kForeground = RGB(244, 244, 244);
constexpr COLORREF kSecondary = RGB(196, 196, 196);
constexpr COLORREF kDisabled = RGB(112, 112, 112);

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

bool CandidateWindow::Create(HINSTANCE instance) {
    if (hwnd_) {
        return true;
    }
    WNDCLASSW window_class{};
    window_class.lpfnWndProc = &CandidateWindow::WndProc;
    window_class.hInstance = instance;
    window_class.hCursor = LoadCursorW(nullptr, MAKEINTRESOURCEW(32512));
    window_class.hbrBackground = nullptr;
    window_class.lpszClassName = kWindowClass;
    RegisterClassW(&window_class);
    hwnd_ = CreateWindowExW(
        WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE | WS_EX_TOPMOST, kWindowClass,
        L"WindWhisper candidates", WS_POPUP, 0, 0, 1, 1, nullptr, nullptr,
        instance, this);
    return hwnd_ != nullptr;
}

CandidateWindow::~CandidateWindow() {
    if (hwnd_) {
        DestroyWindow(hwnd_);
        hwnd_ = nullptr;
    }
}

void CandidateWindow::ShowAt(
    POINT point, UINT dpi, const std::vector<CandidateWindowItem> &items,
    size_t highlighted, size_t page, size_t page_count) {
    if (!hwnd_) {
        return;
    }
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
    const int radius = Scale(12, dpi_);
    SetWindowRgn(hwnd_, CreateRoundRectRgn(0, 0, width + 1, height + 1,
                                           radius, radius), FALSE);
    SetWindowPos(hwnd_, HWND_TOPMOST, point.x, point.y, width, height,
                 SWP_NOACTIVATE | SWP_SHOWWINDOW);
    InvalidateRect(hwnd_, nullptr, FALSE);
}

void CandidateWindow::Hide() {
    if (hwnd_) {
        ShowWindow(hwnd_, SW_HIDE);
        items_.clear();
    }
}

void CandidateWindow::Paint(HDC dc) {
    RECT client{};
    GetClientRect(hwnd_, &client);
    HDC buffer = CreateCompatibleDC(dc);
    HBITMAP bitmap = CreateCompatibleBitmap(
        dc, std::max<LONG>(1, client.right), std::max<LONG>(1, client.bottom));
    HGDIOBJ old_bitmap = SelectObject(buffer, bitmap);

    HBRUSH background = CreateSolidBrush(kBackground);
    FillRect(buffer, &client, background);
    DeleteObject(background);
    HPEN border = CreatePen(PS_SOLID, Scale(1, dpi_), kBorder);
    HGDIOBJ old_pen = SelectObject(buffer, border);
    HGDIOBJ old_brush = SelectObject(buffer, GetStockObject(NULL_BRUSH));
    RoundRect(buffer, 0, 0, client.right, client.bottom,
              Scale(12, dpi_), Scale(12, dpi_));
    SelectObject(buffer, old_brush);
    SelectObject(buffer, old_pen);
    DeleteObject(border);

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
            HBRUSH highlight = CreateSolidBrush(kHighlight);
            FillRect(buffer, &item_rect, highlight);
            DeleteObject(highlight);
            RECT accent{item_rect.left, item_rect.top + Scale(8, dpi_),
                        item_rect.left + Scale(4, dpi_),
                        item_rect.bottom - Scale(8, dpi_)};
            HBRUSH accent_brush = CreateSolidBrush(kAccent);
            FillRect(buffer, &accent, accent_brush);
            DeleteObject(accent_brush);
        }

        RECT number_rect = item_rect;
        number_rect.left += horizontal_padding;
        number_rect.right = number_rect.left + number_size.cx;
        SetTextColor(buffer, kSecondary);
        DrawTextW(buffer, number.c_str(), -1, &number_rect,
                  DT_SINGLELINE | DT_VCENTER | DT_NOPREFIX);

        RECT text_rect = item_rect;
        text_rect.left = number_rect.right + Scale(7, dpi_);
        text_rect.right = text_rect.left + text_size.cx;
        SetTextColor(buffer, kForeground);
        DrawTextW(buffer, items_[index].text.c_str(), -1, &text_rect,
                  DT_SINGLELINE | DT_VCENTER | DT_NOPREFIX);
        if (!items_[index].comment.empty()) {
            RECT comment_rect = item_rect;
            comment_rect.left = text_rect.right + comment_gap;
            SetTextColor(buffer, kSecondary);
            DrawTextW(buffer, items_[index].comment.c_str(), -1, &comment_rect,
                      DT_SINGLELINE | DT_VCENTER | DT_NOPREFIX);
        }
        x += item_width;
    }

    if (page_count_ > 1) {
        const int controls_left = client.right - Scale(92, dpi_);
        HPEN divider = CreatePen(PS_SOLID, Scale(1, dpi_), kDivider);
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
            HBRUSH brush = CreateSolidBrush(enabled ? kForeground : kDisabled);
            HPEN pen = CreatePen(PS_SOLID, 1, enabled ? kForeground : kDisabled);
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
    return DefWindowProcW(window, message, w_param, l_param);
}
#endif
