/// <reference types="vitest/config" />
import { defineConfig, loadEnv } from 'vite'
import vue from '@vitejs/plugin-vue'
import { fileURLToPath, URL } from 'node:url'
import { readFileSync } from 'node:fs'

const pkg = JSON.parse(readFileSync(new URL('./package.json', import.meta.url), 'utf-8')) as { version: string }

export default defineConfig(({ mode }) => {
  const env = { ...loadEnv(mode, process.cwd(), ''), ...process.env }
  const port = Number(env.FRONTEND_PORT || 3000)
  const backend = env.BACKEND_URL || 'http://localhost:3050'
  return {
    plugins: [vue()],
    define: { __APP_VERSION__: JSON.stringify(pkg.version) },
    resolve: { alias: { '@': fileURLToPath(new URL('./src', import.meta.url)) } },
    server: {
      host: '0.0.0.0',
      port,
      strictPort: true,
      // Keep the browser's Host (the backend builds game share links from the request origin)
      // and add X-Forwarded-* so the admin sees real player IPs, not the proxy's.
      proxy: {
        '/api': { target: backend, changeOrigin: false, ws: true, xfwd: true },
        '/.well-known': { target: backend, changeOrigin: false, xfwd: true },
      },
    },
    preview: { host: '0.0.0.0', port },
    build: { outDir: 'dist' },
    test: { environment: 'node', include: ['tests/**/*.test.ts'], setupFiles: ['tests/setup.ts'] },
  }
})
