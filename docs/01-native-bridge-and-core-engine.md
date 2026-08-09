# 01 — Native Bridge & Core Engine

## Overview

This domain is the foundational layer of the transmissionbtc Android BitTorrent client. It bridges the JVM (Dalvik/ART) world with the native C Transmission daemon via the Java Native Interface (JNI). It encompasses all native method declarations in Java, the C++ implementation of every JNI function, Transmission session lifecycle management, torrent CRUD operations, C-to-Java callback bridges, file I/O delegation from C back to Java (SAF-based), a custom CMake-based build system, and synchronization primitives.

The entire architecture is designed around the constraint that Android's Storage Access Framework (SAF) requires the C I/O layer to call back into Java for file operations, creating a bidirectional JNI dependency.

---

## File Inventory

| File | Lines | Purpose |
|------|-------|---------|
| `Native.java` | 264 | All native method declarations (40 methods), library loading, callback trampolines |
| `Scripts.java` | 68 | Shell script execution via `su` (root) for privileged operations |
| `Baos.java` | 20 | ByteArrayOutputStream subclass exposing internal buffer |
| `CompletedFuture.java` | 41 | Pre-completed Future implementation |
| `EncrMode.java` | 23 | Encryption mode enum (Allow/Prefer/Require) |
| `Utils.java` | 861 | Utility methods (network, file I/O, XML, shell exec, proxy config) |
| `PowerLock.java` | 59 | CPU + WiFi wake lock management |
| `StorageAccess.java` | 355 | SAF-based file I/O, called from C via JNI |
| `Localizable.java` | 9 | Interface for localized string resources |
| `func/Consumer.java` | 8 | Functional interface: `void accept(T)` |
| `func/Function.java` | 9 | Functional interface: `R apply(T)` |
| `func/Supplier.java` | 8 | Functional interface: `T get()` |
| `func/Promise.java` | 25 | Cancellable promise with inner `Completed<T>` |
| `cpp/commons.cc` | 201 | Shared JNI utility functions, error handling, Future pattern |
| `cpp/commons.h` | 80 | Macros, types, function declarations |
| `cpp/native_to_java.cc` | 170 | C-to-Java callback bridge + storage access wrappers |
| `cpp/native_to_java.h` | 18 | Header for callback functions |
| `cpp/transmission.cc` | 305 | Transmission session lifecycle JNI functions |
| `cpp/transmission-private.h` | 18 | Internal header |
| `cpp/torrent.cc` | 903 | All torrent-related JNI functions |
| `cpp/hash.cc` | 45 | Torrent hash conversion utilities |
| `cpp/sem.cc` | 37 | POSIX semaphore exposed to Java |
| `cpp/curl.cc` | 54 | cURL-based HTTP download wrapper |
| `cpp/env.cc` | 25 | Environment variable set/unset |
| `cpp/stdredirect.cc` | 48 | stdout/stderr to Android logcat redirection |
| `CMakeLists.txt` | 75 | Top-level CMake build definition |
| `cmake/OpenSSL.cmake` | 48 | OpenSSL 1.1.1l ExternalProject build |
| `cmake/cURL.cmake` | 28 | cURL 7.78.0 ExternalProject build |
| `cmake/Event.cmake` | 27 | libevent 2.1.12 ExternalProject build |
| `cmake/Transmission.cmake` | 39 | Transmission (fork) ExternalProject build |
| `build.gradle` | 162 | Android Gradle build with CMake integration |

---

## 1. JNI Bridge (Native.java)

### 1.1 Library Loading

```java
static { Init.init(null); }
```

`Init.init(Context ctx)` flow:
1. Calls `StorageAccess.init(ctx)` — sets up app context and `pathToUrlMappings` SharedPreferences
2. Attempts `System.loadLibrary("transmissionbtc")` — standard Android native library load
3. On `UnsatisfiedLinkError`: extracts `.so` from APK zip to `{dataDir}/lib/` and uses `System.load()`
4. Calls `initNativeContext()`:
   - `nativeToJavaInit()` — C++ side stores JVM references and method IDs
   - `envSet("TR_CURL_SSL_NO_VERIFY", "true")` + `envSet("TR_CURL_PROXY_SSL_NO_VERIFY", "true")`
   - (debug) `stdRedirect()` — pipe stdout/stderr to logcat

### 1.2 Complete Native Method Catalog (40 methods)

| # | Method | Return | Parameters | Description |
|---|--------|--------|-----------|-------------|
| 1 | `transmissionVersion` | `String` | — | Transmission `SHORT_VERSION_STRING` |
| 2 | `transmissionStart` | `long`  | `configDir, downloadsDir, encrMode, enableRpc, rpcPort, enableAuth, username, password, enableRpcWhitelist, rpcWhitelist, loadConfig, enableSequential, paused` | Init session. Returns opaque session ptr. Throws IOException |
| 3 | `transmissionStop` | `void` | `session, configDir` | Save settings + close session |
| 4 | `transmissionSuspend` | `void` | `session, suspend` | Suspend/resume session |
| 5 | `transmissionHasDownloadingTorrents` | `boolean` | `session` | True if any torrent downloading/checking |
| 6 | `transmissionListTorrentNames` | `String[]` | `session` | `"<id> <hashString> <name>"` per torrent |
| 7 | `transmissionGetEncryptionMode` | `int` | `session` | Current encryption mode |
| 8 | `torrentAdd` | `int` | `session, path, downloadDir, delete, sequential, unwantedIndexes[], returnMeTorrentHash[]` | 0=OK, 1=PARSE_ERR, 2=DUPLICATE, 3=OK_DELETE |
| 9 | `torrentRemove` | `void` | `session, torrentId, removeLocalData` | Remove torrent |
| 10 | `torrentStop` | `void` | `session, torrentId` | Stop torrent |
| 11 | `torrentStart` | `void` | `session, torrentId` | Start torrent |
| 12 | `torrentVerify` | `void` | `session, torrentId` | Verify torrent data |
| 13 | `torrentListFilesFromFile` | `String[]` | `torrent` | List files from .torrent file (no session) |
| 14 | `torrentListFiles` | `String[]` | `session, torrentId` | List files from active torrent |
| 15 | `torrentMagnetToTorrentFile` | `void` | `session, sem, magnet, path, timeout, enqueue[]` | Resolve magnet to .torrent |
| 16 | `torrentFindByHash` | `int` | `session, torrentHash[]` | Find torrent ID by 20-byte SHA-1 |
| 17 | `torrentSetPiecesHiPri` | `void` | `session, torrentId, firstPiece, lastPiece` | Set piece priority range (sequential download) |
| 18 | `torrentGetName` | `String` | `session, torrentId` | Get torrent name |
| 19 | `torrentGetHash` | `void` | `session, torrentId, torrentHash[]` | Write 20-byte SHA hash into buffer |
| 20 | `torrentGetPieceHash` | `void` | `session, torrentId, piece, pieceHash[]` | Write specific piece hash into buffer |
| 21 | `torrentSetDnd` | `void` | `session, torrentId, files[], dnd` | Set do-not-download flag on files |
| 22 | `torrentFindFile` | `String` | `session, torrentId, fileIndex` | Actual filesystem path for downloaded file |
| 23 | `torrentGetFileName` | `String` | `session, torrentId, fileIndex` | Logical file name within torrent |
| 24 | `torrentGetFileStat` | `long[]` | `session, torrentId, fileIndex, stat[]` | File stats + 64-bit piece availability bitfields |
| 25 | `torrentGetPiece` | `void` | `session, torrentId, pieceIndex, dst[], offset, len` | Read piece block from cache |
| 26 | `torrentSetLocation` | `void` | `session, torrentId, path` | Move torrent data |
| 27 | `torrentStatBrief` | `long[]` | `session, stat[]` | 10-field stat per torrent (see torrent management doc) |
| 28 | `torrentGetError` | `String` | `session, torrentId` | Get torrent error string |
| 29 | `envSet` | `void` | `name, value` | Set POSIX environment variable |
| 30 | `envUnset` | `void` | `name` | Unset POSIX environment variable |
| 31 | `semCreate` | `long` | — | Create POSIX semaphore |
| 32 | `semDestroy` | `void` | `sem` | Destroy POSIX semaphore |
| 33 | `semPost` | `void` | `sem` | Post (increment) POSIX semaphore |
| 34 | `stdRedirect` | `void` | — | Redirect stdout/stderr to logcat |
| 35 | `curl` | `void` | `url, dst, timeout` | Download URL to file via cURL. Throws IOException |
| 36 | `hashLength` | `int` | — | `SHA_DIGEST_LENGTH` (20) |
| 37 | `hashBytesToString` | `String` | `hash[]` | Bytes → hex string |
| 38 | `hashStringToBytes` | `byte[]` | `hashString` | Hex string → bytes |
| 39 | `hashGetTorrentHash` | `byte[]` | `torrentPath` | SHA-1 hash from .torrent file |
| 40 | `nativeToJavaInit` | `void` | — | Initialize JNI callback bridge |

### 1.3 Callback Trampolines

Four `@Keep` annotated static methods (targets for C→Java callbacks):
- `torrentAddedOrChangedCallback()` → invokes volatile Runnable
- `torrentStoppedCallback()` → invokes volatile Runnable
- `sessionChangedCallback()` → invokes volatile Runnable
- `scheduledAltSpeedCallback()` → invokes volatile Runnable

---

## 2. C++ Native Layer

### 2.1 commons.cc/h — JNI Utilities

**Error handling macros:**
- `throwEX(env, className, ...)` — format error → `env->ThrowNew()` → `goto CATCH`
- `throwIOEX(env, ...)` — shorthand for IOException
- `CATCH` — `__onException__` goto target

**`Err` struct**: `isSet (bool)` + `set (function pointer)` — for event-thread dispatched errors

**Thread dispatch** — `runInTransmissionThread()`:
1. Create `Future` struct with semaphore, function pointer, user data
2. `tr_runInEventThread(session, wrapper, &f)` — schedule on Transmission event thread
3. `sem_wait(f.sem)` — block calling thread until work completes
4. Check `f.err` — throw Java exception if set

### 2.2 transmission.cc — Session Lifecycle

**`transmissionStart()`** (305 lines, line 108):
1. `tr_variantInitDict(&settings)`
2. If loadConfig: `tr_sessionLoadSettings()`
3. Set defaults: `rename_partial_files=false`, `peer_port_random_on_start=true`
4. Apply config: download_dir, encryption, sequential, RPC (enabled/port/auth/whitelist)
5. Init formatters: mem (KiB/MiB/GiB/TiB), size (kB/MB/GB/TB), speed
6. `tr_sessionInit(configDir, true, &settings)` — creates session, starts DHT/PEX/LPD/port-mapping/µTP
7. `tr_sessionSaveSettings()`
8. Event thread: `tr_sessionSetPaused(false)`, register RPC + alt speed callbacks, `tr_sessionLoadTorrents()`
9. Return session as `jlong`

**RPC Callback (`rpcFunc`):**
- `TR_RPC_TORRENT_ADDED` → if no metadata: register metadata callback → fall through → `callAddedOrChangedCallback()`
- `TR_RPC_TORRENT_STOPPED/REMOVING/TRASHING` → `callStoppedCallback()` + `callSessionChangedCallback()`
- `TR_RPC_SESSION_CHANGED` → `callSessionChangedCallback()`

**`transmissionStop()`**: `tr_sessionGetSettings()` → `tr_sessionSaveSettings()` → `tr_sessionClose()`
**`transmissionSuspend()`**: Dispatch to event thread → `tr_sessionSuspend()`

### 2.3 torrent.cc — Torrent Operations (903 lines)

| Function | Key Logic |
|----------|-----------|
| `torrentAdd()` | Create ctor from file, `tr_torrentNew()`, handle duplicates + unwanted indexes. Returns 0=OK, 1=PARSE_ERR, 2=DUPLICATE, 3=OK_DELETE |
| `torrentMagnetToTorrentFile()` | Create ctor from magnet, add torrent, `sem_timedwait()` for metadata callback, copy .torrent to path |
| `torrentStatBrief()` | Returns 10 longs per torrent: id, status(0=stopped/1=check/2=download/3=seed/4=error), progress%, totalLen, remainingLen, uploadedLen, peersUp, peersDown, speedUp, speedDown |
| `torrentGetFileStat()` | Returns: pieceSize, fileLength, fileOffset, firstPieceIdx, lastPieceIdx, fileComplete(0/1/2-dnd), + 64-bit piece bitfields |
| `torrentGetPiece()` | `tr_cacheReadBlock()` → raw bytes into Java byte[] |
| `torrentSetPiecesHiPri()` | `TR_PRI_HIGH` on piece range, sets `isSequential=true`, triggers peer request rebuild |

### 2.4 native_to_java.cc — Callback Bridge

Caches 9 JNI method IDs during `nativeToJavaInit()`:

**4 callback methods** on `com.ap.transmission.btc.Native`:
- `torrentAddedOrChangedCallback()V`
- `torrentStoppedCallback()V`
- `sessionChangedCallback()V`
- `scheduledAltSpeedCallback()V`

**5 StorageAccess methods** on `com.ap.transmission.btc.StorageAccess`:
- `createDir(String)Z`
- `openFile(String,boolean,boolean,boolean)I` → returns fd
- `closeFileDescriptor(I)Z`
- `renamePath(String,String)Z`
- `removePath(String)Z`

**`tr_android_*` functions** (patched into libtransmission to replace POSIX I/O):
- `tr_android_dir_create` → `StorageAccess.createDir()`
- `tr_android_file_open` → `StorageAccess.openFile()` with SAF flags
- `tr_android_file_open_temp` → retry up to 100 times with random suffix
- `tr_android_file_close` → `StorageAccess.closeFileDescriptor()`
- `tr_android_path_rename` → `StorageAccess.renamePath()` (copy+delete for cross-filesystem moves)
- `tr_android_path_remove` → `StorageAccess.removePath()`

### 2.5 Other C++ Files

- **`hash.cc`**: `tr_binary_to_hex()` / `tr_hex_to_binary()` conversions, torrent hash extraction
- **`sem.cc`**: `sem_init(0)`, `sem_destroy()`, `sem_post()` — Java never calls `sem_wait` directly
- **`curl.cc`**: `curl_easy_perform()` with SSL verification disabled, user agent `"Transmission/<version>"`
- **`env.cc`**: `setenv(name, value, 1)` / `unsetenv(name)` for proxy and SSL variables
- **`stdredirect.cc`**: (Debug only) `dup2(pfd[1], 1)`, `dup2(pfd[1], 2)`, detached pthread reads pipe → `__android_log_write(ANDROID_LOG_DEBUG, "libtransmission", buf)`

---

## 3. Build System

### 3.1 Dependency Tree

```
libtransmissionbtc.so (shared, JNI)
  +-- 9 C++ source files (commons, torrent, transmission, native_to_java, hash, sem, curl, env, stdredirect)
  +-- libtransmission.a (Transmission fork, tag: transmissionbtc)
  |     +-- libdht.a, libarc4.a, libb64.a, libnatpmp.a, libminiupnpc.a, libutp.a
  +-- libcurl.a (7.78.0, HTTP/HTTPS/FTP only)
  +-- libevent.a (2.1.12-stable)
  +-- libssl.a + libcrypto.a (OpenSSL 1.1.1l, heavily stripped)
  +-- liblog.so (Android NDK) + libz.so (Android NDK)
```

### 3.2 Build Parameters

| Parameter | Value |
|-----------|-------|
| C++ Standard | gnu++17 |
| Exceptions | `-fno-exceptions` |
| RTTI | `-frtti` |
| Release | `-O3 -DNDEBUG -flto -fvisibility=hidden -fdata-sections -ffunction-sections` |
| Debug | `-g -O0` |
| ABI Targets | arm64-v8a, armeabi-v7a, x86, x86_64 |
| minSdk | 19 (Android 4.4) |
| targetSdk | 30 (Android 11) |
| AGP | 4.2.2 |

### 3.3 CMake ExternalProject Build Pipeline

1. **openssl**: Download → `Configure android-<arch> --static` with extensive feature disables (no-idea, no-camellia, no-seed, no-bf, no-cast, no-rc2, no-md2, no-md4, no-mdc2, no-dsa, no-err, no-engine, no-tests, no-dso, no-dynamic-engine, no-stdio) → Build static
2. **curl** (depends openssl): Download → `--disable-shared --enable-static --disable-dict/gopher/imap/pop3/rtsp/smtp/telnet/tftp` → Build static
3. **libevent** (depends openssl): Download → CMake with `DISABLE_BENCHMARK/TESTS/SAMPLES=ON` → Build static
4. **transmission** (depends all above): Git clone fork → CMake with `-DENABLE_DAEMON/CLI/GTK/QT/MAC/UTILS/TESTS=OFF -DENABLE_WEB=ON` → Build static

---

## 4. Supporting Java Classes

| Class | Lines | Purpose |
|-------|-------|---------|
| `Scripts.java` | 68 | Root shell script execution. Copies scripts from assets, runs via `su -c`. Enum: set_so_buf, create_dir, create_file |
| `PowerLock.java` | 59 | `PowerManager.PARTIAL_WAKE_LOCK` + `WifiManager.WIFI_MODE_FULL`. `acquire()`/`release()` |
| `EncrMode.java` | 23 | Allow(0), Prefer(1), Require(2). Implements `Localizable` |
| `Consumer<T>` | 8 | `void accept(T t)` |
| `Function<T,R>` | 9 | `R apply(T t)` |
| `Supplier<T>` | 8 | `T get()` |
| `Promise<T>` | 25 | `T get() throws Throwable` + `cancel()`. Inner `Completed<T>` |
| `Baos.java` | 20 | Exposes `buf` directly, `byteBuf()` for ByteBuffer wrapping |
| `CompletedFuture.java` | 41 | Always-done Future |
| `StorageAccess.java` | 355 | SAF-based file I/O, `pathToUrlMappings` SP, `SparseArray<ParcelFileDescriptor>` |

---

## 5. Key Control Flows

### 5.1 App Startup → Native Init

```
Application.onCreate()
→ Native.Init.init(context)
  → StorageAccess.init(ctx)
  → System.loadLibrary("transmissionbtc") [or extract from APK]
  → nativeToJavaInit()  [C++: cache JavaVM + method IDs]
  → envSet(SSL_NO_VERIFY) + stdRedirect() [debug]
```

### 5.2 Torrent Add Flow

```
Native.torrentAdd(session, path, ...)
  → JNI → ctorFromFile(path) → tr_torrentNew()
  → Transmission fires TR_RPC_TORRENT_ADDED
  → rpcFunc() → callAddedOrChangedCallback()
  → JvmAttach → CallStaticVoidMethod(Native.callback) → JvmDetach
  → volatile Runnable field → TorrentsList.update()
```

---

## 6. Platform-Specific API → HarmonyOS Mapping

| Android API | Usage | HarmonyOS Equivalent |
|---|---|---|
| `JNI` / `System.loadLibrary` | Native bridge | N-API via `ace_napi.z` / `napi_module_register` |
| `JavaVM->AttachCurrentThread` | Thread attach for callbacks | N-API thread-safe functions |
| `NewGlobalRef` (JNI) | Persistent method refs | `napi_create_reference` |
| `__android_log_write` | Log to logcat | `OH_LOG_Print` (hilog) |
| `pthread_create/detach` | Debug threading | Standard pthread (musl) |
| `sem_init/wait/post/destroy` | Synchronization | `ohos_sem` or musl semaphores |
| `setenv/unsetenv` | Env vars | musl `setenv`/`unsetenv` |
| `PowerManager.WakeLock` | CPU wake lock | `@ohos.runningLock` |
| `WifiManager.WifiLock` | WiFi lock | `@ohos.wifiManager` |
| `DocumentFile` (SAF) | File I/O | `@ohos.file.fileaccess` / `FileAccessHelper` |
| `ContentResolver` | Content URIs | `FileAccessHelper` |
| `SharedPreferences` | Key-value store | `@ohos.data.preferences` |
| `Build.SUPPORTED_ABIS` | ABI detection | `@ohos.system.DeviceInfo` |
| `ProGuard` | Obfuscation | Hvigor obfuscation |

---

## 7. Error Handling Patterns

**C++ error pattern**: `goto CATCH` with resource cleanup at label.
1. `throwEX`/`throwIOEX` macros format error → find Java exception class → `env->ThrowNew()` → `goto CATCH`
2. CATCH label: release JNI string refs, array elements, free malloc'd memory, return sentinel
3. `Err` struct: for event-thread dispatched code — `setError()` allocates buffer, checked after `sem_wait()`

**Java-side**: Callers catch `IOException`, `NoSuchTorrentException`, `DuplicateTorrentException`.

**Thread safety**: Torrent ops serialized through Transmission's single event thread via `runInTransmissionThread()`. Non-torrent ops (env, sem, curl, hash) assumed called from appropriate threads without contention.
