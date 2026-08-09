// transmissionhm — Functional E2E tests (M7)
//
// In-process native session tests, run on device (plan tasks 7.1, 7.2, 7.8,
// 7.9, 7.10, 7.11, 7.12). These drive the REAL libtransmission session via
// NativeBridge, exactly as the production DownloadsPage does.
//
// Why in-process (not a background service): on HarmonyOS NEXT,
// ServiceExtensionAbility (type:"service") is system-app-only — declaring it
// fails install with `code:9568344 install parse profile prop check error`
// unless the device's install_list_capability.json whitelists the signature.
// The consumer Pura 80 test device (4VM0125513000074) has /system mounted
// erofs ro + SELinux, so the whitelist cannot be modified. The foreground
// service is therefore disabled; the session runs in the process that uses it.
//
// Network-dependent plan tasks (7.3 download integrity, 7.4 sequential
// download) need a reachable tracker + seeding peer — not available in the
// test harness — and 7.6 (boot auto-start) is impossible on a consumer
// device. 7.7 (WiFi-only) requires live network-state manipulation. Those are
// deferred; the file/session-level behavior is covered here.
//
// Fixtures: small self-generated .torrent files (base64-embedded) with a
// dead announce URL — valid metainfo, no peers. Tests add them paused and
// verify add/listing/file-selection/relocation/removal without needing data.
//
// Isolation: every test starts its session under a UNIQUE settingsDir +
// downloadDir beneath the test process filesDir, so no resume-data or
// metainfo state leaks between tests. Network features are disabled for
// determinism (no external traffic attempted).

import { describe, it, expect } from '@ohos/hypium';
import { abilityDelegatorRegistry } from '@kit.TestKit';
import { buffer } from '@kit.ArkTS';
import { fileIo as fs } from '@kit.CoreFileKit';
import { TransmissionSession } from '../../../main/ets/models/TransmissionSession';
import { defaultSessionConfig, SessionConfig } from '../../../main/ets/models/SessionConfig';
import { TorrentInfo } from '../../../main/ets/models/TorrentInfo';
import { TorrentFile, FilePriority } from '../../../main/ets/models/TorrentFile';

// ═════════════════════════════════════════════════════════════════════
// Fixtures — base64-encoded bencoded .torrent metainfo
// ═════════════════════════════════════════════════════════════════════

/** Multi-file torrent: info.name=fixture-dir, contains hello.txt (52 B). */
const TORRENT_FIXTURE_DIR =
  'ZDg6YW5ub3VuY2UzMDpodHRwOi8vMTI3LjAuMC4xOjkwOTEvYW5ub3VuY2UxMDpjcmVhdGVkIGJ5MzE6dHJhbnNtaXNzaW9uaG0tdGVzdC1maXh0dXJlLWdlbjQ6aW5mb2Q1OmZpbGVzbGQ2Omxlbmd0aGk1MmU0OnBhdGhsOTpoZWxsby50eHRlZWU0Om5hbWUxMTpmaXh0dXJlLWRpcjEyOnBpZWNlIGxlbmd0aGkxNjM4NGU2OnBpZWNlczIwOpskzZ0q5/cL/qEmCT8c8r89zZGHZWU=';

/** Ten single-file torrents: fixture-01 .. fixture-10 (concurrent test). */
const TORRENT_FIXTURE_BATCH: string[] = [
  'ZDg6YW5ub3VuY2UzMDpodHRwOi8vMTI3LjAuMC4xOjkwOTEvYW5ub3VuY2UxMDpjcmVhdGVkIGJ5MzE6dHJhbnNtaXNzaW9uaG0tdGVzdC1maXh0dXJlLWdlbjQ6aW5mb2Q2Omxlbmd0aGk4OGU0Om5hbWUxMDpmaXh0dXJlLTAxMTI6cGllY2UgbGVuZ3RoaTE2Mzg0ZTY6cGllY2VzMjA6bAr2zLfGMOaHFTTJwv5ZUrT7J0VlZQ==',
  'ZDg6YW5ub3VuY2UzMDpodHRwOi8vMTI3LjAuMC4xOjkwOTEvYW5ub3VuY2UxMDpjcmVhdGVkIGJ5MzE6dHJhbnNtaXNzaW9uaG0tdGVzdC1maXh0dXJlLWdlbjQ6aW5mb2Q2Omxlbmd0aGk4OWU0Om5hbWUxMDpmaXh0dXJlLTAyMTI6cGllY2UgbGVuZ3RoaTE2Mzg0ZTY6cGllY2VzMjA6mDFK7VOOfjEHdk/7D+YZ8asEe7FlZQ==',
  'ZDg6YW5ub3VuY2UzMDpodHRwOi8vMTI3LjAuMC4xOjkwOTEvYW5ub3VuY2UxMDpjcmVhdGVkIGJ5MzE6dHJhbnNtaXNzaW9uaG0tdGVzdC1maXh0dXJlLWdlbjQ6aW5mb2Q2Omxlbmd0aGk5MGU0Om5hbWUxMDpmaXh0dXJlLTAzMTI6cGllY2UgbGVuZ3RoaTE2Mzg0ZTY6cGllY2VzMjA6kR+DBU0WPbGMKcGRL3lKXyjzd/tlZQ==',
  'ZDg6YW5ub3VuY2UzMDpodHRwOi8vMTI3LjAuMC4xOjkwOTEvYW5ub3VuY2UxMDpjcmVhdGVkIGJ5MzE6dHJhbnNtaXNzaW9uaG0tdGVzdC1maXh0dXJlLWdlbjQ6aW5mb2Q2Omxlbmd0aGk5MWU0Om5hbWUxMDpmaXh0dXJlLTA0MTI6cGllY2UgbGVuZ3RoaTE2Mzg0ZTY6cGllY2VzMjA6iwm0Ckj1bGnhqJsoU1w5HT7MpFVlZQ==',
  'ZDg6YW5ub3VuY2UzMDpodHRwOi8vMTI3LjAuMC4xOjkwOTEvYW5ub3VuY2UxMDpjcmVhdGVkIGJ5MzE6dHJhbnNtaXNzaW9uaG0tdGVzdC1maXh0dXJlLWdlbjQ6aW5mb2Q2Omxlbmd0aGk5MmU0Om5hbWUxMDpmaXh0dXJlLTA1MTI6cGllY2UgbGVuZ3RoaTE2Mzg0ZTY6cGllY2VzMjA6Aq6SlKJdWJ3UQ7sKlVGg10Ny2HJlZQ==',
  'ZDg6YW5ub3VuY2UzMDpodHRwOi8vMTI3LjAuMC4xOjkwOTEvYW5ub3VuY2UxMDpjcmVhdGVkIGJ5MzE6dHJhbnNtaXNzaW9uaG0tdGVzdC1maXh0dXJlLWdlbjQ6aW5mb2Q2Omxlbmd0aGk5M2U0Om5hbWUxMDpmaXh0dXJlLTA2MTI6cGllY2UgbGVuZ3RoaTE2Mzg0ZTY6cGllY2VzMjA66SQRiag1406GYgUPJK/lqzA+16plZQ==',
  'ZDg6YW5ub3VuY2UzMDpodHRwOi8vMTI3LjAuMC4xOjkwOTEvYW5ub3VuY2UxMDpjcmVhdGVkIGJ5MzE6dHJhbnNtaXNzaW9uaG0tdGVzdC1maXh0dXJlLWdlbjQ6aW5mb2Q2Omxlbmd0aGk5NGU0Om5hbWUxMDpmaXh0dXJlLTA3MTI6cGllY2UgbGVuZ3RoaTE2Mzg0ZTY6cGllY2VzMjA6IjK0oeZaHCyPhKVa32UcPaFhMwFlZQ==',
  'ZDg6YW5ub3VuY2UzMDpodHRwOi8vMTI3LjAuMC4xOjkwOTEvYW5ub3VuY2UxMDpjcmVhdGVkIGJ5MzE6dHJhbnNtaXNzaW9uaG0tdGVzdC1maXh0dXJlLWdlbjQ6aW5mb2Q2Omxlbmd0aGk5NWU0Om5hbWUxMDpmaXh0dXJlLTA4MTI6cGllY2UgbGVuZ3RoaTE2Mzg0ZTY6cGllY2VzMjA6/VsnqOc4qkWIKc95/hRj26KMZCplZQ==',
  'ZDg6YW5ub3VuY2UzMDpodHRwOi8vMTI3LjAuMC4xOjkwOTEvYW5ub3VuY2UxMDpjcmVhdGVkIGJ5MzE6dHJhbnNtaXNzaW9uaG0tdGVzdC1maXh0dXJlLWdlbjQ6aW5mb2Q2Omxlbmd0aGk5NmU0Om5hbWUxMDpmaXh0dXJlLTA5MTI6cGllY2UgbGVuZ3RoaTE2Mzg0ZTY6cGllY2VzMjA6xiLLkv1rtt2hamiPizobXvnl6JBlZQ==',
  'ZDg6YW5ub3VuY2UzMDpodHRwOi8vMTI3LjAuMC4xOjkwOTEvYW5ub3VuY2UxMDpjcmVhdGVkIGJ5MzE6dHJhbnNtaXNzaW9uaG0tdGVzdC1maXh0dXJlLWdlbjQ6aW5mb2Q2Omxlbmd0aGk5N2U0Om5hbWUxMDpmaXh0dXJlLTEwMTI6cGllY2UgbGVuZ3RoaTE2Mzg0ZTY6cGllY2VzMjA6jsYee4Gic9AMcOaSeknf5gghOTxlZQ==',
];

// ═════════════════════════════════════════════════════════════════════
// Test helpers (module scope — ArkTS forbids nested functions)
// ═════════════════════════════════════════════════════════════════════

let filesBaseDir: string = '';

function getFilesBaseDir(): string {
  if (filesBaseDir === '') {
    const ctx = abilityDelegatorRegistry.getAbilityDelegator().getAppContext();
    filesBaseDir = ctx.filesDir;
  }
  return filesBaseDir;
}

function ensureDir(path: string): void {
  // accessSync returns true when the path exists — avoid mkdirSync's
  // "File exists" error on the app's already-created filesDir.
  if (fs.accessSync(path)) {
    return;
  }
  fs.mkdirSync(path, true);
}

/** Decode a base64 .torrent into a file under the test files dir. */
function writeTorrentFile(name: string, b64: string): string {
  const dir = getFilesBaseDir();
  ensureDir(dir);
  const path = `${dir}/${name}`;
  const buf = buffer.from(b64, 'base64');
  // Copy decoded bytes into a FRESH Buffer: HarmonyOS pool-allocates
  // Buffers with an unreliable underlying buffer/byteOffset (slicing or
  // viewing them threw "newByteLength is out of range" / wrote 0 bytes).
  // buffer.from(Buffer) copies to a clean, exact-size allocation whose
  // .buffer is directly writable.
  const copy = buffer.from(buf);
  const file = fs.openSync(path,
    fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
  try {
    fs.writeSync(file.fd, copy.buffer);
  } finally {
    fs.closeSync(file);
  }
  return path;
}

/**
 * Sleep for the given number of milliseconds (event-loop friendly).
 */
function sleep(ms: number): Promise<void> {
  return new Promise<void>((resolve) => {
    setTimeout(resolve, ms);
  });
}

/**
 * Poll getAllTorrents() until its length reaches `expected`, or timeout.
 * Needed for remove: tr_torrentRemove dispatches to the session's own
 * event thread and returns immediately, so the torrent disappears a few
 * milliseconds later (the production UI sees it via its 1s poll).
 */
async function waitForTorrentCount(session: TransmissionSession,
                                   expected: number,
                                   timeoutMs: number): Promise<boolean> {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    if (session.getAllTorrents().length === expected) {
      return true;
    }
    await sleep(25);
  }
  return session.getAllTorrents().length === expected;
}

/**
 * Build a SessionConfig isolated per test tag: unique settings + download
 * dirs under the app files dir, networking features disabled so no external
 * traffic is attempted (deterministic, offline).
 */
function makeIsolatedConfig(tag: string): SessionConfig {
  const base = getFilesBaseDir();
  const cfg = defaultSessionConfig();
  cfg.settingsDir = `${base}/e2e_${tag}`;
  cfg.downloadDir = `${base}/e2e_${tag}_dl`;
  ensureDir(cfg.settingsDir);
  ensureDir(cfg.downloadDir);
  cfg.enableRpc = false;
  cfg.enableRpcWhitelist = false;
  cfg.dhtEnabled = false;
  cfg.pexEnabled = false;
  cfg.lpdEnabled = false;
  cfg.utpEnabled = false;
  cfg.startAddedTorrents = false;
  cfg.peerPort = 0; // native picks a random port (peer-port-random-on-start)
  return cfg;
}

/** Add the multi-file fixture paused; returns its torrent id. */
function addFixtureDirTorrent(session: TransmissionSession,
                              cfg: SessionConfig,
                              paused: boolean): number {
  const path = writeTorrentFile('fixture-dir.torrent', TORRENT_FIXTURE_DIR);
  const result = session.addTorrent(path, cfg.downloadDir, paused);
  // result: 0=OK, 1=PARSE_ERR, 2=DUPLICATE, 3=OK_DELETE
  expect(result).assertEqual(0);
  const all = session.getAllTorrents();
  const found = all.find((t: TorrentInfo) => t.name === 'fixture-dir');
  expect(found !== undefined).assertTrue();
  return found ? found.id : -1;
}

export default function functionalE2ETest() {
  // ── 7.1 Session lifecycle ──────────────────────────────────────────
  describe('E2E_session_lifecycle', () => {
    it('7_1_session_start_stop_and_stat_brief', 0, async () => {
      const session = new TransmissionSession();
      const cfg = makeIsolatedConfig('lifecycle');
      await session.start(cfg);
      expect(session.isRunning()).assertTrue();
      expect(session.sessionId > 0).assertTrue();

      // Empty session: stat brief buffer is valid (non-null), no throw.
      const brief = session.getTorrentStatBriefAll();
      expect(brief !== null && brief !== undefined).assertTrue();

      session.stop();
      expect(session.isStopped()).assertTrue();
    });

    it('7_1b_suspend_then_resume_then_stop', 0, async () => {
      const session = new TransmissionSession();
      await session.start(makeIsolatedConfig('suspend'));
      session.suspend(true);
      expect(session.isSuspended()).assertTrue();
      session.suspend(false);
      expect(session.isRunning()).assertTrue();
      session.stop();
      expect(session.isStopped()).assertTrue();
    });
  });

  // ── 7.2 Torrent add (file) ─────────────────────────────────────────
  describe('E2E_torrent_add', () => {
    it('7_2_add_torrent_file_lists_name_and_files', 0, async () => {
      const session = new TransmissionSession();
      const cfg = makeIsolatedConfig('add');
      await session.start(cfg);
      const id = addFixtureDirTorrent(session, cfg, true);

      // Torrent metadata: name 'fixture-dir', one file hello.txt
      const all = session.getAllTorrents();
      const found = all.find((t: TorrentInfo) => t.id === id);
      expect(found !== undefined).assertTrue();
      if (found) {
        expect(found.name === 'fixture-dir').assertTrue();
      }

      const files: TorrentFile[] = session.listTorrentFiles(id);
      expect(files.length).assertEqual(1);
      expect(files[0].name.indexOf('hello.txt') >= 0).assertTrue();

      session.removeTorrent(id, false);
      session.stop();
    });
  });

  // ── 7.8 DnD (do-not-download) file selection ───────────────────────
  describe('E2E_dnd_file_selection', () => {
    it('7_8_mark_file_dnd_flips_wanted_state', 0, async () => {
      const session = new TransmissionSession();
      const cfg = makeIsolatedConfig('dnd');
      await session.start(cfg);
      const id = addFixtureDirTorrent(session, cfg, true);

      const files: TorrentFile[] = session.listTorrentFiles(id);
      expect(files.length).assertEqual(1);
      const file0 = files[0];
      expect(file0.wanted).assertTrue();

      // DnD: mark file 0 as unwanted → native torrentSetFileWanted
      file0.setWanted(false);
      expect(file0.wanted).assertFalse();
      expect(file0.priority).assertEqual(FilePriority.SKIP);

      // Verify the native side applied it: refreshStats reads back the
      // per-file stat whose status field is 2 (= !wanted) when DnD'd.
      file0.refreshStats(session.sessionId, id);
      expect(file0.priority).assertEqual(FilePriority.SKIP);

      session.removeTorrent(id, false);
      session.stop();
    });
  });

  // ── 7.9 10+ concurrent torrents ────────────────────────────────────
  describe('E2E_concurrent_torrents', () => {
    it('7_9_ten_torrents_added_and_listed', 0, async () => {
      const session = new TransmissionSession();
      const cfg = makeIsolatedConfig('concurrent');
      await session.start(cfg);
      expect(TORRENT_FIXTURE_BATCH.length).assertEqual(10);

      for (let i = 0; i < TORRENT_FIXTURE_BATCH.length; i++) {
        const path = writeTorrentFile(`fixture-${i}.torrent`,
          TORRENT_FIXTURE_BATCH[i]);
        const result = session.addTorrent(path, cfg.downloadDir, true);
        expect(result).assertEqual(0);
      }

      const all = session.getAllTorrents();
      expect(all.length).assertEqual(10);
      const brief = session.getTorrentStatBriefAll();
      // 10 int64 per torrent; 10 torrents ⇒ ≥ 800 bytes
      expect(brief.byteLength >= 10 * 80).assertTrue();

      for (const t of all) {
        session.removeTorrent(t.id, false);
      }
      session.stop();
    });
  });

  // ── 7.11 Data relocation ───────────────────────────────────────────
  describe('E2E_relocation', () => {
    it('7_11_set_location_completes_without_error', 0, async () => {
      const session = new TransmissionSession();
      const cfg = makeIsolatedConfig('relocate');
      await session.start(cfg);
      const id = addFixtureDirTorrent(session, cfg, true);

      const newDir = `${getFilesBaseDir()}/e2e_relocate_new`;
      ensureDir(newDir);
      session.setTorrentLocation(id, newDir);

      // Torrent still present after relocation
      const all = session.getAllTorrents();
      expect(all.find((t: TorrentInfo) => t.id === id) !== undefined).assertTrue();

      session.removeTorrent(id, false);
      session.stop();
    });
  });

  // ── 7.12 Removal (with / without data) ─────────────────────────────
  describe('E2E_removal', () => {
    it('7_12a_remove_without_data_leaves_no_torrent', 0, async () => {
      const session = new TransmissionSession();
      const cfg = makeIsolatedConfig('rm_nodata');
      await session.start(cfg);
      const id = addFixtureDirTorrent(session, cfg, true);
      session.removeTorrent(id, false);
      const removed = await waitForTorrentCount(session, 0, 3000);
      expect(removed).assertTrue();
      session.stop();
    });

    it('7_12b_remove_with_data_completes_without_error', 0, async () => {
      const session = new TransmissionSession();
      const cfg = makeIsolatedConfig('rm_data');
      await session.start(cfg);
      const id = addFixtureDirTorrent(session, cfg, true);
      session.removeTorrent(id, true);
      const removed = await waitForTorrentCount(session, 0, 3000);
      expect(removed).assertTrue();
      session.stop();
    });
  });
}
