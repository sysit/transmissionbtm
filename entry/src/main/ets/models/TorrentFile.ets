// transmissionbtm — TorrentFile domain model
//
// Represents a single file within a torrent.
// Pure data: never touches NativeBridge. Per-file native reads (size,
// bytesCompleted, wanted, priority) are performed by TransmissionSession,
// which hands the raw stat buffer to this model via applyFileStat().

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

  get percentComplete(): number {
    return this.size > 0 ? this.bytesCompleted / this.size : 0;
  }

  get isDirectory(): boolean {
    return this.size === 0 && this.name.endsWith('/');
  }

  /**
   * Parse a single file from the raw JSON object returned by native.
   * Pure factory — the data is already fetched by TransmissionSession.
   */
  static fromNative(raw: RawFileEntry): TorrentFile {
    const f = new TorrentFile();
    f.index = raw.index;
    f.name = raw.name;
    f.path = raw.name; // native uses "name" as the relative path within the torrent
    f.size = raw.size;
    f.bytesCompleted = raw.bytesCompleted ?? 0;
    f.wanted = raw.wanted ?? true;
    f.priority = (raw.priority as FilePriority) ?? FilePriority.NORMAL;
    return f;
  }

  /**
   * Apply a native per-file stat buffer to this model.
   *
   * No NativeBridge access — TransmissionSession reads torrentGetFileStat()
   * and passes the raw ArrayBuffer in here. Only mutates this file's fields.
   * Layout (native torrent.cc):
   *   [0]=pieceSize, [1]=fileLength, [2]=byteOffset, [3]=firstPiece,
   *   [4]=lastPiece, [5]=status(0=normal,1=complete,2=dnd), [6+]=piece bitmap
   */
  applyFileStat(buf: ArrayBuffer): void {
    if (!buf || buf.byteLength < 48) {
      return;
    }
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
        // Treat as unsigned 64-bit: a bitmap int64 whose 64th bit (piece 63)
        // is set is NEGATIVE when read as a signed BigInt, and the Kernighan
        // loop would never reach 0 (infinite). asUintN yields the low 64 bits
        // so the popcount terminates for every realistic piece bitmap.
        const bf = BigInt.asUintN(64, BigInt(view[j]));
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
    const isDnd: boolean = Number(view[5]) === 2;
    this.priority = (isDnd ? FilePriority.SKIP : FilePriority.NORMAL) as FilePriority;
    this.wanted = !isDnd;
  }
}
