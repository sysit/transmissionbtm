import { describe, it, expect } from 'vitest';
import { naturalCompare } from '../entry/src/main/ets/utils/NaturalOrderComparator.ets';

describe('naturalCompare', () => {
  it('sorts strings with numbers naturally', () => {
    const items = ['file10', 'file2', 'file1', 'file20'];
    items.sort(naturalCompare);
    expect(items[0]).toBe('file1');
    expect(items[1]).toBe('file2');
    expect(items[2]).toBe('file10');
    expect(items[3]).toBe('file20');
  });

  it('handles pure strings', () => {
    const items = ['def', 'abc2', 'abc', 'abc1'];
    items.sort(naturalCompare);
    expect(items[0]).toBe('abc');
    expect(items[1]).toBe('abc1');
    expect(items[2]).toBe('abc2');
    expect(items[3]).toBe('def');
  });

  it('handles purely numeric strings', () => {
    expect(naturalCompare('100', '20')).toBeGreaterThan(0);
    expect(naturalCompare('5', '50')).toBeLessThan(0);
  });

  it('returns 0 for equal strings', () => {
    expect(naturalCompare('test', 'test')).toBe(0);
  });

  it('sorts items with leading zeros correctly', () => {
    const items = ['item001', 'item02', 'item10', 'item003'];
    items.sort(naturalCompare);
    // naturalCompare treats number segments as integers
    // "02" = 2, "001" = 1, "003" = 3
    expect(items[0]).toBe('item001');
    expect(items[1]).toBe('item02');
    expect(items[2]).toBe('item003');
    expect(items[3]).toBe('item10');
  });

  it('handles empty strings', () => {
    expect(naturalCompare('', 'a')).toBeLessThan(0);
    expect(naturalCompare('a', '')).toBeGreaterThan(0);
    expect(naturalCompare('', '')).toBe(0);
  });
});
