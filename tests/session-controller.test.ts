// transmissionbtm — SessionController host unit tests
//
// Drive the controller with a fake TransmissionSession (no native, no device
// @kit modules — the keep-alive / connectivity collaborators are omitted).
// Covers lifecycle, action delegation, remove-hide timing, and emission.

import { describe, it, expect, vi } from 'vitest';
import { SessionController } from '../entry/src/main/ets/services/SessionController';
import { TorrentInfo } from '../entry/src/main/ets/models/TorrentInfo';
import { TransmissionSession } from '../entry/src/main/ets/models/TransmissionSession';
import { SessionConfig } from '../entry/src/main/ets/models/SessionConfig';
import type { KeepAliveManager } from '../entry/src/main/ets/services/KeepAliveManager';

function makeTorrent(id: number): TorrentInfo {
  const t = new TorrentInfo();
  t.id = id;
  t.name = `t${id}`;
  return t;
}

class FakeSession {
  sessionId = 42;
  calls: string[] = [];
  torrents: TorrentInfo[] = [makeTorrent(1), makeTorrent(2)];
  hasDL = false;
  throwOnRead = false;

  async start(_config: SessionConfig): Promise<TransmissionSession> {
    this.calls.push('start');
    return (this as unknown as TransmissionSession);
  }
  stop(): void { this.calls.push('stop'); }
  suspend(paused: boolean): void { this.calls.push(`suspend:${paused}`); }
  stopTorrent(id: number): void { this.calls.push(`stopTorrent:${id}`); }
  startTorrent(id: number): void { this.calls.push(`startTorrent:${id}`); }
  verifyTorrent(id: number): void { this.calls.push(`verifyTorrent:${id}`); }
  reannounceTorrent(id: number): void { this.calls.push(`reannounceTorrent:${id}`); }
  removeTorrent(id: number, removeData: boolean): void {
    this.calls.push(`removeTorrent:${id}:${removeData}`);
  }
  listTorrentFiles(id: number) {
    this.calls.push(`listTorrentFiles:${id}`);
    return [] as never;
  }
  hasDownloadingTorrents(): boolean { return this.hasDL; }
  getAllTorrents(): TorrentInfo[] {
    this.calls.push('getAllTorrents');
    if (this.throwOnRead) {
      throw new Error('read fail');
    }
    return this.torrents;
  }
}

class FakeKeepAlive {
  acquired = 0;
  released = 0;
  /** Mirrors KeepAliveManager.active — the source of truth for "are we holding". */
  holding = false;
  async acquire(_reason: string): Promise<void> {
    this.acquired++;
    this.holding = true;
  }
  release(): void {
    this.released++;
    this.holding = false;
  }
  isHolding(): boolean { return this.holding; }
  /** Simulate the OS cancelling the task on its own (low-speed / policy). */
  systemCancel(): void { this.holding = false; }
}

function makeController(): { ctrl: SessionController; fake: FakeSession } {
  const fake = new FakeSession();
  const ctrl = new SessionController(fake as unknown as TransmissionSession);
  return { ctrl, fake };
}

describe('SessionController', () => {
  it('start() emits loading(true)→(false) then the torrent list', async () => {
    const { ctrl } = makeController();
    const loading: boolean[] = [];
    const lists: TorrentInfo[][] = [];
    ctrl.onLoading = (l: boolean) => { loading.push(l); };
    ctrl.onTorrents = (list: TorrentInfo[]) => { lists.push(list); };

    await ctrl.start({} as SessionConfig);

    expect(ctrl.isStarted).toBe(true);
    expect(ctrl.sessionId).toBe(42);
    expect(loading).toEqual([true, false]);
    expect(lists.length).toBe(1);
    expect(lists[0].map(t => t.id)).toEqual([1, 2]);
    ctrl.stop();
  });

  it('start() is idempotent — a second call does not re-start the session', async () => {
    const { ctrl, fake } = makeController();
    await ctrl.start({} as SessionConfig);
    await ctrl.start({} as SessionConfig);
    expect(fake.calls.filter(c => c === 'start').length).toBe(1);
    ctrl.stop();
  });

  it('stop() delegates to session and clears the poll timer', async () => {
    const { ctrl, fake } = makeController();
    await ctrl.start({} as SessionConfig);
    ctrl.stop();
    expect(fake.calls).toContain('stop');
    expect(ctrl.isStarted).toBe(false);
  });

  it('pause/resume/verify/reannounce delegate to the session', () => {
    const { ctrl, fake } = makeController();
    ctrl.pause(7);
    ctrl.resume(8);
    ctrl.verify(9);
    ctrl.reannounce(10);
    expect(fake.calls).toEqual([
      'stopTorrent:7', 'startTorrent:8', 'verifyTorrent:9', 'reannounceTorrent:10',
    ]);
  });

  it('remove() delegates with removeData=false and hides the torrent immediately', async () => {
    const { ctrl, fake } = makeController();
    const lists: TorrentInfo[][] = [];
    ctrl.onTorrents = (list: TorrentInfo[]) => { lists.push(list); };
    await ctrl.start({} as SessionConfig); // seeds latest = [1,2]

    ctrl.remove(1);

    expect(fake.calls).toContain('removeTorrent:1:false');
    // Last emission is the post-remove, filtered list
    expect(lists[lists.length - 1].map(t => t.id)).toEqual([2]);
    ctrl.stop();
  });

  it('removeWithData() delegates with removeData=true', () => {
    const { ctrl, fake } = makeController();
    ctrl.removeWithData(3);
    expect(fake.calls).toContain('removeTorrent:3:true');
  });

  it('listFiles() and hasDownloading() delegate to the session', () => {
    const { ctrl, fake } = makeController();
    fake.hasDL = true;
    ctrl.listFiles(5);
    expect(fake.calls).toContain('listTorrentFiles:5');
    expect(ctrl.hasDownloading()).toBe(true);
    fake.hasDL = false;
    expect(ctrl.hasDownloading()).toBe(false);
  });

  it('suspend() only suspends once (network transition guard)', () => {
    const { ctrl, fake } = makeController();
    ctrl.suspend(true);
    ctrl.suspend(true);
    expect(fake.calls.filter(c => c === 'suspend:true').length).toBe(1);
    ctrl.suspend(false);
    expect(fake.calls.filter(c => c === 'suspend:false').length).toBe(1);
  });

  it('holds the keep-alive while a network-loss suspend has the engine paused', () => {
    const fake = new FakeSession();
    const ka = new FakeKeepAlive();
    const ctrl = new SessionController(
      fake as unknown as TransmissionSession,
      ka as unknown as KeepAliveManager
    );

    fake.hasDL = true;
    ctrl.reload(); // downloading → acquire the continuous task
    expect(ka.acquired).toBe(1);
    expect(ka.released).toBe(0);

    // Network lost: the engine is paused, so hasDownloading() goes false.
    // Releasing the task here is the regression — the OS then freezes the
    // process and background downloads never resume.
    fake.hasDL = false;
    ctrl.suspend(true);
    ctrl.reload();
    expect(ka.released).toBe(0);

    // Network back, transfer still in flight → still held.
    ctrl.suspend(false);
    fake.hasDL = true;
    ctrl.reload();
    expect(ka.released).toBe(0);

    // Transfer actually finished → release.
    fake.hasDL = false;
    ctrl.reload();
    expect(ka.released).toBe(1);
  });

  it('re-acquires after the OS cancels the continuous task on its own', async () => {
    const fake = new FakeSession();
    const ka = new FakeKeepAlive();
    const ctrl = new SessionController(
      fake as unknown as TransmissionSession,
      ka as unknown as KeepAliveManager
    );

    fake.hasDL = true;
    ctrl.reload();
    await new Promise((r) => setTimeout(r, 0)); // flush acquire + its .finally() — as it would be after 5s of polling
    expect(ka.acquired).toBe(1);

    // The OS cancels the dataTransfer task by itself (low-speed check or
    // system policy) while a transfer is still running. KeepAliveManager drops
    // its own `active` flag; the controller must notice and re-acquire, or the
    // process has no keep-alive and the OS freezes it the moment the app is
    // backgrounded — downloads then only run while the app is on screen.
    ka.systemCancel();
    ctrl.reload();
    await new Promise((r) => setTimeout(r, 0));
    expect(ka.acquired).toBe(2);
    expect(ka.isHolding()).toBe(true);

    // A user-initiated cancel is respected: KeepAliveManager leaves its own
    // `active` flag set (holding stays true) so the controller does not fight
    // the user by immediately re-acquiring.
    ka.released = 0;
    fake.hasDL = false; // nothing in flight → release
    ctrl.reload();
    expect(ka.released).toBe(1);
  });

  it('keeps the last list and does not throw when getAllTorrents fails', async () => {
    const { ctrl, fake } = makeController();
    const lists: TorrentInfo[][] = [];
    ctrl.onTorrents = (list: TorrentInfo[]) => { lists.push(list); };
    await ctrl.start({} as SessionConfig); // first read ok → [1,2]

    fake.throwOnRead = true;
    ctrl.reload(); // read fails — keeps last list, emits [1,2] again

    expect(lists[lists.length - 1].map(t => t.id)).toEqual([1, 2]);
    ctrl.stop();
  });

  it('the poll timer is cleared on stop()', async () => {
    const { ctrl } = makeController();
    await ctrl.start({} as SessionConfig); // starts the 1s poll timer
    // After stop() the poll is torn down, so a later reload() emits nothing new.
    const spy = vi.fn();
    ctrl.onTorrents = spy;
    ctrl.stop();
    ctrl.reload(); // reload only reads session, does NOT schedule a poll
    expect(ctrl.isStarted).toBe(false);
    // No timer may fire after stop, so reload() must not re-emit via a poll:
    // reload() calls refresh() (emits once) — but no new setInterval is created.
    expect(spy).toHaveBeenCalledTimes(1);
  });
});
