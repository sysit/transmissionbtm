// transmissionbtm — PublishFolderRow (tappable publish/export folder chooser)
//
// Extracted from SettingsPage.BuildPublishFolder(). Two-way binds the parent's
// @State publishDir (@Link) so loadPreferences()/resetToDefaults() keep the page
// as the single source of truth; the picker + persistence + display logic move
// here with the row.

import { Colors, FontSize, Spacing } from '../../utils/constants';
import { PreferencesManager, PrefKeys } from '../../models/Preferences';
import { picker } from '@kit.CoreFileKit';
import { promptAction } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';

const TAG = 'PublishFolderRow';

@Component
export struct PublishFolderRow {
  @Link publishDir: string;

  build() {
    Row() {
      Column() {
        Text('Publish folder')
          .fontSize(FontSize.BODY)
          .fontColor(Colors.TEXT)
          .layoutWeight(1);
        Text(this.publishDisplay())
          .fontSize(FontSize.CAPTION)
          .fontColor(this.publishDir ? Colors.TEXT_SECONDARY : Colors.DOWNLOAD)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis });
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1);

      Text(this.publishDir ? '更改 ›' : '选择 ›')
        .fontSize(FontSize.CAPTION)
        .fontColor(Colors.DOWNLOAD)
        .margin({ right: Spacing.SM });
    }
    .width('100%')
    .padding({ left: Spacing.LG, right: Spacing.LG, top: Spacing.MD, bottom: Spacing.MD })
    .onClick(() => { this.onPickPublishDir(); });
  }

  /** Display name for the publish dir: last path segment (folder basename). */
  private publishDisplay(): string {
    if (!this.publishDir) {
      return '未设置 — 点按选择';
    }
    const trimmed = this.publishDir.endsWith('/')
      ? this.publishDir.slice(0, -1) : this.publishDir;
    const idx = trimmed.lastIndexOf('/');
    const name = idx >= 0 ? trimmed.substring(idx + 1) : trimmed;
    return name.length > 0 ? name : this.publishDir;
  }

  /** Open the system DOWNLOAD-mode picker (returns `Download/<bundle>/`) and
   *  persist the chosen dir URI so "Save to Files" reuses it without re-prompting. */
  private async onPickPublishDir(): Promise<void> {
    try {
      const dp = new picker.DocumentViewPicker();
      const opts = new picker.DocumentSaveOptions();
      opts.pickerMode = picker.DocumentPickerMode.DOWNLOAD;
      const uris: string[] = await dp.save(opts);
      if (!uris || uris.length === 0) {
        return; // picker dismissed
      }
      this.publishDir = uris[0];
      await PreferencesManager.getInstance().setString(PrefKeys.PUBLISH_DIR, uris[0]);
      promptAction.showToast({ message: '发布目录已保存', duration: 2000 });
    } catch (e) {
      hilog.error(0x0001, TAG, 'Pick publish dir failed: %{private}s', String(e));
      promptAction.showToast({ message: `设置失败: ${String(e)}`, duration: 2000 });
    }
  }
}
