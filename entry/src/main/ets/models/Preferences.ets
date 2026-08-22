// transmissionbtm — Preferences & Settings Manager (M2)
//
// Centralized preference keys and typed getters/setters backed by
// @ohos.data.preferences. All other modules read/write settings through
// PreferencesManager.getInstance() — never call preferences API directly.
//
// SessionConfig integration: getSessionConfig() returns a fully populated
// SessionConfig from stored preferences, falling back to defaults.

import { preferences } from '@kit.ArkData';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { SessionConfig, EncryptionMode, defaultSessionConfig } from './SessionConfig';
import { ProxyCipher, LegacyProxyCipher } from '../security/ProxyCipher';

const TAG = 'PreferencesManager';
const STORE_NAME = 'transmissionbtm_preferences';

// ═══════════════════════════════════════════════════════════════════
// Preference Keys (40+ — one per SessionConfig field)
// ═══════════════════════════════════════════════════════════════════

export class PrefKeys {
  // Session
  static readonly DOWNLOAD_DIR: string = 'download_dir';
  static readonly PUBLISH_DIR: string = 'publish_dir';
  static readonly INCOMPLETE_DIR: string = 'incomplete_dir';
  static readonly PEER_PORT: string = 'peer_port';
  static readonly RPC_PORT: string = 'rpc_port';
  static readonly RPC_WHITELIST: string = 'rpc_whitelist';
  static readonly RPC_AUTHENTICATION: string = 'rpc_authentication';
  static readonly RPC_USERNAME: string = 'rpc_username';
  static readonly RPC_PASSWORD: string = 'rpc_password';

  // Speed Limits
  static readonly SPEED_LIMIT_DOWN: string = 'speed_limit_down';
  static readonly SPEED_LIMIT_UP: string = 'speed_limit_up';
  static readonly SPEED_LIMIT_DOWN_ENABLED: string = 'speed_limit_down_enabled';
  static readonly SPEED_LIMIT_UP_ENABLED: string = 'speed_limit_up_enabled';

  // Alternative Speed Limits (Turtle Mode)
  static readonly ALT_SPEED_DOWN: string = 'alt_speed_down';
  static readonly ALT_SPEED_UP: string = 'alt_speed_up';
  static readonly ALT_SPEED_ENABLED: string = 'alt_speed_enabled';
  static readonly ALT_SPEED_TIME_BEGIN: string = 'alt_speed_time_begin';
  static readonly ALT_SPEED_TIME_END: string = 'alt_speed_time_end';
  static readonly ALT_SPEED_DAY: string = 'alt_speed_day';

  // Peer Limits
  static readonly PEER_LIMIT_GLOBAL: string = 'peer_limit_global';
  static readonly PEER_LIMIT_PER_TORRENT: string = 'peer_limit_per_torrent';

  // Encryption & Protocol
  static readonly ENCRYPTION_MODE: string = 'encryption_mode';
  static readonly UTP_ENABLED: string = 'utp_enabled';
  static readonly PEX_ENABLED: string = 'pex_enabled';
  static readonly DHT_ENABLED: string = 'dht_enabled';
  static readonly LPD_ENABLED: string = 'lpd_enabled';

  // Torrent Behavior
  static readonly START_ADDED_TORRENTS: string = 'start_added_torrents';
  static readonly RENAME_PARTIAL_FILES: string = 'rename_partial_files';
  static readonly TRASH_ORIGINAL_TORRENT_FILE: string = 'trash_original_torrent_file';

  // Proxy
  static readonly PROXY_ENABLED: string = 'proxy_enabled';
  static readonly PROXY_URL: string = 'proxy_url';
  static readonly PROXY_PORT: string = 'proxy_port';
  static readonly PROXY_AUTH_REQUIRED: string = 'proxy_auth_required';
  static readonly PROXY_USERNAME: string = 'proxy_username';
  static readonly PROXY_PASSWORD: string = 'proxy_password';

  // Blocklist
  static readonly BLOCKLIST_ENABLED: string = 'blocklist_enabled';
  static readonly BLOCKLIST_URL: string = 'blocklist_url';

  // Seeding Limits
  static readonly SEED_RATIO_LIMIT: string = 'seed_ratio_limit';
  static readonly SEED_RATIO_LIMITED: string = 'seed_ratio_limited';
  static readonly IDLE_SEEDING_LIMIT: string = 'idle_seeding_limit';
  static readonly IDLE_SEEDING_LIMIT_ENABLED: string = 'idle_seeding_limit_enabled';

  // Session-critical (transmissionbtc, not exposed in UI)
  static readonly ENABLE_RPC: string = 'enable_rpc';
  static readonly ENABLE_RPC_WHITELIST: string = 'enable_rpc_whitelist';
  static readonly INCREASE_SO_BUF: string = 'increase_so_buf';
  static readonly ENABLE_SEQ_DOWNLOAD: string = 'enable_seq_download';
  static readonly SETTINGS_DIR: string = 'settings_dir';
}

// ═══════════════════════════════════════════════════════════════════
// Encryption mode mapping (string <-> enum)
// ═══════════════════════════════════════════════════════════════════

const ENCRYPTION_MODE_VALUES: string[] = [
  EncryptionMode.ALLOW,
  EncryptionMode.PREFER,
  EncryptionMode.REQUIRE,
];

function encryptionModeFromString(value: string): EncryptionMode {
  if (value === EncryptionMode.ALLOW) { return EncryptionMode.ALLOW; }
  if (value === EncryptionMode.REQUIRE) { return EncryptionMode.REQUIRE; }
  return EncryptionMode.PREFER;
}

// ═══════════════════════════════════════════════════════════════════
// PreferencesManager
// ═══════════════════════════════════════════════════════════════════

export class PreferencesManager {
  private static instance: PreferencesManager | null = null;
  private store: preferences.Preferences | null = null;
  private context: Context | null = null;
  private passwordCipher: ProxyCipher = new LegacyProxyCipher();

  /**
   * Swap in the on-device HUKS cipher. Called once at app startup (EntryAbility)
   * so host vitest keeps the legacy (plaintext) cipher by default and never
   * resolves @kit.UniversalKeystoreKit here.
   */
  setPasswordCipher(cipher: ProxyCipher): void {
    this.passwordCipher = cipher;
  }

  static getInstance(): PreferencesManager {
    if (!PreferencesManager.instance) {
      PreferencesManager.instance = new PreferencesManager();
    }
    return PreferencesManager.instance;
  }

  /**
   * Initialize the preferences store. Must be called once during app startup
   * (from EntryAbility.onCreate) with the application context.
   */
  async init(context: Context): Promise<void> {
    if (this.store) { return; }
    this.context = context;
    try {
      this.store = await preferences.getPreferences(context, STORE_NAME);
      await this.applyDefaults();
      hilog.info(0x0001, TAG, 'PreferencesManager initialized');
    } catch (err) {
      hilog.error(0x0001, TAG,
        'PreferencesManager init failed: %{private}s', String(err));
    }
  }

  private guard(): preferences.Preferences {
    if (!this.store) {
      throw new Error('PreferencesManager not initialized. Call init(context) first.');
    }
    return this.store;
  }

  // ── Defaults ─────────────────────────────────────────────────────

  /**
   * Apply defaults for any keys not yet stored. Uses the same defaults
   * as defaultSessionConfig() so the two stay synchronized.
   */
  private async applyDefaults(): Promise<void> {
    const store = this.guard();
    const defaults = defaultSessionConfig();

    const boolDefaults: [string, boolean][] = [
      [PrefKeys.RPC_AUTHENTICATION, defaults.rpcAuthentication],
      [PrefKeys.SPEED_LIMIT_DOWN_ENABLED, defaults.speedLimitDownEnabled],
      [PrefKeys.SPEED_LIMIT_UP_ENABLED, defaults.speedLimitUpEnabled],
      [PrefKeys.ALT_SPEED_ENABLED, defaults.altSpeedEnabled],
      [PrefKeys.UTP_ENABLED, defaults.utpEnabled],
      [PrefKeys.PEX_ENABLED, defaults.pexEnabled],
      [PrefKeys.DHT_ENABLED, defaults.dhtEnabled],
      [PrefKeys.LPD_ENABLED, defaults.lpdEnabled],
      [PrefKeys.START_ADDED_TORRENTS, defaults.startAddedTorrents],
      [PrefKeys.RENAME_PARTIAL_FILES, defaults.renamePartialFiles],
      [PrefKeys.TRASH_ORIGINAL_TORRENT_FILE, defaults.trashOriginalTorrentFile],
      [PrefKeys.PROXY_ENABLED, defaults.proxyEnabled],
      [PrefKeys.PROXY_AUTH_REQUIRED, defaults.proxyAuthRequired],
      [PrefKeys.BLOCKLIST_ENABLED, defaults.blocklistEnabled],
      [PrefKeys.SEED_RATIO_LIMITED, defaults.seedRatioLimited],
      [PrefKeys.IDLE_SEEDING_LIMIT_ENABLED, defaults.idleSeedingLimitEnabled],
      [PrefKeys.ENABLE_RPC, defaults.enableRpc],
      [PrefKeys.ENABLE_RPC_WHITELIST, defaults.enableRpcWhitelist],
      [PrefKeys.INCREASE_SO_BUF, defaults.increaseSoBuf],
      [PrefKeys.ENABLE_SEQ_DOWNLOAD, defaults.enableSeqDownload],
    ];

    const intDefaults: [string, number][] = [
      [PrefKeys.PEER_PORT, defaults.peerPort],
      [PrefKeys.RPC_PORT, defaults.rpcPort],
      [PrefKeys.SPEED_LIMIT_DOWN, defaults.speedLimitDown],
      [PrefKeys.SPEED_LIMIT_UP, defaults.speedLimitUp],
      [PrefKeys.ALT_SPEED_DOWN, defaults.altSpeedDown],
      [PrefKeys.ALT_SPEED_UP, defaults.altSpeedUp],
      [PrefKeys.ALT_SPEED_TIME_BEGIN, defaults.altSpeedTimeBegin],
      [PrefKeys.ALT_SPEED_TIME_END, defaults.altSpeedTimeEnd],
      [PrefKeys.ALT_SPEED_DAY, defaults.altSpeedDay],
      [PrefKeys.PEER_LIMIT_GLOBAL, defaults.peerLimitGlobal],
      [PrefKeys.PEER_LIMIT_PER_TORRENT, defaults.peerLimitPerTorrent],
      [PrefKeys.PROXY_PORT, defaults.proxyPort],
      [PrefKeys.IDLE_SEEDING_LIMIT, defaults.idleSeedingLimit],
    ];

    const strDefaults: [string, string][] = [
      [PrefKeys.DOWNLOAD_DIR, defaults.downloadDir],
      [PrefKeys.INCOMPLETE_DIR, defaults.incompleteDir],
      [PrefKeys.RPC_WHITELIST, defaults.rpcWhitelist],
      [PrefKeys.RPC_USERNAME, defaults.rpcUsername],
      [PrefKeys.RPC_PASSWORD, defaults.rpcPassword],
      [PrefKeys.ENCRYPTION_MODE, defaults.encryptionMode],
      [PrefKeys.PROXY_URL, defaults.proxyUrl],
      [PrefKeys.PROXY_USERNAME, defaults.proxyUsername],
      [PrefKeys.PROXY_PASSWORD, defaults.proxyPassword],
      [PrefKeys.BLOCKLIST_URL, defaults.blocklistUrl],
      [PrefKeys.SETTINGS_DIR, defaults.settingsDir],
    ];

    // ArkTS: no destructuring in for-of. Use indexed access.
    for (let i = 0; i < boolDefaults.length; i++) {
      const key = boolDefaults[i][0];
      const def = boolDefaults[i][1];
      if (!(await store.has(key))) { await store.put(key, def); }
    }
    for (let i = 0; i < intDefaults.length; i++) {
      const key = intDefaults[i][0];
      const def = intDefaults[i][1];
      if (!(await store.has(key))) { await store.put(key, def); }
    }
    for (let i = 0; i < strDefaults.length; i++) {
      const key = strDefaults[i][0];
      const def = strDefaults[i][1];
      if (!(await store.has(key))) { await store.put(key, def); }
    }

    // seedRatioLimit is a float but preferences only store number.
    // Store as a number; the getter casts to number.
    if (!(await store.has(PrefKeys.SEED_RATIO_LIMIT))) {
      await store.put(PrefKeys.SEED_RATIO_LIMIT, defaults.seedRatioLimit);
    }

    await store.flush();
  }

  // ── Typed Getters ────────────────────────────────────────────────

  async getBoolean(key: string, def: boolean = false): Promise<boolean> {
    try {
      return await this.guard().get(key, def) as boolean;
    } catch (err) {
      hilog.error(0x0001, TAG,
        'getBoolean(%{private}s) failed: %{private}s', key, String(err));
      return def;
    }
  }

  async getInt(key: string, def: number = 0): Promise<number> {
    try {
      return await this.guard().get(key, def) as number;
    } catch (err) {
      hilog.error(0x0001, TAG,
        'getInt(%{private}s) failed: %{private}s', key, String(err));
      return def;
    }
  }

  async getFloat(key: string, def: number = 0): Promise<number> {
    try {
      return await this.guard().get(key, def) as number;
    } catch (err) {
      hilog.error(0x0001, TAG,
        'getFloat(%{private}s) failed: %{private}s', key, String(err));
      return def;
    }
  }

  async getString(key: string, def: string = ''): Promise<string> {
    try {
      const raw = await this.guard().get(key, def) as string;
      if (key === PrefKeys.PROXY_PASSWORD) {
        // Decrypt the stored envelope. Legacy plaintext (no huk1: prefix) is
        // returned as-is. A broken envelope decrypts to null → fall back to def
        // (an unset password) rather than surfacing ciphertext to the UI.
        return await this.passwordCipher.decrypt(raw) ?? def;
      }
      return raw;
    } catch (err) {
      hilog.error(0x0001, TAG,
        'getString(%{private}s) failed: %{private}s', key, String(err));
      return def;
    }
  }

  // ── Typed Setters ────────────────────────────────────────────────

  async setBoolean(key: string, value: boolean): Promise<void> {
    try {
      await this.guard().put(key, value);
      await this.guard().flush();
    } catch (err) {
      hilog.error(0x0001, TAG,
        'setBoolean(%{private}s) failed: %{private}s', key, String(err));
    }
  }

  async setInt(key: string, value: number): Promise<void> {
    try {
      await this.guard().put(key, value);
      await this.guard().flush();
    } catch (err) {
      hilog.error(0x0001, TAG,
        'setInt(%{private}s) failed: %{private}s', key, String(err));
    }
  }

  async setString(key: string, value: string): Promise<void> {
    try {
      const toStore = key === PrefKeys.PROXY_PASSWORD
        ? await this.passwordCipher.encrypt(value)
        : value;
      await this.guard().put(key, toStore);
      await this.guard().flush();
    } catch (err) {
      hilog.error(0x0001, TAG,
        'setString(%{private}s) failed: %{private}s', key, String(err));
    }
  }

  // ── SessionConfig Builder ────────────────────────────────────────

  /**
   * Build a fully populated SessionConfig from stored preferences.
   * Returns a new object each call — no mutation of shared state.
   */
  /**
   * Build a SessionConfig from persisted preferences using typed getters.
   * Avoids store.getAll() because ArkTS bans Object indexed access.
   */
  async getSessionConfig(): Promise<SessionConfig> {
    try {
      const defs = defaultSessionConfig();
      return {
        downloadDir: await this.getString(PrefKeys.DOWNLOAD_DIR, defs.downloadDir),
        incompleteDir: await this.getString(PrefKeys.INCOMPLETE_DIR, defs.incompleteDir),
        peerPort: await this.getInt(PrefKeys.PEER_PORT, defs.peerPort),
        rpcPort: await this.getInt(PrefKeys.RPC_PORT, defs.rpcPort),
        rpcWhitelist: await this.getString(PrefKeys.RPC_WHITELIST, defs.rpcWhitelist),
        rpcAuthentication: await this.getBoolean(PrefKeys.RPC_AUTHENTICATION, defs.rpcAuthentication),
        rpcUsername: await this.getString(PrefKeys.RPC_USERNAME, defs.rpcUsername),
        rpcPassword: await this.getString(PrefKeys.RPC_PASSWORD, defs.rpcPassword),
        speedLimitDown: await this.getInt(PrefKeys.SPEED_LIMIT_DOWN, defs.speedLimitDown),
        speedLimitUp: await this.getInt(PrefKeys.SPEED_LIMIT_UP, defs.speedLimitUp),
        speedLimitDownEnabled: await this.getBoolean(PrefKeys.SPEED_LIMIT_DOWN_ENABLED, defs.speedLimitDownEnabled),
        speedLimitUpEnabled: await this.getBoolean(PrefKeys.SPEED_LIMIT_UP_ENABLED, defs.speedLimitUpEnabled),
        altSpeedDown: await this.getInt(PrefKeys.ALT_SPEED_DOWN, defs.altSpeedDown),
        altSpeedUp: await this.getInt(PrefKeys.ALT_SPEED_UP, defs.altSpeedUp),
        altSpeedEnabled: await this.getBoolean(PrefKeys.ALT_SPEED_ENABLED, defs.altSpeedEnabled),
        altSpeedTimeBegin: await this.getInt(PrefKeys.ALT_SPEED_TIME_BEGIN, defs.altSpeedTimeBegin),
        altSpeedTimeEnd: await this.getInt(PrefKeys.ALT_SPEED_TIME_END, defs.altSpeedTimeEnd),
        altSpeedDay: await this.getInt(PrefKeys.ALT_SPEED_DAY, defs.altSpeedDay),
        peerLimitGlobal: await this.getInt(PrefKeys.PEER_LIMIT_GLOBAL, defs.peerLimitGlobal),
        peerLimitPerTorrent: await this.getInt(PrefKeys.PEER_LIMIT_PER_TORRENT, defs.peerLimitPerTorrent),
        encryptionMode: encryptionModeFromString(
          await this.getString(PrefKeys.ENCRYPTION_MODE, defs.encryptionMode)
        ),
        utpEnabled: await this.getBoolean(PrefKeys.UTP_ENABLED, defs.utpEnabled),
        pexEnabled: await this.getBoolean(PrefKeys.PEX_ENABLED, defs.pexEnabled),
        dhtEnabled: await this.getBoolean(PrefKeys.DHT_ENABLED, defs.dhtEnabled),
        lpdEnabled: await this.getBoolean(PrefKeys.LPD_ENABLED, defs.lpdEnabled),
        startAddedTorrents: await this.getBoolean(PrefKeys.START_ADDED_TORRENTS, defs.startAddedTorrents),
        renamePartialFiles: await this.getBoolean(PrefKeys.RENAME_PARTIAL_FILES, defs.renamePartialFiles),
        trashOriginalTorrentFile: await this.getBoolean(PrefKeys.TRASH_ORIGINAL_TORRENT_FILE, defs.trashOriginalTorrentFile),
        proxyEnabled: await this.getBoolean(PrefKeys.PROXY_ENABLED, defs.proxyEnabled),
        proxyUrl: await this.getString(PrefKeys.PROXY_URL, defs.proxyUrl),
        proxyPort: await this.getInt(PrefKeys.PROXY_PORT, defs.proxyPort),
        proxyAuthRequired: await this.getBoolean(PrefKeys.PROXY_AUTH_REQUIRED, defs.proxyAuthRequired),
        proxyUsername: await this.getString(PrefKeys.PROXY_USERNAME, defs.proxyUsername),
        proxyPassword: await this.getString(PrefKeys.PROXY_PASSWORD, defs.proxyPassword),
        blocklistEnabled: await this.getBoolean(PrefKeys.BLOCKLIST_ENABLED, defs.blocklistEnabled),
        blocklistUrl: await this.getString(PrefKeys.BLOCKLIST_URL, defs.blocklistUrl),
        seedRatioLimit: await this.getFloat(PrefKeys.SEED_RATIO_LIMIT, defs.seedRatioLimit),
        seedRatioLimited: await this.getBoolean(PrefKeys.SEED_RATIO_LIMITED, defs.seedRatioLimited),
        idleSeedingLimit: await this.getInt(PrefKeys.IDLE_SEEDING_LIMIT, defs.idleSeedingLimit),
        idleSeedingLimitEnabled: await this.getBoolean(PrefKeys.IDLE_SEEDING_LIMIT_ENABLED, defs.idleSeedingLimitEnabled),
        enableRpc: await this.getBoolean(PrefKeys.ENABLE_RPC, defs.enableRpc),
        enableRpcWhitelist: await this.getBoolean(PrefKeys.ENABLE_RPC_WHITELIST, defs.enableRpcWhitelist),
        increaseSoBuf: await this.getBoolean(PrefKeys.INCREASE_SO_BUF, defs.increaseSoBuf),
        enableSeqDownload: await this.getBoolean(PrefKeys.ENABLE_SEQ_DOWNLOAD, defs.enableSeqDownload),
        settingsDir: await this.getString(PrefKeys.SETTINGS_DIR, defs.settingsDir),
      };
    } catch (err) {
      hilog.error(0x0001, TAG,
        'getSessionConfig failed, returning defaults: %{private}s', String(err));
      return defaultSessionConfig();
    }
  }

  async setSessionConfig(config: SessionConfig): Promise<void> {
    const store = this.guard();
    try {
      await store.put(PrefKeys.DOWNLOAD_DIR, config.downloadDir);
      await store.put(PrefKeys.INCOMPLETE_DIR, config.incompleteDir);
      await store.put(PrefKeys.PEER_PORT, config.peerPort);
      await store.put(PrefKeys.RPC_PORT, config.rpcPort);
      await store.put(PrefKeys.RPC_WHITELIST, config.rpcWhitelist);
      await store.put(PrefKeys.RPC_AUTHENTICATION, config.rpcAuthentication);
      await store.put(PrefKeys.RPC_USERNAME, config.rpcUsername);
      await store.put(PrefKeys.RPC_PASSWORD, config.rpcPassword);
      await store.put(PrefKeys.SPEED_LIMIT_DOWN, config.speedLimitDown);
      await store.put(PrefKeys.SPEED_LIMIT_UP, config.speedLimitUp);
      await store.put(PrefKeys.SPEED_LIMIT_DOWN_ENABLED, config.speedLimitDownEnabled);
      await store.put(PrefKeys.SPEED_LIMIT_UP_ENABLED, config.speedLimitUpEnabled);
      await store.put(PrefKeys.ALT_SPEED_DOWN, config.altSpeedDown);
      await store.put(PrefKeys.ALT_SPEED_UP, config.altSpeedUp);
      await store.put(PrefKeys.ALT_SPEED_ENABLED, config.altSpeedEnabled);
      await store.put(PrefKeys.ALT_SPEED_TIME_BEGIN, config.altSpeedTimeBegin);
      await store.put(PrefKeys.ALT_SPEED_TIME_END, config.altSpeedTimeEnd);
      await store.put(PrefKeys.ALT_SPEED_DAY, config.altSpeedDay);
      await store.put(PrefKeys.PEER_LIMIT_GLOBAL, config.peerLimitGlobal);
      await store.put(PrefKeys.PEER_LIMIT_PER_TORRENT, config.peerLimitPerTorrent);
      await store.put(PrefKeys.ENCRYPTION_MODE, config.encryptionMode);
      await store.put(PrefKeys.UTP_ENABLED, config.utpEnabled);
      await store.put(PrefKeys.PEX_ENABLED, config.pexEnabled);
      await store.put(PrefKeys.DHT_ENABLED, config.dhtEnabled);
      await store.put(PrefKeys.LPD_ENABLED, config.lpdEnabled);
      await store.put(PrefKeys.START_ADDED_TORRENTS, config.startAddedTorrents);
      await store.put(PrefKeys.RENAME_PARTIAL_FILES, config.renamePartialFiles);
      await store.put(PrefKeys.TRASH_ORIGINAL_TORRENT_FILE, config.trashOriginalTorrentFile);
      await store.put(PrefKeys.PROXY_ENABLED, config.proxyEnabled);
      await store.put(PrefKeys.PROXY_URL, config.proxyUrl);
      await store.put(PrefKeys.PROXY_PORT, config.proxyPort);
      await store.put(PrefKeys.PROXY_AUTH_REQUIRED, config.proxyAuthRequired);
      await store.put(PrefKeys.PROXY_USERNAME, config.proxyUsername);
      await this.setString(PrefKeys.PROXY_PASSWORD, config.proxyPassword);
      await store.put(PrefKeys.BLOCKLIST_ENABLED, config.blocklistEnabled);
      await store.put(PrefKeys.BLOCKLIST_URL, config.blocklistUrl);
      await store.put(PrefKeys.SEED_RATIO_LIMIT, config.seedRatioLimit);
      await store.put(PrefKeys.SEED_RATIO_LIMITED, config.seedRatioLimited);
      await store.put(PrefKeys.IDLE_SEEDING_LIMIT, config.idleSeedingLimit);
      await store.put(PrefKeys.IDLE_SEEDING_LIMIT_ENABLED, config.idleSeedingLimitEnabled);
      await store.put(PrefKeys.ENABLE_RPC, config.enableRpc);
      await store.put(PrefKeys.ENABLE_RPC_WHITELIST, config.enableRpcWhitelist);
      await store.put(PrefKeys.INCREASE_SO_BUF, config.increaseSoBuf);
      await store.put(PrefKeys.ENABLE_SEQ_DOWNLOAD, config.enableSeqDownload);
      await store.put(PrefKeys.SETTINGS_DIR, config.settingsDir);
      await store.flush();
    } catch (err) {
      hilog.error(0x0001, TAG,
        'setSessionConfig failed: %{private}s', String(err));
    }
  }

  /**
   * Reset all preferences to factory defaults.
   */
  async resetToDefaults(): Promise<void> {
    try {
      await this.guard().clear();
      await this.applyDefaults();
      hilog.info(0x0001, TAG, 'Preferences reset to defaults');
    } catch (err) {
      hilog.error(0x0001, TAG,
        'resetToDefaults failed: %{private}s', String(err));
    }
  }

  // ── Encryption mode helpers ──────────────────────────────────────

  /** Human-readable labels for the three encryption modes. */
  static readonly ENCRYPTION_MODE_LABELS: string[] = [
    'Allow', 'Prefer', 'Require',
  ];

  /** Get the stored encryption mode as a string enum value. */
  async getEncryptionMode(): Promise<EncryptionMode> {
    const val = await this.getString(PrefKeys.ENCRYPTION_MODE,
      EncryptionMode.PREFER);
    return encryptionModeFromString(val);
  }

  /** Set the encryption mode from a label index (0=Allow, 1=Prefer, 2=Require). */
  async setEncryptionModeIndex(index: number): Promise<void> {
    if (index >= 0 && index < ENCRYPTION_MODE_VALUES.length) {
      await this.setString(PrefKeys.ENCRYPTION_MODE,
        ENCRYPTION_MODE_VALUES[index]);
    }
  }
}
