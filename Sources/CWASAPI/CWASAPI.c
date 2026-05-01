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
#include <mfapi.h>
#include <mfidl.h>
#include <mfreadwrite.h>
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
const IID IID_IAudioRenderClient = {
    0xF294ACFC, 0x3146, 0x4483,
    { 0xA7, 0xBF, 0xAD, 0xDC, 0xA7, 0xC2, 0x60, 0xE2 }
};

// Media Foundation GUIDs we use for AAC transcode.
// Defined manually to avoid linking mfuuid.lib.
const GUID MFMediaType_Audio_Local = {
    0x73647561, 0x0000, 0x0010,
    { 0x80, 0x00, 0x00, 0xAA, 0x00, 0x38, 0x9B, 0x71 }
};
const GUID MFAudioFormat_PCM_Local = {
    0x00000001, 0x0000, 0x0010,
    { 0x80, 0x00, 0x00, 0xAA, 0x00, 0x38, 0x9B, 0x71 }
};
const GUID MFAudioFormat_AAC_Local = {
    0x00001610, 0x0000, 0x0010,
    { 0x80, 0x00, 0x00, 0xAA, 0x00, 0x38, 0x9B, 0x71 }
};
const GUID MF_MT_MAJOR_TYPE_Local = {
    0x48eba18e, 0xf8c9, 0x4687,
    { 0xbf, 0x11, 0x0a, 0x74, 0xc9, 0xf9, 0x6a, 0x8f }
};
const GUID MF_MT_SUBTYPE_Local = {
    0xf7e34c9a, 0x42e8, 0x4714,
    { 0xb7, 0x4b, 0xcb, 0x29, 0xd7, 0x2c, 0x35, 0xe5 }
};
const GUID MF_MT_AUDIO_NUM_CHANNELS_Local = {
    0x37e48bf5, 0x645e, 0x4c5b,
    { 0x89, 0xde, 0xad, 0xa9, 0xe2, 0x9b, 0x69, 0x6a }
};
const GUID MF_MT_AUDIO_SAMPLES_PER_SECOND_Local = {
    0x5faeeae7, 0x0290, 0x4c31,
    { 0x9e, 0x8a, 0xc5, 0x34, 0xf6, 0x8d, 0x9d, 0xba }
};
const GUID MF_MT_AUDIO_AVG_BYTES_PER_SECOND_Local = {
    0x1aab75c8, 0xcfef, 0x451c,
    { 0xab, 0x95, 0xac, 0x03, 0x4b, 0x8e, 0x17, 0x31 }
};
const GUID MF_MT_AUDIO_BLOCK_ALIGNMENT_Local = {
    0x322de230, 0x9eeb, 0x43bd,
    { 0xab, 0x7a, 0xff, 0x41, 0x22, 0x51, 0x54, 0x1d }
};
const GUID MF_MT_AUDIO_BITS_PER_SAMPLE_Local = {
    0xf2deb57f, 0x40fa, 0x4764,
    { 0xaa, 0x33, 0xed, 0x4f, 0x2d, 0x1f, 0xf6, 0x69 }
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

    // Force a fixed pipeline format: 48 kHz / 16-bit PCM. Mono for the mic
    // (better for speech / transcription, smaller files); stereo for the
    // render endpoint loopback (so we preserve the system mix). Windows
    // remixes & resamples on its side because we set AUTOCONVERTPCM +
    // SRC_DEFAULT_QUALITY — without that flag pair the mic landed at
    // whatever the device reported (often 16 kHz or 44.1 kHz), which made
    // the muxed output sound chipmunked.
    UINT16 channels    = loopback ? 2 : 1;
    UINT32 sample_rate = 48000;

    WAVEFORMATEX fmt;
    memset(&fmt, 0, sizeof(fmt));
    fmt.wFormatTag      = WAVE_FORMAT_PCM;
    fmt.nChannels       = channels;
    fmt.nSamplesPerSec  = sample_rate;
    fmt.wBitsPerSample  = 16;
    fmt.nBlockAlign     = channels * 2;
    fmt.nAvgBytesPerSec = sample_rate * fmt.nBlockAlign;
    fmt.cbSize          = 0;

    DWORD flags = (loopback ? AUDCLNT_STREAMFLAGS_LOOPBACK : 0)
                | AUDCLNT_STREAMFLAGS_AUTOCONVERTPCM
                | AUDCLNT_STREAMFLAGS_SRC_DEFAULT_QUALITY;
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

// MARK: - Render keepalive

typedef struct {
    IAudioClient        *client;
    IAudioRenderClient  *render;
    UINT32               buffer_frames;
    HANDLE               thread;
    HANDLE               stop_event;
} keepalive_impl;

static DWORD WINAPI keepalive_thread_proc(LPVOID lp) {
    keepalive_impl *k = (keepalive_impl *)lp;
    // Wake roughly every 10ms to top the buffer up with silence.
    while (WaitForSingleObject(k->stop_event, 10) == WAIT_TIMEOUT) {
        UINT32 padding = 0;
        if (FAILED(IAudioClient_GetCurrentPadding(k->client, &padding))) continue;
        UINT32 free_frames = k->buffer_frames - padding;
        if (free_frames == 0) continue;
        BYTE *buf = NULL;
        if (FAILED(IAudioRenderClient_GetBuffer(k->render, free_frames, &buf))) continue;
        // Releasing with AUDCLNT_BUFFERFLAGS_SILENT tells the engine to
        // ignore buf contents — no need to actually zero it.
        IAudioRenderClient_ReleaseBuffer(
            k->render, free_frames, AUDCLNT_BUFFERFLAGS_SILENT
        );
    }
    return 0;
}

recmeet_keepalive_t recmeet_keepalive_start(recmeet_device_t h) {
    dev_impl *d = as_dev(h);
    if (!d || !d->raw) return NULL;

    IAudioClient *client = NULL;
    HRESULT hr = IMMDevice_Activate(d->raw, &IID_IAudioClient, CLSCTX_ALL, NULL, (void **)&client);
    if (FAILED(hr)) return NULL;

    WAVEFORMATEX *fmt = NULL;
    if (FAILED(IAudioClient_GetMixFormat(client, &fmt)) || !fmt) {
        IAudioClient_Release(client);
        return NULL;
    }

    REFERENCE_TIME buf_dur = 10000000; // 1s
    hr = IAudioClient_Initialize(client, AUDCLNT_SHAREMODE_SHARED, 0, buf_dur, 0, fmt, NULL);
    CoTaskMemFree(fmt);
    if (FAILED(hr)) {
        IAudioClient_Release(client);
        return NULL;
    }

    UINT32 buffer_frames = 0;
    if (FAILED(IAudioClient_GetBufferSize(client, &buffer_frames)) || buffer_frames == 0) {
        IAudioClient_Release(client);
        return NULL;
    }

    IAudioRenderClient *render = NULL;
    if (FAILED(IAudioClient_GetService(client, &IID_IAudioRenderClient, (void **)&render)) || !render) {
        IAudioClient_Release(client);
        return NULL;
    }

    // Pre-fill the entire buffer with silence so the stream starts
    // immediately instead of underflowing.
    BYTE *buf = NULL;
    if (SUCCEEDED(IAudioRenderClient_GetBuffer(render, buffer_frames, &buf))) {
        IAudioRenderClient_ReleaseBuffer(render, buffer_frames, AUDCLNT_BUFFERFLAGS_SILENT);
    }

    if (FAILED(IAudioClient_Start(client))) {
        IAudioRenderClient_Release(render);
        IAudioClient_Release(client);
        return NULL;
    }

    keepalive_impl *k = (keepalive_impl *)calloc(1, sizeof(keepalive_impl));
    if (!k) {
        IAudioClient_Stop(client);
        IAudioRenderClient_Release(render);
        IAudioClient_Release(client);
        return NULL;
    }
    k->client = client;
    k->render = render;
    k->buffer_frames = buffer_frames;
    k->stop_event = CreateEventW(NULL, TRUE, FALSE, NULL);
    DWORD tid = 0;
    k->thread = CreateThread(NULL, 0, keepalive_thread_proc, k, 0, &tid);
    if (!k->thread) {
        SetEvent(k->stop_event);
        IAudioClient_Stop(client);
        IAudioRenderClient_Release(render);
        IAudioClient_Release(client);
        if (k->stop_event) CloseHandle(k->stop_event);
        free(k);
        return NULL;
    }
    return (recmeet_keepalive_t)k;
}

// MARK: - AAC encode via Media Foundation

HRESULT recmeet_encode_aac_from_wav(LPCWSTR input_wav_path, LPCWSTR output_m4a_path, UINT32 bitrate_bps) {
    HRESULT hr = MFStartup(MF_VERSION, MFSTARTUP_FULL);
    if (FAILED(hr)) return hr;

    IMFSourceReader *reader = NULL;
    IMFSinkWriter   *writer = NULL;
    IMFMediaType    *pcm_type = NULL;
    IMFMediaType    *aac_in_type = NULL;
    IMFMediaType    *aac_out_type = NULL;

    DWORD writer_stream = 0;
    UINT32 channels = 2;
    UINT32 sample_rate = 48000;

    hr = MFCreateSourceReaderFromURL(input_wav_path, NULL, &reader);
    if (FAILED(hr)) goto done;

    // Force the reader to deliver 16-bit PCM frames.
    hr = MFCreateMediaType(&pcm_type);
    if (FAILED(hr)) goto done;
    IMFMediaType_SetGUID(pcm_type, &MF_MT_MAJOR_TYPE_Local, &MFMediaType_Audio_Local);
    IMFMediaType_SetGUID(pcm_type, &MF_MT_SUBTYPE_Local,    &MFAudioFormat_PCM_Local);
    hr = IMFSourceReader_SetCurrentMediaType(reader, MF_SOURCE_READER_FIRST_AUDIO_STREAM, NULL, pcm_type);
    if (FAILED(hr)) goto done;

    // Read what the reader actually negotiated to discover ch / sample rate.
    IMFMediaType *negotiated = NULL;
    hr = IMFSourceReader_GetCurrentMediaType(reader, MF_SOURCE_READER_FIRST_AUDIO_STREAM, &negotiated);
    if (SUCCEEDED(hr) && negotiated) {
        IMFMediaType_GetUINT32(negotiated, &MF_MT_AUDIO_NUM_CHANNELS_Local, &channels);
        IMFMediaType_GetUINT32(negotiated, &MF_MT_AUDIO_SAMPLES_PER_SECOND_Local, &sample_rate);
        IMFMediaType_Release(negotiated);
    }

    hr = MFCreateSinkWriterFromURL(output_m4a_path, NULL, NULL, &writer);
    if (FAILED(hr)) goto done;

    // Output: AAC, same channel count and sample rate as source.
    hr = MFCreateMediaType(&aac_out_type);
    if (FAILED(hr)) goto done;
    IMFMediaType_SetGUID(aac_out_type, &MF_MT_MAJOR_TYPE_Local, &MFMediaType_Audio_Local);
    IMFMediaType_SetGUID(aac_out_type, &MF_MT_SUBTYPE_Local,    &MFAudioFormat_AAC_Local);
    IMFMediaType_SetUINT32(aac_out_type, &MF_MT_AUDIO_NUM_CHANNELS_Local,        channels);
    IMFMediaType_SetUINT32(aac_out_type, &MF_MT_AUDIO_SAMPLES_PER_SECOND_Local,  sample_rate);
    IMFMediaType_SetUINT32(aac_out_type, &MF_MT_AUDIO_AVG_BYTES_PER_SECOND_Local, bitrate_bps / 8);
    IMFMediaType_SetUINT32(aac_out_type, &MF_MT_AUDIO_BITS_PER_SAMPLE_Local,     16);
    hr = IMFSinkWriter_AddStream(writer, aac_out_type, &writer_stream);
    if (FAILED(hr)) goto done;

    // Input to the sink writer: matches what the reader produces (PCM).
    hr = MFCreateMediaType(&aac_in_type);
    if (FAILED(hr)) goto done;
    IMFMediaType_SetGUID(aac_in_type, &MF_MT_MAJOR_TYPE_Local, &MFMediaType_Audio_Local);
    IMFMediaType_SetGUID(aac_in_type, &MF_MT_SUBTYPE_Local,    &MFAudioFormat_PCM_Local);
    IMFMediaType_SetUINT32(aac_in_type, &MF_MT_AUDIO_NUM_CHANNELS_Local,        channels);
    IMFMediaType_SetUINT32(aac_in_type, &MF_MT_AUDIO_SAMPLES_PER_SECOND_Local,  sample_rate);
    IMFMediaType_SetUINT32(aac_in_type, &MF_MT_AUDIO_BITS_PER_SAMPLE_Local,     16);
    IMFMediaType_SetUINT32(aac_in_type, &MF_MT_AUDIO_BLOCK_ALIGNMENT_Local,     channels * 2);
    IMFMediaType_SetUINT32(aac_in_type, &MF_MT_AUDIO_AVG_BYTES_PER_SECOND_Local, sample_rate * channels * 2);
    hr = IMFSinkWriter_SetInputMediaType(writer, writer_stream, aac_in_type, NULL);
    if (FAILED(hr)) goto done;

    hr = IMFSinkWriter_BeginWriting(writer);
    if (FAILED(hr)) goto done;

    // Pump samples from reader to writer.
    for (;;) {
        DWORD stream_index = 0, flags = 0;
        LONGLONG ts = 0;
        IMFSample *sample = NULL;
        hr = IMFSourceReader_ReadSample(
            reader,
            MF_SOURCE_READER_FIRST_AUDIO_STREAM,
            0, &stream_index, &flags, &ts, &sample
        );
        if (FAILED(hr)) break;
        if (flags & MF_SOURCE_READERF_ENDOFSTREAM) {
            if (sample) IMFSample_Release(sample);
            break;
        }
        if (sample) {
            IMFSample_SetSampleTime(sample, ts);
            IMFSinkWriter_WriteSample(writer, writer_stream, sample);
            IMFSample_Release(sample);
        }
    }

    if (writer) IMFSinkWriter_Finalize(writer);

done:
    if (aac_in_type)  IMFMediaType_Release(aac_in_type);
    if (aac_out_type) IMFMediaType_Release(aac_out_type);
    if (pcm_type)     IMFMediaType_Release(pcm_type);
    if (writer)       IMFSinkWriter_Release(writer);
    if (reader)       IMFSourceReader_Release(reader);
    MFShutdown();
    return hr;
}

void recmeet_keepalive_stop(recmeet_keepalive_t h) {
    if (!h) return;
    keepalive_impl *k = (keepalive_impl *)h;
    if (k->stop_event) SetEvent(k->stop_event);
    if (k->thread) {
        WaitForSingleObject(k->thread, 1000);
        CloseHandle(k->thread);
    }
    if (k->stop_event) CloseHandle(k->stop_event);
    if (k->client)  IAudioClient_Stop(k->client);
    if (k->render)  IAudioRenderClient_Release(k->render);
    if (k->client)  IAudioClient_Release(k->client);
    free(k);
}

#endif // _WIN32
