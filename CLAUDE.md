# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Identity

**transmissionhm** — HarmonyOS BitTorrent client, ported from [transmissionbtc](https://github.com/AndreyPavlenko/transmissionbtc) (Android v1.3.10). All Java discarded; application layer rewritten in ArkTS + ArkUI. The C/C++ engine (libtransmission + deps) is preserved and adapted from JNI → N-API.

## Build & Verify

```bash
# Assemble signed debug HAP (project-local hvigorw wrapper)
./hvigorw assembleHap --mode module -p product=default -p buildMode=debug --no-daemon

# Output: entry/build/default/outputs/default/entry-default-signed.hap
```

**Toolchain:** DevEco Studio hvigor v6.24.3 + Node v18.20.1, targeting HarmonyOS 6.1.1 (API 24). The project-local `hvigorw` wrapper delegates to the DevEco Studio bundled toolchain at `/Applications/DevEco-Studio.app/Contents/tools/`. Signing config uses an automated debug certificate at `~/.ohos/config/default_transmissionBT_*.p12`.

**SDK version ordering** enforced by hvigor 6.x: `compatibleSdkVersion (5.0.0/API 12) <= targetSdkVersion (6.1.1/API 24)`. Do not set compatible higher than target — the build will fail with error 00303015.

No lint or test commands are wired yet (M6 phase: UI complete, tests pending).

## Architecture

```
ArkTS/ArkUI (21 files)  ← M6 complete, all pages functional
        │
N-API Bridge (C++, 11 files) ← M1_FULL_BRIDGE active, 40 methods
        │
libtransmission + deps (C)  ← 18 .a files cross-compiled for OH arm64-v8a (Transmission 4.1 main)
```

Three layers, all active:

- **ArkTS layer** (`entry/src/main/ets/`): All classes call real `native.*` functions via `NativeBridge.getInstance()`. Covers 5 pages (Downloads, Settings, Proxy, About, AddTorrent), 12 components, 5 domain models, foreground service, and NativeBridge.
- **N-API bridge** (`entry/src/main/cpp/`): 12 `.cc` files compiled with `M1_FULL_BRIDGE`. 9 submodules (`Register*` functions) register 40 N-API methods. ThreadSafeFunction callbacks wire libtransmission events to ArkTS.
- **Native engine**: 18 cross-compiled static `.a` files at `entry/src/main/cpp/third_party/` — libtransmission 4.1 (C++ API), OpenSSL (3.0.15), libcurl (8.5.0), libevent (2.1.12) + 10 sub-deps (dht, b64, natpmp, miniupnpc, utp, psl, crcany, deflate, wildmat). Header-only: rapidjson (replaces jsonsl), fmt, fast_float, small, utfcpp, wide-integer, sigslot.

### Third-party `.a` files

All 18 static libraries are at `entry/src/main/cpp/third_party/<lib>/lib/`:

| Library | Files |
|---------|-------|
| transmission | libtransmission.a (15M) |
| openssl | libssl.a, libcrypto.a |
| curl | libcurl.a |
| libevent | libevent.a, libevent_core.a, libevent_extra.a, libevent_openssl.a, libevent_pthreads.a |
| sub-deps | libdht.a, libb64.a, libnatpmp.a, libminiupnpc.a, libutp.a, libpsl.a, libMadlerCrcany.a, libdeflate.a, libwildmat.a |

`libjsonsl.a` removed — replaced by header-only rapidjson (bundled with transmission 4.1).
`libpsl.a` added — Public Suffix List (new submodule in 4.1, eliminates psl_* stubs).
`libMadlerCrcany.a` added — CRC library (new dependency in 4.1).
`third_party_stubs.cc` is empty — all 6 formerly-stubbed symbols resolved by the 4.1 build.

Source repo for the transmission fork: `/Users/xiphis/projects/transmissionbtc` (contains CMake ExternalProject scripts and JNI C++ sources). Build script: `scripts/build-third-party.sh`.

## Key Conventions

### ArkTS
- `@Component` PascalCase, one per file, max 600 lines
- `@State` for local, `@Prop` parent→child, `@Link` two-way binding
- `@Builder` methods extracted when `build()` exceeds ~40 lines
- Native calls go through `NativeBridge.getInstance()` singleton — never call `native.*` directly from components
- Design tokens in `utils/constants.ets` (Colors, FontSize, Spacing, Radius, Duration)

### C++
- `snake_case` for `.cc`/`.h` filenames, `PascalCase` for functions, `camelCase` for N-API exports
- All N-API calls check `napi_status`; macros in `commons.h` (`CHECK_STATUS`, `throwEX`, `CATCH` label)
- ThreadSafeFunction is the only way to call ArkTS from a non-main thread
- Smart pointers only — no raw `new`/`delete`
- hilog format: `%{private}s` for user data, `%{public}s` for constants

## Current Status (2026-08-08)

- [x] DevEco Studio project scaffold (M0.1–0.5)
- [x] N-API module skeleton with `getVersion()` returning `"0.1.0-m6"`
- [x] All ArkTS source files written (production code, ~21 files)
- [x] All C++ N-API source files written (12 files, M1_FULL_BRIDGE active)
- [x] HAP builds and signs successfully (12MB signed HAP)
- [x] Third-party native libs cross-compiled for OH arm64-v8a (18 .a files, Transmission 4.1)
- [x] M1: 40-method N-API bridge → pruned to **31 public NativeBridge methods** (dead surface removed in codex batch, Task #106)
- [x] M2: Preferences & settings persistence (instant-apply, typed getter/setter)
- [x] M3: Torrent domain models (8 files: TorrentInfo, TorrentFile, TorrentDir, TransmissionSession, FileTreeModel, Preferences, SessionConfig, SessionState; legacy models Torrent/TorrentFs/TorrentStat/TorrentItem/TorrentExceptions/MediaInfo/NaturalOrderComparator deleted)
- [x] M4: Foreground service + connectivity monitor + wake lock
- [x] M5: Core UI (torrent list, detail, file tree, add flow, context menu)
- [x] M6: Settings UI + about + polish (loading states, error handling, reset)
- [x] Codex architecture + code review completed (`.ai-review/codex-review.md`); **all findings fixed** (Tasks #98–107) — BUILD SUCCESSFUL
- [x] M7 (unit): ohosTest wired (`hvigorw test` hangs at GenerateUnitTestResult — use `assembleHap -p module=entry@ohosTest` + `hdc install` + `aa test`). **222/222 tests pass on device** (Pura 80 `4VM0125513000074`). 7 initial failures fixed: `buildTree` now normalizes nested `file.name` to basename; 3 stale test assertions corrected (dirCount=3 subdirs, no STOPPING note, downloadedEver=haveValid per Task #104)
- [x] M7 (E2E, in-process): **8/8 in-process E2E tests pass on device — 231/231 total** (Pura 80 `4VM0125513000074`). `FunctionalE2E.test.ets` drives the REAL libtransmission session via NativeBridge (exactly like DownloadsPage): 7.1 session lifecycle + suspend/resume, 7.2 file add + file listing, 7.8 DnD (setWanted → refreshStats priority=SKIP), 7.9 10 concurrent torrents, 7.11 relocation, 7.12 removal (with/without data). Base64-embedded local .torrent fixtures, network features disabled, per-test isolated settingsDir/downloadDir. The foreground service stays REMOVED (system-app-only on HarmonyOS NEXT — see module.json5 note); the session runs in-process. 7.3/7.4 (download integrity/sequential) need a reachable tracker+seed; 7.6 (boot auto-start) is impossible on a consumer device; 7.7 (WiFi-only) needs live network manipulation — all deferred.
  - **E2E-found bridge caveats:** (1) HarmonyOS `@ohos.buffer` `Buffer.buffer.slice()` returns an empty ArrayBuffer on pool-reused allocations — always copy via `buffer.from(buf)` before writing. (2) `tr_torrentRemove` dispatches to the session's own event thread and returns immediately — the torrent disappears a few ms later (the UI sees it via its 1s poll); tests must poll, not assert synchronously.

**v1.0 scope:** 7 milestones, 75 tasks. 22 features deferred to v1.1+ (UPnP/DLNA/SSDP, M3U, Watch Dirs, Dark Theme, RU locale, RSS, Alt Web UI, HTTP streaming server, bidirectional storage adapter).

**Deferred debt from codex review:** async session-thread dispatch for N-API calls (P0 — now CONFIRMED by E2E: `runInTransmissionThread` executes on the calling thread and `tr_torrentRemove` dispatches to the session's event thread fire-and-forget; the UI's 1s poll masks removal latency, but any synchronous assumption after remove is wrong. Revisit when a session-thread dispatch primitive exists), service re-enable requires `install_list_capability` device provisioning (P0 — permanently deferred, see module.json5 note), magnet-link native parsing.

## Critical Docs

| Reference | Content |
|-----------|---------|
| `docs/07-development-plan.md` | Full milestone plan + task breakdown (ground truth) |
| `docs/08-java-to-arkts-mapping.md` | 65 Java files → ArkTS mapping |
| `docs/01-native-bridge-and-core-engine.md` | 40 N-API methods spec, C++ file inventory |
| `docs/06-feature-map-and-gap-analysis.md` | Feature priorities, deferred list |
| `docs/M0-kickoff.md` | M0 execution checklist |
| `design/tokens.css` | CSS design tokens (reference for ArkTS Colors constant) |
| `design/demo.html` | Interactive UI prototype |
