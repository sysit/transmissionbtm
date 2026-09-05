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
  static readonly APP_VERSION: string = '1.0.1';
  static readonly BUILD_DATE: string = '2026-09-05';
  static readonly BUILD_MILESTONE: string = 'Release';
  static readonly RPC_DEFAULT_PORT: number = 9091;
  static readonly PEER_DEFAULT_PORT: number = 51413;
  static readonly ENGINE_VERSION: string = 'Transmission 4.1.0 + OpenSSL + libcurl + libevent';
  static readonly PLATFORM: string = 'HarmonyOS NEXT';
  static readonly ARCH: string = 'arm64-v8a';
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
