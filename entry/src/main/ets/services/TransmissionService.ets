// transmissionhm — Background Transmission Service (M4)
//
// Foreground service that owns the libtransmission session lifecycle.
// Manages wake lock (CPU keep-alive during active downloads), connectivity
// monitoring (pause on network loss), native callback registration, and
// a persistent foreground notification showing download statistics.
//
// Lifecycle (ServiceExtensionAbility):
//   onCreate    → async init: load prefs, start session, register callbacks,
//                  start connectivity monitor, begin 1s polling loop,
//                  post foreground notification
//   onDestroy   → remove notification, stop polling, stop session,
//                  release callbacks, release wake lock, destroy monitor
//   onRequest   → keep-alive — no specific action
//
// Wake lock is acquired when any torrent is actively downloading and
// released when all torrents are idle/paused/seeding.

import { AppServiceExtensionAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { notificationManager } from '@kit.NotificationKit';
import { PreferencesManager } from '../models/Preferences';
import { TransmissionSession } from '../models/TransmissionSession';
import { SessionConfig, defaultSessionConfig } from '../models/SessionConfig';
import { TorrentInfo, TorrentStatus } from '../models/TorrentInfo';
import { NativeBridge } from '../bridge/NativeBridge';
import { WakeLockManager } from './WakeLockManager';
import { ConnectivityMonitor } from './ConnectivityMonitor';
import { formatSpeed } from '../utils/format';

const TAG = 'TransmissionService';

/** Notification ID for the persistent foreground notification. */
const FOREGROUND_NOTIFICATION_ID = 1;

/** Types of session events emitted to state change listeners. */
export type SessionEventType =
  | 'torrentChanged'
  | 'torrentStopped'
  | 'sessionChanged'
  | 'altSpeedChanged';

/** Callback signature for session state change listeners. */
export type SessionEventListener =
  (event: SessionEventType, data: Object | null) => void;

/** Payload for torrent-scoped events (torrentChanged / torrentStopped). */
interface TorrentEventPayload {
  torrentId: number;
}

export default class TransmissionService extends AppServiceExtensionAbility {
  private session: TransmissionSession = new TransmissionSession();
  private wakeLock: WakeLockManager = new WakeLockManager();
  private connectivityMonitor: ConnectivityMonitor | null = null;
  private pollTimer: number = -1;
  private downloadCount: number = 0;
  private downloadSpeed: number = 0;
  private uploadSpeed: number = 0;

  /** State change listeners (observer pattern). */
  private listeners: SessionEventListener[] = [];

  // ═══════════════════════════════════════════════════════════════════
  // ServiceExtensionAbility Lifecycle
  // ═══════════════════════════════════════════════════════════════════

  onCreate(want: Want): void {
    hilog.info(0x0001, TAG, '%{public}s onCreate — starting Transmission service', TAG);

    // Fire-and-forget async initialization.
    // The service stays alive via the foreground notification;
    // initialization errors are logged but do not crash the service.
    this.initializeService();
  }

  onDestroy(): void {
    hilog.info(0x0001, TAG, '%{public}s onDestroy — stopping Transmission service', TAG);

    // Remove foreground notification
    this.removeNotification();

    // Stop stat polling
    this.stopPolling();

    // Stop the native session
    this.session.stop();

    // Release native → ArkTS callback channel
    NativeBridge.getInstance().nativeToArktsRelease();

    // Release wake lock (if held)
    this.wakeLock.release();

    // Destroy connectivity monitor
    if (this.connectivityMonitor !== null) {
      this.connectivityMonitor.destroy();
      this.connectivityMonitor = null;
    }

    // Clear listeners
    this.listeners = [];

    hilog.info(0x0001, TAG, 'TransmissionService destroyed');
  }

  onRequest(want: Want, startId: number): void {
    hilog.info(0x0001, TAG,
      'onRequest startId=%{public}d', startId);
  }

  // ═══════════════════════════════════════════════════════════════════
  // State Change Listener API
  // ═══════════════════════════════════════════════════════════════════

  /**
   * Register a listener for session state change events.
   * The listener will be called on the ArkTS main thread when native
   * ThreadSafeFunction callbacks fire (torrent changed, session changed, etc.).
   */
  addEventListener(listener: SessionEventListener): void {
    const idx = this.listeners.indexOf(listener);
    if (idx < 0) {
      this.listeners.push(listener);
    }
  }

  /**
   * Remove a previously registered state change listener.
   */
  removeEventListener(listener: SessionEventListener): void {
    const idx = this.listeners.indexOf(listener);
    if (idx >= 0) {
      this.listeners.splice(idx, 1);
    }
  }

  /** Emit an event to all registered listeners. */
  private emitEvent(event: SessionEventType, data: Object | null): void {
    for (const listener of this.listeners) {
      try {
        listener(event, data);
      } catch (err) {
        hilog.error(0x0001, TAG,
          'Listener error for %{public}s: %{public}s', event, String(err));
      }
    }
  }

  // ═══════════════════════════════════════════════════════════════════
  // Initialization
  // ═══════════════════════════════════════════════════════════════════

  /**
   * Asynchronous initialization sequence:
   *   1. Load session configuration from preferences (fall back to defaults)
   *   2. Register native → ArkTS callback channel (ThreadSafeFunction init)
   *   3. Start the libtransmission session
   *   4. Start connectivity monitoring (pause/resume on network events)
   *   5. Set environment variables for the native process
   *   6. Begin 1-second polling loop (wake lock + notification management)
   *   7. Post foreground notification
   */
  private async initializeService(): Promise<void> {
    try {
      // ── 1. Load configuration ──────────────────────────────────────
      const config = await this.loadConfig();

      // ── 2. Register native → ArkTS callback channel ────────────────
      // Wire TSFN callbacks to emit state change events to all listeners
      NativeBridge.getInstance().nativeToArktsInit(
        (torrentId?: Object) => {
          const tid = typeof torrentId === 'number' ? torrentId : -1;
          const payload: TorrentEventPayload = { torrentId: tid };
          this.emitEvent('torrentChanged', payload);
        },
        (torrentId?: Object) => {
          const tid = typeof torrentId === 'number' ? torrentId : -1;
          const payload: TorrentEventPayload = { torrentId: tid };
          this.emitEvent('torrentStopped', payload);
        },
        () => { this.emitEvent('sessionChanged', null); },
        () => { this.emitEvent('altSpeedChanged', null); }
      );

      // ── 3. Start the libtransmission session ───────────────────────
      await this.session.start(config);
      hilog.info(0x0001, TAG,
        'Session started (id=%{public}d, dlDir=%{private}s)',
        this.session.sessionId, config.downloadDir);

      // ── 4. Start connectivity monitoring ───────────────────────────
      this.connectivityMonitor = new ConnectivityMonitor(
        () => this.onNetworkAvailable(),
        () => this.onNetworkLost()
      );
      this.connectivityMonitor.start();

      // ── 5. Set environment for native process ──────────────────────
      NativeBridge.getInstance().envSet('TRANSMISSION_HM_VERSION', '0.1.0-m4');

      // ── 6. Start stat polling loop ─────────────────────────────────
      this.startPolling();

      // ── 7. Post foreground notification ────────────────────────────
      await this.startForegroundNotification();

      hilog.info(0x0001, TAG, 'TransmissionService fully initialized');
    } catch (err) {
      hilog.error(0x0001, TAG,
        'initializeService failed: %{public}s', String(err));
    }
  }

  /**
   * Load the SessionConfig from PreferencesManager.
   * Falls back gracefully if the preferences store has not been
   * initialized yet (e.g. service started before EntryAbility).
   */
  private async loadConfig(): Promise<SessionConfig> {
    const prefs = PreferencesManager.getInstance();
    try {
      return await prefs.getSessionConfig();
    } catch (err) {
      hilog.warn(0x0001, TAG,
        'Preferences not yet initialized — attempting init: %{public}s',
        String(err));
      try {
        await prefs.init(this.context);
        return await prefs.getSessionConfig();
      } catch (err2) {
        hilog.warn(0x0001, TAG,
          'Preferences unavailable, using defaults: %{public}s', String(err2));
        return defaultSessionConfig();
      }
    }
  }

  // ═══════════════════════════════════════════════════════════════════
  // Foreground Notification
  // ═══════════════════════════════════════════════════════════════════

  /**
   * Post a persistent foreground notification so the system knows this
   * is a long-running service. Without this, the system may kill the
   * service during memory pressure.
   */
  private async startForegroundNotification(): Promise<void> {
    try {
      const request: notificationManager.NotificationRequest = {
        id: FOREGROUND_NOTIFICATION_ID,
        content: {
          notificationContentType:
            notificationManager.ContentType.NOTIFICATION_CONTENT_BASIC_TEXT,
          normal: {
            title: 'Transmission HM',
            text: 'Service running — no active downloads',
          },
        },
        notificationSlotType: notificationManager.SlotType.SERVICE_INFORMATION,
        isOngoing: true,
        isUnremovable: false,
      };

      await notificationManager.publish(request);
      hilog.info(0x0001, TAG, 'Foreground notification posted');
    } catch (err) {
      hilog.error(0x0001, TAG,
        'Failed to post foreground notification: %{public}s', String(err));
    }
  }

  /**
   * Update the foreground notification with current download statistics.
   * Called from the polling loop so the user always sees live stats.
   */
  private async updateNotification(): Promise<void> {
    try {
      const request: notificationManager.NotificationRequest = {
        id: FOREGROUND_NOTIFICATION_ID,
        content: {
          notificationContentType:
            notificationManager.ContentType.NOTIFICATION_CONTENT_BASIC_TEXT,
          normal: {
            title: 'Transmission HM',
            text: this.downloadCount > 0
              ? `${this.downloadCount} active — D: ${formatSpeed(this.downloadSpeed)} U: ${formatSpeed(this.uploadSpeed)}`
              : 'Idle — no active downloads',
          },
        },
        notificationSlotType: notificationManager.SlotType.SERVICE_INFORMATION,
        isOngoing: true,
        isUnremovable: false,
      };

      await notificationManager.publish(request);
    } catch (err) {
      // Notification update failures are non-critical — log and continue
      hilog.warn(0x0001, TAG,
        'Notification update failed: %{public}s', String(err));
    }
  }

  /** Format bytes/sec to a compact speed string for notification display. */

  /**
   * Remove the foreground notification. Called during service shutdown.
   */
  private async removeNotification(): Promise<void> {
    try {
      await notificationManager.cancel(FOREGROUND_NOTIFICATION_ID);
      hilog.info(0x0001, TAG, 'Foreground notification removed');
    } catch (err) {
      hilog.warn(0x0001, TAG,
        'Failed to remove notification: %{public}s', String(err));
    }
  }

  // ═══════════════════════════════════════════════════════════════════
  // Polling — Torrent Stats, Wake Lock, & Notification Updates
  // ═══════════════════════════════════════════════════════════════════

  /**
   * Start the 1-second polling loop.
   */
  private startPolling(): void {
    if (this.pollTimer >= 0) {
      return;
    }
    this.pollTimer = setInterval(() => {
      this.pollTick();
    }, 1000);
    hilog.info(0x0001, TAG, 'Polling started (1 s interval)');
  }

  /**
   * Stop the polling loop.
   */
  private stopPolling(): void {
    if (this.pollTimer >= 0) {
      clearInterval(this.pollTimer);
      this.pollTimer = -1;
      hilog.info(0x0001, TAG, 'Polling stopped');
    }
  }

  /**
   * Single poll tick. Counts active downloads, adjusts wake lock,
   * and updates the foreground notification with current speeds.
   */
  private async pollTick(): Promise<void> {
    if (!this.session.isRunning()) {
      return;
    }
    try {
      // P1 fix (codex review): pollTick previously read only getAllTorrents()
      // (names/ids from listTorrentNames; every status defaulted to STOPPED,
      // every rate to 0). torrentStatBrief was never consumed, so downloadCount
      // stayed 0, the wake lock was never acquired, and the notification always
      // showed "Idle". Consume the live stat brief instead.
      //
      // Brief layout (10 × int64 per torrent, matches TorrentInfo.fromStatArray):
      //   [0]=id [1]=status [2]=progress% [3]=totalLength [4]=remainingLength
      //   [5]=uploadedLength [6]=peersUp [7]=peersDown [8]=speedUp [9]=speedDown
      let active = 0;
      let totalDown = 0;
      let totalUp = 0;

      const buf: ArrayBuffer = this.session.getTorrentStatBriefAll();
      if (buf && buf.byteLength >= 80) {
        const view = new BigInt64Array(buf);
        const STRIDE = 10;
        const count = Math.floor(view.length / STRIDE);
        for (let i = 0; i < count; i++) {
          const base = i * STRIDE;
          if (Number(view[base + 1]) === TorrentStatus.DOWNLOAD) {
            active++;
          }
          totalDown += Number(view[base + 9]);
          totalUp += Number(view[base + 8]);
        }
      }

      if (active !== this.downloadCount ||
          totalDown !== this.downloadSpeed ||
          totalUp !== this.uploadSpeed) {
        this.downloadCount = active;
        this.downloadSpeed = totalDown;
        this.uploadSpeed = totalUp;
        await this.updateWakeLock();
        await this.updateNotification();
      }
    } catch (err) {
      hilog.error(0x0001, TAG,
        'pollTick failed: %{public}s', String(err));
    }
  }

  // ═══════════════════════════════════════════════════════════════════
  // Wake Lock
  // ═══════════════════════════════════════════════════════════════════

  /**
   * Acquire or release the BACKGROUND running lock based on current
   * download activity.
   */
  private async updateWakeLock(): Promise<void> {
    if (this.downloadCount > 0) {
      await this.wakeLock.acquire(
        `${this.downloadCount} active download(s)`
      );
    } else {
      this.wakeLock.release();
    }
  }

  // ═══════════════════════════════════════════════════════════════════
  // Connectivity Callbacks
  // ═══════════════════════════════════════════════════════════════════

  /**
   * Called by ConnectivityMonitor when a usable network is restored.
   */
  private onNetworkAvailable(): void {
    hilog.info(0x0001, TAG, 'Network available — resuming session');
    if (this.session.isSuspended()) {
      this.session.suspend(false);
      this.startPolling();
    }
  }

  /**
   * Called by ConnectivityMonitor when network connectivity is lost.
   */
  private onNetworkLost(): void {
    hilog.info(0x0001, TAG, 'Network lost — suspending session');
    if (this.session.isRunning()) {
      this.session.suspend(true);
      this.stopPolling();
      this.wakeLock.release();
    }
  }
}
