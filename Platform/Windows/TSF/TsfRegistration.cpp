#include "FengYuGuids.h"

#include <msctf.h>
#include <objbase.h>
#include <shellapi.h>
#include <windows.h>

#include <filesystem>
#include <iostream>
#include <string>

namespace {
constexpr wchar_t kDisplayName[] = L"风语输入法";
// Profiles used by pre-1.0.20 builds.  They are removed during upgrade so
// Windows does not leave three stale input-method entries behind.
constexpr GUID GUID_FengYuLegacyPhoneticProfile = {
    0x2ef9f6e4, 0x3b57, 0x4e74, {0x9c, 0x88, 0x57, 0xa2, 0x0a, 0xb9, 0x6d, 0x61}};
constexpr GUID GUID_FengYuLegacyFullPinyinProfile = {
    0x2d6ae948, 0x4c24, 0x4d7e, {0x96, 0x2e, 0x74, 0x2e, 0x36, 0x77, 0x6f, 0x0a}};

void PrintFailure(const wchar_t *stage, HRESULT result) {
    if (FAILED(result)) {
        std::wcerr << stage << L" failed: 0x" << std::hex
                   << static_cast<unsigned long>(result) << std::dec << L'\n';
    }
}

class ComInitialization {
public:
    ComInitialization() : result_(CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED)) {}
    ~ComInitialization() {
        if (SUCCEEDED(result_)) {
            CoUninitialize();
        }
    }
    HRESULT result() const { return result_; }

private:
    HRESULT result_;
};

std::wstring GuidToString(REFGUID guid) {
    wchar_t value[40]{};
    return StringFromGUID2(guid, value, static_cast<int>(std::size(value))) > 0
               ? value
               : L"";
}

std::wstring ComRegistryPath() {
    return L"Software\\Classes\\CLSID\\" + GuidToString(CLSID_FengYuTextService);
}

bool SetStringValue(HKEY key, const wchar_t *name, const std::wstring &value) {
    return RegSetValueExW(
               key, name, 0, REG_SZ,
               reinterpret_cast<const BYTE *>(value.c_str()),
               static_cast<DWORD>((value.size() + 1) * sizeof(wchar_t))) ==
           ERROR_SUCCESS;
}

bool RegisterComServer(const std::filesystem::path &dll_path) {
    HKEY class_key = nullptr;
    const std::wstring class_path = ComRegistryPath();
    if (RegCreateKeyExW(HKEY_LOCAL_MACHINE, class_path.c_str(), 0, nullptr, 0,
                        KEY_WRITE, nullptr, &class_key, nullptr) != ERROR_SUCCESS) {
        return false;
    }
    const bool class_name_written = SetStringValue(class_key, nullptr, kDisplayName);
    RegCloseKey(class_key);
    if (!class_name_written) {
        return false;
    }

    HKEY server_key = nullptr;
    const std::wstring server_path = class_path + L"\\InprocServer32";
    if (RegCreateKeyExW(HKEY_LOCAL_MACHINE, server_path.c_str(), 0, nullptr, 0,
                        KEY_WRITE, nullptr, &server_key, nullptr) != ERROR_SUCCESS) {
        return false;
    }
    const bool path_written = SetStringValue(server_key, nullptr, dll_path.wstring());
    const bool model_written = SetStringValue(server_key, L"ThreadingModel", L"Both");
    RegCloseKey(server_key);
    return path_written && model_written;
}

void UnregisterComServer() {
    RegDeleteTreeW(HKEY_LOCAL_MACHINE, ComRegistryPath().c_str());
}

HRESULT CreateProfiles(ITfInputProcessorProfiles **profiles) {
    return CoCreateInstance(
        CLSID_TF_InputProcessorProfiles, nullptr, CLSCTX_INPROC_SERVER,
        IID_ITfInputProcessorProfiles, reinterpret_cast<void **>(profiles));
}

HRESULT CreateCategoryManager(ITfCategoryMgr **categories) {
    return CoCreateInstance(
        CLSID_TF_CategoryMgr, nullptr, CLSCTX_INPROC_SERVER,
        IID_ITfCategoryMgr, reinterpret_cast<void **>(categories));
}

HRESULT CreateProfileManager(ITfInputProcessorProfileMgr **manager) {
    return CoCreateInstance(
        CLSID_TF_InputProcessorProfiles, nullptr, CLSCTX_INPROC_SERVER,
        IID_ITfInputProcessorProfileMgr,
        reinterpret_cast<void **>(manager));
}

bool UnregisterTsf() {
    bool success = true;
    ITfInputProcessorProfileMgr *manager = nullptr;
    if (SUCCEEDED(CreateProfileManager(&manager))) {
        for (const GUID &guid : {GUID_FengYuLanguageProfile,
                                 GUID_FengYuLegacyPhoneticProfile,
                                 GUID_FengYuLegacyFullPinyinProfile}) {
            manager->UnregisterProfile(CLSID_FengYuTextService,
                LANGID_FengYuChineseSimplified, guid, 0);
        }
        manager->Release();
    }
    ITfInputProcessorProfiles *profiles = nullptr;
    if (SUCCEEDED(CreateProfiles(&profiles))) {
        for (const GUID &guid : {GUID_FengYuLanguageProfile,
                                 GUID_FengYuLegacyPhoneticProfile,
                                 GUID_FengYuLegacyFullPinyinProfile}) {
            profiles->EnableLanguageProfile(CLSID_FengYuTextService,
                LANGID_FengYuChineseSimplified, guid, FALSE);
            profiles->EnableLanguageProfileByDefault(CLSID_FengYuTextService,
                LANGID_FengYuChineseSimplified, guid, FALSE);
            profiles->RemoveLanguageProfile(CLSID_FengYuTextService,
                LANGID_FengYuChineseSimplified, guid);
        }
        const HRESULT unregister_result = profiles->Unregister(CLSID_FengYuTextService);
        success = SUCCEEDED(unregister_result) || unregister_result == E_FAIL;
        profiles->Release();
    }

    ITfCategoryMgr *categories = nullptr;
    if (SUCCEEDED(CreateCategoryManager(&categories))) {
        categories->UnregisterCategory(
            CLSID_FengYuTextService, GUID_TFCAT_TIP_KEYBOARD,
            CLSID_FengYuTextService);
        categories->UnregisterCategory(
            CLSID_FengYuTextService, GUID_TFCAT_TIPCAP_IMMERSIVESUPPORT,
            CLSID_FengYuTextService);
        categories->UnregisterCategory(
            CLSID_FengYuTextService, GUID_TFCAT_TIPCAP_SYSTRAYSUPPORT,
            CLSID_FengYuTextService);
        categories->Release();
    }
    return success;
}

bool RegisterTsf(const std::filesystem::path &dll_path) {
    ITfInputProcessorProfiles *profiles = nullptr;
    HRESULT result = CreateProfiles(&profiles);
    if (FAILED(result)) {
        PrintFailure(L"CreateProfiles", result);
        return false;
    }
    result = profiles->Register(CLSID_FengYuTextService);
    PrintFailure(L"ITfInputProcessorProfiles::Register", result);
    if (SUCCEEDED(result)) {
        ITfInputProcessorProfileMgr *manager = nullptr;
        result = CreateProfileManager(&manager);
        if (SUCCEEDED(result)) {
            // Clean up profiles created by older packages before registering
            // the single configurable profile.
            for (const GUID &guid : {GUID_FengYuLegacyPhoneticProfile,
                                     GUID_FengYuLegacyFullPinyinProfile}) {
                manager->UnregisterProfile(CLSID_FengYuTextService,
                    LANGID_FengYuChineseSimplified, guid, 0);
                profiles->RemoveLanguageProfile(CLSID_FengYuTextService,
                    LANGID_FengYuChineseSimplified, guid);
            }
            result = manager->RegisterProfile(
                CLSID_FengYuTextService, LANGID_FengYuChineseSimplified,
                GUID_FengYuLanguageProfile, kDisplayName,
                static_cast<ULONG>(std::size(kDisplayName) - 1),
                dll_path.c_str(),
                static_cast<ULONG>(dll_path.native().size()), 0,
                nullptr, 0, TRUE, 0);
            manager->Release();
        }
    }
    PrintFailure(L"ITfInputProcessorProfileMgr::RegisterProfile", result);
    if (SUCCEEDED(result)) {
        result = profiles->EnableLanguageProfileByDefault(
            CLSID_FengYuTextService, LANGID_FengYuChineseSimplified,
            GUID_FengYuLanguageProfile, TRUE);
    }
    PrintFailure(L"ITfInputProcessorProfiles::EnableLanguageProfileByDefault", result);
    if (SUCCEEDED(result)) {
        result = profiles->EnableLanguageProfile(
            CLSID_FengYuTextService, LANGID_FengYuChineseSimplified,
            GUID_FengYuLanguageProfile, TRUE);
    }
    PrintFailure(L"ITfInputProcessorProfiles::EnableLanguageProfile", result);
    profiles->Release();
    if (FAILED(result)) {
        return false;
    }

    ITfCategoryMgr *categories = nullptr;
    result = CreateCategoryManager(&categories);
    if (FAILED(result)) {
        PrintFailure(L"CreateCategoryManager", result);
        return false;
    }
    for (const GUID &category : {GUID_TFCAT_TIP_KEYBOARD,
                                 GUID_TFCAT_TIPCAP_IMMERSIVESUPPORT,
                                 GUID_TFCAT_TIPCAP_SYSTRAYSUPPORT}) {
        result = categories->RegisterCategory(
            CLSID_FengYuTextService, category, CLSID_FengYuTextService);
        if (FAILED(result)) {
            PrintFailure(L"ITfCategoryMgr::RegisterCategory", result);
            categories->Release();
            return false;
        }
    }
    categories->Release();
    return true;
}

bool ProfileExistsAndIsEnabled(ITfInputProcessorProfiles *profiles) {
    IEnumTfLanguageProfiles *enumerator = nullptr;
    if (FAILED(profiles->EnumLanguageProfiles(
            LANGID_FengYuChineseSimplified, &enumerator))) {
        return false;
    }
    bool found = false;
    TF_LANGUAGEPROFILE profile{};
    ULONG fetched = 0;
    while (enumerator->Next(1, &profile, &fetched) == S_OK && fetched == 1) {
        if (profile.clsid == CLSID_FengYuTextService &&
            profile.guidProfile == GUID_FengYuLanguageProfile) {
            found = true;
            break;
        }
    }
    enumerator->Release();
    return found;
}

int SetCurrentUserProfileEnabled(bool enabled, bool activate_session = false) {
    ITfInputProcessorProfileMgr *manager = nullptr;
    HRESULT result = CreateProfileManager(&manager);
    if (SUCCEEDED(result)) {
        DWORD flags = enabled ? TF_IPPMF_ENABLEPROFILE : TF_IPPMF_DISABLEPROFILE;
        if (enabled) {
            flags |= TF_IPPMF_DONTCARECURRENTINPUTLANGUAGE;
        }
        if (activate_session) {
            flags |= TF_IPPMF_FORSESSION;
        }
        result = manager->ActivateProfile(
            TF_PROFILETYPE_INPUTPROCESSOR, LANGID_FengYuChineseSimplified,
            CLSID_FengYuTextService, GUID_FengYuLanguageProfile, nullptr, flags);
        manager->Release();
    }
    PrintFailure(
        enabled ? L"Enable current-user language profile"
                : L"Disable current-user language profile",
        result);
    if (FAILED(result)) {
        return 8;
    }
    std::wcout << L"currentUserProfile="
               << (enabled ? L"enabled" : L"disabled") << L'\n';
    return 0;
}

int RegisterCurrentUserProfile(const std::filesystem::path &dll_path) {
    std::error_code error;
    const auto absolute_path = std::filesystem::weakly_canonical(dll_path, error);
    if (error || !std::filesystem::is_regular_file(absolute_path)) {
        std::wcerr << L"fy_tsf.dll not found: " << dll_path.wstring() << L'\n';
        return 2;
    }
    ITfInputProcessorProfileMgr *manager = nullptr;
    HRESULT result = CreateProfileManager(&manager);
    if (SUCCEEDED(result)) {
        result = manager->RegisterProfile(
            CLSID_FengYuTextService, LANGID_FengYuChineseSimplified,
            GUID_FengYuLanguageProfile, kDisplayName,
            static_cast<ULONG>(std::size(kDisplayName) - 1),
            absolute_path.c_str(),
            static_cast<ULONG>(absolute_path.native().size()), 0,
            nullptr, 0, TRUE, 0);
        manager->Release();
    }
    PrintFailure(L"ITfInputProcessorProfileMgr::RegisterProfile", result);
    return FAILED(result) ? 9 : 0;
}

bool RegistryPathMatches(const std::filesystem::path &expected_path) {
    HKEY key = nullptr;
    const std::wstring path = ComRegistryPath() + L"\\InprocServer32";
    if (RegOpenKeyExW(HKEY_LOCAL_MACHINE, path.c_str(), 0, KEY_READ, &key) !=
        ERROR_SUCCESS) {
        return false;
    }
    wchar_t value[32768]{};
    DWORD type = 0;
    DWORD bytes = sizeof(value);
    const LSTATUS result = RegQueryValueExW(
        key, nullptr, nullptr, &type, reinterpret_cast<BYTE *>(value), &bytes);
    RegCloseKey(key);
    if (result != ERROR_SUCCESS || type != REG_SZ) {
        return false;
    }
    std::error_code error;
    return std::filesystem::equivalent(expected_path, value, error) && !error;
}

bool CheckStatus(const std::filesystem::path &dll_path) {
    const bool registry_ok = RegistryPathMatches(dll_path);
    std::wcout << L"comRegistry=" << (registry_ok ? L"ok" : L"failed") << L'\n';

    IUnknown *service = nullptr;
    const HRESULT create_result = CoCreateInstance(
        CLSID_FengYuTextService, nullptr, CLSCTX_INPROC_SERVER, IID_IUnknown,
        reinterpret_cast<void **>(&service));
    const bool cocreate_ok = SUCCEEDED(create_result) && service;
    if (service) {
        service->Release();
    }
    std::wcout << L"coCreateInstance=" << (cocreate_ok ? L"ok" : L"failed")
               << L" hresult=0x" << std::hex
               << static_cast<unsigned long>(create_result) << std::dec << L'\n';

    bool profile_ok = false;
    ITfInputProcessorProfileMgr *profile_manager = nullptr;
    const HRESULT manager_result = CreateProfileManager(&profile_manager);
    HRESULT get_profile_result = manager_result;
    TF_INPUTPROCESSORPROFILE modern_profile{};
    if (SUCCEEDED(manager_result)) {
        get_profile_result = profile_manager->GetProfile(
            TF_PROFILETYPE_INPUTPROCESSOR, LANGID_FengYuChineseSimplified,
            CLSID_FengYuTextService, GUID_FengYuLanguageProfile, nullptr,
            &modern_profile);
        profile_manager->Release();
    }
    const bool manager_found = SUCCEEDED(get_profile_result);
    const bool manager_enabled =
        manager_found && (modern_profile.dwFlags & TF_IPP_FLAG_ENABLED) != 0;
    const bool manager_active =
        manager_found && (modern_profile.dwFlags & TF_IPP_FLAG_ACTIVE) != 0;
    std::wcout << L"profileManager=" << (manager_found ? L"found" : L"failed")
               << L" enabled=" << (manager_enabled ? L"yes" : L"no")
               << L" active=" << (manager_active ? L"yes" : L"no")
               << L" hresult=0x" << std::hex
               << static_cast<unsigned long>(get_profile_result) << std::dec << L'\n';
    ITfInputProcessorProfileMgr *active_manager = nullptr;
    TF_INPUTPROCESSORPROFILE active_profile{};
    const HRESULT active_result = CreateProfileManager(&active_manager);
    HRESULT active_profile_result = active_result;
    if (SUCCEEDED(active_result)) {
        active_profile_result = active_manager->GetActiveProfile(
            GUID_TFCAT_TIP_KEYBOARD, &active_profile);
        active_manager->Release();
    }
    std::wcout << L"activeProfile hresult=0x" << std::hex
               << static_cast<unsigned long>(active_profile_result) << std::dec;
    if (SUCCEEDED(active_profile_result)) {
        std::wcout << L" langid=0x" << std::hex << active_profile.langid
                   << L" clsid=" << GuidToString(active_profile.clsid)
                   << L" profile=" << GuidToString(active_profile.guidProfile)
                   << std::dec;
    }
    std::wcout << L'\n';

    ITfInputProcessorProfiles *profiles = nullptr;
    if (SUCCEEDED(CreateProfiles(&profiles))) {
        BOOL enabled = FALSE;
        const HRESULT enabled_result = profiles->IsEnabledLanguageProfile(
            CLSID_FengYuTextService, LANGID_FengYuChineseSimplified,
            GUID_FengYuLanguageProfile, &enabled);
        const bool enumerated = ProfileExistsAndIsEnabled(profiles);
        std::wcout << L"profileCheck=enumerated:"
                   << (enumerated ? L"yes" : L"no")
                   << L" enabled:" << (enabled ? L"yes" : L"no")
                   << L" hresult=0x" << std::hex
                   << static_cast<unsigned long>(enabled_result) << std::dec << L'\n';
        // On some Windows 11 builds GetProfile/EnumLanguageProfiles return
        // E_FAIL for a TSF profile that is nevertheless registered and
        // enabled (the registry and IsEnabledLanguageProfile are authoritative
        // in that case).  Do not report a healthy installation as broken just
        // because those optional enumeration APIs are unavailable.
        profile_ok = manager_enabled || (SUCCEEDED(enabled_result) && enabled);
        profiles->Release();
    }
    std::wcout << L"languageProfile=" << (profile_ok ? L"enabled" : L"failed")
               << L'\n';
    return registry_ok && cocreate_ok && profile_ok;
}

int Register(const std::filesystem::path &dll_path) {
    std::error_code error;
    const auto absolute_path = std::filesystem::weakly_canonical(dll_path, error);
    if (error || !std::filesystem::is_regular_file(absolute_path)) {
        std::wcerr << L"fy_tsf.dll not found: " << dll_path.wstring() << L'\n';
        return 2;
    }
    UnregisterTsf();
    UnregisterComServer();
    if (!RegisterComServer(absolute_path) || !RegisterTsf(absolute_path)) {
        UnregisterTsf();
        UnregisterComServer();
        std::wcerr << L"Registration failed and was rolled back.\n";
        return 3;
    }
    std::wcout << L"registration=ok\n";
    return 0;
}

int Unregister() {
    const bool tsf_result = UnregisterTsf();
    UnregisterComServer();
    std::wcout << L"unregister=" << (tsf_result ? L"ok" : L"partial") << L'\n';
    return tsf_result ? 0 : 5;
}
}

int RunRegistrationCommand(int argc, wchar_t **argv) {
    if (argc < 2) {
        std::wcerr << L"Usage: fy_tsf_registration register <fy_tsf.dll> | "
                      L"unregister | register-profile <fy_tsf.dll> | enable | activate | disable | "
                      L"status <fy_tsf.dll>\n";
        return 1;
    }
    ComInitialization com;
    if (FAILED(com.result())) {
        std::wcerr << L"COM initialization failed.\n";
        return 6;
    }
    const std::wstring command = argv[1];
    if (command == L"register" && argc == 3) {
        return Register(argv[2]);
    }
    if (command == L"unregister") {
        return Unregister();
    }
    if (command == L"register-profile" && argc == 3) {
        return RegisterCurrentUserProfile(argv[2]);
    }
    if (command == L"enable") {
        return SetCurrentUserProfileEnabled(true);
    }
    if (command == L"activate") {
        return SetCurrentUserProfileEnabled(true, true);
    }
    if (command == L"disable") {
        return SetCurrentUserProfileEnabled(false);
    }
    if (command == L"status" && argc == 3) {
        return CheckStatus(argv[2]) ? 0 : 7;
    }
    std::wcerr << L"Invalid command.\n";
    return 1;
}

int WINAPI wWinMain(HINSTANCE, HINSTANCE, PWSTR, int) {
    int argument_count = 0;
    wchar_t **arguments = CommandLineToArgvW(GetCommandLineW(), &argument_count);
    if (!arguments) {
        return 1;
    }
    const int result = RunRegistrationCommand(argument_count, arguments);
    LocalFree(arguments);
    return result;
}
