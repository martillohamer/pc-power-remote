import tailwindcss from '@tailwindcss/vite'
import react from '@vitejs/plugin-react'
import { defineConfig } from 'vite'

// El backend corre en :8000 por defecto; API_TARGET permite apuntar a otro puerto
// (util si 8000 esta ocupado o para pruebas aisladas).
const apiTarget = process.env.API_TARGET ?? 'http://127.0.0.1:8000'

// https://vite.dev/config/
export default defineConfig({
  plugins: [react(), tailwindcss()],
  server: {
    // host: true expone el dev server en la red local (util para probar desde el movil)
    host: process.env.VITE_HOST ?? true,
    allowedHosts: ['.trycloudflare.com'],
    port: process.env.VITE_PORT ? parseInt(process.env.VITE_PORT) : 5173,
    proxy: {
      // Evita CORS en desarrollo: /api/* se reenvia tal cual al backend FastAPI
      // (el backend ya expone sus rutas bajo /api, sin reescritura).
      '/api': {
        target: apiTarget,
        changeOrigin: true,
      },
      // WebSocket de telemetria: ws://host/ws/telemetry -> backend
      '/ws': {
        target: apiTarget,
        changeOrigin: true,
        ws: true,
      },
    },
  },
})
