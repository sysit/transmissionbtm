# Status / Changelog

> Change history for **transmissionbtm**. `CLAUDE.md` keeps only live engineering guidance; this file holds the full narrative. Newest first. Dates are when the work landed, not when it was planned.
>
> **Test-count reconcile note:** the numbers below are historical records and drift across snapshots — they were logged as each milestone closed, not re-run as a suite:
> - **On-device ohosTest**: unit-only `222/222` (M7 unit), then `231/231` total once 8 in-process E2E landed (M7 E2E). Note `222 + 8 = 230`, not 231 — the doc itself is off by one at that boundary; both figures are recorded verbatim below and were never re-reconciled. The stale `232/232` on the CLAUDE.md build line predates the E2E numbering.
> - **Host vitest** (Node-only, no device): `76/76` (R8) → `93/93` (proxy-cipher) → **`80/80` (R9, latest)**. Each supersedes the prior; R9's is current.
> - The current `aa test` path on this box SIGABRTs in the harness (`JsTestRunner`), so on-device runs go through `assembleHap -p module=entry@ohosTest` + `hdc install` + `aa test`.

---

## 2026-08-25 — publish/export on-device fixes + WiFi-only SSID gate

- **Publish-folder picker stray file (Bug A) FIXED + on-device verified** (Pura 80 `4VM0125513000074`) — `PublishFolderRow.onPickPublishDir` used the save dialog as a folder-picker proxy and the placeholder filename got materialized as a real empty `publish` file in the target. Removed the hanging `DocumentSelectMode.FOLDER` path (2-in-1-only; on a phone it opens a browse-only view with no confirm affordance, so `select()` never resolves). `save()` is now the sole proxy with a **unique timestamped placeholder** `publish-${Date.now()}` (a fixed name collides with a leftover `publish` → "This file name already exists"), `autoCreateEmptyFile=false` (API 23+), and the **parent** directory URI stored (never the filename). Verified: every pick logs `placeholder already gone / not unlinkable: Error: No such file or directory` — no stray file is materialized, i.e. `autoCreateEmptyFile=false` IS honored on a phone. Recipe in memory `publish-folder-picker-no-stray-file`.
- **Speed values 1000× too small (Bug B) FIXED** — native brief-stat array carries speeds in KB/s (`pieceDownloadSpeed_KBps`) but `TorrentInfo.rateDownload/rateUpload` are bytes/s, so cards showed an impossible "32B/s". New `KBPS_TO_BPS = 1000` (same factor as transmission's `toSpeedBytes`/`tr_speed_K = SPEED_K`), applied at the model boundary in `TorrentInfo.fromStatArray` + `TransmissionSession.applyStatBrief`; both suites updated.
- **Save-to-Files export rewrite (tree-preserving)** — `DownloadsPage.copyTorrentToPublic`: whole-torrent **directory copy** in one `fs.copy(sandboxDir, Download/<name>)` to keep the folder tree (incl. nested dirs), guarded to trust a dir copy only once every file is on disk; fallback per-file copy via **fd→fd** `fs.copyFile` after `fs.openSync` each side (URI-aware, honors the picker's write grant) — `fs.copy`/`copyFileSync` reject a `file://docs` dest. `DocumentPickerMode.DOWNLOAD` confirmed a dead end for export too (ignores `newFileNames`/`defaultFilePathUri`, returns an unwritable folder URI); one `save()` DEFAULT call (honors user "Publish folder" else system Download). `SettingsPage` dropped the moot "Incomplete dir" row and clarified downloads live in the sandbox.
- **Removed-torrent "corpse card" prune** — `DownloadsPage.pruneTorrentMetainfo` unlinks a removed torrent's hash-named `<hash>.torrent` + `<hash>.resume`, so a fresh session doesn't resurrect a removed torrent as a broken 0%/Error card (verified: Big Buck Bunny's `dd8255ec…` survived a Remove). Best-effort; never breaks the remove.
- **WiFi-only SSID allowlist gate (feature)** — new `PrefKeys.WIFI_ONLY` / `WIFI_SSID` (runtime transfer gates, not engine config); `ConnectivityMonitor.isSsidAllowed()` reads the active SSID via `wifiManager.getLinkedInfo()` and requires it in the comma-separated allowlist, **fail-open** on no allowlist / unreadable SSID so the robust bearer-type gate still governs; `SettingsPage` gains a "WiFi/Ethernet only" toggle + conditional "Allowed SSIDs" field; new `ohos.permission.GET_WIFI_INFO` + string.json reason.

---

## 2026-08-24/25 — non-blocking add/relocate (taskpool) + add-torrent fix, on-device verified

- **Non-blocking slow ops via `@ohos.taskpool`** — offloads add-from-file / magnet / URL (`AddTorrentPage.concurrentTorrentAdd`) and the "Change Download Location" relocate (`DownloadsPage.concurrentTorrentSetLocation`) off the UI thread, so the UI no longer freezes while native reads+parses the `.torrent` or moves files. Because `NativeBridge`'s singleton `sessionMap` is NOT shared across taskpool worker heaps, the `BigInt` session ptr is resolved on the main thread (`getSessionPtr`) and passed as a serializable arg to stateless `*ByPtr` statics (`torrentAddByPtr` / `torrentSetLocationByPtr`). Relocate uses a text-entry dialog (the `SET_LOCATION` context-menu item) — `DocumentSelectMode.FOLDER` is 2-in-1-only and returns a URI, so a real sandbox-bound POSIX path is entered manually.
- **TSFN event channel re-wired** — `nativeToArktsInit` registered in `DownloadsPage.initSession` just before `controller.start` (all four events → `controller.reload()`), `nativeToArktsRelease` in `aboutToDisappear`. That's the `transmissionbtc`-style event→poll-invalidate path, so cards update live on add/stop/relocate instead of only on the 5s poll.
- **Add-torrent "could not access the selected file" FIXED + on-device verified** (Pura 80 `4VM0125513000074`) — two bugs behind one symptom. (1) `onBrowseFile` used a **no-arg** `DocumentViewPicker`, whose URI `fs.openSync` can't read back in the app's own context — now `getContext(this)` like the two other working pickers (PublishFolderRow, DownloadsPage). (2) Once readable, `copyPickerUriToCache` failed with **`File name too long` (ENAMETOOLONG)** on long Chinese M-Team names (>255-byte NAME_MAX) — new `safeCacheName()` bounds the throwaway cache filename (native parses the true name from the metainfo) to a short `torrent_<ts>.torrent`, preserving the `.torrent` extension. Verified end-to-end: picked the real 91大神系列 `.torrent` (16.7 GB, ~165 KB) from public Download → added → immediately Downloading at 24.5 KB/s.

---

## 2026-08-23 — two real-engine fixes (commit `822b252`, then P0 piece work)

- **Real 4.1.0 stable engine** — engine rebuilt from the actual `4.1.0` stable tag (`2724011`), replacing the earlier 4.2.0-dev tree that only *appeared* to be 4.1.0 via a version-masked `version.h`. M-Team requires 4.1.x (`mteam只支持4.1.x stable版本`). Bridge C++ adapted to 4.1 API (`tr_stat` pointer + camelCase, `tr_ctorSetMetainfo*` `tr_error*` arg, `tr_torrentRemove` 6-arg, raw-callback setters, `TR_UP`/`TR_DOWN`); CRC sub-dep switched madler-crcany → **Google `crc32c`** (`libcrc32c.a`, `crc32c::Extend`); the C++20 oh-compat.h force-include removed (4.1.0 is C++17, no ranges). `crypto-utils.h` (`WITH_OPENSSL`) and the generated `version.h` (re-hand-set `-TR4100-`/`4.1.0`) survived the header regen by re-apply. **BUILD SUCCESSFUL**; on-device verified: M-Team announce `res='Success'`, tracker `seed=/leech=` answered, session + HUKS `selfTest OK`. Rebuild recipe in memory `transmission-410-engine-build`.
- **ArkUI 5s live-refresh** — torrent cards re-render every 5s (a `TorrentVM` `@Observed` wrapper bound via `@ObjectLink`, mutated in place each poll by `DownloadsPage.syncTorrentVms`, so ForEach reuses cards and updates live instead of only on restart). `SessionController` poll cadence moved 1s → 5s. Verified: `[DBG] stat` at 5s cadence + reactive `ForEachNode skip mark dirty`; seeding torrent shows live "Seeding". About page's stale "4.0.6" engine string corrected to **4.1.0**.
- **P0 remove-race (double-dispatch) FIXED** — `torrentRemoveFunc` ran ON the session thread but called `tr_torrentRemove`, which re-dispatches a second session-thread task and returns immediately, so `sem_wait` unblocked before the removal completed. It now calls `tr_torrentRemoveInSessionThread` (inline, completes on the session thread), so sync-after-remove is safe and the UI poll just masks nothing-for-removal.
- **Piece-priority FIXME resolved (file-level)** — 4.1 has no per-piece priority setter (`piece_priority()` is read-only, derived from the containing file). The reserved `torrentSetPiecesHiPri` now maps a `[first,last]` piece range to the set of files whose piece span overlaps it and raises those files to `TR_PRI_HIGH` via `tr_torrentSetFilePriorities`.

## 2026-08-22 — proxy credentials to HUKS (R7, Tasks #19/#25)

Two on-disk exposures existed:
- **(a)** plaintext `proxy_password` as its own `PrefKeys.PROXY_PASSWORD` entry in the app-sandbox `el2` preferences XML (LOW severity, non-world-readable);
- **(b)** the composed `proxy-url` (with inline `user:pass@`) built by `TransmissionSession.buildSessionSettings()` was ALSO written to `<settingsDir>/settings.json` via `tr_sessionSaveSettings` in native `SessionStart` + `SessionStop`, because transmission persists `TR_KEY_proxy_url` (session-settings.h Field).

R7 fixed BOTH:
- **Preferences store → HUKS AES-256-GCM.** `entry/src/main/ets/security/ProxyCipher.ets` (marker `huk1:` + `ProxyCipher` interface + plaintext `LegacyProxyCipher` fallback) and `security/HukProxyCipher.ets` (GCM pattern ported from v2rayHM's proven `SecureStorage.ets`: IV via `HUKS_TAG_NONCE`, 1-byte AAD via `HUKS_TAG_ASSOCIATED_DATA`, tag split from ciphertext and passed via `HUKS_TAG_AE_TAG`, `HUKS_TAG_DIGEST=HUKS_DIGEST_NONE`, `decodeToString` not `decodeWithStream`). `Preferences.ets` keeps a default `LegacyProxyCipher` (kit-free, host-testable) and injects the HUKS cipher via `setPasswordCipher()`; `setString`/`getString` for `PrefKeys.PROXY_PASSWORD` now encrypt-on-write / decrypt-on-read, `setSessionConfig` routes it through `setString`, and `EntryAbility.onCreate` injects the cipher + runs a startup self-test.
- **settings.json → strip before save.** Native `transmission.cc` gained `StripProxyUrlFromSettings()` (erases `TR_KEY_proxy_url` from a `tr_variant` Map) and strips it at BOTH save sites — right after `tr_sessionInit` (the live session keeps the proxy, applied at init) and in `SessionStop` (which re-reads session settings). The app re-applies proxy from its HUKS-encrypted preferences on every start, so the snapshot losing it is harmless. RPC credentials are intentionally left (they're the app's own server config that transmission persists by design).

**Verified:** main HAP + `entry@ohosTest` both BUILD SUCCESSFUL; host vitest at this point `93/93` (new `tests/proxy-cipher.test.ts` + `tests/preferences-proxy-cipher.test.ts` driving a fake cipher against an in-memory `@kit.ArkData` mock); on-device emulator `aa start` + hilog → `HukProxyCipher: selfTest OK` / `transmissionbtm: HUKS selfTest OK` — proving the AES-256-GCM tag/IV/alias round-trip on device. Legacy plaintext still reads (migration path, re-encrypts on next save); a broken/key-lost envelope degrades to an unset password (decrypt returns null → default, never surfaces ciphertext); an empty password stays plaintext. The persisted-`huk1:`-envelope XML check itself is NOT possible on this box (shell uid 2000 = no root; the `el2` sandbox is unreadable) — the on-device self-test is the substitute proof.

## R8 — page split + SessionController

Split the >600-line pages (DownloadsPage/SettingsPage/AddTorrentPage) into a `SessionController` + sub-components. DownloadsPage now delegates its session lifecycle / poll / D3 wake lock / D4 connectivity / torrent CRUD to a `SessionController` (constructor-DI for host tests, `tests/session-controller.test.ts`), so a device/@kit-free test drives the controller. All three pages now under 600 lines (DownloadsPage 543, SettingsPage 569, AddTorrentPage 576) with presentational sub-components (FilePreview, TorrentStatusBanner, SettingsLoadingState, SettingsErrorBanner, SettingsResetDialog, SandboxSettingRow, PublishFolderRow). Verified: ArkTS build green + `76/76` host vitest.

## R9 — layering inversion + dedup + dead-method removal (Tasks #21/#24)

Models are pure data — `TorrentInfo` and `TorrentFile` no longer import `NativeBridge`; every native read routes through the `TransmissionSession` facade (`getAllTorrents`/`applyStatBrief` for the poll, new `refreshFileStat(torrentId, file)` for the per-file tree read, `setFileWanted` for DnD). The dead model methods (`TorrentInfo.refreshStats`, `TorrentFile.listFromNative/setPriority/setWanted/refreshStats`) were removed; `FileTreePage` calls `session.refreshFileStat(this.torrentId, f)`. The relocated parse surfaced + fixed a latent piece-bitmap infinite-loop bug (a native bitmap whose 64th piece is set reads as a negative int64 — `applyFileStat` now masks with `BigInt.asUintN(64, …)` before the Kernighan popcount). Also removed 7 dead ArkTS wrappers: `getEncryptionMode`, `transmissionVersion`, `torrentSetDnd`, `hashStringToBytes`, `envSet`, `nativeToArktsInit`, `nativeToArktsRelease` (native C++ registrations stay, harmless unreachable). Verified: build green + **`80/80` host vitest** (new `tests/transmission-file-stat.test.ts`) + ohosTest module compiles (`NativeBridge.test.ets` cleaned to the 26-method surface).

---

## Milestones M0–M7 (closed)

- [x] DevEco Studio project scaffold (M0.1–0.5)
- [x] N-API module skeleton with `getVersion()` returning `"0.1.0-m6"`
- [x] All ArkTS source files written (production code, 33 files)
- [x] All C++ N-API source files written (8 files, M1_FULL_BRIDGE active)
- [x] HAP builds and signs successfully (12MB signed HAP)
- [x] Third-party native libs cross-compiled for OH arm64-v8a (18 `.a` files, Transmission 4.1.0 stable)
- [x] M1: N-API bridge → **35 native methods, 26 public NativeBridge methods** (dead surface removed in codex batch, Task #106; 7 more native methods pruned in E1; 7 more dead ArkTS wrappers removed in R9 — see above)
- [x] M2: Preferences & settings persistence (instant-apply, typed getter/setter)
- [x] M3: Torrent domain models (8 files: TorrentInfo, TorrentFile, TorrentDir, TransmissionSession, FileTreeModel, Preferences, SessionConfig, SessionState[SessionRunState only — SessionState class removed in E4]; legacy models Torrent/TorrentFs/TorrentStat/TorrentItem/TorrentExceptions/MediaInfo/NaturalOrderComparator deleted)
- [x] M4: Foreground service + connectivity monitor + wake lock
- [x] M5: Core UI (torrent list, detail, file tree, add flow, context menu)
- [x] M6: Settings UI + about + polish (loading states, error handling, reset)
- [x] Codex architecture + code review completed (`.ai-review/codex-review.md`); critical/high findings fixed (Tasks #98–107) — BUILD SUCCESSFUL (remaining deferred debt below)
- [x] M7 (unit): ohosTest wired (`hvigorw test` hangs at GenerateUnitTestResult — use `assembleHap -p module=entry@ohosTest` + `hdc install` + `aa test`). **222/222 tests pass on device** (Pura 80 `4VM0125513000074`). 7 initial failures fixed: `buildTree` now normalizes nested `file.name` to basename; 3 stale test assertions corrected (dirCount=3 subdirs, no STOPPING note, downloadedEver=haveValid per Task #104)
- [x] M7 (E2E, in-process): **8/8 in-process E2E tests pass on device** (Pura 80 `4VM0125513000074`). `FunctionalE2E.test.ets` drives the REAL libtransmission session via NativeBridge (exactly like DownloadsPage): 7.1 session lifecycle + suspend/resume, 7.2 file add + file listing, 7.8 DnD (setWanted → refreshStats priority=SKIP), 7.9 10 concurrent torrents, 7.11 relocation, 7.12 removal (with/without data). Base64-embedded local `.torrent` fixtures, network features disabled, per-test isolated settingsDir/downloadDir. The foreground service stays REMOVED (system-app-only on HarmonyOS NEXT — see module.json5 note); the session runs in-process. 7.3/7.4 (download integrity/sequential) need a reachable tracker+seed; 7.6 (boot auto-start) is impossible on a consumer device; 7.7 (WiFi-only) needs live network manipulation — all deferred.

### E2E-found bridge caveats
1. HarmonyOS `@ohos.buffer` `Buffer.buffer.slice()` returns an empty ArrayBuffer on pool-reused allocations — always copy via `buffer.from(buf)` before writing.
2. `tr_torrentRemove` previously dispatched to the session's own event thread and returned immediately — the torrent disappeared a few ms later (the UI saw it via its poll); tests had to poll, not assert synchronously. **Fixed 2026-08-23** (see top) — removal now completes inline on the session thread.

---

## v1.0 scope

7 milestones, 75 tasks. 22 features deferred to v1.1+ (UPnP/DLNA/SSDP, M3U, Watch Dirs, Dark Theme, RU locale, RSS, Alt Web UI, HTTP streaming server, bidirectional storage adapter).

## Deferred debt (codex review)

- **Save-to-public-Download keeps only the file, not the folder tree** — "export / save to Download" copies each torrent file individually via fd-based `fs.openSync`+`copyFile` into `Download/`, but does NOT recreate the torrent's subdirectory layout. The whole-directory `fs.copy(<sandboxDir>, file://docs/.../<name>)` attempt in `DownloadsPage.copyTorrentToPublic` fell through (`dir-copy failed err=No such file or directory`) — `fs.copy` needs both sides as valid URIs and the sandbox POSIX path isn't one; even when it runs, folder-tree preservation was never verified on-device (the intended test torrent, Big Buck Bunny, was deleted before a real-tree copy could be exercised). Files land flattened in Download. **遗留问题** — the folder tree is not preserved.
- ~~**Non-blocking async completion primitive for slow ops**~~ (add-from-file / relocate, so the UI thread isn't blocked) — **DONE 2026-08-24 via `@ohos.taskpool` offload + re-wired TSFN events**; see top. (The remove half of the original P0 "async session-thread dispatch" was FIXED 2026-08-23.)
- **Service re-enable** requires `install_list_capability` device provisioning (P0 — permanently deferred, see module.json5 note).
- ~~magnet-link native parsing~~ — **DONE** in D1 (`tr_ctorSetMetainfoFromMagnetLink`, commit 2c488f4).
- ~~Proxy credentials~~ — **DONE** (R7, see above).
- ~~Page split~~ — **DONE** (R8).
- ~~Layering inversion + dedup + dead-method removal~~ — **DONE** (R9).
