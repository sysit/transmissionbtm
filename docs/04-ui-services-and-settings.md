# 04 — UI, Services & Settings

## Overview

This domain encompasses the entire Android presentation layer, foreground service, broadcast receivers, and settings/preferences system. It follows a classic Android pattern: Activities as entry points, custom View classes for complex UI, Android Data Binding for connecting preferences to UI, a Service for background daemon lifecycle, and Broadcast Receivers for system event handling.

---

## File Inventory

| File | Lines | Purpose |
|------|-------|---------|
| `AndroidManifest.xml` | 342 | Manifest: permissions, 4 activities, 1 service, 1 receiver |
| `AndroidManifest.xml` (basic) | 14 | Product flavor: removes 2 activities |
| `activities/ActivityBase.java` | 41 | Base: Native init, Prefs, activity result delegation |
| `activities/MainActivity.java` | 314 | Main: 5 tabs, start/stop service, add file/link, permissions |
| `activities/DownloadTorrentActivity.java` | 349 | Add torrent: URI handling, magnet/HTTP, file selection |
| `activities/OpenTorrentActivity.java` | 134 | Open torrent directly: sequential download, wait+auto-play |
| `activities/SelectFileActivity.java` | 649 | File picker: directory/file selection, SAF integration |
| `activities/ActivityResultHandler.java` | 10 | Interface for onActivityResult delegation |
| `services/TransmissionService.java` | 257 | Foreground service: start/stop Transmission, notifications |
| `receivers/BootOrUpdateReceiver.java` | 52 | Boot + package replaced auto-start |
| `receivers/ConnectivityChangeReceiver.java` | 44 | Network state changes → suspend/resume |
| `views/TorrentsList.java` | 172 | Torrent list: 1-second polling, AsyncTask updates |
| `views/TorrentView.java` | 695 | Single torrent: stats, progress, context menu, file tree |
| `views/BrowseView.java` | 172 | Directory/file browser with path display |
| `views/PageFragment.java` | 86 | Fragment wrapper for data-bound tab pages |
| `views/WatchView.java` | 37 | Watch directory list container |
| `views/WatchItemView.java` | 66 | Single watch directory with browse controls |
| `views/CheckBoxView.java` | 62 | Custom checkbox with preference binding |
| `views/PathItem.java` | 225 | Tree node model for torrent file path selection |
| `views/TabInfo.java` | 35 | Tab metadata (title, icon, layout) |
| `BindingHelper.java` | 136 | Data binding: service state, URL opening, root check |
| `Prefs.java` | 619 | SharedPreferences wrapper: all keys, getters, setters |
| `Adapters.java` | 194 | Binding adapters: EditText, CheckBox, Spinner, HTML |
| `StorageAccess.java` | 355 | SAF: DocumentFile CRUD via ContentResolver |

**Resources**: 17 layouts, 3 menus, 5 value files (EN+RU), 43 PNGs, 1 shell script

---

## 1. AndroidManifest Analysis

### 1.1 Permissions (11 total)
INTERNET, ACCESS_NETWORK_STATE, ACCESS_WIFI_STATE, READ/WRITE_EXTERNAL_STORAGE, RECEIVE_BOOT_COMPLETED, WAKE_LOCK, ACCESS_COARSE/FINE_LOCATION (for Android 8+ WiFi SSID), FOREGROUND_SERVICE (Android 9+)

### 1.2 Activities

| Activity | Intent Filters | Purpose |
|----------|---------------|---------|
| `MainActivity` | MAIN+LAUNCHER, LEANBACK_LAUNCHER | Main entry point, 5 tabs |
| `DownloadTorrentActivity` | VIEW: magnet, application/x-bittorrent, *.torrent | Download/add torrent flow |
| `OpenTorrentActivity` | Same 5 filters as Download | Open torrent for immediate playback |
| `SelectFileActivity` | None (internal only) | File/directory picker |

### 1.3 Service & Receivers

`TransmissionService` — foreground service, no intent filter (explicit start only). `BootOrUpdateReceiver` — BOOT_COMPLETED + MY_PACKAGE_REPLACED, directBootAware.

### 1.4 Product Flavors

**basic** removes `DownloadTorrentActivity` and `OpenTorrentActivity` → no external intent handling, inline add only.

---

## 2. Activity Catalog

### 2.1 MainActivity

**Tabs** (static): Downloads, Settings, Watch Dirs, Proxy, About (RSS commented out)

**Lifecycle**: `onCreate` → init Native (via ActivityBase), setup ViewPager+TabLayout, request 4-6 permissions. `onStart`/`onStop` → activate/deactivate TorrentsList polling.

**Menu**: Add File, Add Link, Suspend/Resume, Stop/Start — visibility toggled by service state.

**Add flows**: `addFile()` → SelectFileActivity → DownloadTorrentActivity. `addLink()` → AlertDialog → DownloadTorrentActivity.

### 2.2 DownloadTorrentActivity

Handles torrent URI (magnet, HTTP, file). Creates temp file, downloads/resolves torrent, parses file list into PathItem tree, shows directory picker + file checkboxes. Download button → starts service → `Transmission.addTorrent()`. Handles: OK, PARSE_ERR, DUPLICATE, NOT_STARTED.

Inner class `LoadMagnet`: AsyncTask, 300s timeout, supports enqueue during resolution.

### 2.3 OpenTorrentActivity

Extends DownloadTorrentActivity. Differences: `isSequential()=true`, `isIgnoreDuplicate()=true`. Overrides `finish()` to wait for file availability and auto-open media. Inner class `WaitForTorrent`: AsyncTask polling until file streams.

### 2.4 SelectFileActivity

Self-contained `ListActivity`. SAF-aware file picker. Constants in Intent extras: REQUEST_FILE, REQUEST_DIR, REQUEST_WRITABLE, REQUEST_INITIAL, REQUEST_PATTERN, RESULT_FILE. Root discovery via StorageVolume reflection, getFilesDir, getExternalStoragePublicDirectory, etc. Lollipop+: tries ACTION_OPEN_DOCUMENT_TREE for writable dirs. Android 11+: MANAGE_EXTERNAL_STORAGE.

---

## 3. TransmissionService (Foreground)

**Lifecycle**: `onCreate` → init Native + create Transmission. `onStartCommand` → startForeground + StartTask AsyncTask. `onDestroy` → StopTask AsyncTask. Returns `START_STICKY`.

**Static API**: `start(ctx, callback)` — if running, execute callback immediately; else queue + startService. `stop(ctx, callback)` — if stopped, execute immediately; else queue + stopService. `isRunning()` / `getTransmission()` — volatile singleton.

**Notification**: Channel "TransmissionBTC", IMPORTANCE_LOW. Content intent → MainActivity. Text shows "Running" / "Suspended" + optional IP address.

**State listeners**: `WeakHashMap<Runnable, Boolean>` — UI components register for service state changes.

---

## 4. Broadcast Receivers

### BootOrUpdateReceiver
`BOOT_COMPLETED` → if `isStartOnBoot()`, start service after `getBootDelay()` seconds. `MY_PACKAGE_REPLACED` → immediate start if enabled. Retries on `IllegalStateException` after 10s.

### ConnectivityChangeReceiver
Programmatically registered (not in manifest). On `CONNECTIVITY_ACTION`: resets interface address cache, checks `isWifiEthOnly()`, suspends/resumes based on allowed SSIDs. Does not override user-initiated suspension.

---

## 5. View Catalog

### 5.1 TorrentsList (LinearLayout)
1-second polling via UpdateTask AsyncTask when tab active. Compares old/new torrent lists — re-creates TorrentViews if different, calls `update()` if same. Shows ProgressBar placeholder on empty.

### 5.2 TorrentView (RelativeLayout)
Single torrent display. Children: title, play button, menu button, details (status/speed/progress text), ProgressBar (color-coded: error=red, paused=black, done=teal, active=yellow), expandable file tree.

**Context menu** (8 items): Expand/Collapse, Play, Pause/Resume, Verify, Set Location, Remove, Remove+Trash.

**File tree**: `FileView extends ItemView<TorrentFile>` — shows progress, play button for media. `DirView extends ItemView<TorrentDir>` — recursive hierarchy, draws tree lines via Canvas.

### 5.3 BrowseView (RelativeLayout)
Title, optional left button (delete/trash), browse button (launches SelectFileActivity), path EditText. Binds to Pref key via `Adapters.editTextPrefAdapter()`. Custom attributes: title, path, select_dir, select_file, writable, editable.

### 5.4 WatchView / WatchItemView (GridLayout)
WatchView reads max index from `WATCH_DIR`, creates WatchItemView children. Each WatchItemView has two BrowseViews: watch dir + download dir, with trash button.

### 5.5 PageFragment
Fragment wrapping data-bound layout. Inner Adapter extends FragmentPagerAdapter, uses TabInfo array.

### 5.6 PathItem (Data Model)
Implements `Comparable<PathItem>`. Tree node: parent, name, path, index, level, children (Map), visible, checked, collapsed. `split(String...)` builds tree from file path array. `ls()` flattens into sorted list. `setChecked/setCollapsed()` recursive. Used in DownloadTorrentActivity for file selection.

---

## 6. Adapters (Data Binding)

| Adapter | Binding | What It Does |
|---------|---------|-------------|
| `editTextPrefAdapter` | `app:pref`, `app:pref_index` | Binds EditText ↔ SharedPreferences with TextWatcher |
| `checkBoxPropAdapter` | `app:pref` | Binds CheckBox ↔ SharedPreferences boolean |
| `spinnerPropAdapter` | `app:pref` | Binds Spinner ↔ SharedPreferences enum |
| `toHtml` | `app:html` | Sets HTML on TextView (API-aware) |
| `textIcon` | `app:icon` | Sets compound drawable on TextView |
| `visibilityAdapter` | (Conversion) | boolean → View.VISIBLE/GONE |

Uses `R.id.listener_tag` to prevent duplicate listener registration.

---

## 7. Complete Preference Key Catalog (Prefs.java)

### General
| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `SETTINGS_DIR` | String | `{dataDir}/Config` | Transmission config directory |
| `DOWNLOAD_DIR` | String | Max external Downloads | Default download location |
| `PREV_DOWNLOAD_DIR` | String | Current DOWNLOAD_DIR | Last used download dir |
| `WATCH_DIR` | String (indexed, 0-N) | `{dataDir}/Watch` | Watch directory for auto-add |
| `START_ON_BOOT` | boolean | false | Auto-start on boot |
| `BOOT_DELAY` | int | 0 | Boot delay in seconds |
| `ENABLE_WATCH_DIR` | boolean | false | Enable watch dir scanning |
| `WATCH_INTERVAL` | int | 0 | Watch interval in seconds |

### Network
| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `ENABLE_PROXY` | boolean | false | Enable proxy |
| `PROXY_ALL` | String | "" | All-protocol proxy |
| `PROXY_HTTP` | String | "" | HTTP proxy |
| `PROXY_HTTPS` | String | "" | HTTPS proxy |
| `PROXY_NO` | String | "" | No-proxy hosts |
| `WIFI_ETH_ONLY` | boolean | true | Only on WiFi/Ethernet |
| `WIFI_SSID` | String | "" | Allowed SSIDs (comma-separated) |
| `SHOW_LOCATION_PERM_ALERT` | boolean | true | One-shot location dialog |

### Encryption & Performance
| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `ENCR_MODE` | EncrMode enum | Allow | Allow/Prefer/Require |
| `INCREASE_SO_BUF` | boolean | false | Increase socket buffers (needs root) |
| `ENABLE_SEQ_DOWNLOAD` | boolean | false | Sequential download |

### RPC & Web
| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `ENABLE_RPC` | boolean | true | Enable RPC server |
| `RPC_PORT` | int | 9091 | RPC port |
| `ENABLE_ALT_WEB_UI` | boolean | false | Alternative web UI |
| `ENABLE_RPC_AUTH` | boolean | false | RPC authentication |
| `RPC_UNAME` | String | "" | RPC username |
| `RPC_PASSWD` | String | "" | RPC password |
| `ENABLE_RPC_WHITELIST` | boolean | false | RPC whitelist |
| `RPC_WHITELIST` | String | "127.0.0.1,192.168.*.*" | Whitelist entries |

### UPnP
| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `ENABLE_UPNP` | boolean | false | Enable UPnP ContentDirectory |
| `HTTP_SERVER_PORT` | int | 9092 | HTTP streaming server port |
| `UUID` | String | Random UUID | Unique device ID |

---

## 8. Resource Summary

### 8.1 Color Definitions
`error=#ffcd2626`, `controlHighlight=#c0f7ff`, `controlHighlight2=#dcf7fa`, `border=#dfdcdc`, `progress=#fabe00`, `progress_done=#009688`, `progress_pause=#000000`

### 8.2 Theme
`Theme.AppCompat.Light` with `colorControlHighlight=@color/controlHighlight`

### 8.3 Layout Structure

| Layout | Key Content |
|--------|------------|
| `main.xml` | TabLayout + ViewPager + Start/Stop + Web UI buttons |
| `settings.xml` | ScrollView > GridLayout: dirs, WiFi, encryption, boot, performance, UPnP, RPC |
| `torrent_view.xml` | Merge: title, play, menu, details, ProgressBar, content (file tree) |
| `download_torrent.xml` | ProgressBar, file list, download dir BrowseView, download/cancel buttons |
| `downloads.xml` | ScrollView > TorrentsList |
| `watch_dirs.xml` | Add button, interval EditText, WatchView |
| `proxy.xml` | CheckBox + ALL/HTTP/HTTPS/NO PROXY fields |
| `select_file.xml` | ListView, path EditText, OK/New/Cancel |
| `browse_view.xml` | Merge: title, left/right browse buttons, path EditText |
| `about.xml` | ScrollView > HTML TextView |

### 8.4 Menu Structure

**main_menu.xml** (overflow): Add File, Add Link, Suspend, Resume, Stop, Start — all with icons, showAsAction=always|withText

**torrent_menu.xml** (context): Expand, Collapse, Play, Pause, Resume, Verify, Set Location, Remove, Remove+Trash

**select_file_menu.xml**: New Folder

---

## 9. Navigation & Interaction Flow

### App Launch
Tap icon → MainActivity.onCreate → Native init → 5 tabs → Downloads tab (default) → "Start" button → TransmissionService.start() → StartTask → notification appears

### Add Torrent (File)
Menu → Add File → SelectFileActivity → pick .torrent → DownloadTorrentActivity → parse + show file tree → pick dir + deselect files → "Download" → service start → Transmission.addTorrent()

### Add Torrent (Magnet)
Menu → Add Link → enter magnet → DownloadTorrentActivity → LoadMagnet AsyncTask (300s timeout) → resolve to .torrent → same as file flow. Supports enqueue during resolution.

### Service Lifecycle
Start: startup foreground notification → StartTask → Transmission.start() → copy web assets → set env vars → Native.transmissionStart() → start HTTP/SSDP servers → register receivers → acquire PowerLock
Stop: StopTask → Transmission.stop() → save settings → close session → remove notification
Suspend/Resume: Direct call, no service stop. Affects transfers only.

---

## 10. Platform-Specific API → HarmonyOS Mapping

| Android API | HarmonyOS Equivalent |
|---|---|
| `AppCompatActivity` | `@ohos.app.ability.Ability` / `AbilitySlice` |
| `DataBindingUtil` (`@BindingAdapter`) | Custom state management / `@State`/`@Prop` |
| `TabLayout` + `ViewPager` + `FragmentPagerAdapter` | `Tabs` + `Swiper` / `Navigation` |
| `Foreground Service` + `startForeground` | `@ohos.app.Service` + `keepBackgroundRunning()` |
| `Notification` / `NotificationChannel` | `@ohos.notification` / `NotificationSlot` |
| `PendingIntent` | `@ohos.notification.NotificationRequest` with intent agent |
| `START_STICKY` | Auto-restart policy |
| `SharedPreferences` | `@ohos.data.preferences` |
| `BroadcastReceiver` | `@ohos.app.StaticSubscriber` / `CommonEvent` |
| `AsyncTask` | `@ohos.taskpool` / `Worker` |
| `AlertDialog` | `@ohos.ohos.dialog` / `CustomDialog` |
| `DocumentFile` (SAF) | `@ohos.file.fileaccess.FileAccessHelper` |
| `ContentResolver` + `takePersistableUriPermission` | `FileAccessHelper` |
| `ACTION_OPEN_DOCUMENT_TREE` | File picker |
| `ConnectivityManager` | `@ohos.net.connection` |
| `MimeTypeMap` | Custom mapping |
| `PopupMenu` (context) | `@ohos.ohos.agp.window.dialog` |
| `ClipboardManager` | `@ohos.pasteboard` |
| `Html.fromHtml` | `@ohos.text.Html` |
| `SUPPORTED_ABIS` | `@ohos.system.DeviceInfo` |
| `su` (root) | Not supported on HarmonyOS |
| ProGuard | Hvigor obfuscation |
