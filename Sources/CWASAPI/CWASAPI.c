#ifdef _WIN32

// `INITGUID` makes every `DEFINE_GUID(...)` in the included headers emit a
// concrete definition into THIS translation unit. That's how we get
// `CLSID_MMDeviceEnumerator`, `IID_IAudioClient`, `IID_IMMDeviceEnumerator`,
// `IID_IAudioCaptureClient`, and `PKEY_Device_FriendlyName` linked into
// the app without depending on extra GUID libraries.
#define INITGUID

#include "CWASAPI.h"
#include <string.h>

const DWORD   recmeet_CLSCTX_ALL                  = CLSCTX_ALL;
const DWORD   recmeet_DEVICE_STATE_ACTIVE         = DEVICE_STATE_ACTIVE;
const DWORD   recmeet_AUDCLNT_STREAMFLAGS_LOOPBACK = AUDCLNT_STREAMFLAGS_LOOPBACK;
const DWORD   recmeet_AUDCLNT_BUFFERFLAGS_SILENT  = AUDCLNT_BUFFERFLAGS_SILENT;
const DWORD   recmeet_STGM_READ                   = STGM_READ;
const VARTYPE recmeet_VT_LPWSTR                   = VT_LPWSTR;
const HRESULT recmeet_E_FAIL                      = E_FAIL;
const HRESULT recmeet_S_OK                        = S_OK;

void recmeet_PropVariantInit(PROPVARIANT *p) {
    memset(p, 0, sizeof(PROPVARIANT));
}

const PROPERTYKEY recmeet_PKEY_Device_FriendlyName = {
    { 0xa45c254e, 0xdf1c, 0x4efd, { 0x80, 0x20, 0x67, 0xd1, 0x46, 0xa8, 0x50, 0xe0 } },
    14
};

#endif // _WIN32
