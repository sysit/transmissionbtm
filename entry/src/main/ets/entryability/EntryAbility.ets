// transmissionbtm — App entry point (M5)
// Initializes preferences and handles external intents (magnet links,
// .torrent files). The background TransmissionService was removed in M7
// (HarmonyOS NEXT service = system-app-only) — the session runs in-process.

import { UIAbility, Want, AbilityConstant } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { PreferencesManager, PrefKeys } from '../models/Preferences';
import { HukProxyCipher } from '../security/HukProxyCipher';

const TAG = 'transmissionbtm';

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
        'Preferences init failed: %{private}s', String(err));
    }

    // Inject the HUKS proxy-password cipher + run a startup self-test.
    // Fire-and-forget: the cipher is injected synchronously on the first tick,
    // so it is in place before any page reads proxy_password. selfTest() proves
    // the AES-256-GCM round-trip on THIS device via a hilog OK/FAIL line.
    this.setupProxyCipher();

    // Parse external intent if launched via magnet/file URI
    this.pendingTorrentIntent = this.parseIntent(want);
  }

  /**
   * Install the on-device HUKS cipher for the proxy password, then log whether
   * a real AES-256-GCM encrypt→decrypt round-trip succeeds. This substitutes
   * for the SIGABRT-blocked aa test runner: `aa start` + hilog 'HUKS selfTest OK'
   * is the proof the GCM tag/IV/alias contract works on this device.
   */
  private async setupProxyCipher(): Promise<void> {
    try {
      const cipher = new HukProxyCipher();
      PreferencesManager.getInstance().setPasswordCipher(cipher);
      const ok = await cipher.selfTest();
      hilog.info(0x0001, TAG, 'HUKS selfTest %{public}s', ok ? 'OK' : 'FAIL');
    } catch (err) {
      hilog.error(0x0001, TAG,
        'HUKS cipher setup failed: %{private}s', String(err));
    }
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
        'parseIntent failed: %{private}s', String(err));
    }

    return { kind: 'unknown', uri: '' };
  }

  /**
   * Apply the user-selected app language so `$r('app.string.*')` resolves to the
   * pinned locale. Reads app_language ('system' follows the device locale, so no
   * override) and calls ApplicationContext.setLanguage() with a BCP-47 tag.
   * 'zh-CN' is stored by the Settings selector; setLanguage expects 'zh-Hans-CN'
   * (script-annotated), so map it here. Main-thread-only, run before loadContent.
   */
  private async applyAppLanguage(): Promise<void> {
    try {
      await PreferencesManager.getInstance().waitReady();
      const lang = await PreferencesManager.getInstance()
        .getString(PrefKeys.APP_LANGUAGE, 'system');
      const tag = lang === 'zh-CN' ? 'zh-Hans-CN'
        : lang === 'en-US' ? 'en-US' : null;
      if (!tag) { return; }
      this.context.getApplicationContext().setLanguage(tag);
      hilog.info(0x0001, TAG, 'App language override: %{public}s', tag);
    } catch (err) {
      hilog.error(0x0001, TAG,
        'applyAppLanguage failed: %{private}s', String(err));
    }
  }

  onDestroy(): void {
    hilog.info(0x0001, TAG, 'EntryAbility onDestroy');
  }

  async onWindowStageCreate(windowStage: window.WindowStage): Promise<void> {
    hilog.info(0x0001, TAG, 'EntryAbility onWindowStageCreate');

    // Pin the app language (Phase E) BEFORE the first frame so `$r` resolves to
    // the user-chosen locale. A change made in Settings takes effect on next
    // launch because this runs on every fresh onCreate/onWindowStageCreate.
    await this.applyAppLanguage();

    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        hilog.error(0x0001, TAG,
          'Failed to load the content. Cause: %{private}s', JSON.stringify(err));
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
