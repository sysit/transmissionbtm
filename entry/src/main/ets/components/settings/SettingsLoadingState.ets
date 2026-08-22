// transmissionbtm — SettingsLoadingState (centered spinner shown while prefs load)
// Extracted from SettingsPage.BuildLoadingState(); purely presentational.

import { Colors, FontSize, Spacing } from '../../utils/constants';

@Component
export struct SettingsLoadingState {
  build() {
    Column() {
      LoadingProgress()
        .width(40)
        .height(40)
        .color(Colors.DOWNLOAD);
      Text('Loading settings...')
        .fontSize(FontSize.CAPTION)
        .fontColor(Colors.TEXT_SECONDARY)
        .margin({ top: Spacing.MD });
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center);
  }
}
