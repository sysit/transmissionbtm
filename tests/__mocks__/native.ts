// Mock for libtransmissionbtm_napi.so
// N-API native module is unavailable in Node.js vitest runtime.
// All methods return sensible defaults for unit testing.
//
// Keep this list equal to the real N-API surface (the {"name", nullptr, …}
// entries in entry/src/main/cpp/*.cc + getVersion): a drifted mock hides a
// missing method until a host test hits it, then fails with "not a function".

export default {
  getVersion(): string { return '0.1.0-mock'; },
  sessionStart(): BigInt { return BigInt(0); },
  sessionStop(): void {},
  sessionSuspend(): void {},
  sessionSettingsUpdate(): void {},
  hasDownloadingTorrents(): boolean { return false; },
  listTorrentNames(): string[] { return []; },
  torrentAdd(): number { return 0; },
  torrentRemove(): void {},
  torrentStart(): void {},
  torrentStop(): void {},
  torrentVerify(): void {},
  torrentReannounce(): void {},
  torrentListFilesFromFile(): string[] { return []; },
  torrentListFiles(): string[] { return []; },
  torrentFindByHash(): number { return -1; },
  torrentGetName(): string { return ''; },
  torrentGetHash(_sessionId: number, _torrentId: number, _buf: ArrayBuffer): void {},
  torrentGetFileName(): string { return ''; },
  torrentGetFileStat(): ArrayBuffer { return new ArrayBuffer(0); },
  torrentStatBrief(): ArrayBuffer { return new ArrayBuffer(0); },
  torrentGetError(): string { return ''; },
  torrentState(): string { return ''; },
  torrentSetDnd(): void {},
  torrentSetLocation(): void {},
  curlDownload(): void {},
  nativeToArktsInit(): void {},
  nativeToArktsRelease(): void {},
};
