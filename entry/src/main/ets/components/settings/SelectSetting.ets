// transmissionbtm — Select Setting Component (M2)
//
// Tappable row showing label + current selection. On tap, shows a
// dialog with all options. Persists the selected index via
// PreferencesManager.

import { Colors, FontSize, Spacing } from '../../utils/constants';
import { PreferencesManager } from '../../models/Preferences';

@Component
export struct SelectSetting {
  @Prop label: ResourceStr = '';
  @Prop options: ResourceStr[] = [];
  @Prop prefKey: string = '';
  @Link selectedIndex: number;
  /** Persist type: 'int' stores the index, 'string' stores optionValues[idx]. */
  @Prop valueType: string = 'int';
  /** When valueType='string', these values are persisted instead of the index. */
  @Prop optionValues: string[] = [];

  private dialogController: CustomDialogController | null = null;

  aboutToAppear(): void {
    this.dialogController = new CustomDialogController({
      builder: SelectOptionDialog({
        title: this.label,
        options: this.options,
        initialIndex: this.selectedIndex,
        onSelect: (index: number) => {
          this.selectedIndex = index;
          if (this.prefKey) {
            if (this.valueType === 'string' && index < this.optionValues.length) {
              PreferencesManager.getInstance().setString(this.prefKey, this.optionValues[index]);
            } else {
              PreferencesManager.getInstance().setInt(this.prefKey, index);
            }
          }
          this.dialogController?.close();
        },
      }),
      autoCancel: true,
      alignment: DialogAlignment.Center,
    });
  }

  build() {
    Row() {
      Text(this.label)
        .fontSize(FontSize.BODY)
        .fontColor(Colors.TEXT)
        .layoutWeight(1);

      Text(this.options[this.selectedIndex] ?? '')
        .fontSize(FontSize.CAPTION)
        .fontColor(Colors.DOWNLOAD)
        .fontWeight(FontWeight.Medium);
    }
    .width('100%')
    .padding({
      left: Spacing.LG,
      right: Spacing.LG,
      top: Spacing.MD,
      bottom: Spacing.MD,
    })
    .onClick(() => {
      if (this.dialogController) {
        this.dialogController.open();
      }
    });
  }
}

// ── Internal Option Dialog ────────────────────────────────────────

@CustomDialog
struct SelectOptionDialog {
  controller: CustomDialogController;
  @Prop title: ResourceStr = '';
  @Prop options: ResourceStr[] = [];
  /** Currently-selected index copied in to highlight the right option. */
  @Prop initialIndex: number = 0;
  /** Called with the chosen index on select; the parent owns persistence. */
  onSelect: (index: number) => void = () => {};
  @State private selectedLocal: number = 0;

  aboutToAppear(): void {
    this.selectedLocal = this.initialIndex;
  }

  build() {
    Column() {
      Text(this.title)
        .fontSize(FontSize.HEADLINE)
        .fontColor(Colors.TEXT)
        .fontWeight(FontWeight.Medium)
        .margin({ bottom: Spacing.LG });

      ForEach(this.options, (option: ResourceStr, index: number) => {
        Button(option)
          .type(ButtonType.Normal)
          .fontSize(FontSize.BODY)
          .fontColor(index === this.selectedLocal ? '#ffffff' : Colors.TEXT)
          .backgroundColor(index === this.selectedLocal ? Colors.DOWNLOAD : Colors.ELEVATED)
          .width('100%')
          .margin({ bottom: Spacing.SM })
          .onClick(() => {
            this.selectedLocal = index;
            this.onSelect(index);
          });
      });

      Button($r('app.string.common_cancel'))
        .type(ButtonType.Normal)
        .fontSize(FontSize.CAPTION)
        .fontColor(Colors.TEXT_SECONDARY)
        .backgroundColor(Colors.ELEVATED)
        .width('100%')
        .margin({ top: Spacing.SM })
        .onClick(() => {
          this.controller?.close();
        });
    }
    .padding(Spacing.XL);
  }
}
