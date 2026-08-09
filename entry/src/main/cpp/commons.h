// transmissionhm — Common utilities for N-API native bridge
// Adapted from transmissionbtc commons.h (JNI → N-API)
// Updated for Transmission 4.1 C++ API (2026-07-12)
//
// Key 3.00→4.0.6 changes:
//   tr_file* → tr_file_view (by-value struct, not pointer)
//   Added internal headers: torrent.h, session.h, error.h

#ifndef TRANSMISSIONHM_COMMONS_H
#define TRANSMISSIONHM_COMMONS_H

#include <napi/native_api.h>
#include <hilog/log.h>
#include <cstdio>
#include <cerrno>
#include <cstdlib>
#include <cstring>
#include <semaphore.h>
#include <libtransmission/transmission.h>
#include <libtransmission/utils.h>
#include <libtransmission/torrent.h>
#include <libtransmission/session.h>
#include <libtransmission/error.h>

// 4.0.6: SHA_DIGEST_LENGTH not in public API.
// tr_sha1_digest_t is std::array<std::byte, 20> (tr-macros.h).
#define SHA_DIGEST_LENGTH 20

// ── Logging ──────────────────────────────────────────────────────
#undef LOG_DOMAIN
#undef LOG_TAG
#define LOG_DOMAIN 0x0001
#define LOG_TAG "transmissionhm"

#define logErr(...) OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, __VA_ARGS__)

// ── Error handling ───────────────────────────────────────────────
#define ERR_IO           "IO_ERROR"
#define ERR_ARG          "ILLEGAL_ARGUMENT"
#define ERR_NO_SUCH      "NO_SUCH_TORRENT"
#define ERR_DUPLICATE    "DUPLICATE_TORRENT"

#define CATCH __onException__

#define __FILENAME__ (strrchr(__FILE__, '/') ? strrchr(__FILE__, '/') + 1 : __FILE__)

#define throwEX(env, code, ...) \
  { throwNapiException(__FILENAME__, __LINE__, env, code, __VA_ARGS__); goto CATCH; }
#define throwIOEX(env, ...) throwEX(env, ERR_IO, __VA_ARGS__)

#define throwOrLog(env, code, doThrow, ...) \
  if (doThrow) { throwEX(env, code, __VA_ARGS__); } \
  else { logErr(__VA_ARGS__); goto CATCH; }

// ── Err type ────────────────────────────────────────────────────
// P0 fix (codex review): `set` was a function pointer initialized to nullptr
// by every direct caller, so findTorrentById/getFileInfo/etc. crashed with a
// null call when a torrent/file was missing. Now `set` is a real method with
// its own storage — always callable, no call through a dangling pointer.
typedef struct Err {
    bool isSet = false;
    const char *ex = nullptr;
    char *exMsg = nullptr;
    uint16_t exMsgBufLen = 0;

    void set(const char *exception, const char *msg, ...) __attribute__((format(printf, 3, 4)));
} Err;
#define errCheck(err) if (err->isSet) goto CATCH

// ── N-API exception helper ──────────────────────────────────────
extern "C" napi_value throwNapiException(const char *file, int line, napi_env env,
                                         const char *code, const char *format, ...);

// ── File utilities ───────────────────────────────────────────────
extern "C" size_t cp(napi_env env, const char *fromPath, const char *toPath);

#define ctorFromFileEx(env, jsession, jpath) \
  ctorFromFile(env, jsession, jpath, true); \
  if (hasPendingException(env)) goto CATCH

inline bool hasPendingException(napi_env env) {
  bool pending = false;
  napi_is_exception_pending(env, &pending);
  return pending;
}

tr_ctor *ctorFromFile(napi_env env, napi_value jsession, napi_value jpath, bool throwErr);

// 4.0.6: tr_info and tr_torrentParse() removed.
// infoFromFile now just validates the file is parseable and returns true/false.
#define infoFromFileEx(env, jsession, jpath) \
  if (!infoFromFile(env, jsession, jpath, true) || \
      hasPendingException(env)) \
    goto CATCH

bool infoFromFile(napi_env env, napi_value jsession, napi_value jpath, bool throwErr);

// ── Torrent lookup ───────────────────────────────────────────────
int  findTorrentByHash(tr_session *session, uint8_t *hash, Err *err);

#define findTorrentByIdEx(session, id, err) findTorrentById(session, id, err); errCheck(err)
tr_torrent *findTorrentById(tr_session *session, int id, Err *err);

// 4.0.6: getFileInfo/getWantedFileInfo return tr_file_view by value
#define getFileInfoEx(tor, idx, err) getFileInfo(tor, idx, err); errCheck(err)
tr_file_view getFileInfo(tr_torrent *tor, uint32_t idx, Err *err);

#define getWantedFileInfoEx(tor, idx, err) getWantedFileInfo(tor, idx, err); errCheck(err)
tr_file_view getWantedFileInfo(tr_torrent *tor, uint32_t idx, Err *err);

// ── Thread dispatch ──────────────────────────────────────────────
#define runInTransmissionThreadEx(env, jsession, func, data) \
  runInTransmissionThread(__FILENAME__, __LINE__, env, jsession, func, data); \
  if (hasPendingException(env)) goto CATCH

void *runInTransmissionThread(const char *file, int line, napi_env env,
                              napi_value jsession,
                              void *(*func)(tr_session *session, void *userData, Err *err),
                              void *userData);

// ── N-API type helpers ──────────────────────────────────────────
inline bool isNapiNull(napi_env env, napi_value val) {
  napi_valuetype type;
  napi_typeof(env, val, &type);
  return type == napi_null || type == napi_undefined;
}

// ── N-API string helpers ─────────────────────────────────────────
extern "C" char *getStringUtf8(napi_env env, napi_value value);
extern "C" napi_value newStringUtf8(napi_env env, const char *str);
extern "C" tr_session *getSession(napi_env env, napi_value jsession);

// ── Session handle registry (B3, docs/11) ─────────────────────────
// getSession() must only return handles created by SessionStart and not
// yet closed. Without this registry, any BigInt passed from ArkTS is
// dereferenced as a tr_session* — a stale handle or BigInt(0) from toPtr
// becomes a wild/null pointer dereference. SessionStart registers, the
// double-stop guard (SessionStop) atomically check-and-erases.
void registerSessionHandle(tr_session *session);
// Returns true if the handle was live (idempotent — second call is a no-op).
bool unregisterSessionHandle(tr_session *session);
bool isLiveSession(tr_session *session);

// ── Hex conversion (4.0.6: tr_binary_to_hex / tr_hex_to_binary removed) ─
void tr_binary_to_hex(void const *input, char *output, size_t byte_length);
// P0/P1 fix (codex review): returns false (and zero-fills output) when the
// input string is shorter than 2*byte_length, preventing an OOB heap read.
bool tr_hex_to_binary(char const *input, void *output, size_t byte_length);


#endif // TRANSMISSIONHM_COMMONS_H
