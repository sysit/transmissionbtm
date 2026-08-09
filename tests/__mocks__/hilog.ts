// Mock for @kit.PerformanceAnalysisKit (hilog)
// hilog is unavailable in Node.js vitest runtime.

export const hilog = {
  info(_domain: number, _tag: string, _fmt: string, ..._args: Object[]): void {},
  warn(_domain: number, _tag: string, _fmt: string, ..._args: Object[]): void {},
  error(_domain: number, _tag: string, _fmt: string, ..._args: Object[]): void {},
  debug(_domain: number, _tag: string, _fmt: string, ..._args: Object[]): void {},
  fatal(_domain: number, _tag: string, _fmt: string, ..._args: Object[]): void {},
  isLoggable(_domain: number, _tag: string, _level: number): boolean { return false; },
};
