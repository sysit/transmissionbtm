// transmissionbtm — FileTreePage (torrent file browser)
//
// Displays a recursive file/directory tree for a single torrent.
// Allows toggling which files to download.
// Rendered inline from DownloadsPage when the user taps "Files" on a torrent.

import { taskpool } from '@kit.ArkTS';
import { BusinessError } from '@kit.BasicServicesKit';
import { CLICK_EFFECT, Colors, FontSize, Spacing, Radius } from '../utils/constants';
import { errText } from '../utils/errors';
import { TorrentFile, RawFileEntry } from '../models/TorrentFile';
import { TorrentDir } from '../models/TorrentDir';
import { FileTreeModel } from '../models/FileTreeModel';
import { FileTreeView } from '../components/torrent/FileTreeView';
import { TransmissionSession } from '../models/TransmissionSession';
import { NativeBridge } from '../bridge/NativeBridge';
import { formatSize } from '../utils/format';
import { hilog } from '@kit.PerformanceAnalysisKit';

const TAG = 'FileTreePage';

/** Worker → UI payload for the file tree (JSON, see loadFileRows). */
interface FileLoadEnvelope {
  entries: RawFileEntry[];
  error: string;
}

/**
 * D3: listing a torrent's files is 1 + N synchronous native calls, each one a
 * semaphore hop onto the engine thread — a multi-thousand-file torrent froze
 * the UI. Run them in a taskpool worker. The worker has an isolated JS heap
 * (the NativeBridge session map is unreachable there), so the main thread
 * passes the BigInt tr_session* pointer and the worker calls the stateless
 * *ByPtr methods. Errors are caught INSIDE the worker and returned in the
 * envelope: an Error crossing the taskpool boundary arrives with its message
 * stripped, which would hide why the tree failed to load.
 */
@Concurrent
function loadFileRows(ptr: BigInt, torrentId: number): string {
  const env: FileLoadEnvelope = { entries: [], error: '' };
  try {
    const names: string[] = NativeBridge.torrentListFilesByPtr(ptr, torrentId);
    for (let i = 0; i < names.length; i++) {
      // listTorrentFiles returns names only; the per-file stat read is the
      // remaining N calls (size / bytesCompleted / wanted / priority).
      const entry: RawFileEntry = {
        index: i, name: names[i], size: 0, wanted: true, priority: 0,
      };
      const file: TorrentFile = TorrentFile.fromNative(entry);
      file.applyFileStat(NativeBridge.torrentGetFileStatByPtr(ptr, torrentId, i));
      entry.size = file.size;
      entry.bytesCompleted = file.bytesCompleted;
      entry.wanted = file.wanted;
      entry.priority = file.priority;
      env.entries.push(entry);
    }
  } catch (err) {
    const be = err as BusinessError;
    env.error = typeof be.message === 'string' && be.message.length > 0
      ? be.message : String(err);
  }
  return JSON.stringify(env);
}

@Component
export struct FileTreePage {
  @Prop torrentId: number = 0;
  @Prop sessionId: number = 0;
  @Prop torrentName: string = '';
  onBack?: () => void;
  @State root: TorrentDir = new TorrentDir();
  @State selectedFiles: boolean[] = [];
  @State isLoading: boolean = true;
  @State totalSize: number = 0;
  @State fileCount: number = 0;
  private session: TransmissionSession = new TransmissionSession();

  aboutToAppear(): void {
    this.loadFiles();
  }

  private async loadFiles(): Promise<void> {
    if (this.sessionId <= 0 || this.torrentId <= 0) {
      this.isLoading = false;
      return;
    }
    try {
      // D13: bind the borrowed handle through attach() — the facade's id is
      // read-only, so a page cannot impersonate start()/stop() by assignment.
      this.session.attach(this.sessionId);
      const ptr: BigInt = NativeBridge.getInstance().getSessionPtr(this.sessionId);
      // D3: list + N stat reads happen on a worker thread, never here.
      const text: string = await taskpool.execute(
        loadFileRows, ptr, this.torrentId) as string;
      const env: FileLoadEnvelope = JSON.parse(text) as FileLoadEnvelope;
      if (env.error.length > 0) {
        hilog.error(0x0001, TAG,
          'Failed to load torrent files: %{private}s', env.error);
      } else if (env.entries.length > 0) {
        const files: TorrentFile[] =
          env.entries.map((e: RawFileEntry): TorrentFile => TorrentFile.fromNative(e));
        this.root = FileTreeModel.buildTree(files);

        // Build selectedFiles array from file wanted states.
        // IMPORTANT: index is the FILE NUMBER (file.index), NOT tree order —
        // native torrentSetFileWanted(files) and FileTreeView both read by
        // file number, so traversal-order indexing would misalign them.
        const totalFiles = this.countTotalFiles(this.root);
        const selected: boolean[] = new Array<boolean>(totalFiles).fill(true);
        this.applyWantedStates(this.root, selected);
        this.selectedFiles = selected;

        this.totalSize = this.root.totalSize;
        this.fileCount = totalFiles;
      }
    } catch (err) {
      hilog.error(0x0001, TAG,
        'Failed to load torrent files: %{private}s', errText(err));
    }
    this.isLoading = false;
  }

  /** Apply a per-file selection (DnD) to the live torrent via the session. */
  private onFileWanted(files: boolean[]): void {
    try {
      this.session.setFileWanted(this.torrentId, files);
    } catch (err) {
      hilog.error(0x0001, TAG,
        'Failed to apply file selection: %{private}s', errText(err));
    }
  }

  private countTotalFiles(dir: TorrentDir): number {
    let count = dir.files.length;
    for (const child of dir.children) {
      count += this.countTotalFiles(child);
    }
    return count;
  }

  private applyWantedStates(dir: TorrentDir, result: boolean[]): void {
    for (const file of dir.files) {
      if (file.index >= 0 && file.index < result.length) {
        result[file.index] = file.wanted;
      }
    }
    for (const child of dir.children) {
      this.applyWantedStates(child, result);
    }
  }

  build() {
    Column() {
      this.buildHeader();
      this.buildSummaryBar();
      this.buildContent();
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Colors.BG);
  }

  @Builder
  buildHeader() {
    Row() {
      // Back button
      Text('←')
        .fontSize(FontSize.HEADLINE)
        .fontColor(Colors.DOWNLOAD)
        .padding({ right: Spacing.MD })
        .clickEffect(CLICK_EFFECT).onClick(() => {
          this.onBack?.();
        });

      // Torrent name
      Text(this.torrentName || $r('app.string.filetree_title'))
        .fontSize(FontSize.TITLE)
        .fontWeight(FontWeight.Bold)
        .fontColor(Colors.TEXT)
        .layoutWeight(1)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis });
    }
    .width('100%')
    .padding({
      left: Spacing.LG,
      right: Spacing.LG,
      top: Spacing.LG,
      bottom: Spacing.SM,
    });
  }

  @Builder
  buildSummaryBar() {
    Row() {
      Text($r('app.string.filetree_file_count', this.fileCount))
        .fontSize(FontSize.SMALL)
        .fontColor(Colors.TEXT_TERTIARY)
        .fontFamily('JetBrains Mono');

      Text(' · ')
        .fontSize(FontSize.SMALL)
        .fontColor(Colors.TEXT_TERTIARY);

      Text(formatSize(this.totalSize))
        .fontSize(FontSize.SMALL)
        .fontColor(Colors.TEXT_TERTIARY)
        .fontFamily('JetBrains Mono');
    }
    .width('100%')
    .padding({
      left: Spacing.LG,
      right: Spacing.LG,
      bottom: Spacing.MD,
    });
  }

  @Builder
  buildContent() {
    if (this.isLoading) {
      Column() {
        LoadingProgress()
          .width(32)
          .height(32)
          .color(Colors.DOWNLOAD);
        Text($r('app.string.filetree_loading'))
          .fontSize(FontSize.CAPTION)
          .fontColor(Colors.TEXT_SECONDARY)
          .margin({ top: Spacing.MD });
      }
      .width('100%')
      .layoutWeight(1)
      .justifyContent(FlexAlign.Center);
    } else if (this.fileCount === 0) {
      Column() {
        Text('📂')
          .fontSize(48)
          .margin({ bottom: Spacing.LG });
        Text($r('app.string.filetree_empty'))
          .fontSize(FontSize.BODY)
          .fontColor(Colors.TEXT_SECONDARY);
      }
      .width('100%')
      .layoutWeight(1)
      .justifyContent(FlexAlign.Center);
    } else {
      Scroll() {
        FileTreeView({
          root: this.root,
          selectedFiles: $selectedFiles,
          onToggleFile: (files: boolean[]) => { this.onFileWanted(files); },
        })
          // A tree shorter than the viewport gets centered by Scroll (ArkUI
          // default), floating a one-row tree mid-page. Filling the viewport
          // restores the column's natural top alignment.
          .constraintSize({ minHeight: '100%' })
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off)
      .padding({ left: Spacing.MD, right: Spacing.MD, top: Spacing.LG });
    }
  }
}
