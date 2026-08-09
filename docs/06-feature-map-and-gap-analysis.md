# 06 — Feature Map & Gap Analysis (v1.0 Simplified)

## Overview

This document maps every feature in **transmissionbtc** (v1.3.10) against a target HarmonyOS port (**transmissionhm**). Each feature is classified with a priority level and notes on dependencies, implementation complexity, and Android→HarmonyOS API migration effort.

**v1.0 Scope Decision (2026-06-28, revised same day):** The following feature groups are **deferred to v1.1+** to reduce initial delivery scope from ~41-60 days to ~26-40 days:

| Deferred | Original Priority | Reason |
|----------|-------------------|--------|
| UPnP/DLNA & SSDP (9 features: 4.1–4.9) | P2–P3 | DLNA Media Server is not core BT functionality |
| Custom HTTP server + streaming (7 features: 3.1–3.7) | P0–P1 | "Play while downloading" is a nice-to-have; v1.0: download complete files, play via file URI |
| M3U playlist generation (3.4) | P1 | Primary consumer was DLNA + HTTP streaming; not needed without either |
| Watch directories (5.12) | P2 | Manual torrent add covers core workflow |
| Dark theme (5.16) | P2 | Ship one intentional theme first; add dark mode post-v1.0 |
| Russian localization (5.17) | P3 | v1.0 targets zh-CN / en-US only |
| RSS feed (5.14) | P3 | Was an empty stub in Android source; never implemented |
| Alternative web UI (8.3) | P3 | Standard Transmission web UI is sufficient |
| Storage adapter (bidirectional N-API I/O bridge) | P0 | **Simplified:** v1.0 uses app sandbox + POSIX I/O directly. No FileAccessHelper bridge needed. External storage support deferred to v1.1+ |

**Legend:** ✅ = Present in source / 🔶 = Partial / ❌ = Missing / 🚫 = Deferred to v1.1+

---

## 1. Protocol & Core Engine

| # | Feature | transmissionbtc | transmissionhm | Priority | Notes |
|---|---------|----------------|----------------|----------|-------|
| 1.1 | BitTorrent protocol (P2P transfers) | ✅ (via libtransmission C) | ❌ | **P0** | Core engine. Port via N-API |
| 1.2 | DHT (Distributed Hash Table) | ✅ (libdht.a) | ❌ | **P1** | Trackerless peer discovery |
| 1.3 | Peer Exchange (PEX) | ✅ (libtransmission) | ❌ | **P1** | Peer list sharing |
| 1.4 | Local Peer Discovery (LPD) | ✅ (libtransmission) | ❌ | **P2** | LAN peer discovery |
| 1.5 | µTP transport | ✅ (libutp.a) | ❌ | **P1** | Low-extra-delay transport |
| 1.6 | NAT-PMP port mapping | ✅ (libnatpmp.a) | ❌ | **P2** | Automatic port forwarding |
| 1.7 | UPnP port mapping | ✅ (libminiupnpc.a) | ❌ | **P2** | Automatic port forwarding |
| 1.8 | Encryption (Allow/Prefer/Require) | ✅ (EncrMode enum + libtransmission) | ❌ | **P0** | Protocol encryption |
| 1.9 | Sequential download | ✅ (torrentSetPiecesHiPri) | ❌ | **P1** | Streaming-friendly download order |
| 1.10 | Peer connection limits | ✅ (via libtransmission) | ❌ | **P2** | Configurable via settings |
| 1.11 | Speed limits | ✅ (via libtransmission alt speed) | ❌ | **P2** | Scheduled + manual |
| 1.12 | File prioritization (DnD) | ✅ (torrentSetDnd) | ❌ | **P1** | Per-file download control |
| 1.13 | Magnet link support | ✅ (torrentMagnetToTorrentFile) | ❌ | **P0** | 300s timeout, metadata callback |
| 1.14 | .torrent file parsing | ✅ (ctorFromFile + infoFromFile) | ❌ | **P0** | Local + remote torrent files |
| 1.15 | Torrent verification | ✅ (torrentVerify) | ❌ | **P1** | Hash re-check of existing data |
| 1.16 | Data relocation (Set Location) | ✅ (torrentSetLocation) | ❌ | **P2** | Move downloaded data |
| 1.17 | Torrent removal (with/without data) | ✅ (torrentRemove) | ❌ | **P0** | Two removal modes |
| 1.18 | Resume after stop | ✅ (tr_sessionLoadTorrents) | ❌ | **P0** | Persist + reload session state |
| 1.19 | Torrent stat collection | ✅ (torrentStatBrief, 10 fields) | ❌ | **P0** | Per-torrent + per-file stats |
| 1.20 | Piece-level stats | ✅ (torrentGetFileStat + bitfields) | ❌ | **P1** | 64-bit piece availability maps |

---

## 2. Networking & Proxy

| # | Feature | transmissionbtc | transmissionhm | Priority | Notes |
|---|---------|----------------|----------------|----------|-------|
| 2.1 | HTTP/HTTPS proxy | ✅ (envSet + libcurl) | ❌ | **P1** | ALL/HTTP/HTTPS/NO_PROXY vars |
| 2.2 | SOCKS5 proxy | 🔶 (via libtransmission, not configurable in UI) | ❌ | **P3** | libtransmission supports it |
| 2.3 | WiFi/Ethernet only mode | ✅ (WIFI_ETH_ONLY + ConnectivityChangeReceiver) | ❌ | **P0** | Auto-suspend on mobile data |
| 2.4 | Allowed SSIDs | ✅ (WIFI_SSID, needs location perm on Android 8+) | ❌ | **P2** | Specific WiFi network filtering |
| 2.5 | cURL HTTP downloads | ✅ (curl.cc via libcurl) | ❌ | **P1** | For torrent file + web UI downloads |
| 2.6 | SSL verification bypass | ✅ (TR_CURL_SSL_NO_VERIFY) | ❌ | **P2** | Configurable for self-signed |

---

## 3. HTTP Server & Streaming — 🚫 DEFERRED TO v1.1+

| # | Feature | transmissionbtc | transmissionhm | Priority | Notes |
|---|---------|----------------|----------------|----------|-------|
| 3.1 | Custom HTTP server | ✅ (SimpleHttpServer, ~250 loc) | 🚫 | ~~P1~~ | Deferred. v1.0: complete files played directly via file URI |
| 3.2 | Torrent file streaming | ✅ (TorrentHandler) | 🚫 | ~~P0~~ | Deferred. "Play while downloading" → v1.1 |
| 3.3 | HTTP Range support | ✅ (Range.java, 206/416) | 🚫 | ~~P1~~ | Deferred with streaming |
| 3.4 | M3U playlist generation | ✅ (PlaylistHandler) | 🚫 | ~~P1~~ | Deferred (already in round 1) |
| 3.5 | Static resource serving | ✅ (AssetHandler, StaticResourceHandler) | 🚫 | ~~P1~~ | Only needed for UPnP SCPD XMLs (also deferred) |
| 3.6 | Configurable HTTP port | ✅ (HTTP_SERVER_PORT, default 9092) | 🚫 | ~~P1~~ | Deferred with HTTP server |
| 3.7 | Local-only mode | ✅ (127.0.0.1 binding) | 🚫 | ~~P1~~ | Deferred with HTTP server |

---

## 4. UPnP/DLNA & SSDP — 🚫 DEFERRED TO v1.1+

| # | Feature | transmissionbtc | transmissionhm | Priority | Notes |
|---|---------|----------------|----------------|----------|-------|
| 4.1 | DLNA Media Server (DMS 1.50) | ✅ (DescriptorHandler) | 🚫 | ~~P2~~ | Deferred |
| 4.2 | ContentDirectory:1 Browse | ✅ (ContentDirectoryHandler) | 🚫 | ~~P2~~ | Deferred |
| 4.3 | ContentDirectory:1 Search | ❌ (not implemented) | 🚫 | ~~P3~~ | Deferred |
| 4.4 | ConnectionManager:1 | 🔶 (SCPD only, no handler) | 🚫 | ~~P3~~ | Deferred |
| 4.5 | DIDL-Lite XML generation | ✅ | 🚫 | ~~P2~~ | Deferred |
| 4.6 | SSDP discovery | ✅ (SsdpServer, 215 loc) | 🚫 | ~~P2~~ | Deferred |
| 4.7 | UPnP enable/disable toggle | ✅ (ENABLE_UPNP) | 🚫 | ~~P2~~ | Deferred |
| 4.8 | UPnP SOAP protocol | ✅ (SoapHandler, generic) | 🚫 | ~~P2~~ | Deferred |
| 4.9 | Media metadata in DLNA | ✅ (MediaInfo enrichment) | 🚫 | ~~P3~~ | Deferred |

---

## 5. User Interface

| # | Feature | transmissionbtc | transmissionhm | Priority | Notes |
|---|---------|----------------|----------------|----------|-------|
| 5.1 | Tab-based navigation (4 tabs) | ✅ (ViewPager + TabLayout) | ❌ | **P0** | Downloads, Settings, Proxy, About (Watch Dirs merged into Settings) |
| 5.2 | Torrent list with live stats | ✅ (TorrentsList, 1s polling) | ❌ | **P0** | Name, progress, speed, peers, status |
| 5.3 | Torrent detail expand/collapse | ✅ (TorrentView) | ❌ | **P0** | File tree with per-file progress |
| 5.4 | Context menu (8 actions) | ✅ (torrent_menu.xml) | ❌ | **P0** | Expand, Play, Pause, Resume, Verify, Set Location, Remove ×2 |
| 5.5 | Add torrent from file | ✅ (MainActivity → SelectFile → Download) | ❌ | **P0** | File picker |
| 5.6 | Add torrent from link | ✅ (MainActivity AlertDialog) | ❌ | **P0** | URL or magnet link input |
| 5.7 | Add torrent from external intent | ✅ (VIEW intent filters ×5) | ❌ | **P0** | Magnet, .torrent, HTTP schemes |
| 5.8 | Open torrent for playback | ✅ (OpenTorrentActivity) | ❌ | **P1** | Sequential + wait + auto-open |
| 5.9 | File selection on add | ✅ (PathItem tree + checkboxes) | ❌ | **P0** | DnD toggle per file |
| 5.10 | Settings (20+ configurable items) | ✅ (settings.xml, live-bound) | ❌ | **P0** | No save button — instant apply |
| 5.11 | Proxy settings | ✅ (proxy.xml, 4 fields) | ❌ | **P1** | ALL/HTTP/HTTPS/NO PROXY |
| 5.12 | Watch directories | ✅ (watch_dirs.xml) | 🚫 | ~~P2~~ | **Deferred to v1.1+** |
| 5.13 | About page | ✅ (about.xml, HTML) | ❌ | **P3** | Version info from BuildConfig + native |
| 5.14 | RSS feed | 🔶 (stub, rss.xml exists but empty) | 🚫 | ~~P3~~ | **Deferred to v1.1+.** Was empty stub in source |
| 5.15 | Android TV (leanback) support | ✅ (LEANBACK_LAUNCHER category) | ❌ | **P3** | Not applicable to HarmonyOS |
| 5.16 | Dark theme support | ❌ (only AppCompat.Light) | 🚫 | ~~P2~~ | **Deferred to v1.1+.** Ship light theme first |
| 5.17 | Russian localization | ✅ (values-ru/) | 🚫 | ~~P3~~ | **Deferred to v1.1+.** v1.0: zh-CN + en-US |

---

## 6. Background Service & System Integration

| # | Feature | transmissionbtc | transmissionhm | Priority | Notes |
|---|---------|----------------|----------------|----------|-------|
| 6.1 | Foreground service | ✅ (TransmissionService) | ❌ | **P0** | Sticky notification |
| 6.2 | Start on boot | ✅ (BootOrUpdateReceiver) | ❌ | **P1** | Configurable delay |
| 6.3 | Auto-restart after update | ✅ (MY_PACKAGE_REPLACED) | ❌ | **P2** | Reconnect after app update |
| 6.4 | CPU wake lock | ✅ (PowerLock, PARTIAL_WAKE_LOCK) | ❌ | **P0** | Prevent sleep during transfers |
| 6.5 | WiFi lock | ✅ (PowerLock, WIFI_MODE_FULL) | ❌ | **P1** | Keep WiFi active |
| 6.6 | Service start/stop from UI | ✅ (main.xml buttons) | ❌ | **P0** | Bound to BindingHelper |
| 6.7 | Suspend/Resume | ✅ (menu items + transmissionSuspend) | ❌ | **P1** | Pause all transfers without stopping service |
| 6.8 | State change listeners | ✅ (WeakHashMap callbacks) | ❌ | **P1** | UI reactivity to service state |
| 6.9 | Notification updates | ✅ (TransmissionService.updateNotification) | ❌ | **P1** | Running/Suspended + IP |

---

## 7. Storage & File Access

> **v1.0 Simplification:** All downloads restricted to app sandbox directory. libtransmission uses raw POSIX I/O (`fopen`/`read`/`write`) directly — no bidirectional N-API file I/O bridge needed. The `tr_android_*` / `tr_oh_*` hooks are NOT compiled into the Transmission fork. External storage support (SD card, etc.) via FileAccessHelper deferred to v1.1+.

| # | Feature | transmissionbtc | transmissionhm | Priority | Notes |
|---|---------|----------------|----------------|----------|-------|
| 7.1 | File I/O (POSIX) | 🔶 (SAF via JNI bridge) | ✅ | **P0** | Raw POSIX in sandbox — no adapter needed |
| 7.2 | Multi-directory download | ✅ (per-torrent download dir) | ❌ | **P1** | Subdirectories within sandbox — POSIX mkdir |
| 7.3 | Directory creation | ✅ (createDir, recursive) | ✅ | **P0** | Standard `mkdir -p` via POSIX |
| 7.4 | File open (fd) | ✅ (openFile → fd via SAF) | ✅ | **P0** | Standard `open()` via POSIX |
| 7.5 | File rename | ✅ (renamePath, copy+delete fallback) | ✅ | **P1** | Standard `rename()` via POSIX |
| 7.6 | File delete | ✅ (removePath, recursive) | ✅ | **P1** | Standard `unlink()` + `rmdir` via POSIX |
| 7.7 | Path-to-URI persistence | ✅ (pathToUrlMappings SP) | ❌ | **P3** | Not needed for sandbox-only v1.0 |
| 7.8 | Storage root discovery | ✅ (SelectFileActivity.getRoots) | ❌ | **P3** | Deferred with external storage |
| 7.9 | Content tree permission persistence | ✅ (takePersistableUriPermission) | ❌ | **P3** | Deferred with external storage |
| 7.10 | Root shell scripts | ✅ (Scripts.java, set_so_buf.sh) | ✂️ | — | Not applicable to HarmonyOS |

---

## 8. Web UI & RPC

| # | Feature | transmissionbtc | transmissionhm | Priority | Notes |
|---|---------|----------------|----------------|----------|-------|
| 8.1 | Transmission RPC server | ✅ (native, port 9091) | ❌ | **P0** | JSON-RPC protocol |
| 8.2 | Web UI serving | ✅ (native, TRANSMISSION_WEB_HOME) | ❌ | **P1** | Copied from APK assets at start |
| 8.3 | Alternative web UI | ✅ (ENABLE_ALT_WEB_UI toggle) | 🚫 | ~~P3~~ | **Deferred to v1.1+.** Standard UI sufficient |
| 8.4 | RPC authentication | ✅ (username/password) | ❌ | **P1** | Optional |
| 8.5 | RPC whitelist | ✅ (IP-based, default 127.0.0.1,192.168.*.*) | ❌ | **P1** | Access control |
| 8.6 | Web UI button in app | ✅ (main.xml button) | ❌ | **P3** | Opens browser to RPC URL |

---

## 9. Data & Configuration

| # | Feature | transmissionbtc | transmissionhm | Priority | Notes |
|---|---------|----------------|----------------|----------|-------|
| 9.1 | Live preference persistence | ✅ (TextWatcher + OnCheckedChangeListener) | ❌ | **P0** | No save button, instant apply |
| 9.2 | Settings JSON save/load | ✅ (tr_sessionLoadSettings/SaveSettings) | ❌ | **P0** | Native-side config persistence |
| 9.3 | Session resume | ✅ (resume directory + load torrents) | ❌ | **P0** | Survives service stop/start |
| 9.4 | UUID generation & persistence | ✅ (UPnP device identity) | ❌ | **P2** | One-shot, persisted to prefs (keep: needed if UPnP added later) |
| 9.5 | Android Data Binding | ✅ (@BindingAdapter, BR variables) | ❌ | **P1** | Replace with @State/@Prop or custom |

---

## 10. Build & Dependencies

| # | Feature | transmissionbtc | transmissionhm | Priority | Notes |
|---|---------|----------------|----------------|----------|-------|
| 10.1 | Gradle build (AGP 4.2.2) | ✅ | ❌ | **P0** | Replace with Hvigor |
| 10.2 | CMake native build | ✅ (ExternalProject for 4 libs) | ❌ | **P0** | Port CMake to OH native build |
| 10.3 | OpenSSL build from source | ✅ (1.1.1l, static) | ❌ | **P0** | May use OH system OpenSSL |
| 10.4 | libcurl build from source | ✅ (7.78.0, static) | ❌ | **P0** | May use OH system curl |
| 10.5 | libevent build from source | ✅ (2.1.12, static) | ❌ | **P0** | Or OH event subsystem |
| 10.6 | libtransmission fork | ✅ (github.com/AndreyPavlenko/transmission) | ❌ | **P0** | Patch + compile for OH |
| 10.7 | Web assets merge | ✅ (download + merge tarball) | ❌ | **P1** | Build-time asset preparation |
| 10.8 | ABI-specific APK building | ✅ (4 ABIs via bundletool) | ❌ | **P1** | OH: arm64-v8a only or multi-arch |
| 10.9 | ProGuard | ✅ (keep com.ap.**) | ❌ | **P2** | Hvigor obfuscation |

---

## 11. Priority Summary (v1.0)

| Priority | Count | Description |
|----------|-------|-------------|
| **P0** | 22 | Core: no functioning app without these (↓3: HTTP streaming ×2 + SAF adapter simplified) |
| **P1** | 19 | Important: needed for good UX (↓7: HTTP features ×5 + M3U + storage roots) |
| **P2** | 11 | Advanced: power users, ecosystem (↓8: UPnP×6 + Watch Dirs + Dark Theme; same as round 1) |
| **P3** | 5 | Nice-to-have: polish, ecosystem (↓6: UPnP×3 + RSS + RU + Alt Web UI; same as round 1) |
| 🚫 **Deferred** | **22** | **v1.1+**: UPnP/DLNA/SSDP (9) + HTTP server/streaming (7) + M3U + Watch Dirs + Dark Theme + RU + RSS + Alt Web UI |

### P0 Critical Path

```
1. Native engine port (libtransmission + deps via N-API)
2. JNI bridge → N-API adaptation (40 methods)
3. Foreground service + notification
4. Basic UI: torrent list + add torrent
5. Preferences + session persistence
6. RPC server + web UI
7. Download complete → play via file URI
```

---

## 12. Feature Dependencies (v1.0)

```
P0:
  ├─ libtransmission + deps (OpenSSL, curl, libevent) → N-API bridge
  ├─ Preferences persistence
  ├─ Foreground service
  ├─ Basic UI (torrent list, add, detail)
  └─ RPC server + web UI

P1:
  ├─ DHT / µTP / PEX ← depends on libtransmission compile flags
  ├─ Proxy config ← depends on RPC config
  ├─ Sequential download ← depends on torrent operations
  ├─ File prioritization ← depends on add torrent flow
  ├─ Boot start ← depends on service + prefs
  └─ Torrent verification ← depends on torrent operations

P2:
  ├─ NAT-PMP/UPnP port mapping ← depends on libtransmission
  ├─ Speed limits ← depends on session management
  ├─ Allowed SSIDs ← depends on network monitoring
  ├─ Set location ← depends on file I/O (POSIX)
  └─ LPD / Peer limits ← depends on libtransmission compile flags

P3:
  ├─ About page ← UI only
  ├─ SOCKS5 proxy ← libtransmission support (no UI)
  ├─ Web UI button ← UI only
  └─ Root scripts ← not applicable to OH

🚫 Deferred (v1.1+):
  ├─ DLNA/UPnP/SSDP (9 features)
  ├─ HTTP server + streaming + Range + M3U (7 features)
  ├─ Watch directories
  ├─ Dark theme
  ├─ Russian localization
  ├─ RSS
  ├─ Alternative web UI
  └─ External storage (FileAccessHelper adapter)
```

---

## 13. Android→HarmonyOS Migration Complexity

| Component | Complexity | Reason |
|-----------|-----------|--------|
| Native engine (C libs + CMake) | **HIGH** | 4 third-party libs, custom fork, N-API adaptation of 40 methods |
| Foreground service | **MEDIUM** | Different lifecycle, notification API |
| UI (Data Binding→ArkUI) | **MEDIUM** | Complete rewrite from XML to ArkTS declarative |
| Preferences | **LOW** | SharedPreferences → @ohos.data.preferences |
| Broadcast receivers | **MEDIUM** | Different event system |
| Build system | **MEDIUM** | Gradle→Hvigor, keep CMake for native |
| ~~File I/O (SAF adapter)~~ | ~~HIGH~~ → **LOW** | v1.0: raw POSIX I/O in sandbox. No bidirectional bridge |
| ~~HTTP server (streaming only)~~ | 🚫 | Deferred to v1.1+ |
| ~~UPnP/SSDP~~ | 🚫 | Deferred to v1.1+ |
