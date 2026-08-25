// transmissionbtm — HUKS AES-256-GCM cipher for the proxy password (R7 #19/#25)
//
// GCM/tag/IV handling is ported from v2rayHM's known-good SecureStorage.ets
// (same SDK, same @kit imports): encrypted output is `ciphertext || tag(16)`;
// on decrypt the tag is split out and supplied via HUKS_TAG_AE_TAG, the IV via
// HUKS_TAG_NONCE, and a 1-byte AAD via HUKS_TAG_ASSOCIATED_DATA.
//
// Serialized envelope (the value persisted under PrefKeys.PROXY_PASSWORD):
//   `huk1:<iv_b64>:<ciphertext_b64>:<tag_b64>`   base64 has no ':' so split is safe
//
// Failure contract: GCM is authenticated, so a wrong key/IV/alias throws rather
// than yielding garbage. encrypt() returns the plaintext (legacy fallback) on a
// HUKS error — never throws, never corrupts existing data. decrypt() returns
// null on a decode/verify error so the caller can discard a broken envelope.
// IMPORTANT (from v2rayHM): HUKS keys can be lost on some emulators after a
// force-stop — decrypt() then returns null, so the caller sees an unset password
// (one re-entry) instead of a crash.

import { huks } from '@kit.UniversalKeystoreKit';
import cryptoFramework from '@ohos.security.cryptoFramework';
import { util } from '@kit.ArkTS';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { HUKS_PREFIX, ProxyCipher, isHukStored } from './ProxyCipher';

const DOMAIN = 0x0001;
const TAG = 'HukProxyCipher';
const KEY_ALIAS = 'transmissionbtm_proxy_password';
/** AES-256-GCM nonce length: 96-bit. */
const IV_LEN = 12;
/** AES-256-GCM auth tag length: 128-bit. */
const TAG_LEN = 16;

/** Three base64 parts of the HUKS envelope. */
interface EncryptedData {
  iv: string;
  ciphertext: string;
  tag: string;
}

export class HukProxyCipher implements ProxyCipher {
  private keyReady: boolean = false;

  // ── HUKS parameter builders ─────────────────────────────────────

  private keyGenProps(): huks.HuksParam[] {
    return [
      { tag: huks.HuksTag.HUKS_TAG_ALGORITHM, value: huks.HuksKeyAlg.HUKS_ALG_AES },
      { tag: huks.HuksTag.HUKS_TAG_KEY_SIZE, value: huks.HuksKeySize.HUKS_AES_KEY_SIZE_256 },
      { tag: huks.HuksTag.HUKS_TAG_PURPOSE,
        value: huks.HuksKeyPurpose.HUKS_KEY_PURPOSE_ENCRYPT | huks.HuksKeyPurpose.HUKS_KEY_PURPOSE_DECRYPT },
      { tag: huks.HuksTag.HUKS_TAG_DIGEST, value: huks.HuksKeyDigest.HUKS_DIGEST_NONE },
      { tag: huks.HuksTag.HUKS_TAG_PADDING, value: huks.HuksKeyPadding.HUKS_PADDING_NONE },
      { tag: huks.HuksTag.HUKS_TAG_BLOCK_MODE, value: huks.HuksCipherMode.HUKS_MODE_GCM },
    ];
  }

  private encryptProps(nonce: Uint8Array): huks.HuksParam[] {
    return [
      { tag: huks.HuksTag.HUKS_TAG_ALGORITHM, value: huks.HuksKeyAlg.HUKS_ALG_AES },
      { tag: huks.HuksTag.HUKS_TAG_KEY_SIZE, value: huks.HuksKeySize.HUKS_AES_KEY_SIZE_256 },
      { tag: huks.HuksTag.HUKS_TAG_PURPOSE, value: huks.HuksKeyPurpose.HUKS_KEY_PURPOSE_ENCRYPT },
      { tag: huks.HuksTag.HUKS_TAG_PADDING, value: huks.HuksKeyPadding.HUKS_PADDING_NONE },
      { tag: huks.HuksTag.HUKS_TAG_BLOCK_MODE, value: huks.HuksCipherMode.HUKS_MODE_GCM },
      { tag: huks.HuksTag.HUKS_TAG_NONCE, value: nonce },
      { tag: huks.HuksTag.HUKS_TAG_ASSOCIATED_DATA, value: new Uint8Array(1) },
    ];
  }

  private decryptProps(nonce: Uint8Array, tag: Uint8Array): huks.HuksParam[] {
    return [
      { tag: huks.HuksTag.HUKS_TAG_ALGORITHM, value: huks.HuksKeyAlg.HUKS_ALG_AES },
      { tag: huks.HuksTag.HUKS_TAG_KEY_SIZE, value: huks.HuksKeySize.HUKS_AES_KEY_SIZE_256 },
      { tag: huks.HuksTag.HUKS_TAG_PURPOSE, value: huks.HuksKeyPurpose.HUKS_KEY_PURPOSE_DECRYPT },
      { tag: huks.HuksTag.HUKS_TAG_PADDING, value: huks.HuksKeyPadding.HUKS_PADDING_NONE },
      { tag: huks.HuksTag.HUKS_TAG_BLOCK_MODE, value: huks.HuksCipherMode.HUKS_MODE_GCM },
      { tag: huks.HuksTag.HUKS_TAG_NONCE, value: nonce },
      { tag: huks.HuksTag.HUKS_TAG_ASSOCIATED_DATA, value: new Uint8Array(1) },
      { tag: huks.HuksTag.HUKS_TAG_AE_TAG, value: tag },
    ];
  }

  // ── Key management ───────────────────────────────────────────────

  private async ensureKey(): Promise<void> {
    if (this.keyReady) { return; }
    try {
      const exists = await huks.isKeyItemExist(KEY_ALIAS, { properties: [] });
      if (exists) { return; }
      await huks.generateKeyItem(KEY_ALIAS, { properties: this.keyGenProps() });
    } catch (_) {
      // isKeyItemExist may throw on API mismatch / HUKS unavailable. Try to
      // generate directly; if that also fails we fall back to plaintext anyway.
      try {
        await huks.generateKeyItem(KEY_ALIAS, { properties: this.keyGenProps() });
      } catch (_) {
        // HUKS key generation unsupported here — callers fall back to plaintext.
      }
    }
    this.keyReady = true;
  }

  // ── Typed byte helpers ───────────────────────────────────────────

  private randomBytes(len: number): Uint8Array {
    return cryptoFramework.createRandom().generateRandomSync(len).data;
  }

  private strToBytes(s: string): Uint8Array {
    return new util.TextEncoder().encodeInto(s);
  }

  private bytesToStr(b: Uint8Array): string {
    return new util.TextDecoder('utf-8').decodeToString(b);
  }

  private b64Encode(b: Uint8Array): string {
    return new util.Base64Helper().encodeToStringSync(b);
  }

  private b64Decode(s: string): Uint8Array {
    return new util.Base64Helper().decodeSync(s);
  }

  // ── ProxyCipher impl ─────────────────────────────────────────────

  async encrypt(plain: string): Promise<string> {
    if (plain.length === 0) { return plain; }
    try {
      await this.ensureKey();
      const nonce = this.randomBytes(IV_LEN);
      const opts: huks.HuksOptions = {
        properties: this.encryptProps(nonce),
        inData: this.strToBytes(plain),
      };
      const session = await huks.initSession(KEY_ALIAS, opts);
      const result = await huks.finishSession(session.handle, opts);
      const out = result.outData ?? new Uint8Array(0); // ciphertext || tag (nonce not included)
      // Non-empty plaintext always yields >= 1 ciphertext byte, so out.length > TAG_LEN.
      // Guard only rejects an all-tag / empty output (a genuine HUKS error) instead of
      // misreading the 12-byte nonce as part of `out` and throwing for short passwords.
      if (out.length <= TAG_LEN) { throw new Error('HUKS short output'); }
      const ciphertext = out.slice(0, out.length - TAG_LEN);
      const tag = out.slice(out.length - TAG_LEN);
      return HUKS_PREFIX +
        this.b64Encode(nonce) + ':' + this.b64Encode(ciphertext) + ':' + this.b64Encode(tag);
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'encrypt failed, keeping legacy plaintext: %{private}s', String(err));
      return plain;
    }
  }

  async decrypt(stored: string): Promise<string | null> {
    if (!isHukStored(stored)) { return stored; }
    try {
      await this.ensureKey();
      const data = this.parseEnvelope(stored);
      if (!data) { return null; }
      const opts: huks.HuksOptions = {
        properties: this.decryptProps(this.b64Decode(data.iv), this.b64Decode(data.tag)),
        inData: this.b64Decode(data.ciphertext),
      };
      const session = await huks.initSession(KEY_ALIAS, opts);
      const result = await huks.finishSession(session.handle, opts);
      return this.bytesToStr(result.outData ?? new Uint8Array(0));
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'decrypt failed (broken envelope): %{private}s', String(err));
      return null;
    }
  }

  private parseEnvelope(stored: string): EncryptedData | null {
    const payload = stored.substring(HUKS_PREFIX.length); // nonce:cipher:tag
    const parts = payload.split(':');
    if (parts.length !== 3) { return null; }
    return { iv: parts[0], ciphertext: parts[1], tag: parts[2] };
  }

  // ── On-device self-test ──────────────────────────────────────────

  /**
   * Run a real HUKS AES-256-GCM round-trip and report whether it succeeded.
   * Called once at app startup and logged, so `aa start` + hilog proves the
   * GCM tag/IV contract works on THIS device (the framework test runner is
   * SIGABRT-blocked). Returns true only on a successful decrypt == input.
   */
  async selfTest(): Promise<boolean> {
    const probe = 'transmissionbtm-huks-roundtrip-probe';
    try {
      const wrapped = await this.encrypt(probe);
      if (!isHukStored(wrapped)) {
        hilog.error(DOMAIN, TAG, 'selfTest FAIL: encrypt did not produce huk1 envelope');
        return false;
      }
      const back = await this.decrypt(wrapped);
      const ok = back === probe;
      hilog.info(DOMAIN, TAG, 'selfTest %{public}s', ok ? 'OK' : 'FAIL-ROUNDTRIP');
      return ok;
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'selfTest FAIL: %{private}s', String(err));
      return false;
    }
  }
}
