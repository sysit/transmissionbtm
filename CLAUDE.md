# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

> **History moved to `docs/STATUS.md`.** This file holds only live engineering guidance; the full change log (R7/R8/R9, engine rebuild, milestone closures, deferred debt) lives in `docs/STATUS.md`.

## Project Identity

**transmissionbtm** — HarmonyOS BitTorrent client, ported from [transmissionbtc](https://github.com/AndreyPavlenko/transmissionbtc) (Android v1.3.10). All Java discarded; application layer rewritten in ArkTS + ArkUI. The C/C++ engine (libtransmission + deps) is preserved and adapted from JNI → N-API.

## Build & Verify

```bash
# Assemble signed debug HAP (project-local hvigorw wrapper)
./hvigorw assembleHap --mode module -p product=default -p buildMode=debug --no-daemon

# Output: entry/build/default/outputs/default/entry-default-signed.hap
```

**Toolchain:** DevEco Studio hvigor v6.24.3 + Node v18.20.1, targeting HarmonyOS 6.1.1 (API 24). The project-local `hvigorw` wrapper delegates to the DevEco Studio bundled toolchain at `/Applications/DevEco-Studio.app/Contents/tools/`. Signing config uses an automated debug certificate at `~/.ohos/config/default_transmissionbtm_*.p12`.

**SDK versions** (build-profile.json5): `compatibleSdkVersion (6.1.1/API 24) == targetSdkVersion (6.1.1/API 24)`. hvigor 6.x enforces compatible <= target — do not set compatible higher than target, or the build fails with error 00303015.

No lint commands are wired yet. Unit + E2E tests run via ohosTest on device (see Status below; 231/231 current).

> `hvigorw test` hangs at GenerateUnitTestResult — use `assembleHap -p module=entry@ohosTest` + `hdc install` + `aa test` instead.

## Architecture

```
ArkTS/ArkUI (33 files)  ← M6 complete, all pages functional
        │
N-API Bridge (C++, 8 files) ← M1_FULL_BRIDGE active, 35 methods
        │
libtransmission + deps (C)  ← 18 .a files cross-compiled for OH arm64-v8a (Transmission 4.1.0 stable)
```

Three layers, all active:

- **ArkTS layer** (`entry/src/main/ets/`): All classes call real `native.*` functions via `NativeBridge.getInstance()`. Covers 7 pages (Index, Downloads, Settings, Proxy, About, AddTorrent, FileTree), 11 components, 8 domain models, 2 services (ConnectivityMonitor, WakeLockManager), and NativeBridge.
- **N-API bridge** (`entry/src/main/cpp/`): 8 files (7 `.cc` + `napi_init.cpp`) compiled with `M1_FULL_BRIDGE`. 7 submodules (`Register*` functions) register 35 N-API methods. ThreadSafeFunction callbacks wire libtransmission events to ArkTS.
- **Native engine**: 18 cross-compiled static `.a` files at `entry/src/main/cpp/third_party/` — libtransmission 4.1.0 (C++ API, built from the real stable tag `2724011`), OpenSSL (3.0.15), libcurl (8.5.0), libevent (2.1.12) + sub-deps (dht, b64, natpmp, miniupnpc, utp, psl, crc32c, deflate, wildmat). Header-only: rapidjson (replaces jsonsl), fmt, fast_float, small, utfcpp, wide-integer, sigslot.

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
`libcrc32c.a` (Google crc32c) added — CRC library; 4.1.0 vendors `crc32c::Extend` (replaces the madler-crcany used by the 4.2.0-dev tree).
`third_party_stubs.cc` deleted (E1) — no stubs remain; all formerly-stubbed symbols are resolved by the 4.1 build.

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

## Status (current)

- **Engine:** real Transmission 4.1.0 stable (tag `2724011`), M-Team-compatible. HAP builds + signs; on-device verified.
- **Live-refresh:** torrent cards re-render every 5s via a `TorrentVM` `@ObjectLink` wrapper (`DownloadsPage.syncTorrentVms`).
- **Tests:** 231/231 on-device ohosTest (unit + in-process E2E, Pura 80 `4VM0125513000074`); 80/80 host vitest.
- **Owed code:** P0 remove-race is FIXED; piece-priority reserved export implemented at file level. Remaining: non-blocking async completion primitive for slow ops (add-from-file / relocate), permanently-deferred service re-enable needs `install_list_capability`.
- Full change log + deferred debt → **`docs/STATUS.md`**.

## Critical Docs

| Reference | Content |
|-----------|---------|
| `docs/STATUS.md` | Full change log + deferred debt (R7/R8/R9, engine rebuild, milestones) |
| `docs/07-development-plan.md` | Full milestone plan + task breakdown (ground truth) |
| `docs/08-java-to-arkts-mapping.md` | 65 Java files → ArkTS mapping |
| `docs/01-native-bridge-and-core-engine.md` | 40 N-API methods spec, C++ file inventory |
| `docs/06-feature-map-and-gap-analysis.md` | Feature priorities, deferred list |
| `docs/12-tracker-connect-debugging.md` | Tracker connect failure investigation + multicast-permission research |
| `docs/M0-kickoff.md` | M0 execution checklist |
| `design/tokens.css` | CSS design tokens (reference for ArkTS Colors constant) |
| `design/demo.html` | Interactive UI prototype |
