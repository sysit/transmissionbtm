// transmissionhm — SettingsPage (M6)
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
import { BrowsePathView } from '../components/settings/BrowsePathView';
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
  @State downloadDir: string = defaultSessionConfig().downloadDir;
  @State incompleteDir: string = defaultSessionConfig().incompleteDir;
  @State startAddedTorrents: boolean = defaultSessionConfig().startAddedTorrents;
  @State renamePartialFiles: boolean = defaultSessionConfig().renamePartialFiles;
  @State trashOriginalTorrentFile: boolean = defaultSessionConfig().trashOriginalTorrentFile;

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
      this.downloadDir = await pm.getString(PrefKeys.DOWNLOAD_DIR, this.downloadDir);
      this.incompleteDir = await pm.getString(PrefKeys.INCOMPLETE_DIR, this.incompleteDir);
      this.startAddedTorrents = await pm.getBoolean(PrefKeys.START_ADDED_TORRENTS, this.startAddedTorrents);
      this.renamePartialFiles = await pm.getBoolean(PrefKeys.RENAME_PARTIAL_FILES, this.renamePartialFiles);
      this.trashOriginalTorrentFile = await pm.getBoolean(PrefKeys.TRASH_ORIGINAL_TORRENT_FILE, this.trashOriginalTorrentFile);

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
        'loadPreferences failed: %{public}s', String(err));
    } finally {
      this.isLoading = false;
    }
  }

  private async onResetDefaults(): Promise<void> {
    this.showResetDialog = false;
    try {
      await PreferencesManager.getInstance().resetToDefaults();
      this.loadPreferences();
      hilog.info(0x0001, TAG, 'Settings reset to defaults');
    } catch (err) {
      hilog.error(0x0001, TAG,
        'resetToDefaults failed: %{public}s', String(err));
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
          this.BuildLoadingState();
        } else {
          this.BuildContent();
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor(Colors.BG);

      // Reset confirmation dialog
      if (this.showResetDialog) {
        this.BuildResetDialog();
      }
    }
    .width('100%')
    .height('100%');
  }

  @Builder
  BuildLoadingState() {
    Column() {
      LoadingProgress()
        .width(40)
        .height(40)
        .color(Colors.DOWNLOAD);
      Text('Loading settings...')
        .fontSize(FontSize.CAPTION)
        .fontColor(Colors.TEXT_SECONDARY)
        .margin({ top: Spacing.MD });
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center);
  }

  @Builder
  BuildContent() {
    Column() {
      // Error banner
      if (this.loadError.length > 0) {
        this.BuildErrorBanner();
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

  @Builder
  BuildErrorBanner() {
    Row() {
      Text('⚠ ' + this.loadError)
        .fontSize(FontSize.CAPTION)
        .fontColor(Colors.ERROR)
        .layoutWeight(1);
    }
    .width('100%')
    .padding({ left: Spacing.LG, right: Spacing.LG, top: Spacing.SM, bottom: Spacing.MD })
    .backgroundColor(Colors.ELEVATED)
    .border({
      width: { bottom: 1 },
      color: Colors.ERROR,
    });
  }

  @Builder
  BuildResetDialog() {
    Column() {
      Column() {
        Text('Reset to Defaults')
          .fontSize(FontSize.HEADLINE)
          .fontWeight(FontWeight.Medium)
          .fontColor(Colors.TEXT)
          .margin({ bottom: Spacing.MD });

        Text('This will reset all settings to their factory defaults. This action cannot be undone.')
          .fontSize(FontSize.CAPTION)
          .fontColor(Colors.TEXT_SECONDARY)
          .margin({ bottom: Spacing.LG });

        Row() {
          Button('Cancel')
            .fontSize(FontSize.CAPTION)
            .fontColor(Colors.TEXT_SECONDARY)
            .backgroundColor(Colors.ELEVATED)
            .layoutWeight(1)
            .onClick(() => { this.showResetDialog = false; });

          Button('Reset')
            .fontSize(FontSize.CAPTION)
            .fontColor('#ffffff')
            .backgroundColor(Colors.ERROR)
            .layoutWeight(1)
            .margin({ left: Spacing.MD })
            .onClick(() => { this.onResetDefaults(); });
        }
        .width('100%');
      }
      .padding(Spacing.XL)
      .borderRadius(Radius.LG)
      .backgroundColor(Colors.SURFACE);
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .padding(Spacing.XL)
    .backgroundColor('rgba(0,0,0,0.6)')
    .onClick(() => { this.showResetDialog = false; });
  }

  // ═══════════════════════════════════════════════════════════════
  // Downloads Section
  // ═══════════════════════════════════════════════════════════════

  @Builder
  BuildDownloadsSection() {
    SettingsGroup({ title: 'Downloads' }) {
      BrowsePathView({ label: 'Download dir', path: $downloadDir });
      EditSetting({
        label: 'Incomplete dir',
        hint: '/storage/downloads/.incomplete',
        prefKey: PrefKeys.INCOMPLETE_DIR,
        value: $incompleteDir,
      });
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
