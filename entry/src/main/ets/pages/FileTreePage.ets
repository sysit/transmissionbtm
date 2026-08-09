// transmissionhm — FileTreePage (torrent file browser)
//
// Displays a recursive file/directory tree for a single torrent.
// Allows toggling which files to download.
// Rendered inline from DownloadsPage when the user taps "Files" on a torrent.

import { Colors, FontSize, Spacing, Radius } from '../utils/constants';
import { TorrentFile } from '../models/TorrentFile';
import { TorrentDir } from '../models/TorrentDir';
import { FileTreeModel } from '../models/FileTreeModel';
import { FileTreeView } from '../components/torrent/FileTreeView';
import { TransmissionSession } from '../models/TransmissionSession';
import { formatSize } from '../utils/format';
import { hilog } from '@kit.PerformanceAnalysisKit';

const TAG = 'FileTreePage';

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

  aboutToAppear(): void {
    this.loadFiles();
  }

  private loadFiles(): void {
    if (this.sessionId <= 0 || this.torrentId <= 0) {
      this.isLoading = false;
      return;
    }
    try {
      const session = new TransmissionSession();
      session.sessionId = this.sessionId;
      const files: TorrentFile[] = session.listTorrentFiles(this.torrentId);
      if (files && files.length > 0) {
        this.root = FileTreeModel.buildTree(files);

        // Build selectedFiles array from file wanted states
        const totalFiles = this.countTotalFiles(this.root);
        const selected: boolean[] = new Array<boolean>(totalFiles);
        this.collectWantedStates(this.root, selected, 0);
        this.selectedFiles = selected;

        this.totalSize = this.root.totalSize;
        this.fileCount = totalFiles;
      }
    } catch (err) {
      hilog.error(0x0001, TAG,
        'Failed to load torrent files: %{public}s', String(err));
    }
    this.isLoading = false;
  }

  private countTotalFiles(dir: TorrentDir): number {
    let count = dir.files.length;
    for (const child of dir.children) {
      count += this.countTotalFiles(child);
    }
    return count;
  }

  private collectWantedStates(dir: TorrentDir,
                              result: boolean[],
                              offset: number): number {
    let idx = offset;
    for (const file of dir.files) {
      result[idx] = file.wanted;
      idx++;
    }
    for (const child of dir.children) {
      idx = this.collectWantedStates(child, result, idx);
    }
    return idx;
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
        .onClick(() => {
          this.onBack?.();
        });

      // Torrent name
      Text(this.torrentName || 'Files')
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
      Text(`${this.fileCount} files`)
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
        Text('Loading file list...')
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
        Text('No files found')
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
        });
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off)
      .padding({ left: Spacing.MD, right: Spacing.MD });
    }
  }
}
