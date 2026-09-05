// transmissionbtm — SettingsPage (M6)
//
// Scrollable settings list with grouped sections. All settings apply
// immediately via the M2 components (ToggleSetting, EditSetting,
// SelectSetting), each of which persists to PreferencesManager.
//
// Sections:
//   Downloads  — directories, file behavior
//   Speed      — rate limits, alt speed (turtle mode)
//   Network    — ports, peer limits, encryption, protocol toggles
//   Blocklist  — IP blocklist toggle + URL
//   RPC        — RPC server port, auth, credentials
//   Seeding    — ratio stop, idle stop

import { Colors, FontSize, Spacing, Radius } from '../utils/constants';
import { SettingsGroup } from '../components/settings/SettingsGroup';
import { ToggleSetting } from '../components/settings/ToggleSetting';
import { EditSetting } from '../components/settings/EditSetting';
import { SelectSetting } from '../components/settings/SelectSetting';
import { SettingsLoadingState } from '../components/settings/SettingsLoadingState';
import { SettingsErrorBanner } from '../components/settings/SettingsErrorBanner';
import { SettingsResetDialog } from '../components/settings/SettingsResetDialog';
import { SandboxSettingRow } from '../components/settings/SandboxSettingRow';
import { PublishFolderRow } from '../components/settings/PublishFolderRow';
import { PreferencesManager, PrefKeys } from '../models/Preferences';
import { defaultSessionConfig } from '../models/SessionConfig';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { promptAction } from '@kit.ArkUI';

const TAG = 'SettingsPage';

@Component
export struct SettingsPage {
  // ── Loading / Error ──────────────────────────────────────────────
  @State isLoading: boolean = true;
  @State loadError: ResourceStr = '';
  @State showResetDialog: boolean = false;

  // ── Downloads ──────────────────────────────────────────────────
  @State startAddedTorrents: boolean = defaultSessionConfig().startAddedTorrents;
  @State renamePartialFiles: boolean = defaultSessionConfig().renamePartialFiles;
  @State trashOriginalTorrentFile: boolean = defaultSessionConfig().trashOriginalTorrentFile;
  @State publishDir: string = '';

  // ── Speed ──────────────────────────────────────────────────────
  @State speedLimitDownEnabled: boolean = defaultSessionConfig().speedLimitDownEnabled;
  @State speedLimitDown: string = String(defaultSessionConfig().speedLimitDown);
  @State speedLimitUpEnabled: boolean = defaultSessionConfig().speedLimitUpEnabled;
  @State speedLimitUp: string = String(defaultSessionConfig().speedLimitUp);
  @State altSpeedEnabled: boolean = defaultSessionConfig().altSpeedEnabled;
  @State altSpeedDown: string = String(defaultSessionConfig().altSpeedDown);
  @State altSpeedUp: string = String(defaultSessionConfig().altSpeedUp);
  @State altSpeedTimeBegin: string = String(defaultSessionConfig().altSpeedTimeBegin);
  @State altSpeedTimeEnd: string = String(defaultSessionConfig().altSpeedTimeEnd);
  @State altSpeedDay: string = String(defaultSessionConfig().altSpeedDay);

  // ── Network ────────────────────────────────────────────────────
  @State peerPort: string = String(defaultSessionConfig().peerPort);
  @State peerLimitGlobal: string = String(defaultSessionConfig().peerLimitGlobal);
  @State peerLimitPerTorrent: string = String(defaultSessionConfig().peerLimitPerTorrent);
  @State encryptionIndex: number = 1; // 0=Allow, 1=Prefer, 2=Require
  @State utpEnabled: boolean = defaultSessionConfig().utpEnabled;
  @State pexEnabled: boolean = defaultSessionConfig().pexEnabled;
  @State dhtEnabled: boolean = defaultSessionConfig().dhtEnabled;
  @State lpdEnabled: boolean = defaultSessionConfig().lpdEnabled;

  // ── WiFi-only gating (Network) ─────────────────────────────────
  // Read by ConnectivityMonitor directly via PrefKeys.WIFI_ONLY /
  // WIFI_SSID — they gate transfers at runtime, not engine config.
  @State wifiOnly: boolean = false;
  @State wifiSsid: string = '';

  // ── Blocklist ──────────────────────────────────────────────────
  @State blocklistEnabled: boolean = defaultSessionConfig().blocklistEnabled;
  @State blocklistUrl: string = defaultSessionConfig().blocklistUrl;

  // ── RPC ────────────────────────────────────────────────────────
  @State rpcEnabled: boolean = defaultSessionConfig().enableRpc;
  @State rpcPort: string = String(defaultSessionConfig().rpcPort);
  @State rpcAuthentication: boolean = defaultSessionConfig().rpcAuthentication;
  @State rpcUsername: string = defaultSessionConfig().rpcUsername;
  @State rpcPassword: string = defaultSessionConfig().rpcPassword;
  @State rpcWhitelist: string = defaultSessionConfig().rpcWhitelist;
  @State rpcWhitelistEnabled: boolean = defaultSessionConfig().enableRpcWhitelist;

  // ── Seeding ────────────────────────────────────────────────────
  @State seedRatioLimited: boolean = defaultSessionConfig().seedRatioLimited;
  @State seedRatioLimit: string = String(defaultSessionConfig().seedRatioLimit);
  @State idleSeedingLimitEnabled: boolean = defaultSessionConfig().idleSeedingLimitEnabled;
  @State idleSeedingLimit: string = String(defaultSessionConfig().idleSeedingLimit);

  private encryptionOptions: string[] = PreferencesManager.ENCRYPTION_MODE_LABELS;
  private encryptionOptionValues: string[] = ['allow', 'prefer', 'require'];

  // ── General (language) ──────────────────────────────────────────
  // Lengths must match: [, zh-CN, en-US].
  @Watch('onLanguageChanged') @State languageIndex: number = 0;
  private languageOptions: ResourceStr[] = [
    $r('app.string.language_system'),
    $r('app.string.language_zh_cn'),
    $r('app.string.language_en_us'),
  ];
  private languageOptionValues: string[] = ['system', 'zh-CN', 'en-US'];
  /** Armed only after loadPreferences completes, so the startup load never fires the toast. */
  private languageLoaded: boolean = false;

  aboutToAppear(): void {
    this.loadPreferences();
  }

  private async loadPreferences(): Promise<void> {
    this.isLoading = true;
    this.loadError = '';
    try {
      const pm = PreferencesManager.getInstance();

      // Downloads
      this.startAddedTorrents = await pm.getBoolean(PrefKeys.START_ADDED_TORRENTS, this.startAddedTorrents);
      this.renamePartialFiles = await pm.getBoolean(PrefKeys.RENAME_PARTIAL_FILES, this.renamePartialFiles);
      this.trashOriginalTorrentFile = await pm.getBoolean(PrefKeys.TRASH_ORIGINAL_TORRENT_FILE, this.trashOriginalTorrentFile);
      this.publishDir = await pm.getString(PrefKeys.PUBLISH_DIR, '');

      // Speed
      this.speedLimitDownEnabled = await pm.getBoolean(PrefKeys.SPEED_LIMIT_DOWN_ENABLED, this.speedLimitDownEnabled);
      this.speedLimitDown = String(await pm.getInt(PrefKeys.SPEED_LIMIT_DOWN, Number(this.speedLimitDown)));
      this.speedLimitUpEnabled = await pm.getBoolean(PrefKeys.SPEED_LIMIT_UP_ENABLED, this.speedLimitUpEnabled);
      this.speedLimitUp = String(await pm.getInt(PrefKeys.SPEED_LIMIT_UP, Number(this.speedLimitUp)));
      this.altSpeedEnabled = await pm.getBoolean(PrefKeys.ALT_SPEED_ENABLED, this.altSpeedEnabled);
      this.altSpeedDown = String(await pm.getInt(PrefKeys.ALT_SPEED_DOWN, Number(this.altSpeedDown)));
      this.altSpeedUp = String(await pm.getInt(PrefKeys.ALT_SPEED_UP, Number(this.altSpeedUp)));
      this.altSpeedTimeBegin = String(await pm.getInt(PrefKeys.ALT_SPEED_TIME_BEGIN, Number(this.altSpeedTimeBegin)));
      this.altSpeedTimeEnd = String(await pm.getInt(PrefKeys.ALT_SPEED_TIME_END, Number(this.altSpeedTimeEnd)));
      this.altSpeedDay = String(await pm.getInt(PrefKeys.ALT_SPEED_DAY, Number(this.altSpeedDay)));

      // Network
      this.peerPort = String(await pm.getInt(PrefKeys.PEER_PORT, Number(this.peerPort)));
      this.peerLimitGlobal = String(await pm.getInt(PrefKeys.PEER_LIMIT_GLOBAL, Number(this.peerLimitGlobal)));
      this.peerLimitPerTorrent = String(await pm.getInt(PrefKeys.PEER_LIMIT_PER_TORRENT, Number(this.peerLimitPerTorrent)));
      const encMode = await pm.getString(PrefKeys.ENCRYPTION_MODE, 'prefer');
      this.encryptionIndex = encMode === 'allow' ? 0 : encMode === 'require' ? 2 : 1;

      // General (language)
      const lang = await pm.getString(PrefKeys.APP_LANGUAGE, 'system');
      this.languageIndex = lang === 'zh-CN' ? 1 : lang === 'en-US' ? 2 : 0;
      this.utpEnabled = await pm.getBoolean(PrefKeys.UTP_ENABLED, this.utpEnabled);
      this.pexEnabled = await pm.getBoolean(PrefKeys.PEX_ENABLED, this.pexEnabled);
      this.dhtEnabled = await pm.getBoolean(PrefKeys.DHT_ENABLED, this.dhtEnabled);
      this.lpdEnabled = await pm.getBoolean(PrefKeys.LPD_ENABLED, this.lpdEnabled);
      this.wifiOnly = await pm.getBoolean(PrefKeys.WIFI_ONLY, false);
      this.wifiSsid = await pm.getString(PrefKeys.WIFI_SSID, '');

      // Blocklist
      this.blocklistEnabled = await pm.getBoolean(PrefKeys.BLOCKLIST_ENABLED, this.blocklistEnabled);
      this.blocklistUrl = await pm.getString(PrefKeys.BLOCKLIST_URL, this.blocklistUrl);

      // RPC
      this.rpcEnabled = await pm.getBoolean(PrefKeys.ENABLE_RPC, this.rpcEnabled);
      this.rpcPort = String(await pm.getInt(PrefKeys.RPC_PORT, Number(this.rpcPort)));
      this.rpcAuthentication = await pm.getBoolean(PrefKeys.RPC_AUTHENTICATION, this.rpcAuthentication);
      this.rpcUsername = await pm.getString(PrefKeys.RPC_USERNAME, this.rpcUsername);
      this.rpcPassword = await pm.getString(PrefKeys.RPC_PASSWORD, this.rpcPassword);
      this.rpcWhitelist = await pm.getString(PrefKeys.RPC_WHITELIST, this.rpcWhitelist);
      this.rpcWhitelistEnabled = await pm.getBoolean(PrefKeys.ENABLE_RPC_WHITELIST, this.rpcWhitelistEnabled);

      // Seeding
      this.seedRatioLimited = await pm.getBoolean(PrefKeys.SEED_RATIO_LIMITED, this.seedRatioLimited);
      this.seedRatioLimit = String(await pm.getInt(PrefKeys.SEED_RATIO_LIMIT, Number(this.seedRatioLimit)));
      this.idleSeedingLimitEnabled = await pm.getBoolean(PrefKeys.IDLE_SEEDING_LIMIT_ENABLED, this.idleSeedingLimitEnabled);
      this.idleSeedingLimit = String(await pm.getInt(PrefKeys.IDLE_SEEDING_LIMIT, Number(this.idleSeedingLimit)));
    } catch (err) {
      this.loadError = $r('app.string.settings_load_error');
      hilog.error(0x0001, TAG,
        'loadPreferences failed: %{private}s', String(err));
    } finally {
      this.isLoading = false;
      this.languageLoaded = true;
    }
  }

  /** Show a restart-to-apply hint when the user changes the language. The @Watch
   * is armed after loadPreferences so the startup assignment (line 139) doesn't toast. */
  onLanguageChanged(): void {
    if (!this.languageLoaded) { return; }
    promptAction.showToast({
      message: $r('app.string.settings_language_restart_toast'),
      duration: 2000,
    });
  }

  /** Actual sandbox download dir; the engine always writes here (see
   * DownloadsPage.applySandboxPaths), regardless of any user-chosen path. */
  private getSandboxDir(): string {
    return `${getContext(this).filesDir}/downloads`;
  }

  private async onResetDefaults(): Promise<void> {
    this.showResetDialog = false;
    try {
      await PreferencesManager.getInstance().resetToDefaults();
      this.loadPreferences();
      hilog.info(0x0001, TAG, 'Settings reset to defaults');
    } catch (err) {
      hilog.error(0x0001, TAG,
        'resetToDefaults failed: %{private}s', String(err));
    }
  }

  build() {
    Stack() {
      Column() {
        // Page header
        Text($r('app.string.settings_title'))
          .fontSize(FontSize.XL)
          .fontWeight(FontWeight.Bold)
          .fontColor(Colors.TEXT)
          .width('100%')
          .padding({
            left: Spacing.LG,
            top: Spacing.LG,
            bottom: Spacing.LG,
          });

        if (this.isLoading) {
          SettingsLoadingState();
        } else {
          this.BuildContent();
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor(Colors.BG);

      // Reset confirmation dialog
      if (this.showResetDialog) {
        SettingsResetDialog({
          onConfirm: () => { this.onResetDefaults(); },
          onCancel: () => { this.showResetDialog = false; },
        });
      }
    }
    .width('100%')
    .height('100%');
  }

  @Builder
  BuildContent() {
    Column() {
      // Error banner
      if (this.loadError) {
        SettingsErrorBanner({ error: this.loadError });
      }

      // Scrollable settings body
      Scroll() {
        Column() {
          this.BuildGeneralSection();
          this.BuildDownloadsSection();
          this.BuildSpeedSection();
          this.BuildNetworkSection();
          this.BuildBlocklistSection();
          this.BuildRpcSection();
          this.BuildSeedingSection();
          this.BuildResetButton();
        }
        .padding({ bottom: 80 });
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off);
    }
    .layoutWeight(1)
    .width('100%');
  }

  // ═══════════════════════════════════════════════════════════════
  // General Section (language)
  // ═══════════════════════════════════════════════════════════════

  @Builder
  BuildGeneralSection() {
    SettingsGroup({ title: $r('app.string.settings_general') }) {
      SelectSetting({
        label: $r('app.string.settings_language'),
        options: this.languageOptions,
        prefKey: PrefKeys.APP_LANGUAGE,
        selectedIndex: $languageIndex,
        valueType: 'string',
        optionValues: this.languageOptionValues,
      });
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // Downloads Section
  // ═══════════════════════════════════════════════════════════════

  @Builder
  BuildDownloadsSection() {
    SettingsGroup({ title: $r('app.string.settings_section_downloads') }) {
      // Download & incomplete dirs are read-only (see getSandboxDir). HarmonyOS
      // NEXT sandboxes third-party apps; the engine needs a real POSIX path, so
      // DownloadsPage.applySandboxPaths() overrides the session dirs to the app
      // filesDir. A folder picked here would be silently ignored — show the real
      // sandbox path, and publish finished data via the torrent "Save to Files".
      // Download dir is read-only: HarmonyOS NEXT sandboxes third-party apps and
      // the engine needs a real POSIX path, so DownloadsPage.applySandboxPaths()
      // overrides the session dir to the app filesDir. Publish folder is the one
      // actionable control — it copies finished files to a system-visible place.
      SandboxSettingRow({ label: $r('app.string.settings_download_dir'), value: this.getSandboxDir() });
      PublishFolderRow({ publishDir: $publishDir });
      Row() {
        Text($r('app.string.settings_sandbox_desc'))
          .fontSize(FontSize.CAPTION)
          .fontColor(Colors.TEXT_SECONDARY)
          .layoutWeight(1);
      }
      .width('100%')
      .padding({ left: Spacing.LG, right: Spacing.LG, top: 2, bottom: Spacing.MD });

      ToggleSetting({
        label: $r('app.string.settings_start_when_added'),
        description: $r('app.string.settings_start_when_added_desc'),
        prefKey: PrefKeys.START_ADDED_TORRENTS,
        checked: $startAddedTorrents,
      });
      ToggleSetting({
        label: $r('app.string.settings_rename_partial_files'),
        description: $r('app.string.settings_rename_partial_files_desc'),
        prefKey: PrefKeys.RENAME_PARTIAL_FILES,
        checked: $renamePartialFiles,
      });
      ToggleSetting({
        label: $r('app.string.settings_trash_original'),
        description: $r('app.string.settings_trash_original_desc'),
        prefKey: PrefKeys.TRASH_ORIGINAL_TORRENT_FILE,
        checked: $trashOriginalTorrentFile,
      });
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // Speed Section
  // ═══════════════════════════════════════════════════════════════

  @Builder
  BuildSpeedSection() {
    SettingsGroup({ title: $r('app.string.settings_section_speed') }) {
      ToggleSetting({
        label: $r('app.string.settings_limit_download_speed'),
        prefKey: PrefKeys.SPEED_LIMIT_DOWN_ENABLED,
        checked: $speedLimitDownEnabled,
      });
      if (this.speedLimitDownEnabled) {
        EditSetting({
          label: $r('app.string.settings_download_limit'),
          hint: $r('app.string.settings_speed_hint_unlimited'),
          prefKey: PrefKeys.SPEED_LIMIT_DOWN,
          value: $speedLimitDown,
          inputType: InputType.Number,
          valueType: 'number',
        });
      }

      ToggleSetting({
        label: $r('app.string.settings_limit_upload_speed'),
        prefKey: PrefKeys.SPEED_LIMIT_UP_ENABLED,
        checked: $speedLimitUpEnabled,
      });
      if (this.speedLimitUpEnabled) {
        EditSetting({
          label: $r('app.string.settings_upload_limit'),
          hint: $r('app.string.settings_speed_hint_unlimited'),
          prefKey: PrefKeys.SPEED_LIMIT_UP,
          value: $speedLimitUp,
          inputType: InputType.Number,
          valueType: 'number',
        });
      }

      ToggleSetting({
        label: $r('app.string.settings_alt_speed'),
        description: $r('app.string.settings_alt_speed_desc'),
        prefKey: PrefKeys.ALT_SPEED_ENABLED,
        checked: $altSpeedEnabled,
      });
      if (this.altSpeedEnabled) {
        EditSetting({
          label: $r('app.string.settings_alt_download'),
          hint: '50',
          prefKey: PrefKeys.ALT_SPEED_DOWN,
          value: $altSpeedDown,
          inputType: InputType.Number,
          valueType: 'number',
        });
        EditSetting({
          label: $r('app.string.settings_alt_upload'),
          hint: '50',
          prefKey: PrefKeys.ALT_SPEED_UP,
          value: $altSpeedUp,
          inputType: InputType.Number,
          valueType: 'number',
        });
        EditSetting({
          label: $r('app.string.settings_alt_begin'),
          hint: $r('app.string.settings_alt_begin_hint'),
          prefKey: PrefKeys.ALT_SPEED_TIME_BEGIN,
          value: $altSpeedTimeBegin,
          inputType: InputType.Number,
          valueType: 'number',
        });
        EditSetting({
          label: $r('app.string.settings_alt_end'),
          hint: $r('app.string.settings_alt_end_hint'),
          prefKey: PrefKeys.ALT_SPEED_TIME_END,
          value: $altSpeedTimeEnd,
          inputType: InputType.Number,
          valueType: 'number',
        });
        EditSetting({
          label: $r('app.string.settings_alt_days'),
          hint: $r('app.string.settings_alt_days_hint'),
          prefKey: PrefKeys.ALT_SPEED_DAY,
          value: $altSpeedDay,
          inputType: InputType.Number,
          valueType: 'number',
        });
      }
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // Network Section
  // ═══════════════════════════════════════════════════════════════

  @Builder
  BuildNetworkSection() {
    SettingsGroup({ title: $r('app.string.settings_section_network') }) {
      EditSetting({
        label: $r('app.string.settings_peer_port'),
        hint: '51413',
        prefKey: PrefKeys.PEER_PORT,
        value: $peerPort,
        inputType: InputType.Number,
        valueType: 'number',
      });
      EditSetting({
        label: $r('app.string.settings_global_peer_limit'),
        hint: '200',
        prefKey: PrefKeys.PEER_LIMIT_GLOBAL,
        value: $peerLimitGlobal,
        inputType: InputType.Number,
        valueType: 'number',
      });
      EditSetting({
        label: $r('app.string.settings_peers_per_torrent'),
        hint: '50',
        prefKey: PrefKeys.PEER_LIMIT_PER_TORRENT,
        value: $peerLimitPerTorrent,
        inputType: InputType.Number,
        valueType: 'number',
      });
      SelectSetting({
        label: $r('app.string.settings_encryption'),
        options: this.encryptionOptions,
        prefKey: PrefKeys.ENCRYPTION_MODE,
        selectedIndex: $encryptionIndex,
        valueType: 'string',
        optionValues: this.encryptionOptionValues,
      });
      // Protocol toggles — 4 short toggles packed 2-per-row to cut vertical height.
      Row() {
        ToggleSetting({
          label: $r('app.string.settings_utp'),
          prefKey: PrefKeys.UTP_ENABLED,
          checked: $utpEnabled,
        }).layoutWeight(1);
        ToggleSetting({
          label: $r('app.string.settings_pex'),
          prefKey: PrefKeys.PEX_ENABLED,
          checked: $pexEnabled,
        }).layoutWeight(1);
      }
      .width('100%');

      Row() {
        ToggleSetting({
          label: $r('app.string.settings_dht'),
          prefKey: PrefKeys.DHT_ENABLED,
          checked: $dhtEnabled,
        }).layoutWeight(1);
        ToggleSetting({
          label: $r('app.string.settings_lpd'),
          prefKey: PrefKeys.LPD_ENABLED,
          checked: $lpdEnabled,
        }).layoutWeight(1);
      }
      .width('100%');
      ToggleSetting({
        label: $r('app.string.settings_wifi_only'),
        description: $r('app.string.settings_wifi_only_desc'),
        prefKey: PrefKeys.WIFI_ONLY,
        checked: $wifiOnly,
      });
      if (this.wifiOnly) {
        EditSetting({
          label: $r('app.string.settings_wifi_ssids'),
          hint: $r('app.string.settings_wifi_ssids_hint'),
          prefKey: PrefKeys.WIFI_SSID,
          value: $wifiSsid,
        });
      }
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // Blocklist Section
  // ═══════════════════════════════════════════════════════════════

  @Builder
  BuildBlocklistSection() {
    SettingsGroup({ title: $r('app.string.settings_section_blocklist') }) {
      ToggleSetting({
        label: $r('app.string.settings_enable_blocklist'),
        description: $r('app.string.settings_enable_blocklist_desc'),
        prefKey: PrefKeys.BLOCKLIST_ENABLED,
        checked: $blocklistEnabled,
      });
      if (this.blocklistEnabled) {
        EditSetting({
          label: $r('app.string.settings_blocklist_url'),
          hint: 'https://list.iblocklist.com/blist.txt',
          prefKey: PrefKeys.BLOCKLIST_URL,
          value: $blocklistUrl,
        });
      }
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // RPC Section
  // ═══════════════════════════════════════════════════════════════

  @Builder
  BuildRpcSection() {
    SettingsGroup({ title: $r('app.string.settings_section_rpc') }) {
      ToggleSetting({
        label: $r('app.string.settings_enable_rpc'),
        description: $r('app.string.settings_enable_rpc_desc'),
        prefKey: PrefKeys.ENABLE_RPC,
        checked: $rpcEnabled,
      });
      if (this.rpcEnabled) {
        EditSetting({
          label: $r('app.string.settings_rpc_port'),
          hint: '9091',
          prefKey: PrefKeys.RPC_PORT,
          value: $rpcPort,
          inputType: InputType.Number,
          valueType: 'number',
        });
        ToggleSetting({
          label: $r('app.string.settings_authentication'),
          description: $r('app.string.settings_authentication_desc'),
          prefKey: PrefKeys.RPC_AUTHENTICATION,
          checked: $rpcAuthentication,
        });
        if (this.rpcAuthentication) {
          EditSetting({
            label: $r('app.string.settings_username'),
            hint: 'admin',
            prefKey: PrefKeys.RPC_USERNAME,
            value: $rpcUsername,
          });
          EditSetting({
            label: $r('app.string.settings_password'),
            hint: '••••••••',
            prefKey: PrefKeys.RPC_PASSWORD,
            value: $rpcPassword,
            inputType: InputType.Password,
          });
        }
        ToggleSetting({
          label: $r('app.string.settings_rpc_whitelist_enabled'),
          description: $r('app.string.settings_rpc_whitelist_enabled_desc'),
          prefKey: PrefKeys.ENABLE_RPC_WHITELIST,
          checked: $rpcWhitelistEnabled,
        });
        if (this.rpcWhitelistEnabled) {
          EditSetting({
            label: $r('app.string.settings_rpc_whitelist'),
            hint: $r('app.string.settings_rpc_whitelist_hint'),
            prefKey: PrefKeys.RPC_WHITELIST,
            value: $rpcWhitelist,
          });
        }
      }
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // Seeding Section
  // ═══════════════════════════════════════════════════════════════

  @Builder
  BuildSeedingSection() {
    SettingsGroup({ title: $r('app.string.settings_section_seeding') }) {
      ToggleSetting({
        label: $r('app.string.settings_stop_at_ratio'),
        description: $r('app.string.settings_stop_at_ratio_desc'),
        prefKey: PrefKeys.SEED_RATIO_LIMITED,
        checked: $seedRatioLimited,
      });
      if (this.seedRatioLimited) {
        EditSetting({
          label: $r('app.string.settings_seed_ratio_limit'),
          hint: '2.0',
          prefKey: PrefKeys.SEED_RATIO_LIMIT,
          value: $seedRatioLimit,
          inputType: InputType.Number,
          valueType: 'float',
        });
      }

      ToggleSetting({
        label: $r('app.string.settings_stop_if_idle'),
        description: $r('app.string.settings_stop_if_idle_desc'),
        prefKey: PrefKeys.IDLE_SEEDING_LIMIT_ENABLED,
        checked: $idleSeedingLimitEnabled,
      });
      if (this.idleSeedingLimitEnabled) {
        EditSetting({
          label: $r('app.string.settings_idle_timeout'),
          hint: '30',
          prefKey: PrefKeys.IDLE_SEEDING_LIMIT,
          value: $idleSeedingLimit,
          inputType: InputType.Number,
          valueType: 'number',
        });
      }
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // Reset Button
  // ═══════════════════════════════════════════════════════════════

  @Builder
  BuildResetButton() {
    Button($r('app.string.settings_reset_defaults'))
      .fontSize(FontSize.CAPTION)
      .fontColor(Colors.ERROR)
      .backgroundColor(Colors.ELEVATED)
      .borderRadius(Radius.MD)
      .width('90%')
      .height(44)
      .margin({ top: Spacing.XL })
      .onClick(() => { this.showResetDialog = true; });
  }
}
