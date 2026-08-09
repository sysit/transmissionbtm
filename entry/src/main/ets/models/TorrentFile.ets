// transmissionhm — TorrentFile domain model
//
// Represents a single file within a torrent.
// Methods that mutate file state (setPriority, setWanted) call through
// NativeBridge and reload the full file list to build the correct DnD array.

import { NativeBridge } from '../bridge/NativeBridge';

export enum FilePriority {
  SKIP = -1,
  NORMAL = 0,
  HIGH = 1,
}

/** JSON shape returned by native torrentListFiles(). */
export interface RawFileEntry {
  index: number;
  name: string;
  size: number;
  bytesCompleted?: number;
  wanted?: boolean;
  priority: number;
}

export class TorrentFile {
  index: number = 0;
  name: string = '';
  path: string = '';
  size: number = 0;
  bytesCompleted: number = 0;
  priority: FilePriority = FilePriority.NORMAL;
  wanted: boolean = true;

  // Internal — set by listFromNative; used by setPriority / setWanted
  private _sessionId: number = -1;
  private _torrentId: number = -1;
  private _fileCount: number = 0;

  get percentComplete(): number {
    return this.size > 0 ? this.bytesCompleted / this.size : 0;
  }

  get isDirectory(): boolean {
    return this.size === 0 && this.name.endsWith('/');
  }

  // ═══════════════════════════════════════════════════════════════════
  // Static factories
  // ═══════════════════════════════════════════════════════════════════

  /**
   * Parse a single file from the raw JSON object returned by native.
   * Typically called as part of listFromNative; also usable when you have
   * a single file's JSON from the native file listing + manual construction.
   */
  static fromNative(raw: RawFileEntry, sessionId: number,
                    torrentId: number, fileCount: number): TorrentFile {
    const f = new TorrentFile();
    f.index = raw.index;
    f.name = raw.name;
    f.path = raw.name; // native uses "name" as the relative path within the torrent
    f.size = raw.size;
    f.bytesCompleted = raw.bytesCompleted ?? 0;
    f.wanted = raw.wanted ?? true;
    f.priority = (raw.priority as FilePriority) ?? FilePriority.NORMAL;
    f._sessionId = sessionId;
    f._torrentId = torrentId;
    f._fileCount = fileCount;
    return f;
  }

  /**
   * Fetch and parse all files for a torrent via NativeBridge.
   * Each returned TorrentFile is wired to the session/torrent so that
   * setPriority() and setWanted() work without extra parameters.
   */
  static listFromNative(sessionId: number, torrentId: number): TorrentFile[] {
    const bridge = NativeBridge.getInstance();
    const names: string[] = bridge.torrentListFiles(sessionId, torrentId);
    if (!names || names.length === 0) {
      return [];
    }
    const fileCount: number = names.length;
    return names.map((name: string, index: number): TorrentFile => {
      const entry: RawFileEntry = {
        index: index,
        name: name,
        size: 0,
        wanted: true,
        priority: 0,
      };
      return TorrentFile.fromNative(entry, sessionId, torrentId, fileCount);
    });
  }

  // ═══════════════════════════════════════════════════════════════════
  // Native-backed mutations
  // ═══════════════════════════════════════════════════════════════════

  /**
   * Set this file's download priority.
   * SKIP  → marks the file as unwanted (DnD).
   * NORMAL/HIGH → marks the file as wanted.
   */
  setPriority(priority: FilePriority): void {
    if (this._sessionId < 0 || this._torrentId < 0) {
      return;
    }
    const bridge = NativeBridge.getInstance();
    // Get file count from file list to build wanted array
    const names: string[] = bridge.torrentListFiles(this._sessionId, this._torrentId);
    if (!names || names.length === 0) {
      return;
    }
    const files: boolean[] = new Array<boolean>(names.length).fill(true);
    // SKIP = not wanted; NORMAL/HIGH = wanted
    files[this.index] = priority !== FilePriority.SKIP;
    bridge.torrentSetFileWanted(this._sessionId, this._torrentId, files);
    // Update local state
    this.priority = priority;
    this.wanted = priority !== FilePriority.SKIP;
  }

  /**
   * Set whether this file is wanted (downloaded).
   * wanted=true  → file will be downloaded.
   * wanted=false → file is skipped (DnD).
   */
  setWanted(wanted: boolean): void {
    if (this._sessionId < 0 || this._torrentId < 0) {
      return;
    }
    const bridge = NativeBridge.getInstance();
    const names: string[] = bridge.torrentListFiles(this._sessionId, this._torrentId);
    if (!names || names.length === 0) {
      return;
    }
    const files: boolean[] = new Array<boolean>(names.length).fill(true);
    files[this.index] = wanted;
    bridge.torrentSetFileWanted(this._sessionId, this._torrentId, files);
    this.wanted = wanted;
    if (!wanted) {
      this.priority = FilePriority.SKIP;
    } else if (this.priority === FilePriority.SKIP) {
      this.priority = FilePriority.NORMAL;
    }
  }

  /**
   * Refresh this file's stat fields from the native side.
   * Useful for polling updates on bytesCompleted and wanted state.
   */
  refreshStats(sessionId: number, torrentId: number): void {
    const bridge = NativeBridge.getInstance();
    const buf: ArrayBuffer = bridge.torrentGetFileStat(sessionId, torrentId, this.index);
    if (!buf || buf.byteLength < 48) {
      return;
    }
    // Layout: [0]=pieceSize, [1]=fileLength, [2]=byteOffset, [3]=firstPiece,
    //         [4]=lastPiece, [5]=status(0=normal,1=complete,2=dnd)
    const view = new BigInt64Array(buf);
    this.size = Number(view[1]);
    // bytesCompleted is estimated from piece availability bitmap.
    // A more precise value requires per-piece tracking; for now use
    // a rough estimate based on the bitfield density.
    if (Number(view[5]) === 1) {
      this.bytesCompleted = this.size; // fully complete
    } else {
      // Count available pieces from bitfield (indices 6+)
      let availPieces = 0;
      const totalPieces = view.length - 6;
      for (let j = 6; j < view.length; j++) {
        const bf = BigInt(view[j]);
        // Count set bits in this int64 (popcount via Brian Kernighan's algorithm)
        let v = bf;
        while (v !== BigInt(0)) {
          availPieces++;
          v = v & (v - BigInt(1));
        }
      }
      if (totalPieces > 0 && availPieces > 0) {
        this.bytesCompleted = Math.floor(
          (availPieces / (totalPieces * 64)) * this.size);
      } else {
        this.bytesCompleted = 0;
      }
    }
    this.priority = (Number(view[5]) === 2 ? FilePriority.SKIP : FilePriority.NORMAL) as FilePriority;
  }
}
