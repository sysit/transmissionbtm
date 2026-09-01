// transmissionbtm — TorrentCard (torrent list item with expandable detail)
//
// Renamed from TorrentDetailView. Shows a compact torrent card with
// progress bar, stats, and expandable action section.

import { TorrentStatus } from '../../models/TorrentInfo';
import { TorrentVM } from './TorrentVM';
import { ProgressBar } from '../ui/ProgressBar';
import { StatChip } from '../ui/StatChip';
import { formatSpeed, formatSize, formatETA } from '../../utils/format';
import { statusResource } from '../../utils/i18n';
import { Colors, Radius, Spacing, FontSize } from '../../utils/constants';

@Component
export struct TorrentCard {
  @ObjectLink vm: TorrentVM;
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
      Text(this.vm.torrent.name)
        .fontSize(FontSize.BODY)
        .fontWeight(FontWeight.Medium)
        .fontColor(Colors.TEXT)
        .layoutWeight(1)
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis });

      // Status badge
      Text(statusResource(this.vm.torrent.getStatusString()))
        .fontSize(FontSize.SMALL)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.vm.torrent.getStatusColor())
        .padding({ left: Spacing.SM, right: Spacing.SM, top: 2, bottom: 4 })
        .borderRadius(Radius.SM)
        .border({ width: 1, color: this.vm.torrent.getStatusColor() })
        .opacity(0.7);
    }
    .width('100%')
    .margin({ bottom: Spacing.MD });
  }

  @Builder
  buildProgressSection() {
    if (this.vm.torrent.status === TorrentStatus.DOWNLOAD ||
      this.vm.torrent.status === TorrentStatus.SEED ||
      this.vm.torrent.status === TorrentStatus.CHECK ||
      this.vm.torrent.isFinished()) {
      ProgressBar({
        progress: this.vm.torrent.percentComplete,
        color: this.vm.torrent.getStatusColor(),
        barHeight: 4,
        showLabel: true,
        labelSize: FontSize.SMALL,
      });
    }

    // Error message
    if (this.vm.torrent.hasError()) {
      Text(this.vm.torrent.errorString || $r('app.string.torrent_error_unknown'))
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
      if (this.vm.torrent.isDownloading()) {
        StatChip({
          label: $r('app.string.torrent_stat_download'),
          value: formatSpeed(this.vm.torrent.rateDownload),
          color: Colors.DOWNLOAD,
        });
        StatChip({
          label: $r('app.string.torrent_stat_eta'),
          value: formatETA(this.vm.torrent.eta),
          color: Colors.TEXT,
        });
      }
      if (this.vm.torrent.isSeeding()) {
        StatChip({
          label: $r('app.string.torrent_stat_upload'),
          value: formatSpeed(this.vm.torrent.rateUpload),
          color: Colors.SEED,
        });
      }
      StatChip({
        label: $r('app.string.torrent_stat_size'),
        value: formatSize(this.vm.torrent.totalSize),
        color: Colors.TEXT,
      });
      StatChip({
        label: $r('app.string.torrent_stat_peers'),
        value: `${this.vm.torrent.peersConnected}`,
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
          Text($r('app.string.torrent_downloaded'))
            .fontSize(FontSize.SMALL)
            .fontColor(Colors.TEXT_TERTIARY);
          Text(formatSize(this.vm.torrent.downloadedEver))
            .fontSize(FontSize.CAPTION)
            .fontColor(Colors.TEXT)
            .fontFamily('JetBrains Mono')
            .margin({ top: 2 });
        }

        Column() {
          Text($r('app.string.torrent_uploaded'))
            .fontSize(FontSize.SMALL)
            .fontColor(Colors.TEXT_TERTIARY);
          Text(formatSize(this.vm.torrent.uploadedEver))
            .fontSize(FontSize.CAPTION)
            .fontColor(Colors.TEXT)
            .fontFamily('JetBrains Mono')
            .margin({ top: 2 });
        }

        Column() {
          Text($r('app.string.torrent_progress'))
            .fontSize(FontSize.SMALL)
            .fontColor(Colors.TEXT_TERTIARY);
          Text(`${Math.round(this.vm.torrent.percentComplete * 100)}%`)
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
        if (this.vm.torrent.isStopped()) {
          this.ActionButton('▶', $r('app.string.torrent_action_resume'), this.onResume);
        } else {
          this.ActionButton('⏸', $r('app.string.torrent_action_pause'), this.onPause);
        }
        this.ActionButton('⟳', $r('app.string.torrent_action_reannounce'), this.onReannounce);
        this.ActionButton('✓', $r('app.string.torrent_action_verify'), this.onVerify);
        this.ActionButton('📁', $r('app.string.torrent_action_files'), this.onShowFiles);
        this.ActionButton('✕', $r('app.string.torrent_action_remove'), this.onRemove);
      }
      .width('100%')
      .justifyContent(FlexAlign.SpaceEvenly);
    }
    .width('100%');
  }

  @Builder
  ActionButton(icon: string, label: ResourceStr, action?: () => void) {
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
