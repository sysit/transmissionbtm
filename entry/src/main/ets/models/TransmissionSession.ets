// transmissionbtm — TransmissionSession domain model
//
// Wraps a native libtransmission session. All operations proxy through
// NativeBridge. Holds the active numeric sessionId after start().
//
// Session lifecycle:
//   STARTING → RUNNING ↔ SUSPENDED → STOPPED
//
// Callers:
//   DownloadsPage — owns the primary session (start/stop/suspend; D3 wake
//     lock, D4 connectivity, network-loss pause/resume)
//   FileTreePage — reads file list for a torrent
//   AddTorrentPage — adds a new torrent to the session
//   (TransmissionService was deleted in E3 — system-app-only on HarmonyOS NEXT)

import { NativeBridge } from '../bridge/NativeBridge';
import { SessionConfig, EncryptionMode } from './SessionConfig';
import { TorrentInfo, TorrentStatus, TorrentError } from './TorrentInfo';
import { TorrentFile, RawFileEntry } from './TorrentFile';
import { SessionRunState } from './SessionState';
import { hilog } from '@kit.PerformanceAnalysisKit';

export class TransmissionSession {
  /** Numeric session ID. Set by start(); may also be set externally
   *  (FileTreePage, AddTorrentPage) when the session is managed elsewhere. */
  sessionId: number = 0;

  /** Current lifecycle state. */
  state: SessionRunState = SessionRunState.STOPPED;

  /** Config directory — stored during start() for use by stop(). */
  private configDir: string = '';

  private bridge: NativeBridge = NativeBridge.getInstance();

  // ═══════════════════════════════════════════════════════════════════
  // Session lifecycle
  // ═══════════════════════════════════════════════════════════════════

  /**
   * Start a native libtransmission session.
   *
   * Maps SessionConfig fields to the 10 native sessionStart() parameters.
   * Stores configDir for later use by stop().
   */
  async start(config: SessionConfig): Promise<TransmissionSession> {
    if (this.state === SessionRunState.RUNNING) {
      return this;
    }
    this.state = SessionRunState.STARTING;
    this.configDir = config.settingsDir;

    // EncryptionMode is a string enum ('allow'|'prefer'|'require');
    // native sessionStart expects 0=ALLOW, 1=PREFER, 2=REQUIRE.
    const encrMode: number =
      config.encryptionMode === EncryptionMode.ALLOW  ? 0 :
      config.encryptionMode === EncryptionMode.PREFER ? 1 : 2;

    this.sessionId = this.bridge.sessionStart(
      config.settingsDir,
      config.downloadDir,
      encrMode,
      config.enableRpc,
      config.rpcPort,
      config.rpcAuthentication,
      config.rpcUsername,
      config.rpcPassword,
      config.enableRpcWhitelist,
      config.rpcWhitelist,
      this.buildSettingsJson(config)
    );

    if (this.sessionId < 0) {
      this.state = SessionRunState.STOPPED;
      this.sessionId = 0;
      throw new Error('Failed to start native transmission session');
    }

    this.state = SessionRunState.RUNNING;
    return this;
  }

  /**
   * Serialize the persisted SessionConfig into a settings JSON string for
   * native tr_sessionInit (codex P1 fix: settingsJson was previously sent
   * but discarded — now it is parsed and merged over defaults).
   *
   * Keys use transmission 4.1 setting names (kebab-case). Keys covered by
   * explicit native args — download-dir, encryption, rpc-* — are excluded;
   * the explicit args are authoritative and override these in native code.
   */
  private buildSettingsJson(config: SessionConfig): string {
    const s: Record<string, string | number | boolean> = {};
    s['peer-port'] = config.peerPort;
    s['incomplete-dir'] = config.incompleteDir;
    s['incomplete-dir-enabled'] = config.incompleteDir.length > 0;
    s['speed-limit-down'] = config.speedLimitDown;
    s['speed-limit-up'] = config.speedLimitUp;
    s['speed-limit-down-enabled'] = config.speedLimitDownEnabled;
    s['speed-limit-up-enabled'] = config.speedLimitUpEnabled;
    s['alt-speed-down'] = config.altSpeedDown;
    s['alt-speed-up'] = config.altSpeedUp;
    s['alt-speed-enabled'] = config.altSpeedEnabled;
    s['alt-speed-time-begin'] = config.altSpeedTimeBegin;
    s['alt-speed-time-end'] = config.altSpeedTimeEnd;
    s['alt-speed-time-day'] = config.altSpeedDay;
    s['peer-limit-global'] = config.peerLimitGlobal;
    s['peer-limit-per-torrent'] = config.peerLimitPerTorrent;
    s['utp-enabled'] = config.utpEnabled;
    s['pex-enabled'] = config.pexEnabled;
    s['dht-enabled'] = config.dhtEnabled;
    s['lpd-enabled'] = config.lpdEnabled;
    s['start-added-torrents'] = config.startAddedTorrents;
    s['rename-partial-files'] = config.renamePartialFiles;
    s['trash-original-torrent-files'] = config.trashOriginalTorrentFile;
    s['blocklist-enabled'] = config.blocklistEnabled;
    s['blocklist-url'] = config.blocklistUrl;
    s['ratio-limit'] = config.seedRatioLimit;
    s['ratio-limit-enabled'] = config.seedRatioLimited;
    s['idle-seeding-limit'] = config.idleSeedingLimit;
    s['idle-seeding-limit-enabled'] = config.idleSeedingLimitEnabled;
    // Transmission 4.1 models proxy as a single "proxy-url" URL string.
    if (config.proxyEnabled && config.proxyUrl.length > 0) {
      let url: string = config.proxyUrl.includes('://')
        ? config.proxyUrl
        : 'http://' + config.proxyUrl;
      if (config.proxyPort > 0) {
        url = url + ':' + String(config.proxyPort);
      }
      if (config.proxyAuthRequired) {
        const schemeEnd: number = url.indexOf('://') + 3;
        const creds: string =
          encodeURIComponent(config.proxyUsername) + ':' +
          encodeURIComponent(config.proxyPassword) + '@';
        url = url.slice(0, schemeEnd) + creds + url.slice(schemeEnd);
      }
      s['proxy-url'] = url;
    }
    return JSON.stringify(s);
  }

  /** Stop the native session and release resources. Idempotent. */
  stop(): void {
    if (this.state === SessionRunState.STOPPED) {
      return;
    }
    this.state = SessionRunState.STOPPED;
    if (this.sessionId > 0) {
      this.bridge.sessionStop(this.sessionId, this.configDir);
      this.sessionId = 0;
    }
  }

  /**
   * Suspend or resume the session.
   * When suspended, all active torrents are paused.
   */
  suspend(suspend: boolean): void {
    if (this.state === SessionRunState.STOPPED) {
      return;
    }
    this.state = suspend
      ? SessionRunState.SUSPENDED
      : SessionRunState.RUNNING;
    if (this.sessionId > 0) {
      this.bridge.sessionSuspend(this.sessionId, suspend);
    }
  }

  // ═══════════════════════════════════════════════════════════════════
  // Torrent CRUD
  // ═══════════════════════════════════════════════════════════════════

  /**
   * Add a torrent from a file path or magnet URI.
   * @param path        Absolute path to .torrent file, or magnet:?... URI
   * @param downloadDir Destination directory for downloaded data
   * @param paused      If true, torrent is added in stopped state
   * @returns TorrentAddResult code: 0=OK, 1=PARSE_ERR, 2=DUPLICATE, 3=OK_DELETE
   *          (NOT a torrent ID — see utils/constants.ets TorrentAddResult)
   */
  addTorrent(path: string, downloadDir: string, paused: boolean): number {
    return this.bridge.torrentAdd(
      this.sessionId, path, downloadDir,
      false /* deleteFlag */, paused
    );
  }

  /**
   * Remove a torrent from the session.
   * @param torrentId  Torrent to remove
   * @param removeData If true, also delete downloaded data from disk
   */
  removeTorrent(torrentId: number, removeData: boolean): void {
    this.bridge.torrentRemove(this.sessionId, torrentId, removeData);
  }

  /** Start (resume) a paused torrent. */
  startTorrent(torrentId: number): void {
    this.bridge.torrentStart(this.sessionId, torrentId);
  }

  /** Stop (pause) a running torrent. */
  stopTorrent(torrentId: number): void {
    this.bridge.torrentStop(this.sessionId, torrentId);
  }

  /** Request a data-verification pass for a torrent. */
  verifyTorrent(torrentId: number): void {
    this.bridge.torrentVerify(this.sessionId, torrentId);
  }

  /** Move a torrent's downloaded data to a new directory. */
  setTorrentLocation(torrentId: number, newDir: string): void {
    this.bridge.torrentSetLocation(this.sessionId, torrentId, newDir);
  }

  /** Re-announce a torrent to its trackers. */
  reannounceTorrent(torrentId: number): void {
    this.bridge.torrentReannounce(this.sessionId, torrentId);
  }

  // ═══════════════════════════════════════════════════════════════════
  // Torrent queries
  // ═══════════════════════════════════════════════════════════════════

  /** Fetch all torrents currently loaded in the session. */
  getAllTorrents(): TorrentInfo[] {
    try {
      const names: string[] = this.bridge.listTorrentNames(this.sessionId);
      if (!names || names.length === 0) {
        return [];
      }
      // listTorrentNames() is id/hash/name only. Merge the live brief stat so
      // status/percent/sizes/speeds are real — otherwise every torrent reports
      // its default STOPPED (0) and shows as "Paused" even while the engine is
      // downloading it (user: "两个种子都是pause状态").
      const list = TorrentInfo.fromNativeJson(names.join('\n'));
      this.applyStatBrief(list);
      return list;
    } catch (e) {
      hilog.error(0x0001, 'TransmissionSession',
        'getAllTorrents failed: %{private}s', String(e));
      return [];
    }
  }

  /**
   * Merge the live brief-stat buffer into a name-only TorrentInfo list.
   *
   * One buffer read, O(n + rows); the field mapping mirrors the per-torrent
   * brief-stat parse (which re-scans the buffer + re-fetches hash/name per
   * torrent — avoid for the polled list). A torrent present in the name list
   * but absent from the brief buffer is left at its default STOPPED.
   */
  private applyStatBrief(list: TorrentInfo[]): void {
    if (list.length === 0) {
      return;
    }
    let buf: ArrayBuffer;
    try {
      buf = this.bridge.torrentStatBrief(this.sessionId);
    } catch (e) {
      return;
    }
    if (!buf || buf.byteLength < 80) {
      return;
    }
    const view = new BigInt64Array(buf);
    const STRIDE = 10; // 10 int64 per torrent (matches native brief-stat layout)
    const count = Math.floor(view.length / STRIDE);
    if (count === 0) {
      return;
    }
    // id → torrent so each row fills its entry in O(1).
    const byId = new Map<number, TorrentInfo>();
    for (const t of list) {
      byId.set(t.id, t);
    }
    for (let r = 0; r < count; r++) {
      const base = r * STRIDE;
      const info = byId.get(Number(view[base]));
      if (!info) {
        continue;
      }
      const total: number = Number(view[base + 3]);
      const remaining: number = Number(view[base + 4]);
      const stVal: number = Number(view[base + 1]);
      info.status = stVal as TorrentStatus;
      info.percentComplete = Number(view[base + 2]) / 100;
      info.totalSize = total;
      info.uploadedEver = Number(view[base + 5]);
      info.peersConnected = Number(view[base + 6]);
      info.peersTotal = Number(view[base + 7]);
      info.rateUpload = Number(view[base + 8]);
      info.rateDownload = Number(view[base + 9]);
      info.haveValid = total - remaining;
      info.percentDone = total > 0 ? info.haveValid / total : 0;
      info.downloadedEver = info.haveValid;
      info.error = info.status === TorrentStatus.ERROR
        ? TorrentError.LOCAL_ERROR : TorrentError.OK;
    }
  }

  /** Return true if any torrent in the session is actively downloading. */
  hasDownloadingTorrents(): boolean {
    return this.bridge.hasDownloadingTorrents(this.sessionId);
  }

  /** Find a torrent by its 20-byte info-hash. Returns -1 if not found. */
  findTorrentByHash(hash: ArrayBuffer): number {
    return this.bridge.torrentFindByHash(this.sessionId, hash);
  }

  /** Get brief stats for ALL torrents in the session as raw ArrayBuffer. */
  getTorrentStatBriefAll(): ArrayBuffer {
    return this.bridge.torrentStatBrief(this.sessionId);
  }

  /** Get the name of a torrent. */
  getTorrentName(torrentId: number): string {
    return this.bridge.torrentGetName(this.sessionId, torrentId);
  }

  /** Get the 20-byte info hash of a torrent. */
  getTorrentHash(torrentId: number): Uint8Array {
    return this.bridge.torrentGetHash(this.sessionId, torrentId);
  }

  /** Get the error string for a torrent (empty string if no error). */
  getTorrentError(torrentId: number): string {
    return this.bridge.torrentGetError(this.sessionId, torrentId);
  }

  /** Diagnostic: live native engine state as a compact string. */
  getTorrentState(torrentId: number): string {
    return this.bridge.torrentState(this.sessionId, torrentId);
  }

  // ═══════════════════════════════════════════════════════════════════
  // File operations
  // ═══════════════════════════════════════════════════════════════════

  /**
   * List all files in a torrent.
   *
   * Native returns file names as a string[]. Constructs minimal TorrentFile
   * objects — call refreshFileStat() for per-file size/bytesCompleted/wanted.
   */
  listTorrentFiles(torrentId: number): TorrentFile[] {
    const names: string[] = this.bridge.torrentListFiles(
      this.sessionId, torrentId
    );
    if (!names || names.length === 0) {
      return [];
    }
    return names.map((name: string, index: number): TorrentFile => {
      const entry: RawFileEntry = {
        index: index,
        name: name,
        size: 0,
        wanted: true,
        priority: 0,
      };
      return TorrentFile.fromNative(entry);
    });
  }

  /**
   * Read a single file's live stat and apply it to the given TorrentFile.
   *
   * The model stays pure (no NativeBridge import); the per-file native read
   * lives here in the session facade. FileTreePage calls this once per file
   * when the tree opens (N reads acceptable, on-demand).
   */
  refreshFileStat(torrentId: number, file: TorrentFile): void {
    const buf: ArrayBuffer = this.bridge.torrentGetFileStat(
      this.sessionId, torrentId, file.index);
    file.applyFileStat(buf);
  }

  /**
   * List files from a .torrent file without adding it to the session.
   * Returns TorrentFile objects built from native file name strings.
   */
  listTorrentFilesFromFile(filePath: string): TorrentFile[] {
    const names: string[] = this.bridge.torrentListFilesFromFile(filePath);
    if (!names || names.length === 0) {
      return [];
    }
    return names.map((name: string, index: number): TorrentFile => {
      const entry: RawFileEntry = {
        index: index,
        name: name,
        size: 0,
        wanted: true,
        priority: 0,
      };
      return TorrentFile.fromNative(entry);
    });
  }

  /** Get a file's logical name by index. */
  getTorrentFileName(torrentId: number, fileIndex: number): string {
    return this.bridge.torrentGetFileName(this.sessionId, torrentId,
      fileIndex);
  }

  /**
   * Set the per-file download (DnD) selection for a torrent.
   * files[i] === true  → file i is wanted (downloaded)
   * files[i] === false → file i is skipped (DnD), after the current file list.
   * Routes through NativeBridge.torrentSetFileWanted, which builds the exact
   * skip-index array native tr_torrentSetFileDLs expects.
   */
  setFileWanted(torrentId: number, files: boolean[]): void {
    this.bridge.torrentSetFileWanted(this.sessionId, torrentId, files);
  }

  // ═══════════════════════════════════════════════════════════════════
  // State queries
  // ═══════════════════════════════════════════════════════════════════

  isRunning(): boolean {
    return this.state === SessionRunState.RUNNING;
  }

  isStopped(): boolean {
    return this.state === SessionRunState.STOPPED;
  }

  isSuspended(): boolean {
    return this.state === SessionRunState.SUSPENDED;
  }
}
