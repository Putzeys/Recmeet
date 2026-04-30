// Public C surface of the recmeet Windows audio engine.
//
// We deliberately do NOT include any of the COM audio headers
// (mmdeviceapi.h, propsys.h, audioclient.h) here — they don't play well
// with Swift's clang-module importer. Instead, this header exposes only
// opaque pointer types and plain functions; everything COM-related lives
// inside CWASAPI.c (compiled as ordinary C, where include order works).
#pragma once

#ifdef _WIN32
#include <windows.h>

// Opaque handles — Swift sees these as OpaquePointer.
typedef void *recmeet_device_t;
typedef void *recmeet_capture_t;

typedef struct {
    UINT32 sample_rate;   // Hz
    UINT16 channels;      // 1 = mono, 2 = stereo, ...
} recmeet_format_t;

// COM lifecycle. Idempotent — safe to call init multiple times.
HRESULT recmeet_init(void);
void    recmeet_shutdown(void);

// Device enumeration. Caller releases each returned handle with
// recmeet_device_release. Returns the number of devices written into
// out_devices (capped at max_count).
int recmeet_enumerate_capture_devices(recmeet_device_t *out_devices, int max_count);

recmeet_device_t recmeet_default_capture_device(void);
recmeet_device_t recmeet_default_render_device(void);
recmeet_device_t recmeet_device_by_id(LPCWSTR id);

// Returns a wide string allocated with CoTaskMemAlloc. Caller frees with
// CoTaskMemFree. Returns NULL on failure.
LPWSTR recmeet_device_id(recmeet_device_t dev);
LPWSTR recmeet_device_name(recmeet_device_t dev);

UINT32 recmeet_device_channel_count(recmeet_device_t dev);
int    recmeet_device_is_default_capture(recmeet_device_t dev);
void   recmeet_device_release(recmeet_device_t dev);

// Capture session. `loopback != 0` selects WASAPI loopback (system audio
// from the default render device). The returned handle owns its own copy
// of the underlying IMMDevice; the caller may release the source device
// immediately after creation.
recmeet_capture_t recmeet_capture_create(recmeet_device_t dev, int loopback, HRESULT *out_hr);
HRESULT           recmeet_capture_start(recmeet_capture_t cap);
HRESULT           recmeet_capture_stop(recmeet_capture_t cap);
recmeet_format_t  recmeet_capture_format(recmeet_capture_t cap);

// Pull a packet from the capture client.
//   returns  1: a packet was captured. *out_data points to internal memory
//              valid until recmeet_capture_release_packet is called. Do NOT
//              free *out_data.
//   returns  0: no packet currently available — caller should sleep briefly
//              and try again.
//   returns <0: capture error; treat as fatal for the session.
int  recmeet_capture_get_packet(recmeet_capture_t cap,
                                void **out_data,
                                UINT32 *out_frames,
                                UINT32 *out_flags);
void recmeet_capture_release_packet(recmeet_capture_t cap, UINT32 frames);
void recmeet_capture_release(recmeet_capture_t cap);

// Bit flags returned in `out_flags`.
extern const UINT32 recmeet_AUDCLNT_BUFFERFLAGS_SILENT;
// Convenience.
extern const HRESULT recmeet_E_FAIL;

#endif // _WIN32
