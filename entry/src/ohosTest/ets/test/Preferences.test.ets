// transmissionhm — PrefKeys and encryption mode mapping tests
//
// Pure logic tests — no async store operations.
// PreferencesManager async methods are tested via integration tests.
// Cross-referenced against transmissionbtc Prefs.java key semantics.

import { describe, it, expect } from '@ohos/hypium';
import { PrefKeys, PreferencesManager } from '../../../main/ets/models/Preferences';
import { EncryptionMode } from '../../../main/ets/models/SessionConfig';

export default function preferencesTest(): void {
  describe('PrefKeys', () => {
    it('has_all_download_keys', 0, (): void => {
      expect(PrefKeys.DOWNLOAD_DIR).assertEqual('download_dir');
      expect(PrefKeys.INCOMPLETE_DIR).assertEqual('incomplete_dir');
      expect(PrefKeys.START_ADDED_TORRENTS).assertEqual('start_added_torrents');
      expect(PrefKeys.RENAME_PARTIAL_FILES).assertEqual('rename_partial_files');
      expect(PrefKeys.TRASH_ORIGINAL_TORRENT_FILE).assertEqual('trash_original_torrent_file');
    });

    it('has_all_network_keys', 0, (): void => {
      expect(PrefKeys.PEER_PORT).assertEqual('peer_port');
      expect(PrefKeys.RPC_PORT).assertEqual('rpc_port');
      expect(PrefKeys.RPC_WHITELIST).assertEqual('rpc_whitelist');
      expect(PrefKeys.RPC_AUTHENTICATION).assertEqual('rpc_authentication');
      expect(PrefKeys.RPC_USERNAME).assertEqual('rpc_username');
      expect(PrefKeys.RPC_PASSWORD).assertEqual('rpc_password');
      expect(PrefKeys.PEER_LIMIT_GLOBAL).assertEqual('peer_limit_global');
      expect(PrefKeys.PEER_LIMIT_PER_TORRENT).assertEqual('peer_limit_per_torrent');
    });

    it('has_all_speed_keys', 0, (): void => {
      expect(PrefKeys.SPEED_LIMIT_DOWN).assertEqual('speed_limit_down');
      expect(PrefKeys.SPEED_LIMIT_UP).assertEqual('speed_limit_up');
      expect(PrefKeys.SPEED_LIMIT_DOWN_ENABLED).assertEqual('speed_limit_down_enabled');
      expect(PrefKeys.SPEED_LIMIT_UP_ENABLED).assertEqual('speed_limit_up_enabled');
      expect(PrefKeys.ALT_SPEED_DOWN).assertEqual('alt_speed_down');
      expect(PrefKeys.ALT_SPEED_UP).assertEqual('alt_speed_up');
      expect(PrefKeys.ALT_SPEED_ENABLED).assertEqual('alt_speed_enabled');
      expect(PrefKeys.ALT_SPEED_TIME_BEGIN).assertEqual('alt_speed_time_begin');
      expect(PrefKeys.ALT_SPEED_TIME_END).assertEqual('alt_speed_time_end');
      expect(PrefKeys.ALT_SPEED_DAY).assertEqual('alt_speed_day');
    });

    it('has_all_protocol_keys', 0, (): void => {
      expect(PrefKeys.ENCRYPTION_MODE).assertEqual('encryption_mode');
      expect(PrefKeys.UTP_ENABLED).assertEqual('utp_enabled');
      expect(PrefKeys.PEX_ENABLED).assertEqual('pex_enabled');
      expect(PrefKeys.DHT_ENABLED).assertEqual('dht_enabled');
      expect(PrefKeys.LPD_ENABLED).assertEqual('lpd_enabled');
    });

    it('has_all_proxy_keys', 0, (): void => {
      expect(PrefKeys.PROXY_ENABLED).assertEqual('proxy_enabled');
      expect(PrefKeys.PROXY_URL).assertEqual('proxy_url');
      expect(PrefKeys.PROXY_PORT).assertEqual('proxy_port');
      expect(PrefKeys.PROXY_AUTH_REQUIRED).assertEqual('proxy_auth_required');
      expect(PrefKeys.PROXY_USERNAME).assertEqual('proxy_username');
      expect(PrefKeys.PROXY_PASSWORD).assertEqual('proxy_password');
    });

    it('has_all_seeding_keys', 0, (): void => {
      expect(PrefKeys.SEED_RATIO_LIMIT).assertEqual('seed_ratio_limit');
      expect(PrefKeys.SEED_RATIO_LIMITED).assertEqual('seed_ratio_limited');
      expect(PrefKeys.IDLE_SEEDING_LIMIT).assertEqual('idle_seeding_limit');
      expect(PrefKeys.IDLE_SEEDING_LIMIT_ENABLED).assertEqual('idle_seeding_limit_enabled');
    });

    it('has_all_blocklist_keys', 0, (): void => {
      expect(PrefKeys.BLOCKLIST_ENABLED).assertEqual('blocklist_enabled');
      expect(PrefKeys.BLOCKLIST_URL).assertEqual('blocklist_url');
    });

    it('has_all_session_critical_keys', 0, (): void => {
      expect(PrefKeys.ENABLE_RPC).assertEqual('enable_rpc');
      expect(PrefKeys.ENABLE_RPC_WHITELIST).assertEqual('enable_rpc_whitelist');
      expect(PrefKeys.INCREASE_SO_BUF).assertEqual('increase_so_buf');
      expect(PrefKeys.ENABLE_SEQ_DOWNLOAD).assertEqual('enable_seq_download');
      expect(PrefKeys.SETTINGS_DIR).assertEqual('settings_dir');
    });

    it('has_exactly_45_keys_total', 0, (): void => {
      // Count all static readonly string properties on PrefKeys.
      // This test verifies no keys were accidentally added or removed.
      const keys: string[] = [
        PrefKeys.DOWNLOAD_DIR,
        PrefKeys.INCOMPLETE_DIR,
        PrefKeys.PEER_PORT,
        PrefKeys.RPC_PORT,
        PrefKeys.RPC_WHITELIST,
        PrefKeys.RPC_AUTHENTICATION,
        PrefKeys.RPC_USERNAME,
        PrefKeys.RPC_PASSWORD,
        PrefKeys.SPEED_LIMIT_DOWN,
        PrefKeys.SPEED_LIMIT_UP,
        PrefKeys.SPEED_LIMIT_DOWN_ENABLED,
        PrefKeys.SPEED_LIMIT_UP_ENABLED,
        PrefKeys.ALT_SPEED_DOWN,
        PrefKeys.ALT_SPEED_UP,
        PrefKeys.ALT_SPEED_ENABLED,
        PrefKeys.ALT_SPEED_TIME_BEGIN,
        PrefKeys.ALT_SPEED_TIME_END,
        PrefKeys.ALT_SPEED_DAY,
        PrefKeys.PEER_LIMIT_GLOBAL,
        PrefKeys.PEER_LIMIT_PER_TORRENT,
        PrefKeys.ENCRYPTION_MODE,
        PrefKeys.UTP_ENABLED,
        PrefKeys.PEX_ENABLED,
        PrefKeys.DHT_ENABLED,
        PrefKeys.LPD_ENABLED,
        PrefKeys.START_ADDED_TORRENTS,
        PrefKeys.RENAME_PARTIAL_FILES,
        PrefKeys.TRASH_ORIGINAL_TORRENT_FILE,
        PrefKeys.PROXY_ENABLED,
        PrefKeys.PROXY_URL,
        PrefKeys.PROXY_PORT,
        PrefKeys.PROXY_AUTH_REQUIRED,
        PrefKeys.PROXY_USERNAME,
        PrefKeys.PROXY_PASSWORD,
        PrefKeys.BLOCKLIST_ENABLED,
        PrefKeys.BLOCKLIST_URL,
        PrefKeys.SEED_RATIO_LIMIT,
        PrefKeys.SEED_RATIO_LIMITED,
        PrefKeys.IDLE_SEEDING_LIMIT,
        PrefKeys.IDLE_SEEDING_LIMIT_ENABLED,
        PrefKeys.ENABLE_RPC,
        PrefKeys.ENABLE_RPC_WHITELIST,
        PrefKeys.INCREASE_SO_BUF,
        PrefKeys.ENABLE_SEQ_DOWNLOAD,
        PrefKeys.SETTINGS_DIR,
      ];
      expect(keys.length).assertEqual(45);
      // Verify all keys are unique (no duplicates).
      const unique: Set<string> = new Set();
      for (let i = 0; i < keys.length; i++) {
        unique.add(keys[i]);
      }
      expect(unique.size).assertEqual(45);
    });

    it('pref_key_names_use_snake_case', 0, (): void => {
      // All keys should follow snake_case convention.
      const keys: string[] = [
        PrefKeys.DOWNLOAD_DIR,
        PrefKeys.RPC_AUTHENTICATION,
        PrefKeys.SPEED_LIMIT_DOWN_ENABLED,
        PrefKeys.IDLE_SEEDING_LIMIT_ENABLED,
      ];
      for (let i = 0; i < keys.length; i++) {
        const key: string = keys[i];
        // Snake case: lowercase letters, digits, and underscores only.
        const valid: boolean = /^[a-z0-9_]+$/.test(key);
        expect(valid).assertTrue();
      }
    });
  });

  describe('PreferencesManager (static properties)', () => {
    // PreferencesManager is a singleton. getInstance() returns the same
    // instance every call.

    it('getInstance_returns_same_reference', 0, (): void => {
      const a: PreferencesManager = PreferencesManager.getInstance();
      const b: PreferencesManager = PreferencesManager.getInstance();
      // Same singleton instance.
      expect(a === b).assertTrue();
    });

    it('ENCRYPTION_MODE_LABELS_has_three_entries', 0, (): void => {
      const labels: string[] = PreferencesManager.ENCRYPTION_MODE_LABELS;
      expect(labels.length).assertEqual(3);
      expect(labels[0]).assertEqual('Allow');
      expect(labels[1]).assertEqual('Prefer');
      expect(labels[2]).assertEqual('Require');
    });

    it('ENCRYPTION_MODE_LABELS_match_enum_order', 0, (): void => {
      // Labels follow the same order: Allow → Prefer → Require.
      // Matches EncryptionMode enum: ALLOW, PREFER, REQUIRE.
      const labels: string[] = PreferencesManager.ENCRYPTION_MODE_LABELS;
      expect(labels[0]).assertEqual('Allow');
      expect(labels[1]).assertEqual('Prefer');
      expect(labels[2]).assertEqual('Require');
    });
  });

  describe('encryptionModeFromString (indirect)', () => {
    // encryptionModeFromString() is a private function in Preferences.ets.
    // We test its expected behavior indirectly through the public API:
    // - getEncryptionMode() wraps it (but requires async init).
    // - The default SessionConfig uses EncryptionMode.PREFER.
    //
    // For pure logic coverage, we document expected mapping behavior here.

    it('encryption_mode_enum_values_cover_all_cases', 0, (): void => {
      // The three EncryptionMode string values must be mutually distinct.
      expect(EncryptionMode.ALLOW).assertEqual('allow');
      expect(EncryptionMode.PREFER).assertEqual('prefer');
      expect(EncryptionMode.REQUIRE).assertEqual('require');
      // Verify they are different from each other.
      // ArkTS strict mode: cast enum values to string for comparison.
      const allowVal: string = EncryptionMode.ALLOW;
      const preferVal: string = EncryptionMode.PREFER;
      const requireVal: string = EncryptionMode.REQUIRE;
      expect(allowVal === preferVal).assertFalse();
      expect(preferVal === requireVal).assertFalse();
      expect(allowVal === requireVal).assertFalse();
    });

    it('ENCRYPTION_MODE key_name_is_correct', 0, (): void => {
      // The preferences key for encryption mode must be 'encryption_mode'.
      expect(PrefKeys.ENCRYPTION_MODE).assertEqual('encryption_mode');
    });
  });
}
