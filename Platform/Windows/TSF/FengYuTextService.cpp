#include "FengYuTextService.h"
#ifdef _WIN32
#include "fy_engine.h"
FengYuTextService::FengYuTextService() = default;
FengYuTextService::~FengYuTextService(){if(thread_manager_)thread_manager_->Release();}
HRESULT FengYuTextService::QueryInterface(REFIID riid,void**pp){if(!pp)return E_POINTER;*pp=nullptr;if(riid==IID_IUnknown||riid==IID_ITfTextInputProcessor||riid==IID_ITfTextInputProcessorEx)*pp=static_cast<ITfTextInputProcessorEx*>(this);else if(riid==IID_ITfKeyEventSink)*pp=static_cast<ITfKeyEventSink*>(this);else return E_NOINTERFACE;AddRef();return S_OK;}
ULONG FengYuTextService::AddRef(){return InterlockedIncrement(&refs_);} ULONG FengYuTextService::Release(){ULONG n=InterlockedDecrement(&refs_);if(!n)delete this;return n;}
HRESULT FengYuTextService::Activate(ITfThreadMgr*m,TfClientId id){return ActivateEx(m,id,0);} HRESULT FengYuTextService::ActivateEx(ITfThreadMgr*m,TfClientId id,DWORD){if(!m)return E_INVALIDARG;if(thread_manager_)thread_manager_->Release();thread_manager_=m;thread_manager_->AddRef();client_id_=id;return S_OK;} HRESULT FengYuTextService::Deactivate(){if(thread_manager_){thread_manager_->Release();thread_manager_=nullptr;}client_id_=TF_CLIENTID_NULL;return S_OK;}
HRESULT FengYuTextService::OnTestKeyDown(ITfContext*,WPARAM w,LPARAM,BOOL*e){if(!e)return E_POINTER;*e=(w>='a'&&w<='z')||(w>='A'&&w<='Z')||w=='-'||w=='=';return S_OK;} HRESULT FengYuTextService::OnTestKeyUp(ITfContext*,WPARAM,LPARAM,BOOL*e){if(!e)return E_POINTER;*e=FALSE;return S_OK;} HRESULT FengYuTextService::OnKeyDown(ITfContext*c,WPARAM w,LPARAM l,BOOL*e){return OnTestKeyDown(c,w,l,e);} HRESULT FengYuTextService::OnKeyUp(ITfContext*c,WPARAM w,LPARAM l,BOOL*e){return OnTestKeyUp(c,w,l,e);}
#endif
