// transmissionbtm — N-API type declarations (M1 full bridge)
// All 28 methods exported from libtransmissionbtm_napi.so.
// Signatures match C++ N-API exports exactly (ground truth: napi_get_cb_info arg extraction).

/**
 * Native module type declarations for libtransmissionbtm_napi.so.
 * Import via: import native from 'libtransmissionbtm_napi.so';
 */
declare module 'libtransmissionbtm_napi.so' {
  // ── Version ──────────────────────────────────────────
  function getVersion(): string;

  // ── Session lifecycle ────────────────────────────────
  function sessionStart(
    configDir: string,
    downloadsDir: string,
    encrMode: number,
    enableRpc: boolean,
    rpcPort: number,
    enableAuth: boolean,
    username: string,
    password: string,
    enableRpcWhitelist: boolean,
    rpcWhitelist: string,
    settingsJson?: string
  ): BigInt;  // tr_session* pointer as uint64 BigInt
  function sessionStop(session: BigInt, configDir: string): void;
  function sessionSuspend(session: BigInt, suspend: boolean): void;
  function sessionSettingsUpdate(session: BigInt, settingsJson: string): void;
  /** Point the engine at the bundled web UI before the first sessionStart.
   *  Sets TRANSMISSION_WEB_HOME (a static one-shot cache in tr_getWebClientDir),
   *  so call this before sessionStart. path = <filesDir>/public_html. */
  function sessionSetWebClientDir(path: string): void;
  function hasDownloadingTorrents(session: BigInt): boolean;
  function listTorrentNames(session: BigInt): string[];

  // ── Torrent CRUD ─────────────────────────────────────
  /** Returns: 0=OK, 1=PARSE_ERR, 2=DUPLICATE, 3=OK_DELETE */
  function torrentAdd(
    session: BigInt,
    path: string,
    downloadDir: string | null,   // P0 fix: string, not ArrayBuffer (native uses getStringUtf8); null = session default
    setDelete: boolean,
    sequential: boolean,
    unwantedIndexes: ArrayBuffer | null,  // Int32Array as ArrayBuffer
    hashOut: ArrayBuffer | null,          // 20-byte buffer for info hash
    paused?: boolean                      // true = stop immediately after creation
  ): number;
  function torrentRemove(session: BigInt, torrentId: number, removeData: boolean): void;
  function torrentStart(session: BigInt, torrentId: number): void;
  function torrentStop(session: BigInt, torrentId: number): void;
  function torrentVerify(session: BigInt, torrentId: number): void;

  // ── Torrent file listing ─────────────────────────────
  /** List files from a .torrent file (no session needed). */
  function torrentListFilesFromFile(path: string): string[];
  /** List files from an active torrent. */
  function torrentListFiles(session: BigInt, torrentId: number): string[];

  // ── Torrent queries ──────────────────────────────────
  /** Returns torrentId or -1 if not found. hash must be 20-byte ArrayBuffer. */
  function torrentFindByHash(session: BigInt, hash: ArrayBuffer): number;
  function torrentGetName(session: BigInt, torrentId: number): string;
  /** Writes 20-byte SHA1 info hash into hashOut. */
  function torrentGetHash(session: BigInt, torrentId: number, hashOut: ArrayBuffer): void;

  // ── File operations ──────────────────────────────────
  /** Get logical file name from torrent metadata. */
  function torrentGetFileName(session: BigInt, torrentId: number, fileIndex: number): string;
  /** Get detailed file stat. Returns ArrayBuffer of int64 values:
   *   [0]=pieceSize, [1]=fileLength, [2]=byteOffset, [3]=firstPiece,
   *   [4]=lastPiece, [5]=status(0=normal,1=complete,2=dnd),
   *   then piece availability bitfield (64 pieces per int64). */
  function torrentGetFileStat(session: BigInt, torrentId: number, fileIndex: number): ArrayBuffer;

  // ── Torrent statistics ───────────────────────────────
  /** Returns ArrayBuffer of int64 values: [id, status, progress, sizeWhenDone,
   *   leftUntilDone, uploaded, peersUp, peersDown, speedUp, speedDown] × N torrents. */
  function torrentStatBrief(session: BigInt): ArrayBuffer;
  /** Diagnostic: live native engine state as a compact string. */
  function torrentState(session: BigInt, torrentId: number): string;

  // ── Torrent error / control ──────────────────────────
  /** Get torrent error string (empty if no error). */
  function torrentGetError(session: BigInt, torrentId: number): string;
  /** Set files as "do not download". fileIndices is ArrayBuffer of int32 indices. */
  function torrentSetDnd(session: BigInt, torrentId: number, fileIndices: ArrayBuffer, dnd: boolean): void;
  /** Move torrent data to a new directory. */
  function torrentSetLocation(session: BigInt, torrentId: number, newDir: string): void;
  /** Force a manual tracker announce (tr_torrentManualUpdate). */
  function torrentReannounce(session: BigInt, torrentId: number): void;

  // ── HTTP download (libcurl) ──────────────────────────
  function curlDownload(url: string, dst: string, timeout: number): void;

  // ── ThreadSafeFunction callbacks ─────────────────────
  /** Initialize TSFN callbacks. Takes up to 4 ArkTS callback functions:
   *  onTorrentChanged, onTorrentStopped, onSessionChanged, onAltSpeedChanged */
  function nativeToArktsInit(
    onTorrentChanged?: (...args: Object[]) => void,
    onTorrentStopped?: (...args: Object[]) => void,
    onSessionChanged?: (...args: Object[]) => void,
    onAltSpeedChanged?: (...args: Object[]) => void
  ): void;
  function nativeToArktsRelease(): void;
}
