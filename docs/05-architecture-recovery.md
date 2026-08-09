# 05 — Architecture Recovery (ArkTS Rewrite Edition)

## Overview

This document reconstructs the architecture of **transmissionbtc** (v1.3.10) and maps it to the target **transmissionhm** HarmonyOS architecture. The decision has been made to **discard all Java code** and rewrite the entire application layer in **ArkTS + ArkUI**, keeping only the C/C++ native layer (adapted via N-API).

### Rewrite Scope

| Layer | transmissionbtc | transmissionhm | Action |
|-------|----------------|----------------|--------|
| UI | Java + XML (DataBinding) | ArkUI declarative | **Rewrite** |
| Torrent Model | Java classes (Torrent, TorrentFile, etc.) | ArkTS classes | **Rewrite** |
| HTTP/UPnP/SSDP | Java (java.net.Socket) | ArkTS (reuse java.net on OH or @ohos.net) | **Rewrite/Adapt** |
| Service/Broadcast | Android Service + Receiver | OH Service + CommonEvent | **Rewrite** |
| Settings | SharedPreferences + DataBinding | @ohos.data.preferences + @State | **Rewrite** |
| JNI Bridge | Java Native.java + JNI | N-API module | **Rewrite** |
| Native C/C++ | 9 files, JNI functions | Same logic, N-API wrappers | **Adapt** |
| Third-party C libs | OpenSSL, curl, libevent, Transmission | Same, compiled for OH | **Preserve** |

---

## 1. New Architecture (ArkTS + N-API)

```
┌─────────────────────────────────────────────────────────────┐
│                    ArkTS APPLICATION LAYER                   │
│  ┌──────────────────────────────────────────────────────┐   │
│  │  ArkUI Pages & Components                             │   │
│  │  MainPage (Tabs: Downloads, Settings, Proxy, About)   │   │
│  │  TorrentListView, TorrentDetailView, AddTorrentSheet, │   │
│  │  FileTreeView, SettingsView, ProxyView                │   │
│  └────────────────────────┬─────────────────────────────┘   │
│  ┌────────────────────────┴─────────────────────────────┐   │
│  │  Domain Services (ArkTS singletons)                   │   │
│  │  ┌──────────────────────────────────────────────┐    │   │
│  │  │ TransmissionSession                           │    │   │
│  │  │ TorrentFs / Torrent / TorrentFile / TorrentDir│    │   │
│  │  │ TorrentStat / MediaInfo                       │    │   │
│  │  └──────────────────────────────────────────────┘    │   │
│  └────────────────────────┬─────────────────────────────┘   │
│  ┌────────────────────────┴─────────────────────────────┐   │
│  │  Platform Adapters                                    │   │
│  │  NotificationManager, WakeLockManager,                │   │
│  │  ConnectivityMonitor, PreferencesManager              │   │
│  └────────────────────────┬─────────────────────────────┘   │
├───────────────────────────┼─────────────────────────────────┤
│                    N-API BRIDGE LAYER                        │
│  ┌────────────────────────┴─────────────────────────────┐   │
│  │  native_bridge.cpp (N-API module)                     │   │
│  │  - 40 functions replacing Native.java methods         │   │
│  │  - ThreadSafeFunction for C→ArkTS callbacks           │   │
│  │  - module registration: napi_module_register()        │   │
│  └────────────────────────┬─────────────────────────────┘   │
├───────────────────────────┼─────────────────────────────────┤
│                  NATIVE LAYER (C/C++ Preserved)              │
│  ┌────────────────────────┴─────────────────────────────┐   │
│  │  Core C++ files (adapted from JNI → N-API):           │   │
│  │  commons.cc, transmission.cc, torrent.cc,             │   │
│  │  native_to_java.cc → native_to_arkts.cc,              │   │
│  │  hash.cc, sem.cc, curl.cc, env.cc, stdredirect.cc     │   │
│  │                                                        │   │
│  │  File I/O: Raw POSIX (fopen/read/write) in sandbox    │   │
│  │  No bidirectional N-API file bridge needed            │   │
│  │                                                        │   │
│  │  Third-Party Static Libraries:                         │   │
│  │  libtransmission.a (+dht, utp, natpmp, miniupnpc)     │   │
│  │  libcurl.a │ libevent.a │ libssl.a + libcrypto.a      │   │
│  └──────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
```

---

## 2. ArkTS Module Structure

```
entry/src/main/ets/
├── pages/
│   ├── MainPage.ets              -- Tabs container
│   ├── AddTorrentPage.ets        -- Add torrent flow
│   └── SelectFilePage.ets        -- File picker
├── components/
│   ├── torrent/
│   │   ├── TorrentListView.ets   -- Torrent list with live stats
│   │   ├── TorrentDetailView.ets -- Single torrent display
│   │   ├── FileTreeView.ets      -- Recursive file tree
│   │   └── TorrentContextMenu.ets -- Context actions
│   ├── settings/
│   │   ├── SettingsView.ets      -- Settings form
│   │   ├── ProxyView.ets         -- Proxy configuration
│   │   └── AboutView.ets         -- Version info
│   └── common/
│       ├── BrowsePathView.ets    -- Directory path with browse button
│       ├── CheckBoxSetting.ets   -- Labeled checkbox
│       └── ProgressBar.ets       -- Torrent progress bar
├── services/
│   └── TransmissionService.ets   -- OH foreground service
├── domain/
│   ├── TransmissionSession.ets   -- Session management
│   ├── TorrentFs.ets             -- Torrent registry
│   └── models/
│       ├── Torrent.ets
│       ├── TorrentFile.ets
│       ├── TorrentDir.ets
│       ├── TorrentStat.ets
│       └── MediaInfo.ets
├── platform/
│   ├── PreferencesManager.ets    -- Settings persistence
│   ├── NotificationHelper.ets    -- Foreground notification
│   ├── WakeLockManager.ets       -- CPU/WiFi locks
│   └── ConnectivityMonitor.ets   -- Network state watching
└── native/
    └── NativeBridge.ets          -- N-API wrapper class
```

---

## 3. Java → ArkTS Mapping (Key Classes)

### 3.1 Activity → Page

| Java (Android) | ArkTS (HarmonyOS) | Notes |
|----------------|-------------------|-------|
| `MainActivity` (314 lines) | `MainPage.ets` | Tabs + start/stop binding |
| `DownloadTorrentActivity` (349) | `AddTorrentPage.ets` | Full add flow as modal page |
| `OpenTorrentActivity` (134) | `AddTorrentPage.ets` (mode: "open") | Same page, different mode |
| `SelectFileActivity` (649) | `SelectFilePage.ets` | OH FilePicker dialog |
| `ActivityBase` (41) | Base page mixin | Native init + Prefs init |

### 3.2 Views → @Component

| Java (Android) | ArkTS (HarmonyOS) | Notes |
|----------------|-------------------|-------|
| `TorrentsList` (172) | `TorrentListView` | `List` + `ListItem` with `@State` data |
| `TorrentView` (695) | `TorrentDetailView` | Expandable card with Progress |
| `BrowseView` (172) | `BrowsePathView` | `Row` with Text + path input + browse icon |
| `WatchView` (37) | `WatchDirsListView` | `List` with add/remove |
| `WatchItemView` (66) | `WatchDirItem` | Reusable list item |
| `CheckBoxView` (62) | `CheckBoxSetting` | `Toggle` + label |
| `PageFragment` (86) | Not needed | ArkUI `Tabs` handles this natively |
| `TabInfo` (35) | `TabBarItem` data | Built into `Tabs` |

### 3.3 Domain Layer

| Java | ArkTS | Key Considerations |
|------|-------|-------------------|
| `Transmission.java` | `TransmissionSession.ets` | Session lifecycle, JNI→N-API calls |
| `TorrentFs.java` | `TorrentFs.ets` | Torrent registry, file system ops |
| `Torrent.java` (38 methods) | `Torrent.ets` | Class with N-API backed methods |
| `TorrentFile.java` (30+ methods) | `TorrentFile.ets` | Piece read/wait logic preserved |
| `TorrentDir.java` | `TorrentDir.ets` | Recursive DnD + completeness |
| `TorrentStat.java` | `TorrentStat.ets` | 10-field flat array parsing |
| `MediaInfo.java` | `MediaInfo.ets` | Media type detection |

### 3.4 HTTP/UPnP/SSDP Layer — 🚫 DEFERRED TO v1.1+

All HTTP server, streaming, UPnP/DLNA, and SSDP features are deferred to v1.1+. See `docs/06-feature-map-and-gap-analysis.md` §3-4.

### 3.5 Platform Adapters

| Java | ArkTS | OH API |
|------|-------|--------|
| `Prefs.java` (40+ keys) | `PreferencesManager.ets` | `@ohos.data.preferences` |
| `PowerLock.java` | `WakeLockManager.ets` | `@ohos.runningLock` + `@ohos.wifiManager` |
| `Native.java` (40 methods) | `NativeBridge.ets` (N-API wrapper) | `ace_napi.z` |
| `Scripts.java` | ✂️ Discarded | No root access on OH |
| `StorageAccess.java` (355) | ✂️ Not needed for v1.0 | POSIX I/O in sandbox. FileAccessHelper deferred to v1.1+ |
| `BindingHelper.java` | Not needed | ArkUI `@State` / `@Provide` |
| `Adapters.java` | Not needed | ArkUI built-in bindings |
| `TransmissionService.java` | `TransmissionService.ets` | `@ohos.app.Service` |
| `BootOrUpdateReceiver.java` | `StaticSubscriber` | `@ohos.app.StaticSubscriber` |
| `ConnectivityChangeReceiver.java` | `ConnectivityMonitor.ets` | `@ohos.net.connection` |
| `SelectFileActivity (SAF)` | `SelectFilePage` + FilePicker | `@ohos.file.picker` |

### 3.6 Discarded (No OH Equivalent or Not Needed)

| Java Class | Reason for Discard |
|------------|-------------------|
| `Scripts.java` + `set_so_buf.sh` | No root access on HarmonyOS |
| `BindingHelper.java` | Replaced by ArkUI state management |
| `Adapters.java` (DataBinding) | Replaced by ArkUI `@BuilderParam` / `@State` |
| `Baos.java` | Use `Uint8Array` or equivalent |
| `CompletedFuture.java` | Use standard `Promise` |
| `func/Consumer.java` etc. | ArkTS has native callbacks/lambdas |
| `Localizable.java` | Use OH `$r()` resource system |
| `NaturalOrderComparator.java` | Rewrite as ArkTS utility function |
| `Utils.java` (861 lines) | Split: network → `@ohos.net`, file → `@ohos.file.fs`, XML→`@ohos.xml` |

---

## 4. N-API Bridge Architecture

### 4.1 JNI → N-API Function Mapping

The 40 JNI functions in `Native.java` become N-API exported functions:

```cpp
// JNI style (old):
JNIEXPORT jstring JNICALL Java_com_ap_transmission_btc_Native_transmissionVersion(JNIEnv*, jclass)

// N-API style (new):
static napi_value TransmissionVersion(napi_env env, napi_callback_info info)

// Module registration:
NAPI_MODULE(transmissionbtc, Init)
```

### 4.2 C→ArkTS Callback Pattern

```cpp
// Old: JNI
// Cache method ID: env->GetStaticMethodID(classNative, "torrentAddedOrChangedCallback", "()V")
// Call: env->CallStaticVoidMethod(classNative, addedOrChangedCallback)

// New: N-API ThreadSafeFunction
napi_value tsfn;
napi_create_threadsafe_function(
    env, callback, nullptr, resource_name,
    0, 1, nullptr, nullptr, nullptr,
    CallJsCallback, &tsfn
);

// Call from any thread:
napi_call_threadsafe_function(tsfn, nullptr, napi_tsfn_blocking);
```

### 4.3 Storage: POSIX I/O in App Sandbox (v1.0 Simplification)

For v1.0, all downloads are restricted to the app sandbox directory. libtransmission uses raw POSIX I/O (`fopen`/`read`/`write`/`rename`/`unlink`) directly — **no** `tr_android_*` / `tr_oh_*` hooks are compiled in. The Transmission fork is built without the SAF patch.

```cpp
// v1.0: libtransmission calls standard POSIX directly
FILE* f = fopen("/data/storage/el2/base/haps/entry/files/downloads/...", "rb");
// No N-API round-trip needed

// v1.1+: add tr_oh_file_open → N-API ThreadSafeFunction → FileAccessHelper
// for external storage (SD card) support
```

This eliminates the entire `native_to_arkts.cc` storage bridge (~170 lines) and `StorageAccessAdapter.ets` (~355 lines Android → ArkTS).

---

## 5. Data Flow (ArkTS Rewrite)

### 5.1 App Startup

```
MainPage.aboutToAppear()
  → NativeBridge.init()        // N-API: cache callbacks, env vars, stdRedirect
  → PreferencesManager.init()  // Load preferences
  → Check permissions
```

### 5.2 Start Transmission

```
User taps "Start"
  → TransmissionService.startService()
    → startForeground() + notification
    → TransmissionSession.start()
      → copyWebAssets() → NativeBridge.setEnv()
      → NativeBridge.transmissionStart(configDir, downloadsDir, ...)
        → N-API → C++: tr_sessionInit() + load torrents (POSIX I/O)
      → ConnectivityMonitor.register()
      → WakeLockManager.acquire()
```

### 5.3 Torrent Add

```
AddTorrentPage: user selects file + files → taps "Download"
  → TransmissionSession.addTorrent(path, downloadDir, ...)
    → NativeBridge.torrentAdd(session, path, ...)
      → N-API → C++: tr_torrentNew()
    → [Transmission event]
      → N-API ThreadSafeFunction callback → ArkTS
        → @State update → TorrentListView re-renders
```

### 5.4 Media Playback (v1.0: Complete Files Only)

```
Media Player: opens file via URI
  → TorrentFs.findTorrent(hash).getFile(idx)
  → If complete: open file directly via POSIX path → play
  → If incomplete: show "download in progress" (streaming deferred to v1.1+)
```

> HTTP streaming for incomplete files (`tr_cacheReadBlock`) is deferred to v1.1+.

---

## 6. State Management Architecture

```
@Provide('transmissionState') state: TransmissionState
  ├─ isRunning: boolean
  ├─ isSuspended: boolean
  ├─ torrents: Torrent[]
  └─ stats: TorrentStat[]

@Provide('preferences') prefs: PreferencesManager
  ├─ All 40+ settings as reactive properties

@Provide('serviceControl') service: ServiceController
  ├─ start() / stop() / suspend() / resume()

// Consumers:
@Consume('transmissionState') state: TransmissionState  // In TorrentListView
@Consume('preferences') prefs: PreferencesManager       // In SettingsView
```

---

## 7. Key Design Decisions

| Decision | Rationale |
|----------|-----------|
| **Discard all Java** | No JVM on HarmonyOS — ArkTS is the native language |
| **Preserve C/C++ layer** | libtransmission is the core engine — rewrite would take months |
| **N-API over direct FFI** | Type-safe, supported by OH, matches JNI pattern |
| **ArkUI @State over DataBinding** | OH native pattern for reactive UI |
| **POSIX I/O in sandbox (v1.0)** | Avoids entire bidirectional N-API file bridge. External storage (FileAccessHelper) deferred to v1.1+ |
| **No HTTP streaming server (v1.0)** | "Play while downloading" deferred. Complete files played via file URI |
| **@ohos.taskpool for async** | OH equivalent of AsyncTask/ExecutorService |
| **java.net.* reuse for HTTP** | java.net is available on OH via standard library (used for RPC client only in v1.0) |

---

## 8. Platform API Summary

| Concern | Android (transmissionbtc) | HarmonyOS (transmissionhm) |
|---------|--------------------------|---------------------------|
| Language | Java + Kotlin (compatible) | ArkTS |
| UI Framework | XML + DataBinding + AppCompat | ArkUI declarative |
| Native Bridge | JNI | N-API |
| Preferences | SharedPreferences | @ohos.data.preferences |
| File I/O | SAF (DocumentFile + ContentResolver) | POSIX in sandbox (v1.0). FileAccessHelper deferred to v1.1+ |
| HTTP Server | Custom (java.net.Socket) | 🚫 Deferred to v1.1+ |
| Networking | java.net (built-in) | java.net (available) or @ohos.net.socket |
| Service | Android Service (foreground) | @ohos.app.Service |
| Notifications | NotificationManager + Channel | @ohos.notification |
| Background Work | AsyncTask + ExecutorService | @ohos.taskpool |
| System Events | BroadcastReceiver | CommonEvent / StaticSubscriber |
| Wake Locks | PowerManager + WifiManager | @ohos.runningLock + @ohos.wifiManager |
| XML Parsing | javax.xml.parsers | @ohos.xml or javax (available) |
| Resources | AssetManager + res/* | @ohos.resourceManager + resources/ |
| Build System | Gradle + CMake | Hvigor + CMake |
