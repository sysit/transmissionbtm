import { describe, it, expect } from 'vitest';
import { TorrentStat, TorrentStatStatus, TORRENT_STAT_STATUS_LABELS } from '../entry/src/main/ets/models/TorrentStat.ets';

describe('TorrentStatStatus', () => {
  it('has five statuses', () => {
    expect(TorrentStatStatus.STOPPED).toBe(0);
    expect(TorrentStatStatus.CHECK).toBe(1);
    expect(TorrentStatStatus.DOWNLOAD).toBe(2);
    expect(TorrentStatStatus.SEED).toBe(3);
    expect(TorrentStatStatus.ERROR).toBe(4);
  });
});

describe('TORRENT_STAT_STATUS_LABELS', () => {
  it('has labels for all statuses', () => {
    expect(TORRENT_STAT_STATUS_LABELS[0]).toBe('Stopped');
    expect(TORRENT_STAT_STATUS_LABELS[1]).toBe('Checking');
    expect(TORRENT_STAT_STATUS_LABELS[2]).toBe('Downloading');
    expect(TORRENT_STAT_STATUS_LABELS[3]).toBe('Seeding');
    expect(TORRENT_STAT_STATUS_LABELS[4]).toBe('Error');
  });
});

describe('TorrentStat.fromArray', () => {
  it('parses stat from flat array', () => {
    // Layout: [torrentId, status, progress, totalLen, remaining, uploaded, peersUp, peersDown, speedUp, speedDown]
    const arr = [0, 2, 72, 1000000, 280000, 500000, 10, 5, 524288, 131072];
    const stat = TorrentStat.fromArray(arr);
    expect(stat.getStatus()).toBe(2);
    expect(stat.getProgress()).toBe(72);
    expect(stat.getTotalLength()).toBe(1000000);
    expect(stat.getRemainingLength()).toBe(280000);
    expect(stat.getUploadedLength()).toBe(500000);
    expect(stat.getPeersUp()).toBe(10);
    expect(stat.getPeersDown()).toBe(5);
    expect(stat.getSpeedUp()).toBe(524288);
    expect(stat.getSpeedDown()).toBe(131072);
  });

  it('defaults missing values to 0', () => {
    const stat = TorrentStat.fromArray([42, 0]);
    expect(stat.getProgress()).toBe(0);
    expect(stat.getStatus()).toBe(0);
  });

  it('supports offset into shared array', () => {
    const arr = [
      1, 4, 50, 500, 250, 100, 3, 0, 1024, 0,   // torrent 1
      2, 0, 0, 1000, 1000, 0, 0, 0, 0, 0,       // torrent 2
    ];
    const t1 = TorrentStat.fromArray(arr, 0);
    expect(t1.getStatus()).toBe(4);
    expect(t1.getTotalLength()).toBe(500);
    const t2 = TorrentStat.fromArray(arr, 10);
    expect(t2.getStatus()).toBe(0);
    expect(t2.getTotalLength()).toBe(1000);
  });
});

describe('TorrentStat.fromBuffer', () => {
  it('parses packed ArrayBuffer', () => {
    const buf = new ArrayBuffer(2 * 10 * 8); // 2 torrents * 10 int64 * 8 bytes
    const view = new BigInt64Array(buf);
    view[0] = BigInt(1); view[1] = BigInt(2); view[2] = BigInt(50);
    view[3] = BigInt(1000); view[4] = BigInt(500);
    view[10] = BigInt(2); view[11] = BigInt(0);
    const results = TorrentStat.fromBuffer(buf);
    expect(results.length).toBe(2);
  });
});
