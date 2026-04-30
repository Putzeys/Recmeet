#ifdef _WIN32

// Compiled as ordinary C. COBJMACROS lets us call interface methods as
// IMMDevice_GetId(p, ...) instead of dancing through ->lpVtbl->GetId.
//
// We deliberately do NOT use INITGUID here — clang on Windows did not expand
// DEFINE_GUID into storage definitions reliably, leaving us with linker
// errors for CLSID_MMDeviceEnumerator etc. Instead, we provide explicit
// definitions for every GUID we reference. The headers themselves only
// declare them (DEFINE_GUID without INITGUID = `extern const GUID`), so
// there is no duplicate-definition conflict.
#define COBJMACROS

#include <windows.h>
#include <propsys.h>
#include <mmdeviceapi.h>
#include <audioclient.h>
#include <stdlib.h>
#include <string.h>
#include <wchar.h>

#include "CWASAPI.h"

// MARK: - GUID storage definitions (would normally come from mmdevapi.lib /
// uuid.lib, but we don't take that dependency).

const CLSID CLSID_MMDeviceEnumerator = {
    0xBCDE0395, 0xE52F, 0x467C,
    { 0x8E, 0x3D, 0xC4, 0x57, 0x92, 0x91, 0x69, 0x2E }
};
const IID IID_IMMDeviceEnumerator = {
    0xA95664D2, 0x9614, 0x4F35,
    { 0xA7, 0x46, 0xDE, 0x8D, 0xB6, 0x36, 0x17, 0xE6 }
};
const IID IID_IAudioClient = {
    0x1CB9AD4C, 0xDBFA, 0x4C32,
    { 0xB1, 0x78, 0xC2, 0xF5, 0x68, 0xA7, 0x03, 0xB2 }
};
const IID IID_IAudioCaptureClient = {
    0xC8ADBD64, 0xE71E, 0x48A0,
    { 0xA4, 0xDE, 0x18, 0x5C, 0x39, 0x5C, 0xD3, 0x17 }
};

// PKEY_Device_FriendlyName, defined manually so we don't need
// functiondiscoverykeys_devpkey.h (and its include-chain pain).
static const PROPERTYKEY kPKEY_Device_FriendlyName = {
    { 0xa45c254e, 0xdf1c, 0x4efd, { 0x80, 0x20, 0x67, 0xd1, 0x46, 0xa8, 0x50, 0xe0 } },
    14
};

const UINT32  recmeet_AUDCLNT_BUFFERFLAGS_SILENT = AUDCLNT_BUFFERFLAGS_SILENT;
const HRESULT recmeet_E_FAIL                     = E_FAIL;

// MARK: - Internal types

typedef struct {
    IMMDevice *raw;
    BOOL       is_default_capture;
} dev_impl;

typedef struct {
    IMMDevice           *device;        // owned (AddRef'd)
    IAudioClient        *client;
    IAudioCaptureClient *capture;
    recmeet_format_t     format;
} cap_impl;

static dev_impl *as_dev(recmeet_device_t h) { return (dev_impl *)h; }
static cap_impl *as_cap(recmeet_capture_t h) { return (cap_impl *)h; }

// MARK: - Init

HRESULT recmeet_init(void) {
    HRESULT hr = CoInitializeEx(NULL, COINIT_MULTITHREADED);
    // S_FALSE just means "already initialised on this thread" — treat as success.
    return (hr == S_FALSE) ? S_OK : hr;
}

void recmeet_shutdown(void) {
    CoUninitialize();
}

// MARK: - Enumerator helper

static IMMDeviceEnumerator *make_enumerator(void) {
    IMMDeviceEnumerator *e = NULL;
    HRESULT hr = CoCreateInstance(
        &CLSID_MMDeviceEnumerator,
        NULL,
        CLSCTX_ALL,
        &IID_IMMDeviceEnumerator,
        (void **)&e
    );
    return SUCCEEDED(hr) ? e : NULL;
}

static dev_impl *wrap_device(IMMDevice *raw, BOOL is_default) {
    if (!raw) return NULL;
    dev_impl *d = (dev_impl *)calloc(1, sizeof(dev_impl));
    if (!d) {
        IMMDevice_Release(raw);
        return NULL;
    }
    d->raw = raw;
    d->is_default_capture = is_default;
    return d;
}

// MARK: - Public device API

int recmeet_enumerate_capture_devices(recmeet_device_t *out_devices, int max_count) {
    if (!out_devices || max_count <= 0) return 0;
    IMMDeviceEnumerator *e = make_enumerator();
    if (!e) return 0;

    LPWSTR default_id = NULL;
    {
        IMMDevice *def = NULL;
        if (SUCCEEDED(IMMDeviceEnumerator_GetDefaultAudioEndpoint(e, eCapture, eConsole, &def)) && def) {
            IMMDevice_GetId(def, &default_id);
            IMMDevice_Release(def);
        }
    }

    IMMDeviceCollection *col = NULL;
    HRESULT hr = IMMDeviceEnumerator_EnumAudioEndpoints(e, eCapture, DEVICE_STATE_ACTIVE, &col);
    IMMDeviceEnumerator_Release(e);
    if (FAILED(hr) || !col) {
        if (default_id) CoTaskMemFree(default_id);
        return 0;
    }

    UINT count = 0;
    IMMDeviceCollection_GetCount(col, &count);
    int written = 0;
    for (UINT i = 0; i < count && written < max_count; i++) {
        IMMDevice *raw = NULL;
        if (SUCCEEDED(IMMDeviceCollection_Item(col, i, &raw)) && raw) {
            BOOL is_default = FALSE;
            if (default_id) {
                LPWSTR id = NULL;
                IMMDevice_GetId(raw, &id);
                if (id) {
                    is_default = (wcscmp(id, default_id) == 0);
                    CoTaskMemFree(id);
                }
            }
            dev_impl *d = wrap_device(raw, is_default);
            if (d) {
                out_devices[written++] = (recmeet_device_t)d;
            }
        }
    }
    IMMDeviceCollection_Release(col);
    if (default_id) CoTaskMemFree(default_id);
    return written;
}

recmeet_device_t recmeet_default_capture_device(void) {
    IMMDeviceEnumerator *e = make_enumerator();
    if (!e) return NULL;
    IMMDevice *raw = NULL;
    HRESULT hr = IMMDeviceEnumerator_GetDefaultAudioEndpoint(e, eCapture, eConsole, &raw);
    IMMDeviceEnumerator_Release(e);
    return SUCCEEDED(hr) ? (recmeet_device_t)wrap_device(raw, TRUE) : NULL;
}

recmeet_device_t recmeet_default_render_device(void) {
    IMMDeviceEnumerator *e = make_enumerator();
    if (!e) return NULL;
    IMMDevice *raw = NULL;
    HRESULT hr = IMMDeviceEnumerator_GetDefaultAudioEndpoint(e, eRender, eConsole, &raw);
    IMMDeviceEnumerator_Release(e);
    return SUCCEEDED(hr) ? (recmeet_device_t)wrap_device(raw, FALSE) : NULL;
}

recmeet_device_t recmeet_device_by_id(LPCWSTR id) {
    if (!id) return NULL;
    IMMDeviceEnumerator *e = make_enumerator();
    if (!e) return NULL;
    IMMDevice *raw = NULL;
    HRESULT hr = IMMDeviceEnumerator_GetDevice(e, id, &raw);
    IMMDeviceEnumerator_Release(e);
    return SUCCEEDED(hr) ? (recmeet_device_t)wrap_device(raw, FALSE) : NULL;
}

LPWSTR recmeet_device_id(recmeet_device_t h) {
    dev_impl *d = as_dev(h);
    if (!d || !d->raw) return NULL;
    LPWSTR id = NULL;
    IMMDevice_GetId(d->raw, &id);
    return id;
}

LPWSTR recmeet_device_name(recmeet_device_t h) {
    dev_impl *d = as_dev(h);
    if (!d || !d->raw) return NULL;
    IPropertyStore *store = NULL;
    if (FAILED(IMMDevice_OpenPropertyStore(d->raw, STGM_READ, &store)) || !store) {
        return NULL;
    }
    PROPVARIANT prop;
    memset(&prop, 0, sizeof(prop));

    LPWSTR result = NULL;
    if (SUCCEEDED(IPropertyStore_GetValue(store, &kPKEY_Device_FriendlyName, &prop))
        && prop.vt == VT_LPWSTR
        && prop.pwszVal) {
        size_t bytes = (wcslen(prop.pwszVal) + 1) * sizeof(WCHAR);
        result = (LPWSTR)CoTaskMemAlloc(bytes);
        if (result) memcpy(result, prop.pwszVal, bytes);
    }
    // Equivalent to PropVariantClear for the only variant we read.
    if (prop.vt == VT_LPWSTR && prop.pwszVal) {
        CoTaskMemFree(prop.pwszVal);
    }
    memset(&prop, 0, sizeof(prop));
    IPropertyStore_Release(store);
    return result;
}

UINT32 recmeet_device_channel_count(recmeet_device_t h) {
    dev_impl *d = as_dev(h);
    if (!d || !d->raw) return 0;
    IAudioClient *client = NULL;
    if (FAILED(IMMDevice_Activate(d->raw, &IID_IAudioClient, CLSCTX_ALL, NULL, (void **)&client)) || !client) {
        return 0;
    }
    WAVEFORMATEX *fmt = NULL;
    UINT32 ch = 0;
    if (SUCCEEDED(IAudioClient_GetMixFormat(client, &fmt)) && fmt) {
        ch = fmt->nChannels;
        CoTaskMemFree(fmt);
    }
    IAudioClient_Release(client);
    return ch;
}

int recmeet_device_is_default_capture(recmeet_device_t h) {
    dev_impl *d = as_dev(h);
    return (d && d->is_default_capture) ? 1 : 0;
}

void recmeet_device_release(recmeet_device_t h) {
    dev_impl *d = as_dev(h);
    if (!d) return;
    if (d->raw) IMMDevice_Release(d->raw);
    free(d);
}

// MARK: - Capture session

recmeet_capture_t recmeet_capture_create(recmeet_device_t h, int loopback, HRESULT *out_hr) {
    dev_impl *d = as_dev(h);
    if (!d || !d->raw) {
        if (out_hr) *out_hr = E_INVALIDARG;
        return NULL;
    }

    IAudioClient *client = NULL;
    HRESULT hr = IMMDevice_Activate(d->raw, &IID_IAudioClient, CLSCTX_ALL, NULL, (void **)&client);
    if (FAILED(hr)) { if (out_hr) *out_hr = hr; return NULL; }

    WAVEFORMATEX *mix_fmt = NULL;
    hr = IAudioClient_GetMixFormat(client, &mix_fmt);
    if (FAILED(hr) || !mix_fmt) {
        IAudioClient_Release(client);
        if (out_hr) *out_hr = FAILED(hr) ? hr : E_FAIL;
        return NULL;
    }
    UINT32 sample_rate = mix_fmt->nSamplesPerSec;
    UINT16 channels    = mix_fmt->nChannels;
    CoTaskMemFree(mix_fmt);

    WAVEFORMATEX fmt;
    memset(&fmt, 0, sizeof(fmt));
    fmt.wFormatTag      = WAVE_FORMAT_PCM;
    fmt.nChannels       = channels;
    fmt.nSamplesPerSec  = sample_rate;
    fmt.wBitsPerSample  = 16;
    fmt.nBlockAlign     = channels * 2;
    fmt.nAvgBytesPerSec = sample_rate * fmt.nBlockAlign;
    fmt.cbSize          = 0;

    DWORD flags = loopback ? AUDCLNT_STREAMFLAGS_LOOPBACK : 0;
    REFERENCE_TIME buf_dur = 10000000; // 1 second

    hr = IAudioClient_Initialize(client, AUDCLNT_SHAREMODE_SHARED, flags, buf_dur, 0, &fmt, NULL);
    if (FAILED(hr)) {
        IAudioClient_Release(client);
        if (out_hr) *out_hr = hr;
        return NULL;
    }

    IAudioCaptureClient *capture = NULL;
    hr = IAudioClient_GetService(client, &IID_IAudioCaptureClient, (void **)&capture);
    if (FAILED(hr) || !capture) {
        IAudioClient_Release(client);
        if (out_hr) *out_hr = FAILED(hr) ? hr : E_FAIL;
        return NULL;
    }

    cap_impl *cap = (cap_impl *)calloc(1, sizeof(cap_impl));
    if (!cap) {
        IAudioCaptureClient_Release(capture);
        IAudioClient_Release(client);
        if (out_hr) *out_hr = E_OUTOFMEMORY;
        return NULL;
    }
    cap->device = d->raw;
    IMMDevice_AddRef(d->raw);
    cap->client = client;
    cap->capture = capture;
    cap->format.sample_rate = sample_rate;
    cap->format.channels = channels;
    if (out_hr) *out_hr = S_OK;
    return (recmeet_capture_t)cap;
}

HRESULT recmeet_capture_start(recmeet_capture_t h) {
    cap_impl *c = as_cap(h);
    if (!c || !c->client) return E_INVALIDARG;
    return IAudioClient_Start(c->client);
}

HRESULT recmeet_capture_stop(recmeet_capture_t h) {
    cap_impl *c = as_cap(h);
    if (!c || !c->client) return E_INVALIDARG;
    return IAudioClient_Stop(c->client);
}

recmeet_format_t recmeet_capture_format(recmeet_capture_t h) {
    cap_impl *c = as_cap(h);
    if (!c) {
        recmeet_format_t empty = { 0, 0 };
        return empty;
    }
    return c->format;
}

int recmeet_capture_get_packet(recmeet_capture_t h, void **out_data, UINT32 *out_frames, UINT32 *out_flags) {
    cap_impl *c = as_cap(h);
    if (!c || !c->capture || !out_data || !out_frames || !out_flags) return -1;
    UINT32 packet_size = 0;
    HRESULT hr = IAudioCaptureClient_GetNextPacketSize(c->capture, &packet_size);
    if (FAILED(hr)) return -1;
    if (packet_size == 0) return 0;

    BYTE *data = NULL;
    UINT32 frames = 0;
    DWORD flags = 0;
    hr = IAudioCaptureClient_GetBuffer(c->capture, &data, &frames, &flags, NULL, NULL);
    if (FAILED(hr)) return -1;

    *out_data = data;
    *out_frames = frames;
    *out_flags = flags;
    return 1;
}

void recmeet_capture_release_packet(recmeet_capture_t h, UINT32 frames) {
    cap_impl *c = as_cap(h);
    if (!c || !c->capture) return;
    IAudioCaptureClient_ReleaseBuffer(c->capture, frames);
}

void recmeet_capture_release(recmeet_capture_t h) {
    cap_impl *c = as_cap(h);
    if (!c) return;
    if (c->capture) IAudioCaptureClient_Release(c->capture);
    if (c->client)  IAudioClient_Release(c->client);
    if (c->device)  IMMDevice_Release(c->device);
    free(c);
}

#endif // _WIN32
