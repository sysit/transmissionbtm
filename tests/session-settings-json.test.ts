// transmissionbtm — session-settings JSON contract (review batch 2026-11-08)
//
// Pins three settings-object properties that are invisible to a compile and
// silent at runtime:
//   1. `ratio-limit` is a JSON REAL. The engine's serializer only accepts a
//      real for a double (`to_double()` → `value_if<double>()`); stringify(3.0)
//      emits `3`, rapidjson parses int64, and the field is skipped.
//   2. `alt-speed-time-enabled` is sent. Without it the engine's scheduler is
//      off by default and the begin/end/day window is ignored.
//   3. The live re-apply path omits `download-dir` / `incomplete-dir`. Prefs
//      keep the unusable /storage/... defaults; sending them would point new
//      torrents at a directory the app cannot write.
//
// Drives the real TransmissionSession against the mocked native module and
// captures the JSON at the two native boundaries.

import { describe, it, expect, vi, beforeEach } from 'vitest';
import native from 'libtransmissionbtm_napi.so';
import {
  TransmissionSession,
} from '../entry/src/main/ets/models/TransmissionSession.ets';
import { defaultSessionConfig } from '../entry/src/main/ets/models/SessionConfig.ets';

async function startedSession(): Promise<{
  session: TransmissionSession;
  cfg: ReturnType<typeof defaultSessionConfig>;
}> {
  const cfg = defaultSessionConfig();
  cfg.downloadDir = '/data/app/el2/100/base/x/downloads';
  cfg.incompleteDir = '/data/app/el2/100/base/x/incomplete';
  // start() puts the session in RUNNING — updateSettings() is a no-op from
  // STOPPED (a page that outlived teardown must not resurrect it).
  const session = await new TransmissionSession().start(cfg);
  return { session, cfg };
}

beforeEach(() => {
  vi.restoreAllMocks();
  vi.spyOn(native, 'sessionStart').mockReturnValue(BigInt(1));
});

describe('session settings JSON', () => {
  it('serializes ratio-limit as a real so the engine does not drop it', async () => {
    const { session, cfg } = await startedSession();
    cfg.seedRatioLimit = 3; // integer-valued user input
    const spy = vi.spyOn(native, 'sessionSettingsUpdate');
    session.updateSettings(cfg);
    const json = spy.mock.calls[0][1] as string;
    expect(json).toContain('"ratio-limit":3.000000001');
  });

  it('enables the alt-speed scheduler whenever alt speed is enabled', async () => {
    const { session, cfg } = await startedSession();
    cfg.altSpeedEnabled = true;
    const spy = vi.spyOn(native, 'sessionSettingsUpdate');
    session.updateSettings(cfg);
    const parsed = JSON.parse(spy.mock.calls[0][1] as string) as Record<string, unknown>;
    expect(parsed['alt-speed-enabled']).toBe(true);
    expect(parsed['alt-speed-time-enabled']).toBe(true);
  });

  it('sends incomplete-dir at start — it has no native argument', async () => {
    const cfg = defaultSessionConfig();
    cfg.incompleteDir = '/data/app/el2/100/base/x/incomplete';
    const spy = vi.spyOn(native, 'sessionStart').mockReturnValue(BigInt(1));
    await new TransmissionSession().start(cfg);
    const json = spy.mock.calls[0][3] as string;
    const parsed = JSON.parse(json) as Record<string, unknown>;
    expect(parsed['incomplete-dir']).toBe(cfg.incompleteDir);
    expect(parsed['incomplete-dir-enabled']).toBe(true);
  });

  it('does not re-send download dirs on live re-apply', async () => {
    const { session, cfg } = await startedSession();
    const spy = vi.spyOn(native, 'sessionSettingsUpdate');
    session.updateSettings(cfg);
    const parsed = JSON.parse(spy.mock.calls[0][1] as string) as Record<string, unknown>;
    expect('download-dir' in parsed).toBe(false);
    expect('incomplete-dir' in parsed).toBe(false);
    expect('incomplete-dir-enabled' in parsed).toBe(false);
    // Encryption has no native arg on re-apply — it must ride in the JSON.
    expect(parsed['encryption']).toBe(1);
  });
});
