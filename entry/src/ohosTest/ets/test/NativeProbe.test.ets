// transmissionbtm — Native probe test (M7 E2E prep)
//
// DECISIVE probe: unlike the defensive unit tests that skip when the
// native .so is unavailable, this test asserts on REAL native return
// values. It answers one question: can the ohosTest process load
// libtransmissionbtm_napi.so and call the native bridge in-process?
//
// If the .so is bundled into the test HAP (externalNativeOptions on the
// ohosTest target) this passes and in-process E2E functional tests are
// viable. If it fails, native calls must be exercised another way.

import { describe, it, expect } from '@ohos/hypium';
import { NativeBridge, EngineVersions } from '../../../main/ets/bridge/NativeBridge';

export default function nativeProbeTest() {
  describe('NativeProbe', () => {
    it('native_so_loads_and_getVersion_returns_real_value', 0, () => {
      const version: string = NativeBridge.getInstance().getVersion();
      // Real native value — the C++ side returns the release version string
      // (napi_init.cpp GetVersion), bumped with every release commit.
      // An unavailable .so throws here and fails this test.
      expect(version === '1.0.4').assertTrue();
    });

    it('native_getBuildDate_returns_iso_date', 0, () => {
      const date: string = NativeBridge.getInstance().getBuildDate();
      // Computed from __DATE__ in napi_init.cpp — the test bundle compiles on
      // a different day than the shipped .so, so only the shape is asserted.
      expect(/^\d{4}-\d{2}-\d{2}$/.test(date)).assertTrue();
    });

    it('native_getEngineVersions_reports_all_four_libraries', 0, () => {
      const v: EngineVersions = NativeBridge.getInstance().getEngineVersions();
      // Values come from the headers the .so was compiled against, so no
      // literal is pinned here (that copy is what went stale before).
      expect(/^\d+\.\d+\.\d+$/.test(v.transmission)).assertTrue();
      expect(v.openssl.length > 0).assertTrue();
      expect(v.curl.length > 0).assertTrue();
      expect(v.libevent.length > 0).assertTrue();
    });
  });
}
