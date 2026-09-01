// transmissionbtm — SettingsResetDialog (full-screen confirm overlay)
// Extracted from SettingsPage.BuildResetDialog(). The parent gates visibility
// (if showResetDialog) and supplies the confirm/cancel handlers; this component
// is purely presentational.

import { Colors, FontSize, Spacing, Radius } from '../../utils/constants';

@Component
export struct SettingsResetDialog {
  onConfirm: () => void = () => {};
  onCancel: () => void = () => {};

  build() {
    Column() {
      Column() {
        Text($r('app.string.settings_reset_defaults'))
          .fontSize(FontSize.HEADLINE)
          .fontWeight(FontWeight.Medium)
          .fontColor(Colors.TEXT)
          .margin({ bottom: Spacing.MD });

        Text($r('app.string.settings_reset_confirm_desc'))
          .fontSize(FontSize.CAPTION)
          .fontColor(Colors.TEXT_SECONDARY)
          .margin({ bottom: Spacing.LG });

        Row() {
          Button($r('app.string.common_cancel'))
            .fontSize(FontSize.CAPTION)
            .fontColor(Colors.TEXT_SECONDARY)
            .backgroundColor(Colors.ELEVATED)
            .layoutWeight(1)
            .onClick(() => { this.onCancel(); });

          Button($r('app.string.settings_reset_confirm'))
            .fontSize(FontSize.CAPTION)
            .fontColor('#ffffff')
            .backgroundColor(Colors.ERROR)
            .layoutWeight(1)
            .margin({ left: Spacing.MD })
            .onClick(() => { this.onConfirm(); });
        }
        .width('100%');
      }
      .padding(Spacing.XL)
      .borderRadius(Radius.LG)
      .backgroundColor(Colors.SURFACE);
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .padding(Spacing.XL)
    .backgroundColor('rgba(0,0,0,0.6)')
    .onClick(() => { this.onCancel(); });
  }
}
