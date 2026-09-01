// transmissionbtm — AboutPage (M6)
//
// App identity, version info, engine details, open-source licenses,
// and credits. Version is fetched from the native bridge on render.

import { Colors, FontSize, Spacing, Radius, AppConstants } from '../utils/constants';
import { NativeBridge } from '../bridge/NativeBridge';
import { hilog } from '@kit.PerformanceAnalysisKit';

const TAG = 'AboutPage';

@Component
export struct AboutPage {
  @State version: string = AppConstants.APP_VERSION;
  @State isLoadingVersion: boolean = true;
  @State versionError: ResourceStr = '';

  aboutToAppear(): void {
    this.fetchVersion();
  }

  private fetchVersion(): void {
    this.isLoadingVersion = true;
    try {
      const bridge = NativeBridge.getInstance();
      const v = bridge.getVersion();
      if (v && v.length > 0) {
        this.version = v;
      }
    } catch (err) {
      this.versionError = $r('app.string.about_version_error');
      hilog.error(0x0001, TAG,
        'fetchVersion failed: %{private}s', String(err));
    } finally {
      this.isLoadingVersion = false;
    }
  }

  build() {
    Column() {
      // Page header
      Text($r('app.string.about_title'))
        .fontSize(FontSize.XL)
        .fontWeight(FontWeight.Bold)
        .fontColor(Colors.TEXT)
        .width('100%')
        .padding({
          left: Spacing.LG,
          top: Spacing.LG,
          bottom: Spacing.XXL,
        });

      Scroll() {
        Column() {
          this.BuildHeroSection();
          this.BuildLicenseSection();
          this.BuildCreditsSection();
        }
        .alignItems(HorizontalAlign.Center)
        .padding({ left: Spacing.LG, right: Spacing.LG, bottom: 80 });
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off);
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Colors.BG);
  }

  // ═══════════════════════════════════════════════════════════════
  // Hero: App icon, name, version
  // ═══════════════════════════════════════════════════════════════

  @Builder
  BuildHeroSection() {
    Column() {
      // App icon — layered download arrow on accent background
      Stack() {
        Row()
          .width(80)
          .height(80)
          .borderRadius(20)
          .backgroundColor(Colors.DOWNLOAD);
        Column() {
          Text('↓')
            .fontSize(28)
            .fontColor('#ffffff')
            .fontWeight(FontWeight.Bold);
        }
        .width(80)
        .height(80)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center);
      }
      .width(80)
      .height(80)
      .margin({ bottom: Spacing.LG });

      // App name
      Text(AppConstants.APP_NAME)
        .fontSize(FontSize.XL)
        .fontWeight(FontWeight.Bold)
        .fontColor(Colors.TEXT)
        .margin({ bottom: 4 });

      // Version
      if (this.isLoadingVersion) {
        Row() {
          LoadingProgress()
            .width(16)
            .height(16)
            .color(Colors.TEXT_SECONDARY);
          Text($r('app.string.about_reading_version'))
            .fontSize(FontSize.SMALL)
            .fontColor(Colors.TEXT_TERTIARY)
            .margin({ left: Spacing.SM });
        }
        .margin({ bottom: Spacing.SM });
      } else if (this.versionError) {
        Text($r('app.string.about_version_fallback', this.version))
          .fontSize(FontSize.MD)
          .fontColor(Colors.TEXT_SECONDARY)
          .fontFamily('JetBrains Mono')
          .margin({ bottom: Spacing.SM });
        Text(this.versionError)
          .fontSize(FontSize.SMALL)
          .fontColor(Colors.ERROR)
          .margin({ bottom: Spacing.SM });
      } else {
        Text(`v${this.version}`)
          .fontSize(FontSize.MD)
          .fontColor(Colors.TEXT_SECONDARY)
          .fontFamily('JetBrains Mono')
          .margin({ bottom: Spacing.SM });
      }

      // Build info
      Text($r('app.string.about_build', AppConstants.BUILD_MILESTONE, AppConstants.BUILD_DATE))
        .fontSize(FontSize.SM)
        .fontColor(Colors.TEXT_TERTIARY)
        .margin({ bottom: Spacing.XXL });
    }
    .alignItems(HorizontalAlign.Center)
    .width('100%')
    .margin({ top: Spacing.LG, bottom: Spacing.XXL });
  }

  // ═══════════════════════════════════════════════════════════════
  // Open Source Licenses
  // ═══════════════════════════════════════════════════════════════

  @Builder
  BuildLicenseSection() {
    Column() {
      Text($r('app.string.about_opensource'))
        .fontSize(FontSize.SM)
        .fontColor(Colors.TEXT_TERTIARY)
        .fontWeight(FontWeight.Medium)
        .textCase(TextCase.UpperCase)
        .letterSpacing(0.5)
        .width('100%')
        .padding({ left: Spacing.MD, bottom: Spacing.SM });

      Column() {
        this.BuildLicenseRow('libtransmission', '4.1.0', 'GPL-2.0 / MIT');
        this.BuildDivider();
        this.BuildLicenseRow('OpenSSL', '3.0', 'Apache-2.0');
        this.BuildDivider();
        this.BuildLicenseRow('libcurl', '8.5', 'curl License');
        this.BuildDivider();
        this.BuildLicenseRow('libevent', '2.1.12', 'BSD-3-Clause');
        this.BuildDivider();
        this.BuildLicenseRow('ArkUI Framework', '5.0', 'HarmonyOS SDK EULA');
      }
      .width('100%')
      .borderRadius(Radius.LG)
      .backgroundColor(Colors.SURFACE)
      .padding({
        top: Spacing.MD,
        bottom: Spacing.MD,
      });
    }
    .width('100%')
    .margin({ bottom: Spacing.XL });
  }

  // ═══════════════════════════════════════════════════════════════
  // Credits
  // ═══════════════════════════════════════════════════════════════

  @Builder
  BuildCreditsSection() {
    Column() {
      Text($r('app.string.about_credits'))
        .fontSize(FontSize.SM)
        .fontColor(Colors.TEXT_TERTIARY)
        .fontWeight(FontWeight.Medium)
        .textCase(TextCase.UpperCase)
        .letterSpacing(0.5)
        .width('100%')
        .padding({ left: Spacing.MD, bottom: Spacing.SM });

      Column() {
        Text('transmissionbtm © 2024–2026')
          .fontSize(FontSize.CAPTION)
          .fontColor(Colors.TEXT)
          .width('100%')
          .textAlign(TextAlign.Center)
          .padding({ top: Spacing.SM, bottom: Spacing.SM });
        this.BuildDivider();
        Text($r('app.string.about_built_with'))
          .fontSize(FontSize.CAPTION)
          .fontColor(Colors.TEXT)
          .width('100%')
          .textAlign(TextAlign.Center)
          .padding({ top: Spacing.SM, bottom: Spacing.SM });
      }
      .width('100%')
      .borderRadius(Radius.LG)
      .backgroundColor(Colors.SURFACE)
      .padding({
        top: Spacing.MD,
        bottom: Spacing.MD,
      });
    }
    .width('100%')
    .margin({ bottom: Spacing.XL });
  }

  // ── Shared Helpers ─────────────────────────────────────────────

  @Builder
  BuildLicenseRow(name: string, version: string, license: string) {
    Row() {
      Column() {
        Text(name)
          .fontSize(FontSize.CAPTION)
          .fontColor(Colors.TEXT);
        Text(`v${version}`)
          .fontSize(FontSize.SMALL)
          .fontColor(Colors.TEXT_TERTIARY);
      }
      .layoutWeight(1);

      Text(license)
        .fontSize(FontSize.SMALL)
        .fontColor(Colors.TEXT_SECONDARY)
        .fontFamily('JetBrains Mono')
        .padding({
          left: Spacing.SM,
          right: Spacing.SM,
          top: 2,
          bottom: 2,
        })
        .borderRadius(Radius.SM)
        .backgroundColor(Colors.ELEVATED);
    }
    .width('100%')
    .padding({
      left: Spacing.LG,
      right: Spacing.LG,
      top: Spacing.SM,
      bottom: Spacing.SM,
    });
  }

  @Builder
  BuildDivider() {
    Divider()
      .color(Colors.DIVIDER)
      .strokeWidth(0.5)
      .margin({
        left: Spacing.LG,
        right: Spacing.LG,
      });
  }
}
