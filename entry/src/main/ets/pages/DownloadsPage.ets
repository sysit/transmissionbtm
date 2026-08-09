// transmissionhm — DownloadsPage (main torrent list with 1s polling)
//
// Manages a TransmissionSession, polls for torrent stats every second,
// and renders a list of TorrentCard items. Provides a FAB to add torrents
// and navigation to the AddTorrentPage.

import { hilog } from '@kit.PerformanceAnalysisKit';
import { TorrentInfo } from '../models/TorrentInfo';
import { TransmissionSession } from '../models/TransmissionSession';
import { defaultSessionConfig, SessionConfig } from '../models/SessionConfig';
import { fileIo as fs } from '@kit.CoreFileKit';
import { TorrentCard } from '../components/torrent/TorrentCard';
import { TorrentContextMenu, TorrentAction } from '../components/torrent/TorrentContextMenu';
import { AddTorrentPage } from './AddTorrentPage';
import { FileTreePage } from './FileTreePage';
import { EmptyState } from '../components/ui/EmptyState';
import { formatSpeed } from '../utils/format';
import { Colors, FontSize, Spacing, Radius } from '../utils/constants';

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
  private session: TransmissionSession = new TransmissionSession();
  private pollTimer: number = -1;

  aboutToAppear(): void {
    hilog.info(0x0001, TAG, 'DownloadsPage aboutToAppear');
    this.initSession();
  }

  aboutToDisappear(): void {
    this.stopPolling();
    this.stopSession();
  }

  // ═══════════════════════════════════════════════════════════════════
  // Session lifecycle
  // ═══════════════════════════════════════════════════════════════════

  private async initSession(): Promise<void> {
    try {
      const config = defaultSessionConfig();
      this.applySandboxPaths(config);
      await this.session.start(config);
      hilog.info(0x0001, TAG, 'Session started, id=%{public}d', this.session.sessionId);
      this.refreshTorrents();
      this.startPolling();
    } catch (e) {
      hilog.error(0x0001, TAG, 'Session start failed: %{public}s', String(e));
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
    config.settingsDir = `${filesDir}/transmission`;
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

  private stopSession(): void {
    try {
      this.session.stop();
      hilog.info(0x0001, TAG, 'Session stopped');
    } catch (e) {
      hilog.error(0x0001, TAG, 'Session stop failed: %{public}s', String(e));
    }
  }

  private startPolling(): void {
    this.pollTimer = setInterval(() => {
      this.refreshTorrents();
    }, 1000);
  }

  private stopPolling(): void {
    if (this.pollTimer >= 0) {
      clearInterval(this.pollTimer);
      this.pollTimer = -1;
    }
  }

  // ═══════════════════════════════════════════════════════════════════
  // Data refresh
  // ═══════════════════════════════════════════════════════════════════

  private refreshTorrents(): void {
    try {
      this.torrents = this.session.getAllTorrents();
    } catch (e) {
      // Session may not be active — keep existing list
    }
    this.isLoading = false;
  }

  // ═══════════════════════════════════════════════════════════════════
  // Torrent actions
  // ═══════════════════════════════════════════════════════════════════

  private onPause(t: TorrentInfo): void {
    try {
      this.session.stopTorrent(t.id);
    } catch (e) {
      hilog.error(0x0001, TAG, 'Pause failed for %{public}d: %{public}s',
        t.id, String(e));
    }
  }

  private onResume(t: TorrentInfo): void {
    try {
      this.session.startTorrent(t.id);
    } catch (e) {
      hilog.error(0x0001, TAG, 'Resume failed for %{public}d: %{public}s',
        t.id, String(e));
    }
  }

  private onRemove(t: TorrentInfo): void {
    try {
      this.session.removeTorrent(t.id, false);
      // Remove from local list immediately for UI responsiveness
      this.torrents = this.torrents.filter((x: TorrentInfo) => x.id !== t.id);
    } catch (e) {
      hilog.error(0x0001, TAG, 'Remove failed for %{public}d: %{public}s',
        t.id, String(e));
    }
  }

  private onVerify(t: TorrentInfo): void {
    try {
      this.session.verifyTorrent(t.id);
    } catch (e) {
      hilog.error(0x0001, TAG, 'Verify failed for %{public}d: %{public}s',
        t.id, String(e));
    }
  }

  private onReannounce(t: TorrentInfo): void {
    try {
      this.session.reannounceTorrent(t.id);
    } catch (e) {
      hilog.error(0x0001, TAG, 'Reannounce failed for %{public}d: %{public}s',
        t.id, String(e));
    }
  }

  private onShowFiles(t: TorrentInfo): void {
    this.fileTreeTorrentId = t.id;
    this.fileTreeTorrentName = t.name;
    this.showFileTree = true;
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
        try {
          this.session.removeTorrent(t.id, true);
          this.torrents = this.torrents.filter((x: TorrentInfo) => x.id !== t.id);
        } catch (e) {
          hilog.error(0x0001, TAG, 'Remove with data failed: %{public}s', String(e));
        }
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
      case TorrentAction.SHOW_DETAIL:
        // Toggle expanded state — handled by TorrentCard internally
        break;
    }
  }

  private onTorrentAdded(): void {
    this.showAddPage = false;
    this.refreshTorrents();
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
          sessionId: this.session.sessionId,
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
            sessionId: this.session.sessionId,
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
      sessionId: this.session.sessionId,
      torrentName: this.fileTreeTorrentName,
      onBack: () => { this.showFileTree = false; },
    });
  }

  @Builder
  buildAddPageOverlay() {
    AddTorrentPage({
      sessionId: this.session.sessionId,
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
