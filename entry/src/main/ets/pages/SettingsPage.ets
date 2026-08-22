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

const TAG = 'SettingsPage';

@Component
export struct SettingsPage {
  // ── Loading / Error ──────────────────────────────────────────────
  @State isLoading: boolean = true;
  @State loadError: string = '';
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

  // ── Blocklist ──────────────────────────────────────────────────
  @State blocklistEnabled: boolean = defaultSessionConfig().blocklistEnabled;
  @State blocklistUrl: string = defaultSessionConfig().blocklistUrl;

  // ── RPC ────────────────────────────────────────────────────────
  @State rpcEnabled: boolean = defaultSessionConfig().enableRpc;
  @State rpcPort: string = String(defaultSessionConfig().rpcPort);
  @State rpcAuthentication: boolean = defaultSessionConfig().rpcAuthentication;
  @State rpcUsername: string = defaultSessionConfig().rpcUsername;
  @State rpcPassword: string = defaultSessionConfig().rpcPassword;

  // ── Seeding ────────────────────────────────────────────────────
  @State seedRatioLimited: boolean = defaultSessionConfig().seedRatioLimited;
  @State seedRatioLimit: string = String(defaultSessionConfig().seedRatioLimit);
  @State idleSeedingLimitEnabled: boolean = defaultSessionConfig().idleSeedingLimitEnabled;
  @State idleSeedingLimit: string = String(defaultSessionConfig().idleSeedingLimit);

  private encryptionOptions: string[] = PreferencesManager.ENCRYPTION_MODE_LABELS;
  private encryptionOptionValues: string[] = ['allow', 'prefer', 'require'];

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
      this.utpEnabled = await pm.getBoolean(PrefKeys.UTP_ENABLED, this.utpEnabled);
      this.pexEnabled = await pm.getBoolean(PrefKeys.PEX_ENABLED, this.pexEnabled);
      this.dhtEnabled = await pm.getBoolean(PrefKeys.DHT_ENABLED, this.dhtEnabled);
      this.lpdEnabled = await pm.getBoolean(PrefKeys.LPD_ENABLED, this.lpdEnabled);

      // Blocklist
      this.blocklistEnabled = await pm.getBoolean(PrefKeys.BLOCKLIST_ENABLED, this.blocklistEnabled);
      this.blocklistUrl = await pm.getString(PrefKeys.BLOCKLIST_URL, this.blocklistUrl);

      // RPC
      this.rpcEnabled = await pm.getBoolean(PrefKeys.ENABLE_RPC, this.rpcEnabled);
      this.rpcPort = String(await pm.getInt(PrefKeys.RPC_PORT, Number(this.rpcPort)));
      this.rpcAuthentication = await pm.getBoolean(PrefKeys.RPC_AUTHENTICATION, this.rpcAuthentication);
      this.rpcUsername = await pm.getString(PrefKeys.RPC_USERNAME, this.rpcUsername);
      this.rpcPassword = await pm.getString(PrefKeys.RPC_PASSWORD, this.rpcPassword);

      // Seeding
      this.seedRatioLimited = await pm.getBoolean(PrefKeys.SEED_RATIO_LIMITED, this.seedRatioLimited);
      this.seedRatioLimit = String(await pm.getInt(PrefKeys.SEED_RATIO_LIMIT, Number(this.seedRatioLimit)));
      this.idleSeedingLimitEnabled = await pm.getBoolean(PrefKeys.IDLE_SEEDING_LIMIT_ENABLED, this.idleSeedingLimitEnabled);
      this.idleSeedingLimit = String(await pm.getInt(PrefKeys.IDLE_SEEDING_LIMIT, Number(this.idleSeedingLimit)));
    } catch (err) {
      this.loadError = 'Failed to load settings. Using defaults.';
      hilog.error(0x0001, TAG,
        'loadPreferences failed: %{private}s', String(err));
    } finally {
      this.isLoading = false;
    }
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
        Text('Settings')
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
      if (this.loadError.length > 0) {
        SettingsErrorBanner({ error: this.loadError });
      }

      // Scrollable settings body
      Scroll() {
        Column() {
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
  // Downloads Section
  // ═══════════════════════════════════════════════════════════════

  @Builder
  BuildDownloadsSection() {
    SettingsGroup({ title: 'Downloads' }) {
      // Download & incomplete dirs are read-only (see getSandboxDir). HarmonyOS
      // NEXT sandboxes third-party apps; the engine needs a real POSIX path, so
      // DownloadsPage.applySandboxPaths() overrides the session dirs to the app
      // filesDir. A folder picked here would be silently ignored — show the real
      // sandbox path, and publish finished data via the torrent "Save to Files".
      SandboxSettingRow({ label: 'Download dir', value: this.getSandboxDir() });
      SandboxSettingRow({ label: 'Incomplete dir', value: this.getSandboxDir() + '/.incomplete' });
      PublishFolderRow({ publishDir: $publishDir });
      Row() {
        Text('Downloads are written to the app sandbox (the engine needs a real POSIX path, '
          + 'and HarmonyOS NEXT gives a phone app no shared-dir write). Pick a "Publish folder" '
          + 'above, or use the torrent "Save to Files" action, to copy finished files into a '
          + 'system-visible Download folder.')
          .fontSize(FontSize.CAPTION)
          .fontColor(Colors.TEXT_SECONDARY)
          .layoutWeight(1)
          .padding({ right: Spacing.SM });
      }
      .width('100%')
      .padding({ left: Spacing.LG, right: Spacing.LG, top: 2, bottom: Spacing.MD });

      ToggleSetting({
        label: 'Start when added',
        description: 'Begin downloading torrents immediately',
        prefKey: PrefKeys.START_ADDED_TORRENTS,
        checked: $startAddedTorrents,
      });
      ToggleSetting({
        label: 'Rename partial files',
        description: 'Append .part to incomplete files',
        prefKey: PrefKeys.RENAME_PARTIAL_FILES,
        checked: $renamePartialFiles,
      });
      ToggleSetting({
        label: 'Trash original torrent file',
        description: 'Move .torrent file to trash after adding',
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
    SettingsGroup({ title: 'Speed' }) {
      ToggleSetting({
        label: 'Limit download speed',
        prefKey: PrefKeys.SPEED_LIMIT_DOWN_ENABLED,
        checked: $speedLimitDownEnabled,
      });
      if (this.speedLimitDownEnabled) {
        EditSetting({
          label: 'Download limit (KB/s)',
          hint: '0 = unlimited',
          prefKey: PrefKeys.SPEED_LIMIT_DOWN,
          value: $speedLimitDown,
          inputType: InputType.Number,
          valueType: 'number',
        });
      }

      ToggleSetting({
        label: 'Limit upload speed',
        prefKey: PrefKeys.SPEED_LIMIT_UP_ENABLED,
        checked: $speedLimitUpEnabled,
      });
      if (this.speedLimitUpEnabled) {
        EditSetting({
          label: 'Upload limit (KB/s)',
          hint: '0 = unlimited',
          prefKey: PrefKeys.SPEED_LIMIT_UP,
          value: $speedLimitUp,
          inputType: InputType.Number,
          valueType: 'number',
        });
      }

      ToggleSetting({
        label: 'Alternative speed',
        description: 'Scheduled lower speed limits',
        prefKey: PrefKeys.ALT_SPEED_ENABLED,
        checked: $altSpeedEnabled,
      });
      if (this.altSpeedEnabled) {
        EditSetting({
          label: 'Alt download (KB/s)',
          hint: '50',
          prefKey: PrefKeys.ALT_SPEED_DOWN,
          value: $altSpeedDown,
          inputType: InputType.Number,
          valueType: 'number',
        });
        EditSetting({
          label: 'Alt upload (KB/s)',
          hint: '50',
          prefKey: PrefKeys.ALT_SPEED_UP,
          value: $altSpeedUp,
          inputType: InputType.Number,
          valueType: 'number',
        });
        EditSetting({
          label: 'Begin (minutes)',
          hint: '480 = 8:00 AM',
          prefKey: PrefKeys.ALT_SPEED_TIME_BEGIN,
          value: $altSpeedTimeBegin,
          inputType: InputType.Number,
          valueType: 'number',
        });
        EditSetting({
          label: 'End (minutes)',
          hint: '1080 = 6:00 PM',
          prefKey: PrefKeys.ALT_SPEED_TIME_END,
          value: $altSpeedTimeEnd,
          inputType: InputType.Number,
          valueType: 'number',
        });
        EditSetting({
          label: 'Days (bitmask)',
          hint: '127 = every day',
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
    SettingsGroup({ title: 'Network' }) {
      EditSetting({
        label: 'Peer port',
        hint: '51413',
        prefKey: PrefKeys.PEER_PORT,
        value: $peerPort,
        inputType: InputType.Number,
        valueType: 'number',
      });
      EditSetting({
        label: 'Global peer limit',
        hint: '200',
        prefKey: PrefKeys.PEER_LIMIT_GLOBAL,
        value: $peerLimitGlobal,
        inputType: InputType.Number,
        valueType: 'number',
      });
      EditSetting({
        label: 'Peers per torrent',
        hint: '50',
        prefKey: PrefKeys.PEER_LIMIT_PER_TORRENT,
        value: $peerLimitPerTorrent,
        inputType: InputType.Number,
        valueType: 'number',
      });
      SelectSetting({
        label: 'Encryption',
        options: this.encryptionOptions,
        prefKey: PrefKeys.ENCRYPTION_MODE,
        selectedIndex: $encryptionIndex,
        valueType: 'string',
        optionValues: this.encryptionOptionValues,
      });
      ToggleSetting({
        label: 'uTP',
        description: 'Micro Transport Protocol',
        prefKey: PrefKeys.UTP_ENABLED,
        checked: $utpEnabled,
      });
      ToggleSetting({
        label: 'PEX',
        description: 'Peer Exchange',
        prefKey: PrefKeys.PEX_ENABLED,
        checked: $pexEnabled,
      });
      ToggleSetting({
        label: 'DHT',
        description: 'Distributed Hash Table',
        prefKey: PrefKeys.DHT_ENABLED,
        checked: $dhtEnabled,
      });
      ToggleSetting({
        label: 'LPD',
        description: 'Local Peer Discovery',
        prefKey: PrefKeys.LPD_ENABLED,
        checked: $lpdEnabled,
      });
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // Blocklist Section
  // ═══════════════════════════════════════════════════════════════

  @Builder
  BuildBlocklistSection() {
    SettingsGroup({ title: 'Blocklist' }) {
      ToggleSetting({
        label: 'Enable blocklist',
        description: 'Block known malicious IP ranges',
        prefKey: PrefKeys.BLOCKLIST_ENABLED,
        checked: $blocklistEnabled,
      });
      if (this.blocklistEnabled) {
        EditSetting({
          label: 'Blocklist URL',
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
    SettingsGroup({ title: 'Remote Control (RPC)' }) {
      ToggleSetting({
        label: 'Enable RPC server',
        description: 'Off by default — no web UI is bundled. ' +
          'Enabling binds the RPC port; keep whitelist & auth set.',
        prefKey: PrefKeys.ENABLE_RPC,
        checked: $rpcEnabled,
      });
      if (this.rpcEnabled) {
        EditSetting({
          label: 'RPC port',
          hint: '9091',
          prefKey: PrefKeys.RPC_PORT,
          value: $rpcPort,
          inputType: InputType.Number,
          valueType: 'number',
        });
        ToggleSetting({
          label: 'Authentication',
          description: 'Require username & password for RPC access',
          prefKey: PrefKeys.RPC_AUTHENTICATION,
          checked: $rpcAuthentication,
        });
        if (this.rpcAuthentication) {
          EditSetting({
            label: 'Username',
            hint: 'admin',
            prefKey: PrefKeys.RPC_USERNAME,
            value: $rpcUsername,
          });
          EditSetting({
            label: 'Password',
            hint: '••••••••',
            prefKey: PrefKeys.RPC_PASSWORD,
            value: $rpcPassword,
            inputType: InputType.Password,
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
    SettingsGroup({ title: 'Seeding' }) {
      ToggleSetting({
        label: 'Stop seeding at ratio',
        description: 'Stop when share ratio is reached',
        prefKey: PrefKeys.SEED_RATIO_LIMITED,
        checked: $seedRatioLimited,
      });
      if (this.seedRatioLimited) {
        EditSetting({
          label: 'Seed ratio limit',
          hint: '2.0',
          prefKey: PrefKeys.SEED_RATIO_LIMIT,
          value: $seedRatioLimit,
          inputType: InputType.Number,
          valueType: 'float',
        });
      }

      ToggleSetting({
        label: 'Stop if idle',
        description: 'Stop seeding after idle timeout',
        prefKey: PrefKeys.IDLE_SEEDING_LIMIT_ENABLED,
        checked: $idleSeedingLimitEnabled,
      });
      if (this.idleSeedingLimitEnabled) {
        EditSetting({
          label: 'Idle timeout (min)',
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
    Button('Reset to Defaults')
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
