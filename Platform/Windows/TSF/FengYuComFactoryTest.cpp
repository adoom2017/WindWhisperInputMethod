#include "FengYuTextService.h"
#include <ctffunc.h>

#define CHECK(condition) \
    do {                 \
        if (!(condition)) { \
            return __LINE__; \
        }                \
    } while (false)

int main() {
    CHECK(SUCCEEDED(CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED)));
    const HMODULE module = LoadLibraryW(L"fy_tsf.dll");
    CHECK(module != nullptr);
    const auto get_class_object = reinterpret_cast<LPFNGETCLASSOBJECT>(
        GetProcAddress(module, "DllGetClassObject"));
    const auto can_unload_now = reinterpret_cast<LPFNCANUNLOADNOW>(
        GetProcAddress(module, "DllCanUnloadNow"));
    CHECK(get_class_object != nullptr);
    CHECK(can_unload_now != nullptr);
    CHECK(can_unload_now() == S_OK);

    IClassFactory *factory = nullptr;
    CHECK(get_class_object(CLSID_NULL, IID_IClassFactory,
                           reinterpret_cast<void **>(&factory)) ==
          CLASS_E_CLASSNOTAVAILABLE);
    CHECK(factory == nullptr);

    CHECK(SUCCEEDED(get_class_object(
        CLSID_FengYuTextService, IID_IClassFactory,
        reinterpret_cast<void **>(&factory))));
    CHECK(factory != nullptr);
    CHECK(can_unload_now() == S_FALSE);

    ITfTextInputProcessorEx *service = nullptr;
    CHECK(SUCCEEDED(factory->CreateInstance(
        nullptr, IID_ITfTextInputProcessorEx,
        reinterpret_cast<void **>(&service))));
    CHECK(service != nullptr);

    ITfFunctionProvider *provider = nullptr;
    CHECK(SUCCEEDED(service->QueryInterface(
        IID_ITfFunctionProvider, reinterpret_cast<void **>(&provider))));
    CHECK(provider != nullptr);
    ITfFnConfigure *configure = nullptr;
    CHECK(SUCCEEDED(provider->GetFunction(
        GUID_NULL, IID_ITfFnConfigure, reinterpret_cast<IUnknown **>(&configure))));
    CHECK(configure != nullptr);
    BSTR configure_name = nullptr;
    CHECK(SUCCEEDED(configure->GetDisplayName(&configure_name)));
    CHECK(configure_name != nullptr);
    SysFreeString(configure_name);
    configure->Release();
    provider->Release();

    ITfKeyEventSink *key_sink = nullptr;
    CHECK(SUCCEEDED(service->QueryInterface(
        IID_ITfKeyEventSink, reinterpret_cast<void **>(&key_sink))));

    ITfThreadMgrEventSink *thread_sink = nullptr;
    CHECK(SUCCEEDED(service->QueryInterface(
        IID_ITfThreadMgrEventSink, reinterpret_cast<void **>(&thread_sink))));

    ITfThreadMgr *thread_manager = nullptr;
    CHECK(SUCCEEDED(CoCreateInstance(
        CLSID_TF_ThreadMgr, nullptr, CLSCTX_INPROC_SERVER, IID_ITfThreadMgr,
        reinterpret_cast<void **>(&thread_manager))));
    TfClientId client_id = TF_CLIENTID_NULL;
    CHECK(SUCCEEDED(thread_manager->Activate(&client_id)));
    CHECK(client_id != TF_CLIENTID_NULL);

    key_sink->Release();
    thread_sink->Release();

    const HRESULT activation_result = service->ActivateEx(thread_manager, client_id, 0);
    CHECK(SUCCEEDED(activation_result) || activation_result == E_INVALIDARG);

    using CreateLangBarItemMgr = HRESULT(WINAPI *)(ITfLangBarItemMgr **);
    const HMODULE tsf_module = LoadLibraryW(L"msctf.dll");
    CHECK(tsf_module != nullptr);
    const auto create_lang_bar_item_mgr =
        reinterpret_cast<CreateLangBarItemMgr>(GetProcAddress(
            tsf_module, "TF_CreateLangBarItemMgr"));
    CHECK(create_lang_bar_item_mgr != nullptr);
    ITfLangBarItemMgr *item_manager = nullptr;
    CHECK(SUCCEEDED(create_lang_bar_item_mgr(&item_manager)));
    item_manager->Release();
    FreeLibrary(tsf_module);
    CHECK(SUCCEEDED(service->Deactivate()));
    CHECK(SUCCEEDED(thread_manager->Deactivate()));
    thread_manager->Release();

    service->Release();
    factory->Release();

    CHECK(can_unload_now() == S_OK);
    CHECK(FreeLibrary(module));
    CoUninitialize();
    return 0;
}
