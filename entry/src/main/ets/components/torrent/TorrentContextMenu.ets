// transmissionbtm — TorrentContextMenu (action sheet for torrent operations)
//
// Provides a modal action sheet with all available torrent operations.
// Actions are conditionally shown based on torrent state (pause vs resume).

import { TorrentInfo } from '../../models/TorrentInfo';
import { Colors, Radius, Spacing, FontSize } from '../../utils/constants';

/** Action identifiers for torrent context menu. */
export enum TorrentAction {
  PAUSE = 'pause',
  RESUME = 'resume',
  REMOVE = 'remove',
  REMOVE_WITH_DATA = 'remove_with_data',
  VERIFY = 'verify',
  REANNOUNCE = 'reannounce',
  SHOW_FILES = 'show_files',
  SAVE_TO_FILES = 'save_to_files',
  SHOW_DETAIL = 'show_detail',
}

/** Callback type for torrent context menu actions. */
export type TorrentActionCallback = (action: TorrentAction, torrent: TorrentInfo) => void;

@Component
export struct TorrentContextMenu {
  @Prop torrent: TorrentInfo;
  @Prop sessionId: number = 0;
  // @Link (not @State): visibility is owned by the parent's showContextMenu —
  // with @State, reopening after a dismiss left it stuck false, so the menu
  // wouldn't re-appear. @Link gives a single two-way source of truth.
  @Link isVisible: boolean;
  onAction?: TorrentActionCallback;

  /** Show the context menu programmatically. */
  show(): void {
    this.isVisible = true;
  }

  /** Hide the context menu programmatically. */
  hide(): void {
    this.isVisible = false;
  }

  build() {
    if (this.isVisible) {
      Stack() {
        // Backdrop (dismiss on tap)
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor('#00000080')
          .onClick(() => { this.hide(); });

        // Menu panel
        Column() {
          this.buildMenuHeader();
          this.buildMenuActions();
          this.buildMenuCancel();
        }
        .width('90%')
        .borderRadius(Radius.LG)
        .backgroundColor(Colors.SURFACE)
        .padding({ top: Spacing.LG, bottom: Spacing.LG });
      }
      .width('100%')
      .height('100%')
      .position({ x: 0, y: 0 });
    }
  }

  @Builder
  buildMenuHeader() {
    Row() {
      Text(this.torrent.name)
        .fontSize(FontSize.HEADLINE)
        .fontWeight(FontWeight.Medium)
        .fontColor(Colors.TEXT)
        .layoutWeight(1)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis });

      Text(this.torrent.getStatusString())
        .fontSize(FontSize.SMALL)
        .fontColor(this.torrent.getStatusColor())
        .padding({ left: Spacing.SM, right: Spacing.SM, top: 2, bottom: 4 })
        .borderRadius(Radius.SM)
        .border({ width: 1, color: this.torrent.getStatusColor() });
    }
    .width('100%')
    .padding({ left: Spacing.LG, right: Spacing.LG })
    .margin({ bottom: Spacing.MD });
  }

  @Builder
  buildMenuActions() {
    Column() {
      // Pause / Resume
      if (this.torrent.isStopped()) {
        this.MenuItem('▶', 'Resume', TorrentAction.RESUME, Colors.SEED);
      } else {
        this.MenuItem('⏸', 'Pause', TorrentAction.PAUSE, Colors.PAUSED);
      }

      // Verify
      this.MenuItem('✓', 'Verify Local Data', TorrentAction.VERIFY, Colors.QUEUED);

      // Reannounce
      this.MenuItem('⟳', 'Reannounce', TorrentAction.REANNOUNCE, Colors.TEXT);

      // Show Files
      this.MenuItem('📁', 'Show Files', TorrentAction.SHOW_FILES, Colors.TEXT);

      // Save to Files (export completed data into public Download via picker)
      this.MenuItem('⬇', 'Save to Files', TorrentAction.SAVE_TO_FILES, Colors.DOWNLOAD);

      // Remove
      this.MenuItem('✕', 'Remove', TorrentAction.REMOVE, Colors.ERROR);

      // Remove with data
      this.MenuItem('✕✕', 'Remove and Delete Data', TorrentAction.REMOVE_WITH_DATA, Colors.ERROR);

      Divider()
        .color(Colors.DIVIDER)
        .margin({ top: Spacing.SM, bottom: Spacing.SM });

      // Show Detail
      this.MenuItem('ℹ', 'Torrent Details', TorrentAction.SHOW_DETAIL, Colors.TEXT);
    }
    .width('100%');
  }

  @Builder
  buildMenuCancel() {
    Button('Cancel')
      .fontSize(FontSize.BODY)
      .fontColor(Colors.TEXT_SECONDARY)
      .width('90%')
      .height(44)
      .borderRadius(Radius.MD)
      .backgroundColor(Colors.ELEVATED)
      .margin({ top: Spacing.MD })
      .onClick(() => { this.hide(); });
  }

  @Builder
  MenuItem(icon: string, label: string, action: TorrentAction, color: string) {
    Row() {
      Text(icon)
        .fontSize(18)
        .fontColor(color)
        .width(36)
        .textAlign(TextAlign.Center);

      Text(label)
        .fontSize(FontSize.BODY)
        .fontColor(Colors.TEXT)
        .layoutWeight(1);

      Text('›')
        .fontSize(FontSize.BODY)
        .fontColor(Colors.TEXT_TERTIARY);
    }
    .width('100%')
    .height(48)
    .padding({ left: Spacing.LG, right: Spacing.LG })
    .onClick(() => {
      this.hide();
      if (this.onAction) {
        this.onAction(action, this.torrent);
      }
    });
  }
}
