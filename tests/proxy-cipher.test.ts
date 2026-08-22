// transmissionbtm — ProxyCipher marker contract (R7 #19/#25)
//
// The HUKS cipher itself (HukProxyCipher.ets) needs device @kit. It is
// device-verified by the EntryAbility startup self-test (`aa start` + hilog).
// This host test pins the SHARED marker contract that the store relies on:
//   - HUKS_PREFIX marks a HUKS-encrypted envelope ('huk1:')
//   - isHukStored() detects the prefix (and rejects plaintext/empty)
//   - LegacyProxyCipher (the default, plaintext fallback) round-trips
//     unaltered — so a pre-migration install keeps working until re-saved.

import { describe, it, expect } from 'vitest';
import {
  HUKS_PREFIX,
  LegacyProxyCipher,
  isHukStored,
} from '../entry/src/main/ets/security/ProxyCipher.ets';

describe('HUKS_PREFIX', () => {
  it('is the leading marker written before an encrypted envelope', () => {
    expect(HUKS_PREFIX).toBe('huk1:');
  });
});

describe('isHukStored', () => {
  it('detects a HUKS-encrypted envelope by prefix', () => {
    expect(isHukStored('huk1:aa:bb:cc')).toBe(true);
  });

  it('rejects legacy plaintext and empty strings', () => {
    expect(isHukStored('secret')).toBe(false);
    expect(isHukStored('')).toBe(false);
  });

  it('treats any value starting with the prefix as a HUKS envelope', () => {
    // A HUKS envelope always has two more ':'-separated parts; purely prefix-
    // matching is the contract, so a value like 'huk1:socks5' is treated as
    // HUKS. The decrypt path split-tests for 3 parts and returns null on
    // malformed input, so this cannot silently yield wrong data.
    expect(isHukStored('huk1:socks5')).toBe(true);
  });
});

describe('LegacyProxyCipher', () => {
  const cipher = new LegacyProxyCipher();

  it('round-trips plaintext unaltered (the pre-migration fallback)', async () => {
    const stored = await cipher.encrypt('p@ssw0rd');
    expect(stored).toBe('p@ssw0rd');
    expect(await cipher.decrypt(stored)).toBe('p@ssw0rd');
  });

  it('passes legacy plaintext through decrypt unchanged', async () => {
    expect(await cipher.decrypt('legacy-plain')).toBe('legacy-plain');
  });

  it('handles empty string', async () => {
    expect(await cipher.encrypt('')).toBe('');
    expect(await cipher.decrypt('')).toBe('');
  });
});
