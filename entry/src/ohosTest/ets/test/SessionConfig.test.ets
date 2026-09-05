// transmissionbtm — SessionConfig and EncryptionMode tests
//
// Cross-referenced against upstream prefs defaults.
// Notable divergence: upstream defaults to EncrMode.Allow;
// our fork defaults to EncryptionMode.PREFER as a hardening measure.

import { describe, it, expect } from '@ohos/hypium';
import {
  SessionConfig,
  EncryptionMode,
  defaultSessionConfig,
} from '../../../main/ets/models/SessionConfig';

export default function sessionConfigTest(): void {
  describe('defaultSessionConfig', () => {
    it('returns_valid_download_defaults', 0, (): void => {
      const config: SessionConfig = defaultSessionConfig();
      expect(config.downloadDir).assertEqual('/storage/downloads');
      expect(config.incompleteDir).assertEqual('/storage/downloads/.incomplete');
      expect(config.startAddedTorrents).assertTrue();
      expect(config.renamePartialFiles).assertTrue();
      expect(config.trashOriginalTorrentFile).assertFalse();
    });

    it('returns_valid_network_defaults', 0, (): void => {
      const config: SessionConfig = defaultSessionConfig();
      expect(config.peerPort).assertEqual(51413);
      expect(config.rpcPort).assertEqual(9091);
      expect(config.rpcWhitelist).assertEqual('127.0.0.1');
      expect(config.rpcAuthentication).assertTrue();
      expect(config.rpcUsername).assertEqual('');
      expect(config.rpcPassword).assertEqual('');
      expect(config.peerLimitGlobal).assertEqual(200);
      expect(config.peerLimitPerTorrent).assertEqual(50);
    });

    it('returns_valid_speed_defaults', 0, (): void => {
      const config: SessionConfig = defaultSessionConfig();
      expect(config.speedLimitDown).assertEqual(0);
      expect(config.speedLimitUp).assertEqual(0);
      expect(config.speedLimitDownEnabled).assertFalse();
      expect(config.speedLimitUpEnabled).assertFalse();
      expect(config.altSpeedDown).assertEqual(50);
      expect(config.altSpeedUp).assertEqual(50);
      expect(config.altSpeedEnabled).assertFalse();
      expect(config.altSpeedTimeBegin).assertEqual(480);
      expect(config.altSpeedTimeEnd).assertEqual(1080);
      expect(config.altSpeedDay).assertEqual(127);
    });

    it('returns_valid_protocol_defaults', 0, (): void => {
      const config: SessionConfig = defaultSessionConfig();
      expect(config.dhtEnabled).assertTrue();
      expect(config.pexEnabled).assertTrue();
      expect(config.utpEnabled).assertTrue();
      // Source: lpdEnabled defaults to false (local peer discovery off by default)
      expect(config.lpdEnabled).assertFalse();
    });

    it('returns_valid_proxy_defaults', 0, (): void => {
      const config: SessionConfig = defaultSessionConfig();
      expect(config.proxyEnabled).assertFalse();
      expect(config.proxyUrl).assertEqual('');
      expect(config.proxyPort).assertEqual(0);
      expect(config.proxyAuthRequired).assertFalse();
      expect(config.proxyUsername).assertEqual('');
      expect(config.proxyPassword).assertEqual('');
    });

    it('returns_valid_seeding_defaults', 0, (): void => {
      const config: SessionConfig = defaultSessionConfig();
      expect(config.seedRatioLimit).assertEqual(2.0);
      expect(config.seedRatioLimited).assertFalse();
      expect(config.idleSeedingLimit).assertEqual(30);
      expect(config.idleSeedingLimitEnabled).assertFalse();
    });

    it('returns_valid_blocklist_defaults', 0, (): void => {
      const config: SessionConfig = defaultSessionConfig();
      expect(config.blocklistEnabled).assertFalse();
      expect(config.blocklistUrl).assertEqual('');
    });

    it('returns_valid_session_critical_defaults', 0, (): void => {
      const config: SessionConfig = defaultSessionConfig();
      // RPC listener off by default — no bundled web UI, so 9091 is an opt-in
      // via the Settings toggle. The whitelist stays on so a future web-control
      // opt-in binds to 127.0.0.1.
      expect(config.enableRpc).assertFalse();
      expect(config.enableRpcWhitelist).assertTrue();
      expect(config.settingsDir).assertEqual('/storage/transmission');
    });

    // Upstream Prefs.java: ENCR_MODE defaults to EncrMode.Allow.
    // Our fork deliberately defaults to PREFER as a hardening measure.
    it('encryptionMode_default_diverges_from_upstream', 0, (): void => {
      const config: SessionConfig = defaultSessionConfig();
      // NOTE: upstream defaults to ALLOW.
      // Our fork deliberately defaults to PREFER as a hardening measure.
      expect(config.encryptionMode).assertEqual(EncryptionMode.PREFER);
    });

    it('creates_new_object_each_call', 0, (): void => {
      const a: SessionConfig = defaultSessionConfig();
      const b: SessionConfig = defaultSessionConfig();
      // Mutate one copy — the other must remain unchanged (immutability).
      a.downloadDir = '/tmp/mutated';
      expect(b.downloadDir).assertEqual('/storage/downloads');
    });
  });

  describe('EncryptionMode', () => {
    it('has_three_string_values', 0, (): void => {
      expect(EncryptionMode.ALLOW).assertEqual('allow');
      expect(EncryptionMode.PREFER).assertEqual('prefer');
      expect(EncryptionMode.REQUIRE).assertEqual('require');
    });
  });

  describe('SessionConfig', () => {
    it('constructs_full_config_with_all_fields', 0, (): void => {
      const config: SessionConfig = {
        downloadDir: '/test/dl',
        incompleteDir: '/test/inc',
        peerPort: 6881,
        rpcPort: 9092,
        rpcWhitelist: '127.0.0.1',
        rpcAuthentication: true,
        rpcUsername: 'admin',
        rpcPassword: '',
        speedLimitDown: 100,
        speedLimitUp: 50,
        speedLimitDownEnabled: true,
        speedLimitUpEnabled: false,
        altSpeedDown: 50,
        altSpeedUp: 50,
        altSpeedEnabled: false,
        altSpeedTimeBegin: 480,
        altSpeedTimeEnd: 1080,
        altSpeedDay: 127,
        peerLimitGlobal: 200,
        peerLimitPerTorrent: 50,
        encryptionMode: EncryptionMode.REQUIRE,
        utpEnabled: true,
        pexEnabled: true,
        dhtEnabled: true,
        lpdEnabled: false,
        startAddedTorrents: true,
        renamePartialFiles: true,
        trashOriginalTorrentFile: false,
        proxyEnabled: false,
        proxyUrl: '',
        proxyPort: 8080,
        proxyAuthRequired: false,
        proxyUsername: '',
        proxyPassword: '',
        blocklistEnabled: false,
        blocklistUrl: '',
        seedRatioLimit: 1.5,
        seedRatioLimited: true,
        idleSeedingLimit: 60,
        idleSeedingLimitEnabled: true,
        enableRpc: true,
        enableRpcWhitelist: false,
        settingsDir: '/test/transmission',
      };
      expect(config.downloadDir).assertEqual('/test/dl');
      expect(config.encryptionMode).assertEqual(EncryptionMode.REQUIRE);
      expect(config.seedRatioLimit).assertEqual(1.5);
      expect(config.seedRatioLimited).assertTrue();
      expect(config.idleSeedingLimit).assertEqual(60);
      expect(config.enableRpc).assertTrue();
      expect(config.enableRpcWhitelist).assertFalse();
      expect(config.settingsDir).assertEqual('/test/transmission');
    });

    it('config_fields_are_mutable', 0, (): void => {
      const config: SessionConfig = defaultSessionConfig();
      config.downloadDir = '/new/path';
      expect(config.downloadDir).assertEqual('/new/path');
    });
  });
}
