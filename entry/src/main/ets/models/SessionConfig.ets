// transmissionhm — SessionConfig for native sessionStart()

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
  // Session-critical (transmissionbtc, not exposed in UI)
  enableRpc: boolean;
  enableRpcWhitelist: boolean;
  increaseSoBuf: boolean;
  enableSeqDownload: boolean;
  settingsDir: string;
}

export function defaultSessionConfig(): SessionConfig {
  return {
    downloadDir: '/storage/downloads',
    incompleteDir: '/storage/downloads/.incomplete',
    peerPort: 51413, rpcPort: 9091,
    rpcWhitelist: '127.0.0.1', rpcAuthentication: false,
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
    // RPC listener is disabled by default: no web UI exists (ENABLE_WEB=OFF),
    // so binding 9091 only exposes an unauthenticated control surface.
    // See docs/11 A2. D7 (web control) would re-enable with auth.
    enableRpc: false, enableRpcWhitelist: true,
    increaseSoBuf: true, enableSeqDownload: false,
    settingsDir: '/storage/transmission',
  };
}
