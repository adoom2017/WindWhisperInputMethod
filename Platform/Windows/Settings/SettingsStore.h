#pragma once
#ifdef _WIN32
#include <string>
namespace fengyu { std::wstring DataDirectory(); bool SetTraditional(bool); bool Traditional(); }
#endif
