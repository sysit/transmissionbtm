import { describe, it, expect } from 'vitest';
import { defaultSessionConfig, EncryptionMode } from '../entry/src/main/ets/models/SessionConfig.ets';

describe('EncryptionMode', () => {
  it('has three modes as string values', () => {
    expect(EncryptionMode.ALLOW).toBe('allow');
    expect(EncryptionMode.PREFER).toBe('prefer');
    expect(EncryptionMode.REQUIRE).toBe('require');
  });
});

describe('defaultSessionConfig', () => {
  const cfg = defaultSessionConfig();

  it('has correct download defaults', () => {
    expect(cfg.downloadDir).toBe('/storage/downloads');
    expect(cfg.incompleteDir).toBe('/storage/downloads/.incomplete');
    expect(cfg.startAddedTorrents).toBe(true);
    expect(cfg.renamePartialFiles).toBe(true);
    expect(cfg.trashOriginalTorrentFile).toBe(false);
  });

  it('has correct network defaults', () => {
    expect(cfg.peerPort).toBe(51413);
    expect(cfg.rpcPort).toBe(9091);
    expect(cfg.utpEnabled).toBe(true);
    expect(cfg.pexEnabled).toBe(true);
    expect(cfg.dhtEnabled).toBe(true);
    expect(cfg.lpdEnabled).toBe(false);
  });

  it('defaults to PREFER encryption', () => {
    expect(cfg.encryptionMode).toBe(EncryptionMode.PREFER);
  });

  it('has correct RPC defaults', () => {
    // RPC listener is off by default: no web UI (ENABLE_WEB=OFF), so binding
    // 9091 only exposes an unauthenticated control surface (SessionConfig.ets).
    expect(cfg.enableRpc).toBe(false);
    expect(cfg.enableRpcWhitelist).toBe(true);
    expect(cfg.rpcWhitelist).toBe('127.0.0.1');
    expect(cfg.rpcAuthentication).toBe(false);
    expect(cfg.rpcUsername).toBe('');
    expect(cfg.rpcPassword).toBe('');
  });

  it('has correct speed limit defaults', () => {
    expect(cfg.speedLimitDown).toBe(0);
    expect(cfg.speedLimitUp).toBe(0);
    expect(cfg.speedLimitDownEnabled).toBe(false);
    expect(cfg.speedLimitUpEnabled).toBe(false);
  });

  it('has correct alt speed defaults', () => {
    expect(cfg.altSpeedDown).toBe(50);
    expect(cfg.altSpeedUp).toBe(50);
    expect(cfg.altSpeedEnabled).toBe(false);
    expect(cfg.altSpeedTimeBegin).toBe(480);
    expect(cfg.altSpeedTimeEnd).toBe(1080);
    expect(cfg.altSpeedDay).toBe(127);
  });

  it('has correct peer limits', () => {
    expect(cfg.peerLimitGlobal).toBe(200);
    expect(cfg.peerLimitPerTorrent).toBe(50);
  });

  it('has correct proxy defaults', () => {
    expect(cfg.proxyEnabled).toBe(false);
    expect(cfg.proxyUrl).toBe('');
    expect(cfg.proxyPort).toBe(0);
    expect(cfg.proxyAuthRequired).toBe(false);
  });

  it('has correct blocklist defaults', () => {
    expect(cfg.blocklistEnabled).toBe(false);
    expect(cfg.blocklistUrl).toBe('');
  });

  it('has correct seed ratio defaults', () => {
    expect(cfg.seedRatioLimit).toBe(2.0);
    expect(cfg.seedRatioLimited).toBe(false);
  });

  it('has correct idle seeding defaults', () => {
    expect(cfg.idleSeedingLimit).toBe(30);
    expect(cfg.idleSeedingLimitEnabled).toBe(false);
  });

  it('has correct advanced defaults', () => {
    expect(cfg.increaseSoBuf).toBe(true);
    expect(cfg.enableSeqDownload).toBe(false);
    expect(cfg.settingsDir).toBe('/storage/transmission');
  });

  it('returns all required keys', () => {
    const keys = Object.keys(cfg);
    expect(keys.length).toBeGreaterThanOrEqual(35);
    expect('downloadDir' in cfg).toBe(true);
    expect('encryptionMode' in cfg).toBe(true);
    expect('peerPort' in cfg).toBe(true);
  });
});
