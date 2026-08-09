// transmissionhm — Environment variable access (N-API)
// Adapted from transmissionbtc env.cc (JNI → N-API)
// OH musl: setenv/unsetenv work directly — no adaptation needed.

#include <napi/native_api.h>
#include <cstdlib>
#include <cstring>

static napi_value EnvUnset(napi_env env, napi_callback_info info) {
  size_t argc = 1;
  napi_value args[1];
  napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

  if (argc < 1) {
    napi_throw_error(env, nullptr, "Expected 1 argument: name");
    return nullptr;
  }

  char name[256];
  size_t len = 0;
  // C2 (docs/11): the napi_get_value_string_utf8 status was unchecked — on a
  // non-string argument len stayed uninitialized and name[len] was an OOB write.
  if (napi_get_value_string_utf8(env, args[0], name, sizeof(name) - 1, &len) != napi_ok) {
    napi_throw_type_error(env, nullptr, "Argument 0 must be a string");
    return nullptr;
  }
  // P1 fix (codex review): clamp len before writing the NUL. On a truncated
  // string some N-API impls report the full required length, which would
  // make name[len] an out-of-bounds write.
  if (len >= sizeof(name)) len = sizeof(name) - 1;
  name[len] = '\0';
  unsetenv(name);

  napi_value result;
  napi_get_undefined(env, &result);
  return result;
}

static napi_value EnvSet(napi_env env, napi_callback_info info) {
  size_t argc = 2;
  napi_value args[2];
  napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

  if (argc < 1) {
    napi_throw_error(env, nullptr, "Expected at least 1 argument: name");
    return nullptr;
  }

  char name[256], value[4096];
  size_t name_len = 0, value_len = 0;
  // C2 (docs/11): status unchecked on the name arg — see EnvUnset.
  if (napi_get_value_string_utf8(env, args[0], name, sizeof(name) - 1, &name_len) != napi_ok) {
    napi_throw_type_error(env, nullptr, "Argument 0 must be a string");
    return nullptr;
  }
  // P1 fix (codex review): same bounds-clamp as EnvUnset — see above.
  if (name_len >= sizeof(name)) name_len = sizeof(name) - 1;
  name[name_len] = '\0';

  // Check if value is null/empty → unset
  if ((argc < 2) ||
      (napi_get_value_string_utf8(env, args[1], value, sizeof(value), &value_len) != napi_ok) ||
      (value_len == 0)) {
    unsetenv(name);
  } else {
    // C2 (docs/11): a value longer than the buffer is not NUL-terminated by
    // the N-API call — clamp and terminate before setenv reads past it.
    if (value_len >= sizeof(value)) value_len = sizeof(value) - 1;
    value[value_len] = '\0';
    setenv(name, value, 1);
  }

  napi_value result;
  napi_get_undefined(env, &result);
  return result;
}

extern "C" void RegisterEnv(napi_env env, napi_value exports) {
  napi_property_descriptor desc[] = {
    {"envUnset", nullptr, EnvUnset, nullptr, nullptr, nullptr, napi_default, nullptr},
    {"envSet",   nullptr, EnvSet,   nullptr, nullptr, nullptr, napi_default, nullptr}
  };
  napi_define_properties(env, exports, sizeof(desc) / sizeof(desc[0]), desc);
}
