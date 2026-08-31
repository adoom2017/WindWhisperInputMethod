#pragma once
#ifdef _WIN32
#include <msctf.h>
#include <windows.h>

class FengYuTextService final : public ITfTextInputProcessorEx, public ITfKeyEventSink {
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
private:
    LONG refs_ = 1; ITfThreadMgr *thread_manager_ = nullptr; TfClientId client_id_ = TF_CLIENTID_NULL;
};
#endif
