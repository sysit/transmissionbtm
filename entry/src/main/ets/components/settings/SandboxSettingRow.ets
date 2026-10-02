// transmissionbtm — SandboxSettingRow (read-only label/value pair for a
// runtime-fixed path). Extracted from SettingsPage.BuildSandboxSetting() so the
// page doesn't inline a reusable row.

import { Colors, FontSize, Spacing } from '../../utils/constants';

@Component
export struct SandboxSettingRow {
  @Prop label: ResourceStr = '';
  @Prop value: string = '';

  build() {
    // Value on its own line, not beside the label: a sandbox path is longer
    // than the space left of a right-aligned label, so side-by-side either
    // truncates (ellipsis) or wraps mid-path. Stacked, it fits on one line.
    Column() {
      Text(this.label)
        .fontSize(FontSize.BODY)
        .fontColor(Colors.TEXT);

      // No maxLines/ellipsis anywhere — wrap is the fallback, never a cut.
      Text(this.value)
        .fontSize(FontSize.CAPTION)
        .fontColor(Colors.TEXT_SECONDARY)
        .margin({ top: Spacing.XS });
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .padding({ left: Spacing.LG, right: Spacing.LG, top: Spacing.MD, bottom: Spacing.MD });
  }
}
