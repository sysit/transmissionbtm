// transmissionbtm — ProxyPage (M6)
//
// HTTP/HTTPS proxy configuration for all BitTorrent traffic.
// When proxy is enabled, the native engine routes connections
// through the configured host:port. Optional authentication.
//
// All settings persist via PreferencesManager through the
// M2 components (prefKey wiring).

import { Colors, FontSize, Spacing } from '../utils/constants';
import { SettingsGroup } from '../components/settings/SettingsGroup';
import { ToggleSetting } from '../components/settings/ToggleSetting';
import { EditSetting } from '../components/settings/EditSetting';
import { PreferencesManager, PrefKeys } from '../models/Preferences';
import { defaultSessionConfig } from '../models/SessionConfig';
import { hilog } from '@kit.PerformanceAnalysisKit';

const TAG = 'ProxyPage';

@Component
export struct ProxyPage {
  @State isLoading: boolean = true;
  @State proxyEnabled: boolean = defaultSessionConfig().proxyEnabled;
  @State proxyUrl: string = defaultSessionConfig().proxyUrl;
  @State proxyPort: string = String(defaultSessionConfig().proxyPort);
  @State proxyAuthRequired: boolean = defaultSessionConfig().proxyAuthRequired;
  @State proxyUsername: string = defaultSessionConfig().proxyUsername;
  @State proxyPassword: string = defaultSessionConfig().proxyPassword;

  aboutToAppear(): void {
    this.loadPreferences();
  }

  private async loadPreferences(): Promise<void> {
    this.isLoading = true;
    try {
      const pm = PreferencesManager.getInstance();

      this.proxyEnabled = await pm.getBoolean(
        PrefKeys.PROXY_ENABLED, this.proxyEnabled);
      this.proxyUrl = await pm.getString(
        PrefKeys.PROXY_URL, this.proxyUrl);
      this.proxyPort = String(await pm.getInt(
        PrefKeys.PROXY_PORT, Number(this.proxyPort)));
      this.proxyAuthRequired = await pm.getBoolean(
        PrefKeys.PROXY_AUTH_REQUIRED, this.proxyAuthRequired);
      this.proxyUsername = await pm.getString(
        PrefKeys.PROXY_USERNAME, this.proxyUsername);
      this.proxyPassword = await pm.getString(
        PrefKeys.PROXY_PASSWORD, this.proxyPassword);
    } catch (err) {
      hilog.error(0x0001, TAG,
        'loadPreferences failed: %{private}s', String(err));
    } finally {
      this.isLoading = false;
    }
  }

  build() {
    Column() {
      // Page header
      Text('Proxy')
        .fontSize(FontSize.XL)
        .fontWeight(FontWeight.Bold)
        .fontColor(Colors.TEXT)
        .width('100%')
        .padding({
          left: Spacing.LG,
          top: Spacing.LG,
          bottom: Spacing.LG,
        });

      if (this.isLoading) {
        this.BuildLoadingState();
      } else {
        this.BuildContent();
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Colors.BG);
  }

  @Builder
  BuildLoadingState() {
    Column() {
      LoadingProgress()
        .width(40)
        .height(40)
        .color(Colors.DOWNLOAD);
      Text('Loading proxy settings...')
        .fontSize(FontSize.CAPTION)
        .fontColor(Colors.TEXT_SECONDARY)
        .margin({ top: Spacing.MD });
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center);
  }

  @Builder
  BuildContent() {
    Column() {
      Column() {
        SettingsGroup({ title: 'HTTP Proxy' }) {
          ToggleSetting({
            label: 'Enable proxy',
            description: 'Route BitTorrent traffic through proxy',
            prefKey: PrefKeys.PROXY_ENABLED,
            checked: $proxyEnabled,
          });

          if (this.proxyEnabled) {
            this.BuildDivider();

            // Host with validation hint
            Column() {
              EditSetting({
                label: 'Host',
                hint: 'proxy.example.com',
                prefKey: PrefKeys.PROXY_URL,
                value: $proxyUrl,
              });
            }
            .width('100%');

            // Port with validation hint
            Column() {
              EditSetting({
                label: 'Port',
                hint: '8080',
                prefKey: PrefKeys.PROXY_PORT,
                value: $proxyPort,
                inputType: InputType.Number,
                valueType: 'number',
              });
            }
            .width('100%');

            this.BuildDivider();

            ToggleSetting({
              label: 'Authentication',
              description: 'Proxy requires username and password',
              prefKey: PrefKeys.PROXY_AUTH_REQUIRED,
              checked: $proxyAuthRequired,
            });

            if (this.proxyAuthRequired) {
              EditSetting({
                label: 'Username',
                hint: 'user',
                prefKey: PrefKeys.PROXY_USERNAME,
                value: $proxyUsername,
              });

              EditSetting({
                label: 'Password',
                hint: 'password',
                prefKey: PrefKeys.PROXY_PASSWORD,
                value: $proxyPassword,
                inputType: InputType.Password,
              });
            }
          }
        }
      }
      .padding({
        left: Spacing.LG,
        right: Spacing.LG,
      });

      // Inactive state hint
      if (!this.proxyEnabled) {
        Column() {
          Text('🔒  Proxy is disabled')
            .fontSize(FontSize.CAPTION)
            .fontColor(Colors.TEXT_TERTIARY)
            .margin({ top: Spacing.XXL });
          Text('Enable proxy above to configure')
            .fontSize(FontSize.SMALL)
            .fontColor(Colors.TEXT_TERTIARY)
            .margin({ top: Spacing.SM });
        }
        .width('100%')
        .alignItems(HorizontalAlign.Center);
      }

      // Spacer
      Column().layoutWeight(1);
    }
    .layoutWeight(1)
    .width('100%');
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
