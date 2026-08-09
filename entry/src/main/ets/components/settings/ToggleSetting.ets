// transmissionhm — Toggle Setting Component (M2)
//
// Reusable toggle row: label + optional description + switch.
// Persists the value to PreferencesManager on every toggle.

import { Colors, FontSize, Spacing } from '../../utils/constants';
import { PreferencesManager } from '../../models/Preferences';

@Component
export struct ToggleSetting {
  @Prop label: string = '';
  @Prop description: string = '';
  @Prop prefKey: string = '';
  @Link checked: boolean;

  build() {
    Row() {
      Column() {
        Text(this.label)
          .fontSize(FontSize.BODY)
          .fontColor(Colors.TEXT)
          .margin({ bottom: 2 });

        if (this.description) {
          Text(this.description)
            .fontSize(FontSize.SMALL)
            .fontColor(Colors.TEXT_SECONDARY);
        }
      }
      .layoutWeight(1);

      Toggle({ type: ToggleType.Switch, isOn: this.checked })
        .onChange((isOn: boolean) => {
          this.checked = isOn;
          if (this.prefKey) {
            PreferencesManager.getInstance().setBoolean(this.prefKey, isOn);
          }
        })
        .selectedColor(Colors.DOWNLOAD);
    }
    .width('100%')
    .padding({
      left: Spacing.LG,
      right: Spacing.LG,
      top: Spacing.MD,
      bottom: Spacing.MD,
    });
  }
}
