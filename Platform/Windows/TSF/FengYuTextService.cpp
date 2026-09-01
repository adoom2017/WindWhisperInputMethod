#include "FengYuTextService.h"
#include "../CandidateWindow/CandidateWindow.h"
#include "WindowsKeyMapper.h"
#include "fy_engine.h"

#ifdef _WIN32
#include <ctffunc.h>
#include <olectl.h>
#include <algorithm>
#include <cstring>
#include <fstream>
#include <filesystem>
#include <memory>
#include <string>
#include <strsafe.h>
#include <unordered_map>
#include <utility>
#include <vector>

namespace {
volatile LONG g_object_count = 0;
volatile LONG g_server_lock_count = 0;

constexpr wchar_t kSettingsPath[] = L"Software\\WindWhisper\\InputMethod";
constexpr wchar_t kSchemaValue[] = L"Schema";

std::string ReadConfiguredSchema() {
    HKEY key = nullptr;
    if (RegOpenKeyExW(HKEY_CURRENT_USER, kSettingsPath, 0, KEY_READ, &key) !=
        ERROR_SUCCESS) {
        return "flypyShape";
    }
    wchar_t value[64]{};
    DWORD type = 0;
    DWORD bytes = sizeof(value);
    const LONG result = RegQueryValueExW(
        key, kSchemaValue, nullptr, &type, reinterpret_cast<BYTE *>(value),
        &bytes);
    RegCloseKey(key);
    if (result != ERROR_SUCCESS || type != REG_SZ || value[0] == L'\0') {
        return "flypyShape";
    }
    if (wcscmp(value, L"flypyPhonetic") == 0) return "flypyPhonetic";
    if (wcscmp(value, L"fullPinyin") == 0) return "fullPinyin";
    if (wcscmp(value, L"flypyShape") == 0) return "flypyShape";
    return "flypyShape";
}

bool WriteConfiguredSchema(const char *schema) {
    if (!schema || (std::strcmp(schema, "flypyShape") != 0 &&
                    std::strcmp(schema, "flypyPhonetic") != 0 &&
                    std::strcmp(schema, "fullPinyin") != 0)) {
        return false;
    }
    const int length = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS,
                                           schema, -1, nullptr, 0);
    if (length <= 0) return false;
    std::wstring wide(static_cast<size_t>(length), L'\0');
    if (MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, schema, -1,
                            wide.data(), length) != length) {
        return false;
    }
    HKEY key = nullptr;
    if (RegCreateKeyExW(HKEY_CURRENT_USER, kSettingsPath, 0, nullptr, 0,
                        KEY_WRITE, nullptr, &key, nullptr) != ERROR_SUCCESS) {
        return false;
    }
    const LONG result = RegSetValueExW(
        key, kSchemaValue, 0, REG_SZ, reinterpret_cast<const BYTE *>(wide.c_str()),
        static_cast<DWORD>(wide.size() * sizeof(wchar_t)));
    RegCloseKey(key);
    return result == ERROR_SUCCESS;
}

void DebugLog(const char *event, HRESULT result = S_OK, WPARAM virtual_key = 0,
              BOOL eaten = FALSE) {
    wchar_t local_app_data[32768]{};
    const DWORD length = GetEnvironmentVariableW(
        L"LOCALAPPDATA", local_app_data,
        static_cast<DWORD>(std::size(local_app_data)));
    if (length == 0 || length >= std::size(local_app_data)) {
        return;
    }
    std::wstring directory(local_app_data, length);
    directory += L"\\WindWhisper\\InputMethod";
    const auto parent = directory.substr(0, directory.find_last_of(L'\\'));
    CreateDirectoryW(parent.c_str(), nullptr);
    CreateDirectoryW(directory.c_str(), nullptr);
    const std::wstring path = directory + L"\\tsf-debug.log";
    HANDLE file = CreateFileW(path.c_str(), FILE_APPEND_DATA,
                              FILE_SHARE_READ | FILE_SHARE_WRITE, nullptr,
                              OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
    if (file == INVALID_HANDLE_VALUE) {
        return;
    }
    char line[256]{};
    _snprintf_s(line, sizeof(line), _TRUNCATE,
                "%s hr=0x%08lX vk=%llu eaten=%d\r\n", event,
                static_cast<unsigned long>(result),
                static_cast<unsigned long long>(virtual_key), eaten ? 1 : 0);
    DWORD written = 0;
    WriteFile(file, line, static_cast<DWORD>(std::strlen(line)), &written,
              nullptr);
    CloseHandle(file);
}

std::wstring Utf8ToWide(const char *text, size_t length) {
    if (!text || length == 0 || length > static_cast<size_t>(INT_MAX)) {
        return {};
    }
    const int wide_length = MultiByteToWideChar(
        CP_UTF8, MB_ERR_INVALID_CHARS, text, static_cast<int>(length), nullptr, 0);
    if (wide_length <= 0) {
        return {};
    }
    std::wstring result(static_cast<size_t>(wide_length), L'\0');
    if (MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, text,
                            static_cast<int>(length), result.data(),
                            wide_length) != wide_length) {
        return {};
    }
    return result;
}

bool KeyStateDown(int virtual_key) {
    return (GetKeyState(virtual_key) & 0x8000) != 0;
}

std::string LoadBundledDictionary() {
    HMODULE module = nullptr;
    if (!GetModuleHandleExW(
            GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS |
                GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,
            reinterpret_cast<LPCWSTR>(&LoadBundledDictionary), &module)) {
        DebugLog("dictionary-module", HRESULT_FROM_WIN32(GetLastError()));
        return {};
    }
    wchar_t path[MAX_PATH * 4]{};
    const DWORD length = GetModuleFileNameW(module, path,
                                             static_cast<DWORD>(std::size(path)));
    if (length == 0 || length >= std::size(path)) {
        DebugLog("dictionary-path", HRESULT_FROM_WIN32(GetLastError()));
        return {};
    }
    const std::filesystem::path dictionary_path(path, path + length);
    const std::filesystem::path sibling =
        dictionary_path.parent_path() / L"fy.dict.yaml";
    std::ifstream file(sibling, std::ios::binary);
    if (!file) {
        DebugLog("dictionary-open", HRESULT_FROM_WIN32(ERROR_FILE_NOT_FOUND));
        return {};
    }
    file.seekg(0, std::ios::end);
    const std::streamoff size = file.tellg();
    if (size <= 0) {
        DebugLog("dictionary-size", E_FAIL);
        return {};
    }
    std::string contents(static_cast<size_t>(size), '\0');
    file.seekg(0, std::ios::beg);
    file.read(contents.data(), static_cast<std::streamsize>(contents.size()));
    if (!file) {
        DebugLog("dictionary-read", E_FAIL);
        return {};
    }
    // Preserve the macOS user-dictionary contract.  Each custom row is
    // normalized to the same consolidated format and receives a very high
    // weight, without ever putting its text in diagnostics.
    wchar_t local_app_data[32768]{};
    const DWORD local_length = GetEnvironmentVariableW(
        L"LOCALAPPDATA", local_app_data, static_cast<DWORD>(std::size(local_app_data)));
    if (local_length > 0 && local_length < std::size(local_app_data)) {
        const std::filesystem::path custom_path =
            std::filesystem::path(local_app_data, local_app_data + local_length) /
            L"WindWhisper" / L"InputMethod" / L"custom_words.tsv";
        std::ifstream custom(custom_path, std::ios::binary);
        if (custom) {
            std::string line;
            int order = 1000000000;
            while (std::getline(custom, line)) {
                if (!line.empty() && line.back() == '\r') line.pop_back();
                if (line.empty() || line[0] == '#') continue;
                const size_t tab = line.find('\t');
                if (tab == std::string::npos || tab == 0 || tab + 1 >= line.size()) continue;
                const size_t second = line.find('\t', tab + 1);
                const std::string text = line.substr(0, tab);
                const std::string code = line.substr(tab + 1,
                    second == std::string::npos ? std::string::npos : second - tab - 1);
                const std::string weight = second == std::string::npos
                                                ? "3000000"
                                                : line.substr(second + 1);
                contents += text + "\t" + code + "\t" + weight + "\tflypy\t" +
                            std::to_string(order++) + "\n";
            }
        }
    }
    DebugLog("dictionary-loaded", S_OK,
             static_cast<WPARAM>(std::min<size_t>(contents.size(), UINT_MAX)));
    return contents;
}
}

struct FengYuContextSession {
    FengYuContextSession(ITfContext *value, fy_engine *engine,
                         CandidateWindow *window, const char *schema)
        : context(value), session(fy_session_create(engine)),
          candidate_window(window) {
        context->AddRef();
        if (session) {
            fy_session_select_schema(session, schema, std::strlen(schema));
        }
    }

    ~FengYuContextSession() {
        if (composition) {
            composition->Release();
        }
        fy_session_destroy(session);
        context->Release();
    }

    ITfContext *context = nullptr;
    fy_session *session = nullptr;
    ITfComposition *composition = nullptr;
    CandidateWindow *candidate_window = nullptr;
};

class FengYuTextServiceState {
public:
    FengYuTextServiceState() {
        schema_ = ReadConfiguredSchema();
        const std::string dictionary = LoadBundledDictionary();
        engine_ = fy_engine_create(dictionary.data(), dictionary.size());
        candidate_window_.Create(GetModuleHandleW(nullptr));
    }

    void SetSchema(const char *schema) {
        if (schema && *schema) schema_ = schema;
    }
    void ReloadSchema() { schema_ = ReadConfiguredSchema(); }
    const char *schema() const { return schema_.c_str(); }

    ~FengYuTextServiceState() {
        candidate_window_.Hide();
        sessions_.clear();
        fy_engine_destroy(engine_);
    }

    std::shared_ptr<FengYuContextSession> Find(ITfContext *context) const {
        const auto found = sessions_.find(context);
        return found == sessions_.end() ? nullptr : found->second;
    }

    std::shared_ptr<FengYuContextSession> GetOrCreate(ITfContext *context) {
        if (auto existing = Find(context)) {
            return existing;
        }
        auto created = std::make_shared<FengYuContextSession>(
            context, engine_, &candidate_window_, schema_.c_str());
        if (!created->session) {
            return nullptr;
        }
        sessions_.emplace(context, created);
        return created;
    }

    std::shared_ptr<FengYuContextSession> Remove(ITfContext *context) {
        const auto found = sessions_.find(context);
        if (found == sessions_.end()) {
            return nullptr;
        }
        auto removed = found->second;
        sessions_.erase(found);
        return removed;
    }

    std::vector<std::shared_ptr<FengYuContextSession>> Drain() {
        std::vector<std::shared_ptr<FengYuContextSession>> result;
        result.reserve(sessions_.size());
        for (auto &entry : sessions_) {
            result.push_back(std::move(entry.second));
        }
        sessions_.clear();
        return result;
    }

private:
    fy_engine *engine_ = nullptr;
    std::unordered_map<ITfContext *, std::shared_ptr<FengYuContextSession>> sessions_;
    CandidateWindow candidate_window_;
    std::string schema_ = "flypyShape";
};

class FengYuConfigureFunction final : public ITfFnConfigure {
public:
    FengYuConfigureFunction() { InterlockedIncrement(&g_object_count); }
    ~FengYuConfigureFunction() { InterlockedDecrement(&g_object_count); }

    HRESULT STDMETHODCALLTYPE QueryInterface(REFIID riid, void **object) override {
        if (!object) return E_POINTER;
        *object = nullptr;
        if (riid == IID_IUnknown || riid == IID_ITfFunction ||
            riid == IID_ITfFnConfigure) {
            *object = static_cast<ITfFnConfigure *>(this);
            AddRef();
            return S_OK;
        }
        return E_NOINTERFACE;
    }

    ULONG STDMETHODCALLTYPE AddRef() override {
        return InterlockedIncrement(&refs_);
    }

    ULONG STDMETHODCALLTYPE Release() override {
        const ULONG refs = InterlockedDecrement(&refs_);
        if (refs == 0) delete this;
        return refs;
    }

    HRESULT STDMETHODCALLTYPE GetDisplayName(BSTR *name) override {
        if (!name) return E_POINTER;
        *name = SysAllocString(L"风语输入法设置");
        return *name ? S_OK : E_OUTOFMEMORY;
    }

    HRESULT STDMETHODCALLTYPE Show(HWND parent, LANGID, REFGUID) override {
        int selected = 0;
        if (!ShowSelectionWindow(parent, &selected)) return S_FALSE;
        const char *schema = selected == 100 ? "flypyShape"
                               : selected == 101 ? "flypyPhonetic"
                                                 : selected == 102 ? "fullPinyin" : nullptr;
        if (!schema) return S_FALSE;
        const bool saved = WriteConfiguredSchema(schema);
        DebugLog(selected == 100 ? "schema-config-flypy-shape"
                 : selected == 101 ? "schema-config-flypy-phonetic"
                                    : "schema-config-full-pinyin",
                 saved ? S_OK : E_FAIL);
        return saved ? S_OK : E_FAIL;
    }

private:
    struct WindowState {
        int selected = 100;
        bool done = false;
        bool accepted = false;
    };

    static LRESULT CALLBACK WindowProc(HWND window, UINT message,
                                       WPARAM wparam, LPARAM lparam) {
        auto *state = reinterpret_cast<WindowState *>(
            GetWindowLongPtrW(window, GWLP_USERDATA));
        if (message == WM_NCCREATE) {
            const auto *create = reinterpret_cast<const CREATESTRUCTW *>(lparam);
            state = reinterpret_cast<WindowState *>(create->lpCreateParams);
            SetWindowLongPtrW(window, GWLP_USERDATA,
                              reinterpret_cast<LONG_PTR>(state));
        }
        if (message == WM_COMMAND && state) {
            const int id = LOWORD(wparam);
            if (id == 100 || id == 101 || id == 102) {
                state->selected = id;
                for (const int option : {100, 101, 102}) {
                    const HWND button = GetDlgItem(window, option);
                    SendMessageW(button, BM_SETCHECK,
                                 option == id ? BST_CHECKED : BST_UNCHECKED, 0);
                }
            } else if (id == IDOK) {
                state->accepted = true;
                state->done = true;
                DestroyWindow(window);
            } else if (id == IDCANCEL) {
                state->done = true;
                DestroyWindow(window);
            }
        } else if (message == WM_CLOSE && state) {
            state->done = true;
            DestroyWindow(window);
        }
        return DefWindowProcW(window, message, wparam, lparam);
    }

    static bool ShowSelectionWindow(HWND parent, int *selected) {
        if (!selected) return false;
        static const wchar_t kClassName[] = L"WindWhisperConfigureWindow";
        static ATOM atom = 0;
        if (!atom) {
            WNDCLASSW klass{};
            klass.lpfnWndProc = WindowProc;
            klass.hInstance = GetModuleHandleW(nullptr);
            klass.hCursor = LoadCursorW(nullptr, MAKEINTRESOURCEW(IDC_ARROW));
            klass.hbrBackground = reinterpret_cast<HBRUSH>(COLOR_WINDOW + 1);
            klass.lpszClassName = kClassName;
            atom = RegisterClassW(&klass);
            if (!atom && GetLastError() != ERROR_CLASS_ALREADY_EXISTS) return false;
        }
        WindowState state;
        const HWND window = CreateWindowExW(
            WS_EX_DLGMODALFRAME, kClassName, L"风语输入法设置",
            WS_CAPTION | WS_SYSMENU, CW_USEDEFAULT, CW_USEDEFAULT, 420, 250,
            parent, nullptr, GetModuleHandleW(nullptr), &state);
        if (!window) return false;
        CreateWindowW(L"STATIC", L"选择输入方案（保存后切换到其他应用即可生效）：",
                      WS_CHILD | WS_VISIBLE, 20, 18, 370, 24, window, nullptr,
                      GetModuleHandleW(nullptr), nullptr);
        for (const auto &option : {
                 std::pair<int, const wchar_t *>{100, L"小鹤音形（四码自动上屏）"},
                 std::pair<int, const wchar_t *>{101, L"小鹤双拼"},
                 std::pair<int, const wchar_t *>{102, L"全拼"}}) {
            const HWND button = CreateWindowW(
                L"BUTTON", option.second,
                WS_CHILD | WS_VISIBLE | BS_AUTORADIOBUTTON |
                    (option.first == 100 ? WS_GROUP : 0),
                32, 50 + (option.first - 100) * 32, 300, 26, window,
                reinterpret_cast<HMENU>(static_cast<INT_PTR>(option.first)),
                GetModuleHandleW(nullptr), nullptr);
            SendMessageW(button, BM_SETCHECK,
                         option.first == state.selected ? BST_CHECKED : BST_UNCHECKED, 0);
        }
        CreateWindowW(L"BUTTON", L"确定", WS_CHILD | WS_VISIBLE | BS_DEFPUSHBUTTON,
                      220, 170, 80, 28, window,
                      reinterpret_cast<HMENU>(static_cast<INT_PTR>(IDOK)),
                      GetModuleHandleW(nullptr), nullptr);
        CreateWindowW(L"BUTTON", L"取消", WS_CHILD | WS_VISIBLE,
                      310, 170, 80, 28, window,
                      reinterpret_cast<HMENU>(static_cast<INT_PTR>(IDCANCEL)),
                      GetModuleHandleW(nullptr), nullptr);
        if (parent) EnableWindow(parent, FALSE);
        ShowWindow(window, SW_SHOW);
        UpdateWindow(window);
        MSG message{};
        while (!state.done && GetMessageW(&message, nullptr, 0, 0) > 0) {
            TranslateMessage(&message);
            DispatchMessageW(&message);
        }
        if (parent) EnableWindow(parent, TRUE);
        if (state.accepted) *selected = state.selected;
        return state.accepted;
    }

    LONG refs_ = 1;
};

class FengYuLanguageBarButton final : public ITfLangBarItemButton,
                                      public ITfSource {
public:
    explicit FengYuLanguageBarButton(FengYuTextService *service)
        : service_(service) {
        InterlockedIncrement(&g_object_count);
    }
    ~FengYuLanguageBarButton() {
        if (sink_) sink_->Release();
        InterlockedDecrement(&g_object_count);
    }

    HRESULT STDMETHODCALLTYPE QueryInterface(REFIID riid, void **object) override {
        if (!object) return E_POINTER;
        *object = nullptr;
        if (riid == IID_IUnknown || riid == IID_ITfLangBarItem ||
            riid == IID_ITfLangBarItemButton) {
            *object = static_cast<ITfLangBarItemButton *>(this);
        } else if (riid == IID_ITfSource) {
            *object = static_cast<ITfSource *>(this);
        } else {
            return E_NOINTERFACE;
        }
        AddRef();
        return S_OK;
    }
    ULONG STDMETHODCALLTYPE AddRef() override { return InterlockedIncrement(&refs_); }
    ULONG STDMETHODCALLTYPE Release() override {
        const ULONG refs = InterlockedDecrement(&refs_);
        if (refs == 0) delete this;
        return refs;
    }
    HRESULT STDMETHODCALLTYPE GetInfo(TF_LANGBARITEMINFO *info) override {
        if (!info) return E_POINTER;
        ZeroMemory(info, sizeof(*info));
        info->clsidService = CLSID_FengYuTextService;
        // Windows 8 and later only surface the first language-bar item whose
        // guidItem is GUID_LBI_INPUTMODE in the modern taskbar input
        // indicator.  A private GUID is silently ignored there, even though
        // the item can be seen in the legacy floating language bar.
        info->guidItem = GUID_LBI_INPUTMODE;
        // dwStyle only accepts TF_LBI_STYLE_* values. TF_LBI_ICON/TEXT/
        // TOOLTIP are OnUpdate masks and overlap the low style bits; placing
        // them here accidentally marks the item hidden and is rejected by
        // AddItem on Windows 11.
        // Use a command button so OnClick receives both left and right clicks.
        // A pure BTN_MENU item routes every click to InitMenu and therefore
        // cannot use left click for the Chinese/English mode switch.
        info->dwStyle = TF_LBI_STYLE_SHOWNINTRAY | TF_LBI_STYLE_BTN_BUTTON;
        info->ulSort = 0;
        StringCchCopyW(info->szDescription, TF_LBI_DESC_MAXLEN,
                       L"风语输入法中英文切换与设置");
        DebugLog("language-bar-get-info");
        return S_OK;
    }
    HRESULT STDMETHODCALLTYPE GetStatus(DWORD *status) override {
        if (!status) return E_POINTER;
        *status = 0;
        return S_OK;
    }
    HRESULT STDMETHODCALLTYPE Show(BOOL) override {
        if (sink_) sink_->OnUpdate(TF_LBI_STATUS);
        return S_OK;
    }
    HRESULT STDMETHODCALLTYPE GetTooltipString(BSTR *tooltip) override {
        if (!tooltip) return E_POINTER;
        *tooltip = SysAllocString(IsAsciiMode()
                                      ? L"风语输入法：英文模式（左键切换，右键设置）"
                                      : L"风语输入法：中文模式（左键切换，右键设置）");
        return *tooltip ? S_OK : E_OUTOFMEMORY;
    }
    HRESULT STDMETHODCALLTYPE OnClick(
        TfLBIClick click, POINT point, const RECT *) override {
        DebugLog(click == TF_LBI_CLK_LEFT ? "language-bar-left-click"
                                          : "language-bar-right-click");
        if (click == TF_LBI_CLK_LEFT) {
            return service_ ? service_->ToggleInputModeFromLanguageBar() : E_FAIL;
        }
        if (click != TF_LBI_CLK_RIGHT) return S_FALSE;

        HMENU menu = CreatePopupMenu();
        HMENU schemes = CreatePopupMenu();
        if (!menu || !schemes) {
            if (schemes) DestroyMenu(schemes);
            if (menu) DestroyMenu(menu);
            return E_OUTOFMEMORY;
        }
        AppendMenuW(menu, MF_STRING | MF_DISABLED,
                    0, IsAsciiMode() ? L"当前：英文模式" : L"当前：中文模式");
        AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);
        const std::string schema = ReadConfiguredSchema();
        AppendMenuW(schemes, MF_STRING |
                                 (schema == "flypyShape" ? MF_CHECKED : 0),
                    100, L"小鹤音形（四码自动上屏）");
        AppendMenuW(schemes, MF_STRING |
                                 (schema == "flypyPhonetic" ? MF_CHECKED : 0),
                    101, L"小鹤双拼");
        AppendMenuW(schemes, MF_STRING |
                                 (schema == "fullPinyin" ? MF_CHECKED : 0),
                    102, L"全拼");
        AppendMenuW(menu, MF_POPUP, reinterpret_cast<UINT_PTR>(schemes),
                    L"输入方案");
        AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);
        AppendMenuW(menu, MF_STRING, 200, L"输入法设置...");
        if (point.x == 0 && point.y == 0) GetCursorPos(&point);
        const UINT command = TrackPopupMenu(
            menu, TPM_RETURNCMD | TPM_RIGHTBUTTON | TPM_NONOTIFY,
            point.x, point.y, 0, GetForegroundWindow(), nullptr);
        HRESULT result = S_OK;
        if (command >= 100 && command <= 102) {
            result = OnMenuSelect(command);
        } else if (command == 200) {
            FengYuConfigureFunction function;
            result = function.Show(GetForegroundWindow(),
                                   LANGID_FengYuChineseSimplified,
                                   GUID_FengYuLanguageProfile);
        }
        DestroyMenu(menu);
        return result;
    }
    HRESULT STDMETHODCALLTYPE InitMenu(ITfMenu *menu) override {
        if (!menu) return E_POINTER;
        DebugLog("language-bar-init-menu");
        const std::string schema = ReadConfiguredSchema();
        const auto add = [&](UINT id, const wchar_t *text,
                             const char *value) -> HRESULT {
            DWORD flags = (schema == value) ? TF_LBMENUF_CHECKED : 0;
            return menu->AddMenuItem(id, flags, nullptr, nullptr, text,
                                     static_cast<ULONG>(wcslen(text)), nullptr);
        };
        HRESULT result = add(100, L"小鹤音形（四码自动上屏）", "flypyShape");
        if (FAILED(result)) return result;
        result = add(101, L"小鹤双拼", "flypyPhonetic");
        if (FAILED(result)) return result;
        return add(102, L"全拼", "fullPinyin");
    }
    HRESULT STDMETHODCALLTYPE OnMenuSelect(UINT id) override {
        const char *schema = id == 100 ? "flypyShape"
                             : id == 101 ? "flypyPhonetic"
                                         : id == 102 ? "fullPinyin" : nullptr;
        if (!schema) return S_FALSE;
        const bool saved = WriteConfiguredSchema(schema);
        DebugLog("language-bar-menu-select", saved ? S_OK : E_FAIL,
                 static_cast<WPARAM>(id));
        DebugLog(id == 100 ? "schema-menu-flypy-shape"
                 : id == 101 ? "schema-menu-flypy-phonetic"
                              : "schema-menu-full-pinyin",
                 saved ? S_OK : E_FAIL);
        if (saved && sink_) {
            sink_->OnUpdate(TF_LBI_STATUS | TF_LBI_TEXT |
                            TF_LBI_TOOLTIP | TF_LBI_ICON);
        }
        return saved ? S_OK : E_FAIL;
    }
    HRESULT STDMETHODCALLTYPE GetIcon(HICON *icon) override {
        if (!icon) return E_POINTER;
        // The modern input indicator requires an icon for its mode item.
        HMODULE module = nullptr;
        GetModuleHandleExW(
            GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS |
                GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,
            reinterpret_cast<LPCWSTR>(&DebugLog), &module);
        *icon = module ? LoadIconW(module, MAKEINTRESOURCEW(101)) : nullptr;
        DebugLog("language-bar-get-icon", *icon ? S_OK : E_FAIL);
        return *icon ? S_OK : E_FAIL;
    }
    HRESULT STDMETHODCALLTYPE GetText(BSTR *text) override {
        if (!text) return E_POINTER;
        *text = SysAllocString(IsAsciiMode() ? L"英" : L"中");
        return *text ? S_OK : E_OUTOFMEMORY;
    }

    void NotifyModeChanged() {
        if (sink_) {
            sink_->OnUpdate(TF_LBI_TEXT | TF_LBI_TOOLTIP | TF_LBI_ICON |
                            TF_LBI_STATUS);
        }
    }

    void Detach() { service_ = nullptr; }

    HRESULT STDMETHODCALLTYPE AdviseSink(
        REFIID riid, IUnknown *unknown, DWORD *cookie) override {
        if (!cookie) return E_POINTER;
        *cookie = TF_INVALID_COOKIE;
        if (riid != IID_ITfLangBarItemSink) {
            return CONNECT_E_CANNOTCONNECT;
        }
        if (!unknown) return E_INVALIDARG;
        if (sink_) return CONNECT_E_ADVISELIMIT;
        const HRESULT result = unknown->QueryInterface(
            IID_ITfLangBarItemSink, reinterpret_cast<void **>(&sink_));
        if (FAILED(result)) {
            sink_ = nullptr;
            return E_NOINTERFACE;
        }
        *cookie = kSinkCookie;
        DebugLog("language-bar-advise-sink");
        return S_OK;
    }

    HRESULT STDMETHODCALLTYPE UnadviseSink(DWORD cookie) override {
        if (cookie != kSinkCookie || !sink_) return CONNECT_E_NOCONNECTION;
        sink_->Release();
        sink_ = nullptr;
        DebugLog("language-bar-unadvise-sink");
        return S_OK;
    }

private:
    bool IsAsciiMode() const {
        return service_ && service_->ascii_mode_;
    }
    static constexpr DWORD kSinkCookie = 1;
    LONG refs_ = 1;
    ITfLangBarItemSink *sink_ = nullptr;
    FengYuTextService *service_ = nullptr;
};

namespace {
HRESULT GetSelectionRange(
    ITfContext *context, TfEditCookie cookie, ITfRange **range) {
    if (!range) {
        return E_POINTER;
    }
    *range = nullptr;
    TF_SELECTION selection{};
    ULONG fetched = 0;
    const HRESULT result = context->GetSelection(
        cookie, TF_DEFAULT_SELECTION, 1, &selection, &fetched);
    if (FAILED(result)) {
        return result;
    }
    if (fetched != 1 || !selection.range) {
        return E_FAIL;
    }
    *range = selection.range;
    return S_OK;
}

HRESULT ReplaceRangeAndMoveCaret(
    ITfContext *context, ITfRange *range, TfEditCookie cookie,
    const std::wstring &text) {
    if (text.size() > static_cast<size_t>(LONG_MAX)) {
        return E_INVALIDARG;
    }
    const HRESULT set_result = range->SetText(
        cookie, 0, text.empty() ? nullptr : text.data(),
        static_cast<LONG>(text.size()));
    if (FAILED(set_result)) {
        DebugLog("range-set-text", set_result,
                 static_cast<WPARAM>(text.size()));
        return set_result;
    }
    const HRESULT collapse_result = range->Collapse(cookie, TF_ANCHOR_END);
    if (FAILED(collapse_result)) {
        DebugLog("range-collapse", collapse_result);
        return collapse_result;
    }
    TF_SELECTION selection{};
    selection.range = range;
    selection.style.ase = TF_AE_NONE;
    selection.style.fInterimChar = FALSE;
    const HRESULT selection_result = context->SetSelection(cookie, 1, &selection);
    DebugLog("context-set-selection", selection_result);
    return selection_result;
}

void ShowCandidates(CandidateWindow &, ITfContext *, TfEditCookie,
                    ITfComposition *, const fy_snapshot &);

class FengYuCompositionSink final : public ITfCompositionSink {
public:
    FengYuCompositionSink() { InterlockedIncrement(&g_object_count); }
    ~FengYuCompositionSink() { InterlockedDecrement(&g_object_count); }

    HRESULT STDMETHODCALLTYPE QueryInterface(REFIID riid, void **object) override {
        if (!object) {
            return E_POINTER;
        }
        *object = nullptr;
        if (riid != IID_IUnknown && riid != IID_ITfCompositionSink) {
            return E_NOINTERFACE;
        }
        *object = static_cast<ITfCompositionSink *>(this);
        AddRef();
        return S_OK;
    }

    ULONG STDMETHODCALLTYPE AddRef() override {
        return InterlockedIncrement(&refs_);
    }

    ULONG STDMETHODCALLTYPE Release() override {
        const ULONG refs = InterlockedDecrement(&refs_);
        if (refs == 0) {
            delete this;
        }
        return refs;
    }

    HRESULT STDMETHODCALLTYPE OnCompositionTerminated(TfEditCookie, ITfComposition *) override {
        DebugLog("composition-terminated");
        return S_OK;
    }

private:
    LONG refs_ = 1;
};

class FengYuEditSession final : public ITfEditSession {
public:
    FengYuEditSession(std::shared_ptr<FengYuContextSession> state,
                      std::wstring composition, std::wstring commit)
        : state_(std::move(state)), composition_(std::move(composition)),
          commit_(std::move(commit)) {
        InterlockedIncrement(&g_object_count);
    }

    ~FengYuEditSession() {
        InterlockedDecrement(&g_object_count);
    }

    HRESULT STDMETHODCALLTYPE QueryInterface(REFIID riid, void **object) override {
        if (!object) {
            return E_POINTER;
        }
        *object = nullptr;
        if (riid != IID_IUnknown && riid != IID_ITfEditSession) {
            return E_NOINTERFACE;
        }
        *object = static_cast<ITfEditSession *>(this);
        AddRef();
        return S_OK;
    }

    ULONG STDMETHODCALLTYPE AddRef() override {
        return InterlockedIncrement(&refs_);
    }

    ULONG STDMETHODCALLTYPE Release() override {
        const ULONG refs = InterlockedDecrement(&refs_);
        if (refs == 0) {
            delete this;
        }
        return refs;
    }

    HRESULT STDMETHODCALLTYPE DoEditSession(TfEditCookie cookie) override {
        HRESULT result = S_OK;
        if (!commit_.empty()) {
            result = Commit(cookie);
        } else if (!composition_.empty()) {
            result = UpdateComposition(cookie);
            if (SUCCEEDED(result)) {
                fy_snapshot snapshot{};
                if (fy_session_snapshot(state_->session, &snapshot)) {
                    ShowCandidates(*state_->candidate_window, state_->context,
                                   cookie, state_->composition, snapshot);
                }
            }
        } else {
            result = CancelComposition(cookie);
        }
        if (!commit_.empty() || composition_.empty()) {
            if (state_->candidate_window) {
                state_->candidate_window->Hide();
            }
        }
        DebugLog("do-edit-session", result,
                 static_cast<WPARAM>(composition_.size()),
                 !commit_.empty());
        if (FAILED(result)) {
            fy_session_reset(state_->session);
        }
        return result;
    }

private:
    HRESULT StartComposition(TfEditCookie cookie, const std::wstring &initial_text) {
        ITfContextComposition *manager = nullptr;
        HRESULT result = state_->context->QueryInterface(
            IID_ITfContextComposition,
            reinterpret_cast<void **>(&manager));
        if (FAILED(result)) {
            DebugLog("composition-context-interface", result);
            return result;
        }

        ITfInsertAtSelection *inserter = nullptr;
        result = state_->context->QueryInterface(
            IID_ITfInsertAtSelection, reinterpret_cast<void **>(&inserter));
        if (SUCCEEDED(result)) {
            ITfRange *inserted_range = nullptr;
            result = inserter->InsertTextAtSelection(
                cookie, TF_IAS_QUERYONLY, nullptr, 0, &inserted_range);
            DebugLog("insert-initial-composition-text", result,
                     static_cast<WPARAM>(initial_text.size()));
            inserter->Release();
            if (SUCCEEDED(result) && inserted_range) {
                auto *sink = new FengYuCompositionSink();
                result = manager->StartComposition(
                    cookie, inserted_range, sink, &state_->composition);
                DebugLog("start-composition", result);
                sink->Release();
                inserted_range->Release();
            } else if (SUCCEEDED(result)) {
                result = E_FAIL;
            }
        }
        manager->Release();
        return result;
    }

    HRESULT UpdateComposition(TfEditCookie cookie) {
        if (!state_->composition) {
            const HRESULT start_result = StartComposition(cookie, composition_);
            if (FAILED(start_result)) {
                return start_result;
            }
        }
        ITfRange *range = nullptr;
        const HRESULT range_result = state_->composition->GetRange(&range);
        if (FAILED(range_result)) {
            DebugLog("composition-get-range", range_result);
            return range_result;
        }
        const HRESULT result = ReplaceRangeAndMoveCaret(
            state_->context, range, cookie, composition_);
        DebugLog("update-composition", result,
                 static_cast<WPARAM>(composition_.size()));
        range->Release();
        return result;
    }

    HRESULT Commit(TfEditCookie cookie) {
        ITfRange *range = nullptr;
        HRESULT result = state_->composition
                             ? state_->composition->GetRange(&range)
                             : GetSelectionRange(state_->context, cookie, &range);
        if (SUCCEEDED(result)) {
            result = ReplaceRangeAndMoveCaret(
                state_->context, range, cookie, commit_);
        }
        if (range) {
            range->Release();
        }
        if (state_->composition) {
            const HRESULT end_result = state_->composition->EndComposition(cookie);
            state_->composition->Release();
            state_->composition = nullptr;
            if (SUCCEEDED(result)) {
                result = end_result;
            }
        }
        return result;
    }

    HRESULT CancelComposition(TfEditCookie cookie) {
        if (!state_->composition) {
            return S_OK;
        }
        ITfRange *range = nullptr;
        HRESULT result = state_->composition->GetRange(&range);
        if (SUCCEEDED(result)) {
            result = ReplaceRangeAndMoveCaret(state_->context, range, cookie, L"");
        }
        if (range) {
            range->Release();
        }
        const HRESULT end_result = state_->composition->EndComposition(cookie);
        state_->composition->Release();
        state_->composition = nullptr;
        return FAILED(result) ? result : end_result;
    }

    LONG refs_ = 1;
    std::shared_ptr<FengYuContextSession> state_;
    std::wstring composition_;
    std::wstring commit_;
};

bool QueueEditSession(
    const std::shared_ptr<FengYuContextSession> &state, TfClientId client_id,
    const std::wstring &composition, const std::wstring &commit) {
    if (!state || client_id == TF_CLIENTID_NULL) {
        return false;
    }
    auto *edit_session = new FengYuEditSession(state, composition, commit);
    HRESULT session_result = E_FAIL;
    const HRESULT request_result = state->context->RequestEditSession(
        client_id, edit_session, TF_ES_SYNC | TF_ES_READWRITE, &session_result);
    edit_session->Release();
    DebugLog("request-edit-session", request_result,
             static_cast<WPARAM>(session_result),
             SUCCEEDED(request_result) && SUCCEEDED(session_result));
    return SUCCEEDED(request_result) && SUCCEEDED(session_result);
}
}

FengYuTextService::FengYuTextService()
    : state_(std::make_unique<FengYuTextServiceState>()) {
    InterlockedIncrement(&g_object_count);
}

namespace {
void ShowCandidates(
    CandidateWindow &window, ITfContext *context, TfEditCookie cookie,
    ITfComposition *composition, const fy_snapshot &snapshot) {
    if (!context || !snapshot.is_composing || snapshot.candidate_count == 0) {
        DebugLog("candidate-hidden-no-data", S_OK,
                 static_cast<WPARAM>(snapshot.candidate_count));
        window.Hide();
        return;
    }
    ITfRange *range = nullptr;
    HRESULT result = composition ? composition->GetRange(&range)
                                 : GetSelectionRange(context, cookie, &range);
    if (FAILED(result) || !range) {
        DebugLog("candidate-get-range", result);
        window.Hide();
        return;
    }
    ITfContextView *view = nullptr;
    result = context->GetActiveView(&view);
    RECT bounds{};
    BOOL clipped = FALSE;
    if (SUCCEEDED(result)) {
        result = view->GetTextExt(cookie, range, &bounds, &clipped);
    }
    if (view) {
        view->Release();
    }
    range->Release();
    if (FAILED(result)) {
        DebugLog("candidate-get-text-ext", result);
        window.Hide();
        return;
    }
    std::vector<CandidateWindowItem> items;
    items.reserve(snapshot.candidate_count);
    for (size_t index = 0; index < snapshot.candidate_count; ++index) {
        const fy_candidate &candidate = snapshot.candidates[index];
        items.push_back({Utf8ToWide(candidate.text, candidate.text_len),
                         Utf8ToWide(candidate.comment, candidate.comment_len)});
    }
    POINT point{bounds.left, bounds.bottom};
    window.ShowAt(point, 96, items, snapshot.highlighted, snapshot.page,
                  snapshot.page_count);
    DebugLog("candidate-show", S_OK,
             static_cast<WPARAM>(snapshot.candidate_count));
}
}

FengYuTextService::~FengYuTextService() {
    Deactivate();
    InterlockedDecrement(&g_object_count);
}

HRESULT FengYuTextService::QueryInterface(REFIID riid, void **object) {
    if (!object) {
        return E_POINTER;
    }
    *object = nullptr;
    if (riid == IID_IUnknown || riid == IID_ITfTextInputProcessor ||
        riid == IID_ITfTextInputProcessorEx) {
        *object = static_cast<ITfTextInputProcessorEx *>(this);
    } else if (riid == IID_ITfKeyEventSink) {
        *object = static_cast<ITfKeyEventSink *>(this);
    } else if (riid == IID_ITfThreadMgrEventSink) {
        *object = static_cast<ITfThreadMgrEventSink *>(this);
    } else if (riid == IID_ITfFunctionProvider) {
        *object = static_cast<ITfFunctionProvider *>(this);
    } else {
        return E_NOINTERFACE;
    }
    AddRef();
    return S_OK;
}

ULONG FengYuTextService::AddRef() {
    return InterlockedIncrement(&refs_);
}

ULONG FengYuTextService::Release() {
    const ULONG refs = InterlockedDecrement(&refs_);
    if (refs == 0) {
        delete this;
    }
    return refs;
}

HRESULT FengYuTextService::Activate(ITfThreadMgr *thread_manager, TfClientId client_id) {
    return ActivateEx(thread_manager, client_id, 0);
}

HRESULT FengYuTextService::ActivateEx(
    ITfThreadMgr *thread_manager, TfClientId client_id, DWORD) {
    if (!thread_manager || client_id == TF_CLIENTID_NULL) {
        return E_INVALIDARG;
    }

    DebugLog("activate-begin");
    Deactivate();
    thread_manager_ = thread_manager;
    thread_manager_->AddRef();
    client_id_ = client_id;

    HRESULT result = thread_manager_->QueryInterface(
        IID_ITfSource, reinterpret_cast<void **>(&thread_source_));
    if (SUCCEEDED(result)) {
        result = thread_source_->AdviseSink(
            IID_ITfThreadMgrEventSink,
            static_cast<ITfThreadMgrEventSink *>(this),
            &thread_event_sink_cookie_);
    }
    if (SUCCEEDED(result)) {
        result = thread_manager_->QueryInterface(
            IID_ITfKeystrokeMgr, reinterpret_cast<void **>(&keystroke_manager_));
    }
    // Register the language-bar configuration button independently of the
    // key-sink handshake.  Some hosts reject AdviseKeyEventSink until a text
    // context is focused, but the language-bar item must still be discoverable
    // while the profile is selected.
    if (SUCCEEDED(result)) {
        RegisterLanguageBarItem();
    }
    if (SUCCEEDED(result)) {
        result = keystroke_manager_->AdviseKeyEventSink(
            client_id_, static_cast<ITfKeyEventSink *>(this), TRUE);
        key_sink_advised_ = SUCCEEDED(result);
    }
    if (SUCCEEDED(result)) {
        state_->ReloadSchema();
        DebugLog("schema-loaded");
    }
    if (FAILED(result)) {
        Deactivate();
    }
    DebugLog("activate-result", result, key_sink_advised_ ? 1 : 0);
    return result;
}

HRESULT FengYuTextService::Deactivate() {
    DebugLog("deactivate-begin");
    if (thread_source_) {
        if (thread_event_sink_cookie_ != TF_INVALID_COOKIE) {
            thread_source_->UnadviseSink(thread_event_sink_cookie_);
            thread_event_sink_cookie_ = TF_INVALID_COOKIE;
        }
        thread_source_->Release();
        thread_source_ = nullptr;
    }
    if (keystroke_manager_) {
        if (key_sink_advised_ && client_id_ != TF_CLIENTID_NULL) {
            keystroke_manager_->UnadviseKeyEventSink(client_id_);
        }
        key_sink_advised_ = false;
        keystroke_manager_->Release();
        keystroke_manager_ = nullptr;
    }

    UnregisterLanguageBarItem();

    for (const auto &context : state_->Drain()) {
        QueueEditSession(context, client_id_, L"", L"");
    }
    if (thread_manager_) {
        thread_manager_->Release();
        thread_manager_ = nullptr;
    }
    client_id_ = TF_CLIENTID_NULL;
    ascii_mode_ = false;
    shift_tap_.Reset();
    DebugLog("deactivate-result");
    return S_OK;
}

bool FengYuTextService::MapKey(
    ITfContext *context, WPARAM virtual_key, uint32_t *key,
    uint32_t *modifiers) const {
    if (!context || !key || !modifiers || client_id_ == TF_CLIENTID_NULL ||
        ascii_mode_) {
        return false;
    }
    ITfContextComposition *composition_manager = nullptr;
    if (FAILED(context->QueryInterface(
            IID_ITfContextComposition,
            reinterpret_cast<void **>(&composition_manager)))) {
        return false;
    }
    composition_manager->Release();

    bool composing = false;
    if (const auto session = state_->Find(context)) {
        fy_snapshot snapshot{};
        composing = fy_session_snapshot(session->session, &snapshot) &&
                    snapshot.is_composing;
    }
    FyMappedKey mapped{};
    if (!FyMapVirtualKey(
            virtual_key, KeyStateDown(VK_SHIFT),
            (GetKeyState(VK_CAPITAL) & 1) != 0, KeyStateDown(VK_CONTROL),
            KeyStateDown(VK_MENU), composing, &mapped)) {
        return false;
    }
    *key = mapped.key;
    *modifiers = mapped.modifiers;
    return true;
}

HRESULT FengYuTextService::OnTestKeyDown(
    ITfContext *context, WPARAM virtual_key, LPARAM, BOOL *eaten) {
    if (!eaten) {
        return E_POINTER;
    }
    if (shift_tap_.TestKeyDown(virtual_key)) {
        *eaten = TRUE;
        DebugLog("test-shift-down", S_OK, virtual_key, *eaten);
        return S_OK;
    }
    uint32_t key = 0;
    uint32_t modifiers = 0;
    *eaten = MapKey(context, virtual_key, &key, &modifiers) ? TRUE : FALSE;
    DebugLog("test-key-down", S_OK, virtual_key, *eaten);
    return S_OK;
}

HRESULT FengYuTextService::OnTestKeyUp(
    ITfContext *, WPARAM virtual_key, LPARAM, BOOL *eaten) {
    if (!eaten) {
        return E_POINTER;
    }
    *eaten = shift_tap_.TestKeyUp(virtual_key) ? TRUE : FALSE;
    DebugLog("test-key-up", S_OK, virtual_key, *eaten);
    return S_OK;
}

HRESULT FengYuTextService::OnKeyDown(
    ITfContext *context, WPARAM virtual_key, LPARAM flags, BOOL *eaten) {
    if (!eaten) {
        return E_POINTER;
    }
    *eaten = FALSE;
    if (FyShiftTapState::IsShiftKey(virtual_key)) {
        const bool repeat =
            (static_cast<ULONG_PTR>(flags) & (1ull << 30)) != 0;
        shift_tap_.KeyDown(
            virtual_key, repeat,
            KeyStateDown(VK_CONTROL) || KeyStateDown(VK_MENU) ||
                KeyStateDown(VK_LWIN) || KeyStateDown(VK_RWIN));
        *eaten = TRUE;
        DebugLog("shift-down", S_OK, virtual_key, *eaten);
        return S_OK;
    }
    uint32_t key = 0;
    uint32_t modifiers = 0;
    if (!MapKey(context, virtual_key, &key, &modifiers)) {
        DebugLog("key-down-unmapped", S_OK, virtual_key, FALSE);
        return S_OK;
    }

    const auto session = state_->GetOrCreate(context);
    if (!session || !fy_session_process_key(session->session, key, modifiers)) {
        DebugLog("key-down-engine-rejected", S_OK, virtual_key, FALSE);
        return S_OK;
    }
    fy_snapshot snapshot{};
    if (!fy_session_snapshot(session->session, &snapshot)) {
        fy_session_reset(session->session);
        state_->Remove(context);
        return E_FAIL;
    }
    const std::wstring composition = Utf8ToWide(
        snapshot.composition, snapshot.composition_len);
    const std::wstring commit = Utf8ToWide(snapshot.commit, snapshot.commit_len);
    DebugLog("snapshot", S_OK,
             static_cast<WPARAM>(composition.size()), !commit.empty());
    if (!QueueEditSession(session, client_id_, composition, commit)) {
        fy_session_reset(session->session);
        state_->Remove(context);
        return S_OK;
    }
    *eaten = TRUE;
    DebugLog("key-down-eaten", S_OK, virtual_key, TRUE);
    return S_OK;
}

HRESULT FengYuTextService::OnKeyUp(
    ITfContext *context, WPARAM key, LPARAM, BOOL *eaten) {
    if (!eaten) {
        return E_POINTER;
    }
    *eaten = FALSE;
    if (!shift_tap_.KeyUp(key)) {
        return S_OK;
    }
    const HRESULT result = ToggleInputMode(context);
    *eaten = SUCCEEDED(result) ? TRUE : FALSE;
    DebugLog(ascii_mode_ ? "shift-mode-english" : "shift-mode-chinese",
             result, key, *eaten);
    return result;
}

HRESULT FengYuTextService::ToggleInputMode(ITfContext *context) {
    if (client_id_ == TF_CLIENTID_NULL) return E_UNEXPECTED;
    if (context) {
        const auto session = state_->GetOrCreate(context);
        if (!session) return E_OUTOFMEMORY;
        fy_snapshot snapshot{};
        std::wstring literal;
        if (fy_session_snapshot(session->session, &snapshot)) {
            literal = Utf8ToWide(snapshot.composition, snapshot.composition_len);
        }
        fy_session_reset(session->session);
        if (!QueueEditSession(session, client_id_, L"", literal)) {
            state_->Remove(context);
            return E_FAIL;
        }
    }
    ascii_mode_ = !ascii_mode_;
    if (language_bar_button_) language_bar_button_->NotifyModeChanged();
    DebugLog(ascii_mode_ ? "input-mode-english" : "input-mode-chinese");
    return S_OK;
}

HRESULT FengYuTextService::ToggleInputModeFromLanguageBar() {
    ITfDocumentMgr *document_manager = nullptr;
    ITfContext *context = nullptr;
    if (thread_manager_ &&
        SUCCEEDED(thread_manager_->GetFocus(&document_manager)) &&
        document_manager) {
        document_manager->GetTop(&context);
        document_manager->Release();
    }
    const HRESULT result = ToggleInputMode(context);
    if (context) context->Release();
    DebugLog("language-bar-toggle-mode", result, ascii_mode_ ? 1 : 0);
    return result;
}

HRESULT FengYuTextService::OnPreservedKey(ITfContext *, REFGUID, BOOL *eaten) {
    if (!eaten) {
        return E_POINTER;
    }
    *eaten = FALSE;
    return S_OK;
}

HRESULT FengYuTextService::OnInitDocumentMgr(ITfDocumentMgr *) {
    DebugLog("init-document-manager");
    return S_OK;
}

HRESULT FengYuTextService::OnUninitDocumentMgr(ITfDocumentMgr *document_manager) {
    RemoveDocumentManager(document_manager);
    return S_OK;
}

HRESULT FengYuTextService::OnSetFocus(
    ITfDocumentMgr *focused, ITfDocumentMgr *previous) {
    state_->ReloadSchema();
    if (previous && previous != focused) {
        RemoveDocumentManager(previous);
    }
    if (focused) {
        ITfContext *context = nullptr;
        if (SUCCEEDED(focused->GetTop(&context)) && context) {
            ConfigureInputMode(context);
            context->Release();
        }
    }
    return S_OK;
}

HRESULT FengYuTextService::OnPushContext(ITfContext *) {
    return S_OK;
}

HRESULT FengYuTextService::OnPopContext(ITfContext *context) {
    RemoveContext(context);
    return S_OK;
}

HRESULT FengYuTextService::GetType(GUID *type) {
    if (!type) return E_POINTER;
    *type = CLSID_FengYuTextService;
    return S_OK;
}

HRESULT FengYuTextService::GetDescription(BSTR *description) {
    if (!description) return E_POINTER;
    *description = SysAllocString(L"风语输入法功能");
    return *description ? S_OK : E_OUTOFMEMORY;
}

HRESULT FengYuTextService::GetFunction(
    REFGUID, REFIID riid, IUnknown **function) {
    if (!function) return E_POINTER;
    *function = nullptr;
    if (riid != IID_ITfFnConfigure && riid != IID_ITfFunction) {
        return E_NOINTERFACE;
    }
    auto *configure = new FengYuConfigureFunction();
    const HRESULT result = configure->QueryInterface(riid,
                                                      reinterpret_cast<void **>(function));
    configure->Release();
    return result;
}

void FengYuTextService::RemoveContext(ITfContext *context) {
    if (const auto removed = state_->Remove(context)) {
        QueueEditSession(removed, client_id_, L"", L"");
    }
}

void FengYuTextService::RemoveDocumentManager(ITfDocumentMgr *document_manager) {
    if (!document_manager) {
        return;
    }
    ITfContext *context = nullptr;
    if (SUCCEEDED(document_manager->GetTop(&context)) && context) {
        RemoveContext(context);
        context->Release();
    }
}

void FengYuTextService::ConfigureInputMode(ITfContext *context) {
    if (!context || client_id_ == TF_CLIENTID_NULL) {
        return;
    }
    ITfCompartmentMgr *manager = nullptr;
    HRESULT result = context->QueryInterface(
        IID_ITfCompartmentMgr, reinterpret_cast<void **>(&manager));
    if (FAILED(result)) {
        DebugLog("input-mode-compartment-manager", result);
        return;
    }
    auto set_compartment = [&](REFGUID guid, LONG value) {
        ITfCompartment *compartment = nullptr;
        HRESULT set_result = manager->GetCompartment(guid, &compartment);
        if (SUCCEEDED(set_result)) {
            VARIANT variant;
            VariantInit(&variant);
            variant.vt = VT_I4;
            variant.lVal = value;
            set_result = compartment->SetValue(client_id_, &variant);
            VariantClear(&variant);
            compartment->Release();
        }
        DebugLog("input-mode-compartment", set_result);
    };
    set_compartment(GUID_COMPARTMENT_KEYBOARD_OPENCLOSE, 1);
    set_compartment(GUID_COMPARTMENT_KEYBOARD_INPUTMODE_CONVERSION,
                    TF_CONVERSIONMODE_NATIVE | TF_SENTENCEMODE_NONE);
    manager->Release();
}

void FengYuTextService::RegisterLanguageBarItem() {
    if (!thread_manager_ || language_bar_item_manager_ || language_bar_item_) {
        return;
    }
    // Match Microsoft's SampleIME: the language-bar manager must belong to
    // the ITfThreadMgr instance that activated this text service.
    HRESULT result = thread_manager_->QueryInterface(
        IID_ITfLangBarItemMgr,
        reinterpret_cast<void **>(&language_bar_item_manager_));
    DebugLog("language-bar-thread-manager", result);
    if (FAILED(result) || !language_bar_item_manager_) {
        DebugLog("language-bar-item-manager", result);
        language_bar_item_manager_ = nullptr;
        return;
    }
    auto *button = new FengYuLanguageBarButton(this);
    result = language_bar_item_manager_->AddItem(button);
    if (SUCCEEDED(result)) {
        language_bar_item_ = button;
        language_bar_button_ = button;
        DebugLog("language-bar-item-added");
    } else {
        DebugLog("language-bar-item-add", result);
        button->Release();
        language_bar_item_manager_->Release();
        language_bar_item_manager_ = nullptr;
    }
}

void FengYuTextService::UnregisterLanguageBarItem() {
    if (language_bar_button_) {
        language_bar_button_->Detach();
        language_bar_button_ = nullptr;
    }
    if (language_bar_item_manager_ && language_bar_item_) {
        const HRESULT result = language_bar_item_manager_->RemoveItem(
            language_bar_item_);
        DebugLog("language-bar-item-removed", result);
        language_bar_item_->Release();
        language_bar_item_ = nullptr;
    }
    if (language_bar_item_manager_) {
        language_bar_item_manager_->Release();
        language_bar_item_manager_ = nullptr;
    }
}

class FengYuClassFactory final : public IClassFactory {
public:
    FengYuClassFactory() {
        InterlockedIncrement(&g_object_count);
    }

    ~FengYuClassFactory() {
        InterlockedDecrement(&g_object_count);
    }

    HRESULT STDMETHODCALLTYPE QueryInterface(REFIID riid, void **object) override {
        if (!object) {
            return E_POINTER;
        }
        *object = nullptr;
        if (riid != IID_IUnknown && riid != IID_IClassFactory) {
            return E_NOINTERFACE;
        }
        *object = static_cast<IClassFactory *>(this);
        AddRef();
        return S_OK;
    }

    ULONG STDMETHODCALLTYPE AddRef() override {
        return InterlockedIncrement(&refs_);
    }

    ULONG STDMETHODCALLTYPE Release() override {
        const ULONG refs = InterlockedDecrement(&refs_);
        if (refs == 0) {
            delete this;
        }
        return refs;
    }

    HRESULT STDMETHODCALLTYPE CreateInstance(
        IUnknown *outer, REFIID riid, void **object) override {
        if (!object) {
            return E_POINTER;
        }
        *object = nullptr;
        if (outer) {
            return CLASS_E_NOAGGREGATION;
        }
        auto *service = new FengYuTextService;
        const HRESULT result = service->QueryInterface(riid, object);
        service->Release();
        return result;
    }

    HRESULT STDMETHODCALLTYPE LockServer(BOOL lock) override {
        if (lock) {
            InterlockedIncrement(&g_server_lock_count);
        } else if (InterlockedCompareExchange(&g_server_lock_count, 0, 0) > 0) {
            InterlockedDecrement(&g_server_lock_count);
        }
        return S_OK;
    }

private:
    LONG refs_ = 1;
};

STDAPI DllGetClassObject(REFCLSID clsid, REFIID riid, void **object) {
    if (!object) {
        return E_POINTER;
    }
    *object = nullptr;
    if (clsid != CLSID_FengYuTextService) {
        return CLASS_E_CLASSNOTAVAILABLE;
    }
    auto *factory = new FengYuClassFactory;
    const HRESULT result = factory->QueryInterface(riid, object);
    factory->Release();
    return result;
}

STDAPI DllCanUnloadNow() {
    return InterlockedCompareExchange(&g_object_count, 0, 0) == 0 &&
                   InterlockedCompareExchange(&g_server_lock_count, 0, 0) == 0
               ? S_OK
               : S_FALSE;
}
#endif
