// transmissionbtm — N-API module registration
//
// 32 methods reach ArkTS: getVersion() + getBuildDate() + getEngineVersions()
// registered in Init() below, plus the five submodules declared here (curl,
// nativeToArkts, commons, transmission, torrent) = 29 entries in their
// descriptor arrays.
// RegisterCommons exports nothing today; it is kept so every submodule
// initializes the same way.

#include <napi/native_api.h>
#include <hilog/log.h>
#include <cstdio>

// Engine + dependency versions for the About page. Compiled from the actual
// headers the libraries were built with (and libevent's own runtime string),
// so they cannot drift from the shipped binaries the way hand-edited
// ArkTS constants did (About read 'Transmission 4.1.0' after an engine bump).
#include <libtransmission/version.h>  // MAJOR_VERSION / MINOR_VERSION / PATCH_VERSION
#include <openssl/opensslv.h>         // OPENSSL_VERSION_STR
#include <curl/curlver.h>             // LIBCURL_VERSION
#include <event2/event.h>             // event_get_version()

#undef LOG_DOMAIN
#undef LOG_TAG
#define LOG_DOMAIN 0x0001
#define LOG_TAG "transmissionbtm_napi"

// ── Submodule declarations (extern "C", defined in respective .cc files) ──
extern "C" {
void RegisterCurl(napi_env env, napi_value exports);
void RegisterNativeToArkts(napi_env env, napi_value exports);
void RegisterCommons(napi_env env, napi_value exports);
void RegisterTransmission(napi_env env, napi_value exports);
void RegisterTorrent(napi_env env, napi_value exports);
}

// ── getVersion() — always available ────────────────────────────────
static napi_value GetVersion(napi_env env, napi_callback_info info) {
  (void)info;
  napi_value result;
  // P3 (codex review): check the N-API status — a failed string creation
  // previously returned an undefined handle silently.
  if (napi_create_string_utf8(env, "1.0.4", NAPI_AUTO_LENGTH, &result) != napi_ok) {
    napi_throw_error(env, nullptr, "Failed to create version string");
    return nullptr;
  }
  return result;
}

// ── getBuildDate() — compile date of this native library ───────────
// The About page shows a build date; keeping it as an ArkTS constant meant
// bumping it by hand and it went stale (read '2026-09-29' while 1.0.3
// shipped in November). __DATE__ is set by the compiler, so the shown date
// is always the date this .so was built — same reasoning that keeps the
// version out of ArkTS (constants.ets) and in native code.
static napi_value GetBuildDate(napi_env env, napi_callback_info info) {
  (void)info;
  // __DATE__ is "Mmm dd yyyy" (e.g. "Nov  9 2026") — normalise to ISO 8601.
  static const char kMonths[] = "JanFebMarAprMayJunJulAugSepOctNovDec";
  static const char kDate[] = __DATE__;
  int month = 1;
  for (int p = 0; p < 12 * 3; p += 3) {
    if (kDate[0] == kMonths[p] && kDate[1] == kMonths[p + 1] && kDate[2] == kMonths[p + 2]) {
      month = p / 3 + 1;
      break;
    }
  }
  const int day = (kDate[4] == ' ') ? (kDate[5] - '0')
                                    : ((kDate[4] - '0') * 10 + (kDate[5] - '0'));
  char iso[11];
  snprintf(iso, sizeof(iso), "%.4s-%02d-%02d", kDate + 7, month, day);

  napi_value result;
  if (napi_create_string_utf8(env, iso, NAPI_AUTO_LENGTH, &result) != napi_ok) {
    napi_throw_error(env, nullptr, "Failed to create build date string");
    return nullptr;
  }
  return result;
}

// ── getEngineVersions() — engine + bundled dependency versions ─────
// Read from the headers each library was compiled with (and libevent's own
// runtime string), so the About page's licence rows cannot drift from the
// shipped binaries the way hand-edited ArkTS constants did.
static napi_value GetEngineVersions(napi_env env, napi_callback_info info) {
  (void)info;
  char json[256];
  const int n = snprintf(json, sizeof(json),
                         "{\"transmission\":\"%d.%d.%d\",\"openssl\":\"%s\","
                         "\"curl\":\"%s\",\"libevent\":\"%s\"}",
                         MAJOR_VERSION, MINOR_VERSION, PATCH_VERSION,
                         OPENSSL_VERSION_STR, LIBCURL_VERSION, event_get_version());
  if (n < 0 || static_cast<size_t>(n) >= sizeof(json)) {
    napi_throw_error(env, nullptr, "Engine version string overflow");
    return nullptr;
  }
  napi_value result;
  if (napi_create_string_utf8(env, json, NAPI_AUTO_LENGTH, &result) != napi_ok) {
    napi_throw_error(env, nullptr, "Failed to create engine version string");
    return nullptr;
  }
  return result;
}

// ── Init: register all submodules ──────────────────────────────────
EXTERN_C_START
static napi_value Init(napi_env env, napi_value exports) {
  OH_LOG_INFO(LOG_APP, "transmissionbtm_napi: module initializing");

  // Core (always available)
  napi_property_descriptor coreDesc[] = {
    {"getVersion", nullptr, GetVersion, nullptr, nullptr, nullptr, napi_default, nullptr},
    {"getBuildDate", nullptr, GetBuildDate, nullptr, nullptr, nullptr, napi_default, nullptr},
    {"getEngineVersions", nullptr, GetEngineVersions, nullptr, nullptr, nullptr, napi_default, nullptr}
  };
  if (napi_define_properties(env, exports, sizeof(coreDesc) / sizeof(coreDesc[0]), coreDesc) != napi_ok) {
    OH_LOG_ERROR(LOG_APP, "transmissionbtm_napi: failed to register core functions");
  }

  // Submodules (each Register* adds its functions to exports)
  RegisterCurl(env, exports);
  RegisterNativeToArkts(env, exports);
  RegisterCommons(env, exports);
  RegisterTransmission(env, exports);
  RegisterTorrent(env, exports);

  OH_LOG_INFO(LOG_APP, "transmissionbtm_napi: module initialized");
  return exports;
}
EXTERN_C_END

static napi_module demoModule = {
  1,                       // nm_version
  0,                       // nm_flags
  nullptr,                 // nm_filename
  Init,                    // nm_register_func
  "transmissionbtm_napi",   // nm_modname
  nullptr,                 // nm_priv
  {0},                     // reserved
};

extern "C" __attribute__((constructor)) void RegisterEntryModule(void) {
  napi_module_register(&demoModule);
}
