// transmissionhm — C→ArkTS callbacks via ThreadSafeFunction
// Adapted from transmissionbtc native_to_java.cc (JNI → N-API TSFN)
//
// Key changes:
//   JavaVM + JNIEnv + CallStaticVoidMethod → napi_threadsafe_function
//   JvmAttach/JvmDetach macros → TSFN call pattern
//   tr_android_file_* hooks → POSIX sandbox (no StorageAccess needed for v1.0)
//
// M0: TSFN infrastructure only. Actual callback wiring happens in M1
//     when transmission.cc's sessionStart creates the TSFN handles.

#include <napi/native_api.h>
#include <hilog/log.h>
#include <cstdlib>
#include <cstring>
#include <fcntl.h>
#include <unistd.h>
#include <sys/stat.h>
#include <mutex>
#include <libtransmission/transmission.h>
#include <libtransmission/file.h>
#include "commons.h"

#undef LOG_DOMAIN
#undef LOG_TAG
#define LOG_DOMAIN 0x0001
#define LOG_TAG "transmissionhm-cb"

// ── TSFN handles + release tracking ─────────────────────────────────
static napi_threadsafe_function tsfnTorrentChanged = nullptr;
static napi_threadsafe_function tsfnTorrentStopped = nullptr;
static napi_threadsafe_function tsfnSessionChanged = nullptr;
static napi_threadsafe_function tsfnAltSpeedChanged = nullptr;
static bool tsfnReleased = false;
// P0 fix (codex review): the handles and tsfnReleased were read on the
// libtransmission threads (call*Callback) while NativeToArktsRelease/Init
// wrote them on the JS thread — a data race and a use-after-free window
// when a callback fired between release and pointer-null. Guard all
// access with this mutex.
static std::mutex tsfnMutex;

// ── Call data for TSFN payload ─────────────────────────────────────
struct TsfnCallData {
  int32_t torrent_id;
  bool has_torrent_id;
};

// ── TSFN call wrappers (called from libtransmission thread) ─────────
extern "C" {

// P0 fix (codex review): napi_call_threadsafe_function status was unchecked —
// a failed nonblocking call leaked the heap-allocated TsfnCallData. Free it.
static void freeOnEnqueueFailure(napi_status status, void *data) {
  if (status != napi_ok && data != nullptr) {
    delete static_cast<TsfnCallData *>(data);
  }
}

void callTorrentChangedCallback(tr_torrent_id_t torrent_id) {
  std::lock_guard<std::mutex> lock(tsfnMutex);
  if (tsfnTorrentChanged != nullptr && !tsfnReleased) {
    auto *data = new TsfnCallData{static_cast<int32_t>(torrent_id), true};
    napi_status status = napi_call_threadsafe_function(tsfnTorrentChanged, data, napi_tsfn_nonblocking);
    freeOnEnqueueFailure(status, data);
  }
}

void callTorrentStoppedCallback(tr_torrent_id_t torrent_id) {
  std::lock_guard<std::mutex> lock(tsfnMutex);
  if (tsfnTorrentStopped != nullptr && !tsfnReleased) {
    auto *data = new TsfnCallData{static_cast<int32_t>(torrent_id), true};
    napi_status status = napi_call_threadsafe_function(tsfnTorrentStopped, data, napi_tsfn_nonblocking);
    freeOnEnqueueFailure(status, data);
  }
}

void callSessionChangedCallback() {
  std::lock_guard<std::mutex> lock(tsfnMutex);
  if (tsfnSessionChanged != nullptr && !tsfnReleased) {
    napi_call_threadsafe_function(tsfnSessionChanged, nullptr, napi_tsfn_nonblocking);
  }
}

void callAltSpeedChangedCallback() {
  std::lock_guard<std::mutex> lock(tsfnMutex);
  if (tsfnAltSpeedChanged != nullptr && !tsfnReleased) {
    napi_call_threadsafe_function(tsfnAltSpeedChanged, nullptr, napi_tsfn_nonblocking);
  }
}

} // extern "C"

// ── TSFN JS callback (invoked on ArkTS main thread) ───────────────────
static void CallJsCallback(napi_env env, napi_value js_callback,
                           void * /*context*/, void *data) {
  napi_value undefined;
  napi_get_undefined(env, &undefined);

  if (data != nullptr) {
    // Pass torrent_id as the callback argument
    auto *cd = static_cast<TsfnCallData *>(data);
    napi_value arg;
    napi_create_int32(env, cd->torrent_id, &arg);
    napi_value result;
    napi_call_function(env, undefined, js_callback, 1, &arg, &result);
    delete cd;
  } else {
    napi_value result;
    napi_call_function(env, undefined, js_callback, 0, nullptr, &result);
  }
}

// ── N-API: Initialize TSFN handles ──────────────────────────────────
static napi_value NativeToArktsInit(napi_env env, napi_callback_info info) {
  size_t argc = 4;
  napi_value args[4];
  napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

  std::lock_guard<std::mutex> lock(tsfnMutex);
  // P0 fix (codex review): tsfnReleased was never reset here, so after a
  // nativeToArktsRelease + re-init every call*Callback silently no-op'd —
  // callbacks stayed permanently dead after a session restart.
  tsfnReleased = false;

  // Release any existing handles first
  if (tsfnTorrentChanged != nullptr) {
    napi_release_threadsafe_function(tsfnTorrentChanged, napi_tsfn_release);
    tsfnTorrentChanged = nullptr;
  }
  if (tsfnTorrentStopped != nullptr) {
    napi_release_threadsafe_function(tsfnTorrentStopped, napi_tsfn_release);
    tsfnTorrentStopped = nullptr;
  }
  if (tsfnSessionChanged != nullptr) {
    napi_release_threadsafe_function(tsfnSessionChanged, napi_tsfn_release);
    tsfnSessionChanged = nullptr;
  }
  if (tsfnAltSpeedChanged != nullptr) {
    napi_release_threadsafe_function(tsfnAltSpeedChanged, napi_tsfn_release);
    tsfnAltSpeedChanged = nullptr;
  }

  // Create TSFN handles from optional callback arguments
  const char *names[4] = {
    "tsfnTorrentChanged", "tsfnTorrentStopped",
    "tsfnSessionChanged", "tsfnAltSpeedChanged"
  };
  napi_threadsafe_function *handles[4] = {
    &tsfnTorrentChanged, &tsfnTorrentStopped,
    &tsfnSessionChanged, &tsfnAltSpeedChanged
  };

  for (int i = 0; i < 4; i++) {
    if (argc > (size_t)i && !isNapiNull(env, args[i])) {
      napi_value resource_name;
      napi_create_string_utf8(env, names[i], NAPI_AUTO_LENGTH, &resource_name);
      napi_status status = napi_create_threadsafe_function(
        env, args[i], nullptr, resource_name,
        0,   // unlimited queue
        1,   // max 1 thread calling
        nullptr, nullptr, nullptr,
        CallJsCallback, handles[i]
      );
      if (status == napi_ok && *handles[i] != nullptr) {
        OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG,
                     "TSFN handle created for %{public}s", names[i]);
      } else {
        OH_LOG_Print(LOG_APP, LOG_WARN, LOG_DOMAIN, LOG_TAG,
                     "Failed to create TSFN handle for %{public}s (status=%d)", names[i], status);
      }
    }
  }

  napi_value result;
  napi_get_undefined(env, &result);
  return result;
}

// ── N-API: Release TSFN handles ─────────────────────────────────────
static napi_value NativeToArktsRelease(napi_env env, napi_callback_info info) {
  (void)info;
  std::lock_guard<std::mutex> lock(tsfnMutex);
  tsfnReleased = true;
  if (tsfnTorrentChanged != nullptr) {
    napi_release_threadsafe_function(tsfnTorrentChanged, napi_tsfn_release);
    tsfnTorrentChanged = nullptr;
  }
  if (tsfnTorrentStopped != nullptr) {
    napi_release_threadsafe_function(tsfnTorrentStopped, napi_tsfn_release);
    tsfnTorrentStopped = nullptr;
  }
  if (tsfnSessionChanged != nullptr) {
    napi_release_threadsafe_function(tsfnSessionChanged, napi_tsfn_release);
    tsfnSessionChanged = nullptr;
  }
  if (tsfnAltSpeedChanged != nullptr) {
    napi_release_threadsafe_function(tsfnAltSpeedChanged, napi_tsfn_release);
    tsfnAltSpeedChanged = nullptr;
  }

  napi_value result;
  napi_get_undefined(env, &result);
  return result;
}

// ── POSIX file hooks (replaces tr_android_file_* StorageAccess) ─────
// v1.0: OH supports POSIX I/O on the app sandbox filesystem.
// These are registered with libtransmission via tr_sessionSet*.

extern "C" {

tr_sys_file_t tr_android_file_open(char const *path, int flags) {
  int posixFlags = O_RDONLY;
  if (flags & TR_SYS_FILE_WRITE) posixFlags = O_RDWR;
  if (flags & TR_SYS_FILE_CREATE) posixFlags |= O_CREAT;
  // 4.0.6: TR_SYS_FILE_CREATE_NEW removed — O_EXCL applied with TR_SYS_FILE_CREATE
  if (flags & TR_SYS_FILE_TRUNCATE) posixFlags |= O_TRUNC;

  int fd = open(path, posixFlags, 0666);
  return (fd == -1) ? TR_BAD_SYS_FILE : fd;
}

bool tr_android_file_close(tr_sys_file_t handle) {
  return close(handle) == 0;
}

bool tr_android_path_rename(char const *src_path, char const *dst_path) {
  return rename(src_path, dst_path) == 0;
}

bool tr_android_path_remove(char const *path) {
  return remove(path) == 0;
}

bool tr_android_dir_create(char const *path) {
  return mkdir(path, 0755) == 0;
}

} // extern "C"

// ── Module registration ─────────────────────────────────────────────
extern "C" void RegisterNativeToArkts(napi_env env, napi_value exports) {
  napi_property_descriptor desc[] = {
    {"nativeToArktsInit",    nullptr, NativeToArktsInit,    nullptr, nullptr, nullptr, napi_default, nullptr},
    {"nativeToArktsRelease", nullptr, NativeToArktsRelease, nullptr, nullptr, nullptr, napi_default, nullptr}
  };
  napi_define_properties(env, exports, sizeof(desc) / sizeof(desc[0]), desc);
}
