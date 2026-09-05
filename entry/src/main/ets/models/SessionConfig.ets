// transmissionbtm — SessionConfig for native sessionStart()

export enum EncryptionMode {
  ALLOW = 'allow',
  PREFER = 'prefer',
  REQUIRE = 'require',
}

export interface SessionConfig {
  downloadDir: string;
  incompleteDir: string;
  peerPort: number;
  rpcPort: number;
  rpcWhitelist: string;
  rpcAuthentication: boolean;
  rpcUsername: string;
  rpcPassword: string;
  speedLimitDown: number;
  speedLimitUp: number;
  speedLimitDownEnabled: boolean;
  speedLimitUpEnabled: boolean;
  altSpeedDown: number;
  altSpeedUp: number;
  altSpeedEnabled: boolean;
  altSpeedTimeBegin: number;
  altSpeedTimeEnd: number;
  altSpeedDay: number;
  peerLimitGlobal: number;
  peerLimitPerTorrent: number;
  encryptionMode: EncryptionMode;
  utpEnabled: boolean;
  pexEnabled: boolean;
  dhtEnabled: boolean;
  lpdEnabled: boolean;
  startAddedTorrents: boolean;
  renamePartialFiles: boolean;
  trashOriginalTorrentFile: boolean;
  proxyEnabled: boolean;
  proxyUrl: string;
  proxyPort: number;
  proxyAuthRequired: boolean;
  proxyUsername: string;
  proxyPassword: string;
  blocklistEnabled: boolean;
  blocklistUrl: string;
  seedRatioLimit: number;
  seedRatioLimited: boolean;
  idleSeedingLimit: number;
  idleSeedingLimitEnabled: boolean;
// RPC opt-in gate — Settings exposes a toggle for enableRpc (JSON-RPC control
// endpoint) and a whitelist toggle/address edit. Off by default (no bundled web
// UI), so 9091 only opens once the user flips the enable RPC toggle.
  enableRpc: boolean;
  enableRpcWhitelist: boolean;
  settingsDir: string;
}

export function defaultSessionConfig(): SessionConfig {
  return {
    downloadDir: '/storage/downloads',
    incompleteDir: '/storage/downloads/.incomplete',
    peerPort: 51413, rpcPort: 9091,
    rpcWhitelist: '127.0.0.1', rpcAuthentication: true,
    rpcUsername: '', rpcPassword: '',
    speedLimitDown: 0, speedLimitUp: 0,
    speedLimitDownEnabled: false, speedLimitUpEnabled: false,
    altSpeedDown: 50, altSpeedUp: 50, altSpeedEnabled: false,
    altSpeedTimeBegin: 480, altSpeedTimeEnd: 1080, altSpeedDay: 127,
    peerLimitGlobal: 200, peerLimitPerTorrent: 50,
    encryptionMode: EncryptionMode.PREFER,
    utpEnabled: true, pexEnabled: true, dhtEnabled: true, lpdEnabled: false,
    startAddedTorrents: true, renamePartialFiles: true, trashOriginalTorrentFile: false,
    proxyEnabled: false, proxyUrl: '', proxyPort: 0,
    proxyAuthRequired: false, proxyUsername: '', proxyPassword: '',
    blocklistEnabled: false, blocklistUrl: '',
    seedRatioLimit: 2.0, seedRatioLimited: false,
    idleSeedingLimit: 30, idleSeedingLimitEnabled: false,
    // RPC listener is disabled by default (opt-in): no web UI exists, so 9091
    // only opens after the user flips enableRpc. When enabled, auth defaults ON
    // (fail-safe) and the bind address is honored by the engine (loopback
    // 127.0.0.1 by default; the user sets 0.0.0.0 for LAN). See docs/11 A2/D7.
    enableRpc: false, enableRpcWhitelist: true,
    settingsDir: '/storage/transmission',
  };
}

// Transmission's RPC whitelist is a glob list (tr_wildmat, `*` wildcard) — NOT
// CIDR. A user naturally types a subnet as CIDR ("172.16.1.1/24"); if passed
// literally it matches nothing, so any LAN client (e.g. a phone on 172.16.1.x)
// gets HTTP 403 "Unauthorized IP Address" even though it's in the intended LAN.
// Translate a byte-aligned CIDR token to the equivalent glob so the engine
// actually matches it. Non-CIDR tokens and non-byte-aligned prefixes pass
// through untouched (a /0 or /25 can't be expressed as a safe byte-aligned
// glob, so we leave them as-is rather than over-open the whitelist).
function cidrToGlob(token: string): string {
  const t = token.trim();
  const m = /^([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})\/([0-9]{1,2})$/.exec(t);
  if (!m) { return t; }
  const octets: number[] = [m[1], m[2], m[3], m[4]].map((n: string) => Number(n));
  if (octets.some((n: number) => n > 255)) { return t; }
  const len = Number(m[5]);
  if (len === 0 || len % 8 !== 0) { return t; } // only /8 /16 /24 /32 exact
  const full = Math.floor(len / 8);
  const parts: string[] = octets.slice(0, full).map((n: number) => String(n));
  // A trailing `*` matches any remaining octets (tr_wildmat's `*` spans dots),
  // so /8 → "10.*", /16 → "192.168.*", /24 → "172.16.1.*", /32 → exact IP.
  if (full < 4) { parts.push('*'); }
  return parts.join('.');
}

/**
 * Normalize a stored RPC whitelist string into the glob form Transmission
 * understands. Split on the engine's `" ,;"` delimiters, translate each CIDR
 * token, and rejoin. "127.0.0.1,172.16.1.1/24" → "127.0.0.1,172.16.1.*".
 * Applied when a SessionConfig is read from Preferences, covering both the
 * session-start native args and the live re-apply path.
 */
export function normalizeRpcWhitelist(raw: string): string {
  if (!raw) { return raw; }
  return raw.split(/[ ,;]+/)
    .map(cidrToGlob)
    .filter((t: string) => t.length > 0)
    .join(',');
}
