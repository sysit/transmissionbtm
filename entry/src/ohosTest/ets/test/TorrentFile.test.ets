// transmissionbtm — TorrentFile domain model tests
//
// Tests FilePriority enum, TorrentFile.fromNative() factory, percentComplete
// getter, isDirectory, and structural defaults. No native calls.
// Cross-referenced against transmissionbtc TorrentFile.java patterns.

import { describe, it, expect } from '@ohos/hypium';
import { TorrentFile, FilePriority, RawFileEntry } from '../../../main/ets/models/TorrentFile';

// Module-level helper: build a RawFileEntry for fromNative tests.
// Must be at module scope — ArkTS does not allow nested functions.
function makeRawEntry(
  index: number, name: string, size: number,
  bytesCompleted: number, wanted: boolean, priority: number,
): RawFileEntry {
  return { index, name, size, bytesCompleted, wanted, priority };
}

export default function torrentFileTest(): void {
  describe('FilePriority', () => {
    it('has_three_levels', 0, (): void => {
      expect(FilePriority.SKIP).assertEqual(-1);
      expect(FilePriority.NORMAL).assertEqual(0);
      expect(FilePriority.HIGH).assertEqual(1);
    });

    it('values_are_mutually_distinct', 0, (): void => {
      expect((FilePriority.SKIP as number) === (FilePriority.NORMAL as number)).assertFalse();
      expect((FilePriority.NORMAL as number) === (FilePriority.HIGH as number)).assertFalse();
      expect((FilePriority.SKIP as number) === (FilePriority.HIGH as number)).assertFalse();
    });
  });

  describe('TorrentFile', () => {
    it('constructor_initializes_sensible_defaults', 0, (): void => {
      const f: TorrentFile = new TorrentFile();
      expect(f.index).assertEqual(0);
      expect(f.name).assertEqual('');
      expect(f.path).assertEqual('');
      expect(f.size).assertEqual(0);
      expect(f.bytesCompleted).assertEqual(0);
      expect(f.priority).assertEqual(FilePriority.NORMAL);
      expect(f.wanted).assertTrue();
    });

    it('percentComplete_calculated_from_bytesCompleted_over_size', 0, (): void => {
      const f: TorrentFile = new TorrentFile();
      f.size = 10000;
      f.bytesCompleted = 7200;
      expect(f.percentComplete).assertEqual(0.72);
    });

    it('percentComplete_zero_when_size_zero', 0, (): void => {
      const f: TorrentFile = new TorrentFile();
      f.size = 0;
      f.bytesCompleted = 500;
      expect(f.percentComplete).assertEqual(0);
    });

    it('percentComplete_zero_when_bytesCompleted_zero', 0, (): void => {
      const f: TorrentFile = new TorrentFile();
      f.size = 1000;
      f.bytesCompleted = 0;
      expect(f.percentComplete).assertEqual(0);
    });

    it('percentComplete_one_when_fully_downloaded', 0, (): void => {
      const f: TorrentFile = new TorrentFile();
      f.size = 1000;
      f.bytesCompleted = 1000;
      expect(f.percentComplete).assertEqual(1);
    });

    it('isDirectory_true_when_size_zero_and_name_ends_with_slash', 0, (): void => {
      const f: TorrentFile = new TorrentFile();
      f.size = 0;
      f.name = 'somedir/';
      expect(f.isDirectory).assertTrue();
    });

    it('isDirectory_false_when_size_nonzero', 0, (): void => {
      const f: TorrentFile = new TorrentFile();
      f.size = 100;
      f.name = 'somedir/';
      expect(f.isDirectory).assertFalse();
    });

    it('isDirectory_false_when_no_trailing_slash', 0, (): void => {
      const f: TorrentFile = new TorrentFile();
      f.size = 0;
      f.name = 'file.txt';
      expect(f.isDirectory).assertFalse();
    });

    it('wanted_defaults_to_true', 0, (): void => {
      const f: TorrentFile = new TorrentFile();
      expect(f.wanted).assertTrue();
    });

    it('priority_defaults_to_NORMAL', 0, (): void => {
      const f: TorrentFile = new TorrentFile();
      expect(f.priority).assertEqual(FilePriority.NORMAL);
    });
  });

  describe('TorrentFile.fromNative', () => {
    it('fromNative_maps_all_fields_correctly', 0, (): void => {
      const raw: RawFileEntry = makeRawEntry(0, 'video.mp4', 10000, 7200, true, 0);
      const f: TorrentFile = TorrentFile.fromNative(raw);
      expect(f.index).assertEqual(0);
      expect(f.name).assertEqual('video.mp4');
      expect(f.path).assertEqual('video.mp4');
      expect(f.size).assertEqual(10000);
      expect(f.bytesCompleted).assertEqual(7200);
      expect(f.wanted).assertTrue();
      expect(f.priority).assertEqual(FilePriority.NORMAL);
    });

    it('fromNative_path_equals_name_for_nested_files', 0, (): void => {
      const raw: RawFileEntry = makeRawEntry(5, 'sub/dir/file.txt', 200, 50, true, 1);
      const f: TorrentFile = TorrentFile.fromNative(raw);
      expect(f.name).assertEqual('sub/dir/file.txt');
      expect(f.path).assertEqual('sub/dir/file.txt');
    });

    it('fromNative_SKIP_priority_mapped_correctly', 0, (): void => {
      const raw: RawFileEntry = makeRawEntry(3, 'skipme.bin', 100, 0, false, -1);
      const f: TorrentFile = TorrentFile.fromNative(raw);
      expect(f.wanted).assertFalse();
      expect(f.priority).assertEqual(FilePriority.SKIP);
    });

    it('fromNative_HIGH_priority_mapped_correctly', 0, (): void => {
      const raw: RawFileEntry = makeRawEntry(2, 'important.txt', 500, 500, true, 1);
      const f: TorrentFile = TorrentFile.fromNative(raw);
      expect(f.priority).assertEqual(FilePriority.HIGH);
    });

    it('fromNative_defaults_bytesCompleted_to_zero_when_omitted', 0, (): void => {
      // In the source: raw.bytesCompleted ?? 0 — so undefined → 0
      const raw: RawFileEntry = {
        index: 1, name: 'file.bin', size: 100, priority: 0,
      };
      const f: TorrentFile = TorrentFile.fromNative(raw);
      expect(f.bytesCompleted).assertEqual(0);
    });

    it('fromNative_defaults_wanted_to_true_when_omitted', 0, (): void => {
      const raw: RawFileEntry = {
        index: 0, name: 'file.bin', size: 100,
        bytesCompleted: 50, priority: 0,
      };
      const f: TorrentFile = TorrentFile.fromNative(raw);
      expect(f.wanted).assertTrue();
    });
  });
}
