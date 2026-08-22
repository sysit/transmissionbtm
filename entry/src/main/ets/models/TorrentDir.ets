// transmissionbtm — TorrentDir domain model
//
// Represents a directory node in the torrent file tree.
// Aggregates stats (size, completed bytes) recursively from children.

import { TorrentFile } from './TorrentFile';

export class TorrentDir {
  name: string = '';
  path: string = '';
  children: TorrentDir[] = [];
  files: TorrentFile[] = [];
  parent: TorrentDir | null = null;
  depth: number = 0;

  /** Total size of all files under this directory (recursive). */
  get totalSize(): number {
    let size = 0;
    for (const f of this.files) {
      size += f.size;
    }
    for (const d of this.children) {
      size += d.totalSize;
    }
    return size;
  }

  /** Total bytes completed for all files under this directory (recursive). */
  get totalBytesCompleted(): number {
    let completed = 0;
    for (const f of this.files) {
      completed += f.bytesCompleted;
    }
    for (const d of this.children) {
      completed += d.totalBytesCompleted;
    }
    return completed;
  }

  /** Overall completion ratio for this directory (0.0–1.0). */
  get percentComplete(): number {
    const total = this.totalSize;
    return total > 0 ? this.totalBytesCompleted / total : 0;
  }

  /** Total number of files under this directory (recursive). */
  get fileCount(): number {
    let count = this.files.length;
    for (const d of this.children) {
      count += d.fileCount;
    }
    return count;
  }

  /** Total number of subdirectories under this directory (recursive). */
  get dirCount(): number {
    let count = this.children.length;
    for (const d of this.children) {
      count += d.dirCount;
    }
    return count;
  }
}
