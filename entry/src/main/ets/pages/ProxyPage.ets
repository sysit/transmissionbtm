// transmissionbtm — ProxyPage (M6)
//
// HTTP/HTTPS proxy configuration for all BitTorrent traffic.
// When proxy is enabled, the native engine routes connections
// through the configured host:port. Optional authentication.
//
// All settings persist via PreferencesManager through the
// M2 components (prefKey wiring).

import { promptAction } from '@kit.ArkUI';
import { Colors, FontSize, Limits, Spacing } from '../utils/constants';
import { errText } from '../utils/errors';
import { SettingsGroup } from '../components/settings/SettingsGroup';
import { SettingsErrorBanner } from '../components/settings/SettingsErrorBanner';
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
  @State loadError: ResourceStr = '';

  aboutToAppear(): void {
    this.loadPreferences();
  }

  private async loadPreferences(): Promise<void> {
    this.isLoading = true;
    this.loadError = '';
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

      // D1: getters return defaults on failure — report it once instead of
      // rendering defaults as saved values.
      if (pm.consumeError() !== '') {
        this.loadError = $r('app.string.settings_load_error');
      }
      // D7: a stored envelope that no longer decrypts would otherwise show as
      // an empty password with no explanation. Clear the field and ask.
      if (pm.consumePasswordLost()) {
        this.proxyPassword = '';
        promptAction.showToast({ message: $r('app.string.proxy_password_reentry') });
      }
    } catch (err) {
      hilog.error(0x0001, TAG,
        'loadPreferences failed: %{private}s', errText(err));
      // A throw here means the rows below show @State defaults, not the stored
      // config — say so instead of rendering them as if they were saved.
      this.loadError = $r('app.string.settings_load_error');
    } finally {
      this.isLoading = false;
    }
  }

  build() {
    Column() {
      // Page header
      Text($r('app.string.proxy_title'))
        .fontSize(FontSize.XL)
        .fontWeight(FontWeight.Bold)
        .fontColor(Colors.TEXT)
        .width('100%')
        .padding({
          left: Spacing.LG,
          top: Spacing.LG,
          bottom: Spacing.LG,
        });

      if (this.loadError) {
        SettingsErrorBanner({ error: this.loadError });
      }

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
      Text($r('app.string.proxy_loading'))
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
        SettingsGroup({ title: $r('app.string.proxy_section') }) {
          ToggleSetting({
            label: $r('app.string.proxy_enable'),
            description: $r('app.string.proxy_enable_desc'),
            prefKey: PrefKeys.PROXY_ENABLED,
            checked: $proxyEnabled,
          });

          if (this.proxyEnabled) {
            this.BuildDivider();

            // Host with validation hint
            Column() {
              EditSetting({
                label: $r('app.string.proxy_host'),
                hint: 'proxy.example.com',
                prefKey: PrefKeys.PROXY_URL,
                value: $proxyUrl,
                // D6: a host the engine cannot resolve is only discovered at
                // connect time — reject obvious junk at the input instead.
                validate: (text: string): boolean => {
                  const host = text.trim();
                  // Hostname, IPv4, or bracketed IPv6 — reject spaces, '/',
                  // '://' and other junk that can only fail at connect time.
                  return host === '' || /^[a-zA-Z0-9.\-\[\]:]+$/.test(host);
                },
              });
            }
            .width('100%');

            // Port with validation hint
            Column() {
              EditSetting({
                label: $r('app.string.proxy_port'),
                hint: '8080',
                prefKey: PrefKeys.PROXY_PORT,
                value: $proxyPort,
                inputType: InputType.Number,
                valueType: 'number',
                minValue: Limits.PORT_MIN,
                maxValue: Limits.PORT_MAX,
              });
            }
            .width('100%');

            this.BuildDivider();

            ToggleSetting({
              label: $r('app.string.settings_authentication'),
              description: $r('app.string.proxy_auth_desc'),
              prefKey: PrefKeys.PROXY_AUTH_REQUIRED,
              checked: $proxyAuthRequired,
            });

            if (this.proxyAuthRequired) {
              EditSetting({
                label: $r('app.string.settings_username'),
                hint: 'user',
                prefKey: PrefKeys.PROXY_USERNAME,
                value: $proxyUsername,
              });

              EditSetting({
                label: $r('app.string.settings_password'),
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
          Text($r('app.string.proxy_disabled'))
            .fontSize(FontSize.CAPTION)
            .fontColor(Colors.TEXT_TERTIARY)
            .margin({ top: Spacing.XXL });
          Text($r('app.string.proxy_disabled_hint'))
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
