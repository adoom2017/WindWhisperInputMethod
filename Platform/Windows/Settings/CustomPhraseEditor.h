#pragma once

#ifdef _WIN32
#include <windows.h>

namespace fengyu {

enum class CustomPhraseEditorResult { Cancelled, Saved };
CustomPhraseEditorResult ShowCustomPhraseEditor(HWND owner);

}  // namespace fengyu
#endif
