// transmissionbtm — Design token constants (ArkTS compatible)
//
// Design tokens drive all visual styling. Components reference these
// rather than hardcoding values, enabling consistent theming.
// Values match the design/demo.html prototype.

// ═══════════════════════════════════════════════════════════════════
// Colors
// ═══════════════════════════════════════════════════════════════════

export class Colors {
  // Core surfaces
  static readonly BG: string = '#0b0d10';
  static readonly SURFACE: string = '#181b21';
  static readonly CARD: string = '#1e2129';
  static readonly ELEVATED: string = '#252833';

  // Text
  static readonly TEXT: string = '#e4e6ec';
  static readonly TEXT_SECONDARY: string = '#9ca0ab';
  static readonly TEXT_TERTIARY: string = '#6b6f7a';

  // Semantic
  static readonly DOWNLOAD: string = '#3b82f6';
  static readonly SEED: string = '#22c55e';
  static readonly PAUSED: string = '#f59e0b';
  static readonly ERROR: string = '#ef4444';
  static readonly ACCENT: string = '#6366f1';

  // Aliases for convenience
  static readonly QUEUED: string = '#6366f1';
  static readonly ACTIVE: string = '#3b82f6';
  static readonly COMPLETE: string = '#22c55e';

  // Decorative
  static readonly PROGRESS_BG: string = '#1e293b';
  static readonly BORDER: string = '#2a2d37';
  static readonly DIVIDER: string = '#1f222a';
}

// ═══════════════════════════════════════════════════════════════════
// Typography
// ═══════════════════════════════════════════════════════════════════

export class FontSize {
  // Spec-standard names
  static readonly SM: number = 11;
  static readonly MD: number = 13;
  static readonly LG: number = 16;
  static readonly XL: number = 20;
  static readonly XXL: number = 28;

  // Backward-compatible aliases (used by M2 components)
  static readonly HERO: number = 28;
  static readonly TITLE: number = 20;
  static readonly HEADLINE: number = 17;
  static readonly BODY: number = 15;
  static readonly CAPTION: number = 13;
  static readonly SMALL: number = 11;
}

// ═══════════════════════════════════════════════════════════════════
// Spacing
// ═══════════════════════════════════════════════════════════════════

export class Spacing {
  // Spec-standard names
  static readonly SM: number = 8;
  static readonly MD: number = 12;
  static readonly LG: number = 16;
  static readonly XL: number = 24;
  static readonly XXL: number = 32;

  // Backward-compatible aliases
  static readonly XS: number = 4;
  static readonly SECTION: number = 32;
}

// ═══════════════════════════════════════════════════════════════════
// Border Radius
// ═══════════════════════════════════════════════════════════════════

export class Radius {
  // Spec-standard names
  static readonly SM: number = 4;
  static readonly MD: number = 8;
  static readonly LG: number = 12;
  static readonly XL: number = 16;
}

// ═══════════════════════════════════════════════════════════════════
// Animation Durations (milliseconds)
// ═══════════════════════════════════════════════════════════════════

export class Duration {
  static readonly FAST: number = 150;
  static readonly NORMAL: number = 300;
  static readonly SLOW: number = 500;
}

// ═══════════════════════════════════════════════════════════════════
// Application Constants
// ═══════════════════════════════════════════════════════════════════

export class AppConstants {
  static readonly APP_NAME: string = 'transmissionbtm';
  // Public target the torrent "Save to Files" action exports into (picker
  // default); shown read-only on the Settings page.
  static readonly SANDBOX_EXPORT_DIR: string = 'Download/com.9bt.transmissionbtm';
  // No APP_VERSION, BUILD_DATE or ENGINE_VERSION here on purpose: hardcoded
  // copies drift silently (APP_VERSION read '1.0.1' while 1.0.2 shipped;
  // BUILD_DATE read '2026-09-29' while 1.0.3 shipped in November;
  // ENGINE_VERSION still said 'Transmission 4.1.0' after the 4.1.4 bump).
  // The native bridge owns all three — getVersion()/getBuildDate()/
  // getEngineVersions() in napi_init.cpp.
  static readonly BUILD_MILESTONE: string = 'Release';
  static readonly PEER_DEFAULT_PORT: number = 51413;
  static readonly PLATFORM: string = 'HarmonyOS NEXT';
  static readonly ARCH: string = 'arm64-v8a';
}

// ═══════════════════════════════════════════════════════════════════
// Interaction Feedback
// ═══════════════════════════════════════════════════════════════════

/**
 * Shared press feedback for every tappable element. ArkUI's native
 * clickEffect: while pressed the node scales down and glows, so taps on
 * cards / rows / plain-Text buttons are visibly acknowledged. LIGHT keeps
 * big cards from visually "sinking" under the finger; scale 0.92 is enough
 * to read as a press without looking like a mis-render.
 */
export const CLICK_EFFECT: ClickEffect = {
  level: ClickEffectLevel.LIGHT,
  scale: 0.92,
};

// ═══════════════════════════════════════════════════════════════════
// Setting Input Bounds
// ═══════════════════════════════════════════════════════════════════

/**
 * Bounds enforced by EditSetting before a value is persisted (D4). Values
 * outside these ranges are meaningless to libtransmission: port 0 / >65535 is
 * rejected by the engine, and the alt-speed minute/day fields index fixed-size
 * arrays.
 */
export class Limits {
  static readonly PORT_MIN: number = 1;
  static readonly PORT_MAX: number = 65535;
  /** KB/s — native speed limits are KB/s, matching the settings hints. */
  static readonly SPEED_KBPS_MAX: number = 1000000;
  static readonly MINUTE_OF_DAY_MAX: number = 1439;
  static readonly WEEKDAY_MASK_MAX: number = 127;
  static readonly PEER_LIMIT_MAX: number = 10000;
  static readonly PEERS_PER_TORRENT_MAX: number = 1000;
  static readonly SEED_RATIO_MAX: number = 10000;
}

// ═══════════════════════════════════════════════════════════════════
// Torrent Status Codes
// ═══════════════════════════════════════════════════════════════════

export enum TorrentAddResult {
  OK = 0,
  PARSE_ERR = 1,
  DUPLICATE = 2,
  OK_DELETE = 3,
}
