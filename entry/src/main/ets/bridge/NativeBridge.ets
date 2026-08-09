import native from 'libtransmissionhm_napi.so';
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
      enableAuth, username, password, enableRpcWhitelist, rpcWhitelist, settingsJson
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
      hilog.warn(0x0001, TAG, 'sessionStop ignored: %{public}s', String(e));
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

  hasDownloadingTorrents(sessionId: number): boolean {
    return native.hasDownloadingTorrents(this.toPtr(sessionId));
  }

  listTorrentNames(sessionId: number): string[] {
    return native.listTorrentNames(this.toPtr(sessionId));
  }

  getEncryptionMode(sessionId: number): number {
    return native.getEncryptionMode(this.toPtr(sessionId));
  }

  transmissionVersion(): string {
    return native.transmissionVersion();
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

  torrentSetDnd(
    sessionId: number, torrentId: number, fileIndices: ArrayBuffer, dnd: boolean
  ): void {
    native.torrentSetDnd(this.toPtr(sessionId), torrentId, fileIndices, dnd);
  }

  torrentSetLocation(sessionId: number, torrentId: number, newDir: string): void {
    native.torrentSetLocation(this.toPtr(sessionId), torrentId, newDir);
  }

  // ═══════════════════════════════════════════════════════════════════
  // Hash Utilities
  // ═══════════════════════════════════════════════════════════════════
  hashBytesToString(hash: Uint8Array): string {
    // P2 fix (codex review): hash.buffer is the whole backing store; for a
    // sliced view that ignores byteOffset/byteLength and hex-encodes the
    // wrong region. Slice the view's exact span before handing it to native.
    const span: ArrayBuffer = hash.buffer.slice(hash.byteOffset,
      hash.byteOffset + hash.byteLength);
    return native.hashBytesToString(span);
  }

  hashStringToBytes(hashHex: string): Uint8Array {
    return new Uint8Array(native.hashStringToBytes(hashHex));
  }

  // ═══════════════════════════════════════════════════════════════════
  // Environment Variables
  // ═══════════════════════════════════════════════════════════════════
  envSet(name: string, value?: string): void {
    native.envSet(name, value ?? '');
  }

  // ═══════════════════════════════════════════════════════════════════
  // Callbacks / TSFN (ThreadSafeFunction)
  // ═══════════════════════════════════════════════════════════════════
  nativeToArktsInit(
    onTorrentChanged?: (...args: Object[]) => void,
    onTorrentStopped?: (...args: Object[]) => void,
    onSessionChanged?: (...args: Object[]) => void,
    onAltSpeedChanged?: (...args: Object[]) => void
  ): void {
    native.nativeToArktsInit(
      onTorrentChanged, onTorrentStopped, onSessionChanged, onAltSpeedChanged);
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
