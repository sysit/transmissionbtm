// transmissionbtm — N-API module registration
// M0: skeleton with getVersion(). M1: full 40-method bridge.
//
// All 9 Register* functions are declared here and called from Init().
// When a submodule's source file is omitted from CMakeLists.txt (M0),
// its Register* function is replaced with a no-op stub below.

#include <napi/native_api.h>
#include <hilog/log.h>

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
  if (napi_create_string_utf8(env, "1.0.0", NAPI_AUTO_LENGTH, &result) != napi_ok) {
    napi_throw_error(env, nullptr, "Failed to create version string");
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
    {"getVersion", nullptr, GetVersion, nullptr, nullptr, nullptr, napi_default, nullptr}
  };
  if (napi_define_properties(env, exports, sizeof(coreDesc) / sizeof(coreDesc[0]), coreDesc) != napi_ok) {
    OH_LOG_ERROR(LOG_APP, "transmissionbtm_napi: failed to register getVersion");
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
