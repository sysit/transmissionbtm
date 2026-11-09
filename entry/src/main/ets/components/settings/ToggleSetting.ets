// transmissionbtm — Toggle Setting Component (M2)
//
// Reusable toggle row: label + optional description + switch.
// Persists the value to PreferencesManager on every toggle.

import { promptAction } from '@kit.ArkUI';
import { Colors, FontSize, Spacing } from '../../utils/constants';
import { PreferencesManager } from '../../models/Preferences';

@Component
export struct ToggleSetting {
  @Prop label: ResourceStr = '';
  @Prop description: ResourceStr = '';
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
          if (!this.prefKey) {
            return;
          }
          // D5: only keep the new position when the write landed. Reverting on
          // failure keeps the switch from showing an unsaved value.
          PreferencesManager.getInstance().setBoolean(this.prefKey, isOn)
            .then((ok: boolean) => {
              if (!ok) {
                this.checked = !isOn;
                promptAction.showToast({ message: $r('app.string.settings_save_failed') });
              }
            });
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
