// transmissionbtm — AddTorrentPage (add torrent via file, magnet URI, or URL)
//
// Three-tab interface: file picker for .torrent files, text input for magnet
// URIs / info-hashes, and a URL field for downloading .torrent files (D2).
// Validates inputs before passing to TransmissionSession.addTorrent().

import { hilog } from '@kit.PerformanceAnalysisKit';
import { NativeBridge } from '../bridge/NativeBridge';
import { TorrentAddResult } from '../utils/constants';
import { Colors, FontSize, Spacing, Radius } from '../utils/constants';
import { picker, fileIo as fs } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';
import { taskpool } from '@kit.ArkTS';
import { FilePreview } from '../components/add/FilePreview';
import { TorrentStatusBanner } from '../components/add/TorrentStatusBanner';

const TAG = 'AddTorrentPage';

/** Tab identifiers for the add torrent page. */
enum AddTab {
  FILE = 0,
  MAGNET = 1,
  URL = 2,
}

/**
 * D2: run the synchronous native curlDownload off the UI thread via taskpool.
 * libcurl's curl_easy_perform can block for up to `timeout` seconds; running
 * it on the ArkTS main thread would freeze the UI while fetching a URL.
 */
@Concurrent
function runCurlDownload(url: string, dstPath: string, timeout: number): void {
  NativeBridge.getInstance().curlDownload(url, dstPath, timeout);
}

/**
 * Offload the blocking native torrentAdd (file read + bencode parse +
 * tr_torrentNew/tr_torrentStart disk I/O) to a taskpool worker so the UI thread
 * isn't frozen. A worker has an isolated JS heap, so it cannot resolve the
 * session via the NativeBridge singleton's sessionMap — pass the BigInt
 * tr_session* pointer in and call the stateless NativeBridge.torrentAddByPtr.
 * Returns the native result code (0=OK, 1=PARSE_ERR, 2=DUPLICATE, 3=OK_DELETE).
 */
@Concurrent
function concurrentTorrentAdd(ptr: BigInt, path: string, downloadDir: string,
    deleteFlag: boolean, paused: boolean): number {
  return NativeBridge.torrentAddByPtr(ptr, path, downloadDir, deleteFlag, paused);
}

@Component
export struct AddTorrentPage {
  @Prop sessionId: number = 0;
  @Prop downloadDir: string = '/storage/downloads';
  @State currentTab: AddTab = AddTab.FILE;
  @State filePath: string = '';
  @State magnetUri: string = '';
  @State urlInput: string = '';
  @State addPaused: boolean = false;
  @State isAdding: boolean = false;
  @State statusMessage: string = '';
  @State statusIsError: boolean = false;
  onTorrentAdded?: () => void;
  onCancel?: () => void;

  build() {
    Column() {
      this.buildHeader();
      this.buildTabBar();
      this.buildTabContent();
      TorrentStatusBanner({ message: this.statusMessage, isError: this.statusIsError });
      this.buildActionButtons();
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Colors.BG);
  }

  // ═══════════════════════════════════════════════════════════════════
  // Header
  // ═══════════════════════════════════════════════════════════════════

  @Builder
  buildHeader() {
    Row() {
      Text('Add Torrent')
        .fontSize(FontSize.TITLE)
        .fontWeight(FontWeight.Bold)
        .fontColor(Colors.TEXT)
        .layoutWeight(1);

      Text('✕')
        .fontSize(FontSize.HEADLINE)
        .fontColor(Colors.TEXT_SECONDARY)
        .padding(Spacing.SM)
        .onClick(() => {
          this.onCancel?.();
        });
    }
    .width('100%')
    .padding({ left: Spacing.LG, right: Spacing.LG, top: Spacing.LG, bottom: Spacing.MD });
  }

  // ═══════════════════════════════════════════════════════════════════
  // Tab bar
  // ═══════════════════════════════════════════════════════════════════

  @Builder
  buildTabBar() {
    Row() {
      this.TabButton('📄 File', AddTab.FILE);
      this.TabButton('🧲 Magnet', AddTab.MAGNET);
      this.TabButton('🔗 URL', AddTab.URL);
    }
    .width('100%')
    .padding({ left: Spacing.LG, right: Spacing.LG });
  }

  @Builder
  TabButton(label: string, tab: AddTab) {
    Column() {
      Text(label)
        .fontSize(FontSize.BODY)
        .fontWeight(this.currentTab === tab ? FontWeight.Medium : FontWeight.Normal)
        .fontColor(this.currentTab === tab ? Colors.TEXT : Colors.TEXT_SECONDARY)
        .padding({ left: Spacing.LG, right: Spacing.LG, top: Spacing.MD, bottom: Spacing.SM });

      if (this.currentTab === tab) {
        Row()
          .width(24)
          .height(3)
          .borderRadius(2)
          .backgroundColor(Colors.DOWNLOAD);
      }
    }
    .alignItems(HorizontalAlign.Center)
    .onClick(() => { this.currentTab = tab; });
  }

  // ═══════════════════════════════════════════════════════════════════
  // Tab content
  // ═══════════════════════════════════════════════════════════════════

  @Builder
  buildTabContent() {
    Column() {
      if (this.currentTab === AddTab.FILE) {
        this.buildFileTab();
      } else if (this.currentTab === AddTab.MAGNET) {
        this.buildMagnetTab();
      } else {
        this.buildUrlTab();
      }

      // Download directory (shared across all tabs)
      this.buildDirectorySection();
    }
    .layoutWeight(1)
    .width('100%')
    .padding({ left: Spacing.LG, right: Spacing.LG, top: Spacing.LG });
  }

  @Builder
  buildFileTab() {
    Column() {
      Text('Select a .torrent file to add')
        .fontSize(FontSize.CAPTION)
        .fontColor(Colors.TEXT_SECONDARY)
        .width('100%')
        .margin({ bottom: Spacing.MD });

      // File path input
      Row() {
        TextInput({ placeholder: '/path/to/file.torrent', text: this.filePath })
          .fontSize(FontSize.BODY)
          .fontColor(Colors.TEXT)
          .backgroundColor(Colors.SURFACE)
          .borderRadius(Radius.MD)
          .layoutWeight(1)
          .height(48)
          .padding({ left: Spacing.MD, right: Spacing.MD })
          .onChange((value: string) => {
            this.filePath = value;
          });

        Button('Browse')
          .fontSize(FontSize.CAPTION)
          .fontColor('#ffffff')
          .backgroundColor(Colors.DOWNLOAD)
          .borderRadius(Radius.MD)
          .height(48)
          .padding({ left: Spacing.LG, right: Spacing.LG })
          .margin({ left: Spacing.SM })
          .onClick(() => { this.onBrowseFile(); });
      }
      .width('100%')
      .margin({ bottom: Spacing.LG });

      // File type hint
      Row() {
        Text('💡 ')
          .fontSize(FontSize.SMALL);
        Text('Valid file extensions: .torrent')
          .fontSize(FontSize.SMALL)
          .fontColor(Colors.TEXT_TERTIARY);
      }
      .width('100%')
      .margin({ bottom: Spacing.MD });

      // File info preview (when path is set)
      if (this.filePath.length > 0) {
        FilePreview({ path: this.filePath });
      }
    }
    .width('100%');
  }

  @Builder
  buildMagnetTab() {
    Column() {
      Text('Paste a magnet link or info-hash')
        .fontSize(FontSize.CAPTION)
        .fontColor(Colors.TEXT_SECONDARY)
        .width('100%')
        .margin({ bottom: Spacing.MD });

      // D1 (docs/11): native BEP 9 — the magnet is added immediately and
      // libtransmission fetches the metainfo from peers in the background
      // (metadataPercentComplete grows 0→1). No blocking "resolve" step
      // exists anymore, so no spinner here.
      TextArea({
        placeholder: 'magnet:?xt=urn:btih:...',
        text: this.magnetUri,
      })
        .fontSize(FontSize.CAPTION)
        .fontColor(Colors.TEXT)
        .fontFamily('JetBrains Mono')
        .backgroundColor(Colors.SURFACE)
        .borderRadius(Radius.MD)
        .height(120)
        .padding(Spacing.MD)
        .maxLength(2048)
        .onChange((value: string) => {
          this.magnetUri = value;
        });
    }
    .width('100%');
  }

  @Builder
  buildUrlTab() {
    Column() {
      Text('Download a .torrent from a URL')
        .fontSize(FontSize.CAPTION)
        .fontColor(Colors.TEXT_SECONDARY)
        .width('100%')
        .margin({ bottom: Spacing.MD });

      // D2 (docs/11): the URL is fetched to the app cache via curlDownload
      // (NativeBridge), then added through the existing file-based path.
      TextInput({ placeholder: 'https://example.com/file.torrent', text: this.urlInput })
        .fontSize(FontSize.CAPTION)
        .fontColor(Colors.TEXT)
        .backgroundColor(Colors.SURFACE)
        .borderRadius(Radius.MD)
        .height(44)
        .padding({ left: Spacing.MD, right: Spacing.MD })
        .maxLength(2048)
        .onChange((value: string) => {
          this.urlInput = value;
        });
    }
    .width('100%');
  }

  // ═══════════════════════════════════════════════════════════════════
  // Download directory
  // ═══════════════════════════════════════════════════════════════════

  @Builder
  buildDirectorySection() {
    Column() {
      Text('Download Directory')
        .fontSize(FontSize.SMALL)
        .fontColor(Colors.TEXT_TERTIARY)
        .width('100%')
        .margin({ top: Spacing.XL, bottom: Spacing.SM });

      // Read-only: the session always writes into the app sandbox because the
      // native engine needs a real POSIX path and HarmonyOS NEXT grants a phone
      // app no shared-dir write. Use the torrent's "Save to Files" action to
      // publish a completed download into the public Download dir.
      Row() {
        Column() {
          Text(this.downloadDir.length > 0 ? 'App sandbox (system-isolated)' : 'App sandbox')
            .fontSize(FontSize.BODY)
            .fontColor(Colors.TEXT)
            .width('100%');
          Text(this.downloadDir.length > 0 ? this.downloadDir : '(app sandbox)')
            .fontSize(FontSize.CAPTION)
            .fontColor(Colors.TEXT_SECONDARY)
            .width('100%')
            .margin({ top: 4 });
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
        .backgroundColor(Colors.SURFACE)
        .borderRadius(Radius.MD)
        .padding({ left: Spacing.MD, right: Spacing.MD, top: 10, bottom: 10 });
      }
      .width('100%');

      Text('Downloads always go to the app sandbox — HarmonyOS NEXT lets no phone app '
        + 'write the public Download dir, so this path cannot be changed. Publish finished '
        + 'files with the "Save to Files" action on a torrent.')
        .fontSize(FontSize.SMALL)
        .fontColor(Colors.TEXT_TERTIARY)
        .width('100%')
        .margin({ top: Spacing.SM });
    }
    .width('100%')
    .margin({ bottom: Spacing.LG });
  }

  // ═══════════════════════════════════════════════════════════════════
  // Status message
  // ═══════════════════════════════════════════════════════════════════

  // ═══════════════════════════════════════════════════════════════════
  // Action buttons
  // ═══════════════════════════════════════════════════════════════════

  @Builder
  buildActionButtons() {
    Column() {
      // Start paused toggle
      Row() {
        Text('Add in paused state')
          .fontSize(FontSize.CAPTION)
          .fontColor(Colors.TEXT)
          .layoutWeight(1);

        Toggle({ type: ToggleType.Switch, isOn: this.addPaused })
          .selectedColor(Colors.DOWNLOAD)
          .onChange((checked: boolean) => {
            this.addPaused = checked;
          });
      }
      .width('100%')
      .padding({ left: Spacing.LG, right: Spacing.LG, bottom: Spacing.MD });

      // Add button
      Button(this.isAdding ? 'Adding...' : 'Add Torrent')
        .fontSize(FontSize.BODY)
        .fontWeight(FontWeight.Medium)
        .fontColor('#ffffff')
        .width('90%')
        .height(48)
        .borderRadius(Radius.MD)
        .backgroundColor(this.isAdding ? Colors.ELEVATED : Colors.DOWNLOAD)
        .enabled(!this.isAdding)
        .margin({ bottom: Spacing.SM })
        .onClick(() => { this.onAddTorrent(); });

      // Cancel
      Button('Cancel')
        .fontSize(FontSize.BODY)
        .fontColor(Colors.TEXT_SECONDARY)
        .width('90%')
        .height(44)
        .borderRadius(Radius.MD)
        .backgroundColor(Colors.SURFACE)
        .margin({ bottom: Spacing.XXL })
        .onClick(() => {
          this.onCancel?.();
        });
    }
    .width('100%')
    .alignItems(HorizontalAlign.Center);
  }

  // ═══════════════════════════════════════════════════════════════════
  // Actions
  // ═══════════════════════════════════════════════════════════════════

  private async onBrowseFile(): Promise<void> {
    try {
      // Pass the app context to the picker. A no-arg DocumentViewPicker can
      // return URIs that fs.openSync() cannot read back from the app's context
      // ("could not access the selected file" bug), because the read grant is
      // bound to the context that opened the picker. The working publish-folder
      // and Save-to-Files pickers both pass getContext(this) — match them.
      const dp = new picker.DocumentViewPicker(getContext(this) as common.UIAbilityContext);
      const options = new picker.DocumentSelectOptions();
      options.maxSelectNumber = 1;
      options.selectMode = picker.DocumentSelectMode.FILE;
      const uris = await dp.select(options);
      if (uris && uris.length > 0) {
        const uri = uris[0];
        if (uri) {
          this.filePath = this.copyPickerUriToCache(uri);
        }
      }
    } catch (err) {
      // User cancelled or picker not available — keep current path
      hilog.info(0x0001, TAG,
        'File picker dismissed: %{private}s', String(err));
    }
  }

  /**
   * DocumentViewPicker returns a file:// URI (e.g.
   * file://docs/storage/Users/currentUser/Download/x.torrent), but the native
   * libtransmission tr_ctorSetMetainfoFromFile() only opens real POSIX paths —
   * passing the URI raw yields "Invalid torrent file" (PARSE_ERR). Copy the
   * picked file into the app-sandbox cache dir and return that real path so
   * the native side can read it.
   */
  private copyPickerUriToCache(uri: string): string {
    try {
      let baseName = this.extractFileName(uri);
      if (baseName.length === 0) {
        baseName = `torrent_${Date.now()}.torrent`;
      } else if (!baseName.toLowerCase().endsWith('.torrent')) {
        baseName = `${baseName}.torrent`;
      }
      // A picker filename (e.g. a long Chinese M-Team name) can exceed the FS
      // NAME_MAX (255 bytes), making fs.copyFileSync() throw ENAMETOOLONG ("File
      // name too long"). The cache name is throwaway — native parses the true
      // torrent name from the file's metainfo, not this filename — so cap it.
      baseName = this.safeCacheName(baseName);
      const destPath = `${getContext(this).cacheDir}/${baseName}`;
      // DocumentViewPicker returns a file:// URI. copyFileSync() does NOT
      // understand that scheme (it only takes a real path or an fd), so open
      // the URI first to get a readable fd, then copy fd -> cache path.
      const srcFile = fs.openSync(uri, fs.OpenMode.READ_ONLY);
      fs.copyFileSync(srcFile.fd, destPath);
      fs.closeSync(srcFile.fd);
      hilog.info(0x0001, TAG, 'Picked torrent copied to %{private}s', destPath);
      return destPath;
    } catch (err) {
      // Log the raw URI + real error at %{public}s so the add-torrent "could not
      // access the selected file" regression is diagnosable in hilog (the
      // previous %{private}s hid both). Distinguish a remote/cloud URI (which a
      // consumer app can't open as a local file — tell the user to save it to
      // local Download first) from a local file whose open failed for another
      // reason (surface the real error).
      const eStr = String(err);
      hilog.error(0x0001, TAG, 'copyPickerUriToCache FAILED uri=%{public}s err=%{public}s',
        uri, eStr);
      this.showError(uri.startsWith('file://')
        ? `无法访问所选文件: ${eStr}`
        : '所选文件位于远程/云位置，暂不支持直接添加，请先保存到本地 Download');
      return '';
    }
  }

  /**
   * Bound a picker-provided filename to a safe UTF-8 byte length so
   * copyPickerUriToCache() can't throw ENAMETOOLONG ("File name too long") on
   * long Chinese M-Team names. Falls back to a short generated name when > MAX
   * bytes. The .torrent extension is preserved (native expects a .torrent
   * container); the name is a throwaway cache name — native reads the real
   * torrent name from the metainfo.
   */
  private safeCacheName(name: string): string {
    const MAX = 100; // UTF-8 bytes — well under the FS NAME_MAX (255)
    let bytes = 0;
    for (let i = 0; i < name.length; i++) {
      const code = name.charCodeAt(i);
      bytes += code < 0x80 ? 1 : code < 0x800 ? 2 : code < 0x10000 ? 3 : 4;
      if (bytes > MAX) {
        return `torrent_${Date.now()}.torrent`;
      }
    }
    return name;
  }

  private async onAddTorrent(): Promise<void> {
    this.statusMessage = '';
    this.statusIsError = false;

    // Validate input
    const input = this.currentTab === AddTab.FILE ? this.filePath.trim()
      : this.currentTab === AddTab.MAGNET ? this.magnetUri.trim()
      : this.urlInput.trim();

    if (input.length === 0) {
      this.showError(
        this.currentTab === AddTab.FILE ? 'Please select a .torrent file'
          : this.currentTab === AddTab.MAGNET ? 'Please enter a magnet URI'
          : 'Please enter a torrent URL'
      );
      return;
    }

    if (this.currentTab === AddTab.FILE) {
      if (!this.validateTorrentFile(input)) {
        this.showError('File must have a .torrent extension');
        return;
      }
    } else if (this.currentTab === AddTab.MAGNET) {
      if (!this.validateMagnetUri(input)) {
        this.showError('Enter a magnet:?xt=urn:btih:... URI or a 40-hex info-hash');
        return;
      }
    } else if (!this.validateUrl(input)) {
      this.showError('Invalid URL. Must be http(s)://...');
      return;
    }

    this.isAdding = true;
    this.statusMessage = '';

    try {
      // Resolve the live session pointer on the UI thread, then offload the
      // blocking native add (file parse + tr_torrentNew/Start) to a taskpool
      // worker. The worker can't reach the NativeBridge singleton (isolated
      // heap — sessionMap isn't shared), so pass the BigInt ptr in and call the
      // stateless torrentAddByPtr.
      const ptr = NativeBridge.getInstance().getSessionPtr(this.sessionId);

      // D2 (docs/11): URL tab — fetch the .torrent to the app cache first, then
      // add it through the existing file-based path. A download failure shows
      // here instead of a misleading PARSE_ERR from torrentAdd.
      if (this.currentTab === AddTab.URL) {
        await this.addFromUrl(ptr, input);
        return;
      }

      // D1 (docs/11): native torrentAdd accepts magnet URIs and bare 40-hex
      // info-hashes directly (BEP 9 ut_metadata) — no blocking resolve step.
      this.handleAddResult(await taskpool.execute(
        concurrentTorrentAdd, ptr, input, this.downloadDir, false, this.addPaused) as number);
    } catch (e) {
      this.showError(`Error: ${String(e)}`);
      this.isAdding = false;
    }
  }

  /** D2 (docs/11): curlDownload the URL into the app cache, then add the file. */
  private async addFromUrl(ptr: BigInt, url: string): Promise<void> {
    try {
      this.statusMessage = 'Downloading .torrent...';
      this.statusIsError = false;
      const dstPath = `${getContext(this).cacheDir}/url_${Date.now()}.torrent`;
      // Blocking libcurl fetch → taskpool worker, so the UI thread stays live.
      await taskpool.execute(runCurlDownload, url, dstPath, 60);
      this.handleAddResult(await taskpool.execute(
        concurrentTorrentAdd, ptr, dstPath, this.downloadDir, false, this.addPaused) as number);
    } catch (e) {
      this.showError(`Download failed: ${String(e)}`);
      this.isAdding = false;
    }
  }

  /** Shared result handling for the file / magnet / URL add paths. */
  private handleAddResult(tid: number): void {
    // P0 fix (codex review): native torrentAdd returns a result *code*
    // (0=OK, 1=PARSE_ERR, 2=DUPLICATE, 3=OK_DELETE), NOT a torrent ID.
    // The old `tid > 0` check treated every success (code 0) as a failure
    // and showed "Failed to add torrent (code: 0)".
    if (tid === TorrentAddResult.OK || tid === TorrentAddResult.OK_DELETE) {
      this.showSuccess('Torrent added');
      // Notify parent after a brief delay so user sees success
      setTimeout(() => {
        this.isAdding = false;
        this.onTorrentAdded?.();
      }, 600);
    } else if (tid === TorrentAddResult.DUPLICATE) {
      this.showError('This torrent is already in the list');
      this.isAdding = false;
    } else if (tid === TorrentAddResult.PARSE_ERR) {
      this.showError('Failed to parse torrent file. It may be corrupted.');
      this.isAdding = false;
    } else {
      this.showError(`Failed to add torrent (code: ${tid})`);
      this.isAdding = false;
    }
  }

  // ═══════════════════════════════════════════════════════════════════
  // Validation
  // ═══════════════════════════════════════════════════════════════════

  private validateTorrentFile(path: string): boolean {
    return path.length > 8 && path.toLowerCase().endsWith('.torrent');
  }

  private validateMagnetUri(uri: string): boolean {
    // D1 (docs/11): accept a magnet URI or a bare 40-hex info-hash — native
    // torrentAdd converts the bare hash to magnet:?xt=urn:btih:<hash>.
    if (uri.length === 40) {
      let allHex: boolean = true;
      for (let i = 0; i < 40; i++) {
        const code: number = uri.charCodeAt(i);
        const isHex: boolean = (code >= 48 && code <= 57) ||
          (code >= 97 && code <= 102) || (code >= 65 && code <= 70);
        if (!isHex) {
          allHex = false;
          break;
        }
      }
      if (allHex) {
        return true;
      }
    }
    const lower = uri.toLowerCase();
    return lower.startsWith('magnet:') &&
      (lower.includes('xt=urn:btih:') || lower.includes('btih:'));
  }

  /** D2 (docs/11): accept only http(s):// URLs (native curlDownload enforces the same). */
  private validateUrl(url: string): boolean {
    const lower = url.toLowerCase();
    return (lower.startsWith('http://') || lower.startsWith('https://')) && url.length > 8;
  }

  private extractFileName(path: string): string {
    const parts = path.split('/');
    return parts.length > 0 ? parts[parts.length - 1] : path;
  }

  // ═══════════════════════════════════════════════════════════════════
  // Status helpers
  // ═══════════════════════════════════════════════════════════════════

  private showSuccess(message: string): void {
    this.statusMessage = message;
    this.statusIsError = false;
  }

  private showError(message: string): void {
    this.statusMessage = message;
    this.statusIsError = true;
    hilog.error(0x0001, TAG, 'Add torrent failed: %{private}s', message);
  }
}
