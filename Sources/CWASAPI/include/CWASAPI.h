// Bridges Windows audio headers into Swift and re-exports the macros that
// Swift's importer cannot bring in directly (function-like, composed, or
// using opaque casts).
#pragma once

#ifdef _WIN32

#include <windows.h>
#include <mmdeviceapi.h>
#include <audioclient.h>
#include <functiondiscoverykeys_devpkey.h>
#include <propvarutil.h>
#include <propkey.h>

// Macros not importable into Swift — exposed as concrete constants.
extern const DWORD    recmeet_CLSCTX_ALL;
extern const DWORD    recmeet_DEVICE_STATE_ACTIVE;
extern const DWORD    recmeet_AUDCLNT_STREAMFLAGS_LOOPBACK;
extern const DWORD    recmeet_AUDCLNT_BUFFERFLAGS_SILENT;
extern const DWORD    recmeet_STGM_READ;
extern const VARTYPE  recmeet_VT_LPWSTR;
extern const HRESULT  recmeet_E_FAIL;
extern const HRESULT  recmeet_S_OK;

// `PropVariantInit` is a function-like macro on MSVC; wrap as a real function.
void recmeet_PropVariantInit(PROPVARIANT *p);

// `PKEY_Device_FriendlyName` is normally provided by linking propsys.lib;
// re-expose the storage so Swift can take its address.
extern const PROPERTYKEY recmeet_PKEY_Device_FriendlyName;

#endif // _WIN32
