import { describe, it, expect } from 'vitest';
import {
  TorrentStatus,
  TorrentError,
  TorrentInfo,
} from '../entry/src/main/ets/models/TorrentInfo.ets';

describe('TorrentStatus', () => {
  it('has five status values', () => {
    expect(TorrentStatus.STOPPED).toBe(0);
    expect(TorrentStatus.CHECK).toBe(1);
    expect(TorrentStatus.DOWNLOAD).toBe(2);
    expect(TorrentStatus.SEED).toBe(3);
    expect(TorrentStatus.ERROR).toBe(4);
  });
});

describe('TorrentError', () => {
  it('has error enum values', () => {
    expect(TorrentError.OK).toBe(0);
    expect(TorrentError.TRACKER_WARNING).toBe(1);
    expect(TorrentError.TRACKER_ERROR).toBe(2);
    expect(TorrentError.LOCAL_ERROR).toBe(3);
  });
});

describe('TorrentInfo.fromStatArray', () => {
  it('parses a downloading torrent', () => {
    const arr = [1, 2, 50, 1000000, 500000, 1048576, 10, 25, 524288, 131072];
    const info = TorrentInfo.fromStatArray(arr, 'test.torrent', 'abc123');
    expect(info.id).toBe(1);
    expect(info.status).toBe(TorrentStatus.DOWNLOAD);
    expect(info.totalSize).toBe(1000000);
    expect(info.haveValid).toBe(500000);
    // arr idx8/9 carry native KBps (piece*Speed_KBps); model fields are bytes/s.
    expect(info.rateDownload).toBe(131072 * 1000);
    expect(info.rateUpload).toBe(524288 * 1000);
    expect(info.peersConnected).toBe(10);
    expect(info.peersTotal).toBe(25);
    expect(info.name).toBe('test.torrent');
    expect(info.hashString).toBe('abc123');
  });

  it('parses a stopped torrent', () => {
    const arr = [2, 0, 0, 500000, 500000, 0, 0, 0, 0, 0];
    const info = TorrentInfo.fromStatArray(arr, 'paused.torrent', 'def456');
    expect(info.id).toBe(2);
    expect(info.status).toBe(TorrentStatus.STOPPED);
    expect(info.totalSize).toBe(500000);
    expect(info.isStopped()).toBe(true);
  });

  it('parses a seeding torrent', () => {
    const arr = [3, 3, 100, 2000000, 0, 65536, 0, 5, 1024, 0];
    const info = TorrentInfo.fromStatArray(arr, 'seed.torrent', 'ghi789');
    expect(info.id).toBe(3);
    expect(info.status).toBe(TorrentStatus.SEED);
    expect(info.isSeeding()).toBe(true);
    expect(info.percentComplete).toBe(1);
  });
});

describe('TorrentInfo status methods', () => {
  it('isActive is true for download/seed/check', () => {
    const dl = TorrentInfo.fromStatArray([1, 2, 50, 100, 50, 1024, 5, 0, 512, 256], 'a', 'h1');
    expect(dl.isActive()).toBe(true);
    const seed = TorrentInfo.fromStatArray([2, 3, 100, 100, 0, 512, 0, 3, 1024, 0], 'b', 'h2');
    expect(seed.isActive()).toBe(true);
    const check = TorrentInfo.fromStatArray([3, 1, 0, 100, 100, 0, 0, 0, 0, 0], 'c', 'h3');
    expect(check.isActive()).toBe(true);
    const stopped = TorrentInfo.fromStatArray([4, 0, 0, 100, 100, 0, 0, 0, 0, 0], 'd', 'h4');
    expect(stopped.isActive()).toBe(false);
  });

  it('isStopped is true for status=0', () => {
    const s = TorrentInfo.fromStatArray([1, 0, 0, 100, 100, 0, 0, 0, 0, 0], 'x', 'hx');
    expect(s.isStopped()).toBe(true);
    const dl = TorrentInfo.fromStatArray([2, 2, 50, 100, 50, 1024, 5, 0, 512, 256], 'y', 'hy');
    expect(dl.isStopped()).toBe(false);
  });

  it('isDownloading is true for status=2', () => {
    const dl = TorrentInfo.fromStatArray([1, 2, 50, 100, 50, 1024, 5, 0, 512, 256], 'a', 'h');
    expect(dl.isDownloading()).toBe(true);
    const seed = TorrentInfo.fromStatArray([2, 3, 100, 100, 0, 0, 0, 3, 1024, 0], 'b', 'h');
    expect(seed.isDownloading()).toBe(false);
  });

  it('isSeeding is true for status=3', () => {
    const seed = TorrentInfo.fromStatArray([1, 3, 100, 100, 0, 0, 0, 3, 1024, 0], 'a', 'h');
    expect(seed.isSeeding()).toBe(true);
    const dl = TorrentInfo.fromStatArray([2, 2, 50, 100, 50, 1024, 5, 0, 512, 256], 'b', 'h');
    expect(dl.isSeeding()).toBe(false);
  });
});

describe('TorrentInfo.getStatusString', () => {
  it('returns correct strings for each status', () => {
    const stop = TorrentInfo.fromStatArray([1, 0, 0, 100, 100, 0, 0, 0, 0, 0], 'a', 'h');
    expect(stop.getStatusString()).toBe('Paused');
    const check = TorrentInfo.fromStatArray([2, 1, 0, 100, 100, 0, 0, 0, 0, 0], 'b', 'h');
    expect(check.getStatusString()).toBe('Verifying');
    const dl = TorrentInfo.fromStatArray([3, 2, 50, 100, 50, 1024, 5, 0, 512, 256], 'c', 'h');
    expect(dl.getStatusString()).toBe('Downloading');
    const seed = TorrentInfo.fromStatArray([4, 3, 100, 100, 0, 0, 0, 3, 1024, 0], 'd', 'h');
    expect(seed.getStatusString()).toBe('Seeding');
  });
});

describe('TorrentInfo.fromNativeJson', () => {
  it('parses native listTorrentNames format', () => {
    // Format: "id 40charhex name" per line. Hashes must be exactly 40 chars.
    const h1 = 'aaaaaaaaaabbbbbbbbbbccccccccccdddddddddd'; // exactly 40
    const h2 = '0000000000111111111122222222223333333333'; // exactly 40
    const raw = '5 ' + h1 + ' test.torrent\n6 ' + h2 + ' video.mkv';
    const infos = TorrentInfo.fromNativeJson(raw);
    expect(infos.length).toBe(2);
    expect(infos[0].id).toBe(5);
    expect(infos[0].name).toBe('test.torrent');
    expect(infos[0].hashString).toBe(h1);
    expect(infos[1].id).toBe(6);
    expect(infos[1].name).toBe('video.mkv');
  });

  it('returns empty array for empty/placeholder input', () => {
    expect(TorrentInfo.fromNativeJson('')).toEqual([]);
    expect(TorrentInfo.fromNativeJson('[]')).toEqual([]);
  });
});

describe('TorrentInfo serialization', () => {
  it('toJSON produces correct fields', () => {
    const info = TorrentInfo.fromStatArray([1, 2, 72, 1000, 280, 500, 3, 0, 1024, 512], 'test', 'hash');
    const json = info.toJSON();
    expect(json.id).toBe(1);
    expect(json.name).toBe('test');
    expect(json.hashString).toBe('hash');
    expect(json.status).toBe(2);
    expect(json.totalSize).toBe(1000);
  });
});
