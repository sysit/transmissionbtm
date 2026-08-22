// transmissionbtm — TorrentStatusBanner (add-flow result message)
//
// Extracted from AddTorrentPage.buildStatusMessage(). Shows a success/error
// icon + message; purely presentational, driven by the parent's @State.

import { Colors, Spacing, FontSize } from '../../utils/constants';

@Component
export struct TorrentStatusBanner {
  @Prop message: string = '';
  @Prop isError: boolean = false;

  build() {
    if (this.message.length > 0) {
      Row() {
        Text(this.isError ? '✕' : '✓')
          .fontSize(FontSize.CAPTION)
          .fontColor(this.isError ? Colors.ERROR : Colors.SEED)
          .margin({ right: Spacing.SM });

        Text(this.message)
          .fontSize(FontSize.CAPTION)
          .fontColor(this.isError ? Colors.ERROR : Colors.SEED)
          .layoutWeight(1);
      }
      .width('100%')
      .padding({ left: Spacing.LG, right: Spacing.LG, bottom: Spacing.MD });
    }
  }
}
