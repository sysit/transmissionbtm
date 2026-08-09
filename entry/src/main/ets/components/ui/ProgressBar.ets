// transmissionhm — ProgressBar component

import { Colors } from '../../utils/constants';

@Component
export struct ProgressBar {
  @Prop progress: number = 0;
  @Prop color: string = Colors.DOWNLOAD;
  @Prop barHeight: number = 4;
  @Prop showLabel: boolean = true;
  @Prop labelSize: number = 11;

  build() {
    Row() {
      Stack({ alignContent: Alignment.Start }) {
        Row()
          .width('100%')
          .height(this.barHeight)
          .borderRadius(this.barHeight / 2)
          .backgroundColor(Colors.PROGRESS_BG);
        Row()
          .width(`${Math.min(this.progress * 100, 100)}%`)
          .height(this.barHeight)
          .borderRadius(this.barHeight / 2)
          .backgroundColor(this.color)
          .animation({ duration: 250, curve: Curve.EaseOut });
      }
      .layoutWeight(1);

      if (this.showLabel) {
        Text(`${Math.round(this.progress * 100)}%`)
          .fontSize(this.labelSize)
          .fontColor(Colors.TEXT_SECONDARY)
          .fontFamily('JetBrains Mono')
          .margin({ left: 8 });
      }
    }
    .width('100%')
    .alignItems(VerticalAlign.Center);
  }
}
