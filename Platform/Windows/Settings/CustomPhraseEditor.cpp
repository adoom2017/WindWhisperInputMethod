#include "CustomPhraseEditor.h"
#include "CustomPhraseStore.h"

#ifdef _WIN32
#include <commctrl.h>
#include <commdlg.h>

#include <charconv>
#include <iterator>
#include <string>
#include <tuple>

namespace fengyu {
namespace {

constexpr wchar_t kEditorClass[] = L"WindWhisperCustomPhraseEditor";
constexpr int kList = 1001;
constexpr int kText = 1002;
constexpr int kCode = 1003;
constexpr int kWeight = 1004;
constexpr int kNew = 1005;
constexpr int kApply = 1006;
constexpr int kDelete = 1007;
constexpr int kSave = 1008;
constexpr int kCancel = 1009;
constexpr int kStatus = 1010;
constexpr int kImport = 1011;
constexpr int kExport = 1012;

struct EditorState {
    std::filesystem::path path;
    CustomPhraseDocument document;
    HWND window = nullptr;
    HWND list = nullptr;
    HWND text = nullptr;
    HWND code = nullptr;
    HWND weight = nullptr;
    HWND apply = nullptr;
    HWND remove = nullptr;
    HWND status = nullptr;
    HFONT font = nullptr;
    int selected = -1;
    bool dirty = false;
    bool form_dirty = false;
    bool suppress_changes = false;
    bool suppress_selection = false;
    bool status_error = false;
    CustomPhraseEditorResult result = CustomPhraseEditorResult::Cancelled;
};

std::wstring ControlText(HWND control) {
    const int length = GetWindowTextLengthW(control);
    std::wstring value(static_cast<size_t>(length) + 1, L'\0');
    if (length > 0) GetWindowTextW(control, value.data(), length + 1);
    value.resize(static_cast<size_t>(length));
    return value;
}

std::string AsciiFromWide(const std::wstring &value) {
    std::string result;
    result.reserve(value.size());
    for (wchar_t character : value) {
        if (character > 0x7f) return {};
        result.push_back(static_cast<char>(character));
    }
    return result;
}

void SetStatus(EditorState *state, const std::wstring &message, bool error) {
    if (!state || !state->status) return;
    state->status_error = error;
    SetWindowTextW(state->status, message.c_str());
    InvalidateRect(state->status, nullptr, TRUE);
    if (error) MessageBeep(MB_ICONWARNING);
}

void SelectRow(EditorState *state, int row) {
    if (!state || !state->list) return;
    state->suppress_selection = true;
    ListView_SetItemState(state->list, -1, 0,
                          LVIS_SELECTED | LVIS_FOCUSED);
    if (row >= 0) {
        ListView_SetItemState(state->list, row,
                              LVIS_SELECTED | LVIS_FOCUSED,
                              LVIS_SELECTED | LVIS_FOCUSED);
        ListView_EnsureVisible(state->list, row, FALSE);
    }
    state->suppress_selection = false;
}

void PopulateForm(EditorState *state, int row) {
    if (!state) return;
    state->suppress_changes = true;
    state->selected = row;
    if (row >= 0 && static_cast<size_t>(row) < state->document.entries.size()) {
        const CustomPhrase &entry = state->document.entries[row];
        SetWindowTextW(state->text, entry.text.c_str());
        const std::wstring code(entry.code.begin(), entry.code.end());
        SetWindowTextW(state->code, code.c_str());
        const std::wstring weight =
            entry.weight ? std::to_wstring(*entry.weight) : L"";
        SetWindowTextW(state->weight, weight.c_str());
        SetWindowTextW(state->apply, L"更新词组");
        EnableWindow(state->remove, TRUE);
    } else {
        SetWindowTextW(state->text, L"");
        SetWindowTextW(state->code, L"");
        SetWindowTextW(state->weight, L"");
        SetWindowTextW(state->apply, L"添加词组");
        EnableWindow(state->remove, FALSE);
    }
    state->form_dirty = false;
    state->suppress_changes = false;
}

void SetListItemText(HWND list, int row, int column,
                     const std::wstring &text) {
    LVITEMW item{};
    item.iSubItem = column;
    item.pszText = const_cast<wchar_t *>(text.c_str());
    SendMessageW(list, LVM_SETITEMTEXTW, static_cast<WPARAM>(row),
                 reinterpret_cast<LPARAM>(&item));
}

void RefreshList(EditorState *state) {
    if (!state || !state->list) return;
    ListView_DeleteAllItems(state->list);
    for (size_t index = 0; index < state->document.entries.size(); ++index) {
        const CustomPhrase &entry = state->document.entries[index];
        LVITEMW item{};
        item.mask = LVIF_TEXT;
        item.iItem = static_cast<int>(index);
        item.pszText = const_cast<wchar_t *>(entry.text.c_str());
        SendMessageW(state->list, LVM_INSERTITEMW, 0,
                     reinterpret_cast<LPARAM>(&item));
        const std::wstring code(entry.code.begin(), entry.code.end());
        SetListItemText(state->list, static_cast<int>(index), 1, code);
        const std::wstring weight =
            entry.weight ? std::to_wstring(*entry.weight) : L"自动";
        SetListItemText(state->list, static_cast<int>(index), 2, weight);
    }
    if (state->document.entries.empty()) {
        SetStatus(state, L"暂无自定义词组。点击“新增”开始添加。", false);
    } else {
        SetStatus(state,
                  L"共 " + std::to_wstring(state->document.entries.size()) +
                      L" 个自定义词组。",
                  false);
    }
}

bool ReadForm(EditorState *state, CustomPhrase *entry,
              std::wstring *error_message) {
    if (!state || !entry) return false;
    entry->text = ControlText(state->text);
    const std::wstring wide_code = ControlText(state->code);
    entry->code = AsciiFromWide(wide_code);
    if (entry->code.empty() && !wide_code.empty()) {
        if (error_message) *error_message = L"编码只能包含英文字母和撇号。";
        return false;
    }
    const std::wstring wide_weight = ControlText(state->weight);
    if (!wide_weight.empty()) {
        const std::string weight = AsciiFromWide(wide_weight);
        int value = 0;
        const auto parsed = std::from_chars(
            weight.data(), weight.data() + weight.size(), value);
        if (weight.empty() || parsed.ec != std::errc{} ||
            parsed.ptr != weight.data() + weight.size() || value < 0) {
            if (error_message) {
                *error_message = L"权重必须留空或填写非负整数。";
            }
            return false;
        }
        entry->weight = value;
    }
    return true;
}

bool ApplyForm(EditorState *state) {
    CustomPhrase entry;
    std::wstring error;
    if (!ReadForm(state, &entry, &error)) {
        SetStatus(state, error + L" 请修改后重试。", true);
        SetFocus(state->code);
        return false;
    }
    CustomPhraseDocument updated = state->document;
    const bool replacing = state->selected >= 0 &&
                           static_cast<size_t>(state->selected) <
                               updated.entries.size();
    if (replacing) {
        updated.entries[state->selected] = std::move(entry);
    } else {
        updated.entries.push_back(std::move(entry));
    }
    if (!NormalizeCustomPhrases(&updated, &error)) {
        SetStatus(state, error + L" 请修改后重试。", true);
        return false;
    }
    state->document = std::move(updated);
    state->selected = replacing
                          ? state->selected
                          : static_cast<int>(state->document.entries.size() - 1);
    state->dirty = true;
    state->form_dirty = false;
    RefreshList(state);
    SelectRow(state, state->selected);
    PopulateForm(state, state->selected);
    SetStatus(state, replacing ? L"词组已更新，点击“保存并应用”完成保存。"
                               : L"词组已添加，点击“保存并应用”完成保存。",
              false);
    return true;
}

bool ConfirmDiscard(EditorState *state) {
    if (!state || (!state->dirty && !state->form_dirty)) return true;
    return MessageBoxW(
               state->window,
               L"关闭后，本次对自定义词组的修改不会保留。",
               L"放弃未保存的修改？",
               MB_ICONWARNING | MB_YESNO | MB_DEFBUTTON2) == IDYES;
}

bool ConfirmDiscardForm(EditorState *state) {
    if (!state || !state->form_dirty) return true;
    return MessageBoxW(
               state->window,
               L"当前表单中的修改尚未添加或更新，切换后将会丢失。",
               L"放弃当前编辑？",
               MB_ICONWARNING | MB_YESNO | MB_DEFBUTTON2) == IDYES;
}

bool ChoosePhraseFile(HWND owner, bool save, std::filesystem::path *path) {
    if (!path) return false;
    wchar_t file_name[32768]{};
    if (save) {
        wcscpy_s(file_name, std::size(file_name), L"custom_words.tsv");
    }
    OPENFILENAMEW dialog{};
    dialog.lStructSize = sizeof(dialog);
    dialog.hwndOwner = owner;
    dialog.lpstrFilter =
        L"自定义词库 (*.tsv)\0*.tsv\0所有文件 (*.*)\0*.*\0\0";
    dialog.lpstrFile = file_name;
    dialog.nMaxFile = static_cast<DWORD>(std::size(file_name));
    dialog.lpstrDefExt = L"tsv";
    dialog.lpstrTitle = save ? L"导出自定义词库"
                             : L"导入自定义词库";
    dialog.Flags = OFN_EXPLORER | OFN_PATHMUSTEXIST | OFN_NOCHANGEDIR |
                   (save ? OFN_OVERWRITEPROMPT : OFN_FILEMUSTEXIST);
    const BOOL selected = save ? GetSaveFileNameW(&dialog)
                               : GetOpenFileNameW(&dialog);
    if (!selected) {
        const DWORD error = CommDlgExtendedError();
        if (error != 0) {
            const std::wstring message =
                L"无法打开文件选择器（错误代码 " +
                std::to_wstring(error) + L"）。请重试。";
            MessageBoxW(owner, message.c_str(), L"自定义词库",
                        MB_OK | MB_ICONERROR);
        }
        return false;
    }
    *path = file_name;
    return true;
}

void ImportPhrases(EditorState *state) {
    if (!state || !ConfirmDiscardForm(state)) return;
    std::filesystem::path path;
    if (!ChoosePhraseFile(state->window, false, &path)) return;
    CustomPhraseDocument imported;
    std::wstring error;
    if (!LoadCustomPhrases(path, &imported, &error)) {
        MessageBoxW(state->window,
                    (error + L"\n\n请检查文件是否为 UTF-8 编码，并使用“词组<Tab>编码<Tab>可选权重”格式。").c_str(),
                    L"导入失败", MB_OK | MB_ICONERROR);
        return;
    }
    const std::wstring prompt =
        L"文件中共有 " + std::to_wstring(imported.entries.size()) +
        L" 个词组。\n\n选择“是”：合并到当前词库\n"
        L"选择“否”：用导入文件替换当前全部词组\n"
        L"选择“取消”：不做任何修改";
    const int choice = MessageBoxW(
        state->window, prompt.c_str(), L"选择导入方式",
        MB_ICONQUESTION | MB_YESNOCANCEL | MB_DEFBUTTON1);
    if (choice == IDCANCEL) return;

    std::wstring status;
    if (choice == IDYES) {
        CustomPhraseMergeResult summary;
        if (!MergeCustomPhrases(&state->document, std::move(imported),
                                &summary, &error)) {
            MessageBoxW(state->window, error.c_str(), L"导入失败",
                        MB_OK | MB_ICONERROR);
            return;
        }
        status = L"已合并：新增 " + std::to_wstring(summary.added) +
                 L" 个，更新 " + std::to_wstring(summary.updated) +
                 L" 个，跳过 " + std::to_wstring(summary.unchanged) +
                 L" 个。";
    } else {
        const size_t count = imported.entries.size();
        state->document = std::move(imported);
        status = L"已用导入文件替换列表，共 " +
                 std::to_wstring(count) + L" 个词组。";
    }
    state->dirty = true;
    PopulateForm(state, -1);
    RefreshList(state);
    SetStatus(state, status + L" 点击“保存并应用”完成保存。", false);
}

void ExportPhrases(EditorState *state) {
    if (!state) return;
    if (state->form_dirty && !ApplyForm(state)) return;
    std::filesystem::path path;
    if (!ChoosePhraseFile(state->window, true, &path)) return;
    std::wstring error;
    if (!SaveCustomPhrases(path, state->document, &error)) {
        MessageBoxW(state->window,
                    (error + L"\n\n请选择其他位置或检查文件写入权限。").c_str(),
                    L"导出失败", MB_OK | MB_ICONERROR);
        return;
    }
    SetStatus(state,
              L"已导出 " +
                  std::to_wstring(state->document.entries.size()) +
                  L" 个自定义词组。",
              false);
}

void SaveAndClose(EditorState *state) {
    if (!state) return;
    const bool has_form_value = GetWindowTextLengthW(state->text) > 0 ||
                                GetWindowTextLengthW(state->code) > 0 ||
                                GetWindowTextLengthW(state->weight) > 0;
    if ((state->form_dirty || (state->selected < 0 && has_form_value)) &&
        !ApplyForm(state)) {
        return;
    }
    std::wstring error;
    if (!SaveCustomPhrases(state->path, state->document, &error)) {
        SetStatus(state, error + L" 请检查文件权限后重试。", true);
        return;
    }
    state->dirty = false;
    state->form_dirty = false;
    state->result = CustomPhraseEditorResult::Saved;
    DestroyWindow(state->window);
}

void DeleteSelection(EditorState *state) {
    if (!state || state->selected < 0 ||
        static_cast<size_t>(state->selected) >= state->document.entries.size()) {
        return;
    }
    const CustomPhrase &entry = state->document.entries[state->selected];
    const std::wstring message = L"确定删除“" + entry.text + L"”吗？";
    if (MessageBoxW(state->window, message.c_str(), L"删除自定义词组",
                    MB_ICONWARNING | MB_YESNO | MB_DEFBUTTON2) != IDYES) {
        return;
    }
    state->document.entries.erase(state->document.entries.begin() +
                                  state->selected);
    state->dirty = true;
    state->selected = -1;
    RefreshList(state);
    PopulateForm(state, -1);
    SetStatus(state, L"词组已从列表删除，点击“保存并应用”完成保存。", false);
}

void SetFont(HWND control, HFONT font) {
    if (control) {
        SendMessageW(control, WM_SETFONT, reinterpret_cast<WPARAM>(font), TRUE);
    }
}

HWND AddControl(EditorState *state, DWORD extended_style,
                const wchar_t *class_name, const wchar_t *text, DWORD style,
                int x, int y, int width, int height, int id) {
    HWND control = CreateWindowExW(
        extended_style, class_name, text, WS_CHILD | WS_VISIBLE | style,
        x, y, width, height, state->window,
        reinterpret_cast<HMENU>(static_cast<INT_PTR>(id)),
        GetModuleHandleW(nullptr), nullptr);
    SetFont(control, state->font);
    return control;
}

void CreateControls(EditorState *state) {
    state->font = static_cast<HFONT>(GetStockObject(DEFAULT_GUI_FONT));
    AddControl(state, 0, L"STATIC", L"自定义词组", 0,
               20, 16, 160, 22, 0);
    state->list = AddControl(
        state, WS_EX_CLIENTEDGE, WC_LISTVIEWW, L"",
        LVS_REPORT | LVS_SINGLESEL | LVS_SHOWSELALWAYS | WS_TABSTOP,
        20, 42, 704, 258, kList);
    ListView_SetExtendedListViewStyle(
        state->list,
        LVS_EX_FULLROWSELECT | LVS_EX_GRIDLINES | LVS_EX_DOUBLEBUFFER);
    for (const auto &column : {
             std::tuple<int, int, const wchar_t *>{0, 315, L"词组"},
             std::tuple<int, int, const wchar_t *>{1, 235, L"编码"},
             std::tuple<int, int, const wchar_t *>{2, 130, L"权重"}}) {
        LVCOLUMNW value{};
        value.mask = LVCF_TEXT | LVCF_WIDTH | LVCF_SUBITEM;
        value.iSubItem = std::get<0>(column);
        value.cx = std::get<1>(column);
        value.pszText = const_cast<wchar_t *>(std::get<2>(column));
        SendMessageW(state->list, LVM_INSERTCOLUMNW,
                     static_cast<WPARAM>(value.iSubItem),
                     reinterpret_cast<LPARAM>(&value));
    }

    AddControl(state, 0, L"STATIC", L"词组", 0, 20, 316, 260, 20, 0);
    AddControl(state, 0, L"STATIC", L"编码", 0, 300, 316, 180, 20, 0);
    AddControl(state, 0, L"STATIC", L"权重（可选）", 0,
               500, 316, 180, 20, 0);
    state->text = AddControl(state, WS_EX_CLIENTEDGE, L"EDIT", L"",
                             ES_AUTOHSCROLL | WS_TABSTOP,
                             20, 338, 260, 28, kText);
    state->code = AddControl(state, WS_EX_CLIENTEDGE, L"EDIT", L"",
                             ES_AUTOHSCROLL | WS_TABSTOP,
                             300, 338, 180, 28, kCode);
    state->weight = AddControl(state, WS_EX_CLIENTEDGE, L"EDIT", L"",
                               ES_AUTOHSCROLL | ES_NUMBER | WS_TABSTOP,
                               500, 338, 224, 28, kWeight);

    AddControl(state, 0, L"BUTTON", L"新增", WS_TABSTOP,
               20, 382, 90, 30, kNew);
    state->apply = AddControl(state, 0, L"BUTTON", L"添加词组", WS_TABSTOP,
                              120, 382, 110, 30, kApply);
    state->remove = AddControl(state, 0, L"BUTTON", L"删除", WS_TABSTOP,
                               240, 382, 90, 30, kDelete);
    EnableWindow(state->remove, FALSE);
    AddControl(state, 0, L"BUTTON", L"导入", WS_TABSTOP,
               340, 382, 90, 30, kImport);
    AddControl(state, 0, L"BUTTON", L"导出", WS_TABSTOP,
               440, 382, 90, 30, kExport);
    AddControl(state, 0, L"STATIC",
               L"编码仅支持英文字母和撇号；权重越高，候选越靠前。",
               0, 20, 422, 704, 22, 0);
    state->status = AddControl(state, 0, L"STATIC", L"", SS_LEFT,
                               20, 452, 704, 40, kStatus);
    AddControl(state, 0, L"BUTTON", L"保存并应用",
               BS_DEFPUSHBUTTON | WS_TABSTOP,
               486, 508, 112, 32, kSave);
    AddControl(state, 0, L"BUTTON", L"取消", WS_TABSTOP,
               612, 508, 112, 32, kCancel);
    RefreshList(state);
}

LRESULT CALLBACK EditorWindowProc(HWND window, UINT message,
                                  WPARAM wparam, LPARAM lparam) {
    auto *state = reinterpret_cast<EditorState *>(
        GetWindowLongPtrW(window, GWLP_USERDATA));
    if (message == WM_NCCREATE) {
        const auto *create = reinterpret_cast<const CREATESTRUCTW *>(lparam);
        state = static_cast<EditorState *>(create->lpCreateParams);
        state->window = window;
        SetWindowLongPtrW(window, GWLP_USERDATA,
                          reinterpret_cast<LONG_PTR>(state));
    }
    if (!state) return DefWindowProcW(window, message, wparam, lparam);
    switch (message) {
    case WM_CREATE:
        CreateControls(state);
        return 0;
    case WM_COMMAND: {
        const int id = LOWORD(wparam);
        const int notification = HIWORD(wparam);
        if ((id == kText || id == kCode || id == kWeight) &&
            notification == EN_CHANGE && !state->suppress_changes) {
            state->form_dirty = true;
        } else if (id == kNew && notification == BN_CLICKED) {
            if (!ConfirmDiscardForm(state)) return 0;
            SelectRow(state, -1);
            PopulateForm(state, -1);
            SetStatus(state, L"填写词组和编码后，点击“添加词组”。", false);
            SetFocus(state->text);
        } else if (id == kApply && notification == BN_CLICKED) {
            ApplyForm(state);
        } else if (id == kDelete && notification == BN_CLICKED) {
            DeleteSelection(state);
        } else if (id == kImport && notification == BN_CLICKED) {
            ImportPhrases(state);
        } else if (id == kExport && notification == BN_CLICKED) {
            ExportPhrases(state);
        } else if (id == kSave && notification == BN_CLICKED) {
            SaveAndClose(state);
        } else if (id == kCancel && notification == BN_CLICKED) {
            SendMessageW(window, WM_CLOSE, 0, 0);
        }
        return 0;
    }
    case WM_NOTIFY: {
        const auto *notification = reinterpret_cast<const NMHDR *>(lparam);
        if (notification && notification->idFrom == kList &&
            notification->code == LVN_ITEMCHANGED &&
            !state->suppress_selection) {
            const auto *change = reinterpret_cast<const NMLISTVIEW *>(lparam);
            if ((change->uChanged & LVIF_STATE) != 0 &&
                (change->uNewState & LVIS_SELECTED) != 0 &&
                change->iItem != state->selected) {
                if (!ConfirmDiscardForm(state)) {
                    SelectRow(state, state->selected);
                } else {
                    PopulateForm(state, change->iItem);
                }
            }
        }
        return 0;
    }
    case WM_CTLCOLORSTATIC:
        if (reinterpret_cast<HWND>(lparam) == state->status &&
            state->status_error) {
            SetTextColor(reinterpret_cast<HDC>(wparam), RGB(185, 28, 28));
            SetBkMode(reinterpret_cast<HDC>(wparam), TRANSPARENT);
            return reinterpret_cast<LRESULT>(GetSysColorBrush(COLOR_WINDOW));
        }
        break;
    case WM_CLOSE:
        if (ConfirmDiscard(state)) DestroyWindow(window);
        return 0;
    default:
        break;
    }
    return DefWindowProcW(window, message, wparam, lparam);
}

bool EnsureEditorClass() {
    static ATOM atom = 0;
    if (atom) return true;
    WNDCLASSW window_class{};
    window_class.lpfnWndProc = EditorWindowProc;
    window_class.hInstance = GetModuleHandleW(nullptr);
    window_class.hIcon =
        LoadIconW(nullptr, MAKEINTRESOURCEW(32512));  // IDI_APPLICATION
    window_class.hCursor =
        LoadCursorW(nullptr, MAKEINTRESOURCEW(32512));  // IDC_ARROW
    window_class.hbrBackground = GetSysColorBrush(COLOR_WINDOW);
    window_class.lpszClassName = kEditorClass;
    atom = RegisterClassW(&window_class);
    return atom != 0 || GetLastError() == ERROR_CLASS_ALREADY_EXISTS;
}

}  // namespace

CustomPhraseEditorResult ShowCustomPhraseEditor(HWND owner) {
    INITCOMMONCONTROLSEX controls{sizeof(controls), ICC_LISTVIEW_CLASSES};
    InitCommonControlsEx(&controls);
    EditorState state;
    state.path = CustomPhraseFilePath();
    std::wstring error;
    if (!LoadCustomPhrases(state.path, &state.document, &error)) {
        MessageBoxW(owner, error.c_str(), L"无法打开自定义词组",
                    MB_OK | MB_ICONERROR);
        return CustomPhraseEditorResult::Cancelled;
    }
    if (!EnsureEditorClass()) {
        MessageBoxW(owner, L"无法创建自定义词组管理窗口。",
                    L"风语输入法", MB_OK | MB_ICONERROR);
        return CustomPhraseEditorResult::Cancelled;
    }
    const HWND window = CreateWindowExW(
        WS_EX_DLGMODALFRAME | WS_EX_CONTROLPARENT, kEditorClass,
        L"管理自定义词组", WS_CAPTION | WS_SYSMENU,
        CW_USEDEFAULT, CW_USEDEFAULT, 760, 600, owner, nullptr,
        GetModuleHandleW(nullptr), &state);
    if (!window) return CustomPhraseEditorResult::Cancelled;

    RECT owner_bounds{};
    RECT window_bounds{};
    GetWindowRect(owner && IsWindow(owner) ? owner : GetDesktopWindow(),
                  &owner_bounds);
    GetWindowRect(window, &window_bounds);
    SetWindowPos(
        window, HWND_TOP,
        owner_bounds.left +
            ((owner_bounds.right - owner_bounds.left) -
             (window_bounds.right - window_bounds.left)) /
                2,
        owner_bounds.top +
            ((owner_bounds.bottom - owner_bounds.top) -
             (window_bounds.bottom - window_bounds.top)) /
                2,
        0, 0, SWP_NOSIZE);
    if (owner && IsWindow(owner)) EnableWindow(owner, FALSE);
    ShowWindow(window, SW_SHOW);
    UpdateWindow(window);
    MSG message{};
    while (IsWindow(window) && GetMessageW(&message, nullptr, 0, 0) > 0) {
        if (message.message == WM_KEYDOWN && message.wParam == VK_ESCAPE) {
            SendMessageW(window, WM_CLOSE, 0, 0);
            continue;
        }
        if (!IsDialogMessageW(window, &message)) {
            TranslateMessage(&message);
            DispatchMessageW(&message);
        }
    }
    if (owner && IsWindow(owner)) {
        EnableWindow(owner, TRUE);
        SetForegroundWindow(owner);
    }
    return state.result;
}

}  // namespace fengyu
#endif
