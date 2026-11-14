// transmissionbtm — AboutPage (M6)
//
// App identity, version info, engine details, open-source licenses,
// and credits. Version is fetched from the native bridge on render.

import { Colors, FontSize, Spacing, Radius, AppConstants } from '../utils/constants';
import { errText } from '../utils/errors';
import { NativeBridge, EngineVersions } from '../bridge/NativeBridge';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { bundleManager } from '@kit.AbilityKit';

const TAG = 'AboutPage';

@Component
export struct AboutPage {
  @State version: string = '';
  @State buildDate: string = '';
  @State isLoadingVersion: boolean = true;
  @State versionError: ResourceStr = '';
  @State engineVersions: EngineVersions = {
    transmission: '', openssl: '', curl: '', libevent: '',
  };
  // SDK API level this build targets, read from the installed bundle — the
  // ArkUI row used to claim '5.0' long after the app moved to API 24.
  @State targetApi: number = 0;

  aboutToAppear(): void {
    this.fetchNativeInfo();
  }

  private fetchNativeInfo(): void {
    this.isLoadingVersion = true;
    try {
      const bridge = NativeBridge.getInstance();
      const v = bridge.getVersion();
      if (v && v.length > 0) {
        this.version = v;
      }
      this.buildDate = bridge.getBuildDate();
      this.engineVersions = bridge.getEngineVersions();
    } catch (err) {
      this.versionError = $r('app.string.about_version_error');
      hilog.error(0x0001, TAG,
        'fetchNativeInfo failed: %{private}s', errText(err));
    } finally {
      this.isLoadingVersion = false;
    }
    // Separate from the bridge read above: a missing API level must not take
    // down the version row, and vice versa.
    try {
      // targetVersion is the *encoded* SDK version, not the API level: an
      // API 24 / 6.1.1 build reports 60101024 (<major><minor><patch><api>).
      // Shown raw it read 'API 60101024' on device — the API level is the
      // last three digits.
      const targetVersion: number = bundleManager.getBundleInfoForSelfSync(
        bundleManager.BundleFlag.GET_BUNDLE_INFO_DEFAULT).targetVersion;
      this.targetApi = targetVersion > 999 ? targetVersion % 1000 : targetVersion;
    } catch (err) {
      hilog.error(0x0001, TAG,
        'targetVersion read failed: %{private}s', errText(err));
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
        // No version number is shown here on purpose: the only copy in the
        // ArkTS layer would be a hardcoded string that drifts every release
        // (it read '1.0.1' while the shipped build was 1.0.2). The native
        // bridge owns the version; if it can't be read, say so.
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

      // Build info — date comes from the native build (__DATE__); '—' only
      // when the bridge failed, which the version error above already flags.
      Text($r('app.string.about_build', AppConstants.BUILD_MILESTONE,
        this.buildDate.length > 0 ? this.buildDate : '—'))
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
        // Versions come from the shipped binaries via getEngineVersions(), not
        // from literals here — those read '4.1.0' / '3.0' long after the deps
        // moved on. '—' means the bridge could not read them (see versionError).
        this.BuildLicenseRow('libtransmission', this.engineVersions.transmission, 'GPL-2.0 / MIT');
        this.BuildDivider();
        this.BuildLicenseRow('OpenSSL', this.engineVersions.openssl, 'Apache-2.0');
        this.BuildDivider();
        this.BuildLicenseRow('libcurl', this.engineVersions.curl, 'curl License');
        this.BuildDivider();
        this.BuildLicenseRow('libevent', this.engineVersions.libevent, 'BSD-3-Clause');
        this.BuildDivider();
        this.BuildLicenseRow('ArkUI Framework',
          this.targetApi > 0 ? `API ${this.targetApi}` : '', 'HarmonyOS SDK EULA');
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
        // 'v' only for bare numbers; 'API 24', '—' and the libevent
        // '2.1.13-stable' style are already labelled.
        Text(version.length === 0 ? '—'
          : (/^\d/.test(version) ? `v${version}` : version))
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
