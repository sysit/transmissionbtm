import { describe, it, expect } from 'vitest';
import { formatSpeed, formatSize, formatETA, formatPercentage, formatProgress, formatDate } from '../entry/src/main/ets/utils/format.ets';

describe('formatSpeed', () => {
  it('returns em dash for undefined/null/negative', () => {
    expect(formatSpeed(undefined as unknown as number)).toBe('—');
    expect(formatSpeed(null as unknown as number)).toBe('—');
    expect(formatSpeed(-1)).toBe('—');
  });
  it('returns 0 B/s for zero', () => expect(formatSpeed(0)).toBe('0 B/s'));
  it('formats B/s', () => expect(formatSpeed(500)).toBe('500 B/s'));
  it('formats KB/s at 1000', () => expect(formatSpeed(1000)).toBe('1.0 KB/s'));
  it('formats MB/s', () => expect(formatSpeed(1048576)).toBe('1.0 MB/s'));
  it('formats GB/s', () => { const val = 3221225472; expect(formatSpeed(val)).toBe('3.2 GB/s'); });
  it('stays at GB/s for huge values', () => expect(formatSpeed(1e15)).toContain('GB/s'));
});

describe('formatSize', () => {
  it('returns em dash for undefined/negative', () => {
    expect(formatSize(undefined as unknown as number)).toBe('—');
    expect(formatSize(-1)).toBe('—');
  });
  it('returns 0 B for zero', () => expect(formatSize(0)).toBe('0 B'));
  it('formats KB at 1000', () => expect(formatSize(1000)).toBe('1.0 KB'));
  it('formats MB', () => expect(formatSize(1048576)).toBe('1.0 MB'));
  it('formats GB', () => expect(formatSize(1073741824)).toBe('1.1 GB'));
  it('formats TB', () => expect(formatSize(1099511627776)).toBe('1.1 TB'));
});

describe('formatETA', () => {
  it('returns em dash for invalid', () => {
    expect(formatETA(undefined as unknown as number)).toBe('—');
    expect(formatETA(0)).toBe('—');
    expect(formatETA(-5)).toBe('—');
    expect(formatETA(Infinity)).toBe('—');
    expect(formatETA(NaN)).toBe('—');
  });
  it('formats seconds', () => expect(formatETA(42)).toBe('42s'));
  it('formats minutes+seconds', () => expect(formatETA(252)).toBe('4m 12s'));
  it('formats hours+minutes', () => {
    expect(formatETA(3661)).toBe('1h 1m');
    expect(formatETA(7200)).toBe('2h 0m');
  });
});

describe('formatPercentage', () => {
  it('returns em dash for undefined/negative', () => {
    expect(formatPercentage(undefined as unknown as number)).toBe('—');
    expect(formatPercentage(-0.5)).toBe('—');
  });
  it('returns 0% for zero', () => expect(formatPercentage(0)).toBe('0%'));
  it('treats <= 1 as ratio', () => {
    expect(formatPercentage(0.5)).toBe('50%');
    expect(formatPercentage(0.723)).toBe('72.3%');
    expect(formatPercentage(1.0)).toBe('100%');
  });
  it('treats > 1 as direct percent', () => {
    expect(formatPercentage(50)).toBe('50%');
    expect(formatPercentage(100)).toBe('100%');
  });
  it('rounds to 1 decimal', () => expect(formatPercentage(0.666)).toBe('66.6%'));
  it('drops decimal for integers', () => expect(formatPercentage(75)).toBe('75%'));
});

describe('formatProgress', () => {
  it('delegates to formatPercentage', () => {
    expect(formatProgress(0.42)).toBe('42%');
    expect(formatProgress(0)).toBe('0%');
  });
});

describe('formatDate', () => {
  it('returns em dash for invalid', () => {
    expect(formatDate(0)).toBe('—');
    expect(formatDate(NaN)).toBe('—');
    expect(formatDate(Infinity)).toBe('—');
  });
  it('formats YYYY-MM-DD', () => {
    expect(formatDate(1768435200000)).toMatch(/^\d{4}-\d{2}-\d{2}$/);
  });
});
