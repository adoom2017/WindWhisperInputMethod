#pragma once
#ifdef _WIN32
#include <windows.h>
class CandidateWindow final { public: bool Create(HINSTANCE); void ShowAt(POINT, UINT dpi); void Hide(); HWND hwnd() const { return hwnd_; } private: HWND hwnd_{}; };
#endif
