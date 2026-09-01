// transmissionbtm — DownloadsPage (main torrent list with 1s polling)
//
// Renders the torrent list and owns the overlay navigation (add / file-tree /
// context menu). Session side-effects (lifecycle, polling, wake lock,
// connectivity, torrent actions) are delegated to SessionController; this page
// keeps only the ArkUI @State and subscribes via the controller's
// onTorrents()/onLoading() callbacks. Sandbox path resolution and Save-to-Files
// stay here because they use the UI context (getContext) and the file picker.

import { hilog } from '@kit.PerformanceAnalysisKit';
import { TorrentInfo } from '../models/TorrentInfo';
import { SessionConfig } from '../models/SessionConfig';
import { PreferencesManager } from '../models/Preferences';
import { fileIo as fs, picker, fileUri } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';
import { promptAction } from '@kit.ArkUI';
import { taskpool } from '@kit.ArkTS';
import { TorrentCard } from '../components/torrent/TorrentCard';
import { TorrentVM } from '../components/torrent/TorrentVM';
import { TorrentContextMenu, TorrentAction } from '../components/torrent/TorrentContextMenu';
import { AddTorrentPage } from './AddTorrentPage';
import { FileTreePage } from './FileTreePage';
import { EmptyState } from '../components/ui/EmptyState';
import { formatSpeed } from '../utils/format';
import { Colors, FontSize, Spacing, Radius } from '../utils/constants';
import { WakeLockManager } from '../services/WakeLockManager';
import { ConnectivityMonitor } from '../services/ConnectivityMonitor';
import { SessionController } from '../services/SessionController';
import { NativeBridge } from '../bridge/NativeBridge';

const TAG = 'DownloadsPage';

// Save-to-Files export target (HarmonyOS NEXT public Download).
//
// A consumer app CANNOT write the public Download dir by permission on a phone:
// READ_WRITE_DOWNLOAD_DIRECTORY is user_grant but only supported on 2-in-1 /
// tablet — a phone rejects the runtime request (authResults=2, "device-type
// condition not met"), so it never appears in system settings (verified: the app
// shows only Notification + Internet). The device-independent, permission-free
// way to put a file into the user's Download is the system
// DocumentViewPicker.save() in DEFAULT mode: it honors newFileNames +
// defaultFilePathUri, creates the file, and returns a writable file://docs URI we
// then fs.copy() into. DOWNLOAD mode grants a writable DIRECTORY under
// Download/<bundleName> (it ignores newFileNames/defaultFilePathUri — you
// populate it yourself) — see copyTorrentToPublic.
/** A completed torrent file pending export: its sanitized publish name and the
 *  sandbox path to copy from. ArkTS forbids inline object-literal types, so this
 *  is a declared interface (arkts-no-obj-literals-as-types). */
interface FileJob {
  /** Leaf file name for the publish destination. */
  name: string;
  /** Torrent-relative directory part ('' when the file sits at the torrent root),
   *  reused verbatim to rebuild the downloaded tree in the public dir. */
  rel: string;
  /** Sandbox path to copy from. */
  src: string;
}

/**
 * Offload the blocking native torrentSetLocation (libtransmission moves the
 * torrent's files on disk) to a taskpool worker so the UI thread isn't frozen.
 * A worker has an isolated JS heap, so it can't resolve the session via the
 * NativeBridge singleton — pass the BigInt tr_session* pointer in and call the
 * stateless NativeBridge.torrentSetLocationByPtr.
 */
@Concurrent
function concurrentTorrentSetLocation(ptr: BigInt, torrentId: number, newDir: string): void {
  NativeBridge.torrentSetLocationByPtr(ptr, torrentId, newDir);
}

@Component
export struct DownloadsPage {
  @State torrents: TorrentInfo[] = [];
  // ArkUI-observable mirror of `torrents`, one TorrentVM per torrent, mutated
  // in place each poll so the reused ForEach cards re-render live (see TorrentVM).
  @State torrentVms: TorrentVM[] = [];
  @State isLoading: boolean = true;
  @State showAddPage: boolean = false;
  @State showFileTree: boolean = false;
  @State fileTreeTorrentId: number = 0;
  @State fileTreeTorrentName: string = '';
  @State showContextMenu: boolean = false;
  @State contextMenuTorrent: TorrentInfo | null = null;
  // Relocate dialog (Part B): show/hide + the target path typed by the user.
  @State showRelocateDialog: boolean = false;
  @State relocateTarget: string = '';
  // Owns the session lifecycle, 1s poll, D3 wake lock, D4 connectivity monitor,
  // and torrent CRUD. Wake lock + connectivity factory are supplied here (they
  // need device-only @kit modules); host tests omit them.
  private controller: SessionController = new SessionController(
    // session defaults to a real TransmissionSession
    undefined,
    new WakeLockManager(),
    (onAvailable: () => void, onLost: () => void) =>
      new ConnectivityMonitor(onAvailable, onLost)
  );
  // Resolved sandbox download dir (set in applySandboxPaths). Native libtransmission
  // writes torrent data here; the "Save to Files" action copies completed files from
  // here into the public Download dir via the picker.
  private sessionDownloadDir: string = '';
  /** <filesDir>/transmissionbtm — libtransmission torrent/resume state dir. */
  private sessionSettingsDir: string = '';
  // B2 (codex P1): set in aboutToDisappear and checked after each await in
  // initSession, so an async start that outlives page teardown can't wire the
  // native session + 5s poll with no page left to stop it.
  private isDisposed: boolean = false;

  aboutToAppear(): void {
    hilog.info(0x0001, TAG, 'DownloadsPage aboutToAppear');
    this.isDisposed = false;
    this.controller.onTorrents = (list: TorrentInfo[]) => {
      this.torrents = list;
      this.syncTorrentVms(list);
    };
    this.controller.onLoading = (loading: boolean) => { this.isLoading = loading; };
    this.initSession();
  }

  aboutToDisappear(): void {
    // B2 (codex P1): mark disposed so a still-running initSession short-circuits
    // after its next await instead of wiring a session/poll with no page left.
    this.isDisposed = true;
    // D3/D4 (docs/11): controller.stop() releases the wake lock, unregisters the
    // connectivity monitor, stops polling, and tears the session down.
    this.controller.stop();
    // Release the TSFN event channel before teardown so late events can't fire
    // into a torn-down session. Native re-init (nativeToArktsInit) resets the
    // channel on the next page appear, so this is safe to call each disappear.
    NativeBridge.getInstance().nativeToArktsRelease();
  }

  // ═══════════════════════════════════════════════════════════════════
  // Session lifecycle (the controller owns the live session; the page resolves
  // the sandbox paths it needs before handing config to start())
  // ═══════════════════════════════════════════════════════════════════

  private async initSession(): Promise<void> {
    try {
      // Read the persisted settings (Speed, Proxy, peer port, encryption, DHT/PEX,
      // blocklist, RPC, seeding limits) so the Settings/Proxy pages actually drive
      // the live engine. applySandboxPaths then overrides the three directory
      // fields to the app sandbox (those /storage/... defaults don't exist on device).
      const config = await PreferencesManager.getInstance().getSessionConfig();
      if (this.isDisposed) { return; }
      this.applySandboxPaths(config);
      this.sessionDownloadDir = config.downloadDir;
      // Re-wire native TSFN events → controller.reload(). MUST run before
      // sessionStart (sessionStart wires the tr_session RPC callbacks that fire
      // them). All four funnel to reload() (poll + invalidate), matching
// refresh-on-event behavior, so a move/add is never dropped.
      NativeBridge.getInstance().nativeToArktsInit(
        () => this.controller.reload(),
        () => this.controller.reload(),
        () => this.controller.reload(),
        () => this.controller.reload(),
      );
      if (this.isDisposed) { return; }
      await this.controller.start(config);
    } catch (e) {
      hilog.error(0x0001, TAG, 'Session start failed: %{private}s', String(e));
      this.isLoading = false;
    }
  }

  /**
   * HarmonyOS NEXT sandboxes third-party apps: the /storage/... paths in the
   * SessionConfig defaults do not exist on device (verified: /storage/downloads
   * is absent) and are not creatable by a sandboxed app. Resolve every session
   * directory to a writable app-sandbox path under filesDir and pre-create it.
   */
  private applySandboxPaths(config: SessionConfig): void {
    const filesDir = getContext(this).filesDir;
    config.downloadDir = `${filesDir}/downloads`;
    config.incompleteDir = `${filesDir}/downloads/.incomplete`;
    config.settingsDir = `${filesDir}/transmissionbtm`;
    this.sessionSettingsDir = config.settingsDir;
    this.ensureDir(config.downloadDir);
    this.ensureDir(config.incompleteDir);
    this.ensureDir(config.settingsDir);
  }

  private ensureDir(path: string): void {
    // fs.mkdirSync throws EEXIST on an existing dir even with recursion=true;
    // accessSync() returns existence, so guard before creating.
    if (!fs.accessSync(path)) {
      fs.mkdirSync(path, true);
    }
  }

  // ═══════════════════════════════════════════════════════════════════
  // Torrent actions (delegated to the controller; only UI state stays here)
  // ═══════════════════════════════════════════════════════════════════

  private onPause(t: TorrentInfo): void {
    this.controller.pause(t.id);
  }

  private onResume(t: TorrentInfo): void {
    this.controller.resume(t.id);
  }

  private onRemove(t: TorrentInfo): void {
    this.controller.remove(t.id);
    this.pruneTorrentMetainfo(t);
  }

  /**
   * Delete a removed torrent's leftover metainfo so a fresh session can't
   * resurrect it. native.torrentRemove (cpp, uneditable) frees the torrent from
   * the running session but leaves its resident .torrent and .resume files in
   * settingsDir — so the next session start re-loads it as a broken "corpse"
   * card (verified: Big Buck Bunny's dd8255ec… .torrent/.resume survived a
   * Remove and re-appeared at 0%/Error). We unlink both hash-named files after
   * the native remove. unlinkSync only targets exact files (guarded by hash
   * length), never the whole settings or downloads dir.
   */
  private pruneTorrentMetainfo(t: TorrentInfo): void {
    if (!t || t.hashString.length !== 40) {
      return;
    }
    const paths: string[] = [
      `${this.sessionSettingsDir}/torrents/${t.hashString}.torrent`,
      `${this.sessionSettingsDir}/resume/${t.hashString}.resume`,
    ];
    for (let i = 0; i < paths.length; i++) {
      try {
        if (fs.accessSync(paths[i])) {
          fs.unlinkSync(paths[i]);
        }
      } catch (e) {
        // Torrent metainfo cleanup is best-effort — never break the remove.
      }
    }
  }

  private onVerify(t: TorrentInfo): void {
    this.controller.verify(t.id);
  }

  private onReannounce(t: TorrentInfo): void {
    this.controller.reannounce(t.id);
  }

  private onShowFiles(t: TorrentInfo): void {
    this.fileTreeTorrentId = t.id;
    this.fileTreeTorrentName = t.name;
    this.showFileTree = true;
  }

  /**
   * D5 (docs/11): export a torrent's downloaded data into the user-visible
   * public Download directory via the system document-save picker.
   *
   * On a phone the READ_WRITE_DOWNLOAD_DIRECTORY permission is tablet/2-in-1-only
   * and rejected (auth=2), so the ONLY supported path is the DocumentViewPicker:
   * the app calls save() in DEFAULT mode with the real file name + the Download
   * default path, the system creates the file and returns a writable file://docs
   * URI, and we fs.copy the sandbox file into it. Unsupported-name collisions are
   * auto-suffixed by the system; the user confirms the save dialog once per call.
   */
  private async onSaveToFiles(t: TorrentInfo): Promise<void> {
    try {
      this.diagReset();
      this.diag(`onSaveToFiles name=${t.name}`);
      const copied = await this.copyTorrentToPublic(t);
      hilog.info(0x0001, TAG, 'SaveToFiles: final copied=%{public}d', copied);
      promptAction.showToast({
        message: copied > 0
          ? $r('app.string.downloads_toast_saved', copied)
          : $r('app.string.downloads_toast_no_files'),
        duration: 2000,
      });
    } catch (e) {
      hilog.error(0x0001, TAG, 'Save to Files failed: %{private}s', String(e));
      promptAction.showToast({
        message: $r('app.string.downloads_toast_save_failed', String(e)),
        duration: 2000,
      });
    }
  }

  /**
   * Append one line to a sandboxed diagnostic file (readable via hdc). The app's
   * hilog (domain 0x0001, tag DownloadsPage) does not reliably surface in
   * `hilog -d` on-device, so a file is the deterministic way to trace the export
   * path. Diagnostics are best-effort and must never break the export.
   */
  private diag(msg: string): void {
    try {
      const p = `${getContext(this).filesDir}/export-diag.txt`;
      const file = fs.openSync(p, fs.OpenMode.APPEND | fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY);
      fs.writeSync(file.fd, `${msg}\n`);
      fs.closeSync(file);
    } catch (e) {
      // ignore — diagnostics must not break the export
    }
  }

  /** Reset the sandboxed export diag file at the start of a save attempt. */
  private diagReset(): void {
    try {
      const p = `${getContext(this).filesDir}/export-diag.txt`;
      const file = fs.openSync(p, fs.OpenMode.CREATE | fs.OpenMode.TRUNC | fs.OpenMode.WRITE_ONLY);
      fs.closeSync(file);
    } catch (e) {
      // ignore
    }
  }

  /**
   * Build the list of on-disk (completed) files of `t`, ask the system picker to
   * create a destination for each in public Download (one confirmation dialog),
   * then fs.copy the sandbox source into each returned file://docs URI.
   *
   * Torrent metadata is untrusted → sanitize each relative path first (see
   * sanitizeRelPath) so a malicious name can't escape the download dir (read via
   * buildSandboxFilePath) or smuggle traversal into the picker file name. Returns
   * the count of files actually copied.
   */
  private async copyTorrentToPublic(t: TorrentInfo): Promise<number> {
    const files = this.controller.listFiles(t.id);
    this.diag(`copy begin nFiles=${files.length}`);

    // Rebuild the torrent's directory tree: mirror each completed (on-disk)
    // file's torrent-relative path under the granted public directory. This
    // preserves the folder hierarchy (incl. nested dirs like Preview/) AND
    // respects DnD (only on-disk files) — the prior per-file copy flattened
    // every file to the Download root, destroying the structure.
    const jobs: FileJob[] = [];
    for (let i = 0; i < files.length; i++) {
      const f = files[i];
      if (f.isDirectory) {
        continue;
      }
      const safeRel = this.sanitizeRelPath(f.name);
      if (!safeRel) {
        continue; // traversal / malformed / empty — skip this file
      }
      const srcAbs = this.buildSandboxFilePath(safeRel);
      if (!fs.accessSync(srcAbs)) {
        this.diag(`skip not-on-disk ${safeRel}`);
        continue; // not yet on disk (still downloading / in incomplete dir)
      }
      // Split into the directory part (kept verbatim → rebuilt as real folders)
      // and the file leaf. Separators are already normalized by sanitizeRelPath.
      const slash = safeRel.lastIndexOf('/');
      const rel = slash >= 0 ? safeRel.slice(0, slash) : '';
      const name = slash >= 0 ? safeRel.slice(slash + 1) : safeRel;
      jobs.push({ name, rel, src: srcAbs });
      this.diag(`job rel=${rel} name=${name} onDisk=true`);
    }
    if (jobs.length === 0) {
      this.diag('no on-disk files');
      return 0;
    }

    // One picker save() in DOWNLOAD mode → a writable DIRECTORY grant under the
    // public Download/<bundleName>/. Unlike DEFAULT mode (which returns one flat
    // per-file URI and flattens the tree), DOWNLOAD grants the DIRECTORY so we
    // can mkdir subfolders and rebuild the hierarchy. It ignores newFileNames /
    // defaultFilePathUri — we build the tree ourselves from the granted dir.
    // (The prior verdict that DOWNLOAD was a dead end was wrong: it doesn't make
    // named files, it grants a dir you populate yourself.)
    let uris: Array<string> = [];
    try {
      const opts = new picker.DocumentSaveOptions();
      opts.pickerMode = picker.DocumentPickerMode.DOWNLOAD;
      const pv = new picker.DocumentViewPicker(getContext(this) as common.UIAbilityContext);
      uris = await pv.save(opts);
      this.diag(`DOWNLOAD save returned ${uris.length} uris`);
    } catch (e) {
      // A picker throw is a real failure (permission / DOWNLOAD unsupported),
      // NOT "no files" — rethrow so the caller shows "保存失败: <err>".
      this.diag(`save picker error=${String(e)}`);
      throw new Error(String(e));
    }
    if (uris.length === 0) {
      this.diag('save returned 0 uris (user cancelled)');
      return 0;
    }

    // Critical: convert the granted DIRECTORY URI → a physical path. fs.open /
    // fs.copyFile reject a file://docs URI as a target ("input parameter is
    // invalid"); the real path (e.g. /storage/Users/currentUser/Download/<bundle>)
    // is writable because the picker granted it. Same URI→path rule as
    // AddTorrentPage.copyPickerUriToCache.
    let baseDir: string;
    try {
      baseDir = new fileUri.FileUri(uris[0]).path;
      this.diag(`baseDir=${baseDir}`);
    } catch (e) {
      this.diag(`FileUri convert err=${String(e)}`);
      throw new Error(String(e));
    }

    let copied = 0;
    for (let i = 0; i < jobs.length; i++) {
      const j = jobs[i];
      const destDir = j.rel.length > 0 ? `${baseDir}/${j.rel}` : baseDir;
      try {
        this.mkdirRecursive(destDir);
        const destPath = `${destDir}/${j.name}`;
        this.diag(`copy ${j.rel}/${j.name} -> ${destPath}`);
        const s = fs.openSync(j.src, fs.OpenMode.READ_ONLY);
        const d = fs.openSync(destPath, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
        try {
          await fs.copyFile(s.fd, d.fd);
          copied++;
          this.diag(`copied ok ${j.rel}/${j.name}`);
        } finally {
          try { fs.closeSync(s); } catch (e1) { /* ignore */ }
          try { fs.closeSync(d); } catch (e2) { /* ignore */ }
        }
      } catch (e) {
        this.diag(`copyFail ${j.rel}/${j.name} err=${String(e)}`);
      }
    }
    this.diag(`copy done copied=${copied}`);
    return copied;
  }

  /** Create a nested directory chain at a physical path. fs.mkdirSync can throw
   *  EEXIST on an existing dir, so create level-by-level and swallow the race.
   *  Used to rebuild the torrent's folder tree under the granted public dir. */
  private mkdirRecursive(dir: string): void {
    if (!dir || fs.accessSync(dir)) {
      return;
    }
    const segments = dir.split('/').filter((s: string) => s.length > 0);
    let cur = '';
    for (let i = 0; i < segments.length; i++) {
      cur = `${cur}/${segments[i]}`;
      try {
        if (!fs.accessSync(cur)) {
          fs.mkdirSync(cur);
        }
      } catch (e) {
        // EEXIST from a concurrent creator, or a reserved/read-only base segment
        // (e.g. an already-existing root path) — ignore; the next accessSync
        // confirms it is usable.
      }
    }
  }

  /** Move a torrent's data to a new sandbox dir (taskpool-offloaded). Sets up
   *  the relocate dialog; doRelocate does the offloaded native move. */
  private onSetLocation(t: TorrentInfo): void {
    this.relocateTarget = `${this.sessionDownloadDir}/moved_${t.id}`;
    this.contextMenuTorrent = t;
    this.showRelocateDialog = true;
  }

  /**
   * Run the offloaded torrentSetLocation. The native call moves file data on
   * disk, so it wraps the synchronous native torrentSetLocation in a taskpool
* worker to keep the UI thread responsive (mirrors the classic poll+wake pattern
   * background ThreadPoolExecutor). The target must stay inside the app sandbox,
   * the only path libtransmission can write on API 24.
   */
  private async doRelocate(): Promise<void> {
    const target = this.relocateTarget.trim();
    this.showRelocateDialog = false;
    const t = this.contextMenuTorrent;
    if (!t || target.length === 0) {
      return;
    }
    if (!target.startsWith(getContext(this).filesDir)) {
      promptAction.showToast({ message: $r('app.string.downloads_toast_move_sandbox'), duration: 2000 });
      return;
    }
    try {
      if (!fs.accessSync(target)) {
        fs.mkdirSync(target, true);
      }
      // Resolve the session ptr on the MAIN thread and pass it in — a taskpool
      // worker has an isolated heap and can't read the session map (see the
      // '@Concurrent' table above).
      const ptr = NativeBridge.getInstance().getSessionPtr(this.controller.sessionId);
      await taskpool.execute(concurrentTorrentSetLocation, ptr, t.id, target);
      promptAction.showToast({ message: $r('app.string.downloads_toast_moved'), duration: 2000 });
      this.controller.reload();
    } catch (e) {
      hilog.error(0x0001, TAG, 'Relocate failed: %{private}s', String(e));
      promptAction.showToast({ message: $r('app.string.downloads_toast_move_failed', String(e)), duration: 2000 });
    }
  }

  /** Absolute sandbox path for a downloadDir-relative file name. Returns ''
   *  (caller must guard) if the name escapes the sandbox via path traversal. */
  private buildSandboxFilePath(torrentRelPath: string): string {
    const safe = this.sanitizeRelPath(torrentRelPath);
    if (!safe) {
      return '';
    }
    return `${this.sessionDownloadDir}/${safe}`;
  }

  /**
   * Sanitize a torrent-relative file path against path traversal.
   * Torrent file names are untrusted (come from .torrent metadata). Strips
   * leading separators, collapses '.'/empty segments, and rejects '..' — which
   * would let a malicious torrent escape the download or publish dir.
   * Returns a clean relative path, or null if unusable (empty/traversal).
   */
  private sanitizeRelPath(relPath: string): string | null {
    const p = relPath.replace(/\\/g, '/').replace(/^\/+/, '');
    const segments = p.split('/');
    const out: string[] = [];
    for (let i = 0; i < segments.length; i++) {
      const seg = segments[i];
      if (seg === '' || seg === '.') {
        continue; // collapse empty / self segments
      }
      if (seg === '..') {
        return null; // traversal — reject the whole path
      }
      out.push(seg);
    }
    return out.length > 0 ? out.join('/') : null;
  }

  private onContextMenuAction(action: TorrentAction): void {
    const t = this.contextMenuTorrent;
    if (!t) {
      return;
    }
    this.showContextMenu = false;

    switch (action) {
      case TorrentAction.PAUSE:
        this.onPause(t);
        break;
      case TorrentAction.RESUME:
        this.onResume(t);
        break;
      case TorrentAction.REMOVE:
        this.onRemove(t);
        break;
      case TorrentAction.REMOVE_WITH_DATA:
        this.controller.removeWithData(t.id);
        this.pruneTorrentMetainfo(t);
        break;
      case TorrentAction.VERIFY:
        this.onVerify(t);
        break;
      case TorrentAction.REANNOUNCE:
        this.onReannounce(t);
        break;
      case TorrentAction.SHOW_FILES:
        this.onShowFiles(t);
        break;
      case TorrentAction.SAVE_TO_FILES:
        this.onSaveToFiles(t);
        break;
      case TorrentAction.SET_LOCATION:
        this.onSetLocation(t);
        break;
      case TorrentAction.SHOW_DETAIL:
        // Toggle expanded state — handled by TorrentCard internally
        break;
    }
  }

  private onTorrentAdded(): void {
    this.showAddPage = false;
    this.controller.reload();
  }

  /**
   * Reconcile @State torrentVms against the latest polled list, REUSING the
   * existing TorrentVM instances by id. Re-using keeps the ForEach child
   * components (and their @State, e.g. isExpanded) alive; setting `vm.torrent`
   * to the fresh TorrentInfo is an @Observed mutation that re-renders the
   * @ObjectLink-bound card in place instead of freezing on first render.
   */
  private syncTorrentVms(list: TorrentInfo[]): void {
    const prev = new Map<number, TorrentVM>();
    for (const vm of this.torrentVms) {
      prev.set(vm.torrent.id, vm);
    }
    const next: TorrentVM[] = [];
    for (const t of list) {
      const existing = prev.get(t.id);
      if (existing !== undefined) {
        existing.torrent = t; // mutate in place → @ObjectLink re-renders
        next.push(existing);
      } else {
        next.push(new TorrentVM(t));
      }
    }
    this.torrentVms = next;
  }

  // ═══════════════════════════════════════════════════════════════════
  // Build
  // ═══════════════════════════════════════════════════════════════════

  build() {
    if (this.showAddPage) {
      Stack() {
        this.buildAddPageOverlay();
      }
      .width('100%')
      .height('100%')
      .backgroundColor(Colors.BG);
    } else if (this.showFileTree) {
      Stack() {
        this.buildFileTreeOverlay();
      }
      .width('100%')
      .height('100%')
      .backgroundColor(Colors.BG);
    } else {
      this.buildMainPage();
    }
  }

  @Builder
  buildMainPage() {
    Stack() {
      Column() {
        this.buildHeader();
        this.buildContent();
        this.buildFAB();
      }
      .width('100%')
      .height('100%')
      .backgroundColor(Colors.BG);

      // Context menu overlay
      if (this.showContextMenu && this.contextMenuTorrent !== null) {
        TorrentContextMenu({
          torrent: this.contextMenuTorrent,
          sessionId: this.controller.sessionId,
          isVisible: $showContextMenu,
          onAction: (action: TorrentAction, _torrent: TorrentInfo) => {
            this.onContextMenuAction(action);
          },
        });
      }

      // Relocate dialog overlay (text-entry — the FOLDER picker returns a
      // file://docs URI and is 2-in-1-only, so it can't supply a POSIX path).
      if (this.showRelocateDialog) {
        this.buildRelocateOverlay();
      }
    }
    .width('100%')
    .height('100%');
  }

  @Builder
  buildHeader() {
    Row() {
      Text($r('app.string.downloads_title'))
        .fontSize(FontSize.TITLE)
        .fontWeight(FontWeight.Bold)
        .fontColor(Colors.TEXT)
        .layoutWeight(1);

      if (this.torrents.length > 0) {
        Text(`${this.torrents.length}`)
          .fontSize(FontSize.CAPTION)
          .fontColor(Colors.TEXT_TERTIARY)
          .fontFamily('JetBrains Mono')
          .padding({ left: Spacing.SM, right: Spacing.SM, top: 2, bottom: 4 })
          .borderRadius(Radius.SM)
          .backgroundColor(Colors.ELEVATED);
      }
    }
    .width('100%')
    .padding({ left: Spacing.LG, right: Spacing.LG, top: Spacing.LG, bottom: Spacing.SM });
  }

  @Builder
  buildContent() {
    if (this.isLoading) {
      this.buildLoadingState();
    } else if (this.torrents.length === 0) {
      this.buildEmptyState();
    } else {
      this.buildTorrentList();
    }
  }

  @Builder
  buildLoadingState() {
    Column() {
      LoadingProgress()
        .width(40)
        .height(40)
        .color(Colors.DOWNLOAD);
      Text($r('app.string.downloads_loading'))
        .fontSize(FontSize.CAPTION)
        .fontColor(Colors.TEXT_SECONDARY)
        .margin({ top: Spacing.MD });
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center);
  }

  @Builder
  buildEmptyState() {
    Column() {
      EmptyState({
        icon: '⬇',
        title: $r('app.string.downloads_empty_title'),
        description: $r('app.string.downloads_empty_desc'),
      });
    }
    .width('100%')
    .layoutWeight(1);
  }

  @Builder
  buildTorrentList() {
    // Summary bar
    Row() {
      Text(this.summaryText())
        .fontSize(FontSize.SMALL)
        .fontColor(Colors.TEXT_TERTIARY)
        .layoutWeight(1);

      Text(this.speedSummaryText())
        .fontSize(FontSize.SMALL)
        .fontColor(Colors.TEXT_SECONDARY)
        .fontFamily('JetBrains Mono');
    }
    .width('100%')
    .padding({ left: Spacing.LG, right: Spacing.LG, bottom: Spacing.SM });

    // Torrent list
    List() {
      ForEach(this.torrentVms, (vm: TorrentVM) => {
        ListItem() {
          TorrentCard({
            vm: vm,
            sessionId: this.controller.sessionId,
            onPause: () => { this.onPause(vm.torrent); },
            onResume: () => { this.onResume(vm.torrent); },
            onRemove: () => { this.onRemove(vm.torrent); },
            onVerify: () => { this.onVerify(vm.torrent); },
            onReannounce: () => { this.onReannounce(vm.torrent); },
            onShowFiles: () => { this.onShowFiles(vm.torrent); },
          });
        }
        .gesture(
          LongPressGesture({ repeat: false, duration: 500 })
            .onAction(() => {
              this.contextMenuTorrent = vm.torrent;
              this.showContextMenu = true;
            })
        )
        .margin({ left: Spacing.LG, right: Spacing.LG, bottom: Spacing.MD });
      }, (vm: TorrentVM) => `${vm.torrent.id}`)
    }
    .layoutWeight(1)
    .width('100%');
  }

  @Builder
  buildFAB() {
    Row() {
      Button('+')
        .fontSize(28)
        .fontColor('#ffffff')
        .width(56)
        .height(56)
        .borderRadius(28)
        .backgroundColor(Colors.DOWNLOAD)
        .shadow({
          radius: 16,
          color: '#3b82f640',
          offsetY: 6,
        })
        .onClick(() => { this.showAddPage = true; });
    }
    .width('100%')
    .justifyContent(FlexAlign.End)
    .padding(Spacing.LG)
    .position({ right: 0, bottom: 0 });
  }

  @Builder
  buildFileTreeOverlay() {
    FileTreePage({
      torrentId: this.fileTreeTorrentId,
      sessionId: this.controller.sessionId,
      torrentName: this.fileTreeTorrentName,
      onBack: () => { this.showFileTree = false; },
    });
  }

  @Builder
  buildAddPageOverlay() {
    AddTorrentPage({
      sessionId: this.controller.sessionId,
      downloadDir: this.getDefaultDownloadDir(),
      onTorrentAdded: () => { this.onTorrentAdded(); },
      onCancel: () => { this.showAddPage = false; },
    });
  }

  @Builder
  buildRelocateOverlay() {
    Stack() {
      // Backdrop (dismiss on tap)
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('#00000080')
        .onClick(() => { this.showRelocateDialog = false; });

      Column() {
        Text($r('app.string.downloads_relocate_title'))
          .fontSize(FontSize.HEADLINE)
          .fontWeight(FontWeight.Medium)
          .fontColor(Colors.TEXT)
          .margin({ bottom: Spacing.MD });

        Text($r('app.string.downloads_relocate_hint'))
          .fontSize(FontSize.SMALL)
          .fontColor(Colors.TEXT_SECONDARY)
          .width('100%')
          .margin({ bottom: Spacing.SM });

        TextInput({ placeholder: '.../downloads/moved_N', text: this.relocateTarget })
          .fontSize(FontSize.CAPTION)
          .fontColor(Colors.TEXT)
          .backgroundColor(Colors.ELEVATED)
          .borderRadius(Radius.MD)
          .height(44)
          .width('100%')
          .onChange((value: string) => { this.relocateTarget = value; });

        Button($r('app.string.downloads_relocate_move'))
          .fontSize(FontSize.BODY)
          .fontColor('#ffffff')
          .backgroundColor(Colors.DOWNLOAD)
          .width('90%')
          .height(48)
          .borderRadius(Radius.MD)
          .margin({ top: Spacing.LG })
          .onClick(() => { this.doRelocate(); });

        Button($r('app.string.common_cancel'))
          .fontSize(FontSize.BODY)
          .fontColor(Colors.TEXT_SECONDARY)
          .width('90%')
          .height(44)
          .borderRadius(Radius.MD)
          .backgroundColor(Colors.ELEVATED)
          .margin({ top: Spacing.SM })
          .onClick(() => { this.showRelocateDialog = false; });
      }
      .width('90%')
      .borderRadius(Radius.LG)
      .backgroundColor(Colors.SURFACE)
      .padding({ top: Spacing.LG, bottom: Spacing.LG, left: Spacing.LG, right: Spacing.LG });
    }
    .width('100%')
    .height('100%')
    .position({ x: 0, y: 0 });
  }

  private getDefaultDownloadDir(): string {
    return `${getContext(this).filesDir}/downloads`;
  }

  // ═══════════════════════════════════════════════════════════════════
  // Summary helpers
  // ═══════════════════════════════════════════════════════════════════

  /** Resolve a $r-created (optionally format-arg) resource to a display string. */
  private lbl(res: Resource): string {
    return getContext(this).resourceManager.getStringSync(res);
  }

  private summaryText(): string {
    const count = this.torrents.length;
    let downloading = 0;
    let seeding = 0;
    let paused = 0;

    for (const t of this.torrents) {
      if (t.isDownloading()) {
        downloading++;
      } else if (t.isSeeding()) {
        seeding++;
      } else if (t.isStopped()) {
        paused++;
      }
    }

    const parts: string[] = [];
    if (downloading > 0) {
      parts.push(this.lbl($r('app.string.downloads_summary_downloading', downloading)));
    }
    if (seeding > 0) {
      parts.push(this.lbl($r('app.string.downloads_summary_seeding', seeding)));
    }
    if (paused > 0) {
      parts.push(this.lbl($r('app.string.downloads_summary_paused', paused)));
    }
    return parts.length > 0 ? parts.join(' · ')
      : this.lbl($r('app.string.downloads_summary_all', count));
  }

  private speedSummaryText(): string {
    let totalDown = 0;
    let totalUp = 0;
    for (const t of this.torrents) {
      totalDown += t.rateDownload;
      totalUp += t.rateUpload;
    }

    const parts: string[] = [];
    if (totalDown > 0) {
      parts.push(formatSpeed(totalDown) + ' ↓');
    }
    if (totalUp > 0) {
      parts.push(formatSpeed(totalUp) + ' ↑');
    }
    return parts.length > 0 ? parts.join('  ') : '';
  }

}
