// transmissionbtm — SandboxSettingRow (read-only label/value pair for a
// runtime-fixed path). Extracted from SettingsPage.BuildSandboxSetting() so the
// page doesn't inline a reusable row.

import { Colors, FontSize, Spacing } from '../../utils/constants';

@Component
export struct SandboxSettingRow {
  @Prop label: ResourceStr = '';
  @Prop value: string = '';

  build() {
    Row() {
      Text(this.label)
        .fontSize(FontSize.BODY)
        .fontColor(Colors.TEXT)
        .layoutWeight(1);

      Text(this.value)
        .fontSize(FontSize.CAPTION)
        .fontColor(Colors.TEXT_SECONDARY)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .constraintSize({ maxWidth: '55%' })
        .margin({ right: Spacing.SM });
    }
    .width('100%')
    .padding({ left: Spacing.LG, right: Spacing.LG, top: Spacing.MD, bottom: Spacing.MD });
  }
}
