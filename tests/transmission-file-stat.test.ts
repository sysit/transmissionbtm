// Host-side regression net for the R9 layering inversion (#24).
//
// Before: TorrentFile.refreshStats(sessionId, torrentId) called NativeBridge
// directly (a model → bridge inversion). After: the per-file native read lives
// on TransmissionSession.refreshFileStat(), which hands the raw stat buffer to
// the now-pure TorrentFile.applyFileStat(). This suite drives the facade
// through the vitest + native mock harness (vitest.config.ts aliases
// libtransmissionbtm_napi.so → tests/__mocks__/native.ts), so it verifies the
// relocated parse deterministically without the on-device runner (SIGABRT).

import { describe, it, expect, vi, beforeEach } from 'vitest';
import native from 'libtransmissionbtm_napi.so';
import { NativeBridge } from '../entry/src/main/ets/bridge/NativeBridge.ets';
import { TransmissionSession } from '../entry/src/main/ets/models/TransmissionSession.ets';
import { TorrentFile, FilePriority } from '../entry/src/main/ets/models/TorrentFile.ets';

// Build an int64 ArrayBuffer matching the native torrentGetFileStat() layout:
//   [0]=pieceSize, [1]=fileLength, [2]=byteOffset, [3]=firstPiece,
//   [4]=lastPiece, [5]=status(0=normal,1=complete,2=dnd), [6+]=piece bitmap
function craftFileStat(fields: number[]): ArrayBuffer {
  const buf = new ArrayBuffer(fields.length * 8);
  const v = new BigInt64Array(buf);
  fields.forEach((cell: number, i: number) => { v[i] = BigInt(cell); });
  return buf;
}

// Register a live session id through the mocked native.sessionStart.
function newSession(): TransmissionSession {
  vi.spyOn(native, 'sessionStart').mockReturnValue(BigInt(1));
  const sid: number = NativeBridge.getInstance().sessionStart(
    '/tmp/transmission-file-stat-test/settings', '/tmp/transmission-file-stat-test/downloads',
    1 /* encryption PREFER */, false /* rpc */, 9091, false /* auth */, '', '',
    false /* whitelist */, '*', '{}'
  );
  const session = new TransmissionSession();
  session.sessionId = sid;
  return session;
}

beforeEach(() => {
  vi.restoreAllMocks();
});

describe('TransmissionSession.refreshFileStat (relocated per-file read)', () => {
  it('applies a complete-status buffer (status=1) to the file', () => {
    const session = newSession();
    const file = TorrentFile.fromNative(
      { index: 0, name: 'a.bin', size: 0, wanted: true, priority: 0 });
    vi.spyOn(native, 'torrentGetFileStat').mockReturnValue(
      craftFileStat([1024, 10000, 0, 0, 0, 1, 0, 0])); // complete

    session.refreshFileStat(42, file);
    expect(file.size).toBe(10000);
    expect(file.bytesCompleted).toBe(10000);
    expect(file.priority).toBe(FilePriority.NORMAL);
    expect(file.wanted).toBe(true);
  });

  it('applies a DnD-status buffer (status=2) to the file', () => {
    const session = newSession();
    const file = TorrentFile.fromNative(
      { index: 1, name: 'b.bin', size: 0, wanted: true, priority: 0 });
    vi.spyOn(native, 'torrentGetFileStat').mockReturnValue(
      craftFileStat([1024, 10000, 0, 0, 0, 2, 0, 0])); // dnd

    session.refreshFileStat(42, file);
    expect(file.size).toBe(10000);
    expect(file.priority).toBe(FilePriority.SKIP);
    expect(file.wanted).toBe(false);
  });

  it('leaves the file untouched when the buffer is too short (< 48 bytes)', () => {
    const session = newSession();
    const file = TorrentFile.fromNative(
      { index: 2, name: 'c.bin', size: 99, wanted: true, priority: 0 });
    vi.spyOn(native, 'torrentGetFileStat').mockReturnValue(new ArrayBuffer(16));

    session.refreshFileStat(42, file);
    expect(file.size).toBe(99);      // unchanged
    expect(file.wanted).toBe(true);  // unchanged
  });

  it('estimates bytesCompleted from the piece bitmap when status=0', () => {
    const session = newSession();
    const file = TorrentFile.fromNative(
      { index: 3, name: 'd.bin', size: 0, wanted: true, priority: 0 });
    // status=0; two bitmap int64s, first fully set (-1 = 64 bits), second 0
    // → 64 available / 128 total → bytesCompleted = 64/128 * 10000 = 5000.
    vi.spyOn(native, 'torrentGetFileStat').mockReturnValue(
      craftFileStat([1024, 10000, 0, 0, 0, 0, -1, 0]));

    session.refreshFileStat(42, file);
    expect(file.size).toBe(10000);
    expect(file.bytesCompleted).toBe(5000);
    expect(file.priority).toBe(FilePriority.NORMAL);
    expect(file.wanted).toBe(true);
  });
});
