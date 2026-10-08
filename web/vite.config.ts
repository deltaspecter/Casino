import { defineConfig, type Plugin } from 'vite'
import preact from '@preact/preset-vite'
import { createHash } from 'node:crypto'
import { readdirSync, statSync } from 'node:fs'
import { join, relative } from 'node:path'

/**
 * Erzeugt den Service Worker mit einer vollständigen Liste aller Dateien des Builds.
 * Dadurch funktioniert die App nach dem ersten Öffnen komplett offline.
 */
function serviceWorker(): Plugin {
  return {
    name: 'blackcasino-service-worker',
    apply: 'build',
    generateBundle(_options, bundle) {
      const files = new Set<string>(['./', './index.html', './manifest.webmanifest'])
      for (const name of Object.keys(bundle)) files.add('./' + name)
      const walk = (dir: string) => {
        for (const entry of readdirSync(dir)) {
          const full = join(dir, entry)
          if (statSync(full).isDirectory()) walk(full)
          else files.add('./' + relative('public', full).split('\\').join('/'))
        }
      }
      walk('public')
      const list = [...files].filter((f) => f !== './sw.js').sort()
      const version = createHash('sha256').update(list.join('|') + Date.now()).digest('hex').slice(0, 12)
      const source = `// Automatisch erzeugt – nicht bearbeiten.
const CACHE = 'blackcasino-${version}'
const FILES = ${JSON.stringify(list)}

self.addEventListener('install', (event) => {
  event.waitUntil(caches.open(CACHE).then((cache) => cache.addAll(FILES)))
})

self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches.keys()
      .then((keys) => Promise.all(keys.filter((k) => k !== CACHE).map((k) => caches.delete(k))))
      .then(() => self.clients.claim()),
  )
})

self.addEventListener('message', (event) => {
  if (event.data === 'skipWaiting') self.skipWaiting()
})

self.addEventListener('fetch', (event) => {
  const request = event.request
  if (request.method !== 'GET') return
  const url = new URL(request.url)
  if (url.origin !== self.location.origin) return
  if (request.mode === 'navigate') {
    // Seite: zuerst Netz (für Updates), sonst Cache – so startet die App auch offline.
    event.respondWith(
      fetch(request).then((response) => {
        const copy = response.clone()
        caches.open(CACHE).then((cache) => cache.put('./index.html', copy))
        return response
      }).catch(() => caches.match('./index.html', { ignoreSearch: true })),
    )
    return
  }
  event.respondWith(
    caches.match(request, { ignoreSearch: true }).then((cached) => cached || fetch(request)),
  )
})
`
      this.emitFile({ type: 'asset', fileName: 'sw.js', source })
    },
  }
}

// base './' – läuft unter jeder Unterseite (z. B. GitHub Pages /Casino/).
export default defineConfig({
  base: './',
  plugins: [preact(), serviceWorker()],
  define: { __APP_VERSION__: JSON.stringify(process.env.npm_package_version ?? '1.0.0') },
  build: { target: 'es2022', assetsInlineLimit: 0, chunkSizeWarningLimit: 900 },
  test: { environment: 'node', include: ['tests/**/*.test.ts'] },
} as any)
