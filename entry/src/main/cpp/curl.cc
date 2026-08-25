// transmissionbtm — libcurl HTTP download (N-API)
// Adapted from transmissionbtc curl.cc (JNI → N-API)

#include <napi/native_api.h>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <cerrno>
#include <mutex>
#include <curl/curl.h>
#include <libtransmission/version.h>
#include "commons.h"

// throwEX helper for curl (uses inline return, not CATCH goto — curl.cc has no CATCH label)
#define throwCurlEX(env, code, ...) do { \
  char _msg[256]; \
  snprintf(_msg, sizeof(_msg), __VA_ARGS__); \
  napi_throw_error(env, code, _msg); \
  return nullptr; \
} while(0)

// C7 (codex): one-time libcurl global init, idempotent + thread-safe. curl_global_init
// is refcounted, so calling from both the ArkTS download path and the detached
// probe thread is safe.
static std::once_flag g_curlInitFlag;
void ensureCurlGlobalInit() {
  std::call_once(g_curlInitFlag, [] {
    curl_global_init(CURL_GLOBAL_DEFAULT);
  });
}

static napi_value CurlDownload(napi_env env, napi_callback_info info) {
  size_t argc = 3;
  napi_value args[3];
  napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

  // Validate args
  if (argc < 2) {
    napi_throw_error(env, nullptr, "Expected arguments: url, dstPath [, timeout]");
    return nullptr;
  }
  ensureCurlGlobalInit();

  char *url = getStringUtf8(env, args[0]);
  char *dst = getStringUtf8(env, args[1]);

  if (url == nullptr || dst == nullptr) {
    free(url);
    free(dst);
    napi_throw_error(env, nullptr, "Arguments must be non-null strings");
    return nullptr;
  }

  // D2 (docs/11): restrict to http/https. Without this a user-supplied URL
  // can be "file:///..." and CURLOPT_WRITEDATA would write an arbitrary local
  // file — an arbitrary-file-write primitive driven by user input. Checked
  // before fopen so a rejected URL never creates a garbage destination file.
  if (strncmp(url, "http://", 7) != 0 && strncmp(url, "https://", 8) != 0) {
    free(url);
    free(dst);
    napi_throw_error(env, nullptr, "Only http:// and https:// URLs are supported");
    return nullptr;
  }

  int32_t timeout = 30; // default 30s
  if (argc >= 3 && napi_get_value_int32(env, args[2], &timeout) != napi_ok) {
    timeout = 30;  // C4 (codex): a bad-type timeout never silently corrupts the value
  }

  // C8 (codex P2): validate the destination path before fopen. The app's own
  // sandbox/cache paths are absolute with no traversal; a user-supplied path
  // could otherwise write an arbitrary file (or escape via "..").
  if (dst[0] != '/' || strstr(dst, "..") != nullptr) {
    free(url);
    free(dst);
    napi_throw_error(env, ERR_IO, "Destination path must be absolute, no traversal");
    return nullptr;
  }

  FILE *file = fopen(dst, "wb");
  if (file == nullptr) {
    char _msg[256];
    snprintf(_msg, sizeof(_msg), "Failed to open file %s: %s", dst, strerror(errno));
    free(url);
    free(dst);
    napi_throw_error(env, ERR_IO, _msg);
    return nullptr;
  }

  CURL *curl = curl_easy_init();
  if (curl) {
    char err[CURL_ERROR_SIZE];
    curl_easy_setopt(curl, CURLOPT_URL, url);
    curl_easy_setopt(curl, CURLOPT_ERRORBUFFER, err);
    curl_easy_setopt(curl, CURLOPT_WRITEFUNCTION, nullptr);
    curl_easy_setopt(curl, CURLOPT_WRITEDATA, file);
    curl_easy_setopt(curl, CURLOPT_USERAGENT, "Transmission/" SHORT_VERSION_STRING);
    curl_easy_setopt(curl, CURLOPT_TIMEOUT, (long) timeout);

#ifndef NDEBUG
    curl_easy_setopt(curl, CURLOPT_VERBOSE, 1);
#endif

    CURLcode res = curl_easy_perform(curl);
    curl_easy_cleanup(curl);

    if (res != CURLE_OK) {
      fclose(file);
      free(url);
      free(dst);
      throwCurlEX(env, ERR_IO, "%s", err);
    }
  } else {
    fclose(file);
    free(url);
    free(dst);
    throwCurlEX(env, ERR_IO, "Failed to initialize curl");
  }

  fclose(file);
  free(url);
  free(dst);

  napi_value result;
  napi_get_undefined(env, &result);
  return result;
}

// ── Module registration ─────────────────────────────────────────────
extern "C" void RegisterCurl(napi_env env, napi_value exports) {
  napi_property_descriptor desc[] = {
    {"curlDownload", nullptr, CurlDownload, nullptr, nullptr, nullptr, napi_default, nullptr}
  };
  napi_define_properties(env, exports, sizeof(desc) / sizeof(desc[0]), desc);
}
