// transmissionbtm — SessionController
//
// Consolidates the DownloadsPage session side-effects into one observable,
// addressable unit: the libtransmission session lifecycle, the 5s polling
// loop, the D3 keep-alive, and the D4 connectivity monitor (network-loss
// suspend/resume). The page keeps its own @State and subscribes through
// onTorrents()/onLoading(), so ArkUI reactivity is unchanged — only the
// side-effect ownership moves out of the page into this controller.
//
// Testability: TransmissionSession is constructor-injectable and the wake
// lock / connectivity monitor are injected collaborators, so host tests drive
// a fake session (and omit the collaborators) without touching native. The
// keep-alive type is imported type-only so the module has no runtime
// dependency on @kit.BasicServicesKit (which host vitest does not mock).
//
// Callers:
//   DownloadsPage — owns a SessionController, subscribes, and renders.

import { TransmissionSession } from '../models/TransmissionSession';
import { PreferencesManager } from '../models/Preferences';
import { SessionConfig } from '../models/SessionConfig';
import { TorrentInfo } from '../models/TorrentInfo';
import { TorrentFile } from '../models/TorrentFile';
import type { KeepAliveManager } from './KeepAliveManager';
import { hilog } from '@kit.PerformanceAnalysisKit';

const TAG = 'SessionController';

/** Minimal connectivity contract — satisfied by ConnectivityMonitor. */
export interface ConnectivityContract {
  start(): Promise<void>;
  destroy(): Promise<void>;
}

export class SessionController {
  private session: TransmissionSession;
  /** D3 keep-alive holder (continuous task). Null => disabled (host tests omit it). */
  private keepAlive: KeepAliveManager | null;
  /** D4 connectivity factory. Undefined => no network suspend/resume. */
  private connectivityFactory: ((onAvailable: () => void, onLost: () => void) => ConnectivityContract) | null;

  private pollTimer: number = -1;
  /** True while an acquire() call is in flight (acquire is async). */
  private acquiring: boolean = false;
  /** The in-flight acquire() promise, so stop() can undo a late completion. */
  private inflightAcquire: Promise<void> | null = null;
  /**
   * Bumped by stop(). start() captures it before its await and bails out if it
   * changed, so a start() that outlives a stop() can't wire listeners/poll onto
   * a closed session.
   */
  private epoch: number = 0;
  private connectivity: ConnectivityContract | null = null;
  private netPaused: boolean = false;
  private _started: boolean = false;
  /** Mirror of the last emitted list, for synchronous remove-hide timing. */
  private latest: TorrentInfo[] = [];
  /** PreferencesManager settings-listener handle (unregistered in stop()). */
  private unregisterSettingsListener: (() => void) | null = null;

  // ── Reactive outputs (the page subscribes and mirrors into @State) ──
  onTorrents: (torrents: TorrentInfo[]) => void = () => {};
  onLoading: (loading: boolean) => void = () => {};

  constructor(
    session: TransmissionSession = new TransmissionSession(),
    keepAlive: KeepAliveManager | null = null,
    connectivityFactory: ((onAvailable: () => void, onLost: () => void) => ConnectivityContract) | null = null
  ) {
    this.session = session;
    this.keepAlive = keepAlive;
    this.connectivityFactory = connectivityFactory;
  }

  get sessionId(): number {
    return this.session.sessionId;
  }

  get isStarted(): boolean {
    return this._started;
  }

  /**
   * Start the native session, then the 5s poll, the keep-alive, and the
   * connectivity monitor. Mirrors the page's former initSession(): the page
   * resolves sandbox paths into config BEFORE calling start; here we start the
   * session and begin polling.
   */
  async start(config: SessionConfig): Promise<void> {
    if (this._started) {
      return;
    }
    // Snapshot the stop-generation: if stop() runs while session.start() is in
    // flight, the session below is already torn down and installing the
    // settings listener + 5s poll here would leave both running with no page
    // left to stop them.
    const epoch = this.epoch;
    this.onLoading(true);
    try {
      await this.session.start(config);
      if (epoch !== this.epoch) {
        hilog.info(0x0001, TAG, 'start superseded by stop() — discarding');
        // stop() already reset _started and closed the session; a session.start()
        // that landed after that is re-closed here (session.stop is idempotent).
        this.session.stop();
        return;
      }
      hilog.info(0x0001, TAG, 'Session started, id=%{public}d', this.session.sessionId);
      this._started = true;
      this.unregisterSettingsListener = PreferencesManager.getInstance()
        .registerSettingsListener((config: SessionConfig) => {
          // Live re-apply: settings edited mid-session reach the RUNNING engine
          // immediately (native tr_sessionSet on the session thread). No-op if
          // the session is not running — config is still persisted for next start.
          this.session.updateSettings(config);
        });
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

  /** Tear down the poll, keep-alive, connectivity monitor, and session. */
  stop(): void {
    // Supersede any in-flight start(): it captured the old epoch and will tear
    // itself down instead of installing a listener/poll on the closed session.
    this.epoch++;
    // Unsub from the settings change-notifier first so a concurrent settings
    // edit can't re-apply to a session we're about to close.
    if (this.unregisterSettingsListener !== null) {
      this.unregisterSettingsListener();
      this.unregisterSettingsListener = null;
    }
    this.stopPolling();
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
    // Release the continuous task LAST: sessionClose can block for tens of
    // seconds (waitSessionIdle + tr_sessionClose, 15s each), and the OS freezes
    // a backgrounded process ~5s after the task is gone — releasing first would
    // freeze us mid-close, possibly before resume data is flushed to disk.
    if (this.keepAlive !== null) {
      this.keepAlive.release();
      const inflight = this.inflightAcquire;
      if (inflight !== null) {
        // An acquire() still in flight when we got here can complete AFTER the
        // release above and re-hold the task, with the poll stopped and nobody
        // left to release it. Undo it on completion. (KeepAliveManager.release
        // is a no-op when it isn't holding.)
        inflight.then(() => { this.keepAlive?.release(); })
                .catch(() => { /* acquire failure already logged */ });
      }
    }
    this.acquiring = false;
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

  /** True if any torrent is actively downloading (keep-alive gate). */
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

  /** Read the full torrent list once and emit it. Also drives the keep-alive. */
  private refresh(): void {
    let list: TorrentInfo[] = this.latest;
    try {
      list = this.session.getAllTorrents();
    } catch (e) {
      // Session may not be active — keep the last list emitted
    }
    this.latest = list;
    this.onTorrents(list);
    this.updateKeepAlive();
  }

  private hide(torrentId: number): void {
    this.latest = this.latest.filter((t: TorrentInfo) => t.id !== torrentId);
    this.onTorrents(this.latest);
  }

  // ── D3 keep-alive (hold while transferring) ─────────────────────────

  private updateKeepAlive(): void {
    if (this.keepAlive === null) {
      return;
    }
    // netPaused counts as active: a network-loss pause stops the engine, which
    // makes hasDownloading() false — releasing the continuous task there lets
    // the OS freeze the process, and a frozen process can never resume when the
    // network comes back. Hold the task for as long as the user still has
    // transfers in flight; the OS may suspend it (logged by KeepAliveManager)
    // but it stays recoverable.
    const active = this.hasDownloading() || this.netPaused;
    // Ask the manager whether it is actually holding, NOT a local mirror of it.
    // The OS can cancel a continuous task on its own (low-speed check, system
    // policy) and KeepAliveManager drops its flag when that happens; a mirror
    // that never hears about it would stay true and skip every later acquire.
    // Nothing would then re-acquire the task and the OS would freeze the
    // process as soon as the app went to the background — downloads then ran
    // only while the app was on screen, which is the reported bug.
    if (active && !this.keepAlive.isHolding() && !this.acquiring) {
      this.acquiring = true; // acquire() is async; dedupe until it settles
      const p = this.keepAlive.acquire('active torrent transfer');
      this.inflightAcquire = p;
      p.catch((e: Error) => {
        hilog.error(0x0001, TAG, 'keep-alive acquire failed: %{private}s', String(e));
      }).finally(() => {
        this.acquiring = false; // a failed acquire is retried on the next poll
        this.inflightAcquire = null;
      });
    } else if (!active && this.keepAlive.isHolding()) {
      this.keepAlive.release();
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
