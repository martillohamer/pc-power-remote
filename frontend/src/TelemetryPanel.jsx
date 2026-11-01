import { useEffect, useRef, useState } from 'react'

const RECONNECT_MIN_MS = 1500
const RECONNECT_MAX_MS = 8000

const TONES = {
  ok: {
    bar: 'bg-emerald-400',
    text: 'text-emerald-300',
    glow: 'shadow-[0_0_18px_-6px_#34d399]',
  },
  warn: {
    bar: 'bg-ember',
    text: 'text-ember',
    glow: 'shadow-[0_0_18px_-6px_#ffb020]',
  },
  crit: {
    bar: 'bg-neon',
    text: 'text-neon-soft',
    glow: 'shadow-[0_0_18px_-6px_#ff2d3f]',
  },
}

function socketUrl(pin) {
  const protocol = window.location.protocol === 'https:' ? 'wss:' : 'ws:'
  return `${protocol}//${window.location.host}/ws/telemetry?pin=${encodeURIComponent(pin)}`
}

function toneFor(value) {
  if (value >= 85) return 'crit'
  if (value >= 65) return 'warn'
  return 'ok'
}

function formatUptime(totalSeconds) {
  if (!Number.isFinite(totalSeconds) || totalSeconds < 0) return '--'
  const days = Math.floor(totalSeconds / 86400)
  const hours = Math.floor((totalSeconds % 86400) / 3600)
  const minutes = Math.floor((totalSeconds % 3600) / 60)
  if (days > 0) return `${days}d ${hours}h ${minutes}m`
  if (hours > 0) return `${hours}h ${minutes}m`
  return `${minutes}m`
}

function formatMb(megabytes) {
  if (!Number.isFinite(megabytes)) return '--'
  if (megabytes >= 1024) return `${(megabytes / 1024).toFixed(1)} GB`
  return `${Math.round(megabytes)} MB`
}

function Metric({ label, value, detail }) {
  const hasValue = typeof value === 'number' && Number.isFinite(value)
  const safe = hasValue ? Math.max(0, Math.min(100, value)) : 0
  const tone = TONES[toneFor(safe)]

  return (
    <div>
      <div className="flex items-baseline justify-between gap-2">
        <p className="text-[10px] uppercase tracking-[0.3em] text-zinc-500">{label}</p>
        <p className={`text-lg font-bold tabular-nums ${hasValue ? tone.text : 'text-zinc-600'}`}>
          {hasValue ? value.toFixed(1) : '--'}
          <span className="ml-0.5 text-[10px] font-normal text-zinc-600">%</span>
        </p>
      </div>
      <div className="mt-2 h-1.5 w-full overflow-hidden bg-edge">
        <div
          className={`h-full ${tone.bar} ${tone.glow} transition-[width] duration-700 ease-out`}
          style={{ width: `${safe}%` }}
        />
      </div>
      <p className="mt-1.5 truncate text-[10px] uppercase tracking-[0.18em] text-zinc-600">
        {detail}
      </p>
    </div>
  )
}

export default function TelemetryPanel({ pin, onAuthError }) {
  const [telemetry, setTelemetry] = useState(null)
  const [status, setStatus] = useState(() => (pin ? 'connecting' : 'idle'))
  const authErrorRef = useRef(onAuthError)

  useEffect(() => {
    authErrorRef.current = onAuthError
  }, [onAuthError])

  useEffect(() => {
    if (!pin) return undefined

    let active = true
    let socket = null
    let retryId = null
    let delay = RECONNECT_MIN_MS

    const connect = () => {
      if (!active) return

      socket = new WebSocket(socketUrl(pin))

      socket.onopen = () => {
        if (!active) return
        delay = RECONNECT_MIN_MS
        setStatus('live')
      }

      socket.onmessage = (event) => {
        if (!active) return
        try {
          const payload = JSON.parse(event.data)
          if (!payload || payload.error) return
          setTelemetry(payload)
        } catch {
          // Frame corrupto: se ignora y se espera la siguiente muestra.
        }
      }

      socket.onclose = (event) => {
        if (!active) return

        if (event.code === 1008) {
          setStatus('idle')
          authErrorRef.current?.('PIN rechazado por el monitor de telemetria.')
          return
        }

        setStatus('reconnecting')
        retryId = setTimeout(connect, delay)
        delay = Math.min(delay * 2, RECONNECT_MAX_MS)
      }

      socket.onerror = () => {
        socket?.close()
      }
    }

    connect()

    return () => {
      active = false
      clearTimeout(retryId)
      if (socket) {
        socket.onclose = null
        socket.onerror = null
        socket.close()
      }
    }
  }, [pin])

  const live = status === 'live'
  const label =
    status === 'live'
      ? 'LIVE TELEMETRY'
      : status === 'reconnecting'
        ? 'RECONNECTING'
        : status === 'connecting'
          ? 'CONNECTING'
          : 'TELEMETRY OFF'

  const ledClass = live
    ? 'bg-emerald-400 led-ok'
    : status === 'reconnecting'
      ? 'bg-ember led'
      : status === 'connecting'
        ? 'bg-ember led'
        : 'bg-zinc-700'

  const cpu = telemetry?.cpu_usage
  const ram = telemetry?.ram_usage
  const disk = telemetry?.disk_usage

  return (
    <section className="relative border border-edge bg-panel/80 p-5">
      <div className="flex items-center justify-between gap-3">
        <p className="text-[10px] uppercase tracking-[0.35em] text-zinc-500">
          telemetria del sistema
        </p>
        <div className="flex items-center gap-2">
          <span className={`size-2 rounded-full ${ledClass}`} />
          <span
            className={`text-[10px] font-bold uppercase tracking-[0.25em] ${
              live ? 'text-emerald-300' : status === 'idle' ? 'text-zinc-600' : 'text-ember'
            }`}
          >
            {label}
          </span>
        </div>
      </div>

      <div className="mt-5 grid gap-5 sm:grid-cols-3">
        <Metric
          label="cpu"
          value={cpu}
          detail={telemetry ? 'procesador · 1.5 s' : 'esperando datos'}
        />
        <Metric
          label="ram"
          value={ram}
          detail={
            telemetry
              ? `${formatMb(telemetry.ram_used_mb)} / ${formatMb(telemetry.ram_total_mb)}`
              : 'esperando datos'
          }
        />
        <Metric
          label="disco"
          value={disk}
          detail={telemetry ? 'volumen del sistema' : 'esperando datos'}
        />
      </div>

      <div className="mt-5 flex items-center justify-between gap-3 border-t border-edge pt-3 text-[10px] uppercase tracking-[0.2em] text-zinc-600">
        <span>uptime: {formatUptime(telemetry?.uptime_seconds)}</span>
        <span className="truncate">
          {live
            ? 'socket ws/telemetry · activo'
            : status === 'reconnecting'
              ? 'reintentando conexion'
              : 'sin muestras'}
        </span>
      </div>
    </section>
  )
}
