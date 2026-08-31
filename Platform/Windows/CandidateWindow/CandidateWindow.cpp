#include "CandidateWindow.h"
#ifdef _WIN32
bool CandidateWindow::Create(HINSTANCE instance){ hwnd_=CreateWindowExW(WS_EX_TOOLWINDOW|WS_EX_NOACTIVATE,L"STATIC",L"",WS_POPUP,0,0,1,1,nullptr,nullptr,instance,nullptr); return hwnd_!=nullptr; }
void CandidateWindow::ShowAt(POINT p,UINT dpi){if(!hwnd_)return; int w=240*dpi/96; SetWindowPos(hwnd_,HWND_TOPMOST,p.x,p.y,w,32,SWP_NOACTIVATE|SWP_SHOWWINDOW);} void CandidateWindow::Hide(){if(hwnd_)ShowWindow(hwnd_,SW_HIDE);}
#endif
