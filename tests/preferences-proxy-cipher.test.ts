// transmissionbtm — PreferencesManager proxy_password secrecy interception (R7 #19/#25)
//
// Proves the store-level contract on HOST (no device @kit): with any injected
// ProxyCipher, writing PrefKeys.PROXY_PASSWORD encrypts (stores the cipher
// envelope) and reading it decrypts. The default cipher on host is the plaintext
// LegacyProxyCipher; the device injects HukProxyCipher in EntryAbility. This
// test double stands in for that injection so the interception logic — the
// actual security boundary — is verified in CI rather than only on-device.

import { describe, it, expect, beforeAll, beforeEach } from 'vitest';
import { PreferencesManager, PrefKeys } from '../entry/src/main/ets/models/Preferences.ets';
import { defaultSessionConfig } from '../entry/src/main/ets/models/SessionConfig.ets';
import { ProxyCipher } from '../entry/src/main/ets/security/ProxyCipher.ets';

/** Fake cipher that wraps plaintext in the `huk1:` prefix and can force a null decode. */
class FakeCipher implements ProxyCipher {
  encryptCalls: string[] = [];
  decryptCalls: string[] = [];
  forceNull = false;

  async encrypt(plain: string): Promise<string> {
    this.encryptCalls.push(plain);
    return plain.length > 0 ? 'huk1:' + plain : plain;
  }

  async decrypt(stored: string): Promise<string | null> {
    this.decryptCalls.push(stored);
    if (this.forceNull) { return null; }
    return stored.startsWith('huk1:') ? stored.slice(5) : stored;
  }
}

// Non-password key used to prove the cipher is NOT invoked for ordinary values.
const OTHER_KEY = 'rpc_username';

describe('PreferencesManager proxy_password cipher interception', () => {
  let pm: PreferencesManager;
  let cipher: FakeCipher;

  beforeAll(async () => {
    pm = PreferencesManager.getInstance();
    await pm.init({} as never); // mock @kit.ArkData store
  });

  beforeEach(async () => {
    // Clean slate: clear + re-apply defaults (proxy_password = '' plainly).
    await pm.resetToDefaults();
    cipher = new FakeCipher();
    pm.setPasswordCipher(cipher);
  });

  it('encrypts proxy_password on write and decrypts on read', async () => {
    await pm.setString(PrefKeys.PROXY_PASSWORD, 's3cret');
    expect(cipher.encryptCalls).toEqual(['s3cret']); // cipher saw the plaintext

    const readBack = await pm.getString(PrefKeys.PROXY_PASSWORD, '');
    expect(cipher.decryptCalls.length).toBeGreaterThan(0);
    expect(cipher.decryptCalls[cipher.decryptCalls.length - 1]).toBe('huk1:s3cret');
    expect(readBack).toBe('s3cret'); // round-trips to plaintext
  });

  it('does NOT invoke the cipher for ordinary (non-password) keys', async () => {
    await pm.setString(OTHER_KEY, 'bob');
    expect(cipher.encryptCalls.length).toBe(0);

    const readBack = await pm.getString(OTHER_KEY, '');
    expect(cipher.decryptCalls.length).toBe(0); // no crypto on the read path either
    expect(readBack).toBe('bob');
  });

  it('reads legacy plaintext written before the cipher was installed', async () => {
    // Revert to the default plaintext cipher (no huk1: wrap) and save a value.
    pm.setPasswordCipher({
      encrypt: (p: string) => Promise.resolve(p),
      decrypt: (s: string) => Promise.resolve(s),
    });
    await pm.setString(PrefKeys.PROXY_PASSWORD, 'oldpass');

    // Now install the prefix-wrapping fake and read it back.
    pm.setPasswordCipher(cipher);
    const readBack = await pm.getString(PrefKeys.PROXY_PASSWORD, '');
    expect(readBack).toBe('oldpass'); // legacy value survives, no data loss
  });

  it('falls back to the default when the envelope cannot be decoded', async () => {
    await pm.setString(PrefKeys.PROXY_PASSWORD, 's3cret');
    cipher.forceNull = true; // HUKS key lost / broken envelope
    const readBack = await pm.getString(PrefKeys.PROXY_PASSWORD, '');
    expect(readBack).toBe(''); // returns def, never surfaces ciphertext
  });

  it('routes setSessionConfig proxy_password through the cipher', async () => {
    const cfg = defaultSessionConfig();
    cfg.proxyPassword = 'sessionpw';
    await pm.setSessionConfig(cfg);
    expect(cipher.encryptCalls).toContain('sessionpw');

    const read = await pm.getSessionConfig();
    // getSessionConfig reads proxy_password via getString → decrypt.
    expect(read.proxyPassword).toBe('sessionpw');
  });

  it('keeps a non-HUKS proxy_password field intact across setSessionConfig round-trip', async () => {
    // Guard against a regression where setSessionConfig wrote plaintext directly.
    const cfg = defaultSessionConfig();
    cfg.proxyPassword = 'abc';
    await pm.setSessionConfig(cfg);

    const stored = await pm.getString(PrefKeys.PROXY_PASSWORD, '');
    expect(stored).toBe('abc'); // decrypted back to plaintext by getString
    expect(stored.length).toBe(3);
  });
});
