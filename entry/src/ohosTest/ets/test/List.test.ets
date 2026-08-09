// transmissionhm — Test suite entry point
//
// Imports and runs all test suites. Each suite is a default-export
// function containing one or more describe() blocks.
//
// Add new test files: import + call in testsuite().

import abilityTest from './Ability.test';
import sessionConfigTest from './SessionConfig.test';
import preferencesTest from './Preferences.test';
import sessionStateTest from './SessionState.test';
import fileTreeModelTest from './FileTreeModel.test';
import formatUtilsTest from './FormatUtils.test';
import torrentInfoTest from './TorrentInfo.test';
import torrentFileTest from './TorrentFile.test';
import nativeBridgeTest from './NativeBridge.test';
import transmissionSessionTest from './TransmissionSession.test';
import toggleSettingTest from './ToggleSetting.test';
import nativeProbeTest from './NativeProbe.test';
import functionalE2ETest from './FunctionalE2E.test';

export default function testsuite(): void {
  // Framework smoke test (built-in template)
  abilityTest();

  // Models & config
  sessionConfigTest();
  preferencesTest();
  sessionStateTest();
  fileTreeModelTest();

  // Utils
  formatUtilsTest();

  // Domain models
  torrentInfoTest();
  torrentFileTest();

  // Bridge & session
  nativeBridgeTest();
  transmissionSessionTest();
  nativeProbeTest();

  // In-process functional E2E (real native session on device)
  functionalE2ETest();

  // Component contracts
  toggleSettingTest();
}
