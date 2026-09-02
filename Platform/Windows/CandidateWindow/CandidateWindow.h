#pragma once
#ifdef _WIN32
#include <windows.h>
#include <string>
#include <vector>

struct CandidateWindowItem {
    std::wstring text;
    std::wstring comment;
};

enum class CandidateWindowTheme {
    Dark,
    Light,
};

class CandidateWindow final {
public:
    bool Create(HINSTANCE);
    void SetTheme(CandidateWindowTheme);
    void ShowAt(POINT, UINT dpi, const std::vector<CandidateWindowItem>&,
                size_t highlighted, size_t page, size_t page_count);
    void Hide();
    HWND hwnd() const { return hwnd_; }
    ~CandidateWindow();

private:
    static LRESULT CALLBACK WndProc(HWND, UINT, WPARAM, LPARAM);
    void Paint(HDC);

    HWND hwnd_{};
    UINT dpi_ = 96;
    size_t highlighted_ = 0;
    size_t page_ = 0;
    size_t page_count_ = 0;
    CandidateWindowTheme theme_ = CandidateWindowTheme::Dark;
    std::vector<CandidateWindowItem> items_;
};
#endif
