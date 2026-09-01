#pragma once
#ifdef _WIN32
#include <msctf.h>
#include <ctfutb.h>
#include <windows.h>
#include <memory>

#include "FengYuGuids.h"

class FengYuTextServiceState;

class FengYuTextService final : public ITfTextInputProcessorEx,
                                public ITfKeyEventSink,
                                public ITfThreadMgrEventSink,
                                public ITfFunctionProvider {
public:
    FengYuTextService();
    virtual ~FengYuTextService();
    HRESULT STDMETHODCALLTYPE QueryInterface(REFIID, void**) override;
    ULONG STDMETHODCALLTYPE AddRef() override;
    ULONG STDMETHODCALLTYPE Release() override;
    HRESULT STDMETHODCALLTYPE Activate(ITfThreadMgr*, TfClientId) override;
    HRESULT STDMETHODCALLTYPE Deactivate() override;
    HRESULT STDMETHODCALLTYPE ActivateEx(ITfThreadMgr*, TfClientId, DWORD) override;
    HRESULT STDMETHODCALLTYPE OnSetFocus(BOOL) override { return S_OK; }
    HRESULT STDMETHODCALLTYPE OnTestKeyDown(ITfContext*, WPARAM, LPARAM, BOOL*) override;
    HRESULT STDMETHODCALLTYPE OnTestKeyUp(ITfContext*, WPARAM, LPARAM, BOOL*) override;
    HRESULT STDMETHODCALLTYPE OnKeyDown(ITfContext*, WPARAM, LPARAM, BOOL*) override;
    HRESULT STDMETHODCALLTYPE OnKeyUp(ITfContext*, WPARAM, LPARAM, BOOL*) override;
    HRESULT STDMETHODCALLTYPE OnPreservedKey(ITfContext*, REFGUID, BOOL*) override;
    HRESULT STDMETHODCALLTYPE OnInitDocumentMgr(ITfDocumentMgr*) override;
    HRESULT STDMETHODCALLTYPE OnUninitDocumentMgr(ITfDocumentMgr*) override;
    HRESULT STDMETHODCALLTYPE OnSetFocus(ITfDocumentMgr*, ITfDocumentMgr*) override;
    HRESULT STDMETHODCALLTYPE OnPushContext(ITfContext*) override;
    HRESULT STDMETHODCALLTYPE OnPopContext(ITfContext*) override;
    HRESULT STDMETHODCALLTYPE GetType(GUID*) override;
    HRESULT STDMETHODCALLTYPE GetDescription(BSTR*) override;
    HRESULT STDMETHODCALLTYPE GetFunction(REFGUID, REFIID, IUnknown**) override;
private:
    bool MapKey(ITfContext*, WPARAM, uint32_t*, uint32_t*) const;
    void RemoveContext(ITfContext*);
    void RemoveDocumentManager(ITfDocumentMgr*);
    void ConfigureInputMode(ITfContext*);
    void RegisterLanguageBarItem();
    void UnregisterLanguageBarItem();

    LONG refs_ = 1;
    ITfThreadMgr *thread_manager_ = nullptr;
    ITfKeystrokeMgr *keystroke_manager_ = nullptr;
    ITfLangBarItemMgr *language_bar_item_manager_ = nullptr;
    ITfLangBarItemButton *language_bar_item_ = nullptr;
    ITfSource *thread_source_ = nullptr;
    TfClientId client_id_ = TF_CLIENTID_NULL;
    DWORD thread_event_sink_cookie_ = TF_INVALID_COOKIE;
    bool key_sink_advised_ = false;
    std::unique_ptr<FengYuTextServiceState> state_;
};
#endif
