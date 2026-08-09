// transmissionhm — Native probe test (M7 E2E prep)
//
// DECISIVE probe: unlike the defensive unit tests that skip when the
// native .so is unavailable, this test asserts on REAL native return
// values. It answers one question: can the ohosTest process load
// libtransmissionhm_napi.so and call the native bridge in-process?
//
// If the .so is bundled into the test HAP (externalNativeOptions on the
// ohosTest target) this passes and in-process E2E functional tests are
// viable. If it fails, native calls must be exercised another way.

import { describe, it, expect } from '@ohos/hypium';
import { NativeBridge } from '../../../main/ets/bridge/NativeBridge';

export default function nativeProbeTest() {
  describe('NativeProbe', () => {
    it('native_so_loads_and_getVersion_returns_real_value', 0, () => {
      const version: string = NativeBridge.getInstance().getVersion();
      // Real native value — the C++ side returns '0.1.0-m6'.
      // An unavailable .so throws here and fails this test.
      expect(version === '0.1.0-m6').assertTrue();
    });
  });
}
