// transmissionbtm — PublishFolderRow (tappable publish/export folder chooser)
//
// Extracted from SettingsPage.BuildPublishFolder(). Two-way binds the parent's
// @State publishDir (@Link) so loadPreferences()/resetToDefaults() keep the page
// as the single source of truth; the picker + persistence + display logic move
// here with the row.

import { Colors, FontSize, Spacing } from '../../utils/constants';
import { PreferencesManager, PrefKeys } from '../../models/Preferences';
import { fileIo as fs, picker } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';
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
          .fontColor(Colors.TEXT);
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

  /**
   * Pick the "Publish folder" (the directory "Save to Files" seeds as its start
   * location) and persist its URI. Phone-safe single-path strategy:
   *
   * DocumentViewPicker has no *file-free* directory picker on a phone:
   * `DocumentSelectMode.FOLDER` (line 432 of @ohos.file.picker.d.ts) is documented
   * as "Only 2-in-1 devices are supported" — on a phone (Pura 80, API 24) it opens
   * a browse-only view (breadcrumb + folder nav) with no confirm affordance, so
   * `select()` never resolves and the UI hangs. Verified on-device. It is not a
   * viable primary path.
   *
   * The reliable path on a phone is `save()` (DEFAULT mode): it confirms via the ✓
   * button. But it is file-oriented, so:
   *   - the filename box must be non-blank ("Can't be left blank") → pre-fill a
   *     disposable placeholder;
   *   - the placeholder name must not collide with an existing file (the picker
   *     refuses "This file name already exists" — a stray `publish` left by an older
   *     build currently blocks that fixed name) → make it unique with a timestamp;
   *   - `autoCreateEmptyFile=false` (API 23+, FolderSelection syscap; line 825)
   *     prevents the picker materialising an empty file at the target — this is the
   *     actual anti-stray-file guarantee (fs.unlinkSync is path-only, not URI-aware,
   *     so it cannot delete a file://docs placeholder reliably);
   *   - we store the PARENT directory URI (never the filename), then best-effort
   *     unlink the placeholder so nothing is left in the target directory.
   * The stored publishDir is a directory URI either way — exactly what
   * DownloadsPage.exportToPublishDir() expects as its defaultFilePathUri.
   */
  private async onPickPublishDir(): Promise<void> {
    try {
      const dp = new picker.DocumentViewPicker(getContext(this) as common.UIAbilityContext);
      const DOWNLOAD_URI = 'file://docs/storage/Users/currentUser/Download';

      const opts = new picker.DocumentSaveOptions();
      opts.pickerMode = picker.DocumentPickerMode.DEFAULT;
      // Unique disposable placeholder so the dialog never collides with an existing
      // file of the same name (a stray `publish` from an older build blocks a fixed
      // name with "This file name already exists").
      opts.newFileNames = [`publish-${Date.now()}`];
      opts.defaultFilePathUri = this.publishDir && this.publishDir.length > 0
        ? this.publishDir : DOWNLOAD_URI;
      opts.autoCreateEmptyFile = false; // API 23+; prevents an empty file where honoured

      const uris: string[] = await dp.save(opts);
      if (!uris || uris.length === 0) {
        return; // picker dismissed
      }
      // The returned URI points at the placeholder file; the publish dir is its parent.
      const fileUri = uris[0];
      const parent = this.parentUri(fileUri);
      await this.applyPublishDir(parent);
      hilog.info(0x0001, TAG, 'save dialog dir=%{private}s placeholder=%{private}s', parent, fileUri);
      // Best-effort remove the disposable placeholder so nothing is left in the target
      // folder. unlinkSync is path-only and may reject a file://docs URI — ignore.
      try {
        fs.unlinkSync(fileUri);
      } catch (ulErr) {
        hilog.info(0x0001, TAG, 'placeholder already gone / not unlinkable: %{private}s', String(ulErr));
      }
      promptAction.showToast({ message: '发布目录已保存', duration: 2000 });
    } catch (e) {
      hilog.error(0x0001, TAG, 'Pick publish dir failed: %{private}s', String(e));
      promptAction.showToast({ message: `设置失败: ${String(e)}`, duration: 2000 });
    }
  }

  /** Persist the chosen publish dir and update the row's display (@Link). */
  private async applyPublishDir(dir: string): Promise<void> {
    this.publishDir = dir;
    await PreferencesManager.getInstance().setString(PrefKeys.PUBLISH_DIR, dir);
  }

  /** Parent directory URI of a file URI (strip the trailing path segment). */
  private parentUri(uri: string): string {
    const trimmed = uri.endsWith('/') ? uri.slice(0, -1) : uri;
    const idx = trimmed.lastIndexOf('/');
    return idx >= 0 ? trimmed.substring(0, idx) : trimmed;
  }
}
