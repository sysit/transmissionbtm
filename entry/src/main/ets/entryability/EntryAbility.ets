// transmissionhm — App entry point (M5)
// Initializes preferences, starts the background Transmission service,
// and handles external intents (magnet links, .torrent files).

import { UIAbility, Want, AbilityConstant } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { PreferencesManager } from '../models/Preferences';

const TAG = 'transmissionhm';

/** Parsed external intent for torrent adding. */
export interface TorrentIntent {
  kind: 'magnet' | 'file' | 'unknown';
  uri: string;
}

export default class EntryAbility extends UIAbility {
  /** Pending intent parsed during cold-start, consumed by Index page. */
  private pendingTorrentIntent: TorrentIntent | null = null;

  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(0x0001, TAG, 'EntryAbility onCreate');

    // Initialize preferences store for all app settings
    try {
      PreferencesManager.getInstance().init(this.context);
      hilog.info(0x0001, TAG, 'Preferences initialized');
    } catch (err) {
      hilog.error(0x0001, TAG,
        'Preferences init failed: %{public}s', String(err));
    }

    // Start the background Transmission service
    this.startTransmissionService();

    // Parse external intent if launched via magnet/file URI
    this.pendingTorrentIntent = this.parseIntent(want);
  }

  /**
   * Called when the app is already running and receives a new intent.
   * Required for processing magnet/file URIs while app is in foreground.
   */
  onNewWant(want: Want, _launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(0x0001, TAG, 'EntryAbility onNewWant');

    const intent = this.parseIntent(want);
    if (intent.kind !== 'unknown') {
      this.pendingTorrentIntent = intent;
    }
  }

  /** Consume and clear the pending torrent intent. Called by Index page. */
  consumePendingIntent(): TorrentIntent | null {
    const intent = this.pendingTorrentIntent;
    this.pendingTorrentIntent = null;
    return intent;
  }

  /**
   * Parse a Want into a TorrentIntent.
   * Handles magnet:// scheme and file:///https:// torrent URIs.
   */
  private parseIntent(want: Want): TorrentIntent {
    try {
      const uri = want?.uri ?? '';

      if (uri.length > 0) {
        // Magnet link
        if (uri.startsWith('magnet:')) {
          hilog.info(0x0001, TAG, 'Parsed magnet intent');
          return { kind: 'magnet', uri: uri };
        }

        // .torrent file (file://, content://, https://)
        const lower = uri.toLowerCase();
        if (lower.endsWith('.torrent') ||
            (want?.type ?? '').includes('x-bittorrent')) {
          hilog.info(0x0001, TAG, 'Parsed torrent file intent');
          return { kind: 'file', uri: uri };
        }
      }

      // Check parameters for file paths
      if (want?.parameters) {
        const params = want.parameters as Record<string, Object>;
        const filePath = params['filePath'] as string | undefined;
        if (filePath && filePath.toLowerCase().endsWith('.torrent')) {
          return { kind: 'file', uri: filePath };
        }
      }
    } catch (err) {
      hilog.error(0x0001, TAG,
        'parseIntent failed: %{public}s', String(err));
    }

    return { kind: 'unknown', uri: '' };
  }

  private startTransmissionService(): void {
    try {
      const serviceWant: Want = {
        // P0 fix (codex review): was hardcoded 'com.transmissionhm' — the
        // real bundle is com.9bt.transmission (AppScope/app.json5), so
        // startUIServiceExtensionAbility always failed.
        bundleName: 'com.9bt.transmission',
        abilityName: 'TransmissionService',
      };
      this.context.startUIServiceExtensionAbility(serviceWant)
        .then(() => {
          hilog.info(0x0001, TAG, 'TransmissionService started');
        })
        .catch((err: Error) => {
          hilog.error(0x0001, TAG,
            'Failed to start TransmissionService: %{public}s', String(err));
        });
    } catch (err) {
      hilog.error(0x0001, TAG,
        'startServiceExtensionAbility failed: %{public}s', String(err));
    }
  }

  onDestroy(): void {
    hilog.info(0x0001, TAG, 'EntryAbility onDestroy');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    hilog.info(0x0001, TAG, 'EntryAbility onWindowStageCreate');

    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        hilog.error(0x0001, TAG,
          'Failed to load the content. Cause: %{public}s', JSON.stringify(err));
        return;
      }
      hilog.info(0x0001, TAG, 'Succeeded in loading the content.');
    });
  }

  onWindowStageDestroy(): void {
    hilog.info(0x0001, TAG, 'EntryAbility onWindowStageDestroy');
  }

  onForeground(): void {
    hilog.info(0x0001, TAG, 'EntryAbility onForeground');
  }

  onBackground(): void {
    hilog.info(0x0001, TAG, 'EntryAbility onBackground');
  }
}
