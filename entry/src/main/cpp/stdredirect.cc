// transmissionhm — C stdout/stderr → hilog redirection
// Adapted from transmissionbtc: __android_log_write → OH_LOG_Print
// M0: M1 hooks into session start.

#include <napi/native_api.h>
#include <hilog/log.h>
#include <cstdio>
#include <cstdlib>
#include <unistd.h>
#include <errno.h>
#include <pthread.h>

#undef LOG_DOMAIN
#undef LOG_TAG
#define LOG_DOMAIN 0x0001
#define LOG_TAG "libtransmission"

static int pfd[2];
static pthread_t thr;

static void *thread_func(void * /*unused*/) {
  ssize_t rdsz;
  char buf[128];
  while ((rdsz = read(pfd[0], buf, sizeof(buf) - 1)) != 0) {
    if (rdsz < 0) {
      if (errno == EINTR) continue;
      break; // real error or pipe closed
    }
    if (buf[rdsz - 1] == '\n') --rdsz;
    buf[rdsz] = 0;
    OH_LOG_Print(LOG_APP, LOG_DEBUG, LOG_DOMAIN, LOG_TAG, "%{private}s", buf);
  }
  return nullptr;
}

static napi_value StdRedirect(napi_env env, napi_callback_info /*info*/) {
  setvbuf(stdout, nullptr, _IOLBF, 0);
  setvbuf(stderr, nullptr, _IONBF, 0);

  pipe(pfd);
  dup2(pfd[1], 1);
  dup2(pfd[1], 2);

  if (pthread_create(&thr, nullptr, thread_func, nullptr) == -1) {
    napi_throw_error(env, nullptr, "pthread_create() failed");
  } else {
    pthread_detach(thr);
  }

  napi_value result;
  napi_get_undefined(env, &result);
  return result;
}

// ── Module registration helper ──────────────────────────────────
extern "C" void RegisterStdRedirect(napi_env env, napi_value exports) {
  napi_property_descriptor desc[] = {
    {"stdRedirect", nullptr, StdRedirect, nullptr, nullptr, nullptr, napi_default, nullptr}
  };
  napi_define_properties(env, exports, sizeof(desc) / sizeof(desc[0]), desc);
}
