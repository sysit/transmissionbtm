# 08 — Java → ArkTS Mapping Guide

## Overview

This document provides a class-by-class mapping from **transmissionbtc** Java source to the target **transmissionhm** ArkTS implementation. Every Java class is accounted for: rewritten, discarded, or replaced by OH platform APIs.

**Legend:**
- ✍️ **Rewrite** — Logic ported to ArkTS
- 🗑️ **Discard** — No equivalent needed
- 🔌 **OH API** — Replaced by HarmonyOS platform API
- 🔧 **Adapt** — Native C++ code, adapted from JNI to N-API

---

## 1. Complete Class Inventory (65 Java Files)

### 1.1 Root Package (`com.ap.transmission.btc`)

| Java File | Lines | Action | ArkTS Target | Notes |
|-----------|-------|--------|-------------|-------|
| `Native.java` | 264 | ✍️ | `native/NativeBridge.ets` | 40 N-API calls + ThreadSafeFunction for callbacks |
| `Prefs.java` | 619 | ✍️ | `platform/PreferencesManager.ets` | All 40+ keys preserved, OH preferences API |
| `StorageAccess.java` | 355 | ✍️ | `platform/StorageAccessAdapter.ets` | SAF→OH FileAccess, path→URI→path mapping |
| `Utils.java` | 861 | ✍️/🗑️ | Split into multiple modules | Network→`@ohos.net`, File→`@ohos.file.fs`, XML→`@ohos.xml` |
| `Scripts.java` | 68 | 🗑️ | — | No root access on OH |
| `PowerLock.java` | 59 | ✍️ | `platform/WakeLockManager.ets` | CPU+WiFi locks via OH APIs |
| `BindingHelper.java` | 136 | 🗑️ | — | Replaced by `@State`/`@Provide`/`@Consume` |
| `Adapters.java` | 194 | 🗑️ | — | Replaced by ArkUI built-in bindings |
| `EncrMode.java` | 23 | ✍️ | `domain/models/EncrMode.ets` | Enum: Allow/Prefer/Require |
| `Localizable.java` | 9 | 🗑️ | — | Use OH `$r()` |
| `NaturalOrderComparator.java` | — | ✍️ | `utils/NaturalOrderComparator.ets` | Utility function |
| `CompletedFuture.java` | 41 | 🗑️ | — | Use native `Promise<T>` |
| `Baos.java` | 20 | 🗑️ | — | Use `Uint8Array` / `ArrayBuffer` |
| `func/Consumer.java` | 8 | 🗑️ | — | ArkTS lambdas |
| `func/Function.java` | 9 | 🗑️ | — | ArkTS lambdas |
| `func/Supplier.java` | 8 | 🗑️ | — | ArkTS lambdas |
| `func/Promise.java` | 25 | 🗑️ | — | Use native `Promise<T>` |

### 1.2 Activities (`activities/`)

| Java File | Lines | Action | ArkTS Target | Notes |
|-----------|-------|--------|-------------|-------|
| `ActivityBase.java` | 41 | ✍️ | `pages/BasePage.ets` (mixin) | Native init + Prefs init |
| `MainActivity.java` | 314 | ✍️ | `pages/MainPage.ets` | Tabs, start/stop, add file/link, permissions |
| `DownloadTorrentActivity.java` | 349 | ✍️ | `pages/AddTorrentPage.ets` | URI handling, file selection, magnet+HTTP resolve |
| `OpenTorrentActivity.java` | 134 | ✍️ | `pages/AddTorrentPage.ets` (mode param) | Sequential download + auto-open |
| `SelectFileActivity.java` | 649 | ✍️/🔌 | `pages/SelectFilePage.ets` + OH FilePicker | Storage root discovery replaced by OH APIs |
| `ActivityResultHandler.java` | 10 | 🗑️ | — | ArkUI navigation/callbacks |

### 1.3 Service & Receivers (`services/`, `receivers/`)

| Java File | Lines | Action | ArkTS Target | Notes |
|-----------|-------|--------|-------------|-------|
| `TransmissionService.java` | 257 | ✍️ | `services/TransmissionService.ets` | OH foreground service |
| `BootOrUpdateReceiver.java` | 52 | ✍️ | `platform/BootStartManager.ets` | OH StaticSubscriber |
| `ConnectivityChangeReceiver.java` | 44 | ✍️ | `platform/ConnectivityMonitor.ets` | OH net observer |

### 1.4 Torrent Domain (`torrent/`)

| Java File | Lines | Action | ArkTS Target | Notes |
|-----------|-------|--------|-------------|-------|
| `Transmission.java` | ~500 | ✍️ | `domain/TransmissionSession.ets` | Session lifecycle, add/remove/control torrents |
| `TorrentFs.java` | ~200 | ✍️ | `domain/TorrentFs.ets` | Torrent registry, fs listing |
| `Torrent.java` | ~400 | ✍️ | `domain/models/Torrent.ets` | 38 methods, 10 fields |
| `TorrentFile.java` | ~400 | ✍️ | `domain/models/TorrentFile.ets` | 30+ methods, piece read/wait logic |
| `TorrentDir.java` | ~150 | ✍️ | `domain/models/TorrentDir.ets` | Recursive DnD/completeness ops |
| `TorrentItem.java` | ~30 | ✍️ | `domain/models/TorrentItem.ets` | Interface |
| `TorrentItemContainer.java` | ~20 | ✍️ | `domain/models/TorrentItemContainer.ets` | Interface with `ls()` |
| `TorrentStat.java` | ~80 | ✍️ | `domain/models/TorrentStat.ets` | 10-field flat array parsing |
| `MediaInfo.java` | ~100 | ✍️ | `domain/models/MediaInfo.ets` | Media type detection, metadata |
| `DuplicateTorrentException.java` | ~10 | ✍️ | `domain/models/TorrentExceptions.ets` | Custom Error subclass |
| `NoSuchTorrentException.java` | ~10 | ✍️ | `domain/models/TorrentExceptions.ets` | Custom Error subclass |
| `TorrentException.java` | ~10 | ✍️ | `domain/models/TorrentExceptions.ets` | Base Error subclass |

### 1.5 HTTP Server (`http/`)

| Java File | Lines | Action | ArkTS Target | Notes |
|-----------|-------|--------|-------------|-------|
| `HttpServer.java` | 26 | ✍️ | `domain/http/HttpServer.ets` | Interface |
| `SimpleHttpServer.java` | 249 | ✍️ | `domain/http/SimpleHttpServer.ets` | Core server, possible java.net reuse |
| `Request.java` | 236 | ✍️ | `domain/http/Request.ets` | Byte-level HTTP parsing |
| `Response.java` | 75 | ✍️ | `domain/http/Response.ets` | Static error singletons |
| `Range.java` | 53 | ✍️ | `domain/http/Range.ets` | Byte range math |
| `Method.java` | 24 | ✍️ | `domain/http/Method.ets` | Enum: GET/POST/HEAD |
| `HttpVersion.java` | 27 | ✍️ | `domain/http/HttpVersion.ets` | Enum: HTTP/1.0, HTTP/1.1 |
| `RequestHandler.java` | 10 | ✍️ | `domain/http/RequestHandler.ets` | Interface |

### 1.6 HTTP Handlers (`http/handlers/`)

| Java File | Lines | Action | ArkTS Target | Notes |
|-----------|-------|--------|-------------|-------|
| `HandlerBase.java` | 211 | ✍️ | `domain/http/handlers/HandlerBase.ets` | 200/206/416 response builders |
| `AssetHandler.java` | 48 | ✍️ | `domain/http/handlers/AssetHandler.ets` | OH resourceManager |
| `StaticResourceHandler.java` | 95 | ✍️ | `domain/http/handlers/StaticResourceHandler.ets` | Range+HEAD, file serving |
| `SoapHandler.java` | 199 | ✍️ | `domain/http/handlers/upnp/SoapHandler.ets` | SOAP 1.1 parsing |
| `TorrentHandler.java` | 278 | ✍️ | `domain/http/handlers/TorrentHandler.ets` | Torrent streaming |
| `PlaylistHandler.java` | 197 | ✍️ | `domain/http/handlers/PlaylistHandler.ets` | M3U generation |
| `ContentDirectoryHandler.java` | 275 | ✍️ | `domain/http/handlers/upnp/ContentDirectoryHandler.ets` | DIDL-Lite Browse |
| `DescriptorHandler.java` | 122 | ✍️ | `domain/http/handlers/upnp/DescriptorHandler.ets` | Device XML |

### 1.7 SSDP (`ssdp/`)

| Java File | Lines | Action | ArkTS Target | Notes |
|-----------|-------|--------|-------------|-------|
| `SsdpServer.java` | 215 | ✍️ | `services/SsdpService.ets` | Multicast SSDP |

### 1.8 Views (`views/`)

| Java File | Lines | Action | ArkTS Target | Notes |
|-----------|-------|--------|-------------|-------|
| `TorrentsList.java` | 172 | ✍️ | `components/torrent/TorrentListView.ets` | `List` + `@State` polling |
| `TorrentView.java` | 695 | ✍️ | `components/torrent/TorrentDetailView.ets` | Expandable card, progress, menu |
| `BrowseView.java` | 172 | ✍️ | `components/common/BrowsePathView.ets` | Row with text + button |
| `PageFragment.java` | 86 | 🗑️ | — | ArkUI `Tabs` handles natively |
| `WatchView.java` | 37 | ✍️ | `components/settings/WatchDirsView.ets` | List container |
| `WatchItemView.java` | 66 | ✍️ | `components/settings/WatchDirItem.ets` | Reusable row |
| `CheckBoxView.java` | 62 | ✍️ | `components/common/CheckBoxSetting.ets` | `Toggle` + label |
| `PathItem.java` | 225 | ✍️ | `components/torrent/FileTreeModel.ets` | Tree model for file selection |
| `TabInfo.java` | 35 | 🗑️ | — | Built into `Tabs` component |

---

## 2. Rewrite Complexity by Module

| Module | Java LOC | Complexity | Key Challenges |
|--------|----------|-----------|----------------|
| Native Bridge (Native.java) | 264 | **HIGH** | N-API adaptation of 40 methods + ThreadSafeFunction for callbacks |
| Storage Access (StorageAccess.java) | 355 | **HIGH** | Bidirectional C→ArkTS I/O, path/URI mapping, fd tracking |
| Transmission Session | ~500 | **HIGH** | Session lifecycle, watch dirs, thread safety |
| Torrent Models (Torrent+File+Dir) | ~950 | **MEDIUM** | Data model port, N-API backed methods |
| TorrentView (UI) | 695 | **MEDIUM** | Complex custom view: progress bar, file tree, context menu |
| HTTP Server | ~650 | **MEDIUM** | Byte-level HTTP parsing, java.net reuse on OH |
| UPnP/SSDP | ~700 | **MEDIUM** | DIDL-Lite XML, SOAP parsing, multicast |
| MainActivity/AddTorrent | ~800 | **MEDIUM** | Navigation flow, intent handling, permissions |
| SelectFileActivity | 649 | **MEDIUM** | File picker, SAF→OH FileAccess adaptation |
| Settings + Adapters | ~900 | **LOW** | Preferences CRUD, simple UI bindings |
| Prefs.java | 619 | **LOW** | Key-value store, simple default logic |
| Utils.java | 861 | **LOW** | Split into OH platform API calls |

---

## 3. N-API Bridge Rewrite (40 Methods)

All 40 native methods from `Native.java` must be reimplemented as N-API functions:

### 3.1 Simple Type Mapping

| JNI Type | N-API Type | Example |
|----------|-----------|---------|
| `jstring` | `napi_value` (string) | `transmissionVersion() → string` |
| `jlong` | `napi_value` (int64/bigint) | Session pointer, torrent ID, semaphore |
| `jint` | `napi_value` (int32) | Counts, result codes |
| `jboolean` | `napi_value` (boolean) | Flags |
| `void` (return) | `napi_get_undefined` | Mutating operations |
| `jlongArray` | `napi_value` (BigInt64Array) | Stat arrays |
| `jbyteArray` | `napi_value` (Uint8Array) | Hash buffers |
| `jobjectArray` (String[]) | `napi_value` (string[]) | File name lists |

### 3.2 N-API Function Skeleton

```cpp
// For each of the 40 methods:
static napi_value TransmissionVersion(napi_env env, napi_callback_info info) {
    // 1. Extract args via napi_get_cb_info
    size_t argc = 0;
    napi_value args[0];
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

    // 2. Call existing C logic (unchanged from JNI version)
    const char* version = SHORT_VERSION_STRING;

    // 3. Return via napi_create_*
    napi_value result;
    napi_create_string_utf8(env, version, NAPI_AUTO_LENGTH, &result);
    return result;
}
```

### 3.3 C→ArkTS Callback Migration

```cpp
// Old JNI pattern:
// static jmethodID addedOrChangedCallback;  // Cached in nativeToJavaInit
// env->CallStaticVoidMethod(classNative, addedOrChangedCallback);

// New N-API pattern:
// static napi_threadsafe_function tsfn_added_or_changed;

// In init: napi_create_threadsafe_function(
//     env, callback_js_func, nullptr, "TorrentCallback",
//     0, 1, nullptr, nullptr, nullptr,
//     CallJsCallback, &tsfn_added_or_changed
// );

// In C callback:
// napi_call_threadsafe_function(tsfn_added_or_changed, nullptr, napi_tsfn_blocking);

// CallJsCallback (on loop thread):
static void CallJsCallback(napi_env env, napi_value js_cb,
                           void* context, void* data) {
    napi_call_function(env, nullptr, js_cb, 0, nullptr, nullptr);
}
```

### 3.4 tr_android_* → tr_oh_* Migration

```cpp
// Old: int tr_android_file_open(const char* path, int flags, ...)
//   → JNI FindClass + GetStaticMethodID → CallStaticIntMethod
//   → Java StorageAccess.openFile() returns int fd

// New: int tr_oh_file_open(const char* path, int flags, ...)
//   → Pack params into struct
//   → napi_call_threadsafe_function(tsfn_file_open, packed_params, ...)
//   → sem_wait() for result
//   → ArkTS StorageAccessAdapter.openFile() returns int fd
//   → sem_post() + return fd
```

---

## 4. UI Component Mapping

### 4.1 Fragment/ViewPager → ArkUI Tabs

```typescript
// Old: ViewPager + FragmentPagerAdapter + 5 PageFragments
// New:
@Component
struct MainPage {
  @State currentIndex: number = 0

  build() {
    Tabs({ index: this.currentIndex }) {
      TabContent() { DownloadsView() }
        .tabBar('Downloads')
      TabContent() { SettingsView() }
        .tabBar('Settings')
      TabContent() { WatchDirsView() }
        .tabBar('Watch Dirs')
      TabContent() { ProxyView() }
        .tabBar('Proxy')
      TabContent() { AboutView() }
        .tabBar('About')
    }
  }
}
```

### 4.2 TorrentView → ArkUI @Component

```typescript
// Old: TorrentView extends RelativeLayout (695 lines)
// New:
@Component
struct TorrentDetailView {
  @State torrent: Torrent
  @State expanded: boolean = false
  @State files: TorrentItem[] = []

  build() {
    Column() {
      Row() {
        Text(this.torrent.name).fontSize(16)
        Image($r('app.media.play')).onClick(() => this.play())
        Image($r('app.media.menu')).onClick(() => this.showMenu())
      }
      Text(this.statusText).fontSize(12).fontColor(this.statusColor)
      Progress({ value: this.torrent.progress, total: 100 })
        .color(this.progressColor)
      if (this.expanded) {
        ForEach(this.files, (item: TorrentItem) => {
          if (item instanceof TorrentDir) {
            DirView({ dir: item })
          } else {
            FileView({ file: item as TorrentFile })
          }
        })
      }
    }
    .onClick(() => this.expanded = !this.expanded)
  }

  // Computed properties
  get statusText(): string { /* ... */ }
  get statusColor(): string { /* ... */ }
  get progressColor(): string { /* ... */ }

  // Actions
  play() { /* ... */ }
  showMenu() { /* ContextMenuSheet */ }
}
```

### 4.3 DataBinding → @State / @Provide

```typescript
// Old: DataBindingUtil.setVariable(BR.h, bindingHelper)
//      @{h.serviceRunning ? "Stop" : "Start"}

// New: ArkUI reactive state
@Provide('serviceState') serviceState: ServiceState = new ServiceState()

// In child component:
@Consume('serviceState') serviceState: ServiceState

// In template:
Button(this.serviceState.isRunning ? 'Stop' : 'Start')
  .onClick(() => this.serviceState.toggle())
```

### 4.4 Adapters → ArkUI Built-in

```typescript
// Old: @BindingAdapter({"app:pref"})
//      checkBoxPropAdapter(CheckBox, K) — TextWatcher → SharedPreferences

// New: Direct @State binding
@Component
struct CheckBoxSetting {
  @State checked: boolean = false
  prefKey: string = ''

  aboutToAppear() {
    this.checked = PreferencesManager.getBoolean(this.prefKey, false)
  }

  build() {
    Row() {
      Text(this.label)
      Toggle({ type: ToggleType.Checkbox, isOn: this.checked })
        .onChange((isOn: boolean) => {
          this.checked = isOn
          PreferencesManager.putBoolean(this.prefKey, isOn)
        })
    }
  }
}
```

---

## 5. Summary Statistics

| Category | Java Files | Action |
|----------|-----------|--------|
| Full Rewrite (Java→ArkTS) | 42 | Logic preserved, syntax ported |
| Discarded (not needed) | 13 | Replaced by ArkUI/OH features |
| OH API Replacement | 6 | Platform API instead of custom code |
| Native Adaptation (C++) | 12 | JNI→N-API, logic unchanged |

**Estimated rewrite effort:**
- Java → ArkTS translation: ~65 files, ~11K LOC → ~7-8K LOC ArkTS
- N-API adaptation: ~1.9K LOC C++ → ~2.5K LOC (adds ThreadSafeFunction boilerplate)
- ArkUI declarative rewrites: ~3K LOC for complex views
- Total new code: ~13K LOC ArkTS + ~2.5K LOC adapted C++

---

## 6. Migration Order (Dependency-Driven)

```
Phase A: Foundation (no dependencies)
  ├─ PreferencesManager.ets (Prefs.java)
  ├─ NativeBridge.ets (Native.java N-API wrapper)
  ├─ StorageAccessAdapter.ets (StorageAccess.java)
  ├─ WakeLockManager.ets (PowerLock.java)
  └─ ConnectivityMonitor.ets (ConnectivityChangeReceiver.java)

Phase B: Domain Models (depends on A)
  ├─ TorrentExceptions.ets
  ├─ TorrentItem.ets → Torrent.ets, TorrentFile.ets, TorrentDir.ets
  ├─ TorrentStat.ets, MediaInfo.ets
  ├─ TorrentFs.ets
  └─ TransmissionSession.ets

Phase C: HTTP Infrastructure (soft depends on B)
  ├─ Method.ets, HttpVersion.ets, Range.ets
  ├─ Request.ets, Response.ets
  └─ SimpleHttpServer.ets + HandlerBase.ets

Phase D: HTTP Handlers (depends on C)
  ├─ TorrentHandler.ets, PlaylistHandler.ets
  ├─ AssetHandler.ets, StaticResourceHandler.ets
  └─ SoapHandler.ets → UPnP handlers

Phase E: Services (depends on B)
  ├─ TransmissionService.ets
  ├─ HttpServerService.ets
  └─ SsdpService.ets

Phase F: UI Components (depends on B+E)
  ├─ Common: BrowsePathView, CheckBoxSetting
  ├─ Torrent: TorrentListView, TorrentDetailView, FileTreeModel
  └─ Settings: SettingsView, ProxyView, WatchDirsView

Phase G: Pages (depends on F)
  ├─ MainPage.ets
  ├─ AddTorrentPage.ets
  └─ SelectFilePage.ets
```
