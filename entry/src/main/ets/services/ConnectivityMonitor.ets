// transmissionbtm — Connectivity Monitor (M4)
//
// Monitors WiFi/Ethernet/Cellular connectivity via @ohos.net.connection.
// Notifies the service of network availability changes so the session
// can be paused on network loss and resumed on restore.
//
// WiFi-only mode: when enabled via preferences, the session is paused
// whenever the active network is not WiFi (bearer type mismatch).
//
// Usage:
//   const monitor = new ConnectivityMonitor(onAvailable, onLost);
//   monitor.start();
//   // ... later ...
//   monitor.destroy();

import { connection } from '@kit.NetworkKit';
import { wifiManager } from '@kit.ConnectivityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { PreferencesManager } from '../models/Preferences';

const TAG = 'ConnectivityMonitor';

/** Preference key for WiFi-only download mode (added by M4). */
const KEY_WIFI_ONLY = 'wifi_only';
/** Allowlist of SSIDs (comma-separated) honored when WiFi-only is on. */
const KEY_WIFI_SSID = 'wifi_ssid';

interface NetCapabilitiesChangeData {
  netHandle: connection.NetHandle;
  netCap: connection.NetCapabilities;
}

export class ConnectivityMonitor {
  private netConn: connection.NetConnection | null = null;
  private onAvailable: () => void;
  private onLost: () => void;
  private isStarted: boolean = false;
  private wasAvailable: boolean = true;

  /**
   * @param onAvailable Callback when a usable network becomes available.
   * @param onLost Callback when network connectivity is lost.
   */
  constructor(onAvailable: () => void, onLost: () => void) {
    this.onAvailable = onAvailable;
    this.onLost = onLost;
  }

  /**
   * Start monitoring network connectivity.
   * Attaches netAvailable/netLost/netCapabilitiesChange listeners, then
   * activates them with register() (required — listeners do not fire
   * otherwise).
   */
  async start(): Promise<void> {
    if (this.isStarted) {
      return;
    }
    this.isStarted = true;
    try {
      const nc: connection.NetConnection = connection.createNetConnection();
      this.netConn = nc;

      // Network becomes available
      nc.on('netAvailable', (data: connection.NetHandle) => {
        this.handleNetAvailable(data).then(() => {});
      });

      // Network is lost
      nc.on('netLost', (data: connection.NetHandle) => {
        this.handleNetLost(data);
      });

      // Network capabilities change (e.g. switching from WiFi to cellular)
      nc.on('netCapabilitiesChange', (data: NetCapabilitiesChangeData) => {
        this.handleCapabilitiesChange(data).then(() => {});
      });

      // P1 fix (codex review): .register() is REQUIRED to activate the
      // listeners — the old comment claiming registration was automatic was
      // wrong, so no events ever fired and the session never paused/resumed
      // on network loss. SDK NetConnection.register() is callback-style —
      // wrap in a Promise so we can await it here.
      await new Promise<void>((resolve, reject) => {
        nc.register((err: BusinessError) => {
          if (err) {
            reject(err);
          } else {
            resolve();
          }
        });
      });
      hilog.info(0x0001, TAG, 'Connectivity monitoring started');
    } catch (err) {
      this.isStarted = false;
      hilog.error(0x0001, TAG,
        'Failed to start connectivity monitoring: %{private}s', String(err));
    }
  }

  /**
   * Stop monitoring and release resources.
   * Removes listeners and unregisters the NetConnection — the old comment
   * claiming GC cleanup was wrong; the connection object held references and
   * listeners kept firing.
   */
  async destroy(): Promise<void> {
    if (!this.isStarted) {
      return;
    }
    this.isStarted = false;
    const nc = this.netConn;
    this.netConn = null;
    try {
      if (nc) {
        // SDK (API 24) NetConnection has no off() method — listeners are
        // released by unregister(). It is callback-style; wrap for await.
        await new Promise<void>((resolve, reject) => {
          nc.unregister((err: BusinessError) => {
            if (err) {
              reject(err);
            } else {
              resolve();
            }
          });
        });
      }
      hilog.info(0x0001, TAG, 'Connectivity monitoring stopped');
    } catch (err) {
      hilog.error(0x0001, TAG,
        'Failed to stop connectivity monitoring: %{private}s', String(err));
    }
  }

  /**
   * Handle a network becoming available.
   * Checks WiFi-only preference and bearer type before notifying.
   */
  private async handleNetAvailable(netHandle: connection.NetHandle): Promise<void> {
    hilog.info(0x0001, TAG, 'Network available event received');

    // Check WiFi-only mode
    const wifiOnly = await this.isWifiOnlyEnabled();
    if (wifiOnly) {
      const isWifi = await this.isWifiNetwork(netHandle);
      if (!isWifi) {
        hilog.info(0x0001, TAG,
          'WiFi-only mode: ignoring non-WiFi network');
        return;
      }
      if (!(await this.isSsidAllowed())) {
        hilog.info(0x0001, TAG,
          'WiFi-only mode: not on an allowed SSID — ignoring');
        return;
      }
    }

    if (!this.wasAvailable) {
      this.wasAvailable = true;
      this.onAvailable();
    }
  }

  /**
   * Handle a network being lost.
   */
  private handleNetLost(_netHandle: connection.NetHandle): void {
    hilog.info(0x0001, TAG, 'Network lost event received');
    if (this.wasAvailable) {
      this.wasAvailable = false;
      this.onLost();
    }
  }

  /**
   * Handle network capabilities change.
   * Re-evaluates whether the current network is acceptable for transfers
   * (e.g. WiFi-only mode with a switch from WiFi to cellular).
   */
  private async handleCapabilitiesChange(data: NetCapabilitiesChangeData): Promise<void> {
    const wifiOnly = await this.isWifiOnlyEnabled();
    if (!wifiOnly) {
      return;
    }

    const bearerTypes = data.netCap?.bearerTypes ?? [];
    const hasWifi = bearerTypes.some(
      (t: number) => t === connection.NetBearType.BEARER_WIFI
    );

    if (!hasWifi && this.wasAvailable) {
      hilog.info(0x0001, TAG,
        'WiFi-only mode: network no longer WiFi — suspending');
      this.wasAvailable = false;
      this.onLost();
    } else if (hasWifi && !this.wasAvailable) {
      if (await this.isSsidAllowed()) {
        hilog.info(0x0001, TAG,
          'WiFi-only mode: WiFi network detected — resuming');
        this.wasAvailable = true;
        this.onAvailable();
      }
    }
  }

  // ═══════════════════════════════════════════════════════════════════
  // Helpers
  // ═══════════════════════════════════════════════════════════════════

  /**
   * Check whether WiFi-only download mode is enabled in preferences.
   */
  private async isWifiOnlyEnabled(): Promise<boolean> {
    try {
      const prefs = PreferencesManager.getInstance();
      return await prefs.getBoolean(KEY_WIFI_ONLY, false);
    } catch (err) {
      hilog.error(0x0001, TAG,
        'isWifiOnlyEnabled failed: %{private}s', String(err));
      return false;
    }
  }

  /**
   * When WiFi-only mode has an SSID allowlist configured, require the current
   * SSID to be in it. Fail-open: no allowlist, or the active SSID can't be read
   * (permission denied / STA off / unsupported) → treat as allowed so the robust
   * bearer-type gate still governs. Never block a transfer because of a transient
   * SSID-read failure.
   */
  private async isSsidAllowed(): Promise<boolean> {
    try {
      const allowRaw = await PreferencesManager.getInstance().getString(KEY_WIFI_SSID, '');
      const allow = allowRaw.trim();
      if (allow.length === 0) {
        return true; // no allowlist → no SSID constraint
      }
      const info = await wifiManager.getLinkedInfo();
      const ssid = (info?.ssid ?? '').trim();
      if (ssid.length === 0) {
        return true; // cannot read active SSID → fail open
      }
      const names = allow.split(',')
        .map((s: string) => s.trim())
        .filter((s: string) => s.length > 0);
      return names.includes(ssid);
    } catch (err) {
      hilog.warn(0x0001, TAG,
        'SSID check failed (fail-open): %{private}s', String(err));
      return true;
    }
  }

  /**
   * Check if a given network handle is a WiFi network.
   */
  private async isWifiNetwork(netHandle: connection.NetHandle): Promise<boolean> {
    try {
      const caps = await connection.getNetCapabilities(netHandle);
      if (!caps || !caps.bearerTypes) {
        return false;
      }
      return caps.bearerTypes.some(
        (t: number) => t === connection.NetBearType.BEARER_WIFI
      );
    } catch (err) {
      hilog.error(0x0001, TAG,
        'isWifiNetwork failed: %{private}s', String(err));
      return false;
    }
  }
}
