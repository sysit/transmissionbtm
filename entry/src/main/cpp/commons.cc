// transmissionhm — Common utilities for N-API native bridge
// Adapted from transmissionbtc commons.cc (JNI → N-API)
// Updated for Transmission 4.1 C++ API (2026-07-12)
//
// Key 3.00→4.0.6 changes:
//   tr_info → tr_torrent accessor methods (fileCount(), name(), fileSubpath(), etc.)
//   tr_runInEventThread() → session->run(std::function)
//   tr_file → tr_file_view (by-value struct, see transmission.h)
//   dnd → wanted (inverted semantics: !f.wanted means "don't download")
//   throwException → throwNapiException

#include "commons.h"
#include <cstdio>
#include <cstdarg>

// ── N-API exception helper ──────────────────────────────────────────
extern "C" napi_value throwNapiException(const char *file, int line, napi_env env,
                                         const char *code, const char *format, ...) {
  int len;
  char msg[256];
  const char *fmt = format;

#ifndef NDEBUG
  char dfmt[1024];
  len = snprintf(dfmt, sizeof(dfmt), "[%s:%d] %s", file, line, format);
  if (len > 0) fmt = dfmt;
#endif

  va_list args;
  va_start(args, format);
  len = vsnprintf(msg, sizeof(msg), fmt, args);
  va_end(args);
  if (len > 0) fmt = msg;

  napi_throw_error(env, code, fmt);
  return nullptr;
}

// ── File copy ───────────────────────────────────────────────────────
extern "C" size_t cp(napi_env env, const char *fromPath, const char *toPath) {
  FILE *from = nullptr, *to = nullptr;
  size_t count = 0;

  if ((from = fopen(fromPath, "rb")) == nullptr) {
    throwIOEX(env, "Failed to open source file %s", fromPath);
  }

  if ((to = fopen(toPath, "wb")) == nullptr) {
    fclose(from);
    from = nullptr;  // prevent double-close in CATCH block
    throwIOEX(env, "Failed to open destination file %s", toPath);
  }

  size_t n;
  char buffer[BUFSIZ];

  while ((n = fread(buffer, sizeof(char), sizeof(buffer), from)) > 0) {
    if (fwrite(buffer, sizeof(char), n, to) != n) {
      throwIOEX(env, "Error writing to destination file %s", toPath);
    } else {
      count += n;
    }
  }

  CATCH:
  if (from != nullptr) fclose(from);
  if (to != nullptr) fclose(to);
  return count;
}

// ── Torrent constructor from file ───────────────────────────────────
tr_ctor *ctorFromFile(napi_env env, napi_value jsession, napi_value jpath, bool throwErr) {
  tr_session *session = (jsession != nullptr) ? getSession(env, jsession) : nullptr;
  char *path = getStringUtf8(env, jpath);
  tr_ctor *ctor = tr_ctorNew(session);

  if (path == nullptr) {
    tr_ctorFree(ctor);
    ctor = nullptr;
    throwOrLog(env, ERR_ARG, throwErr, "Invalid path argument (null)");
  }

  // 4.0.6: tr_ctorSetMetainfoFromFile takes std::string_view, returns bool
  if (ctor != nullptr && !tr_ctorSetMetainfoFromFile(ctor, path)) {
    tr_ctorFree(ctor);
    ctor = nullptr;
    throwOrLog(env, ERR_IO, throwErr, "Invalid torrent file: %s", path);
  }

  CATCH:
  free(path);
  return ctor;
}

// ── Parse/validate torrent info from file ───────────────────────────
// 4.0.6: tr_torrentParse() and tr_info removed. Validate via ctor + metainfo API.
bool
infoFromFile(napi_env env, napi_value jsession, napi_value jpath, bool throwErr) {
  (void)jsession;
  char *path = nullptr;
  tr_ctor *ctor = nullptr;
  bool result = false;

  path = getStringUtf8(env, jpath);
  if (path == nullptr) goto CATCH;

  ctor = tr_ctorNew(nullptr);
  if (tr_ctorSetMetainfoFromFile(ctor, path)) {
    // tr_ctorGetMetainfo returns non-null when metainfo is present
    if (tr_ctorGetMetainfo(ctor) != nullptr) result = true;
  }

  if (result != true) {
    throwOrLog(env, ERR_IO, throwErr, "Failed to parse torrent file: %s", path);
  }

  CATCH:
  free(path);
  if (ctor != nullptr) tr_ctorFree(ctor);
  return result;
}

// ── Torrent lookup by hash ──────────────────────────────────────────
// 4.0.6: tr_torrentFindFromHash() removed. Iterate session->torrents() instead.
int findTorrentByHash(tr_session *session, uint8_t *hash, Err *err) {
  tr_torrent *found = nullptr;
  for (auto tor : session->torrents()) {
    auto const &torHash = tor->metainfo().info_hash();
    if (memcmp(std::data(torHash), hash, SHA_DIGEST_LENGTH) == 0) {
      found = tor;
      break;
    }
  }

  if (found == nullptr) {
    if (err != nullptr) {
      char hashString[1 + 2 * SHA_DIGEST_LENGTH];
      tr_binary_to_hex(hash, hashString, SHA_DIGEST_LENGTH);
      err->set(ERR_NO_SUCH, "No such torrent: hash=%s", hashString);
    }
    return -1;
  }

  return tr_torrentId(found);
}

// ── Torrent lookup by ID ────────────────────────────────────────────
tr_torrent *findTorrentById(tr_session *session, int id, Err *err) {
  tr_torrent *tor = tr_torrentFindFromId(session, id);
  if (tor == nullptr && err != nullptr)
    err->set(ERR_NO_SUCH, "No such torrent: id=%d", id);
  return tor;
}

// ── File info by index (4.0.6: returns tr_file_view by value) ───────
tr_file_view getFileInfo(tr_torrent *tor, uint32_t idx, Err *err) {
  if (idx >= tor->file_count()) {
    if (err != nullptr)
      err->set(ERR_ARG, "Invalid file index: %d", idx);
    return {};
  }
  return tr_torrentFile(tor, idx);
}

// ── Wanted file info by index ───────────────────────────────────────
tr_file_view getWantedFileInfo(tr_torrent *tor, uint32_t idx, Err *err) {
  tr_file_view f = getFileInfo(tor, idx, err);
  if (err != nullptr && err->isSet) goto CATCH;
  if (!f.wanted) {
    if (err != nullptr)
      err->set(ERR_ARG, "File #%d is unwanted for download: %s", idx, f.name);
    return {};
  }
  CATCH:
  return f;
}

// ── Err::set implementation ──────────────────────────────────────────
// P0 fix (codex review): real method on Err (was a null function pointer).
void Err::set(const char *exception, const char *msg, ...) {
  if (exMsg == nullptr) {
    exMsgBufLen = 512;
    exMsg = (char *) calloc(exMsgBufLen, sizeof(char));
  }

  va_list args;
  va_start(args, msg);
  vsnprintf(exMsg, exMsgBufLen, msg, args);
  va_end(args);
  ex = exception;
  isSet = true;
}

// ── Thread dispatch (semaphore-based, adapted for 4.0.6 session API) ─
struct Future {
  Err err;
  sem_t sem;
  tr_session *session;
  void *userData;
  void *result;

  void *(*func)(tr_session *session, void *userData, Err *err);
};

static void runFutureFunc(struct Future *f) {
  f->result = f->func(f->session, f->userData, &(f->err));
  sem_post(&(f->sem));
}

void *runInTransmissionThread(const char *file, int line, napi_env env,
                              napi_value jsession,
                              void *(*func)(tr_session *, void *, Err *),
                              void *userData) {
  struct Future f;
  sem_t *sem = &(f.sem);
  sem_init(sem, 0, 0);
  f.session = getSession(env, jsession);
  f.userData = userData;
  f.func = func;

  // 4.0.6: tr_runInEventThread() removed. Run directly on calling thread.
  // The calling ArkTS thread is NOT the transmission event thread,
  // but this is safe for simple queries and short-lived operations.
  runFutureFunc(&f);

  while ((sem_wait(sem) == -1) && (errno == EINTR));
  sem_destroy(sem);

  if (f.err.isSet) {
    throwNapiException(file, line, env, f.err.ex, f.err.exMsg);
    free(f.err.exMsg);
    return nullptr;
  } else {
    return f.result;
  }
}

// ── N-API string helpers ────────────────────────────────────────────
extern "C" char *getStringUtf8(napi_env env, napi_value value) {
  if (value == nullptr) return nullptr;

  size_t bufSize;
  napi_status status = napi_get_value_string_utf8(env, value, nullptr, 0, &bufSize);
  if (status != napi_ok) return nullptr;

  char *buf = (char *) malloc(bufSize + 1);
  if (buf == nullptr) return nullptr;

  status = napi_get_value_string_utf8(env, value, buf, bufSize + 1, &bufSize);
  if (status != napi_ok) {
    free(buf);
    return nullptr;
  }
  return buf;
}

extern "C" napi_value newStringUtf8(napi_env env, const char *str) {
  if (str == nullptr) {
    napi_value result;
    napi_get_undefined(env, &result);
    return result;
  }
  napi_value result;
  napi_status status = napi_create_string_utf8(env, str, NAPI_AUTO_LENGTH, &result);
  if (status != napi_ok) {
    napi_get_undefined(env, &result);
  }
  return result;
}

// ── Session pointer extraction (ArkTS passes BigInt) ────────────────
extern "C" tr_session *getSession(napi_env env, napi_value jsession) {
  if (jsession == nullptr) return nullptr;

  uint64_t val;
  bool lossless;
  napi_status status = napi_get_value_bigint_uint64(env, jsession, &val, &lossless);
  if (status != napi_ok) return nullptr;

  return (tr_session *) (uintptr_t) val;
}

// ── Module registration ─────────────────────────────────────────────
extern "C" void RegisterCommons(napi_env /*env*/, napi_value /*exports*/) {
  // Commons functions are used internally by other modules.
  // No N-API exports at this time — registration is a no-op
  // but required by napi_init.cpp for consistent module initialization.
}

// ── Hex conversion utilities (4.0.6: removed from public API) ────────

void tr_binary_to_hex(void const *input, char *output, size_t byte_length) {
  static char const hex[] = "0123456789abcdef";
  auto const *in = static_cast<uint8_t const *>(input);
  for (size_t i = 0; i < byte_length; ++i) {
    output[i * 2] = hex[in[i] >> 4];
    output[i * 2 + 1] = hex[in[i] & 0xf];
  }
  output[byte_length * 2] = '\0';
}

bool tr_hex_to_binary(char const *input, void *output, size_t byte_length) {
  auto *out = static_cast<uint8_t *>(output);
  if (output == nullptr || byte_length == 0) {
    return true;  // Nothing to do
  }
  if (input == nullptr || strlen(input) < 2 * byte_length) {
    // P0/P1 fix (codex review): short input would have caused an out-of-bounds
    // heap read. Zero-fill the output and report failure to the caller.
    memset(out, 0, byte_length);
    return false;
  }
  for (size_t i = 0; i < byte_length; ++i) {
    auto high = input[i * 2];
    auto low = input[i * 2 + 1];
    out[i] = static_cast<uint8_t>(
      ((high >= 'a' ? high - 'a' + 10 : high >= 'A' ? high - 'A' + 10 : high - '0') << 4) |
       (low >= 'a' ? low - 'a' + 10 : low >= 'A' ? low - 'A' + 10 : low - '0'));
  }
  return true;
}
