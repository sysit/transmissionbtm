// transmissionhm — libcurl HTTP download (N-API)
// Adapted from transmissionbtc curl.cc (JNI → N-API)

#include <napi/native_api.h>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <cerrno>
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

static napi_value CurlDownload(napi_env env, napi_callback_info info) {
  size_t argc = 3;
  napi_value args[3];
  napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

  // Validate args
  if (argc < 2) {
    napi_throw_error(env, nullptr, "Expected arguments: url, dstPath [, timeout]");
    return nullptr;
  }

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
  if (argc >= 3) {
    napi_get_value_int32(env, args[2], &timeout);
  }

  FILE *file = fopen(dst, "wb");
  if (file == nullptr) {
    throwCurlEX(env, ERR_IO, "Failed to open file %s: %s", dst, strerror(errno));
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
