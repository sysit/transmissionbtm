import { defineConfig } from 'vitest/config';
import { transformSync } from 'esbuild';
import { readFileSync } from 'fs';
import { resolve } from 'path';

const MOCKS_DIR = resolve(__dirname, 'tests/__mocks__');

export default defineConfig({
  test: {
    include: ['tests/**/*.test.ts'],
  },
  resolve: {
    extensions: ['.ets', '.ts', '.js', '.mjs', '.cjs'],
    alias: {
      'libtransmissionbtm_napi.so': resolve(MOCKS_DIR, 'native.ts'),
      '@kit.PerformanceAnalysisKit': resolve(MOCKS_DIR, 'hilog.ts'),
      '@kit.ArkData': resolve(MOCKS_DIR, 'arkdata.ts'),
    },
  },
  plugins: [
    {
      name: 'ets-transform',
      enforce: 'pre',
      async transform(_code: string, id: string) {
        if (!id.endsWith('.ets')) return null;
        // Use esbuild to strip TypeScript types from .ets files
        const raw = readFileSync(id, 'utf-8');
        const result = transformSync(raw, {
          loader: 'ts',
          format: 'esm',
          target: 'es2020',
        });
        return { code: result.code, map: result.map };
      },
    },
  ],
});
