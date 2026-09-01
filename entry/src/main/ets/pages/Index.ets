// transmissionbtm — MainPage (M6)
//
// App shell with Navigation + bottom tab bar.
// Four tabs: Downloads, Settings, Proxy, About.
//
// Architecture:
//   Navigation (host)
//   └── Tabs (barPosition: End = bottom tab bar)
//       ├── TabContent → DownloadsPage
//       ├── TabContent → SettingsPage
//       ├── TabContent → ProxyPage
//       └── TabContent → AboutPage

import { Colors, FontSize, Spacing, Duration } from '../utils/constants';
import { DownloadsPage } from './DownloadsPage';
import { SettingsPage } from './SettingsPage';
import { ProxyPage } from './ProxyPage';
import { AboutPage } from './AboutPage';
import { PreferencesManager, PrefKeys } from '../models/Preferences';
import { PrivacyDialog } from '../components/privacy/PrivacyDialog';

@Entry
@Component
struct Index {
  @Provide('navPathStack') navPathStack: NavPathStack = new NavPathStack();
  @State currentTab: number = 0;
  @State showPrivacyDialog: boolean = false;

  async aboutToAppear(): Promise<void> {
    // Wait for the preferences store (init is fire-and-forget in EntryAbility).
    try {
      await PreferencesManager.getInstance().waitReady();
    } catch (err) {
      // Non-fatal: fall through and default to showing the gate.
    }
    let accepted = false;
    try {
      accepted = await PreferencesManager.getInstance()
        .getBoolean(PrefKeys.PRIVACY_ACCEPTED, false);
    } catch (err) {
      // Non-fatal: default to showing the gate.
      accepted = false;
    }
    // Show the privacy gate only on first launch (until the user accepts).
    this.showPrivacyDialog = !accepted;
  }

  build() {
    Stack() {
      Navigation(this.navPathStack) {
      Column() {
        Tabs({ index: this.currentTab }) {
          TabContent() {
            DownloadsPage()
          }
          .tabBar(this.TabDownloads);

          TabContent() {
            SettingsPage()
          }
          .tabBar(this.TabSettings);

          TabContent() {
            ProxyPage()
          }
          .tabBar(this.TabProxy);

          TabContent() {
            AboutPage()
          }
          .tabBar(this.TabAbout);
        }
        .barPosition(BarPosition.End)
        .barHeight(56)
        .barBackgroundColor(Colors.SURFACE)
        .animationDuration(Duration.NORMAL)
        .onChange((index: number) => {
          this.currentTab = index;
        })
        .width('100%')
        .height('100%')
        .backgroundColor(Colors.BG);
      }
      .width('100%')
      .height('100%');
    }
    .hideTitleBar(true)
    .mode(NavigationMode.Stack)
    .backgroundColor(Colors.BG);

      if (this.showPrivacyDialog) {
        PrivacyDialog({ show: $showPrivacyDialog })
      }
    }
    .width('100%')
    .height('100%')
  }

  // ═══════════════════════════════════════════════════════════════
  // Per-tab @Builder wrappers (required by ArkTS tabBar contract;
  // each must be a distinct parameterless @Builder reference.)
  // ═══════════════════════════════════════════════════════════════

  @Builder
  TabDownloads() {
    this.BuildTabContent($r('app.string.tab_downloads'), '⬇', 0);
  }

  @Builder
  TabSettings() {
    this.BuildTabContent($r('app.string.tab_settings'), '⚙', 1);
  }

  @Builder
  TabProxy() {
    this.BuildTabContent($r('app.string.tab_proxy'), '🔒', 2);
  }

  @Builder
  TabAbout() {
    this.BuildTabContent($r('app.string.tab_about'), 'ℹ', 3);
  }

  // ═══════════════════════════════════════════════════════════════
  // Shared tab bar content builder
  // ═══════════════════════════════════════════════════════════════

  @Builder
  BuildTabContent(title: ResourceStr, icon: string, tabIndex: number) {
    Column() {
      Text(icon)
        .fontSize(this.currentTab === tabIndex ? 20 : 18)
        .fontColor(
          this.currentTab === tabIndex ? Colors.DOWNLOAD : Colors.TEXT_TERTIARY
        )
        .animation({
          duration: Duration.FAST,
          curve: Curve.EaseOut,
        });

      Text(title)
        .fontSize(10)
        .fontColor(
          this.currentTab === tabIndex ? Colors.DOWNLOAD : Colors.TEXT_TERTIARY
        )
        .fontWeight(
          this.currentTab === tabIndex ? FontWeight.Medium : FontWeight.Normal
        )
        .margin({ top: 2 })
        .animation({
          duration: Duration.FAST,
          curve: Curve.EaseOut,
        });
    }
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .padding({
      top: Spacing.SM,
      bottom: Spacing.SM,
    });
  }
}
