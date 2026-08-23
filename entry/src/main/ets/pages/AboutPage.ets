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
  @State versionError: string = '';

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
      this.versionError = 'Could not read native version';
      hilog.error(0x0001, TAG,
        'fetchVersion failed: %{private}s', String(err));
    } finally {
      this.isLoadingVersion = false;
    }
  }

  build() {
    Column() {
      // Page header
      Text('About')
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
          this.BuildEngineSection();
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
          Text(' Reading native version...')
            .fontSize(FontSize.SMALL)
            .fontColor(Colors.TEXT_TERTIARY);
        }
        .margin({ bottom: Spacing.SM });
      } else if (this.versionError.length > 0) {
        Text(`v${this.version} (fallback)`)
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
      Text(`Build ${AppConstants.BUILD_MILESTONE}  •  ${AppConstants.BUILD_DATE}`)
        .fontSize(FontSize.SM)
        .fontColor(Colors.TEXT_TERTIARY)
        .margin({ bottom: Spacing.XXL });
    }
    .alignItems(HorizontalAlign.Center)
    .width('100%')
    .margin({ top: Spacing.LG, bottom: Spacing.XXL });
  }

  // ═══════════════════════════════════════════════════════════════
  // Engine: native stack details
  // ═══════════════════════════════════════════════════════════════

  @Builder
  BuildEngineSection() {
    Column() {
      Text('Native Engine')
        .fontSize(FontSize.SM)
        .fontColor(Colors.TEXT_TERTIARY)
        .fontWeight(FontWeight.Medium)
        .textCase(TextCase.UpperCase)
        .letterSpacing(0.5)
        .width('100%')
        .padding({ left: Spacing.MD, bottom: Spacing.SM });

      Column() {
        this.BuildInfoRow('Engine', AppConstants.ENGINE_VERSION);
        this.BuildDivider();
        this.BuildInfoRow('Platform', AppConstants.PLATFORM);
        this.BuildDivider();
        this.BuildInfoRow('Architecture', AppConstants.ARCH);
        this.BuildDivider();
        this.BuildInfoRow('Native bridge', 'N-API (40 methods)');
        this.BuildDivider();
        this.BuildInfoRow('RPC port', String(AppConstants.RPC_DEFAULT_PORT));
        this.BuildDivider();
        this.BuildInfoRow('Peer port', String(AppConstants.PEER_DEFAULT_PORT));
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
  // Open Source Licenses
  // ═══════════════════════════════════════════════════════════════

  @Builder
  BuildLicenseSection() {
    Column() {
      Text('Open Source Licenses')
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
      Text('Credits')
        .fontSize(FontSize.SM)
        .fontColor(Colors.TEXT_TERTIARY)
        .fontWeight(FontWeight.Medium)
        .textCase(TextCase.UpperCase)
        .letterSpacing(0.5)
        .width('100%')
        .padding({ left: Spacing.MD, bottom: Spacing.SM });

      Column() {
        this.BuildInfoRow(
          'Original port',
          'transmissionbtc (Android) by Andrey Pavlenko'
        );
        this.BuildDivider();
        this.BuildInfoRow(
          'HarmonyOS port',
          'transmissionbtm © 2024–2026'
        );
        this.BuildDivider();
        this.BuildInfoRow(
          'Design',
          'Built for HarmonyOS NEXT with ArkTS + ArkUI'
        );
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
  BuildInfoRow(label: string, value: string) {
    Row() {
      Text(label)
        .fontSize(FontSize.CAPTION)
        .fontColor(Colors.TEXT_SECONDARY)
        .layoutWeight(1);
      Text(value)
        .fontSize(FontSize.CAPTION)
        .fontColor(Colors.TEXT)
        .fontFamily('JetBrains Mono')
        .textAlign(TextAlign.End);
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
