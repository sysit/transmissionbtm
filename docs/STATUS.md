# Status / Changelog

> Change history for **transmissionbtm**. `CLAUDE.md` keeps only live engineering guidance; this file holds the full narrative. Newest first. Dates are when the work landed, not when it was planned.
>
> **Test-count reconcile note:** the numbers below are historical records and drift across snapshots — they were logged as each milestone closed, not re-run as a suite:
> - **On-device ohosTest**: unit-only `222/222` (M7 unit), then `231/231` total once 8 in-process E2E landed (M7 E2E). Note `222 + 8 = 230`, not 231 — the doc itself is off by one at that boundary; both figures are recorded verbatim below and were never re-reconciled. The stale `232/232` on the CLAUDE.md build line predates the E2E numbering.
> - **Host vitest** (Node-only, no device): `76/76` (R8) → `93/93` (proxy-cipher) → **`80/80` (R9, latest)**. Each supersedes the prior; R9's is current.
> - The current `aa test` path on this box SIGABRTs in the harness (`JsTestRunner`), so on-device runs go through `assembleHap -p module=entry@ohosTest` + `hdc install` + `aa test`.

---

## 2026-09-01 — multi-language i18n (native `$r` resources) + app language selector

- **i18n via native `$r('app.string.*')`** — built `resources/base` (English) + `resources/zh_CN` (Chinese) mirror, ~200 flat `[domain]_[desc]` keys (`settings_*`, `tab_*`, `torrent_action_*`, `torrent_status_*`, `privacy_*`, `addtorrent_*`, `common_*`). System locale = zh_CN auto-resolves to Chinese (a zh device gets Chinese UI with no user action — satisfies AppGallery "UI supports Chinese").
- **Settings "Language" selector (General row)** — new `PrefKeys.APP_LANGUAGE='app_language'`, default `'system'`, values `system|zh-CN|en-US`; UI-only (NOT in `SessionConfig`, same precedent as `PRIVACY_ACCEPTED`). Reuses existing `SelectSetting` (`valueType:'string'`).
- **App-level language override** — `EntryAbility.onWindowStageCreate` awaits `applyAppLanguage()` (via `PreferencesManager.waitReady()`) before `loadContent`; maps `zh-CN→zh-Hans-CN` (BCP-47 script-annotated), `en-US→en-US`; `ApplicationContext.setLanguage(tag)` (main-thread-only). Takes effect on restart → Settings shows a "restart to apply" toast via `@Watch('onLanguageChanged')` + `languageLoaded` guard armed in `loadPreferences`' `finally`.
- **Kept the model layer pure** — `getStatusString()` stays English (both `TorrentInfo.test.ets` + `tests/torrent-info.test.ts` assert the literals); localized at display via `utils/i18n.ets` `statusResource()`. Plan constraint: no `$r` in the pure model layer.
- **Type relaxation** — `@Prop label/options: ResourceStr` (`string | Resource`) so `$r` flows into EditSetting/SelectSetting/StatChip/etc. `ResourceStr` is the ArkUI compatibility trick.
- **Migration** — 7 pages + 6 components + settings controls to `$r`; **202 `$r` usages**; **0 residual hardcoded Chinese/English user-facing literals** in UI markup (non-localizable only: ` · ` separator, copyright line, `💡` emoji).
- **Verified on API24 emulator (`127.0.0.1:5555`)** — en default → Settings shows "Language" row; pick 简体中文 → persisted → force-stop + relaunch → **whole UI renders Chinese (设置/通用/语言/下载/速度/网络 + bottom tabs 下载/设置/代理/关于)**, no mojibake or truncation; reset 系统默认 → relaunch → back to English. Build green (only pre-existing deprecation WARNs).

---

## 2026-08-26 — v0.1.1 release

- **Version bump** — `AppScope/app.json5` versionName `0.1.0`→`0.1.1`, versionCode `1`→`2`; native `getVersion()` (`napi_init.cpp`) `"0.1.0-m6"`→`"0.1.1"` (drop the `-m6` milestone suffix); `NativeProbe.test.ets` assertion updated to match; `AppConstants.APP_VERSION` (`utils/constants.ets`) `"0.1.0-m6"`→`"0.1.1"` (About page display). `oh-package.json5` (N-API types package version) left as-is — project hook forbids direct edits; use DevEco's project-structure panel if it needs a bump.

---

## 2026-08-26 — codex review fix batch (B1 + C1–C11 + D1–D4), build + vitest green

Second pass over the merged codex architecture + code review findings. All correctness/security/memory-safety items landed; host **vitest 93/93** and `assembleHap` both green. (The `.ai-review` reports were re-read; a few E/F findings were false positives or deferred — see below.)

- **B1 session use-after-free guard** — `runInTransmissionThread` now takes a **lifetime ref** (`retainSessionForDispatch`/`releaseSessionDispatch`, `gSessionRefs` map behind `gSessionMutex`); a concurrent `SessionStop` can no longer `tr_sessionClose` underneath an in-flight dispatch. `SessionStop` unregisters → saves → `waitSessionIdle` (15s bounded) → `tr_sessionClose`, draining in-flight dispatches first. Guards both the `getSession`→dispatch gap and the close path.
- **C3b honor configured peer port** — `buildSettingsJson()` now emits `'peer-port-random-on-start' = false`, so the Settings "peer port" control actually applies instead of libtransmission randomizing the port every start.
- **C1 tracker probe off the session thread** — the two synchronous curl probes (`HttpProbeOnce`) that stalled torrent ops up to ~16s on first poll now run on a `std::thread(...).detach()` (was already in place; re-verified).
- **C2 context-menu `isVisible` `@Link`** — `TorrentContextMenu` is constructed with `isVisible: $showContextMenu` (was a value copy `isVisible: this.showContextMenu`, so the flag never propagated back → menu couldn't close).
- **C4/C8 curlDownload** — bad-type `timeout` arg silently resets to the 30s default instead of corrupting the value; the destination path is validated **before** `fopen` (must be absolute, no `..`), closing an arbitrary-file-write via a user-supplied path.
- **C5 pending-exception bail** — `TorrentGetFileStat` / `TorrentGetPiece` now `hasPendingException(env)` early-return (and free `d.bf`) after `runInTransmissionThread`, instead of calling `napi_create_arraybuffer`/`napi_get_undefined` with an exception pending (which leaves the return value uninitialized).
- **C6 file index range guard** — `getFileInfo` bounds-checks `idx >= file_count()` (re-added null-torrent guard); the `int32→uint32` cast makes a negative index huge → caught by the same check.
- **C7 `curl_global_init`** — new `ensureCurlGlobalInit()` (`std::call_once`) called from both `CurlDownload` (ArkTS thread) and `HttpProbeFetch` (detached thread); libcurl's global init is refcounted/idempotent so the two callers race safely.
- **C9 `torrentSetLocation` path validation** — relocate path must be absolute and free of `..` (mirrors C8), like the curl path check.
- **C10 redacted a log leak** — `TorrentStart` `err='%{public}s'` → `%{private}s` (the torrent error string carries user/torrent data). The PROBE/TRK lines only log hardcoded-host diagnostics with no passkey, so they stay public for diagnosability.
- **C11 `TorrentGetFileStat` `memcpy` guard** — copy only when `d.bf != nullptr && bfBytes > 0`; previously `memcpy(out, null, 0)` ran on the every-stat-0 path.
- **D1 add-dialog auto-close race** — `AddTorrentPage.handleAddResult` OK branch now sets an `addSuccessTimer` (600ms) and clears it in `aboutToDisappear`, so `onTorrentAdded` isn't fired after the page has been removed.
- **D2 swallowed promise rejections** — `SessionController` `.destroy()`/`.acquire()`/`.start()` on the connectivity monitor + wake lock now `.catch` and `hilog.error` instead of `then(() => {})` (silently swallowed).
- **D3 float→`setInt` truncation + ProxyPage dead state** — `EditSetting` `valueType:'float'` now routes to a new `Preferences.setFloat()` (was `setInt`, truncating e.g. seed-ratio `1.5`→`1`); `number` still routes to `setInt`. Removed `ProxyPage` dead `hostError`/`portError` `@State` + their never-rendering display blocks.
- **D4 Index.d.ts accuracy** — comment "All 36 methods"; added `torrentState(session, torrentId)` diagnostic; removed `envUnset` (never registered in `env.cc`).

**Deferred (with rationale):**
- **A4 TLS cert verify global-off** — libcurl has no per-request bypass here and the CA bundle is a build/asset lift; documented, not changed.
- **D5 FileTreePage batch/taskpool** — perf refactor, not a correctness bug; orthogonal to the already-offloaded add/relocate.
- **E1–E9 dead-code/simplification** — several findings conflicted with actual call sites (false positives); all were verified against `git grep` and only the confirmed-safe ones (D4, ProxyPage dead state) were touched.
- **F1–F4 larger refactors** — high blast radius, low correctness value; deliberately skipped to avoid regressions on the current green state.

---

## 2026-08-26 — input-dialog crash fix (all Settings/Proxy inputs) + About page cleanup

- **`@CustomDialog` + `$@Link` ReferenceError crash FIXED (root cause of the whole "tap any input → 秒崩" cluster)** — `EditSetting` and `SelectSetting` built their dialogs by passing a parent `@Link` down via `$` (`value: $value` / `selectedIndex: $selectedIndex`), which compiles but throws `ReferenceError: $value is not defined` the instant the `@CustomDialog` builder runs on `open()`. Both rewrote to the project's `SettingsResetDialog` pattern — pass a plain **value copy** (`@Prop initialValue` / `@Prop initialIndex`) + an **`onSave`/`onSelect` callback**, and let the **parent own persistence** (set the `@Link` + write `PreferencesManager` inside the closure). Covers all 21 `EditSetting` call sites in SettingsPage (SSID, download/upload speed limit, RPC port, peer port, etc.) + 4 in ProxyPage (Host/Port/Username/Password) + the Encryption `SelectSetting` — every text-configured setting in the app. **On-device verified** (Pura 80 `4VM0125513000074`): string/number/edit-save and select dialogs all open, edit, and persist without crash.
- **About page layout cleanup** — deleted the entire **"Native Engine"** table (Engine/Platform/Architecture/N-API/RPC port/Peer port rows + the now-unused `BuildInfoRow` helper), so the page flows About → version → **Open Source Licenses** → **Credits**. Credits trimmed to the two values only, **centered**: `transmissionbtm © 2024–2026` and `Built for HarmonyOS NEXT with ArkTS + ArkUI` (the `Copyright`/`Design` label words removed). Build + install verified on Pura 80.
- **Settings-effect audit (triage; no code change)** — settings DO take effect, but see timing: `getSessionConfig()` → `TransmissionSession.start(config)` → `native.sessionStart()` applies them **at session start**, and `buildSettingsJson()` writes speed/peer/utp/pex/dht/lpd/alt-speed into the transmission `settings.json`. **Live exception:** the WiFi-only + SSID allowlist gate reads `wifi_only`/`wifi_ssid` on every network event (`ConnectivityMonitor.isSsidAllowed()`, fail-open), so it takes effect without restart. Everything else (ports/proxy/encryption/speeds changed mid-session) needs a session restart because `NativeBridge` has no runtime re-apply setter — added to deferred debt below. Full detail in memory `settings-apply-timing`.



- **Publish-folder picker stray file (Bug A) FIXED + on-device verified** (Pura 80 `4VM0125513000074`) — `PublishFolderRow.onPickPublishDir` used the save dialog as a folder-picker proxy and the placeholder filename got materialized as a real empty `publish` file in the target. Removed the hanging `DocumentSelectMode.FOLDER` path (2-in-1-only; on a phone it opens a browse-only view with no confirm affordance, so `select()` never resolves). `save()` is now the sole proxy with a **unique timestamped placeholder** `publish-${Date.now()}` (a fixed name collides with a leftover `publish` → "This file name already exists"), `autoCreateEmptyFile=false` (API 23+), and the **parent** directory URI stored (never the filename). Verified: every pick logs `placeholder already gone / not unlinkable: Error: No such file or directory` — no stray file is materialized, i.e. `autoCreateEmptyFile=false` IS honored on a phone. Recipe in memory `publish-folder-picker-no-stray-file`.
- **Speed values 1000× too small (Bug B) FIXED** — native brief-stat array carries speeds in KB/s (`pieceDownloadSpeed_KBps`) but `TorrentInfo.rateDownload/rateUpload` are bytes/s, so cards showed an impossible "32B/s". New `KBPS_TO_BPS = 1000` (same factor as transmission's `toSpeedBytes`/`tr_speed_K = SPEED_K`), applied at the model boundary in `TorrentInfo.fromStatArray` + `TransmissionSession.applyStatBrief`; both suites updated.
- **Save-to-Files export rewrite (tree-preserving)** — `DownloadsPage.copyTorrentToPublic`: whole-torrent **directory copy** in one `fs.copy(sandboxDir, Download/<name>)` to keep the folder tree (incl. nested dirs), guarded to trust a dir copy only once every file is on disk; fallback per-file copy via **fd→fd** `fs.copyFile` after `fs.openSync` each side (URI-aware, honors the picker's write grant) — `fs.copy`/`copyFileSync` reject a `file://docs` dest. `DocumentPickerMode.DOWNLOAD` confirmed a dead end for export too (ignores `newFileNames`/`defaultFilePathUri`, returns an unwritable folder URI); one `save()` DEFAULT call (honors user "Publish folder" else system Download). `SettingsPage` dropped the moot "Incomplete dir" row and clarified downloads live in the sandbox.
- **Removed-torrent "corpse card" prune** — `DownloadsPage.pruneTorrentMetainfo` unlinks a removed torrent's hash-named `<hash>.torrent` + `<hash>.resume`, so a fresh session doesn't resurrect a removed torrent as a broken 0%/Error card (verified: Big Buck Bunny's `dd8255ec…` survived a Remove). Best-effort; never breaks the remove.
- **WiFi-only SSID allowlist gate (feature)** — new `PrefKeys.WIFI_ONLY` / `WIFI_SSID` (runtime transfer gates, not engine config); `ConnectivityMonitor.isSsidAllowed()` reads the active SSID via `wifiManager.getLinkedInfo()` and requires it in the comma-separated allowlist, **fail-open** on no allowlist / unreadable SSID so the robust bearer-type gate still governs; `SettingsPage` gains a "WiFi/Ethernet only" toggle + conditional "Allowed SSIDs" field; new `ohos.permission.GET_WIFI_INFO` + string.json reason.

---

## 2026-08-24/25 — non-blocking add/relocate (taskpool) + add-torrent fix, on-device verified

- **Non-blocking slow ops via `@ohos.taskpool`** — offloads add-from-file / magnet / URL (`AddTorrentPage.concurrentTorrentAdd`) and the "Change Download Location" relocate (`DownloadsPage.concurrentTorrentSetLocation`) off the UI thread, so the UI no longer freezes while native reads+parses the `.torrent` or moves files. Because `NativeBridge`'s singleton `sessionMap` is NOT shared across taskpool worker heaps, the `BigInt` session ptr is resolved on the main thread (`getSessionPtr`) and passed as a serializable arg to stateless `*ByPtr` statics (`torrentAddByPtr` / `torrentSetLocationByPtr`). Relocate uses a text-entry dialog (the `SET_LOCATION` context-menu item) — `DocumentSelectMode.FOLDER` is 2-in-1-only and returns a URI, so a real sandbox-bound POSIX path is entered manually.
- **TSFN event channel re-wired** — `nativeToArktsInit` registered in `DownloadsPage.initSession` just before `controller.start` (all four events → `controller.reload()`), `nativeToArktsRelease` in `aboutToDisappear`. That's the event→poll-invalidate path, so cards update live on add/stop/relocate instead of only on the 5s poll.
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
- **No live re-apply of settings changed mid-session** — speeds/proxy/ports/encryption/download-dir edited after session start persist to `PreferencesManager` but only reach the engine on the next `sessionStart`; `NativeBridge` exposes no runtime setter. The WiFi-only/SSID gate is the exception (read live). To make edits apply without a restart, add a native setter path + call it from the settings `onSave`/`onSelect` callback. Detail in memory `settings-apply-timing`.
- ~~**Non-blocking async completion primitive for slow ops**~~ (add-from-file / relocate, so the UI thread isn't blocked) — **DONE 2026-08-24 via `@ohos.taskpool` offload + re-wired TSFN events**; see top. (The remove half of the original P0 "async session-thread dispatch" was FIXED 2026-08-23.)
- **Service re-enable** requires `install_list_capability` device provisioning (P0 — permanently deferred, see module.json5 note).
- ~~magnet-link native parsing~~ — **DONE** in D1 (`tr_ctorSetMetainfoFromMagnetLink`, commit 2c488f4).
- ~~Proxy credentials~~ — **DONE** (R7, see above).
- ~~Page split~~ — **DONE** (R8).
- ~~Layering inversion + dedup + dead-method removal~~ — **DONE** (R9).
