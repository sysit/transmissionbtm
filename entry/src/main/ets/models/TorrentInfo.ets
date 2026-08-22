// transmissionbtm — TorrentInfo domain model
//
// Represents a single torrent loaded in the libtransmission session.
// Mapped from the stat array returned by native torrentStatBrief().
// Also parsed from the JSON returned by native listTorrentNames().

import { hilog } from '@kit.PerformanceAnalysisKit';

/**
 * BitTorrent status constants for the brief stat array.
 * Matches transmissionbtc TorrentStat.Status enum:
 *   STOPPED=0, CHECK=1, DOWNLOAD=2, SEED=3, ERROR=4.
 *
 * The native layer consolidates libtransmission's 7 tr_torrent_activity
 * values into 5 values when building the stat brief array
 * (CHECK_WAIT→CHECK, DOWNLOAD_WAIT→DOWNLOAD, SEED_WAIT→SEED,
 *  TR_STAT_LOCAL_ERROR→ERROR).
 */
export enum TorrentStatus {
  STOPPED = 0,
  CHECK = 1,
  DOWNLOAD = 2,
  SEED = 3,
  ERROR = 4,
}

/** Error codes (matching libtransmission tr_stat_errtype). */
export enum TorrentError {
  OK = 0,
  TRACKER_WARNING = 1,
  TRACKER_ERROR = 2,
  LOCAL_ERROR = 3,
}

/** Plain-object representation of TorrentInfo for persistence/debugging. */
export interface TorrentInfoJSON {
  id: number;
  name: string;
  hashString: string;
  status: number;
  error: number;
  errorString: string;
  totalSize: number;
  downloadedEver: number;
  uploadedEver: number;
  haveValid: number;
  percentComplete: number;
  percentDone: number;
  peersConnected: number;
  peersTotal: number;
  rateDownload: number;
  rateUpload: number;
  metadataPercentComplete: number;
  addedDate: number;
  eta: number;
  hasTorrentFile: boolean;
  queuePosition: number;
}

/** Full torrent state, parsed from the native stat array. */
export class TorrentInfo {
  id: number = -1;
  name: string = '';
  hashString: string = '';
  status: TorrentStatus = TorrentStatus.STOPPED;
  error: TorrentError = TorrentError.OK;
  errorString: string = '';

  // Sizes (bytes)
  totalSize: number = 0;
  downloadedEver: number = 0;
  uploadedEver: number = 0;
  haveValid: number = 0;

  // Progress
  percentComplete: number = 0;
  percentDone: number = 0;

  // Seeds & peers
  peersConnected: number = 0;
  peersTotal: number = 0;

  // Rates (bytes/sec)
  rateDownload: number = 0;
  rateUpload: number = 0;

  // Metadata
  metadataPercentComplete: number = 1;
  addedDate: number = 0;
  eta: number = -1;

  // User state
  hasTorrentFile: boolean = false;
  queuePosition: number = 0;

  /**
   * Parse from the 10-element stat array returned by native torrentStatBrief().
   *
   * Index mapping (matches transmissionbtc torrent.cc:718-777):
   *   arr[0] = torrentId       → id
   *   arr[1] = status (0-4)    → status (TorrentStatus enum)
   *   arr[2] = progress (0-100)→ percentComplete (÷100)
   *   arr[3] = totalLength     → totalSize
   *   arr[4] = remainingLength → haveValid = totalLength - remainingLength
   *   arr[5] = uploadedLength  → uploadedEver
   *   arr[6] = peersUp         → peersConnected
   *   arr[7] = peersDown       → peersTotal
   *   arr[8] = speedUp         → rateUpload
   *   arr[9] = speedDown       → rateDownload
   *
   * Fields NOT in brief stat (left at defaults): errorString,
   * metadataPercentComplete, addedDate, eta, hasTorrentFile, queuePosition.
   * downloadedEver is approximated as haveValid (bytes on disk) — the brief
   * stat carries no true lifetime downloadedEver, and the old
   * `haveValid + uploadedEver` sum was a nonsense figure (codex P2).
   */
  static fromStatArray(arr: number[], name: string, hashString: string): TorrentInfo {
    const info = new TorrentInfo();
    const len = arr.length;
    if (len < 10) {
      // Degraded: fill what we can
      info.id = arr[0] ?? -1;
      info.name = name;
      info.hashString = hashString;
      return info;
    }
    const totalLength: number = arr[3] ?? 0;
    const remainingLength: number = arr[4] ?? 0;

    info.id = arr[0] ?? -1;
    info.status = arr[1] as TorrentStatus;
    info.percentComplete = (arr[2] ?? 0) / 100;
    info.totalSize = totalLength;
    info.uploadedEver = arr[5] ?? 0;
    info.peersConnected = arr[6] ?? 0;
    info.peersTotal = arr[7] ?? 0;
    info.rateUpload = arr[8] ?? 0;
    info.rateDownload = arr[9] ?? 0;

    info.haveValid = totalLength - remainingLength;
    info.percentDone = totalLength > 0
      ? info.haveValid / totalLength
      : 0;
    // P2 fix (codex review): was `haveValid + uploadedEver` — a nonsense sum.
    info.downloadedEver = info.haveValid;
    info.error = info.status === TorrentStatus.ERROR
      ? TorrentError.LOCAL_ERROR : TorrentError.OK;
    info.name = name;
    info.hashString = hashString;
    return info;
  }

  /**
   * Parse the plain-text list returned by native listTorrentNames().
   *
   * Native format (transmissionbtc transmission.cc:256-273):
   *   Each line: "%d %s %s" (id, 40-char hex hashString, name).
   *   Lines are separated by newlines.
   *
   * M0 fallback: returns '[]' (no torrents loaded).
   * M1: returns newline-separated torrent entries.
   */
  static fromNativeJson(raw: string): TorrentInfo[] {
    if (!raw || raw === '[]' || raw === '') {
      return [];
    }
    const result: TorrentInfo[] = [];
    const lines = raw.split('\n');
    for (let i = 0; i < lines.length; i++) {
      const line = lines[i].trim();
      if (!line) {
        continue;
      }
      // Format: "<id> <40-char-hash> <name>"
      const firstSpace = line.indexOf(' ');
      if (firstSpace < 0) {
        hilog.warn(0x0001, 'TorrentInfo',
          'fromNativeJson: skipping malformed line (no space): %{private}s', line);
        continue;
      }
      const id = parseInt(line.substring(0, firstSpace));
      if (isNaN(id)) {
        continue;
      }
      const rest = line.substring(firstSpace + 1);
      // Hash hex string is exactly 40 characters
      if (rest.length < 42) {
        continue; // Need at least space + name char after 40-char hash
      }
      const hashString = rest.substring(0, 40);
      const name = rest.substring(41); // Skip the space after hash
      const info = new TorrentInfo();
      info.id = id;
      info.hashString = hashString;
      info.name = name;
      result.push(info);
    }
    return result;
  }

  /** Serialize to a plain object for persistence or debugging. */
  toJSON(): TorrentInfoJSON {
    return {
      id: this.id,
      name: this.name,
      hashString: this.hashString,
      status: this.status,
      error: this.error,
      errorString: this.errorString,
      totalSize: this.totalSize,
      downloadedEver: this.downloadedEver,
      uploadedEver: this.uploadedEver,
      haveValid: this.haveValid,
      percentComplete: this.percentComplete,
      percentDone: this.percentDone,
      peersConnected: this.peersConnected,
      peersTotal: this.peersTotal,
      rateDownload: this.rateDownload,
      rateUpload: this.rateUpload,
      metadataPercentComplete: this.metadataPercentComplete,
      addedDate: this.addedDate,
      eta: this.eta,
      hasTorrentFile: this.hasTorrentFile,
      queuePosition: this.queuePosition,
    };
  }

  // ═══════════════════════════════════════════════════════════════════
  // Status queries
  // ═══════════════════════════════════════════════════════════════════

  isActive(): boolean {
    return this.status === TorrentStatus.DOWNLOAD ||
      this.status === TorrentStatus.SEED ||
      this.status === TorrentStatus.CHECK;
  }

  isStopped(): boolean {
    return this.status === TorrentStatus.STOPPED;
  }

  isDownloading(): boolean {
    return this.status === TorrentStatus.DOWNLOAD;
  }

  isSeeding(): boolean {
    return this.status === TorrentStatus.SEED;
  }

  isChecking(): boolean {
    return this.status === TorrentStatus.CHECK;
  }

  /**
   * All wanted bytes are on disk.
   *
   * C4 (docs/11): checked together with the C1-fixed getPercentDone — both
   * percentComplete and percentDone derive from size_when_done /
   * left_until_done, so a fresh torrent is 0% and a complete one is 100%.
   * The OR is intentional: during TR_STATUS_CHECK the native brief stat puts
   * verify progress (not download progress) in arr[2], so percentComplete can
   * lag at < 1.0 while percentDone is already 1.0 (all data downloaded,
   * verification still running).
   */
  isFinished(): boolean {
    return this.percentComplete >= 1.0 || this.percentDone >= 1.0;
  }

  /**
   * The 5-value stat array consolidates wait states into active statuses
   * (CHECK_WAIT→CHECK, DOWNLOAD_WAIT→DOWNLOAD, SEED_WAIT→SEED).
   * Queued status cannot be detected from the brief stat array alone.
   * Always returns false from brief stats.
   */
  isQueued(): boolean {
    return false;
  }

  hasError(): boolean {
    return this.error !== TorrentError.OK;
  }

  getStatusString(): string {
    if (this.error !== TorrentError.OK || this.status === TorrentStatus.ERROR) {
      return this.errorString.length > 0 ? this.errorString : 'Error';
    }
    switch (this.status) {
      case TorrentStatus.STOPPED:
        return this.isFinished() ? 'Completed' : 'Paused';
      case TorrentStatus.CHECK:
        return 'Verifying';
      case TorrentStatus.DOWNLOAD:
        return 'Downloading';
      case TorrentStatus.SEED:
        return 'Seeding';
      default:
        return 'Unknown';
    }
  }

  getStatusColor(): string {
    if (this.error !== TorrentError.OK || this.status === TorrentStatus.ERROR) {
      return '#ef4444';
    }
    switch (this.status) {
      case TorrentStatus.DOWNLOAD:
        return '#3b82f6';
      case TorrentStatus.SEED:
        return '#22c55e';
      case TorrentStatus.CHECK:
        return '#6366f1';
      case TorrentStatus.STOPPED:
        return this.isFinished() ? '#22c55e' : '#f59e0b';
      default:
        return '#9ca0ab';
    }
  }
}
