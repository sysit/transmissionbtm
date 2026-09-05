// transmissionbtm — Edit Setting Component (M2)
//
// Tappable row showing label + current value. On tap, opens a dialog
// with a TextInput for editing. Persists via PreferencesManager.

import { Colors, FontSize, Spacing } from '../../utils/constants';
import { PreferencesManager } from '../../models/Preferences';

@Component
export struct EditSetting {
  @Prop label: ResourceStr = '';
  @Prop hint: ResourceStr = '';
  @Prop prefKey: string = '';
  @Prop inputType: InputType = InputType.Normal;
  /** Persist type: 'string' (default), 'number' calls setInt, 'float' uses parseFloat. */
  @Prop valueType: string = 'string';
  @Link value: string;

  private dialogController: CustomDialogController | null = null;

  /** Row text: never reveal a password in plaintext — always show a mask. */
  private displayText(): ResourceStr {
    if (this.inputType === InputType.Password) {
      return this.value ? '••••••••' : this.hint;
    }
    return this.value || this.hint;
  }

  aboutToAppear(): void {
    this.dialogController = new CustomDialogController({
      builder: EditSettingDialog({
        title: this.label,
        hint: this.hint,
        inputType: this.inputType,
        initialValue: this.value,
        onSave: (text: string) => {
          this.value = text;
          if (this.prefKey) {
            if (this.valueType === 'number' || this.valueType === 'float') {
              const numVal = parseFloat(text);
              if (!isNaN(numVal)) {
                if (this.valueType === 'float') {
                  PreferencesManager.getInstance().setFloat(this.prefKey, numVal);
                } else {
                  PreferencesManager.getInstance().setInt(this.prefKey, numVal);
                }
              }
            } else {
              PreferencesManager.getInstance().setString(this.prefKey, text);
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

      Text(this.displayText())
        .fontSize(FontSize.CAPTION)
        .fontColor(this.value ? Colors.DOWNLOAD : Colors.TEXT_TERTIARY)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .constraintSize({ maxWidth: '60%' });
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

// ── Internal Edit Dialog ──────────────────────────────────────────

@CustomDialog
struct EditSettingDialog {
  controller: CustomDialogController;
  @Prop title: ResourceStr = '';
  @Prop hint: ResourceStr = '';
  @Prop inputType: InputType = InputType.Normal;
  /** Current value copied in to prefill the field. */
  @Prop initialValue: string = '';
  /** Called with the edited text on Save; the parent owns persistence. */
  onSave: (text: string) => void = () => {};
  @State private inputText: string = '';

  aboutToAppear(): void {
    this.inputText = this.initialValue;
  }

  build() {
    Column() {
      Text(this.title)
        .fontSize(FontSize.HEADLINE)
        .fontColor(Colors.TEXT)
        .fontWeight(FontWeight.Medium)
        .margin({ bottom: Spacing.LG });

      TextInput({ text: this.inputText, placeholder: this.hint })
        .type(this.inputType)
        .fontSize(FontSize.BODY)
        .fontColor(Colors.TEXT)
        .placeholderColor(Colors.TEXT_TERTIARY)
        .backgroundColor(Colors.ELEVATED)
        .borderRadius(10)
        .padding(Spacing.MD)
        .width('100%')
        .onChange((text: string) => {
          this.inputText = text;
        });

      Row() {
        Button($r('app.string.common_cancel'))
          .fontSize(FontSize.CAPTION)
          .fontColor(Colors.TEXT_SECONDARY)
          .backgroundColor(Colors.ELEVATED)
          .onClick(() => {
            this.controller?.close();
          });

        Button($r('app.string.common_save'))
          .fontSize(FontSize.CAPTION)
          .fontColor('#ffffff')
          .backgroundColor(Colors.DOWNLOAD)
          .margin({ left: Spacing.MD })
          .onClick(() => {
            this.onSave(this.inputText);
          });
      }
      .width('100%')
      .justifyContent(FlexAlign.End)
      .margin({ top: Spacing.LG });
    }
    .padding(Spacing.XL);
  }
}
