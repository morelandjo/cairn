/// <reference types="vitest" />
import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'
import path from 'path'

// https://vite.dev/config/
export default defineConfig({
  plugins: [react()],
  resolve: {
    // Dedupe linked package dependencies so Rollup resolves them from
    // this project's node_modules instead of proto's.
    dedupe: ['libsodium-wrappers-sumo'],
    alias: {
      // The proto dist references mls-wasm relative to dist/esm/mls/;
      // redirect to the actual location in the proto source tree.
      'mls-wasm/pkg/mls_wasm.js': path.resolve(
        __dirname,
        '../../proto/mls-wasm/pkg/mls_wasm.js',
      ),
    },
  },
  server: {
    proxy: {
      '/api': {
        target: 'http://localhost:4000',
        changeOrigin: true,
      },
      '/socket': {
        target: 'ws://localhost:4000',
        ws: true,
      },
    },
  },
  test: {
    globals: true,
    environment: 'jsdom',
    setupFiles: './src/test-setup.ts',
  },
})
