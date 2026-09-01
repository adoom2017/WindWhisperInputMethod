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
constexpr COLORREF kBackground = RGB(32, 34, 38);
constexpr COLORREF kHighlight = RGB(58, 105, 170);
constexpr COLORREF kForeground = RGB(245, 245, 245);
constexpr COLORREF kComment = RGB(180, 185, 195);
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
    const int scale = static_cast<int>(dpi_) ;
    const int row_height = std::max(24, 28 * scale / 96);
    int width = 220 * scale / 96;
    HDC dc = GetDC(hwnd_);
    if (dc) {
        HFONT font = static_cast<HFONT>(GetStockObject(DEFAULT_GUI_FONT));
        HGDIOBJ previous = SelectObject(dc, font);
        for (const auto &item : items_) {
            SIZE size{};
            GetTextExtentPoint32W(dc, item.text.c_str(),
                                  static_cast<int>(item.text.size()), &size);
            width = std::max<int>(width, size.cx + 110 * scale / 96);
        }
        SelectObject(dc, previous);
        ReleaseDC(hwnd_, dc);
    }
    const int height = std::max(1, static_cast<int>(items_.size())) * row_height +
                       (page_count_ > 1 ? 24 * scale / 96 : 8 * scale / 96);
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
    HBRUSH background = CreateSolidBrush(kBackground);
    FillRect(dc, &client, background);
    DeleteObject(background);
    SetBkMode(dc, TRANSPARENT);
    HFONT font = static_cast<HFONT>(GetStockObject(DEFAULT_GUI_FONT));
    HGDIOBJ previous = SelectObject(dc, font);
    const int scale = static_cast<int>(dpi_);
    const int row_height = std::max(24, 28 * scale / 96);
    for (size_t index = 0; index < items_.size(); ++index) {
        RECT row{0, static_cast<LONG>(index * row_height), client.right,
                 static_cast<LONG>((index + 1) * row_height)};
        if (index == highlighted_) {
            HBRUSH highlight = CreateSolidBrush(kHighlight);
            FillRect(dc, &row, highlight);
            DeleteObject(highlight);
        }
        SetTextColor(dc, kForeground);
        std::wstring label = std::to_wstring(index + 1) + L"  " + items_[index].text;
        RECT text = row;
        text.left += 8 * scale / 96;
        DrawTextW(dc, label.c_str(), -1, &text,
                  DT_SINGLELINE | DT_VCENTER | DT_NOPREFIX);
        if (!items_[index].comment.empty()) {
            SetTextColor(dc, kComment);
            RECT comment = row;
            comment.right -= 8 * scale / 96;
            DrawTextW(dc, items_[index].comment.c_str(), -1, &comment,
                      DT_SINGLELINE | DT_VCENTER | DT_RIGHT | DT_NOPREFIX);
        }
    }
    if (page_count_ > 1) {
        SetTextColor(dc, kComment);
        RECT footer{8 * scale / 96,
                    static_cast<LONG>(items_.size() * row_height), client.right,
                    client.bottom};
        std::wstring page = std::to_wstring(page_ + 1) + L"/" +
                            std::to_wstring(page_count_);
        DrawTextW(dc, page.c_str(), -1, &footer,
                  DT_SINGLELINE | DT_VCENTER | DT_RIGHT | DT_NOPREFIX);
    }
    SelectObject(dc, previous);
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
