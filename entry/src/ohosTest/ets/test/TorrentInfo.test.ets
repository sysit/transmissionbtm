// transmissionbtm — TorrentInfo domain model unit tests
//
// Tests cover:
//   - TorrentStatus (5-value enum matching transmissionbtc TorrentStat.Status)
//   - TorrentError enum values
//   - fromStatArray with the 10-element native stat array layout
//   - fromNativeJson parsing of the native text format
//   - toJSON serialization
//   - Status query methods (isActive, isStopped, etc.)
//   - getStatusString and getStatusColor display helpers
//
// Native stat array index mapping (from TorrentInfo.fromStatArray,
// matching transmissionbtc torrent.cc:718-777):
//   arr[0] = torrentId       → id
//   arr[1] = status (0-4)    → TorrentStatus
//   arr[2] = progress (0-100)→ percentComplete (÷100)
//   arr[3] = totalLength     → totalSize
//   arr[4] = remainingLength → haveValid = totalLength - remainingLength
//   arr[5] = uploadedLength  → uploadedEver
//   arr[6] = peersUp         → peersConnected
//   arr[7] = peersDown       → peersTotal
//   arr[8] = speedUp         → rateUpload
//   arr[9] = speedDown       → rateDownload
//
// Status values (matching transmissionbtc TorrentStat.Status):
//   STOPPED=0, CHECK=1, DOWNLOAD=2, SEED=3, ERROR=4
//
// Error values (matching libtransmission tr_stat_errtype):
//   OK=0, TRACKER_WARNING=1, TRACKER_ERROR=2, LOCAL_ERROR=3

import { describe, it, expect } from '@ohos/hypium';
import {
  TorrentInfo,
  TorrentStatus,
  TorrentError,
  TorrentInfoJSON,
} from '../../../main/ets/models/TorrentInfo';

export default function torrentInfoTest(): void {
  // ═══════════════════════════════════════════════════════════════════
  // TorrentStatus enum (5 values, matching transmissionbtc)
  // ═══════════════════════════════════════════════════════════════════
  describe('TorrentStatus', () => {
    it('TorrentStatus_hasFiveValues_matchingTransmissionbtc', 0, (): void => {
      expect(TorrentStatus.STOPPED).assertEqual(0);
      expect(TorrentStatus.CHECK).assertEqual(1);
      expect(TorrentStatus.DOWNLOAD).assertEqual(2);
      expect(TorrentStatus.SEED).assertEqual(3);
      expect(TorrentStatus.ERROR).assertEqual(4);
    });

    it('TorrentStatus_waitStatesConsolidated', 0, (): void => {
      // The native layer consolidates CHECK_WAIT→CHECK,
      // DOWNLOAD_WAIT→DOWNLOAD, SEED_WAIT→SEED.
      // There are no separate wait-state enum values.
      expect(TorrentStatus.CHECK).assertEqual(1);
      expect(TorrentStatus.DOWNLOAD).assertEqual(2);
      expect(TorrentStatus.SEED).assertEqual(3);
    });
  });

  // ═══════════════════════════════════════════════════════════════════
  // TorrentError enum
  // ═══════════════════════════════════════════════════════════════════
  describe('TorrentError', () => {
    it('TorrentError_values_matchSpec', 0, (): void => {
      expect(TorrentError.OK).assertEqual(0);
      expect(TorrentError.TRACKER_WARNING).assertEqual(1);
      expect(TorrentError.TRACKER_ERROR).assertEqual(2);
      expect(TorrentError.LOCAL_ERROR).assertEqual(3);
    });
  });

  // ═══════════════════════════════════════════════════════════════════
  // fromStatArray — parses the native 10-element number array
  // ═══════════════════════════════════════════════════════════════════
  describe('fromStatArray', () => {
    it('fromStatArray_downloading_correctFields', 0, (): void => {
      // 10-element array: [id, status, progress%, totalLen, remainingLen,
      //                    uploadedLen, peersUp, peersDown, speedUp, speedDown]
      // status=2=DOWNLOAD, progress=72%, totalLen=1000000, remainingLen=280000
      const nativeStat: number[] = [
        42, 2, 72, 1000000, 280000,
        50000, 8, 12, 50000, 2000000
      ];
      const info: TorrentInfo = TorrentInfo.fromStatArray(
        nativeStat, 'ubuntu.iso', 'abc123'
      );

      expect(info.id).assertEqual(42);
      expect(info.name).assertEqual('ubuntu.iso');
      expect(info.hashString).assertEqual('abc123');
      expect(info.status).assertEqual(TorrentStatus.DOWNLOAD);
      // percentComplete = progress/100 = 72/100
      expect(info.percentComplete).assertEqual(0.72);
      expect(info.totalSize).assertEqual(1000000);
      // haveValid = totalLen - remainingLen = 1000000 - 280000 = 720000
      expect(info.haveValid).assertEqual(720000);
      // percentDone = haveValid / totalSize = 720000 / 1000000
      expect(info.percentDone).assertEqual(0.72);
      expect(info.uploadedEver).assertEqual(50000);
      // downloadedEver = haveValid (bytes on disk) — the brief stat carries no
      // lifetime downloadedEver (codex P2 fix, Task #104)
      expect(info.downloadedEver).assertEqual(720000);
      expect(info.peersConnected).assertEqual(8);
      expect(info.peersTotal).assertEqual(12);
      // arr[8]=speedUp → rateUpload, arr[9]=speedDown → rateDownload
      expect(info.rateUpload).assertEqual(50000);
      expect(info.rateDownload).assertEqual(2000000);
      // status != ERROR → error = OK
      expect(info.error).assertEqual(TorrentError.OK);
    });

    it('fromStatArray_seeding_correctFields', 0, (): void => {
      // status=3=SEED, progress=100%, totalLen=5000000, remainingLen=0
      const nativeStat: number[] = [
        10, 3, 100, 5000000, 0,
        10000000, 3, 5, 100000, 0
      ];
      const info: TorrentInfo = TorrentInfo.fromStatArray(
        nativeStat, 'debian.iso', 'def456'
      );

      expect(info.id).assertEqual(10);
      expect(info.status).assertEqual(TorrentStatus.SEED);
      expect(info.percentComplete).assertEqual(1.0);
      // percentDone = haveValid / totalSize = 5000000 / 5000000
      expect(info.percentDone).assertEqual(1.0);
      // haveValid = totalLen - remainingLen = 5000000 - 0 = 5000000
      expect(info.haveValid).assertEqual(5000000);
      expect(info.rateDownload).assertEqual(0);
      expect(info.rateUpload).assertEqual(100000);
      expect(info.error).assertEqual(TorrentError.OK);
    });

    it('fromStatArray_stopped_correctFields', 0, (): void => {
      // status=0=STOPPED, everything at zero
      const nativeStat: number[] = [
        5, 0, 0, 2000000, 2000000,
        0, 0, 0, 0, 0
      ];
      const info: TorrentInfo = TorrentInfo.fromStatArray(
        nativeStat, 'paused.iso', 'ghi789'
      );

      expect(info.id).assertEqual(5);
      expect(info.status).assertEqual(TorrentStatus.STOPPED);
      expect(info.percentComplete).assertEqual(0);
      // haveValid = totalLen - remainingLen = 2000000 - 2000000 = 0
      expect(info.haveValid).assertEqual(0);
      expect(info.percentDone).assertEqual(0);
      expect(info.peersConnected).assertEqual(0);
      expect(info.peersTotal).assertEqual(0);
      expect(info.rateDownload).assertEqual(0);
      expect(info.rateUpload).assertEqual(0);
      expect(info.error).assertEqual(TorrentError.OK);
    });

    it('fromStatArray_errorStatus_autoSetsLocalError', 0, (): void => {
      // status=4=ERROR → error is auto-derived as LOCAL_ERROR
      const nativeStat: number[] = [
        99, 4, 50, 1000000, 500000,
        0, 0, 0, 0, 0
      ];
      const info: TorrentInfo = TorrentInfo.fromStatArray(
        nativeStat, 'broken.iso', 'err001'
      );

      expect(info.id).assertEqual(99);
      expect(info.status).assertEqual(TorrentStatus.ERROR);
      expect(info.error).assertEqual(TorrentError.LOCAL_ERROR);
      expect(info.percentComplete).assertEqual(0.5);
      expect(info.haveValid).assertEqual(500000);
    });

    it('fromStatArray_speedUpMapsToRateUpload', 0, (): void => {
      // Verify arr[8]=speedUp → rateUpload, arr[9]=speedDown → rateDownload
      const nativeStat: number[] = [
        1, 2, 50, 1000000, 500000,
        100000, 5, 10, 300000, 5000000
      ];
      const info: TorrentInfo = TorrentInfo.fromStatArray(
        nativeStat, 'speed.iso', 'spd01'
      );
      // arr[8] = 300000 (speedUp) → rateUpload
      expect(info.rateUpload).assertEqual(300000);
      // arr[9] = 5000000 (speedDown) → rateDownload
      expect(info.rateDownload).assertEqual(5000000);
    });

    it('fromStatArray_shortArray_usesDegradedMode', 0, (): void => {
      // Array shorter than 10 → degraded fill
      const nativeStat: number[] = [1];
      const info: TorrentInfo = TorrentInfo.fromStatArray(
        nativeStat, 'minimal.iso', 'min01'
      );

      expect(info.id).assertEqual(1);
      expect(info.name).assertEqual('minimal.iso');
      expect(info.hashString).assertEqual('min01');
      expect(info.totalSize).assertEqual(0);
      expect(info.status).assertEqual(TorrentStatus.STOPPED);
    });
  });

  // ═══════════════════════════════════════════════════════════════════
  // fromNativeJson — parses native listTorrentNames() text format
  // Format: "%d %s %s" per line (id, 40-char hex hash, name)
  // ═══════════════════════════════════════════════════════════════════
  describe('fromNativeJson', () => {
    it('fromNativeJson_singleTorrent_parsesCorrectly', 0, (): void => {
      const raw: string =
        '42 deadbeefdeadbeefdeadbeefdeadbeefdeadbeef ubuntu.iso';
      const torrents: TorrentInfo[] = TorrentInfo.fromNativeJson(raw);

      expect(torrents.length).assertEqual(1);
      expect(torrents[0].id).assertEqual(42);
      expect(torrents[0].hashString).assertEqual(
        'deadbeefdeadbeefdeadbeefdeadbeefdeadbeef'
      );
      expect(torrents[0].name).assertEqual('ubuntu.iso');
    });

    it('fromNativeJson_multipleTorrents_parsesAll', 0, (): void => {
      const raw: string =
        '1 aaaaaaaaaabbbbbbbbbbccccccccccdddddddddd arch.iso\n' +
        '2 bbbbbbbbbbccccccccccddddddddddeeeeeeeeee debian.iso\n' +
        '3 ccccccccccddddddddddeeeeeeeeeeffffffffff fedora.iso';
      const torrents: TorrentInfo[] = TorrentInfo.fromNativeJson(raw);

      expect(torrents.length).assertEqual(3);
      expect(torrents[0].id).assertEqual(1);
      expect(torrents[0].name).assertEqual('arch.iso');
      expect(torrents[1].id).assertEqual(2);
      expect(torrents[1].name).assertEqual('debian.iso');
      expect(torrents[2].id).assertEqual(3);
      expect(torrents[2].name).assertEqual('fedora.iso');
    });

    it('fromNativeJson_emptyArrayString_returnsEmpty', 0, (): void => {
      const torrents: TorrentInfo[] = TorrentInfo.fromNativeJson('[]');
      expect(torrents.length).assertEqual(0);
    });

    it('fromNativeJson_emptyString_returnsEmpty', 0, (): void => {
      const torrents: TorrentInfo[] = TorrentInfo.fromNativeJson('');
      expect(torrents.length).assertEqual(0);
    });

    it('fromNativeJson_allWhitespace_returnsEmpty', 0, (): void => {
      const torrents: TorrentInfo[] = TorrentInfo.fromNativeJson('   \n  \n  ');
      expect(torrents.length).assertEqual(0);
    });

    it('fromNativeJson_skipsMalformedLines', 0, (): void => {
      const raw: string =
        '1 aaaaaaaaaabbbbbbbbbbccccccccccdddddddddd good.iso\n' +
        'badline\n' +
        '2 bbbbbbbbbbccccccccccddddddddddeeeeeeeeee alsoGood.iso';
      const torrents: TorrentInfo[] = TorrentInfo.fromNativeJson(raw);

      expect(torrents.length).assertEqual(2);
      expect(torrents[0].id).assertEqual(1);
      expect(torrents[1].id).assertEqual(2);
    });

    it('fromNativeJson_nameWithSpaces_parsedCorrectly', 0, (): void => {
      // Names can contain spaces — everything after "id hash " is the name
      const raw: string =
        '42 deadbeefdeadbeefdeadbeefdeadbeefdeadbeef Ubuntu 24.04 LTS.iso';
      const torrents: TorrentInfo[] = TorrentInfo.fromNativeJson(raw);

      expect(torrents.length).assertEqual(1);
      expect(torrents[0].id).assertEqual(42);
      expect(torrents[0].name).assertEqual('Ubuntu 24.04 LTS.iso');
    });
  });

  // ═══════════════════════════════════════════════════════════════════
  // toJSON — serializes TorrentInfo to a plain object
  // ═══════════════════════════════════════════════════════════════════
  describe('toJSON', () => {
    it('toJSON_returnsAllFields', 0, (): void => {
      const info: TorrentInfo = new TorrentInfo();
      info.id = 1;
      info.name = 'test.iso';
      info.hashString = 'hash123';
      info.status = TorrentStatus.DOWNLOAD;
      info.error = TorrentError.OK;
      info.errorString = '';
      info.totalSize = 1000000;
      info.downloadedEver = 500000;
      info.uploadedEver = 100000;
      info.haveValid = 500000;
      info.percentComplete = 0.5;
      info.percentDone = 0.5;
      info.peersConnected = 5;
      info.peersTotal = 20;
      info.rateDownload = 1000000;
      info.rateUpload = 50000;
      info.metadataPercentComplete = 1;
      info.addedDate = 1719532800000;
      info.eta = 60;
      info.hasTorrentFile = true;
      info.queuePosition = 0;

      const json: TorrentInfoJSON = info.toJSON();

      expect(json.id).assertEqual(1);
      expect(json.name).assertEqual('test.iso');
      expect(json.hashString).assertEqual('hash123');
      expect(json.status).assertEqual(TorrentStatus.DOWNLOAD);
      expect(json.error).assertEqual(TorrentError.OK);
      expect(json.totalSize).assertEqual(1000000);
      expect(json.percentComplete).assertEqual(0.5);
      expect(json.rateDownload).assertEqual(1000000);
      expect(json.rateUpload).assertEqual(50000);
      expect(json.peersConnected).assertEqual(5);
      expect(json.peersTotal).assertEqual(20);
      expect(json.eta).assertEqual(60);
      expect(json.hasTorrentFile).assertTrue();
      expect(json.queuePosition).assertEqual(0);
    });

    it('toJSON_newInstance_hasDefaultValues', 0, (): void => {
      const info: TorrentInfo = new TorrentInfo();
      const json: TorrentInfoJSON = info.toJSON();

      expect(json.id).assertEqual(-1);
      expect(json.name).assertEqual('');
      expect(json.status).assertEqual(TorrentStatus.STOPPED);
      expect(json.error).assertEqual(TorrentError.OK);
      expect(json.totalSize).assertEqual(0);
      expect(json.percentComplete).assertEqual(0);
    });
  });

  // ═══════════════════════════════════════════════════════════════════
  // isActive — true for DOWNLOAD, SEED, CHECK
  // ═══════════════════════════════════════════════════════════════════
  describe('isActive', () => {
    it('isActive_downloading_returnsTrue', 0, (): void => {
      const info: TorrentInfo = new TorrentInfo();
      info.status = TorrentStatus.DOWNLOAD;
      expect(info.isActive()).assertTrue();
    });

    it('isActive_seeding_returnsTrue', 0, (): void => {
      const info: TorrentInfo = new TorrentInfo();
      info.status = TorrentStatus.SEED;
      expect(info.isActive()).assertTrue();
    });

    it('isActive_checking_returnsTrue', 0, (): void => {
      const info: TorrentInfo = new TorrentInfo();
      info.status = TorrentStatus.CHECK;
      expect(info.isActive()).assertTrue();
    });

    it('isActive_stopped_returnsFalse', 0, (): void => {
      const info: TorrentInfo = new TorrentInfo();
      info.status = TorrentStatus.STOPPED;
      expect(info.isActive()).assertFalse();
    });

    it('isActive_error_returnsFalse', 0, (): void => {
      const info: TorrentInfo = new TorrentInfo();
      info.status = TorrentStatus.ERROR;
      expect(info.isActive()).assertFalse();
    });
  });

  // ═══════════════════════════════════════════════════════════════════
  // isStopped — true only for STOPPED
  // ═══════════════════════════════════════════════════════════════════
  describe('isStopped', () => {
    it('isStopped_stopped_returnsTrue', 0, (): void => {
      const info: TorrentInfo = new TorrentInfo();
      info.status = TorrentStatus.STOPPED;
      expect(info.isStopped()).assertTrue();
    });

    it('isStopped_downloading_returnsFalse', 0, (): void => {
      const info: TorrentInfo = new TorrentInfo();
      info.status = TorrentStatus.DOWNLOAD;
      expect(info.isStopped()).assertFalse();
    });
  });

  // ═══════════════════════════════════════════════════════════════════
  // isDownloading — true only for DOWNLOAD
  // ═══════════════════════════════════════════════════════════════════
  describe('isDownloading', () => {
    it('isDownloading_downloading_returnsTrue', 0, (): void => {
      const info: TorrentInfo = new TorrentInfo();
      info.status = TorrentStatus.DOWNLOAD;
      expect(info.isDownloading()).assertTrue();
    });

    it('isDownloading_seeding_returnsFalse', 0, (): void => {
      const info: TorrentInfo = new TorrentInfo();
      info.status = TorrentStatus.SEED;
      expect(info.isDownloading()).assertFalse();
    });

    it('isDownloading_stopped_returnsFalse', 0, (): void => {
      const info: TorrentInfo = new TorrentInfo();
      info.status = TorrentStatus.STOPPED;
      expect(info.isDownloading()).assertFalse();
    });
  });

  // ═══════════════════════════════════════════════════════════════════
  // isSeeding — true only for SEED
  // ═══════════════════════════════════════════════════════════════════
  describe('isSeeding', () => {
    it('isSeeding_seeding_returnsTrue', 0, (): void => {
      const info: TorrentInfo = new TorrentInfo();
      info.status = TorrentStatus.SEED;
      expect(info.isSeeding()).assertTrue();
    });

    it('isSeeding_downloading_returnsFalse', 0, (): void => {
      const info: TorrentInfo = new TorrentInfo();
      info.status = TorrentStatus.DOWNLOAD;
      expect(info.isSeeding()).assertFalse();
    });
  });

  // ═══════════════════════════════════════════════════════════════════
  // isChecking — true only for CHECK
  // ═══════════════════════════════════════════════════════════════════
  describe('isChecking', () => {
    it('isChecking_checking_returnsTrue', 0, (): void => {
      const info: TorrentInfo = new TorrentInfo();
      info.status = TorrentStatus.CHECK;
      expect(info.isChecking()).assertTrue();
    });

    it('isChecking_stopped_returnsFalse', 0, (): void => {
      const info: TorrentInfo = new TorrentInfo();
      info.status = TorrentStatus.STOPPED;
      expect(info.isChecking()).assertFalse();
    });

    it('isChecking_downloading_returnsFalse', 0, (): void => {
      const info: TorrentInfo = new TorrentInfo();
      info.status = TorrentStatus.DOWNLOAD;
      expect(info.isChecking()).assertFalse();
    });
  });

  // ═══════════════════════════════════════════════════════════════════
  // isFinished — true when percentComplete >= 1.0 OR percentDone >= 1.0
  // (percentDone covers the mid-verification case where the native brief stat
  //  reports verify progress, not download progress, in arr[2] — C4/docs-11)
  // ═══════════════════════════════════════════════════════════════════
  describe('isFinished', () => {
    it('isFinished_complete_returnsTrue', 0, (): void => {
      const info: TorrentInfo = new TorrentInfo();
      info.percentComplete = 1.0;
      expect(info.isFinished()).assertTrue();
    });

    it('isFinished_overComplete_returnsTrue', 0, (): void => {
      const info: TorrentInfo = new TorrentInfo();
      info.percentComplete = 1.5;
      expect(info.isFinished()).assertTrue();
    });

    it('isFinished_partial_returnsFalse', 0, (): void => {
      const info: TorrentInfo = new TorrentInfo();
      info.percentComplete = 0.72;
      expect(info.isFinished()).assertFalse();
    });

    it('isFinished_zero_returnsFalse', 0, (): void => {
      const info: TorrentInfo = new TorrentInfo();
      info.percentComplete = 0;
      expect(info.isFinished()).assertFalse();
    });

    it('isFinished_midVerification_percentDoneCompletes_returnsTrue', 0, (): void => {
      // During TR_STATUS_CHECK the native brief stat puts verify progress in
      // arr[2] (percentComplete) while all bytes are already downloaded
      // (percentDone == 1.0). A torrent that has its data is finished even
      // while the check is still running (C4, docs/11).
      const info: TorrentInfo = new TorrentInfo();
      info.percentComplete = 0.45;
      info.percentDone = 1.0;
      expect(info.isFinished()).assertTrue();
    });
  });

  // ═══════════════════════════════════════════════════════════════════
  // isQueued — always false from brief stats
  // (Wait states are consolidated into active statuses at native layer)
  // ═══════════════════════════════════════════════════════════════════
  describe('isQueued', () => {
    it('isQueued_alwaysFalse_briefStatsCannotDetectQueued', 0, (): void => {
      // The 5-value stat array consolidates wait states into active
      // statuses. isQueued() always returns false from brief stats.
      const info: TorrentInfo = new TorrentInfo();
      info.status = TorrentStatus.DOWNLOAD;
      expect(info.isQueued()).assertFalse();
      info.status = TorrentStatus.SEED;
      expect(info.isQueued()).assertFalse();
      info.status = TorrentStatus.CHECK;
      expect(info.isQueued()).assertFalse();
      info.status = TorrentStatus.STOPPED;
      expect(info.isQueued()).assertFalse();
      info.status = TorrentStatus.ERROR;
      expect(info.isQueued()).assertFalse();
    });
  });

  // ═══════════════════════════════════════════════════════════════════
  // hasError — true when error !== OK
  // ═══════════════════════════════════════════════════════════════════
  describe('hasError', () => {
    it('hasError_noError_returnsFalse', 0, (): void => {
      const info: TorrentInfo = new TorrentInfo();
      info.error = TorrentError.OK;
      expect(info.hasError()).assertFalse();
    });

    it('hasError_trackerWarning_returnsTrue', 0, (): void => {
      const info: TorrentInfo = new TorrentInfo();
      info.error = TorrentError.TRACKER_WARNING;
      expect(info.hasError()).assertTrue();
    });

    it('hasError_trackerError_returnsTrue', 0, (): void => {
      const info: TorrentInfo = new TorrentInfo();
      info.error = TorrentError.TRACKER_ERROR;
      expect(info.hasError()).assertTrue();
    });

    it('hasError_localError_returnsTrue', 0, (): void => {
      const info: TorrentInfo = new TorrentInfo();
      info.error = TorrentError.LOCAL_ERROR;
      expect(info.hasError()).assertTrue();
    });
  });

  // ═══════════════════════════════════════════════════════════════════
  // getStatusString — human-readable status labels
  // ═══════════════════════════════════════════════════════════════════
  describe('getStatusString', () => {
    it('getStatusString_downloading_returnsDownloading', 0, (): void => {
      const info: TorrentInfo = new TorrentInfo();
      info.status = TorrentStatus.DOWNLOAD;
      info.error = TorrentError.OK;
      expect(info.getStatusString()).assertEqual('Downloading');
    });

    it('getStatusString_seeding_returnsSeeding', 0, (): void => {
      const info: TorrentInfo = new TorrentInfo();
      info.status = TorrentStatus.SEED;
      info.error = TorrentError.OK;
      expect(info.getStatusString()).assertEqual('Seeding');
    });

    it('getStatusString_checking_returnsVerifying', 0, (): void => {
      const info: TorrentInfo = new TorrentInfo();
      info.status = TorrentStatus.CHECK;
      info.error = TorrentError.OK;
      expect(info.getStatusString()).assertEqual('Verifying');
    });

    it('getStatusString_stoppedFinished_returnsCompleted', 0, (): void => {
      const info: TorrentInfo = new TorrentInfo();
      info.status = TorrentStatus.STOPPED;
      info.error = TorrentError.OK;
      info.percentComplete = 1.0;
      expect(info.getStatusString()).assertEqual('Completed');
    });

    it('getStatusString_stoppedPartial_returnsPaused', 0, (): void => {
      const info: TorrentInfo = new TorrentInfo();
      info.status = TorrentStatus.STOPPED;
      info.error = TorrentError.OK;
      info.percentComplete = 0.5;
      expect(info.getStatusString()).assertEqual('Paused');
    });

    it('getStatusString_errorStatus_returnsError', 0, (): void => {
      const info: TorrentInfo = new TorrentInfo();
      info.status = TorrentStatus.ERROR;
      info.error = TorrentError.LOCAL_ERROR;
      info.errorString = '';
      expect(info.getStatusString()).assertEqual('Error');
    });

    it('getStatusString_error_noMessage_returnsError', 0, (): void => {
      const info: TorrentInfo = new TorrentInfo();
      info.status = TorrentStatus.DOWNLOAD;
      info.error = TorrentError.TRACKER_ERROR;
      info.errorString = '';
      expect(info.getStatusString()).assertEqual('Error');
    });

    it('getStatusString_error_withMessage_returnsMessage', 0, (): void => {
      const info: TorrentInfo = new TorrentInfo();
      info.status = TorrentStatus.DOWNLOAD;
      info.error = TorrentError.TRACKER_ERROR;
      info.errorString = 'Tracker not responding';
      expect(info.getStatusString()).assertEqual('Tracker not responding');
    });

    it('getStatusString_errorOverridesStatus', 0, (): void => {
      const info: TorrentInfo = new TorrentInfo();
      info.status = TorrentStatus.SEED;
      info.error = TorrentError.LOCAL_ERROR;
      info.errorString = 'Disk full';
      expect(info.getStatusString()).assertEqual('Disk full');
    });
  });

  // ═══════════════════════════════════════════════════════════════════
  // getStatusColor — semantic color coding for status indicators
  // ═══════════════════════════════════════════════════════════════════
  describe('getStatusColor', () => {
    it('getStatusColor_downloading_returnsBlue', 0, (): void => {
      const info: TorrentInfo = new TorrentInfo();
      info.status = TorrentStatus.DOWNLOAD;
      info.error = TorrentError.OK;
      expect(info.getStatusColor()).assertEqual('#3b82f6');
    });

    it('getStatusColor_seeding_returnsGreen', 0, (): void => {
      const info: TorrentInfo = new TorrentInfo();
      info.status = TorrentStatus.SEED;
      info.error = TorrentError.OK;
      expect(info.getStatusColor()).assertEqual('#22c55e');
    });

    it('getStatusColor_checking_returnsIndigo', 0, (): void => {
      const info: TorrentInfo = new TorrentInfo();
      info.status = TorrentStatus.CHECK;
      info.error = TorrentError.OK;
      expect(info.getStatusColor()).assertEqual('#6366f1');
    });

    it('getStatusColor_stoppedFinished_returnsGreen', 0, (): void => {
      const info: TorrentInfo = new TorrentInfo();
      info.status = TorrentStatus.STOPPED;
      info.error = TorrentError.OK;
      info.percentComplete = 1.0;
      expect(info.getStatusColor()).assertEqual('#22c55e');
    });

    it('getStatusColor_stoppedPartial_returnsAmber', 0, (): void => {
      const info: TorrentInfo = new TorrentInfo();
      info.status = TorrentStatus.STOPPED;
      info.error = TorrentError.OK;
      info.percentComplete = 0.3;
      expect(info.getStatusColor()).assertEqual('#f59e0b');
    });

    it('getStatusColor_error_returnsRed', 0, (): void => {
      const info: TorrentInfo = new TorrentInfo();
      info.status = TorrentStatus.ERROR;
      expect(info.getStatusColor()).assertEqual('#ef4444');
    });

    it('getStatusColor_errorWithOtherStatus_returnsRed', 0, (): void => {
      const info: TorrentInfo = new TorrentInfo();
      info.status = TorrentStatus.DOWNLOAD;
      info.error = TorrentError.LOCAL_ERROR;
      expect(info.getStatusColor()).assertEqual('#ef4444');
    });
  });
}
