// transmissionbtm — StatChip (label + value badge)

import { Colors } from '../../utils/constants';

@Component
export struct StatChip {
  @Prop label: string = '';
  @Prop value: string = '';
  @Prop color: string = Colors.TEXT;

  build() {
    Column() {
      Text(this.label)
        .fontSize(10)
        .fontColor(Colors.TEXT_TERTIARY);
      Text(this.value)
        .fontSize(14)
        .fontColor(this.color)
        .fontWeight(FontWeight.Medium)
        .fontFamily('JetBrains Mono')
        .margin({ top: 2 });
    }
    .alignItems(HorizontalAlign.Center)
  }
}
