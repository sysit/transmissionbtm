import native from 'libtransmissionbtm_napi.so';
import { hilog } from '@kit.PerformanceAnalysisKit';

// NOTE: NativeBridge does NOT import domain models.
// All composition/convenience methods that combine native calls
// with model construction live in TransmissionSession.

const TAG = 'NativeBridge';

export class NativeBridge {
  private static instance: NativeBridge | null = null;

  // Map numeric session ID → BigInt tr_session* pointer
  private sessionMap: Map<number, BigInt> = new Map();
  private nextSessionId: number = 1;

  static getInstance(): NativeBridge {
    if (!NativeBridge.instance) {
      NativeBridge.instance = new NativeBridge();
    }
    return NativeBridge.instance;
  }

  private constructor() {
    hilog.info(0x0001, TAG, `NativeBridge v${this.getVersion()} initialized`);
  }

  // ── Session pointer management ───────────────────────────────
  private toPtr(sessionId: number): BigInt {
    const ptr = this.sessionMap.get(sessionId);
    if (ptr !== undefined) {
      return ptr;
    }
    // P1 fix (codex review): returning BigInt(0) let a stale/unknown session
    // ID reach native as a wild (or null) tr_session* dereference. Throw so
    // the caller fails fast at the ArkTS boundary instead.
    throw new Error(`No live session for id ${sessionId} (stale handle?)`);
  }

  private registerSession(ptr: BigInt): number {
    const id = this.nextSessionId++;
    this.sessionMap.set(id, ptr);
    return id;
  }

  private unregisterSession(sessionId: number): void {
    this.sessionMap.delete(sessionId);
  }

  /** Resolve a numeric session id to its live tr_session* pointer.
   *  Call on the MAIN thread. @ohos.taskpool workers have isolated JS heaps,
   *  so they cannot reach the singleton's sessionMap; pass the returned (BigInt,
   *  a serializable taskpool arg) pointer into a @Concurrent function that calls
   *  the stateless *ByPtr methods instead. */
  getSessionPtr(sessionId: number): BigInt {
    return this.toPtr(sessionId);
  }

  // ═══════════════════════════════════════════════════════════════════
  // Version
  // ═══════════════════════════════════════════════════════════════════
  getVersion(): string {
    return native.getVersion();
  }

  // ═══════════════════════════════════════════════════════════════════
  // Session Lifecycle
  // ═══════════════════════════════════════════════════════════════════
  sessionStart(
    configDir: string, downloadsDir: string, encrMode: number,
    enableRpc: boolean, rpcPort: number, enableAuth: boolean,
    username: string, password: string, enableRpcWhitelist: boolean,
    rpcWhitelist: string, settingsJson: string = ''
  ): number {
    const ptr: BigInt = native.sessionStart(
      configDir, downloadsDir, encrMode, enableRpc, rpcPort,
      enableAuth, username, password, enableRpcWhitelist, rpcWhitelist,
      settingsJson
    );
    if (ptr === BigInt(0)) {
      hilog.error(0x0001, TAG, 'sessionStart returned null session pointer');
      return -1;
    }
    return this.registerSession(ptr);
  }

  sessionStop(sessionId: number, configDir: string): void {
    try {
      native.sessionStop(this.toPtr(sessionId), configDir);
    } catch (e) {
      // P2 fix (codex review): a double-stop or stale handle is benign — the
      // native live-session set (transmission.cc) already guards re-close.
      // Swallow so service teardown never throws.
      hilog.warn(0x0001, TAG, 'sessionStop ignored: %{private}s', String(e));
    } finally {
      // P2 fix (codex review): always release the registry entry, even if
      // the native call throws — otherwise the stale id→pointer pair leaks
      // and a later registerSession could reuse the id with a dead pointer.
      this.unregisterSession(sessionId);
    }
  }

  sessionSuspend(sessionId: number, suspend: boolean): void {
    native.sessionSuspend(this.toPtr(sessionId), suspend);
  }

  /**
   * Live re-apply of engine settings to the RUNNING session — no restart.
   * The JSON uses the same kebab-case session-setting keys
   * (TransmissionSession.buildSettingsJson) that sessionStart merges at init;
   * native funnels it through tr_sessionSet on the session's event thread.
   */
  sessionSettingsUpdate(sessionId: number, settingsJson: string): void {
    native.sessionSettingsUpdate(this.toPtr(sessionId), settingsJson);
  }

  hasDownloadingTorrents(sessionId: number): boolean {
    return native.hasDownloadingTorrents(this.toPtr(sessionId));
  }

  listTorrentNames(sessionId: number): string[] {
    return native.listTorrentNames(this.toPtr(sessionId));
  }

  // ═══════════════════════════════════════════════════════════════════
  // Torrent CRUD
  // ═══════════════════════════════════════════════════════════════════
  torrentAdd(
    sessionId: number, path: string, downloadDir: string | null,
    deleteFlag: boolean, paused: boolean
  ): number {
    // P0 fix (codex review): downloadDir is a JS string, NOT an ArrayBuffer.
    // The old code hand-encoded it to bytes, but native torrentAdd calls
    // getStringUtf8() on this arg — passing an ArrayBuffer made it return null
    // and tr_ctorSetDownloadDir got a null pointer (undefined behavior).
    const ptr = this.toPtr(sessionId);
    return native.torrentAdd(ptr, path, downloadDir, deleteFlag,
      false /*sequential*/, null /*unwantedIndexes*/, null /*hashOut*/, paused);
  }

  torrentRemove(sessionId: number, torrentId: number, removeData: boolean): void {
    native.torrentRemove(this.toPtr(sessionId), torrentId, removeData);
  }

  /**
   * Download a file over HTTP(S) to a local path.
   * D2 (docs/11): the AddTorrentPage URL flow fetches a .torrent into the app
   * cache with this, then adds it through torrentAdd(). Native enforces
   * http(s):// schemes (an arbitrary file:// URL would be a file-write vector).
   * @param url      http(s):// URL to fetch
   * @param dstPath  Absolute destination path (e.g. <cacheDir>/x.torrent)
   * @param timeout  Optional timeout in seconds (default 30)
   */
  curlDownload(url: string, dstPath: string, timeout?: number): void {
    native.curlDownload(url, dstPath, timeout ?? 30);
  }

  torrentStart(sessionId: number, torrentId: number): void {
    native.torrentStart(this.toPtr(sessionId), torrentId);
  }

  torrentStop(sessionId: number, torrentId: number): void {
    native.torrentStop(this.toPtr(sessionId), torrentId);
  }

  torrentVerify(sessionId: number, torrentId: number): void {
    native.torrentVerify(this.toPtr(sessionId), torrentId);
  }

  // ═══════════════════════════════════════════════════════════════════
  // Torrent File Listing
  // ═══════════════════════════════════════════════════════════════════
  torrentListFilesFromFile(path: string): string[] {
    return native.torrentListFilesFromFile(path);
  }

  torrentListFiles(sessionId: number, torrentId: number): string[] {
    return native.torrentListFiles(this.toPtr(sessionId), torrentId);
  }

  // ═══════════════════════════════════════════════════════════════════
  // Torrent Queries
  // ═══════════════════════════════════════════════════════════════════
  torrentFindByHash(sessionId: number, hash: ArrayBuffer): number {
    return native.torrentFindByHash(this.toPtr(sessionId), hash);
  }

  torrentGetName(sessionId: number, torrentId: number): string {
    return native.torrentGetName(this.toPtr(sessionId), torrentId);
  }

  torrentGetHash(sessionId: number, torrentId: number): Uint8Array {
    const buf = new ArrayBuffer(NativeBridge.SHA_DIGEST_LENGTH);
    native.torrentGetHash(this.toPtr(sessionId), torrentId, buf);
    return new Uint8Array(buf);
  }

  torrentGetFileName(sessionId: number, torrentId: number, fileIndex: number): string {
    return native.torrentGetFileName(this.toPtr(sessionId), torrentId, fileIndex);
  }

  torrentGetFileStat(sessionId: number, torrentId: number, fileIndex: number): ArrayBuffer {
    return native.torrentGetFileStat(this.toPtr(sessionId), torrentId, fileIndex);
  }

  // ═══════════════════════════════════════════════════════════════════
  // Torrent Statistics
  // ═══════════════════════════════════════════════════════════════════
  torrentStatBrief(sessionId: number): ArrayBuffer {
    return native.torrentStatBrief(this.toPtr(sessionId));
  }

  // ═══════════════════════════════════════════════════════════════════
  // Torrent Error / Control
  // ═══════════════════════════════════════════════════════════════════
  torrentGetError(sessionId: number, torrentId: number): string {
    return native.torrentGetError(this.toPtr(sessionId), torrentId);
  }

  /** Diagnostic: live native engine state as a compact string. */
  torrentState(sessionId: number, torrentId: number): string {
    return native.torrentState(this.toPtr(sessionId), torrentId);
  }

  torrentSetLocation(sessionId: number, torrentId: number, newDir: string): void {
    native.torrentSetLocation(this.toPtr(sessionId), torrentId, newDir);
  }

  // ═══════════════════════════════════════════════════════════════════
  // Stateless native calls (safe from a taskpool worker)
  //
  // @ohos.taskpool runs @Concurrent functions with ISOLATED JS heaps (Actor
  // model): the singleton's sessionMap is NOT shared with a worker, so
  // toPtr(sessionId) would throw there. Instead the UI thread resolves the
  // serializable BigInt pointer via getSessionPtr() and passes it in; these
  // statics call native.* directly with no `this` and no session-map lookup.
  // Use them only from @Concurrent functions, never on the main thread.
  // ═══════════════════════════════════════════════════════════════════
  static torrentAddByPtr(ptr: BigInt, path: string, downloadDir: string,
      deleteFlag: boolean, paused: boolean): number {
    return native.torrentAdd(ptr, path, downloadDir, deleteFlag,
      false /*sequential*/, null /*unwantedIndexes*/, null /*hashOut*/, paused);
  }

  static torrentSetLocationByPtr(ptr: BigInt, torrentId: number, newDir: string): void {
    native.torrentSetLocation(ptr, torrentId, newDir);
  }

  // ═══════════════════════════════════════════════════════════════════
  // ThreadSafeFunction (TSFN) events → ArkTS callbacks
  //
  // native_to_arkts.cc already registers nativeToArktsInit/Release and fires
  // them from libtransmission's session thread. Contracts (from CallJsCallback):
  //   onTorrentChanged / onTorrentStopped -> exactly one int32 arg (= torrent id)
  //   onSessionChanged / onAltSpeedChanged -> zero args
  // Native must be called BEFORE sessionStart, because SessionStart wires the
  // tr_session RPC callbacks that produce these events. The .d.ts declares a
  // loose (...args: Object[]) => void; adapt concrete signatures to it here.
  // ═══════════════════════════════════════════════════════════════════
  nativeToArktsInit(
    onTorrentChanged: (torrentId: number) => void = () => {},
    onTorrentStopped: (torrentId: number) => void = () => {},
    onSessionChanged: () => void = () => {},
    onAltSpeedChanged: () => void = () => {},
  ): void {
    native.nativeToArktsInit(
      (...args: Object[]) => { if (args.length > 0) { onTorrentChanged(args[0] as number); } },
      (...args: Object[]) => { if (args.length > 0) { onTorrentStopped(args[0] as number); } },
      (...args: Object[]) => { onSessionChanged(); },
      (...args: Object[]) => { onAltSpeedChanged(); },
    );
  }

  nativeToArktsRelease(): void {
    native.nativeToArktsRelease();
  }

  // ═══════════════════════════════════════════════════════════════════
  // Composite / Convenience methods
  // ═══════════════════════════════════════════════════════════════════
  torrentSetFileWanted(sessionId: number, torrentId: number, files: boolean[]): void {
    const skipIndices: number[] = [];
    for (let i = 0; i < files.length; i++) {
      if (!files[i]) {
        skipIndices.push(i);
      }
    }
    if (skipIndices.length === 0) {
      const emptyBuf = new ArrayBuffer(0);
      native.torrentSetDnd(this.toPtr(sessionId), torrentId, emptyBuf, false);
    } else {
      const buf = new ArrayBuffer(skipIndices.length * 4);
      const view = new Int32Array(buf);
      for (let i = 0; i < skipIndices.length; i++) {
        view[i] = skipIndices[i];
      }
      native.torrentSetDnd(this.toPtr(sessionId), torrentId, buf, true);
    }
  }

  torrentReannounce(sessionId: number, torrentId: number): void {
    native.torrentReannounce(this.toPtr(sessionId), torrentId);
  }

  // ═══════════════════════════════════════════════════════════════════
  // Internal helpers
  // ═══════════════════════════════════════════════════════════════════
  private static readonly SHA_DIGEST_LENGTH: number = 20;
}
