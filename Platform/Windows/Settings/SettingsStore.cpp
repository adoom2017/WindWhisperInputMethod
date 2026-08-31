#include "SettingsStore.h"
#ifdef _WIN32
#include <windows.h>
namespace fengyu { std::wstring DataDirectory(){wchar_t p[MAX_PATH]{};DWORD n=GetEnvironmentVariableW(L"LOCALAPPDATA",p,MAX_PATH);return std::wstring(p,n)+L"\\WindWhisper\\InputMethod";} bool SetTraditional(bool v){HKEY k{};if(RegCreateKeyExW(HKEY_CURRENT_USER,L"Software\\WindWhisper\\InputMethod",0,nullptr,0,KEY_WRITE,nullptr,&k,nullptr)!=ERROR_SUCCESS)return false;DWORD x=v;auto e=RegSetValueExW(k,L"Traditional",0,REG_DWORD,(BYTE*)&x,sizeof x);RegCloseKey(k);return e==ERROR_SUCCESS;} bool Traditional(){HKEY k{};DWORD x=0,n=sizeof x; if(RegOpenKeyExW(HKEY_CURRENT_USER,L"Software\\WindWhisper\\InputMethod",0,KEY_READ,&k)!=ERROR_SUCCESS)return false;RegQueryValueExW(k,L"Traditional",nullptr,nullptr,(BYTE*)&x,&n);RegCloseKey(k);return x!=0;} }
#endif
