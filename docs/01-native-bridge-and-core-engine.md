# 01 — Native Bridge & Core Engine

## Overview

This domain is the foundational layer of the transmissionbtm HarmonyOS BitTorrent client. It bridges the ArkTS application layer with the native C Transmission daemon via the N-API. It encompasses the ArkTS bridge wrapper in `bridge/NativeBridge.ets`, the C++ implementation of every N-API function, Transmission session lifecycle management, torrent CRUD operations, C-to-ArkTS callback bridges, file I/O delegation, a custom CMake-based build system, and synchronization primitives.

The architecture runs the libtransmission event loop on its own thread. N-API thread-safe functions (TSFN) are the only mechanism used to call back into ArkTS when a torrent or the session state changes; all other native calls run on the calling thread and return synchronously.

---

## File Inventory

| File | Purpose |
|------|---------|
| `bridge/NativeBridge.ets` | ArkTS singleton wrapper over the N-API — typed access to every native method, module loading |
| `cpp/napi_init.cpp` | N-API module entry point — registers the `transmissionbtm_napi` module |
| `cpp/commons.cc` / `commons.h` | Shared N-API utilities, error handling (CHECK_STATUS/throwEX/CATCH), thread dispatch, `Err` struct |
| `cpp/transmission.cc` | Session lifecycle N-API functions |
| `cpp/torrent.cc` | All torrent-related N-API functions (CRUD, stat, pieces, DnD, relocate, reannounce) |
| `cpp/native_to_arkts.cc` | C→ArkTS callback bridge via ThreadSafeFunction |
| `cpp/hash.cc` | Torrent hash conversion utilities |
| `cpp/curl.cc` | cURL-based HTTP download wrapper |
| `cpp/env.cc` | Environment variable set/unset |
| `scripts/build-third-party.sh` | Cross-compiles upstream Transmission + OpenSSL + curl + libevent + deps for OH arm64-v8a |
| `third_party/<lib>/lib/` | Cross-compiled static `.a` libraries (transmission, openssl, curl, libevent + sub-deps) |

---

## 1. N-API Bridge (NativeBridge)

### 1.1 Module Loading

The N-API module is loaded by name from the ArkTS side:

```ts
import native from 'libtransmissionbtm_napi.so';
```

`NativeBridge.getInstance()` is a singleton — all native calls go through it. Module init flow:

1. Resolve the module handle `libtransmissionbtm_napi.so` (module name `transmissionbtm_napi`)
2. `nativeToArktsInit()` — C++ side stores the `napi_env` reference and the callback function refs used by the TSFN
3. `envSet("TR_CURL_SSL_NO_VERIFY", "true")` + `envSet("TR_CURL_PROXY_SSL_NO_VERIFY", "true")`

### 1.2 Complete Native Method Catalog (35 methods)

**Session (transmission.cc):**

| Method | Description |
|--------|-------------|
| `transmissionVersion` | Transmission `SHORT_VERSION_STRING` |
| `sessionStart` | Init session (configDir, downloadsDir, encrMode, RPC settings, loadConfig, sequential, paused). Returns opaque session ptr (BigInt). Throws on error |
| `sessionStop` | Save settings + close session |
| `sessionSuspend` | Suspend/resume session |
| `hasDownloadingTorrents` | True if any torrent downloading/checking |
| `listTorrentNames` | `"<id> <hashString> <name>"` per torrent |
| `getEncryptionMode` | Current encryption mode |

**Torrent (torrent.cc):**

| Method | Description |
|--------|-------------|
| `torrentAdd` | Add torrent. Return 0=OK, 1=PARSE_ERR, 2=DUPLICATE, 3=OK_DELETE. File ctor and magnet (BEP9) both flow through here |
| `torrentRemove` | Remove torrent (with/without local data) |
| `torrentStart` | Start torrent |
| `torrentStop` | Stop torrent |
| `torrentVerify` | Verify torrent data |
| `torrentListFilesFromFile` | List files from a `.torrent` file (no session) |
| `torrentListFiles` | List files from an active torrent |
| `torrentFindByHash` | Find torrent ID by 20-byte SHA-1 |
| `torrentGetName` | Get torrent name |
| `torrentGetHash` | Write 20-byte SHA hash into buffer |
| `torrentGetPieceHash` | Write specific piece hash into buffer |
| `torrentSetPiecesHiPri` | Set piece priority range (sequential download) |
| `torrentSetDnd` | Set do-not-download flag on files |
| `torrentFindFile` | Actual filesystem path for a downloaded file |
| `torrentGetFileName` | Logical file name within torrent |
| `torrentGetFileStat` | File stats + 64-bit piece availability bitfields |
| `torrentGetPiece` | Read a piece block from cache |
| `torrentStatBrief` | 10-field stat per torrent (see torrent management doc) |
| `torrentGetError` | Get torrent error string |
| `torrentState` | Current torrent state enum |
| `torrentSetLocation` | Move torrent data |
| `torrentReannounce` | Re-announce to trackers |

**Utilities:**

| Method | Module | Description |
|--------|--------|-------------|
| `hashBytesToString` | hash.cc | Bytes → hex string |
| `hashStringToBytes` | hash.cc | Hex string → bytes |
| `curlDownload` | curl.cc | Download URL to file via cURL. Throws on error |
| `envSet` | env.cc | Set POSIX environment variable |
| `nativeToArktsInit` | native_to_arkts.cc | Initialize the TSFN callback bridge |
| `nativeToArktsRelease` | native_to_arkts.cc | Release the TSFN callback bridge |

### 1.3 Callback Trampolines

Four callbacks are registered on the ArkTS side (targets of C→ArkTS callbacks):
- `torrentAddedOrChangedCallback()` → invokes the registered listener
- `torrentStoppedCallback()` → invokes the registered listener
- `sessionChangedCallback()` → invokes the registered listener
- `scheduledAltSpeedCallback()` → invokes the registered listener

They are invoked from the libtransmission event thread through a ThreadSafeFunction, which marshals the call onto the ArkTS main thread.

---

## 2. C++ Native Layer

### 2.1 commons.cc/h — N-API Utilities

**Error handling macros:**
- `throwEX(env, ...)` — format error → throw N-API exception → `goto CATCH`
- `throwIOEX(env, ...)` — shorthand for an input/output error
- `CATCH` — `__onException__` goto target

**`Err` struct**: `isSet (bool)` + `set (function pointer)` — for event-thread dispatched errors

**Thread dispatch** — `runInTransmissionThread()`:
1. Create `Future` struct with semaphore, function pointer, user data
2. `tr_runInEventThread(session, wrapper, &f)` — schedule on Transmission event thread
3. `sem_wait(f.sem)` — block calling thread until work completes
4. Check `f.err` — throw an ArkTS exception if set

### 2.2 transmission.cc — Session Lifecycle

**`sessionStart()`**:
1. `tr_variantInitDict(&settings)`
2. If loadConfig: `tr_sessionLoadSettings()`
3. Set defaults: `rename_partial_files=false`, `peer_port_random_on_start=true`
4. Apply config: download_dir, encryption, sequential, RPC (enabled/port/auth/whitelist)
5. Init formatters: mem (KiB/MiB/GiB/TiB), size (kB/MB/GB/TB), speed
6. `tr_sessionInit(configDir, true, &settings)` — creates session, starts DHT/PEX/LPD/port-mapping/µTP
7. `tr_sessionSaveSettings()`
8. Event thread: `tr_sessionSetPaused(false)`, register RPC + alt speed callbacks, `tr_sessionLoadTorrents()`
9. Return session as opaque pointer (BigInt)

**RPC Callback (`rpcFunc`):**
- `TR_RPC_TORRENT_ADDED` → if no metadata: register metadata callback → fall through → `callAddedOrChangedCallback()`
- `TR_RPC_TORRENT_STOPPED/REMOVING/TRASHING` → `callStoppedCallback()` + `callSessionChangedCallback()`
- `TR_RPC_SESSION_CHANGED` → `callSessionChangedCallback()`

**`sessionStop()`**: `tr_sessionGetSettings()` → `tr_sessionSaveSettings()` → `tr_sessionClose()`
**`sessionSuspend()`**: Dispatch to event thread → `tr_sessionSuspend()`

### 2.3 torrent.cc — Torrent Operations

| Function | Key Logic |
|----------|-----------|
| `torrentAdd()` | Create ctor from file (or magnet BEP9), `tr_torrentNew()`, handle duplicates + unwanted indexes. Returns 0=OK, 1=PARSE_ERR, 2=DUPLICATE, 3=OK_DELETE |
| `torrentStatBrief()` | Returns 10 longs per torrent: id, status(0=stopped/1=check/2=download/3=seed/4=error), progress%, totalLen, remainingLen, uploadedLen, peersUp, peersDown, speedUp, speedDown |
| `torrentGetFileStat()` | Returns: pieceSize, fileLength, fileOffset, firstPieceIdx, lastPieceIdx, fileComplete(0/1/2-dnd), + 64-bit piece bitfields |
| `torrentGetPiece()` | `tr_cacheReadBlock()` → raw bytes into an ArkTS byte buffer |
| `torrentSetPiecesHiPri()` | `TR_PRI_HIGH` on piece range, sets `isSequential=true`, triggers peer request rebuild |

### 2.4 native_to_arkts.cc — Callback Bridge

Caches ArkTS callback references during `nativeToArktsInit()`:

**4 callback functions**, delivered to ArkTS via ThreadSafeFunction:
- `torrentAddedOrChangedCallback()`
- `torrentStoppedCallback()`
- `sessionChangedCallback()`
- `scheduledAltSpeedCallback()`

**Note:** There is no storage-access bridge layer. v1.0 uses the app sandbox + raw POSIX I/O (`fopen`/`read`/`write`), so `tr_android_*` / `tr_oh_*` file hooks are NOT compiled into the Transmission fork. Only the callback bridge (TSFN) crosses the C→ArkTS boundary.

### 2.5 Other C++ Files

- **`hash.cc`**: `tr_binary_to_hex()` / `tr_hex_to_binary()` conversions, torrent hash extraction
- **`curl.cc`**: `curl_easy_perform()` with SSL verification disabled, user agent `"Transmission/<version>"`
- **`env.cc`**: `setenv(name, value, 1)` for proxy and SSL variables

---

## 3. Build System

### 3.1 Dependency Tree

```
libtransmissionbtm_napi.so (N-API)
  +-- 9 C++ source files (commons, torrent, transmission, native_to_arkts, hash, curl, env, napi_init)
  +-- libtransmission.a (Transmission 4.1.0 stable)
  |     +-- libdht.a, libb64.a, libnatpmp.a, libminiupnpc.a, libutp.a, libpsl.a, libMadlerCrcany.a
  +-- libcurl.a (8.5.0, HTTP/HTTPS/FTP only)
  +-- libevent.a (2.1.12-stable)
  +-- libssl.a + libcrypto.a (OpenSSL 3.0.15, heavily stripped)
  +-- hilog_ndk.z (OH logging)
```

### 3.2 Build Parameters

| Parameter | Value |
|-----------|-------|
| C++ Standard | gnu++17 |
| Exceptions | `-fno-exceptions` |
| RTTI | `-frtti` |
| Release | `-O3 -DNDEBUG -flto -fvisibility=hidden -fdata-sections -ffunction-sections` |
| Debug | `-g -O0` |
| ABI Target | arm64-v8a (OH musl toolchain) |

### 3.3 CMake ExternalProject Build Pipeline

1. **openssl**: Download → Configure for OH (no-idea, no-camellia, no-seed, no-bf, no-cast, no-rc2, no-md2, no-md4, no-mdc2, no-dsa, no-err, no-engine, no-tests, no-dso, no-dynamic-engine, no-stdio) → Build static
2. **curl** (depends openssl): Download → `--disable-shared --enable-static --disable-dict/gopher/imap/pop3/rtsp/smtp/telnet/tftp` → Build static
3. **libevent** (depends openssl): Download → CMake with `DISABLE_BENCHMARK/TESTS/SAMPLES=ON` → Build static
4. **transmission** (depends all above): Build from upstream 4.1.0 stable via `scripts/build-third-party.sh` → CMake with `-DENABLE_DAEMON/CLI/GTK/QT/MAC/UTILS/TESTS=OFF` → Build static. (4.1.0 has no `ENABLE_WEB` CMake option; the RPC/web server in `libtransmission/rpc-server.cc` compiles unconditionally — only `REBUILD_WEB`/`INSTALL_WEB` affect asset install.)

---

## 4. ArkTS Support Layer

| File | Purpose |
|------|---------|
| `models/TorrentInfo.ets` | Torrent domain model + computed progress/finished state |
| `models/TorrentFile.ets` | Per-file model (DnD, piece read/wait, stat) |
| `models/TorrentDir.ets` | Recursive directory model |
| `models/TorrentStat.ets` | 10-field stat parser |
| `models/TransmissionSession.ets` | Session-facing domain object (start/stop, addTorrent, suspend/resume) |
| `models/Preferences.ets` | Preference keys + typed getters/setters |
| `models/SessionConfig.ets` | Session start config (RPC, directories, encryption) |
| `services/ConnectivityMonitor.ets` | Network connectivity observer (WiFi-only / SSID gate) |
| `services/WakeLockManager.ets` | CPU + WiFi wake lock management |
| `services/SessionController.ets` | Session lifecycle controller in-process (replaces removed service) |
| `utils/format.ets` | Size/speed/ETA formatting |
| `utils/constants.ets` | Design tokens (Colors, FontSize, Spacing, Radius, Duration) |

---

## 5. Key Control Flows

### 5.1 App Startup → Native Init

```
EntryAbility.onCreate()/onWindowStageCreate()
→ NativeBridge.getInstance().init(context)
  → nativeToArktsInit()   [C++: cache napi_env + callback refs]
  → envSet(SSL_NO_VERIFY) [debug]
```

### 5.2 Torrent Add Flow

```
NativeBridge.torrentAdd(session, path, ...)
  → N-API → ctorFromFile(path) → tr_torrentNew()
  → Transmission fires TR_RPC_TORRENT_ADDED
  → rpcFunc() → callAddedOrChangedCallback()
  → TSFN → ArkTS main thread → DownloadsPage listener
```

---

## 6. N-API Patterns & HarmonyOS Equivalents

| N-API / C Concept | HarmonyOS Equivalent |
|---|---|
| `napi_module_register` (module init) | `entry/src/main/cpp/napi_init.cpp` |
| ThreadSafeFunction (cross-thread callback) | `napi_create_threadsafe_function` |
| `napi_create_reference` | Persistent reference for ArkTS callback fns |
| stdout/stderr → hilog | `OH_LOG_Print` / `%{private}s` |
| POSIX semaphores (sem_init/wait/post/destroy) | musl semaphores |
| `setenv`/`unsetenv` | musl `setenv`/`unsetenv` |
| Wake lock (CPU) | `@ohos.runningLock` |
| Wake lock (WiFi) | `@ohos.wifiManager` |
| File I/O | App sandbox, raw POSIX I/O |
| Key-value store | `@ohos.data.preferences` |
| ABI detection | `@ohos.system.DeviceInfo` |
| Obfuscation | Hvigor obfuscation |

---

## 7. Error Handling Patterns

**C++ error pattern**: `goto CATCH` with resource cleanup at label.
1. `throwEX`/`throwIOEX` macros format error → throw an N-API exception → `goto CATCH`
2. CATCH label: release string refs, array elements, free malloc'd memory, return sentinel
3. `Err` struct: for event-thread dispatched code — `setError()` allocates buffer, checked after `sem_wait()`

**ArkTS-side**: Callers catch typed exceptions around `NativeBridge` calls.

**Thread safety**: Torrent ops serialized through Transmission's single event thread via `runInTransmissionThread()`. Non-torrent ops (env, curl, hash) are called from the invoking thread without contention.
