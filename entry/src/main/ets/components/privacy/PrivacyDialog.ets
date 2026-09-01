// transmissionbtm — First-launch privacy dialog
//
// Huawei AppGallery requires a native HarmonyOS app to present its privacy
// policy on first launch and obtain explicit user consent (checkbox) before
// any data is touched. On first run this full-screen overlay is shown on top
// of the main UI; the user must check "I have read and agree..." to proceed.
//
// Rendered as a Stack overlay (not a @CustomDialog) deliberately: passing a
// @Link into a @CustomDialog via $ throws a ReferenceError at open time, and
// a surface overlay is flat, deterministic and safer for a gate this early in
// the UI lifecycle.

import { common } from '@kit.AbilityKit';
import { Colors, FontSize, Spacing, Radius } from '../../utils/constants';
import { PreferencesManager, PrefKeys } from '../../models/Preferences';

const PRIVACY_URL = 'https://sysit.github.io/transmissionbtm/privacy-policy.html';

@Component
export struct PrivacyDialog {
  /** Parent controls visibility; this component sets it false on accept. */
  @Link show: boolean;
  /** Whether the checkbox is checked; gates the "同意" button. */
  @State agreed: boolean = false;

  /**
   * Persist consent and dismiss. Consent persists in preferences so the gate
   * shows only once. Failure to persist is non-fatal (default is not-accepted
   * on next launch, which is the safe direction).
   */
  private async onAgree(): Promise<void> {
    try {
      await PreferencesManager.getInstance().setBoolean(PrefKeys.PRIVACY_ACCEPTED, true);
    } catch (err) {
      // Non-fatal: leave flag unset so the gate reappears next launch.
    }
    this.show = false;
  }

  /** Decline = exit the app. A declined app must not run/collect anything. */
  private onDisagree(): void {
    const ctx = this.getUIContext().getHostContext();
    if (ctx) {
      (ctx as common.UIAbilityContext).terminateSelf();
    }
  }

  /** Open the full privacy policy in the system browser. */
  private openPolicy(): void {
    const ctx = this.getUIContext().getHostContext();
    if (ctx) {
      (ctx as common.UIAbilityContext).startAbility({
        action: 'ohos.want.action.viewData',
        uri: PRIVACY_URL,
      });
    }
  }

  build() {
    Stack() {
      // Full-screen dimmed backdrop. Also eats touches so nothing behind is
      // tappable while the gate is up.
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('#CC000000')
        .onClick(() => {
          // Consume the backdrop tap — the gate is dismissed only via buttons.
        })

      // Card
      Column() {
        Column() {
          Text($r('app.string.privacy_title'))
            .fontSize(FontSize.XL)
            .fontWeight(600)
            .fontColor(Colors.TEXT)

          Scroll() {
            Column() {
              Text($r('app.string.privacy_body'))
                .fontSize(FontSize.MD)
                .fontColor(Colors.TEXT_SECONDARY)
                .lineHeight(22)
            }
            .width('100%')
            .padding({ top: Spacing.MD, bottom: Spacing.MD })
          }
          .height(300)
          .width('100%')

          // "查看完整隐私政策" link row
          Column() {
            Text($r('app.string.privacy_view_policy'))
              .fontSize(FontSize.MD)
              .fontColor(Colors.DOWNLOAD)
              .onClick(() => { this.openPolicy(); })
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
          .padding({ bottom: Spacing.MD })

          Divider()
            .color(Colors.DIVIDER)

          // Checkbox + label
          Row() {
            Checkbox({ name: 'privacy', group: 'privacy' })
              .select(this.agreed)
              .selectedColor(Colors.ACCENT)
              .width(20)
              .height(20)
              .onChange((v: boolean) => { this.agreed = v; })
              .margin({ right: Spacing.SM })
            Text($r('app.string.privacy_agreement_text'))
              .fontSize(FontSize.MD)
              .fontColor(Colors.TEXT)
              .layoutWeight(1)
          }
          .alignItems(VerticalAlign.Center)
          .width('100%')
          .padding({ top: Spacing.MD, bottom: Spacing.MD })

          // Buttons
          Row() {
            Button($r('app.string.privacy_disagree'))
              .fontSize(FontSize.MD)
              .fontColor(Colors.TEXT_SECONDARY)
              .backgroundColor(Colors.ELEVATED)
              .layoutWeight(1)
              .height(44)
              .onClick(() => { this.onDisagree(); })

            Button($r('app.string.privacy_agree'))
              .fontSize(FontSize.MD)
              .fontColor(Colors.TEXT)
              .backgroundColor(this.agreed ? Colors.ACCENT : Colors.ELEVATED)
              .layoutWeight(1)
              .height(44)
              .enabled(this.agreed)
              .margin({ left: Spacing.MD })
              .onClick(() => { this.onAgree(); })
          }
          .width('100%')
          .padding({ top: Spacing.MD })
        }
        .padding(Spacing.XL)
        .width('88%')
        .backgroundColor(Colors.SURFACE)
        .borderRadius(Radius.LG)
      }
      .width('100%')
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
    }
    .width('100%')
    .height('100%')
  }
}
