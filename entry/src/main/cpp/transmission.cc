// transmissionbtm — Session lifecycle (N-API)
// transmissionbtm — session lifecycle via N-API
// Updated for Transmission 4.1 C++ API (2026-07-12)
//
// Key 4.0.6→4.1 changes:
//   tr_variant* → tr_variant (value type, const& params)
//   tr_sessionInit(configDir, bool, &settings) → tr_sessionInit(string_view, bool, const&)
//   tr_sessionLoadSettings() → tr_sessionGetDefaultSettings() + tr_sessionLoadSettings()
//   tr_sessionGetSettings(session, &out) → returns tr_variant by value
//   tr_sessionClose(session) → tr_sessionClose(session, double timeout_secs)
//   tr_variantDictAddBool/Str/Int → settings.try_emplace(TR_KEY_*, tr_variant{val})
//   tr_variantClear(&settings) → settings.clear()
//   Callbacks: std::function<> types, no void* user_data, 2 params only
//   tr_formatter_*_init() removed entirely
//   tr_sessionSetPaused still exists

#include "commons.h"
#include <libtransmission/transmission.h>
#include <libtransmission/version.h>
#include <libtransmission/variant.h>
#include <libtransmission/quark.h>
#include <libtransmission/session.h>
#include <cstring>
#include <cstdlib>
#include <cstdarg>

#undef LOG_DOMAIN
#undef LOG_TAG
#define LOG_DOMAIN 0x0001
#define LOG_TAG "transmissionbtm"

// P1 fix (codex review) + B3 (docs/11): live session handles tracked in the
// commons registry (registerSessionHandle/unregisterSessionHandle). SessionStop
// is idempotent — tr_sessionClose frees the session, so a second stop with the
// same handle would otherwise use-after-free. The registry also backs
// getSession() validation: only SessionStart-created handles are accepted.
#define TR_DEFAULT_RPC_PORT 9091

// R7 (#19/#25) + codex review P1: the composed proxy-url (with embedded
// user:pass@) is applied to the live session at init, but must NEVER be written
// to settings.json — that is a second plaintext-credential exposure alongside
// the app's own preferences store (the HUKS cipher covers the latter; settings.json
// lives in the app's settingsDir). Transmission persists proxy-url as a session
// setting (session-settings.h Field{TR_KEY_proxy_url}), so strip it from any
// settings variant before tr_sessionSaveSettings. The app re-applies proxy from
// its (HUKS-encrypted) preferences on every session start, so losing it from the
// snapshot is harmless. The RPC username/password are the same class of secret:
// they are valid session-settings keys and would otherwise be written in
// plaintext by tr_sessionSaveSettings, mirroring the proxy exposure — strip
// those too.
static void StripCredentialsFromSettings(tr_variant &settings) {
  if (auto *map = settings.get_if<tr_variant::Map>()) {
    map->erase(TR_KEY_proxy_url);
    map->erase(TR_KEY_rpc_username);
    map->erase(TR_KEY_rpc_password);
  }
}

// Forward declarations from native_to_arkts.cc (C linkage)
extern "C" {
void callTorrentChangedCallback(tr_torrent_id_t torrent_id);
void callTorrentStoppedCallback(tr_torrent_id_t torrent_id);
void callSessionChangedCallback();
void callAltSpeedChangedCallback();
}

// ── C++ callbacks (NOT extern "C" — use std::function types) ──────────

// 4.1: tr_rpc_func = raw C pointer tr_rpc_callback_status(*)(tr_session*, tr_rpc_callback_type, tr_torrent*, void*)
static tr_rpc_callback_status rpcFunc(tr_session* /*session*/, tr_rpc_callback_type type,
                                      tr_torrent* tor, void* /*user_data*/) {
  tr_torrent_id_t tid = tor != nullptr ? tr_torrentId(tor) : -1;
  switch (type) {
    case TR_RPC_TORRENT_ADDED:
    case TR_RPC_TORRENT_STARTED:
    case TR_RPC_TORRENT_MOVED:
    case TR_RPC_TORRENT_CHANGED:
      callTorrentChangedCallback(tid);
      break;
    case TR_RPC_TORRENT_STOPPED:
    case TR_RPC_TORRENT_REMOVING:
    case TR_RPC_TORRENT_TRASHING:
      callTorrentStoppedCallback(tid);
      [[fallthrough]];
    case TR_RPC_SESSION_CHANGED:
      callSessionChangedCallback();
      break;
    default:
      break;
  }

  return TR_RPC_OK;
}

// 4.1: tr_session_metadata_func = raw C pointer void(*)(tr_session*, tr_torrent*, void*)
static void metadataCallback(tr_session* /*session*/, tr_torrent* tor, void* /*user_data*/) {
  tr_torrent_id_t tor_id = tor != nullptr ? tr_torrentId(tor) : -1;
  callTorrentChangedCallback(tor_id);
}

// 4.1: tr_altSpeedFunc = raw C pointer void(*)(tr_session*, bool, bool, void*)
static void altSpeedFunc(tr_session* /*session*/, bool /*active*/, bool user_driven, void* /*user_data*/) {
  if (!user_driven) callAltSpeedChangedCallback();
}

extern "C" {

// ── transmissionVersion ─────────────────────────────────────────────
static napi_value TransmissionVersion(napi_env env, napi_callback_info info) {
  (void)info;
  return newStringUtf8(env, SHORT_VERSION_STRING);
}

// ── sessionStart ────────────────────────────────────────────────────
static napi_value SessionStart(napi_env env, napi_callback_info info) {
  size_t argc = 11;
  napi_value args[11];
  napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

  if (argc < 10) {
    napi_throw_error(env, nullptr, "Expected at least 10 arguments");
    return nullptr;
  }

  char *configDir = getStringUtf8(env, args[0]);
  char *downloadsDir = getStringUtf8(env, args[1]);
  if (configDir == nullptr || downloadsDir == nullptr) {
    free(configDir); free(downloadsDir);
    napi_throw_type_error(env, nullptr, "Arguments 0 and 1 must be strings");
    return nullptr;
  }
  int32_t encrMode = 0;
  if (napi_get_value_int32(env, args[2], &encrMode) != napi_ok) {
    free(configDir); free(downloadsDir);
    napi_throw_type_error(env, nullptr, "Argument 2 must be an int32");
    return nullptr;
  }
  bool enableRpc, enableAuth, enableRpcWhitelist;
  if (napi_get_value_bool(env, args[3], &enableRpc) != napi_ok) {
    free(configDir); free(downloadsDir);
    napi_throw_type_error(env, nullptr, "Argument 3 must be a boolean");
    return nullptr;
  }
  int32_t rpcPort = TR_DEFAULT_RPC_PORT;
  if (napi_get_value_int32(env, args[4], &rpcPort) != napi_ok) {
    free(configDir); free(downloadsDir);
    napi_throw_type_error(env, nullptr, "Argument 4 must be an int32");
    return nullptr;
  }
  if (napi_get_value_bool(env, args[5], &enableAuth) != napi_ok) {
    free(configDir); free(downloadsDir);
    napi_throw_type_error(env, nullptr, "Argument 5 must be a boolean");
    return nullptr;
  }
  char *username = getStringUtf8(env, args[6]);
  char *password = getStringUtf8(env, args[7]);
  if (napi_get_value_bool(env, args[8], &enableRpcWhitelist) != napi_ok) {
    free(configDir); free(downloadsDir); free(username); free(password);
    napi_throw_type_error(env, nullptr, "Argument 8 must be a boolean");
    return nullptr;
  }
  char *rpcWhitelist = getStringUtf8(env, args[9]);

  bool suspend = false;

  // 4.1: Get default settings as value type, then override specific keys.
  // try_emplace is on tr_variant::Map, not on tr_variant directly.
  auto settings = tr_sessionGetDefaultSettings();
  auto &map = *settings.get_if<tr_variant::Map>();

  // P1 fix (codex review): settingsJson was only logged then freed — the
  // persisted SessionConfig (speed limits, alt-speed, proxy, blocklist,
  // seeding limits, peer ports, ...) was never applied. Merge it over the
  // defaults first; explicit args below then override the keys they cover.
  if (argc >= 11) {
    char *settingsJson = getStringUtf8(env, args[10]);
    if (settingsJson != nullptr && settingsJson[0] != '\0') {
      // parse_json is private on tr_variant_serde — parse() is the public
      // entry point (serde::json() selects the JSON format). Pass an explicit
      // std::string_view: the CharSpan template overload can't deduce from a
      // raw char* (std::data/std::size fail on pointers).
      auto parsed = tr_variant_serde::json().parse(std::string_view{settingsJson});
      if (parsed.has_value()) {
        auto *parsedMap = parsed->get_if<tr_variant::Map>();
        if (parsedMap != nullptr) {
          // tr_variant is move-only — take ownership of each value.
          for (auto &kv : *parsedMap) {
            map[kv.first] = std::move(kv.second);
          }
        }
      }
    }
    // M4 (review): settingsJson was only freed on the non-empty branch — an
    // empty-string arg leaked. free() is null-safe; run it on every path.
    free(settingsJson);
  }

  // Note: the bundled libcurl has no OS CA store (native
  // libcurl on Android/HarmonyOS can't reach the system trust store), so HTTPS
  // tracker announces fail TLS with "Could not connect to tracker" (rc=60
  // peer failed verification). Android upstream disables engine cert
  // verification via these two libcurl env vars (Native.java initNativeContext)
  // — keep parity with the proven reference implementation. This applies to
  // every libtransmission HTTPS request (tracker announce, etc.).
  setenv("TR_CURL_SSL_NO_VERIFY", "true", 1);
  setenv("TR_CURL_PROXY_SSL_NO_VERIFY", "true", 1);

  // Apply core download settings (explicit args override the JSON above)
  map[TR_KEY_download_dir] = tr_variant{downloadsDir};
  map[TR_KEY_encryption] = static_cast<int64_t>(encrMode);

  // Session tuning NOT exposed via SessionConfig (v1.0). Every key the user
  // can configure — rename-partial-files, utp/pex/dht/lpd, trash-original,
  // peer/seeding limits, start-added-torrents, ... — now comes from
  // settingsJson (or libtransmission defaults). No hardcoded overrides that
  // would shadow user config (codex P1). peer-port now comes exclusively from
  // settingsJson: buildSettingsJson emits peer-port-random-on-start:false so a
  // configured port is honored rather than randomized on every start (codex P1:
  // the old hardcoded `= true` made the Settings peer-port control a no-op).
  map[TR_KEY_port_forwarding_enabled] = false;

  // RPC settings
  if (enableRpc) {
    map[TR_KEY_rpc_enabled] = true;
    map[TR_KEY_rpc_port] = static_cast<int64_t>(rpcPort);

    if (enableAuth) {
      map[TR_KEY_rpc_username] = tr_variant{username ? username : ""};
      map[TR_KEY_rpc_password] = tr_variant{password ? password : ""};
      map[TR_KEY_rpc_authentication_required] = true;
    } else {
      map[TR_KEY_rpc_authentication_required] = false;
    }

    if (enableRpcWhitelist) {
      map[TR_KEY_rpc_whitelist] = tr_variant{rpcWhitelist ? rpcWhitelist : "127.0.0.1"};
      map[TR_KEY_rpc_whitelist_enabled] = true;
    } else {
      map[TR_KEY_rpc_whitelist_enabled] = false;
    }
  } else {
    map[TR_KEY_rpc_enabled] = false;
  }

  // 4.1: tr_sessionInit takes std::string_view and tr_variant const&
  tr_session *session = tr_sessionInit(configDir, true, settings);
  if (session == nullptr) {
    free(configDir); free(downloadsDir); free(username); free(password); free(rpcWhitelist);
    napi_throw_error(env, nullptr, "Failed to initialize transmission session");
    return nullptr;
  }
  // R7 + codex review: strip proxy/RPC credentials from the settings snapshot
  // before persisting. The live session keeps the proxy (applied at init, above);
  // only the on-disk settings.json drops the inline user:pass@ and rpc creds.
  StripCredentialsFromSettings(settings);
  tr_sessionSaveSettings(session, configDir, settings);
  registerSessionHandle(session);

  free(configDir);
  free(downloadsDir);
  free(username);
  free(password);
  free(rpcWhitelist);

  napi_value jsession;
  napi_create_bigint_uint64(env, (uint64_t)(uintptr_t)session, &jsession);

  // 4.1: Set callbacks (3 params incl. user_data)
  tr_sessionSetRPCCallback(session, rpcFunc, nullptr);
  tr_sessionSetAltSpeedFunc(session, altSpeedFunc, nullptr);
  tr_sessionSetMetadataCallback(session, metadataCallback, nullptr);

  // Note: tr_sessionSetPaused is applied once, after load, below (the old
  // duplicate `tr_sessionSetPaused(session, false)` was redundant).
  tr_ctor *ctor = tr_ctorNew(session);
  tr_sessionLoadTorrents(session, ctor);
  tr_sessionSetPaused(session, suspend);
  tr_ctorFree(ctor);

  return jsession;
}

// ── sessionStop ─────────────────────────────────────────────────────
static napi_value SessionStop(napi_env env, napi_callback_info info) {
  size_t argc = 2;
  napi_value args[2];
  napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

  if (argc < 2) {
    napi_throw_error(env, nullptr, "Expected 2 arguments: session, configDir");
    return nullptr;
  }

  tr_session *session = getSession(env, args[0]);
  char *configDir = getStringUtf8(env, args[1]);

  if (session == nullptr) {
    free(configDir);
    napi_throw_error(env, nullptr, "Invalid session handle");
    return nullptr;
  }

  // P1 fix (codex review): double-stop guard. tr_sessionClose frees the
  // session; a second stop with the same handle is a use-after-free. The
  // registry (populated by SessionStart) makes stop idempotent across
  // repeated calls and service teardown — unregisterSessionHandle is an
  // atomic check-and-erase.
  if (!unregisterSessionHandle(session)) {
    free(configDir);
    napi_value result;
    napi_get_undefined(env, &result);
    return result;
  }

  // 4.1: tr_sessionGetSettings returns tr_variant by value
  auto settings = tr_sessionGetSettings(session);
  // R7 + codex review: strip proxy/RPC credentials from the snapshot before
  // persisting (the session may still hold proxy-url internalized from init).
  StripCredentialsFromSettings(settings);
  tr_sessionSaveSettings(session, configDir, settings);
  // B1 (codex P1 UAF fix): after unregister, new dispatches fail at
  // retainSessionForDispatch; wait for any *already-in-flight* dispatches
  // (e.g. a taskpool relocate/add) to drain before freeing the session. Without
  // this, tr_sessionClose can free a tr_session* a worker is still using.
  waitSessionIdle(session);
  tr_sessionClose(session, 15.0);
  free(configDir);

  napi_value result;
  napi_get_undefined(env, &result);
  return result;
}

// ── sessionSuspend ──────────────────────────────────────────────────
typedef struct { bool suspend; } SuspendData;
static void *transmissionSuspendFunc(tr_session *session, void *data, Err *err) {
  (void)err;
  auto *sd = (SuspendData *) data;
  tr_sessionSetPaused(session, sd->suspend);
  return nullptr;
}

static napi_value SessionSuspend(napi_env env, napi_callback_info info) {
  size_t argc = 2;
  napi_value args[2];
  napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

  if (argc < 2) {
    napi_throw_error(env, nullptr, "Expected 2 arguments: session, suspend");
    return nullptr;
  }

  bool suspend = false;
  if (napi_get_value_bool(env, args[1], &suspend) != napi_ok) {
    napi_throw_type_error(env, nullptr, "Argument 1 must be a boolean");
    return nullptr;
  }

  SuspendData d = {suspend};
  runInTransmissionThread(__FILE__, __LINE__, env, args[0], transmissionSuspendFunc, &d);

  napi_value result;
  napi_get_undefined(env, &result);
  return result;
}

// ── sessionSettingsUpdate ───────────────────────────────────────────
// Live re-apply of settings changed while the session is running — no
// restart. The ArkTS side rebuilds the same kebab-case settings JSON that
// SessionStart merges at init; here we funnel it through tr_sessionSet (the
// single 4.1 runtime setter) on the session's event thread so a change takes
// effect immediately. We deliberately do NOT re-persist settings.json here:
// tr_sessionSet mutates the running session, and SessionStop already saves the
// canonical (credentials-stripped) settings at teardown. Persisting on every
// update would need a second credential-strip and is redundant with stop.
struct SettingsUpdateData {
  tr_variant settings;
};

static void *transmissionSettingsUpdateFunc(tr_session *session, void *data, Err *err) {
  (void)err;
  auto *sd = (SettingsUpdateData *) data;
  tr_sessionSet(session, sd->settings);
  return nullptr;
}

static napi_value SessionSettingsUpdate(napi_env env, napi_callback_info info) {
  size_t argc = 2;
  napi_value args[2];
  napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

  if (argc < 2) {
    napi_throw_error(env, nullptr, "Expected 2 arguments: session, settingsJson");
    return nullptr;
  }

  tr_session *session = getSession(env, args[0]);
  if (session == nullptr) {
    napi_throw_error(env, nullptr, "Invalid session handle");
    return nullptr;
  }

  char *settingsJson = getStringUtf8(env, args[1]);
  if (settingsJson == nullptr || settingsJson[0] == '\0') {
    free(settingsJson);
    napi_throw_type_error(env, nullptr, "Argument 1 must be a non-empty JSON string");
    return nullptr;
  }

  // Same parse as SessionStart: parse() is the public entry point on
  // tr_variant_serde, with an explicit std::string_view (the CharSpan
  // template overload can't deduce from a raw char*).
  auto parsed = tr_variant_serde::json().parse(std::string_view{settingsJson});
  free(settingsJson);
  if (!parsed.has_value()) {
    napi_throw_error(env, nullptr, "Failed to parse settings JSON");
    return nullptr;
  }

  // tr_variant is move-only; runInTransmissionThread needs a stable pointer
  // for the duration of the synchronous worker, so heap-hold the parsed
  // variant and free it once the dispatch returns.
  auto *sd = new SettingsUpdateData();
  sd->settings = std::move(*parsed);
  runInTransmissionThread(__FILE__, __LINE__, env, args[0], transmissionSettingsUpdateFunc, sd);
  delete sd;

  napi_value result;
  napi_get_undefined(env, &result);
  return result;
}

// ── hasDownloadingTorrents ──────────────────────────────────────────
static void *transmissionHasDownloadingTorrents(tr_session *session, void *data, Err *err) {
  (void)data;
  (void)err;
  for (auto tor : session->torrents()) {
    switch (tor->activity()) {
      case TR_STATUS_DOWNLOAD:
      case TR_STATUS_DOWNLOAD_WAIT:
      case TR_STATUS_CHECK:
      case TR_STATUS_CHECK_WAIT:
        return (void *)true;
      default:
        continue;
    }
  }
  return (void *)false;
}

static napi_value HasDownloadingTorrents(napi_env env, napi_callback_info info) {
  size_t argc = 1;
  napi_value args[1];
  napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

  if (argc < 1) {
    napi_throw_error(env, nullptr, "Expected 1 argument: session");
    return nullptr;
  }
  tr_session *session = getSession(env, args[0]);
  if (session == nullptr) {
    napi_value r; napi_get_boolean(env, false, &r); return r;
  }
  bool has = runInTransmissionThread(__FILE__, __LINE__, env, args[0],
      transmissionHasDownloadingTorrents, nullptr) != nullptr;

  napi_value result;
  napi_get_boolean(env, has, &result);
  return result;
}

// ── listTorrentNames ────────────────────────────────────────────────
typedef struct ListTorrentsData {
  int count;
  char **torrents;
} ListTorrentsData;

static void *transmissionListTorrentNamesFunc(tr_session *session, void *data, Err *err) {
  (void)err;
  ListTorrentsData *d = (ListTorrentsData *)data;
  d->count = (int)session->torrents().size();
  if (d->count == 0) return nullptr;
  d->torrents = (char **)malloc(d->count * sizeof(char *));
  if (d->torrents == nullptr) { d->count = 0; return nullptr; }
  int i = 0;

  for (auto tor : session->torrents()) {
    auto hashStr = tr_torrentView(tor).hash_string;
    auto &name = tor->name();
    // P1 fix (codex review): the old `hashLen + nameLen + 12` under-allocated
    // by one byte for a 10-digit torrent id ("%d" can produce 10 chars plus
    // two spaces plus NUL). Two-pass snprintf sizes the buffer exactly.
    int need = snprintf(nullptr, 0, "%d %s %s", tr_torrentId(tor), hashStr, name.c_str());
    if (need < 0) goto fail;
    size_t lineLen = (size_t)need + 1;
    char *line = (char *)malloc(lineLen);
    if (line == nullptr) goto fail;
    snprintf(line, lineLen, "%d %s %s", tr_torrentId(tor), hashStr, name.c_str());
    d->torrents[i++] = line;
  }

  return nullptr;

fail:
  // M3 (review): a partial failure left d->torrents filled to `i` but
  // d->count at the full count, so the wrapper derefed/leaked garbage slots.
  // Tear down what we built and signal empty.
  for (int j = 0; j < i; j++) free(d->torrents[j]);
  free(d->torrents);
  d->torrents = nullptr;
  d->count = 0;
  return nullptr;
}

static napi_value ListTorrentNames(napi_env env, napi_callback_info info) {
  size_t argc = 1;
  napi_value args[1];
  napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

  tr_session *session = getSession(env, args[0]);
  if (session == nullptr) {
    napi_value r; napi_get_null(env, &r); return r;
  }
  ListTorrentsData d = {0, nullptr};
  runInTransmissionThread(__FILE__, __LINE__, env, args[0], transmissionListTorrentNamesFunc, &d);

  if (d.count == 0) {
    napi_value result;
    napi_get_null(env, &result);
    return result;
  }

  napi_value result;
  napi_create_array_with_length(env, d.count, &result);

  for (int i = 0; i < d.count; i++) {
    napi_value item = newStringUtf8(env, d.torrents[i]);
    napi_set_element(env, result, i, item);
    free(d.torrents[i]);
  }
  free(d.torrents);
  return result;
}

// ── getEncryptionMode ───────────────────────────────────────────────
typedef struct { int32_t mode; } EncryptionData;
static void *transmissionGetEncryptionFunc(tr_session *session, void *data, Err *err) {
  (void)err;
  auto *ed = (EncryptionData *) data;
  ed->mode = (int32_t) tr_sessionGetEncryption(session);
  return nullptr;
}

static napi_value GetEncryptionMode(napi_env env, napi_callback_info info) {
  size_t argc = 1;
  napi_value args[1];
  napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

  if (argc < 1) {
    napi_throw_error(env, nullptr, "Expected 1 argument: session");
    return nullptr;
  }
  EncryptionData d = {0};
  runInTransmissionThread(__FILE__, __LINE__, env, args[0], transmissionGetEncryptionFunc, &d);
  napi_value result;
  napi_create_int32(env, d.mode, &result);
  return result;
}

// ── Module registration ─────────────────────────────────────────────
void RegisterTransmission(napi_env env, napi_value exports) {
  napi_property_descriptor desc[] = {
    {"transmissionVersion",         nullptr, TransmissionVersion,         nullptr, nullptr, nullptr, napi_default, nullptr},
    {"sessionStart",                nullptr, SessionStart,                nullptr, nullptr, nullptr, napi_default, nullptr},
    {"sessionStop",                 nullptr, SessionStop,                 nullptr, nullptr, nullptr, napi_default, nullptr},
    {"sessionSuspend",              nullptr, SessionSuspend,              nullptr, nullptr, nullptr, napi_default, nullptr},
    {"sessionSettingsUpdate",       nullptr, SessionSettingsUpdate,       nullptr, nullptr, nullptr, napi_default, nullptr},
    {"hasDownloadingTorrents",      nullptr, HasDownloadingTorrents,      nullptr, nullptr, nullptr, napi_default, nullptr},
    {"listTorrentNames",            nullptr, ListTorrentNames,            nullptr, nullptr, nullptr, napi_default, nullptr},
    {"getEncryptionMode",           nullptr, GetEncryptionMode,           nullptr, nullptr, nullptr, napi_default, nullptr}
  };
  napi_define_properties(env, exports, sizeof(desc) / sizeof(desc[0]), desc);
}

} // extern "C"
