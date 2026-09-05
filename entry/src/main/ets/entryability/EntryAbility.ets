// transmissionbtm — App entry point (M5)
// Initializes preferences and handles external intents (magnet links,
// .torrent files). The background TransmissionService was removed in M7
// (HarmonyOS NEXT service = system-app-only) — the session runs in-process.

import { UIAbility, Want, AbilityConstant } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { fileIo as fs } from '@kit.CoreFileKit';
import { PreferencesManager, PrefKeys } from '../models/Preferences';
import { HukProxyCipher } from '../security/HukProxyCipher';
import { Colors } from '../utils/constants';
import { NativeBridge } from '../bridge/NativeBridge';

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

  /**
   * Extract the bundled web client (resources/rawfile/web — the transmission-web-
   * control-ng React SPA's dist) into <filesDir>/public_html, then point the engine at
   * it via NativeBridge.sessionSetWebClientDir (sets TRANSMISSION_WEB_HOME). Must run
   * before the first sessionStart: tr_getWebClientDir caches the dir on first use
   * (during the RPC server's construction during tr_sessionInit), so the env var has to
   * be set before any session init. Re-extracted every cold start so a stale copy from
   * an older app build can't be served after an in-place upgrade. Never fatal: the web
   * UI is a nice-to-have, so a failure only disables the browser client.
   */
  private async setupWebClientDir(): Promise<void> {
    try {
      const webDir = `${this.context.filesDir}/public_html`;
      // Always re-extract every cold start. A prior build (e.g. the official client
      // from an older app version) may have left a stale/partial public_html on disk
      // after an in-place upgrade, so an "index.html already exists" check would skip
      // the copy and serve the stale UI. No single existence check proves the dist is
      // complete (index.html + hashed assets/*.js both matter), so re-copy the whole
      // tree each launch — ~2.9MB / 367 files, cheap, and guarantees the served web
      // client always matches the bundled dist.
      await this.extractRawfileTree('web', webDir);
      NativeBridge.getInstance().sessionSetWebClientDir(webDir);
      hilog.info(0x0001, TAG, 'Web client dir: %{public}s', webDir);
    } catch (err) {
      hilog.error(0x0001, TAG,
        'Web client extraction failed (web UI unavailable): %{private}s', String(err));
    }
  }

  /** Copy every file under resources/rawfile/<relDir> into <dstDir>, preserving the tree
   *  (subdirectories included). getRawFileContent succeeds for a file and throws for a
   *  directory, so a successful content read means "file" (copy it) and a throw means
   *  "directory" (recurse). A directory that turns out to be unlistable just propagates
   *  up to setupWebClientDir's catch — no infinite recursion. */
  private async extractRawfileTree(relDir: string, dstDir: string): Promise<void> {
    const rm = this.context.resourceManager;
    const entries = await rm.getRawFileList(relDir);
    for (let i = 0; i < entries.length; i++) {
      const name = entries[i];
      const relChild = `${relDir}/${name}`;
      const absChild = `${dstDir}/${name}`;
      try {
        const bytes = await rm.getRawFileContent(relChild);
        this.mkdirRecursive(dstDir);
        const file = fs.openSync(absChild,
          fs.OpenMode.CREATE | fs.OpenMode.TRUNC | fs.OpenMode.WRITE_ONLY);
        try {
          // getRawFileContent returns a Uint8Array that may back a larger buffer;
          // copy the exact byte range into a fresh ArrayBuffer for writeSync.
          fs.writeSync(file.fd, bytes.buffer.slice(
            bytes.byteOffset, bytes.byteOffset + bytes.byteLength));
        } finally {
          fs.closeSync(file.fd);
        }
      } catch (e) {
        // Directory (or an unreadable path) — recurse.
        await this.extractRawfileTree(relChild, absChild);
      }
    }
  }

  /** Create a nested directory chain at a physical path. fs.mkdirSync can throw
   *  EEXIST on an existing dir, so create level-by-level and swallow the race.
   *  Mirrors DownloadsPage.mkdirRecursive. */
  private mkdirRecursive(dir: string): void {
    if (!dir || fs.accessSync(dir)) {
      return;
    }
    const segments = dir.split('/').filter((s: string) => s.length > 0);
    let cur = '';
    for (let i = 0; i < segments.length; i++) {
      cur = `${cur}/${segments[i]}`;
      try {
        if (!fs.accessSync(cur)) {
          fs.mkdirSync(cur);
        }
      } catch (e) {
        // EEXIST from a concurrent creator, or a reserved/read-only base segment.
      }
    }
  }

  async onWindowStageCreate(windowStage: window.WindowStage): Promise<void> {
    hilog.info(0x0001, TAG, 'EntryAbility onWindowStageCreate');

    // Pin the app language (Phase E) BEFORE the first frame so `$r` resolves to
    // the user-chosen locale. A change made in Settings takes effect on next
    // launch because this runs on every fresh onCreate/onWindowStageCreate.
    await this.applyAppLanguage();

    // Extract the bundled web client + set TRANSMISSION_WEB_HOME before loadContent
    // so it is in place before any page can trigger the first sessionStart (and thus
    // before the RPC server's one-shot web-dir cache resolves).
    await this.setupWebClientDir();

    // Pin the system status/navigation bars to the app's dark theme. In a
    // non-full-screen window the system renders these bars and follows the
    // SYSTEM theme, so an always-dark app would show a light bar band + dark
    // icons on light-theme devices (the review nit "状态栏对比度/适配"). Color
    // them to match Colors.BG with light icons — content is already auto-inset
    // below the status bar, so no avoid-area underlap work is needed here.
    // Applied AFTER loadContent so Navigation's own page-level SystemBar init
    // (which clears these) can't stomp our values.
    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        hilog.error(0x0001, TAG,
          'Failed to load the content. Cause: %{private}s', JSON.stringify(err));
        return;
      }
      hilog.info(0x0001, TAG, 'Succeeded in loading the content.');
      this.applyStatusBarTheme(windowStage);
    });
  }

  /**
   * Pin the system status/navigation bars to the app's dark theme. The app's
   * palette is always dark (Colors.BG), but a non-full-screen window renders the
   * status/nav bars via the SYSTEM theme — on a light-theme device that yields a
   * light band + dark icons over the dark app, a HarmonyOS UX-compliance nit.
   * Setting the bar colors to Colors.BG with light content keeps it seamless on
   * every device theme. Content is already auto-inset below the status bar, so
   * no avoid-area underlap handling is required here.
   */
  private async applyStatusBarTheme(windowStage: window.WindowStage): Promise<void> {
    try {
      const win = windowStage.getMainWindowSync();
      await win.setWindowSystemBarProperties({
        statusBarColor: Colors.BG,          // status band matches app surface
        statusBarContentColor: Colors.TEXT, // light icons on dark
        navigationBarColor: Colors.BG,
        navigationBarContentColor: Colors.TEXT,
      });
      hilog.info(0x0001, TAG, 'Status/navigation bar theme applied (dark).');
    } catch (err) {
      hilog.error(0x0001, TAG,
        'setWindowSystemBarProperties failed: %{public}s', String(err));
    }
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
