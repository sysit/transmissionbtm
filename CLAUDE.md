# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

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

No lint commands are wired yet. Unit + E2E tests run via ohosTest on device (see M7 below; 232/232 passing).

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

## Current Status (2026-08-08)

- [x] **Real 4.1.0 stable engine (2026-08-23)** — engine rebuilt from the actual `4.1.0` stable tag (`2724011`), replacing the earlier 4.2.0-dev tree that had only *appeared* to be 4.1.0 via a version-masked `version.h`. M-Team requires 4.1.x. Bridge C++ adapted to 4.1 API (`tr_stat` pointer + camelCase, `tr_ctorSetMetainfo*` `tr_error*` arg, `tr_torrentRemove` 6-arg, raw-callback setters, `TR_UP`/`TR_DOWN`); CRC sub-dep switched madler-crcany → **Google `crc32c`** (`libcrc32c.a`, `crc32c::Extend`); the C++20 oh-compat.h force-include removed (4.1.0 is C++17, no ranges). `crypto-utils.h` (`WITH_OPENSSL`) and the generated `version.h` (re-hand-set `-TR4100-`/`4.1.0`) survived the header regen by re-apply. **BUILD SUCCESSFUL**; on-device verified: M-Team announce `res='Success'`, tracker `seed=/leech=` answered, session + HUKS `selfTest OK`. Rebuild recipe in memory `transmission-410-engine-build`.
- [x] **ArkUI 5s live-refresh (2026-08-23)** — torrent cards now re-render every 5s (a `TorrentVM` `@Observed` wrapper bound via `@ObjectLink`, mutated in place each poll by `DownloadsPage.syncTorrentVms`, so ForEach reuses cards and updates live instead of only on restart). `SessionController` poll cadence moved 1s → 5s. Verified: `[DBG] stat` at 5s cadence + reactive `ForEachNode skip mark dirty`; seeding torrent shows live "Seeding". About page's stale "4.0.6" engine string corrected to **4.1.0**.
- [x] DevEco Studio project scaffold (M0.1–0.5)
- [x] N-API module skeleton with `getVersion()` returning `"0.1.0-m6"`
- [x] All ArkTS source files written (production code, 33 files)
- [x] All C++ N-API source files written (8 files, M1_FULL_BRIDGE active)
- [x] HAP builds and signs successfully (12MB signed HAP)
- [x] Third-party native libs cross-compiled for OH arm64-v8a (18 .a files, Transmission 4.1.0 stable)
- [x] M1: N-API bridge → **35 native methods, 26 public NativeBridge methods** (dead surface removed in codex batch, Task #106; 7 more native methods pruned in E1; 7 more dead ArkTS wrappers removed in R9: `getEncryptionMode`, `transmissionVersion`, `torrentSetDnd`, `hashStringToBytes`, `envSet`, `nativeToArktsInit`, `nativeToArktsRelease` — the native C++ registrations stay, harmless unreachable)
- [x] M2: Preferences & settings persistence (instant-apply, typed getter/setter)
- [x] M3: Torrent domain models (8 files: TorrentInfo, TorrentFile, TorrentDir, TransmissionSession, FileTreeModel, Preferences, SessionConfig, SessionState[SessionRunState only — SessionState class removed in E4]; legacy models Torrent/TorrentFs/TorrentStat/TorrentItem/TorrentExceptions/MediaInfo/NaturalOrderComparator deleted)
- [x] M4: Foreground service + connectivity monitor + wake lock
- [x] M5: Core UI (torrent list, detail, file tree, add flow, context menu)
- [x] M6: Settings UI + about + polish (loading states, error handling, reset)
- [x] Codex architecture + code review completed (`.ai-review/codex-review.md`); critical/high findings fixed (Tasks #98–107) — BUILD SUCCESSFUL (remaining deferred debt below)
- [x] M7 (unit): ohosTest wired (`hvigorw test` hangs at GenerateUnitTestResult — use `assembleHap -p module=entry@ohosTest` + `hdc install` + `aa test`). **222/222 tests pass on device** (Pura 80 `4VM0125513000074`). 7 initial failures fixed: `buildTree` now normalizes nested `file.name` to basename; 3 stale test assertions corrected (dirCount=3 subdirs, no STOPPING note, downloadedEver=haveValid per Task #104)
- [x] M7 (E2E, in-process): **8/8 in-process E2E tests pass on device — 231/231 total** (Pura 80 `4VM0125513000074`). `FunctionalE2E.test.ets` drives the REAL libtransmission session via NativeBridge (exactly like DownloadsPage): 7.1 session lifecycle + suspend/resume, 7.2 file add + file listing, 7.8 DnD (setWanted → refreshStats priority=SKIP), 7.9 10 concurrent torrents, 7.11 relocation, 7.12 removal (with/without data). Base64-embedded local .torrent fixtures, network features disabled, per-test isolated settingsDir/downloadDir. The foreground service stays REMOVED (system-app-only on HarmonyOS NEXT — see module.json5 note); the session runs in-process. 7.3/7.4 (download integrity/sequential) need a reachable tracker+seed; 7.6 (boot auto-start) is impossible on a consumer device; 7.7 (WiFi-only) needs live network manipulation — all deferred.
  - **E2E-found bridge caveats:** (1) HarmonyOS `@ohos.buffer` `Buffer.buffer.slice()` returns an empty ArrayBuffer on pool-reused allocations — always copy via `buffer.from(buf)` before writing. (2) `tr_torrentRemove` dispatches to the session's own event thread and returns immediately — the torrent disappears a few ms later (the UI sees it via its 1s poll); tests must poll, not assert synchronously.

**v1.0 scope:** 7 milestones, 75 tasks. 22 features deferred to v1.1+ (UPnP/DLNA/SSDP, M3U, Watch Dirs, Dark Theme, RU locale, RSS, Alt Web UI, HTTP streaming server, bidirectional storage adapter).

**Deferred debt from codex review:** async session-thread dispatch for N-API calls (P0 — now CONFIRMED by E2E: `runInTransmissionThread` executes on the calling thread and `tr_torrentRemove` dispatches to the session's event thread fire-and-forget; the UI's 1s poll masks removal latency, but any synchronous assumption after remove is wrong. Revisit when a session-thread dispatch primitive exists), service re-enable requires `install_list_capability` device provisioning (P0 — permanently deferred, see module.json5 note). ~~magnet-link native parsing~~ — DONE in D1 (`tr_ctorSetMetainfoFromMagnetLink`, commit 2c488f4). Proxy credentials (R7, Tasks #19/#25) — **DONE and on-device-verified (2026-08-22, emulator).** **Two on-disk exposures existed:** (a) plaintext `proxy_password` as its own `PrefKeys.PROXY_PASSWORD` entry in the app-sandbox `el2` preferences XML (LOW severity, non-world-readable), and (b) — the task title's exact concern — the composed `proxy-url` (with inline `user:pass@`) built by `TransmissionSession.buildSessionSettings()` was ALSO being written to `<settingsDir>/settings.json` via `tr_sessionSaveSettings` in native `SessionStart` + `SessionStop`, because transmission persists `TR_KEY_proxy_url` (session-settings.h Field). R7 fixed BOTH:
- **Preferences store → HUKS AES-256-GCM.** `entry/src/main/ets/security/ProxyCipher.ets` (marker `huk1:` + `ProxyCipher` interface + plaintext `LegacyProxyCipher` fallback) and `security/HukProxyCipher.ets` (GCM pattern ported from v2rayHM's proven `SecureStorage.ets`: IV via `HUKS_TAG_NONCE`, 1-byte AAD via `HUKS_TAG_ASSOCIATED_DATA`, tag split from ciphertext and passed via `HUKS_TAG_AE_TAG`, `HUKS_TAG_DIGEST=HUKS_DIGEST_NONE`, `decodeToString` not `decodeWithStream`). `Preferences.ets` keeps a default `LegacyProxyCipher` (kit-free, host-testable) and injects the HUKS cipher via `setPasswordCipher()`; `setString`/`getString` for `PrefKeys.PROXY_PASSWORD` now encrypt-on-write / decrypt-on-read, `setSessionConfig` routes it through `setString`, and `EntryAbility.onCreate` injects the cipher + runs a startup self-test.
- **settings.json → strip before save.** Native `transmission.cc` gained `StripProxyUrlFromSettings()` (erases `TR_KEY_proxy_url` from a `tr_variant` Map) and now strips it at BOTH save sites — right after `tr_sessionInit` (the live session keeps the proxy, applied at init) and in `SessionStop` (which re-reads session settings). The app re-applies proxy from its HUKS-encrypted preferences on every start, so the snapshot losing it is harmless. RPC credentials are intentionally left (they're the app's own server config that transmission persists by design).

**Verified:** main HAP + `entry@ohosTest` both BUILD SUCCESSFUL; **93/93 host vitest** (new `tests/proxy-cipher.test.ts` + `tests/preferences-proxy-cipher.test.ts` driving a fake cipher against an in-memory `@kit.ArkData` mock); and **on-device emulator `aa start` + hilog → `HukProxyCipher: selfTest OK` / `transmissionbtm: HUKS selfTest OK`** — proving the AES-256-GCM tag/IV/alias round-trip on device, closing the earlier "cannot validate GCM here" gap. Legacy plaintext still reads (migration path, re-encrypts on next save); a broken/key-lost envelope degrades to an unset password (decrypt returns null → default, never surfaces ciphertext); an empty password stays plaintext. The persisted-`huk1:`-envelope XML check itself is NOT possible on this box (shell uid 2000 = no root; the `el2` sandbox is unreadable) — the on-device self-test is the substitute proof. One review-mitigation architecture item is done, one remains: R8 (split the >600-line pages — DownloadsPage/SettingsPage/AddTorrentPage — into a SessionController + sub-components) is **DONE** — DownloadsPage now delegates its session lifecycle / 1s poll / D3 wake lock / D4 connectivity / torrent CRUD to a `SessionController` (constructor-DI for host tests, `tests/session-controller.test.ts`), so a device/@kit-free test drives the controller. All three pages are now under 600 lines (DownloadsPage 543, SettingsPage 569, AddTorrentPage 576) with presentational sub-components (FilePreview, TorrentStatusBanner, SettingsLoadingState, SettingsErrorBanner, SettingsResetDialog, SandboxSettingRow, PublishFolderRow). Verified: ArkTS build green + 76/76 host vitest. **R9 is now fully DONE** (layering inversion + dedup + dead-method removal, Tasks #21/#24). Models are pure data — `TorrentInfo` and `TorrentFile` no longer import `NativeBridge`; every native read routes through the `TransmissionSession` facade (`getAllTorrents`/`applyStatBrief` for the poll, new `refreshFileStat(torrentId, file)` for the per-file tree read, `setFileWanted` for DnD). The dead model methods (`TorrentInfo.refreshStats`, `TorrentFile.listFromNative/setPriority/setWanted/refreshStats`) were removed; `FileTreePage` calls `session.refreshFileStat(this.torrentId, f)`. The relocated parse surfaced + fixed a latent piece-bitmap infinite-loop bug (a native bitmap whose 64th piece is set reads as a negative int64 — `applyFileStat` now masks with `BigInt.asUintN(64, …)` before the Kernighan popcount). Verified: build green + **80/80 host vitest** (new `tests/transmission-file-stat.test.ts`) + ohosTest module compiles (`NativeBridge.test.ets` cleaned to the 26-method surface; the module now builds after R9's dead-method removal had left it referencing removed wrappers).

## Critical Docs

| Reference | Content |
|-----------|---------|
| `docs/07-development-plan.md` | Full milestone plan + task breakdown (ground truth) |
| `docs/08-java-to-arkts-mapping.md` | 65 Java files → ArkTS mapping |
| `docs/01-native-bridge-and-core-engine.md` | 40 N-API methods spec, C++ file inventory |
| `docs/06-feature-map-and-gap-analysis.md` | Feature priorities, deferred list |
| `docs/12-tracker-connect-debugging.md` | Tracker connect failure investigation + multicast-permission research |
| `docs/M0-kickoff.md` | M0 execution checklist |
| `design/tokens.css` | CSS design tokens (reference for ArkTS Colors constant) |
| `design/demo.html` | Interactive UI prototype |
