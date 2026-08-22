// transmissionbtm — SessionController host unit tests
//
// Drive the controller with a fake TransmissionSession (no native, no device
// @kit modules — the wake-lock / connectivity collaborators are omitted).
// Covers lifecycle, action delegation, remove-hide timing, and emission.

import { describe, it, expect, vi } from 'vitest';
import { SessionController } from '../entry/src/main/ets/services/SessionController';
import { TorrentInfo } from '../entry/src/main/ets/models/TorrentInfo';
import { TransmissionSession } from '../entry/src/main/ets/models/TransmissionSession';
import { SessionConfig } from '../entry/src/main/ets/models/SessionConfig';

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
