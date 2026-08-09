// transmissionhm — Hash utilities (N-API)
// Adapted from transmissionbtc hash.cc (JNI → N-API)
//
// Key changes:
//   jbyteArray → napi_value (ArrayBuffer)
//   jstring    → napi_value + getStringUtf8/newStringUtf8
//   JNIEXPORT jint JNICALL Java_* → static napi_value

#include <napi/native_api.h>
#include <libtransmission/transmission.h>
#include <libtransmission/utils.h>
#include <cstring>
#include <cstdlib>
#include "commons.h"

// ── hashBytesToString ───────────────────────────────────────────────
static napi_value HashBytesToString(napi_env env, napi_callback_info info) {
  size_t argc = 1;
  napi_value args[1];
  napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

  if (argc < 1) {
    napi_throw_error(env, nullptr, "Expected 1 argument: hash buffer");
    return nullptr;
  }

  // P2 fix (codex review): napi_get_arraybuffer_info status was unchecked —
  // a non-ArrayBuffer argument fell through to a misleading "too short" error.
  bool isArrayBuffer;
  napi_is_arraybuffer(env, args[0], &isArrayBuffer);
  if (!isArrayBuffer) {
    napi_throw_type_error(env, nullptr, "Argument 0 must be an ArrayBuffer");
    return nullptr;
  }

  void *data;
  size_t byteLength;
  napi_status status = napi_get_arraybuffer_info(env, args[0], &data, &byteLength);
  if (status != napi_ok || data == nullptr) {
    napi_throw_error(env, nullptr, "Failed to read hash buffer");
    return nullptr;
  }

  if (byteLength < (size_t) SHA_DIGEST_LENGTH) {
    napi_throw_error(env, nullptr, "Hash bytes too short");
    return nullptr;
  }

  char hashString[1 + 2 * SHA_DIGEST_LENGTH];
  tr_binary_to_hex((const uint8_t *) data, hashString, SHA_DIGEST_LENGTH);
  return newStringUtf8(env, hashString);
}

// ── hashStringToBytes ───────────────────────────────────────────────
static napi_value HashStringToBytes(napi_env env, napi_callback_info info) {
  size_t argc = 1;
  napi_value args[1];
  napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

  char *hashString = getStringUtf8(env, args[0]);
  if (hashString == nullptr) {
    napi_throw_error(env, nullptr, "Invalid hash string argument");
    return nullptr;
  }
  // C2 (docs/11): validate it's EXACTLY 40 hex characters. tr_hex_to_binary
  // only rejects too-short input; a non-hex char decoded as garbage produces
  // a bogus hash that silently matches no torrent.
  size_t slen = strlen(hashString);
  if (slen != 2 * (size_t) SHA_DIGEST_LENGTH) {
    free(hashString);
    napi_throw_error(env, nullptr, "Invalid hash string (expected 40 hex characters)");
    return nullptr;
  }
  for (size_t i = 0; i < slen; i++) {
    char c = hashString[i];
    bool isHex = (c >= '0' && c <= '9') || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F');
    if (!isHex) {
      free(hashString);
      napi_throw_error(env, nullptr, "Invalid hash string (non-hex character)");
      return nullptr;
    }
  }

  // P1 fix (codex review): validate that the hex string is long enough
  // (2*SHA_DIGEST_LENGTH chars). A short input previously caused an
  // out-of-bounds read in tr_hex_to_binary; it now zero-fills and returns
  // false, which we surface to the caller instead of a bogus all-zero hash.
  uint8_t hash[SHA_DIGEST_LENGTH];
  if (!tr_hex_to_binary(hashString, hash, SHA_DIGEST_LENGTH)) {
    free(hashString);
    napi_throw_error(env, nullptr, "Invalid hash string (expected 40 hex characters)");
    return nullptr;
  }
  free(hashString);

  napi_value result;
  void *outData;
  napi_create_arraybuffer(env, SHA_DIGEST_LENGTH, &outData, &result);
  memcpy(outData, hash, SHA_DIGEST_LENGTH);
  return result;
}

// ── Module registration ─────────────────────────────────────────────
extern "C" void RegisterHash(napi_env env, napi_value exports) {
  napi_property_descriptor desc[] = {
    {"hashBytesToString", nullptr, HashBytesToString, nullptr, nullptr, nullptr, napi_default, nullptr},
    {"hashStringToBytes", nullptr, HashStringToBytes, nullptr, nullptr, nullptr, napi_default, nullptr}
  };
  napi_define_properties(env, exports, sizeof(desc) / sizeof(desc[0]), desc);
}
