// Bridges Windows audio headers into Swift and re-exports the macros that
// Swift's importer cannot bring in directly (function-like, composed, or
// using opaque casts).
#pragma once

#ifdef _WIN32

// Order matters: propsys.h must come before mmdeviceapi.h because the latter
// uses IPropertyStore** in OpenPropertyStore.
#include <windows.h>
#include <propsys.h>
#include <mmdeviceapi.h>
#include <audioclient.h>

// Macros not importable into Swift — exposed as concrete constants.
extern const DWORD    recmeet_CLSCTX_ALL;
extern const DWORD    recmeet_DEVICE_STATE_ACTIVE;
extern const DWORD    recmeet_AUDCLNT_STREAMFLAGS_LOOPBACK;
extern const DWORD    recmeet_AUDCLNT_BUFFERFLAGS_SILENT;
extern const DWORD    recmeet_STGM_READ;
extern const VARTYPE  recmeet_VT_LPWSTR;
extern const HRESULT  recmeet_E_FAIL;
extern const HRESULT  recmeet_S_OK;

// PropVariantInit / PropVariantClear are macros or live in propvarutil.h
// (which has its own include-ordering pain). We supply local equivalents
// for the only PROPVARIANT shape recmeet ever sees (VT_LPWSTR).
void    recmeet_PropVariantInit(PROPVARIANT *p);
HRESULT recmeet_PropVariantClear(PROPVARIANT *p);

// PKEY_Device_FriendlyName, defined manually so we don't need propkey.h /
// functiondiscoverykeys_devpkey.h.
extern const PROPERTYKEY recmeet_PKEY_Device_FriendlyName;

#endif // _WIN32
