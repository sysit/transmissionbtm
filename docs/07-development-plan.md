# 07 — Development Plan (ArkTS Rewrite, v1.0 Simplified)

## Overview

This document provides a phased development plan for implementing **transmissionhm** — a HarmonyOS BitTorrent client ported from transmissionbtc. The plan assumes **all Java code is discarded** and the entire application layer is rewritten in **ArkTS + ArkUI**. The C/C++ native layer (libtransmission + dependencies) is preserved and adapted from JNI to N-API.

**v1.0 Scope Decisions (2026-06-28, revised same day):** 22 features deferred to v1.1+ (UPnP/DLNA/SSDP ×9, HTTP server/streaming ×7, M3U playlists, Watch Dirs, Dark Theme, RU locale, RSS, Alt Web UI). Storage simplified to sandbox-only POSIX I/O — no bidirectional FileAccessHelper bridge. See `docs/06-feature-map-and-gap-analysis.md` §11 for details.

**Total estimated effort:** 7 milestones, 68 tasks, ~21-33 working days (sequential), ~15-22 days with parallel work.

---

## Milestone 0: Project Scaffold & Native Build (3-5 days)

**Goal:** HarmonyOS project that compiles. Native libs build for OH. N-API module skeleton loads.

| # | Task | Source Reference | Target | Verification |
|---|------|-----------------|--------|-------------|
| 0.1 | Create DevEco Studio project with Hvigor | — | `entry/` + `hvigor/` | Empty app deploys to device/emulator |
| 0.2 | Port CMake build: libtransmission + 4 deps for OH | `CMakeLists.txt`, `cmake/*.cmake` | OH NDK CMake | `libtransmissionbtc.so` compiles arm64-v8a |
| 0.3 | Compile OpenSSL 1.1.1l for OH | `cmake/OpenSSL.cmake` | OH musl toolchain | `libssl.a` + `libcrypto.a` link |
| 0.4 | Compile libcurl 7.78.0 for OH | `cmake/cURL.cmake` | OH musl toolchain | `libcurl.a` links |
| 0.5 | Compile libevent 2.1.12 for OH | `cmake/Event.cmake` | OH musl toolchain | `libevent.a` links |
| 0.6 | Patch + compile Transmission fork for OH | `cmake/Transmission.cmake` | OH musl, `tr_oh_*` stub hooks | `libtransmission.a` + sub-libs build |
| 0.7 | Set up N-API module registration | `Native.java` init | `napi_module_register()` in `native_bridge.cpp` | Module loads, `napi_get_undefined` returns |
| 0.8 | Adapt `stdredirect.cc` for OH log | `__android_log_write` → `OH_LOG_Print` | hilog | Transmission C logs appear in hilog |
| 0.9 | Adapt `env.cc` for OH | `setenv`/`unsetenv` | musl (unchanged) | Env vars set/get correctly |
| 0.10 | Adapt `hash.cc` for N-API | JNI jbyteArray→napi_value Uint8Array | N-API | SHA-1 hex ↔ bytes round-trips |

---

## Milestone 1: N-API Bridge — Session & Torrent (6-9 days)

**Goal:** All 40 N-API functions implemented. Session lifecycle works. Torrent CRUD works. C→ArkTS callbacks active.

| # | Task | Source | Target | Verification |
|---|------|--------|--------|-------------|
| 1.1 | Port `commons.cc/h` — error handling + thread dispatch | `cpp/commons.cc:1-201` | N-API macros + `napi_throw_error` | Exceptions propagate to ArkTS |
| 1.2 | Implement `runInTransmissionThread` for N-API | `cpp/commons.cc:175` | N-API + OH semaphore/promise | Torrent ops serialize on event thread |
| 1.3 | Port `transmission.cc` — session start/stop/suspend | `cpp/transmission.cc:1-305` | N-API, methods 1-7 | Session inits, torrents resume from disk |
| 1.4 | Port `torrent.cc` — torrent add/remove/start/stop/verify | `cpp/torrent.cc:1-903` | N-API, methods 8-14 | All CRUD operations work |
| 1.5 | Port `torrent.cc` — magnet resolution | `torrentMagnetToTorrentFile()` | N-API, method 15 | Magnet → .torrent with timeout |
| 1.6 | Port `torrent.cc` — stat collection | `torrentStatBrief()`, `torrentGetFileStat()` | N-API, methods 24, 27 | 10-field stat + bitfields correct |
| 1.7 | Port `torrent.cc` — piece access + streaming support | `torrentGetPiece()`, `torrentSetPiecesHiPri()` | N-API, methods 17, 25 | Raw piece read from block cache |
| 1.8 | Port `native_to_java.cc` → `native_to_arkts.cc` — callbacks | ThreadSafeFunction | 4 callbacks: added/changed, stopped, session changed, alt speed | ArkTS receives callbacks on main thread |
| 1.9 | Port `sem.cc` for OH | POSIX → OH semaphore | Methods 31-33 | Magnet resolution + event dispatch work |
| 1.10 | Port `curl.cc` for OH | libcurl or `@ohos.net.http` | Method 35 | URL → file download works |
| 1.11 | Create `NativeBridge.ets` — N-API wrapper class | `Native.java:1-264` | ArkTS class with 40 typed methods | All 40 methods callable, types correct |
| 1.12 | Implement C→ArkTS callback receivers in ArkTS | `Native.java` callback trampolines | ArkTS callbacks registered at init | TorrentAddedOrChanged fires correctly |

---

## Milestone 2: Preferences & Settings Module (2-3 days)

**Goal:** All 40+ preference keys ported. Settings persist + apply in real-time.

| # | Task | Source | Target | Verification |
|---|------|--------|--------|-------------|
| 2.1 | Define all preference keys as constants | `Prefs.java` (40+ keys) | `PreferencesManager.ets` constants | All keys available |
| 2.2 | Implement typed getters with defaults | `Prefs.java` getters | `@ohos.data.preferences` getSync | All types: boolean, int, string, enum |
| 2.3 | Implement typed setters | `Prefs.java` setters | `@ohos.data.preferences` putSync | Changes flush to disk |
| 2.4 | Implement `EncrMode` enum | `EncrMode.java` | ArkTS enum | Allow/Prefer/Require |
| 2.5 | Create `CheckBoxSetting` reusable component | `CheckBoxView.java` + adapter | `@Component` with `Toggle` | Toggle → preference binding works |
| 2.6 | Create `EditTextSetting` reusable component | `Adapters.editTextPrefAdapter` | `@Component` with `TextInput` | Text input → preference binding works |
| 2.7 | Create `SpinnerSetting` reusable component | `Adapters.spinnerPropAdapter` | `@Component` with `Select` | Enum → preference binding works |

---

## Milestone 3: Torrent Domain Models (3.5-5.5 days)

**Goal:** Complete ArkTS domain layer with all torrent management logic. Watch directory polling deferred to v1.1+.

| # | Task | Source | Target | Verification |
|---|------|--------|--------|-------------|
| 3.1 | Define `TorrentItem` + `TorrentItemContainer` interfaces | `torrent/TorrentItem.java` | ArkTS interfaces | Contract matches Java |
| 3.2 | Implement `Torrent` class (38 methods) | `torrent/Torrent.java:1-400` | ArkTS `Torrent` class | All ops via NativeBridge work |
| 3.3 | Implement `TorrentFile` class (30+ methods) | `torrent/TorrentFile.java:1-400` | ArkTS `TorrentFile` class | Piece read/wait, DnD, stat |
| 3.4 | Implement `TorrentDir` class | `torrent/TorrentDir.java:1-150` | ArkTS `TorrentDir` class | Recursive ops, file listing |
| 3.5 | Implement `TorrentStat` (10-field parser) | `torrent/TorrentStat.java` | ArkTS `TorrentStat` class | Flat array → typed accessors |
| 3.6 | Implement `MediaInfo` class | `torrent/MediaInfo.java:1-100` | ArkTS `MediaInfo` class | MIME detection + metadata |
| 3.7 | Implement `TorrentFs` (registry + fs) | `torrent/TorrentFs.java:1-200` | ArkTS `TorrentFs` class | Find by hash, ls, sort, updateId |
| 3.8 | Implement `TransmissionSession` | `torrent/Transmission.java:1-500` | ArkTS `TransmissionSession` class | Start/stop, addTorrent, magnetToTorrent, suspend/resume |
| 3.9 | Implement exception types | `DuplicateTorrentException.java` etc. | ArkTS Error subclasses | Catch + identify error types |
| 3.10 | Implement `NaturalOrderComparator` utility | `NaturalOrderComparator.java` | ArkTS comparison function | File sorting matches Android behavior |

> **Deferred:** Watch directory Watcher (original M4.9) — auto-adding torrents from watch dirs deferred to v1.1+.

---

## Milestone 4: Foreground Service & System Integration (3-4 days)

**Goal:** Background service + notification. Boot start. WiFi/Ethernet only mode.

| # | Task | Source | Target | Verification |
|---|------|--------|--------|-------------|
| 4.1 | Implement `TransmissionService.ets` foreground service | `services/TransmissionService.java:1-257` | `@ohos.app.Service` + `keepBackgroundRunning()` | Service starts + stays running |
| 4.2 | Implement foreground notification | `TransmissionService` notification builder | `@ohos.notification.NotificationRequest` | Running/Suspended + IP text |
| 4.3 | Implement StartTask (async session init) | `TransmissionService.StartTask` | `@ohos.taskpool.Task` | Session inits in background |
| 4.4 | Implement StopTask (async session close) | `TransmissionService.StopTask` | `@ohos.taskpool.Task` | Session saves + closes cleanly |
| 4.5 | Implement state change listener system | `TransmissionService` callbacks | `EventEmitter` or callback array | UI reacts to state changes |
| 4.6 | Implement `WakeLockManager` | `PowerLock.java:1-59` | `@ohos.runningLock` + `@ohos.wifiManager` | Device stays awake during transfers |
| 4.7 | Implement boot start | `BootOrUpdateReceiver.java` | `@ohos.app.StaticSubscriber` | Service auto-starts after boot |
| 4.8 | Implement `ConnectivityMonitor` | `ConnectivityChangeReceiver.java` | `@ohos.net.connection` observer | WiFi/Ethernet only mode works |

---

## Milestone 5: Core UI — Torrents + Add Flow (5-7 days)

**Goal:** Downloads tab with torrent list, torrent detail with file tree, add torrent flows.

| # | Task | Source | Target | Verification |
|---|------|--------|--------|-------------|
| 5.1 | Create `TorrentListView` | `TorrentsList.java` + `downloads.xml` | ArkUI `@Component` with `List` | Live list, 1s polling, progress |
| 5.2 | Create `TorrentDetailView` | `TorrentView.java:1-695` | ArkUI card component | Stats, progress bar, color-coded |
| 5.3 | Create `FileTreeView` (DirView+FileView) | `DirView` + `FileView` inner classes | Recursive ArkUI component | Tree with lines, checkboxes, progress |
| 5.4 | Create `FileTreeModel` | `PathItem.java:1-225` | ArkTS tree data class | File selection with check/collapse state |
| 5.5 | Create `TorrentContextMenu` | `torrent_menu.xml` + handlers | ArkUI `Menu` or action sheet | 8 actions: play, pause, resume, verify, etc. |
| 5.6 | Create `AddTorrentPage` | `DownloadTorrentActivity.java:1-349` | Modal page | File selection + download flow |
| 5.7 | Create magnet link input + resolve UI | `MainActivity.addLink()` + `LoadMagnet` | `CustomDialog` + progress | Magnet resolves with progress feedback |
| 5.8 | Create add-from-external-intent flow | `AndroidManifest` intent filters | OH `skills` in `module.json5` | External apps can share to app |
| 5.9 | Create `SelectFilePage` | `SelectFileActivity.java:1-649` | OH FilePicker integration | Directory + file selection |

---

## Milestone 6: Settings UI & Polish (2.5-4 days)

**Goal:** All settings tabs functional. Single theme (light). zh-CN + en-US. Edge cases handled.

| # | Task | Source | Target | Verification |
|---|------|--------|--------|-------------|
| 6.1 | Create `SettingsView` | `settings.xml`, `CheckBoxView`, `BrowseView` | ArkUI `List` with settings groups | All 20+ settings editable + persist |
| 6.2 | Create `BrowsePathView` | `BrowseView.java` | ArkUI `Row` with Text+Button | Directory picker opens, path displayed |
| 6.3 | Create `ProxyView` | `proxy.xml` | Form with toggle + 4 inputs | Proxy settings save + apply |
| 6.4 | Create `AboutView` | `about.xml` | HTML-rendered text | Version info displays correctly |
| 6.5 | Create `MainPage` with 4-tab structure | `MainActivity.java`, `main.xml` | `Tabs` + `@Provide` state | Downloads, Settings, Proxy, About |
| 6.6 | Implement error handling + user-facing messages | `strings.xml` error keys | ArkTS error dialogs/toasts | All error paths user-friendly |
| 6.7 | Implement loading states | — | ArkUI loading spinners | No blank screens during async ops |

> **Deferred:** WatchDirsView, Dark Theme, Russian localization — all deferred to v1.1+.

---

## Milestone 7: Testing & Hardening (3.5-5.5 days)

**Goal:** Full end-to-end verification. Performance validation. Bug fixes.

| # | Task | Verification |
|---|------|-------------|
| 7.1 | Test native layer: session start/stop/suspend/resume | No crashes, all callbacks fire |
| 7.2 | Test torrent add (magnet + file) end-to-end | Magnet resolves, .torrent adds, files display |
| 7.3 | Test download integrity | Downloaded data passes hash verification |
| 7.4 | Test sequential download (no HTTP streaming in v1.0) | Media player streams in-progress download |
| 7.5 | Test settings persistence | All settings survive service restart |
| 7.6 | Test boot auto-start | Service starts after device reboot |
| 7.7 | Test WiFi/Ethernet only mode | Transfers suspend on mobile data |
| 7.8 | Test DnD (do not download) file selection | Selected files excluded, others download |
| 7.9 | Test 10+ concurrent torrents | UI stays responsive, 1s polling OK |
| 7.10 | Test suspend/resume cycle | Resume continues where suspended |
| 7.11 | Test data relocation (set location) | Files moved, torrent finds new path |
| 7.12 | Test torrent removal with/without data | Files deleted correctly per mode |

> **Deferred tests:** M3U playlist verification, UPnP discovery + browsing, HTTP streaming (Range requests, incomplete file playback) — deferred with their respective features.

---

## Milestone Summary

| Milestone | Est. Days | Tasks | Cumulative |
|-----------|----------|-------|------------|
| M0: Scaffold & Native Build | 3-5 | 10 | — |
| M1: N-API Bridge | 6-9 | 12 | 22 |
| M2: Preferences | 2-3 | 7 | 29 |
| M3: Domain Models | 3.5-5.5 | 10 | 39 |
| M4: Service & System | 3-4 | 8 | 47 |
| M5: Core UI | 5-7 | 9 | 56 |
| M6: Settings UI & Polish | 2.5-4 | 7 | 63 |
| M7: Testing & Hardening | 3.5-5.5 | 12 | 75 |

**Total: 7 milestones, 75 tasks (↓19 from original 94), ~21-33 days** (sequential). With 2-person parallel work: **~15-22 days**.

### v1.0 vs Original Comparison

| Metric | Original Plan | v1.0 Round 1 | v1.0 Round 2 | Total Delta |
|--------|--------------|-------------|-------------|-------------|
| Milestones | 10 | 9 | **7** | **-3** |
| Tasks | 109 | 94 | **75** | **-34** |
| Sequential days | 41-60 | 33-50 | **21-33** | **-20 to -27** |
| Cuts made | — | UPnP×9, M3U, Watch Dirs, Dark Theme, RU, RSS, Alt Web UI | **+HTTP server×7, Storage adapter×9** | **22 features deferred** |

---

## Parallelization Opportunities

```
Stream A: Native Bridge (M0→M1)            // Developer 1
Stream B: Preferences + Domain (M2→M3)     // Developer 2 (after M1 callback infra)
Stream C: Service + UI (M4→M5→M6)          // Both developers (after M3)
Merge: M7 (both)
```

With 2 developers, M2+M3 can overlap with M1 once the N-API callback infrastructure (TSFN) is ready. M4 (Service) and M5 (UI) are largely independent and can parallelize. Target: **~15-22 days** with 2 devs.

---

## Critical Decisions Log

| Decision | Rationale | Impact |
|----------|-----------|--------|
| Discard all Java | No JVM on OH | Must rewrite 65 files in ArkTS |
| Preserve C/C++ | libtransmission is the engine | Only adaptation needed |
| N-API over FFI | Type-safe, supported by OH | More boilerplate but safer |
| java.net for HTTP | Available on OH stdlib | Reduces rewrite effort for HTTP layer |
| @ohos.file.fileaccess for storage | OH equivalent of SAF | Must adapt bidirectional I/O |
| ArkUI @State/@Provide for state | OH native reactive pattern | Replaces DataBinding + BindingHelper |
| ThreadSafeFunction for callbacks | OH N-API pattern for cross-thread calls | Replaces JNI CallStaticVoidMethod |
| **Defer UPnP/DLNA/SSDP to v1.1+** | DLNA is not core BT functionality; HTTP streaming covers playback use case | Saves ~3-4 days, removes 8 tasks |
| **Defer M3U playlists to v1.1+** | Primary consumer was DLNA; file streaming sufficient for v1.0 | Saves ~0.5 days |
| **Defer Watch Dirs to v1.1+** | Manual torrent add covers core workflow | Saves ~1 day |
| **Defer Dark Theme / RU locale to v1.1+** | Ship one theme, zh-CN + en-US first | Saves ~1 day |
| **Simplify storage to sandbox-only POSIX I/O** | No bidirectional N-API file I/O bridge. libtransmission uses raw `fopen`/`read`/`write` within app sandbox. External storage (SD card) deferred to v1.1+ | Removes M2 entirely: saves 4-6 days, 9 tasks |
| **Defer HTTP streaming server to v1.1+** | "Play while downloading" is nice-to-have; v1.0 downloads complete files, plays via file URI. Custom HTTP server + Range support + torrent streaming handler all deferred | Removes M5 entirely: saves 2.5-3.5 days, 9 tasks |
| **Prefer OH system OpenSSL** | Check for system `libopenssl.so` first; if unavailable, build OpenSSL 3.2+ (NOT EOL 1.1.1l) | Saves ~0.5 days if system lib available |
