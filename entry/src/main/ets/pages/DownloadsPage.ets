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
import { PreferencesManager, PrefKeys } from '../models/Preferences';
import { picker, fileIo as fs } from '@kit.CoreFileKit';
import { promptAction } from '@kit.ArkUI';
import { TorrentCard } from '../components/torrent/TorrentCard';
import { TorrentContextMenu, TorrentAction } from '../components/torrent/TorrentContextMenu';
import { AddTorrentPage } from './AddTorrentPage';
import { FileTreePage } from './FileTreePage';
import { EmptyState } from '../components/ui/EmptyState';
import { formatSpeed } from '../utils/format';
import { Colors, FontSize, Spacing, Radius } from '../utils/constants';
import { WakeLockManager } from '../services/WakeLockManager';
import { ConnectivityMonitor } from '../services/ConnectivityMonitor';
import { SessionController } from '../services/SessionController';

const TAG = 'DownloadsPage';

@Component
export struct DownloadsPage {
  @State torrents: TorrentInfo[] = [];
  @State isLoading: boolean = true;
  @State showAddPage: boolean = false;
  @State showFileTree: boolean = false;
  @State fileTreeTorrentId: number = 0;
  @State fileTreeTorrentName: string = '';
  @State showContextMenu: boolean = false;
  @State contextMenuTorrent: TorrentInfo | null = null;
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

  aboutToAppear(): void {
    hilog.info(0x0001, TAG, 'DownloadsPage aboutToAppear');
    this.controller.onTorrents = (list: TorrentInfo[]) => { this.torrents = list; };
    this.controller.onLoading = (loading: boolean) => { this.isLoading = loading; };
    this.initSession();
  }

  aboutToDisappear(): void {
    // D3/D4 (docs/11): controller.stop() releases the wake lock, unregisters the
    // connectivity monitor, stops polling, and tears the session down.
    this.controller.stop();
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
      this.applySandboxPaths(config);
      this.sessionDownloadDir = config.downloadDir;
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
   * public Download directory.
   *
   * HarmonyOS NEXT grants NO shared-dir write permission to a consumer app on
   * a phone (READ_WRITE_DOWNLOAD_DIRECTORY resolves to authResults=2). The
   * browser model applies instead: libtransmission writes into the app sandbox
   * (a real POSIX path) and we publish completed files to Download via
   * DocumentViewPicker.save() DOWNLOAD mode — returns a write-granted
   * `Download/<bundle>/` dir URI that needs NO permission and IS user-visible.
   */
  private async onSaveToFiles(t: TorrentInfo): Promise<void> {
    try {
      // Reuse the persisted publish folder picked in Settings, if any; otherwise
      // prompt once via the system DOWNLOAD-mode picker.
      let dirUri = await PreferencesManager.getInstance().getString(PrefKeys.PUBLISH_DIR, '');
      if (!dirUri) {
        const dp = new picker.DocumentViewPicker();
        const opts = new picker.DocumentSaveOptions();
        opts.pickerMode = picker.DocumentPickerMode.DOWNLOAD;
        const uris: string[] = await dp.save(opts);
        if (!uris || uris.length === 0) {
          return; // picker dismissed
        }
        dirUri = uris[0];
      }
      const files = this.controller.listFiles(t.id);
      let copied = 0;
      for (let i = 0; i < files.length; i++) {
        const f = files[i];
        if (f.isDirectory) {
          continue;
        }
        // Torrent file names are untrusted .torrent metadata. Sanitize the
        // relative path so a malicious name can't escape the download dir
        // (read via buildSandboxFilePath) or the publish dir (write baseName).
        const safeRel = this.sanitizeRelPath(f.name);
        if (!safeRel) {
          continue; // traversal / malformed / empty — skip this file
        }
        const segs = safeRel.split('/');
        const safeBase = segs[segs.length - 1];
        const srcAbs = this.buildSandboxFilePath(safeRel);
        if (!fs.accessSync(srcAbs)) {
          continue; // not yet on disk (still downloading / in incomplete dir)
        }
        fs.copyFileSync(srcAbs, `${dirUri}/${safeBase}`);
        copied++;
      }
      promptAction.showToast({
        message: copied > 0
          ? `已保存 ${copied} 个文件到 Download`
          : '没有可复制的文件(尚未下载完成)',
        duration: 2000,
      });
    } catch (e) {
      hilog.error(0x0001, TAG, 'Save to Files failed: %{private}s', String(e));
      promptAction.showToast({
        message: `保存失败: ${String(e)}`,
        duration: 2000,
      });
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
      case TorrentAction.SHOW_DETAIL:
        // Toggle expanded state — handled by TorrentCard internally
        break;
    }
  }

  private onTorrentAdded(): void {
    this.showAddPage = false;
    this.controller.reload();
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
          isVisible: this.showContextMenu,
          onAction: (action: TorrentAction, _torrent: TorrentInfo) => {
            this.onContextMenuAction(action);
          },
        });
      }
    }
    .width('100%')
    .height('100%');
  }

  @Builder
  buildHeader() {
    Row() {
      Text('Downloads')
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
      Text('Loading torrents...')
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
        title: 'No Torrents',
        description: 'Tap the + button to add a torrent file or magnet link',
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
      ForEach(this.torrents, (torrent: TorrentInfo) => {
        ListItem() {
          TorrentCard({
            torrent: torrent,
            sessionId: this.controller.sessionId,
            onPause: () => { this.onPause(torrent); },
            onResume: () => { this.onResume(torrent); },
            onRemove: () => { this.onRemove(torrent); },
            onVerify: () => { this.onVerify(torrent); },
            onReannounce: () => { this.onReannounce(torrent); },
            onShowFiles: () => { this.onShowFiles(torrent); },
          });
        }
        .gesture(
          LongPressGesture({ repeat: false, duration: 500 })
            .onAction(() => {
              this.contextMenuTorrent = torrent;
              this.showContextMenu = true;
            })
        )
        .margin({ left: Spacing.LG, right: Spacing.LG, bottom: Spacing.MD });
      }, (t: TorrentInfo) => `${t.id}`)
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

  private getDefaultDownloadDir(): string {
    return `${getContext(this).filesDir}/downloads`;
  }

  // ═══════════════════════════════════════════════════════════════════
  // Summary helpers
  // ═══════════════════════════════════════════════════════════════════

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
      parts.push(`${downloading} downloading`);
    }
    if (seeding > 0) {
      parts.push(`${seeding} seeding`);
    }
    if (paused > 0) {
      parts.push(`${paused} paused`);
    }
    return parts.length > 0 ? parts.join(' · ') : `${count} torrents`;
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
