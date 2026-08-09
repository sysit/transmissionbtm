// transmissionhm — BrowsePathView Component (M6)
//
// Renders a label + current path + "Browse" button that opens
// the HarmonyOS DirectoryPicker so the user can choose a folder.
// Used in SettingsPage for download/incomplete directories.

import { Colors, FontSize, Spacing, Radius } from '../../utils/constants';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { picker } from '@kit.CoreFileKit';

const TAG = 'BrowsePathView';

@Component
export struct BrowsePathView {
  @Prop label: string = '';
  @Link path: string;

  /**
   * Open the system directory/file picker and update path on selection.
   * Uses HarmonyOS fileAccess API for directory picking.
   */
  private async openDirectoryPicker(): Promise<void> {
    try {
      const dp = new picker.DocumentViewPicker();
      const options = new picker.DocumentSelectOptions();
      options.maxSelectNumber = 1;
      options.selectMode = picker.DocumentSelectMode.FOLDER;
      const uris = await dp.select(options);
      if (uris && uris.length > 0) {
        const uri = uris[0];
        if (uri) {
          this.path = uri;
          hilog.info(0x0001, TAG,
            'Directory selected for %{private}s: %{private}s', this.label, this.path);
        }
      }
    } catch (err) {
      // User cancelled or picker not available — keep existing path
      hilog.info(0x0001, TAG,
        'Directory picker dismissed for %{private}s: %{public}s', this.label, String(err));
    }
  }

  build() {
    Row() {
      // Label on the left
      Text(this.label)
        .fontSize(FontSize.BODY)
        .fontColor(Colors.TEXT)
        .layoutWeight(1);

      // Current path (truncated)
      Text(this.path || 'Not set')
        .fontSize(FontSize.CAPTION)
        .fontColor(this.path ? Colors.DOWNLOAD : Colors.TEXT_TERTIARY)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .constraintSize({ maxWidth: '40%' })
        .margin({ right: Spacing.SM });

      // Browse button
      Button('Browse')
        .fontSize(FontSize.SMALL)
        .fontColor('#ffffff')
        .backgroundColor(Colors.DOWNLOAD)
        .borderRadius(Radius.SM)
        .padding({
          left: Spacing.MD,
          right: Spacing.MD,
          top: 6,
          bottom: 6,
        })
        .onClick(() => {
          this.openDirectoryPicker();
        });
    }
    .width('100%')
    .padding({
      left: Spacing.LG,
      right: Spacing.LG,
      top: Spacing.MD,
      bottom: Spacing.MD,
    });
  }
}
