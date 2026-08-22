// transmissionbtm — SettingsErrorBanner (inline error strip under the header)
// Extracted from SettingsPage.BuildErrorBanner(); purely presentational.

import { Colors, FontSize, Spacing } from '../../utils/constants';

@Component
export struct SettingsErrorBanner {
  @Prop error: string = '';

  build() {
    Row() {
      Text('⚠ ' + this.error)
        .fontSize(FontSize.CAPTION)
        .fontColor(Colors.ERROR)
        .layoutWeight(1);
    }
    .width('100%')
    .padding({ left: Spacing.LG, right: Spacing.LG, top: Spacing.SM, bottom: Spacing.MD })
    .backgroundColor(Colors.ELEVATED)
    .border({
      width: { bottom: 1 },
      color: Colors.ERROR,
    });
  }
}
