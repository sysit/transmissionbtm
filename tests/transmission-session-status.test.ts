// Regression test for the user bug "两个种子都是pause状态".
//
// Root cause (read path): TransmissionSession.getAllTorrents() used to return
// TorrentInfo.fromNativeJson(names) without merging the live brief-stat buffer,
// so every torrent kept its default TorrentStatus.STOPPED (0) and rendered as
// "Paused" even while libtransmission was downloading it (native act=4).
//
// Fix: getAllTorrents() now runs applyStatBrief(), which overlays the brief
// stat row (status/percent/sizes/speeds) onto each TorrentInfo.
//
// This suite runs on the HOST via the vitest + native mock harness
// (vitest.config.ts aliases libtransmissionbtm_napi.so → tests/__mocks__/native.ts),
// so it verifies the merge deterministically without the on-device test runner
// (which currently SIGABRTs in HarmonyOS's own JsTestRunner::GetTestRunnerPath).

import { describe, it, expect, vi, beforeEach } from 'vitest';
import native from 'libtransmissionbtm_napi.so';
import { NativeBridge } from '../entry/src/main/ets/bridge/NativeBridge.ets';
import { TransmissionSession } from '../entry/src/main/ets/models/TransmissionSession.ets';
import { TorrentStatus } from '../entry/src/main/ets/models/TorrentInfo.ets';

// 40-char fake info-hashes (must be exactly 40 hex chars for fromNativeJson).
const HASH_A = 'aaaaaaaaaabbbbbbbbbbccccccccccdddddddddd'; // 40
const HASH_B = '0000000000111111111122222222223333333333'; // 40

// Build a BigInt64Array brief buffer matching the native torrentStatBrief()
// layout: 10 int64 per torrent, stride exactly 10.
//
// Row: [id, status, percent, totalLength, leftUntilDone, uploadedEver,
//       peersGettingFromUs, peersSendingToUs, speedUp, speedDown]
function craftBrief(rows: number[][]): ArrayBuffer {
  const buf = new ArrayBuffer(rows.length * 10 * 8);
  const v = new BigInt64Array(buf);
  rows.forEach((row: number[], i: number) => {
    const base = i * 10;
    row.forEach((cell: number, j: number) => {
      v[base + j] = BigInt(cell);
    });
  });
  return buf;
}

// Register a live session id through the mocked native.sessionStart
// (returns BigInt(0), which NativeBridge registers as id 1, 2, ...).
function newSession(): TransmissionSession {
  // The default mock returns BigInt(0), which NativeBridge.sessionStart treats
  // as a FAILED start (returns -1, never registers the id → toPtr throws →
  // getAllTorrents catches and returns []). Return a non-null tr_session* so
  // NativeBridge registers a live id that toPtr() can resolve.
  vi.spyOn(native, 'sessionStart').mockReturnValue(BigInt(1));
  const sid: number = NativeBridge.getInstance().sessionStart(
    '/tmp/transmission-session-test/settings', '/tmp/transmission-session-test/downloads',
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

describe('TransmissionSession.getAllTorrents status merge', () => {
  it('populates status=DOWNLOAD for an unpaused torrent (the "stays paused" bug)', () => {
    const session = newSession();
    vi.spyOn(native, 'listTorrentNames').mockReturnValue([
      `1 ${HASH_A} test.torrent`,
      `2 ${HASH_B} video.mkv`,
    ]);
    vi.spyOn(native, 'torrentStatBrief').mockReturnValue(craftBrief([
      [1, 2, 25, 1000, 750, 0, 3, 5, 0, 1024],   // id 1: DOWNLOAD
      [2, 3, 100, 2000, 0, 512, 0, 7, 4096, 0],  // id 2: SEED (100%)
    ]));

    const list = session.getAllTorrents();
    expect(list.length).toBe(2);

    // Torrent 1 — must NOT be STOPPED/Paused.
    expect(list[0].status).toBe(TorrentStatus.DOWNLOAD);
    expect(list[0].percentComplete).toBe(0.25);
    expect(list[0].totalSize).toBe(1000);
    expect(list[0].haveValid).toBe(250);
    expect(list[0].percentDone).toBe(0.25);
    expect(list[0].rateDownload).toBe(1024 * 1000); // idx9 is KBps → bytes/s
    expect(list[0].rateUpload).toBe(0);
    expect(list[0].peersConnected).toBe(3);
    expect(list[0].peersTotal).toBe(5);

    // Torrent 2 — seeding.
    expect(list[1].status).toBe(TorrentStatus.SEED);
    expect(list[1].percentComplete).toBe(1);
    expect(list[1].haveValid).toBe(2000);
  });

  it('leaves a torrent at STOPPED when it is absent from the brief buffer', () => {
    const session = newSession();
    vi.spyOn(native, 'listTorrentNames').mockReturnValue([`1 ${HASH_A} ghost.torrent`]);
    // Brief has only id 9; the ghost id 1 is not in it → stays default STOPPED.
    vi.spyOn(native, 'torrentStatBrief').mockReturnValue(
      craftBrief([[9, 3, 100, 100, 0, 0, 0, 0, 0, 0]])
    );

    const list = session.getAllTorrents();
    expect(list.length).toBe(1);
    expect(list[0].status).toBe(TorrentStatus.STOPPED);
  });

  it('handles an empty brief buffer without crashing (default STOPPED)', () => {
    const session = newSession();
    vi.spyOn(native, 'listTorrentNames').mockReturnValue([`1 ${HASH_A} x.torrent`]);
    vi.spyOn(native, 'torrentStatBrief').mockReturnValue(new ArrayBuffer(0));

    const list = session.getAllTorrents();
    expect(list.length).toBe(1);
    expect(list[0].status).toBe(TorrentStatus.STOPPED);
  });

  it('returns [] when the session has no torrents', () => {
    const session = newSession();
    vi.spyOn(native, 'listTorrentNames').mockReturnValue([]);

    const list = session.getAllTorrents();
    expect(list).toEqual([]);
  });
});
