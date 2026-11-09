// transmissionbtm — Edit Setting Component (M2)
//
// Tappable row showing label + current value. On tap, opens a dialog
// with a TextInput for editing. Persists via PreferencesManager.

import { promptAction } from '@kit.ArkUI';
import { CLICK_EFFECT, Colors, FontSize, Spacing } from '../../utils/constants';
import { PreferencesManager } from '../../models/Preferences';

@Component
export struct EditSetting {
  @Prop label: ResourceStr = '';
  @Prop hint: ResourceStr = '';
  @Prop prefKey: string = '';
  @Prop inputType: InputType = InputType.Normal;
  /** Persist type: 'string' (default), 'number' calls setInt, 'float' uses parseFloat. */
  @Prop valueType: string = 'string';
  /** D4: numeric bounds. Out-of-range values are rejected before they reach
   *  the engine (port 0, negative limits, alt-speed indices past the array). */
  @Prop minValue: number = Number.MIN_SAFE_INTEGER;
  @Prop maxValue: number = Number.MAX_SAFE_INTEGER;
  /** D6: extra format check for string fields (e.g. proxy host). Runs before
   *  persistence; returning false keeps the dialog open. */
  validate: (text: string) => boolean = () => true;
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
          this.applyValue(text);
        },
      }),
      autoCancel: true,
      alignment: DialogAlignment.Center,
    });
  }

  /**
   * Validate, persist, then update the row + close the dialog. The dialog
   * stays open on any failure (invalid format, out of range, or a write that
   * did not land) so the row can never display text that was not stored.
   */
  private async applyValue(text: string): Promise<void> {
    if (this.prefKey) {
      const pm = PreferencesManager.getInstance();
      let ok = true;
      if (this.valueType === 'number' || this.valueType === 'float') {
        // Number(), not parseFloat: parseFloat('8080abc') is 8080, which
        // would persist 8080 while the row then displays '8080abc'. Empty
        // is explicitly NaN because Number('') is 0.
        const trimmed = text.trim();
        const numVal = trimmed === '' ? NaN : Number(trimmed);
        // Integer keys (ports, peer/speed limits) take no fraction either.
        const badShape = this.valueType === 'float'
          ? !isFinite(numVal)
          : (numVal % 1) !== 0;
        if (badShape) {
          promptAction.showToast({ message: $r('app.string.settings_invalid_number') });
          return;
        }
        if (numVal < this.minValue || numVal > this.maxValue) {
          promptAction.showToast({ message: $r('app.string.settings_out_of_range') });
          return;
        }
        ok = this.valueType === 'float'
          ? await pm.setFloat(this.prefKey, numVal)
          : await pm.setInt(this.prefKey, numVal);
      } else {
        if (!this.validate(text)) {
          promptAction.showToast({ message: $r('app.string.settings_invalid_value') });
          return;
        }
        ok = await pm.setString(this.prefKey, text);
      }
      if (!ok) {
        promptAction.showToast({ message: $r('app.string.settings_save_failed') });
        return;
      }
    }
    // Assign the displayed value only after the persist above succeeded.
    this.value = text;
    this.dialogController?.close();
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
    .clickEffect(CLICK_EFFECT).onClick(() => {
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
          .clickEffect(CLICK_EFFECT).onClick(() => {
            this.controller?.close();
          });

        Button($r('app.string.common_save'))
          .fontSize(FontSize.CAPTION)
          .fontColor('#ffffff')
          .backgroundColor(Colors.DOWNLOAD)
          .margin({ left: Spacing.MD })
          .clickEffect(CLICK_EFFECT).onClick(() => {
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
