// transmissionbtm — Proxy credential secrecy boundary (R7 #19/#25)
//
// Preferences persists the proxy password. This module abstracts HOW that
// password is stored so the plaintext never lands in the on-disk preferences
// XML when HUKS is available. The store writes a marker-prefixed envelope:
//
//   huk1:<base64(iv ‖ ciphertext)>   → HUKS AES-256-GCM encrypted
//   <any other string>               → legacy plaintext (pre-migration)
//
// Legacy plaintext is still read (so existing installs keep working) and is
// re-encrypted on the next save. A HUKS failure degrades to the legacy
// plaintext path — never a crash, and never silent data corruption: GCM is
// authenticated, so a wrong key/IV throws rather than yielding garbage.
//
// The cipher is injected so host vitest can drive the store logic with a fake
// cipher (no device HUKS needed); HukProxyCipher is the on-device impl.

/** Prefix marking a HUKS-encrypted password envelope. */
export const HUKS_PREFIX = 'huk1:';

/** The proxy-password secrecy contract encrypted/decrypted by a cipher impl. */
export interface ProxyCipher {
  /** Encrypt a plaintext password into a persistable envelope (possibly legacy plaintext on failure). */
  encrypt(plain: string): Promise<string>;
  /** Decrypt a stored envelope back to plaintext, or null when it cannot be decoded. */
  decrypt(stored: string): Promise<string | null>;
}

/** Plaintext passthrough — the legacy cipher and the host-test double. Never used alone on device. */
export class LegacyProxyCipher implements ProxyCipher {
  async encrypt(plain: string): Promise<string> {
    return plain;
  }
  async decrypt(stored: string): Promise<string | null> {
    return stored;
  }
}

/** True when a stored password was written by the HUKS cipher. */
export function isHukStored(stored: string): boolean {
  return stored.startsWith(HUKS_PREFIX);
}
