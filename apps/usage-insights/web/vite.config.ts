import react from '@vitejs/plugin-react';
import { defineConfig } from 'vitest/config';

export default defineConfig({
  plugins: [react()],
  build: {
    // The Python server serves this folder; it is git-ignored.
    outDir: '../src/usage_insights/static',
    emptyOutDir: true,
  },
  server: {
    // changeOrigin rewrites Host so the server's Host check accepts proxied calls.
    proxy: { '/api': { target: 'http://127.0.0.1:8090', changeOrigin: true } },
  },
  test: {
    environment: 'jsdom',
  },
});
