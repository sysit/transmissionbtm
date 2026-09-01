// transmissionbtm — EmptyState component

import { Colors, Spacing } from '../../utils/constants';

@Component
export struct EmptyState {
  @Prop icon: string = '⊡';
  @Prop title: ResourceStr = 'Nothing here';
  @Prop description: ResourceStr = '';

  build() {
    Column() {
      Text(this.icon).fontSize(48).fontColor(Colors.TEXT_TERTIARY).margin({ bottom: Spacing.LG });
      Text(this.title).fontSize(17).fontWeight(FontWeight.Medium).fontColor(Colors.TEXT_SECONDARY);
      if (this.description) {
        Text(this.description).fontSize(13).fontColor(Colors.TEXT_TERTIARY).margin({ top: Spacing.SM });
      }
    }
    .width('100%')
    .padding({ top: 80, bottom: 80 })
    .alignItems(HorizontalAlign.Center);
  }
}
