# 06 — Feature Map & Priorities (v1.0 Simplified)

## Overview

This document maps every feature of the transmissionbtm HarmonyOS BitTorrent client with a priority level. Each feature is classified with a status, priority, and notes on dependencies, implementation complexity, and cross-platform API effort.

**v1.0 Scope Decision (2026-06-28, revised same day):** The following feature groups are **deferred to v1.1+** to reduce initial delivery scope from ~41-60 days to ~26-40 days:

| Deferred | Priority | 分类 | Reason |
|----------|-------------------|------|--------|
| UPnP/DLNA & SSDP (9 features: 4.1–4.9) | P2–P3 | **移植欠账** | DLNA Media Server is not core BT functionality |
| Custom HTTP server + streaming (7 features: 3.1–3.7) | P0–P1 | **移植欠账** | "Play while downloading" is a nice-to-have; v1.0: download complete files, play via file URI |
| M3U playlist generation (3.4) | P1 | **移植欠账** | Primary consumer was DLNA + HTTP streaming; not needed without either |
| Watch directories (5.12) | P2 | **移植欠账** | Manual torrent add covers core workflow |
| Dark theme (5.16) | P2 | 对齐参考实现（参考实现也没有） | Ship one intentional theme first; add dark mode post-v1.0 |
| Russian localization (5.17) | P3 | 对齐参考实现（参考实现也只有 RU+EN） | v1.0 targets zh-CN / en-US only |
| RSS feed (5.14) | P3 | 对齐参考实现（参考实现也是空桩） | Was an empty stub in the reference source; never implemented |
| Alternative web UI (8.3) | P3 | **移植欠账** | Standard Transmission web UI is sufficient |
| Storage adapter (bidirectional N-API I/O bridge) | P0 | 简化（架构决策，非欠账） | **Simplified:** v1.0 uses app sandbox + POSIX I/O directly. No FileAccessHelper bridge needed. External storage support deferred to v1.1+ |

> **分类口径**：**移植欠账** = 能力上可在 HarmonyOS 上实现、但按**范围决策**延后的功能（magnet、URL 添加、HTTP 流媒体、UPnP/DLNA、监视目录）；延后是**范围决策**而非技术不可行。
> **系统墙** = consumer HarmonyOS NEXT 上系统应用独占、无论投入多少都跑不起来的项——**开机自启**（需 `install_list_capability` 设备级预置）、**前台服务**（TransmissionService 已删，见 docs/11 E3）。这两项不在上方 feature map 里，因为它们无法作为普通第三方应用在 HarmonyOS 上实现。
> 2026-08-09 更新：magnet（D1 `2c488f4`）与 URL 添加（D2 `2c488f4`）两个移植欠账已补齐，见 docs/11 阶段 D。
> **2026-08-23 刷新：** 引擎已还原到真实 4.1.0 stable；P0 remove-race（改 `tr_torrentRemoveInSessionThread`）与 piece-priority（改文件级）已修；`services/TransmissionService.ets` 已删除。上方 defer 表仍成立；其余变更以 [`docs/STATUS.md`](STATUS.md) 为准。

**Legend:** ✅ = Present in source / 🔶 = Partial / ❌ = Missing / 🚫 = Deferred to v1.1+

---

## 1. Protocol & Core Engine

| # | Feature | transmissionbtm | Priority | Notes |
|---|---------|--------------|----------|-------|
| 1.1 | BitTorrent protocol (P2P transfers) | ❌ | **P0** | Core engine. Port via N-API |
| 1.2 | DHT (Distributed Hash Table) | ❌ | **P1** | Trackerless peer discovery |
| 1.3 | Peer Exchange (PEX) | ❌ | **P1** | Peer list sharing |
| 1.4 | Local Peer Discovery (LPD) | ❌ | **P2** | LAN peer discovery |
| 1.5 | µTP transport | ❌ | **P1** | Low-extra-delay transport |
| 1.6 | NAT-PMP port mapping | ❌ | **P2** | Automatic port forwarding |
| 1.7 | UPnP port mapping | ❌ | **P2** | Automatic port forwarding |
| 1.8 | Encryption (Allow/Prefer/Require) | ❌ | **P0** | Protocol encryption |
| 1.9 | Sequential download | ❌ | **P1** | Streaming-friendly download order |
| 1.10 | Peer connection limits | ❌ | **P2** | Configurable via settings |
| 1.11 | Speed limits | ❌ | **P2** | Scheduled + manual |
| 1.12 | File prioritization (DnD) | ❌ | **P1** | Per-file download control |
| 1.13 | Magnet link support | ❌ | **P0** | 300s timeout, metadata callback |
| 1.14 | .torrent file parsing | ❌ | **P0** | Local + remote torrent files |
| 1.15 | Torrent verification | ❌ | **P1** | Hash re-check of existing data |
| 1.16 | Data relocation (Set Location) | ❌ | **P2** | Move downloaded data |
| 1.17 | Torrent removal (with/without data) | ❌ | **P0** | Two removal modes |
| 1.18 | Resume after stop | ❌ | **P0** | Persist + reload session state |
| 1.19 | Torrent stat collection | ❌ | **P0** | Per-torrent + per-file stats |
| 1.20 | Piece-level stats | ❌ | **P1** | 64-bit piece availability maps |

---

## 2. Networking & Proxy

| # | Feature | transmissionbtm | Priority | Notes |
|---|---------|--------------|----------|-------|
| 2.1 | HTTP/HTTPS proxy | ❌ | **P1** | ALL/HTTP/HTTPS/NO_PROXY vars |
| 2.2 | SOCKS5 proxy | ❌ | **P3** | libtransmission supports it |
| 2.3 | WiFi/Ethernet only mode | ❌ | **P0** | Auto-suspend on mobile data |
| 2.4 | Allowed SSIDs | ❌ | **P2** | Specific WiFi network filtering |
| 2.5 | cURL HTTP downloads | ❌ | **P1** | For torrent file + web UI downloads |
| 2.6 | SSL verification bypass | ❌ | **P2** | Configurable for self-signed |

---

## 3. HTTP Server & Streaming — 🚫 DEFERRED TO v1.1+

| # | Feature | transmissionbtm | Priority | Notes |
|---|---------|--------------|----------|-------|
| 3.1 | Custom HTTP server | 🚫 | ~~P1~~ | Deferred. v1.0: complete files played directly via file URI |
| 3.2 | Torrent file streaming | 🚫 | ~~P0~~ | Deferred. "Play while downloading" → v1.1 |
| 3.3 | HTTP Range support | 🚫 | ~~P1~~ | Deferred with streaming |
| 3.4 | M3U playlist generation | 🚫 | ~~P1~~ | Deferred (already in round 1) |
| 3.5 | Static resource serving | 🚫 | ~~P1~~ | Only needed for UPnP SCPD XMLs (also deferred) |
| 3.6 | Configurable HTTP port | 🚫 | ~~P1~~ | Deferred with HTTP server |
| 3.7 | Local-only mode | 🚫 | ~~P1~~ | Deferred with HTTP server |

---

## 4. UPnP/DLNA & SSDP — 🚫 DEFERRED TO v1.1+

| # | Feature | transmissionbtm | Priority | Notes |
|---|---------|--------------|----------|-------|
| 4.1 | DLNA Media Server (DMS 1.50) | 🚫 | ~~P2~~ | Deferred |
| 4.2 | ContentDirectory:1 Browse | 🚫 | ~~P2~~ | Deferred |
| 4.3 | ContentDirectory:1 Search | 🚫 | ~~P3~~ | Deferred |
| 4.4 | ConnectionManager:1 | 🚫 | ~~P3~~ | Deferred |
| 4.5 | DIDL-Lite XML generation | 🚫 | ~~P2~~ | Deferred |
| 4.6 | SSDP discovery | 🚫 | ~~P2~~ | Deferred |
| 4.7 | UPnP enable/disable toggle | 🚫 | ~~P2~~ | Deferred |
| 4.8 | UPnP SOAP protocol | 🚫 | ~~P2~~ | Deferred |
| 4.9 | Media metadata in DLNA | 🚫 | ~~P3~~ | Deferred |

---

## 5. User Interface

| # | Feature | transmissionbtm | Priority | Notes |
|---|---------|--------------|----------|-------|
| 5.1 | Tab-based navigation (4 tabs) | ❌ | **P0** | Downloads, Settings, Proxy, About (Watch Dirs merged into Settings) |
| 5.2 | Torrent list with live stats | ❌ | **P0** | Name, progress, speed, peers, status |
| 5.3 | Torrent detail expand/collapse | ❌ | **P0** | File tree with per-file progress |
| 5.4 | Context menu (8 actions) | ❌ | **P0** | Expand, Play, Pause, Resume, Verify, Set Location, Remove ×2 |
| 5.5 | Add torrent from file | ❌ | **P0** | File picker |
| 5.6 | Add torrent from link | ✅ | **P0** | URL or magnet link input. **Done (D1/D2 `2c488f4`)** — AddTorrentPage 3 页签：FILE/MAGNET/URL；原生磁力（BEP9）+ curlDownload 下载 .torrent 到 cache |
| 5.7 | Add torrent from external intent | ❌ | **P0** | Magnet, .torrent, HTTP schemes |
| 5.8 | Open torrent for playback | ❌ | **P1** | Sequential + wait + auto-open |
| 5.9 | File selection on add | ❌ | **P0** | DnD toggle per file |
| 5.10 | Settings (20+ configurable items) | ❌ | **P0** | No save button — instant apply |
| 5.11 | Proxy settings | ❌ | **P1** | ALL/HTTP/HTTPS/NO PROXY |
| 5.12 | Watch directories | 🚫 | ~~P2~~ | **Deferred to v1.1+** |
| 5.13 | About page | ❌ | **P3** | Version info from BuildConfig + native |
| 5.14 | RSS feed | 🚫 | ~~P3~~ | **Deferred to v1.1+.** Was empty stub in source |
| 5.15 | TV (leanback) support | ❌ | **P3** | Not applicable to HarmonyOS |
| 5.16 | Dark theme support | 🚫 | ~~P2~~ | **Deferred to v1.1+.** Ship light theme first |
| 5.17 | Russian localization | 🚫 | ~~P3~~ | **Deferred to v1.1+.** v1.0: zh-CN + en-US |

---

## 6. Background Service & System Integration

| # | Feature | transmissionbtm | Priority | Notes |
|---|---------|--------------|----------|-------|
| 6.1 | Foreground service | ❌ | **P0** | Sticky notification |
| 6.2 | Start on boot | ❌ | **P1** | Configurable delay |
| 6.3 | Auto-restart after update | ❌ | **P2** | Reconnect after app update |
| 6.4 | CPU wake lock | ❌ | **P0** | Prevent sleep during transfers |
| 6.5 | WiFi lock | ❌ | **P1** | Keep WiFi active |
| 6.6 | Service start/stop from UI | ❌ | **P0** | Bound to BindingHelper |
| 6.7 | Suspend/Resume | ❌ | **P1** | Pause all transfers without stopping service |
| 6.8 | State change listeners | ❌ | **P1** | UI reactivity to service state |
| 6.9 | Notification updates | ❌ | **P1** | Running/Suspended + IP |

---

## 7. Storage & File Access

> **v1.0 Simplification:** All downloads restricted to app sandbox directory. libtransmission uses raw POSIX I/O (`fopen`/`read`/`write`) directly — no bidirectional N-API file I/O bridge needed. The `tr_android_*` / `tr_oh_*` hooks are NOT compiled into the Transmission fork. External storage support (SD card, etc.) via FileAccessHelper deferred to v1.1+.

| # | Feature | transmissionbtm | Priority | Notes |
|---|---------|--------------|----------|-------|
| 7.1 | File I/O (POSIX) | ✅ | **P0** | Raw POSIX in sandbox — no adapter needed |
| 7.2 | Multi-directory download | ❌ | **P1** | Subdirectories within sandbox — POSIX mkdir |
| 7.3 | Directory creation | ✅ | **P0** | Standard `mkdir -p` via POSIX |
| 7.4 | File open (fd) | ✅ | **P0** | Standard `open()` via POSIX |
| 7.5 | File rename | ✅ | **P1** | Standard `rename()` via POSIX |
| 7.6 | File delete | ✅ | **P1** | Standard `unlink()` + `rmdir` via POSIX |
| 7.7 | Path-to-URI persistence | ❌ | **P3** | Not needed for sandbox-only v1.0 |
| 7.8 | Storage root discovery | ❌ | **P3** | Deferred with external storage |
| 7.9 | Content tree permission persistence | ❌ | **P3** | Deferred with external storage |
| 7.10 | Root shell scripts | ✂️ | — | Not applicable to HarmonyOS |

---

## 8. Web UI & RPC

| # | Feature | transmissionbtm | Priority | Notes |
|---|---------|--------------|----------|-------|
| 8.1 | Transmission RPC server | ❌ | **P0** | JSON-RPC protocol |
| 8.2 | Web UI serving | ❌ | **P1** | Copied from APK assets at start |
| 8.3 | Alternative web UI | 🚫 | ~~P3~~ | **Deferred to v1.1+.** Standard UI sufficient |
| 8.4 | RPC authentication | ❌ | **P1** | Optional |
| 8.5 | RPC whitelist | ❌ | **P1** | Access control |
| 8.6 | Web UI button in app | ❌ | **P3** | Opens browser to RPC URL |

---

## 9. Data & Configuration

| # | Feature | transmissionbtm | Priority | Notes |
|---|---------|--------------|----------|-------|
| 9.1 | Live preference persistence | ❌ | **P0** | No save button, instant apply |
| 9.2 | Settings JSON save/load | ❌ | **P0** | Native-side config persistence |
| 9.3 | Session resume | ❌ | **P0** | Survives service stop/start |
| 9.4 | UUID generation & persistence | ❌ | **P2** | One-shot, persisted to prefs (keep: needed if UPnP added later) |
| 9.5 | Data binding (declarative state) | ❌ | **P1** | Replace with @State/@Prop or custom |

---

## 10. Build & Dependencies

| # | Feature | transmissionbtm | Priority | Notes |
|---|---------|--------------|----------|-------|
| 10.1 | Gradle build (AGP 4.2.2) | ❌ | **P0** | Replace with Hvigor |
| 10.2 | CMake native build | ❌ | **P0** | Port CMake to OH native build |
| 10.3 | OpenSSL build from source | ❌ | **P0** | May use OH system OpenSSL |
| 10.4 | libcurl build from source | ❌ | **P0** | May use OH system curl |
| 10.5 | libevent build from source | ❌ | **P0** | Or OH event subsystem |
| 10.6 | libtransmission fork | ❌ | **P0** | Patch + compile for OH |
| 10.7 | Web assets merge | ❌ | **P1** | Build-time asset preparation |
| 10.8 | ABI-specific APK building | ❌ | **P1** | OH: arm64-v8a only or multi-arch |
| 10.9 | ProGuard | ❌ | **P2** | Hvigor obfuscation |

---

## 11. Priority Summary (v1.0)

| Priority | Count | Description |
|----------|-------|-------------|
| **P0** | 22 | Core: no functioning app without these (↓3: HTTP streaming ×2 + storage adapter simplified) |
| **P1** | 19 | Important: needed for good UX (↓7: HTTP features ×5 + M3U + storage roots) |
| **P2** | 11 | Advanced: power users, ecosystem (↓8: UPnP×6 + Watch Dirs + Dark Theme; same as round 1) |
| **P3** | 5 | Nice-to-have: polish, ecosystem (↓6: UPnP×3 + RSS + RU + Alt Web UI; same as round 1) |
| 🚫 **Deferred** | **22** | **v1.1+**: UPnP/DLNA/SSDP (9) + HTTP server/streaming (7) + M3U + Watch Dirs + Dark Theme + RU + RSS + Alt Web UI |

### P0 Critical Path

```
1. Native engine (libtransmission + deps via N-API)
2. N-API bridge (35 native methods)
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

## 13. Implementation Complexity

| Component | Complexity | Reason |
|-----------|-----------|--------|
| Native engine (C libs + CMake) | **HIGH** | 4 third-party libs, custom fork, N-API adaptation of 35 native methods |
| Foreground service | **MEDIUM** | OH service lifecycle + notification API |
| UI (ArkUI) | **MEDIUM** | ArkTS declarative components |
| Preferences | **LOW** | @ohos.data.preferences |
| Broadcast receivers | **MEDIUM** | Event system via @ohos.net.connection / static subscriber |
| Build system | **MEDIUM** | Hvigor + CMake for native |
| ~~File I/O (external storage adapter)~~ | ~~HIGH~~ → **LOW** | v1.0: raw POSIX I/O in sandbox. No bidirectional bridge |
| ~~HTTP server (streaming only)~~ | 🚫 | Deferred to v1.1+ |
| ~~UPnP/SSDP~~ | 🚫 | Deferred to v1.1+ |
