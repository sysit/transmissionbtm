// transmissionbtm — Settings Group Container (M2)
//
// Groups related settings under a section header. Uses @BuilderParam
// so callers can slot arbitrary child content inside the card.

import { Colors, FontSize, Spacing, Radius } from '../../utils/constants';

@Component
export struct SettingsGroup {
  @Prop title: ResourceStr = '';

  @Builder
  defaultContent() {}

  @BuilderParam content: VoidCallback = this.defaultContent;

  build() {
    Column() {
      if (this.title) {
        Text(this.title)
          .fontSize(FontSize.SMALL)
          .fontColor(Colors.TEXT_TERTIARY)
          .fontWeight(FontWeight.Medium)
          .textCase(TextCase.UpperCase)
          .letterSpacing(0.5)
          .padding({
            left: Spacing.MD,
            bottom: Spacing.SM,
          });
      }

      Column() {
        this.content();
      }
      .width('100%')
      .borderRadius(Radius.LG)
      .backgroundColor(Colors.SURFACE);
    }
    .width('100%');
  }
}
