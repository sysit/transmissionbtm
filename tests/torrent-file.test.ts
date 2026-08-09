import { describe, it, expect } from 'vitest';
import { TorrentFile, FilePriority, RawFileEntry } from '../entry/src/main/ets/models/TorrentFile.ets';

describe('FilePriority', () => {
  it('has three priority values', () => {
    expect(FilePriority.SKIP).toBe(-1);
    expect(FilePriority.NORMAL).toBe(0);
    expect(FilePriority.HIGH).toBe(1);
  });
});

describe('TorrentFile', () => {
  const raw: RawFileEntry = {
    index: 0,
    name: 'video.mkv',
    size: 1048576000,
    bytesCompleted: 524288000,
    wanted: true,
    priority: 0,
  };

  it('constructs from RawFileEntry', () => {
    const f = TorrentFile.fromNative(raw, 1, 42, 3);
    expect(f.index).toBe(0);
    expect(f.name).toBe('video.mkv');
    expect(f.size).toBe(1048576000);
    expect(f.bytesCompleted).toBe(524288000);
    expect(f.wanted).toBe(true);
    expect(f.priority).toBe(FilePriority.NORMAL);
  });

  it('computes percentComplete', () => {
    const f = TorrentFile.fromNative(raw, 1, 42, 3);
    expect(f.percentComplete).toBe(0.5);
  });

  it('returns 0 progress for empty file', () => {
    const empty: RawFileEntry = { index: 0, name: 'empty.bin', size: 0, bytesCompleted: 0, wanted: true, priority: 0 };
    const f = TorrentFile.fromNative(empty, 1, 42, 3);
    expect(f.percentComplete).toBe(0);
  });

  it('isDirectory is false for regular files', () => {
    const f = TorrentFile.fromNative(raw, 1, 42, 3);
    expect(f.isDirectory).toBe(false);
  });

  it('isDirectory is true for dir-entry names', () => {
    const dir: RawFileEntry = { index: 1, name: 'subdir/', size: 0, bytesCompleted: 0, wanted: true, priority: 0 };
    const f = TorrentFile.fromNative(dir, 1, 42, 3);
    expect(f.isDirectory).toBe(true);
  });

  it('handles unwanted files', () => {
    const unwanted: RawFileEntry = { index: 1, name: 'skip.data', size: 1024, bytesCompleted: 0, wanted: false, priority: -1 };
    const f = TorrentFile.fromNative(unwanted, 1, 42, 3);
    expect(f.wanted).toBe(false);
    expect(f.priority).toBe(FilePriority.SKIP);
  });

  it('path defaults to name', () => {
    const f = TorrentFile.fromNative(raw, 1, 42, 3);
    expect(f.path).toBe('video.mkv');
  });
});
