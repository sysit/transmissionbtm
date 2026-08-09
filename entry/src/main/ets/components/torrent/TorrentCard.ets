// transmissionhm — TorrentCard (torrent list item with expandable detail)
//
// Renamed from TorrentDetailView. Shows a compact torrent card with
// progress bar, stats, and expandable action section.

import { TorrentInfo, TorrentStatus } from '../../models/TorrentInfo';
import { ProgressBar } from '../ui/ProgressBar';
import { StatChip } from '../ui/StatChip';
import { formatSpeed, formatSize, formatETA } from '../../utils/format';
import { Colors, Radius, Spacing, FontSize } from '../../utils/constants';

@Component
export struct TorrentCard {
  @Prop torrent: TorrentInfo;
  @Prop sessionId: number = 0;
  @State isExpanded: boolean = false;
  onPause?: () => void;
  onResume?: () => void;
  onRemove?: () => void;
  onVerify?: () => void;
  onReannounce?: () => void;
  onShowFiles?: () => void;

  build() {
    Column() {
      this.buildHeader();
      this.buildProgressSection();
      this.buildStatsRow();
      if (this.isExpanded) {
        this.buildDetailSection();
      }
    }
    .width('100%')
    .padding(Spacing.LG)
    .borderRadius(Radius.LG)
    .backgroundColor(Colors.SURFACE)
    .onClick(() => { this.isExpanded = !this.isExpanded; });
  }

  @Builder
  buildHeader() {
    Row() {
      // Torrent name
      Text(this.torrent.name)
        .fontSize(FontSize.BODY)
        .fontWeight(FontWeight.Medium)
        .fontColor(Colors.TEXT)
        .layoutWeight(1)
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis });

      // Status badge
      Text(this.torrent.getStatusString())
        .fontSize(FontSize.SMALL)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.torrent.getStatusColor())
        .padding({ left: Spacing.SM, right: Spacing.SM, top: 2, bottom: 4 })
        .borderRadius(Radius.SM)
        .border({ width: 1, color: this.torrent.getStatusColor() })
        .opacity(0.7);
    }
    .width('100%')
    .margin({ bottom: Spacing.MD });
  }

  @Builder
  buildProgressSection() {
    if (this.torrent.status === TorrentStatus.DOWNLOAD ||
      this.torrent.status === TorrentStatus.SEED ||
      this.torrent.status === TorrentStatus.CHECK ||
      this.torrent.isFinished()) {
      ProgressBar({
        progress: this.torrent.percentComplete,
        color: this.torrent.getStatusColor(),
        barHeight: 4,
        showLabel: true,
        labelSize: FontSize.SMALL,
      });
    }

    // Error message
    if (this.torrent.hasError()) {
      Text(this.torrent.errorString || 'Unknown error')
        .fontSize(FontSize.SMALL)
        .fontColor(Colors.ERROR)
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .margin({ top: Spacing.SM });
    }
  }

  @Builder
  buildStatsRow() {
    Row() {
      if (this.torrent.isDownloading()) {
        StatChip({
          label: '⬇ Download',
          value: formatSpeed(this.torrent.rateDownload),
          color: Colors.DOWNLOAD,
        });
        StatChip({
          label: 'ETA',
          value: formatETA(this.torrent.eta),
          color: Colors.TEXT,
        });
      }
      if (this.torrent.isSeeding()) {
        StatChip({
          label: '⬆ Upload',
          value: formatSpeed(this.torrent.rateUpload),
          color: Colors.SEED,
        });
      }
      StatChip({
        label: 'Size',
        value: formatSize(this.torrent.totalSize),
        color: Colors.TEXT,
      });
      StatChip({
        label: 'Peers',
        value: `${this.torrent.peersConnected}`,
        color: Colors.TEXT,
      });

      // Expand indicator
      Text(this.isExpanded ? '▴' : '▾')
        .fontSize(FontSize.CAPTION)
        .fontColor(Colors.TEXT_TERTIARY)
        .margin({ left: Spacing.SM });
    }
    .width('100%')
    .justifyContent(FlexAlign.SpaceBetween)
    .margin({ top: Spacing.MD });
  }

  @Builder
  buildDetailSection() {
    Column() {
      Divider()
        .color(Colors.DIVIDER)
        .margin({ top: Spacing.MD, bottom: Spacing.MD });

      // Additional stats when expanded
      Row() {
        Column() {
          Text('Downloaded')
            .fontSize(FontSize.SMALL)
            .fontColor(Colors.TEXT_TERTIARY);
          Text(formatSize(this.torrent.downloadedEver))
            .fontSize(FontSize.CAPTION)
            .fontColor(Colors.TEXT)
            .fontFamily('JetBrains Mono')
            .margin({ top: 2 });
        }

        Column() {
          Text('Uploaded')
            .fontSize(FontSize.SMALL)
            .fontColor(Colors.TEXT_TERTIARY);
          Text(formatSize(this.torrent.uploadedEver))
            .fontSize(FontSize.CAPTION)
            .fontColor(Colors.TEXT)
            .fontFamily('JetBrains Mono')
            .margin({ top: 2 });
        }

        Column() {
          Text('Progress')
            .fontSize(FontSize.SMALL)
            .fontColor(Colors.TEXT_TERTIARY);
          Text(`${Math.round(this.torrent.percentComplete * 100)}%`)
            .fontSize(FontSize.CAPTION)
            .fontColor(Colors.TEXT)
            .fontFamily('JetBrains Mono')
            .margin({ top: 2 });
        }
      }
      .width('100%')
      .justifyContent(FlexAlign.SpaceBetween)
      .margin({ bottom: Spacing.MD });

      // Action buttons
      Row() {
        if (this.torrent.isStopped()) {
          this.ActionButton('▶', 'Resume', this.onResume);
        } else {
          this.ActionButton('⏸', 'Pause', this.onPause);
        }
        this.ActionButton('⟳', 'Reannounce', this.onReannounce);
        this.ActionButton('✓', 'Verify', this.onVerify);
        this.ActionButton('📁', 'Files', this.onShowFiles);
        this.ActionButton('✕', 'Remove', this.onRemove);
      }
      .width('100%')
      .justifyContent(FlexAlign.SpaceEvenly);
    }
    .width('100%');
  }

  @Builder
  ActionButton(icon: string, label: string, action?: () => void) {
    Column() {
      Text(icon)
        .fontSize(16)
        .fontColor(Colors.TEXT)
        .width(40)
        .height(36)
        .textAlign(TextAlign.Center)
        .borderRadius(Radius.SM)
        .backgroundColor(Colors.ELEVATED);
      Text(label)
        .fontSize(10)
        .fontColor(Colors.TEXT_SECONDARY)
        .margin({ top: 4 });
    }
    .alignItems(HorizontalAlign.Center)
    .onClick(() => {
      if (action) {
        action();
      }
    });
  }
}
