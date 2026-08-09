// transmissionhm — Semaphore wrappers (N-API)
// Adapted from transmissionbtc sem.cc (JNI → N-API)
// POSIX sem_init/sem_wait/sem_post/sem_destroy — works on OH musl.

#include <napi/native_api.h>
#include <semaphore.h>
#include <cstdlib>
#include <cstring>

static napi_value SemCreate(napi_env env, napi_callback_info /*info*/) {
  sem_t *sem = (sem_t *)malloc(sizeof(sem_t));
  if (sem == nullptr) {
    napi_throw_error(env, nullptr, "malloc failed for sem_t");
    return nullptr;
  }
  sem_init(sem, 0, 0);

  napi_value result;
  napi_create_bigint_uint64(env, (uint64_t)(uintptr_t)sem, &result);
  return result;
}

static napi_value SemDestroy(napi_env env, napi_callback_info info) {
  size_t argc = 1;
  napi_value args[1];
  napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

  uint64_t val;
  bool lossless;
  napi_get_value_bigint_uint64(env, args[0], &val, &lossless);
  sem_t *sem = (sem_t *)(uintptr_t)val;
  sem_destroy(sem);
  free(sem);

  napi_value result;
  napi_get_undefined(env, &result);
  return result;
}

static napi_value SemPost(napi_env env, napi_callback_info info) {
  size_t argc = 1;
  napi_value args[1];
  napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

  uint64_t val;
  bool lossless;
  napi_get_value_bigint_uint64(env, args[0], &val, &lossless);
  sem_t *sem = (sem_t *)(uintptr_t)val;
  sem_post(sem);

  napi_value result;
  napi_get_undefined(env, &result);
  return result;
}

extern "C" void RegisterSem(napi_env env, napi_value exports) {
  napi_property_descriptor desc[] = {
    {"semCreate",  nullptr, SemCreate,  nullptr, nullptr, nullptr, napi_default, nullptr},
    {"semDestroy", nullptr, SemDestroy, nullptr, nullptr, nullptr, napi_default, nullptr},
    {"semPost",    nullptr, SemPost,    nullptr, nullptr, nullptr, napi_default, nullptr}
  };
  napi_define_properties(env, exports, sizeof(desc) / sizeof(desc[0]), desc);
}
