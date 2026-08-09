// transmissionhm — Format utilities unit tests
//
// All format functions are pure logic (no N-API calls). Tests verify
// exact output strings against the decimal-unit (1000) convention.
//
// Expected format rules:
//   - Negative, undefined, or null input → '—' (em dash)
//   - Zero → literal zero string (no decimal)
//   - >= 1000 → divide by 1000, one decimal place
//   - GB is the highest unit for speed; TB for size
//
// Cross-referenced against transmissionbtc Utils.java patterns:
//   - formatSpeed mirrors Utils.bytesToString() for rate display
//   - formatSize mirrors Utils.bytesToString() for file size display
//   - formatETA mirrors Utils.etaToString() for remaining time

import { describe, it, expect } from '@ohos/hypium';
import {
  formatSpeed,
  formatSize,
  formatETA,
  formatPercentage,
  formatProgress,
  formatDate,
} from '../../../main/ets/utils/format';

export default function formatUtilsTest(): void {
  // ═══════════════════════════════════════════════════════════════════
  // formatSpeed
  // ═══════════════════════════════════════════════════════════════════
  describe('formatSpeed', () => {
    it('formatSpeed_zero_returnsLiteralZero', 0, (): void => {
      const result: string = formatSpeed(0);
      expect(result).assertEqual('0 B/s');
    });

    it('formatSpeed_500Bps_returns500Bs', 0, (): void => {
      const result: string = formatSpeed(500);
      expect(result).assertEqual('500 B/s');
    });

    it('formatSpeed_999Bps_returns999Bs_noRounding', 0, (): void => {
      const result: string = formatSpeed(999);
      expect(result).assertEqual('999 B/s');
    });

    it('formatSpeed_1000Bps_returns1_0KBs', 0, (): void => {
      const result: string = formatSpeed(1000);
      expect(result).assertEqual('1.0 KB/s');
    });

    it('formatSpeed_1500Bps_returns1_5KBs', 0, (): void => {
      const result: string = formatSpeed(1500);
      expect(result).assertEqual('1.5 KB/s');
    });

    it('formatSpeed_1MBps_boundary_returns1_0MBs', 0, (): void => {
      const result: string = formatSpeed(1000000);
      expect(result).assertEqual('1.0 MB/s');
    });

    it('formatSpeed_1_5MBps_returns1_5MBs', 0, (): void => {
      const result: string = formatSpeed(1500000);
      expect(result).assertEqual('1.5 MB/s');
    });

    it('formatSpeed_5GBps_returns5_0GBs', 0, (): void => {
      const result: string = formatSpeed(5000000000);
      expect(result).assertEqual('5.0 GB/s');
    });

    it('formatSpeed_veryLarge_remainsInGBs', 0, (): void => {
      // There is no TB/s unit; values beyond GB/s stay in GB/s
      const result: string = formatSpeed(5000000000000);
      expect(result).assertEqual('5000.0 GB/s');
    });

    it('formatSpeed_negative_returnsEmDash', 0, (): void => {
      const result: string = formatSpeed(-1);
      expect(result).assertEqual('—');
    });
  });

  // ═══════════════════════════════════════════════════════════════════
  // formatSize
  // ═══════════════════════════════════════════════════════════════════
  describe('formatSize', () => {
    it('formatSize_zero_returnsLiteralZero', 0, (): void => {
      const result: string = formatSize(0);
      expect(result).assertEqual('0 B');
    });

    it('formatSize_500B_returns500B', 0, (): void => {
      const result: string = formatSize(500);
      expect(result).assertEqual('500 B');
    });

    it('formatSize_999B_returns999B_noRounding', 0, (): void => {
      const result: string = formatSize(999);
      expect(result).assertEqual('999 B');
    });

    it('formatSize_1000B_returns1_0KB', 0, (): void => {
      const result: string = formatSize(1000);
      expect(result).assertEqual('1.0 KB');
    });

    it('formatSize_1536B_returns1_5KB', 0, (): void => {
      const result: string = formatSize(1536);
      expect(result).assertEqual('1.5 KB');
    });

    it('formatSize_1MB_returns1_0MB', 0, (): void => {
      const result: string = formatSize(1000000);
      expect(result).assertEqual('1.0 MB');
    });

    it('formatSize_1GB_returns1_0GB', 0, (): void => {
      const result: string = formatSize(1000000000);
      expect(result).assertEqual('1.0 GB');
    });

    it('formatSize_1TB_returns1_0TB', 0, (): void => {
      const result: string = formatSize(1000000000000);
      expect(result).assertEqual('1.0 TB');
    });

    it('formatSize_2_5TB_returns2_5TB', 0, (): void => {
      const result: string = formatSize(2500000000000);
      expect(result).assertEqual('2.5 TB');
    });

    it('formatSize_negative_returnsEmDash', 0, (): void => {
      const result: string = formatSize(-1);
      expect(result).assertEqual('—');
    });
  });

  // ═══════════════════════════════════════════════════════════════════
  // formatETA
  // ═══════════════════════════════════════════════════════════════════
  describe('formatETA', () => {
    it('formatETA_zero_returnsEmDash', 0, (): void => {
      const result: string = formatETA(0);
      expect(result).assertEqual('—');
    });

    it('formatETA_negative_returnsEmDash', 0, (): void => {
      const result: string = formatETA(-1);
      expect(result).assertEqual('—');
    });

    it('formatETA_30seconds_returns30s', 0, (): void => {
      const result: string = formatETA(30);
      expect(result).assertEqual('30s');
    });

    it('formatETA_59seconds_returns59s', 0, (): void => {
      const result: string = formatETA(59);
      expect(result).assertEqual('59s');
    });

    it('formatETA_60seconds_returns1m0s', 0, (): void => {
      const result: string = formatETA(60);
      expect(result).assertEqual('1m 0s');
    });

    it('formatETA_252seconds_returns4m12s', 0, (): void => {
      const result: string = formatETA(252);
      expect(result).assertEqual('4m 12s');
    });

    it('formatETA_3599seconds_returns59m59s', 0, (): void => {
      const result: string = formatETA(3599);
      expect(result).assertEqual('59m 59s');
    });

    it('formatETA_3600seconds_returns1h0m', 0, (): void => {
      const result: string = formatETA(3600);
      expect(result).assertEqual('1h 0m');
    });

    it('formatETA_3661seconds_returns1h1m', 0, (): void => {
      const result: string = formatETA(3661);
      expect(result).assertEqual('1h 1m');
    });

    it('formatETA_7200seconds_returns2h0m', 0, (): void => {
      const result: string = formatETA(7200);
      expect(result).assertEqual('2h 0m');
    });

    it('formatETA_7320seconds_returns2h2m', 0, (): void => {
      const result: string = formatETA(7320);
      expect(result).assertEqual('2h 2m');
    });

    it('formatETA_90061seconds_returns25h1m', 0, (): void => {
      // 25h 1m 1s — seconds are dropped when hours are present
      const result: string = formatETA(90061);
      expect(result).assertEqual('25h 1m');
    });
  });

  // ═══════════════════════════════════════════════════════════════════
  // formatPercentage
  // ═══════════════════════════════════════════════════════════════════
  describe('formatPercentage', () => {
    it('formatPercentage_zero_returns0pct', 0, (): void => {
      const result: string = formatPercentage(0);
      expect(result).assertEqual('0%');
    });

    it('formatPercentage_ratio_0_5_returns50pct', 0, (): void => {
      const result: string = formatPercentage(0.5);
      expect(result).assertEqual('50%');
    });

    it('formatPercentage_ratio_0_72_returns72pct', 0, (): void => {
      const result: string = formatPercentage(0.72);
      expect(result).assertEqual('72%');
    });

    it('formatPercentage_ratio_0_723_returns72_3pct', 0, (): void => {
      const result: string = formatPercentage(0.723);
      expect(result).assertEqual('72.3%');
    });

    it('formatPercentage_ratio_0_999_returns99_9pct', 0, (): void => {
      const result: string = formatPercentage(0.999);
      expect(result).assertEqual('99.9%');
    });

    it('formatPercentage_ratio_1_0_returns100pct', 0, (): void => {
      const result: string = formatPercentage(1.0);
      expect(result).assertEqual('100%');
    });

    it('formatPercentage_direct72_returns72pct', 0, (): void => {
      // Values > 1 are treated as direct percentages
      const result: string = formatPercentage(72);
      expect(result).assertEqual('72%');
    });

    it('formatPercentage_direct72_3_returns72_3pct', 0, (): void => {
      const result: string = formatPercentage(72.3);
      expect(result).assertEqual('72.3%');
    });

    it('formatPercentage_direct99_9_returns99_9pct', 0, (): void => {
      const result: string = formatPercentage(99.9);
      expect(result).assertEqual('99.9%');
    });

    it('formatPercentage_direct100_returns100pct', 0, (): void => {
      const result: string = formatPercentage(100);
      expect(result).assertEqual('100%');
    });

    it('formatPercentage_negative_returnsEmDash', 0, (): void => {
      const result: string = formatPercentage(-1);
      expect(result).assertEqual('—');
    });
  });

  // ═══════════════════════════════════════════════════════════════════
  // formatProgress (deprecated — delegates to formatPercentage)
  // ═══════════════════════════════════════════════════════════════════
  describe('formatProgress', () => {
    it('formatProgress_0_72_returns72pct', 0, (): void => {
      const result: string = formatProgress(0.72);
      expect(result).assertEqual('72%');
    });

    it('formatProgress_1_0_returns100pct', 0, (): void => {
      const result: string = formatProgress(1.0);
      expect(result).assertEqual('100%');
    });

    it('formatProgress_zero_returns0pct', 0, (): void => {
      const result: string = formatProgress(0);
      expect(result).assertEqual('0%');
    });
  });

  // ═══════════════════════════════════════════════════════════════════
  // formatDate
  // ═══════════════════════════════════════════════════════════════════
  describe('formatDate', () => {
    it('formatDate_zero_returnsEmDash', 0, (): void => {
      const result: string = formatDate(0);
      expect(result).assertEqual('—');
    });

    it('formatDate_negative_returnsEmDash', 0, (): void => {
      const result: string = formatDate(-1);
      expect(result).assertEqual('—');
    });

    it('formatDate_june28_2026_returnsISO', 0, (): void => {
      const testDate: Date = new Date(2026, 5, 28); // Month 5 = June
      const timestamp: number = testDate.getTime();
      const result: string = formatDate(timestamp);
      expect(result).assertEqual('2026-06-28');
    });

    it('formatDate_jan1_2025_returnsISO', 0, (): void => {
      const testDate: Date = new Date(2025, 0, 1); // Month 0 = January
      const timestamp: number = testDate.getTime();
      const result: string = formatDate(timestamp);
      expect(result).assertEqual('2025-01-01');
    });

    it('formatDate_december31_2024_returnsISO', 0, (): void => {
      const testDate: Date = new Date(2024, 11, 31); // Month 11 = December
      const timestamp: number = testDate.getTime();
      const result: string = formatDate(timestamp);
      expect(result).assertEqual('2024-12-31');
    });

    it('formatDate_validTimestamp_hasCorrectLength', 0, (): void => {
      const testDate: Date = new Date(2026, 5, 28);
      const timestamp: number = testDate.getTime();
      const result: string = formatDate(timestamp);
      // ISO date strings are always 10 characters: YYYY-MM-DD
      expect(result.length).assertEqual(10);
    });
  });
}
