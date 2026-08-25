// transmissionbtm — SessionController
//
// Consolidates the DownloadsPage session side-effects into one observable,
// addressable unit: the libtransmission session lifecycle, the 5s polling
// loop, the D3 wake lock, and the D4 connectivity monitor (network-loss
// suspend/resume). The page keeps its own @State and subscribes through
// onTorrents()/onLoading(), so ArkUI reactivity is unchanged — only the
// side-effect ownership moves out of the page into this controller.
//
// Testability: TransmissionSession is constructor-injectable and the wake
// lock / connectivity monitor are injected collaborators, so host tests drive
// a fake session (and omit the collaborators) without touching native. The
// wake lock type is imported type-only so the module has no runtime
// dependency on @kit.BasicServicesKit (which host vitest does not mock).
//
// Callers:
//   DownloadsPage — owns a SessionController, subscribes, and renders.

import { TransmissionSession } from '../models/TransmissionSession';
import { SessionConfig } from '../models/SessionConfig';
import { TorrentInfo } from '../models/TorrentInfo';
import { TorrentFile } from '../models/TorrentFile';
import type { WakeLockManager } from './WakeLockManager';
import { hilog } from '@kit.PerformanceAnalysisKit';

const TAG = 'SessionController';

/** Minimal connectivity contract — satisfied by ConnectivityMonitor. */
export interface ConnectivityContract {
  start(): Promise<void>;
  destroy(): Promise<void>;
}

export class SessionController {
  private session: TransmissionSession;
  /** D3 wake-lock holder. Undefined => wake lock disabled (host tests omit it). */
  private wakeLock: WakeLockManager | null;
  /** D4 connectivity factory. Undefined => no network suspend/resume. */
  private connectivityFactory: ((onAvailable: () => void, onLost: () => void) => ConnectivityContract) | null;

  private pollTimer: number = -1;
  private wakeLockActive: boolean = false;
  private connectivity: ConnectivityContract | null = null;
  private netPaused: boolean = false;
  private _started: boolean = false;
  /** Mirror of the last emitted list, for synchronous remove-hide timing. */
  private latest: TorrentInfo[] = [];

  // ── Reactive outputs (the page subscribes and mirrors into @State) ──
  onTorrents: (torrents: TorrentInfo[]) => void = () => {};
  onLoading: (loading: boolean) => void = () => {};

  constructor(
    session: TransmissionSession = new TransmissionSession(),
    wakeLock: WakeLockManager | null = null,
    connectivityFactory: ((onAvailable: () => void, onLost: () => void) => ConnectivityContract) | null = null
  ) {
    this.session = session;
    this.wakeLock = wakeLock;
    this.connectivityFactory = connectivityFactory;
  }

  get sessionId(): number {
    return this.session.sessionId;
  }

  get isStarted(): boolean {
    return this._started;
  }

  /**
   * Start the native session, then the 5s poll, the wake lock, and the
   * connectivity monitor. Mirrors the page's former initSession(): the page
   * resolves sandbox paths into config BEFORE calling start; here we start the
   * session and begin polling.
   */
  async start(config: SessionConfig): Promise<void> {
    if (this._started) {
      return;
    }
    this.onLoading(true);
    try {
      await this.session.start(config);
      hilog.info(0x0001, TAG, 'Session started, id=%{public}d', this.session.sessionId);
      this._started = true;
      this.refresh();
      this.startPolling();
      this.startConnectivityMonitor();
    } catch (e) {
      hilog.error(0x0001, TAG, 'Session start failed: %{private}s', String(e));
      this._started = false;
    } finally {
      this.onLoading(false);
    }
  }

  /** Tear down the poll, wake lock, connectivity monitor, and session. */
  stop(): void {
    this.stopPolling();
    if (this.wakeLock !== null) {
      this.wakeLock.release();
    }
    this.wakeLockActive = false;
    if (this.connectivity !== null) {
      this.connectivity.destroy().catch((e: Error) => {
        hilog.error(0x0001, TAG, 'connectivity destroy failed: %{private}s', String(e));
      });
      this.connectivity = null;
    }
    this.netPaused = false;
    try {
      this.session.stop();
      hilog.info(0x0001, TAG, 'Session stopped');
    } catch (e) {
      hilog.error(0x0001, TAG, 'Session stop failed: %{private}s', String(e));
    }
    this._started = false;
  }

  /** Suspend (paused=true) or resume the session after a network transition. */
  suspend(paused: boolean): void {
    if (!this.netPaused && paused) {
      hilog.info(0x0001, TAG, 'Network lost — suspending session');
      this.netPaused = true;
      this.session.suspend(true);
    } else if (this.netPaused && !paused) {
      hilog.info(0x0001, TAG, 'Network restored — resuming session');
      this.netPaused = false;
      this.session.suspend(false);
    }
  }

  // ── Torrent CRUD actions (thin delegates to the session) ────────────

  pause(torrentId: number): void {
    this.session.stopTorrent(torrentId);
  }

  resume(torrentId: number): void {
    this.session.startTorrent(torrentId);
  }

  verify(torrentId: number): void {
    this.session.verifyTorrent(torrentId);
  }

  reannounce(torrentId: number): void {
    this.session.reannounceTorrent(torrentId);
  }

  /** Remove a torrent (keeping its data) and hide it immediately for UI. */
  remove(torrentId: number): void {
    this.session.removeTorrent(torrentId, false);
    this.hide(torrentId);
  }

  /** Remove a torrent and delete its data, hiding it immediately. */
  removeWithData(torrentId: number): void {
    this.session.removeTorrent(torrentId, true);
    this.hide(torrentId);
  }

  /** List a torrent's files (used by Save-to-Files). */
  listFiles(torrentId: number): TorrentFile[] {
    return this.session.listTorrentFiles(torrentId);
  }

  /** Force an immediate re-read + emit (used when the add flow completes). */
  reload(): void {
    this.refresh();
  }

  /** True if any torrent is actively downloading (wake-lock gate). */
  hasDownloading(): boolean {
    try {
      return this.session.hasDownloadingTorrents();
    } catch (e) {
      return false;
    }
  }

  // ── Polling loop ─────────────────────────────────────────────────────

  private startPolling(): void {
    // Poll every 5s (user requirement): the engine-side stats are cheap and 5s
    // keeps the UI responsive without per-second re-render churn.
    this.pollTimer = setInterval(() => {
      this.refresh();
    }, 5000);
  }

  private stopPolling(): void {
    if (this.pollTimer >= 0) {
      clearInterval(this.pollTimer);
      this.pollTimer = -1;
    }
  }

  /** Read the full torrent list once and emit it. Also drives the wake lock. */
  private refresh(): void {
    let list: TorrentInfo[] = this.latest;
    try {
      list = this.session.getAllTorrents();
    } catch (e) {
      // Session may not be active — keep the last list emitted
    }
    this.latest = list;
    this.onTorrents(list);
    this.updateWakeLock();
  }

  private hide(torrentId: number): void {
    this.latest = this.latest.filter((t: TorrentInfo) => t.id !== torrentId);
    this.onTorrents(this.latest);
  }

  // ── D3 wake lock (acquire only on idle→active transitions) ──────────

  private updateWakeLock(): void {
    if (this.wakeLock === null) {
      return;
    }
    const active = this.hasDownloading();
    if (active && !this.wakeLockActive) {
      this.wakeLockActive = true;
      this.wakeLock.acquire('active torrent transfer').catch((e: Error) => {
        hilog.error(0x0001, TAG, 'wake lock acquire failed: %{private}s', String(e));
        this.wakeLockActive = false;
      });
    } else if (!active && this.wakeLockActive) {
      this.wakeLockActive = false;
      this.wakeLock.release();
    }
  }

  // ── D4 connectivity monitor (suspend/resume on network loss) ────────

  private startConnectivityMonitor(): void {
    if (this.connectivityFactory === null || this.connectivity !== null) {
      return;
    }
    this.connectivity = this.connectivityFactory(
      () => { this.suspend(false); },
      () => { this.suspend(true); }
    );
    this.netPaused = false;
    this.connectivity.start().catch((e: Error) => {
      hilog.error(0x0001, TAG, 'connectivity start failed: %{private}s', String(e));
    });
  }
}
