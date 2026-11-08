// transmissionbtm — error rendering for logs and user-facing messages.
//
// Rationale: `String(err)` on an ArkTS BusinessError yields "[object Object]",
// and an Error thrown from a @Concurrent worker arrives with its message
// already stripped. Both turn a diagnosable failure into a mystery. Every
// catch block that reports an error goes through errText() so the log always
// carries a code and a message.

import { BusinessError } from '@kit.BasicServicesKit';

/**
 * Best-effort human-readable text for a caught value.
 *
 * ArkTS throws are `object`, not a typed Error union, so this narrows rather
 * than casts blindly: BusinessError supplies `code`/`message`, a plain Error
 * supplies `message`, anything else falls back to String().
 */
export function errText(err: object): string {
  const e = err as BusinessError;
  const msg: string = typeof e.message === 'string' ? e.message : '';
  const hasCode: boolean = typeof e.code === 'number' || typeof e.code === 'string';

  if (msg.length > 0) {
    return hasCode ? `${e.code} ${msg}` : msg;
  }
  if (hasCode) {
    return `${e.code}`;
  }
  const s: string = String(err);
  // String() on a bare object is exactly the symptom this helper exists to
  // prevent — make it explicit instead of letting it pass as a real message.
  return s === '[object Object]' ? 'unknown error (no message)' : s;
}
