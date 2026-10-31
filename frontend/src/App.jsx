import { useEffect, useState } from 'react'

import TelemetryPanel from './TelemetryPanel'
import VoiceCommandButton from './VoiceCommandButton'
import ForensicPanel from './ForensicPanel'

const STORAGE_KEY = 'pc-power-remote.pin'
const DEFAULT_PIN = '134113'
const MAC_STORAGE_KEY = 'pc-power-remote.mac'
const TIMES = [3, 5, 15, 30, 60, 90, 120, 150]
const PIN_PATTERN = /^\d{4,12}$/
const MAC_PATTERN = /^([0-9A-F]{2}:){5}[0-9A-F]{2}$/

function readStoredPin() {
  try {
    const stored = localStorage.getItem(STORAGE_KEY)
    if (stored) return stored
    // Primer arranque: se siembra el PIN por defecto (APP_PIN) para no bloquear la app.
    localStorage.setItem(STORAGE_KEY, DEFAULT_PIN)
    return DEFAULT_PIN
  } catch {
    return DEFAULT_PIN
  }
}

function storePin(pin) {
  try {
    if (pin) localStorage.setItem(STORAGE_KEY, pin)
    else localStorage.removeItem(STORAGE_KEY)
  } catch {
    // localStorage puede estar bloqueado (modo privado): la app sigue funcionando en memoria.
  }
}

function readStoredMac() {
  try {
    return localStorage.getItem(MAC_STORAGE_KEY) ?? ''
  } catch {
    return ''
  }
}

function storeMac(mac) {
  try {
    if (mac) localStorage.setItem(MAC_STORAGE_KEY, mac)
    else localStorage.removeItem(MAC_STORAGE_KEY)
  } catch {
    // idem: se mantiene solo en memoria
  }
}

function formatMacInput(value) {
  const raw = value.replace(/[^0-9a-fA-F]/g, '').slice(0, 12).toUpperCase()
  return raw.replace(/(.{2})(?=.)/g, '$1:')
}

function errorDetail(data, status) {
  if (typeof data?.detail === 'string') return data.detail
  if (Array.isArray(data?.detail)) {
    const parts = data.detail.map((item) => item?.msg).filter(Boolean)
    if (parts.length) return parts.join(' · ')
  }
  return `Error HTTP ${status}`
}

async function api(path, { pin = '', method = 'GET', body } = {}) {
  const headers = { 'X-App-Pin': pin }
  if (body !== undefined) headers['Content-Type'] = 'application/json'

  let res
  try {
    res = await fetch(path, {
      method,
      headers,
      body: body === undefined ? undefined : JSON.stringify(body),
    })
  } catch {
    const err = new Error('Sin conexion con el backend. Verifica que run_backend.bat este activo.')
    err.status = 0
    throw err
  }

  const data = await res.json().catch(() => null)
  if (!res.ok) {
    const err = new Error(errorDetail(data, res.status))
    err.status = res.status
    throw err
  }
  return data
}

function PowerIcon({ className = '' }) {
  return (
    <svg viewBox="0 0 24 24" fill="none" className={className} aria-hidden="true">
      <path
        d="M12 3v8"
        stroke="currentColor"
        strokeWidth="2"
        strokeLinecap="round"
      />
      <path
        d="M7.05 6.3a8 8 0 1 0 9.9 0"
        stroke="currentColor"
        strokeWidth="2"
        strokeLinecap="round"
      />
    </svg>
  )
}

function PinModal({ firstTime, draft, error, busy, onChange, onSubmit, onClose }) {
  return (
    <div className="fixed inset-0 z-50 grid place-items-center bg-void/85 p-4 backdrop-blur-sm">
      <form
        onSubmit={onSubmit}
        role="dialog"
        aria-modal="true"
        aria-labelledby="pin-modal-title"
        className="w-full max-w-sm border border-neon/40 bg-panel p-6 shadow-[0_0_80px_-20px_#ff2d3f]"
      >
        <p className="text-[10px] uppercase tracking-[0.4em] text-neon/70">
          acceso restringido
        </p>
        <h2 id="pin-modal-title" className="mt-1 text-lg font-bold tracking-tight text-white">
          AUTENTICACION REQUERIDA
        </h2>
        <p className="mt-2 text-xs leading-relaxed text-zinc-500">
          Introduce el PIN definido en la variable de entorno{' '}
          <span className="text-zinc-300">APP_PIN</span> para autorizar comandos de
          energia.
        </p>

        <label
          htmlFor="app-pin"
          className="mt-5 block text-[10px] uppercase tracking-[0.3em] text-zinc-500"
        >
          pin de seguridad
        </label>
        <input
          id="app-pin"
          name="pin"
          type="password"
          inputMode="numeric"
          autoComplete="current-password"
          autoFocus
          value={draft}
          onChange={(event) => onChange(event.target.value.replace(/\D/g, '').slice(0, 12))}
          placeholder="••••"
          className="mt-2 w-full border border-edge bg-void px-4 py-3 text-center text-2xl tracking-[0.6em] text-white outline-none transition focus:border-neon focus:shadow-[0_0_25px_-10px_#ff2d3f]"
        />
        {error && <p className="mt-2 text-xs text-neon-soft">{error}</p>}

        <button
          type="submit"
          disabled={busy || draft.length < 4}
          className="mt-5 w-full bg-neon py-3 text-xs font-bold uppercase tracking-[0.3em] text-void transition hover:bg-neon-soft disabled:cursor-not-allowed disabled:opacity-40"
        >
          {busy ? 'Verificando…' : 'Autorizar'}
        </button>

        {!firstTime && (
          <button
            type="button"
            onClick={onClose}
            className="mt-3 w-full py-2 text-[10px] uppercase tracking-[0.3em] text-zinc-500 transition hover:text-zinc-300"
          >
            Cancelar
          </button>
        )}
      </form>
    </div>
  )
}

function MacModal({ draft, error, fallback, fallbackSource, onChange, onSubmit, onClear, onClose }) {
  return (
    <div className="fixed inset-0 z-50 grid place-items-center bg-void/85 p-4 backdrop-blur-sm">
      <form
        onSubmit={onSubmit}
        role="dialog"
        aria-modal="true"
        aria-labelledby="mac-modal-title"
        className="w-full max-w-sm border border-emerald-500/40 bg-panel p-6 shadow-[0_0_80px_-20px_#34d399]"
      >
        <p className="text-[10px] uppercase tracking-[0.4em] text-emerald-400/80">
          wake-on-lan
        </p>
        <h2 id="mac-modal-title" className="mt-1 text-lg font-bold tracking-tight text-white">
          DIRECCION MAC
        </h2>
        <p className="mt-2 text-xs leading-relaxed text-zinc-500">
          El backend detecta la MAC de la tarjeta de red activa al arrancar. Aqui puedes
          sobrescribirla para este navegador; si lo dejas vacio se usa la autodetectada.
        </p>

        <label
          htmlFor="app-mac"
          className="mt-5 block text-[10px] uppercase tracking-[0.3em] text-zinc-500"
        >
          mac destino
        </label>
        <input
          id="app-mac"
          name="mac"
          autoComplete="off"
          spellCheck={false}
          autoFocus
          value={draft}
          onChange={(event) => onChange(formatMacInput(event.target.value))}
          placeholder="AA:BB:CC:DD:EE:FF"
          className="mt-2 w-full border border-edge bg-void px-4 py-3 text-center text-lg tracking-[0.15em] text-white outline-none transition focus:border-emerald-400 focus:shadow-[0_0_25px_-10px_#34d399]"
        />
        <p className="mt-2 text-[10px] uppercase tracking-[0.2em] text-zinc-600">
          backend: {fallback ?? 'sin mac detectada'}
          {fallback && fallbackSource === 'auto' ? ' · autodetectada' : ''}
        </p>
        {error && <p className="mt-2 text-xs text-neon-soft">{error}</p>}

        <button
          type="submit"
          className="mt-5 w-full bg-emerald-400 py-3 text-xs font-bold uppercase tracking-[0.3em] text-void transition hover:bg-emerald-300"
        >
          Guardar
        </button>
        <div className="mt-3 flex gap-2">
          <button
            type="button"
            onClick={onClear}
            className="flex-1 border border-edge py-2 text-[10px] uppercase tracking-[0.25em] text-zinc-500 transition hover:text-zinc-300"
          >
            Usar la del backend
          </button>
          <button
            type="button"
            onClick={onClose}
            className="flex-1 border border-edge py-2 text-[10px] uppercase tracking-[0.25em] text-zinc-500 transition hover:text-zinc-300"
          >
            Cancelar
          </button>
        </div>
      </form>
    </div>
  )
}

function ConfirmModal({ minutes, busy, onConfirm, onCancel }) {
  return (
    <div className="fixed inset-0 z-50 grid place-items-center bg-void/85 p-4 backdrop-blur-sm">
      <div
        role="dialog"
        aria-modal="true"
        aria-labelledby="confirm-modal-title"
        className="w-full max-w-sm border border-ember/50 bg-panel p-6 shadow-[0_0_80px_-25px_#ffb020]"
      >
        <p className="text-[10px] uppercase tracking-[0.4em] text-ember/80">
          confirmar comando
        </p>
        <h2 id="confirm-modal-title" className="mt-1 text-lg font-bold tracking-tight text-white">
          ARMAR APAGADO
        </h2>
        <p className="mt-3 text-sm leading-relaxed text-zinc-400">
          El equipo se apagara en{' '}
          <span className="font-bold text-ember">{minutes} minutos</span>. Mientras
          el temporizador este activo puedes abortarlo desde este panel.
        </p>

        <button
          type="button"
          onClick={onConfirm}
          disabled={busy}
          className="mt-6 w-full bg-ember py-3 text-xs font-bold uppercase tracking-[0.3em] text-void transition hover:brightness-110 disabled:opacity-40"
        >
          {busy ? 'Ejecutando…' : `Armar ${minutes} min`}
        </button>
        <button
          type="button"
          onClick={onCancel}
          className="mt-3 w-full py-2 text-[10px] uppercase tracking-[0.3em] text-zinc-500 transition hover:text-zinc-300"
        >
          Abortar
        </button>
      </div>
    </div>
  )
}

export default function App() {
  const [pin, setPin] = useState(readStoredPin)
  const [pinOpen, setPinOpen] = useState(false)
  const [pinDraft, setPinDraft] = useState('')
  const [pinError, setPinError] = useState('')
  const [verifying, setVerifying] = useState(false)

  const [health, setHealth] = useState({ ok: null, system: null })
  const [pending, setPending] = useState(null)
  const [now, setNow] = useState(() => Date.now())
  const [busy, setBusy] = useState(null)
  const [toast, setToast] = useState(null)
  const [confirmMinutes, setConfirmMinutes] = useState(null)

  const [mac, setMac] = useState(readStoredMac)
  const [macOpen, setMacOpen] = useState(false)
  const [macDraft, setMacDraft] = useState('')
  const [macError, setMacError] = useState('')
  const [backendMac, setBackendMac] = useState(null)
  const [backendSource, setBackendSource] = useState('none')

  // Healthcheck publico: no requiere PIN.
  useEffect(() => {
    let active = true

    const check = () => {
      fetch('/api/health')
        .then((res) => (res.ok ? res.json() : Promise.reject(new Error('offline'))))
        .then((data) => {
          if (active) setHealth({ ok: true, system: data.system ?? null })
        })
        .catch(() => {
          if (active) setHealth({ ok: false, system: null })
        })
    }

    check()
    const id = setInterval(check, 15000)
    return () => {
      active = false
      clearInterval(id)
    }
  }, [])

  // Estado del temporizador (protegido): se refresca al cambiar el PIN y cada 10 s.
  useEffect(() => {
    if (!pin) return undefined

    let active = true
    const load = () => {
      api('/api/state', { pin })
        .then((data) => {
          if (active) setPending(data.pending ? data : null)
        })
        .catch(() => {
          // El poll no interrumpe la UI; los errores de accion si se muestran.
        })
    }

    load()
    const id = setInterval(load, 10000)
    return () => {
      active = false
      clearInterval(id)
    }
  }, [pin])

  // Reloj del countdown.
  useEffect(() => {
    if (!pending) return undefined
    const id = setInterval(() => setNow(Date.now()), 1000)
    return () => clearInterval(id)
  }, [pending])

  // Configuracion de Wake-on-LAN del backend (MAC por defecto, broadcast y puerto).
  useEffect(() => {
    if (!pin) return undefined

    let active = true
    api('/api/config', { pin })
      .then((data) => {
        if (active) {
          setBackendMac(data.mac_address ?? null)
          setBackendSource(data.source ?? 'none')
        }
      })
      .catch(() => {
        if (active) {
          setBackendMac(null)
          setBackendSource('none')
        }
      })

    return () => {
      active = false
    }
  }, [pin])

  // Auto-cierre de la notificacion.
  useEffect(() => {
    if (!toast) return undefined
    const id = setTimeout(() => setToast(null), 7000)
    return () => clearTimeout(id)
  }, [toast])

  const requireNewPin = (message) => {
    storePin('')
    setPin('')
    setPinDraft('')
    setPinError(message)
    setMacOpen(false)
    setPinOpen(true)
  }

  const executeVoiceCommand = (text) => {
    const normalized = text.trim().toLowerCase()
    setBusy('voice')
    setToast({
      tone: 'info',
      title: 'Orden de voz detectada',
      message: `Comando: "${normalized}"`,
    })
    // Pequeño delay para que el usuario vea el toast antes de la accion
    setTimeout(() => {
      if (normalized === 'apagar') {
        scheduleShutdown(5)
      } else if (normalized === 'estado') {
        fetch('/api/state', { headers: { 'X-App-Pin': pin } })
          .then((r) => r.json())
          .then((data) => setPending(data.pending ? data : null))
      } else if (normalized === 'suspender') {
        fetch('/api/system/suspend', {
          method: 'POST',
          headers: { 'X-App-Pin': pin },
        })
          .then((r) => r.json())
          .then((data) => setToast({ tone: 'success', title: 'Suspensión', message: data.message }))
      } else if (normalized === 'reiniciar') {
        // No hay endpoint de reinicio aún, mostramos feedback
        setToast({ tone: 'info', title: 'Reinicio', message: 'Endopint de reinicio no disponible aún' })
      } else if (normalized === 'despertar') {
        fetch('/api/wake', {
          method: 'POST',
          headers: { 'X-App-Pin': pin },
        })
          .then((r) => r.json())
          .then((data) =>
            setToast({
              tone: 'success',
              title: 'WOL',
              message: `WOL a ${data.mac} via ${data.broadcast}:${data.port}.`,
            })
          )
      } else if (normalized === 'cancelar') {
        fetch('/api/cancel', {
          method: 'POST',
          headers: { 'X-App-Pin': pin },
        })
          .then(() => setToast({ tone: 'success', title: 'Cancelado', message: 'Apagado cancelado' }))
          .then(() => fetch('/api/state', { headers: { 'X-App-Pin': pin } }))
          .then((r) => r.json())
          .then((data) => setPending(data.pending ? data : null))
      } else {
        setToast({ tone: 'error', title: 'Comando no reconocido', message: `No reconozco el comando: "${normalized}"` })
      }
      setBusy(null)
    }, 800)
  }

  const handleError = (err, title) => {
    if (err.status === 401) {
      requireNewPin('El PIN configurado no es valido para este equipo.')
    }
    setToast({ tone: 'error', title, message: err.message })
  }

  const submitPin = async (event) => {
    event.preventDefault()
    const candidate = pinDraft.trim()

    if (!PIN_PATTERN.test(candidate)) {
      setPinError('El PIN debe tener entre 4 y 12 digitos.')
      return
    }

    setVerifying(true)
    setPinError('')
    try {
      await api('/api/state', { pin: candidate })
      storePin(candidate)
      setPin(candidate)
      setPinOpen(false)
      setPinDraft('')
      setToast({
        tone: 'success',
        title: 'Acceso autorizado',
        message: 'PIN verificado contra el backend.',
      })
    } catch (err) {
      setPinError(
        err.status === 401
          ? 'PIN incorrecto. Intenta de nuevo.'
          : `No se pudo verificar el PIN: ${err.message}`,
      )
    } finally {
      setVerifying(false)
    }
  }

  const scheduleShutdown = async (minutes) => {
    setConfirmMinutes(null)
    setBusy('shutdown')
    try {
      const data = await api('/api/shutdown', {
        pin,
        method: 'POST',
        body: { minutes },
      })
      setPending({
        pending: true,
        minutes: data.minutes,
        ends_at: data.ends_at,
        seconds_left: data.seconds,
      })
      setNow(Date.now())
      setToast({
        tone: 'success',
        title: 'Apagado armado',
        message: `El equipo se apagara en ${data.minutes} minutos.`,
      })
    } catch (err) {
      handleError(err, 'No se pudo armar el apagado')
    } finally {
      setBusy(null)
    }
  }

  const cancelShutdown = async () => {
    setBusy('cancel')
    try {
      await api('/api/cancel', { pin, method: 'POST' })
      setPending(null)
      setToast({
        tone: 'success',
        title: 'Apagado cancelado',
        message: 'El temporizador fue abortado. El equipo sigue encendido.',
      })
    } catch (err) {
      if (err.status === 409) {
        // Windows dice que no habia nada programado: el estado local estaba obsoleto.
        setPending(null)
        setToast({
          tone: 'info',
          title: 'Sin apagado pendiente',
          message: 'No habia un temporizador activo en el sistema.',
        })
        return
      }
      handleError(err, 'No se pudo cancelar el apagado')
    } finally {
      setBusy(null)
    }
  }

  const openMac = () => {
    setMacDraft(mac)
    setMacError('')
    setMacOpen(true)
  }

  const applyMac = (value) => {
    storeMac(value)
    setMac(value)
    setMacOpen(false)
    setMacDraft('')
    setMacError('')
    setToast(
      value
        ? {
            tone: 'success',
            title: 'MAC guardada',
            message: `Los paquetes de encendido se enviaran a ${value}.`,
          }
        : {
            tone: 'info',
            title: 'MAC local borrada',
            message: 'Se usara la MAC autodetectada por el backend.',
          },
    )
  }

  const saveMac = (event) => {
    event.preventDefault()
    const candidate = macDraft.trim().toUpperCase()

    if (candidate && !MAC_PATTERN.test(candidate)) {
      setMacError('MAC invalida: usa el formato AA:BB:CC:DD:EE:FF.')
      return
    }

    applyMac(candidate)
  }

  const wakePc = async () => {
    setBusy('wake')
    try {
      const data = await api('/api/wake', {
        pin,
        method: 'POST',
        body: mac ? { mac } : {},
      })
      setToast({
        tone: 'success',
        title: 'Paquete magico enviado',
        message: `WOL a ${data.mac} via ${data.broadcast}:${data.port}. El PC deberia encender en unos segundos.`,
      })
    } catch (err) {
      if (err.status === 409) {
        setMacDraft(mac)
        setMacError(err.message)
        setMacOpen(true)
      }
      handleError(err, 'No se pudo enviar Wake-on-LAN')
    } finally {
      setBusy(null)
    }
  }

  const secondsLeft = pending
    ? Math.max(0, Math.ceil((new Date(pending.ends_at).getTime() - now) / 1000))
    : 0
  const clock = `${String(Math.floor(secondsLeft / 60)).padStart(2, '0')}:${String(
    secondsLeft % 60,
  ).padStart(2, '0')}`
  const progress = pending
    ? Math.max(0, Math.min(100, (secondsLeft / (pending.minutes * 60)) * 100))
    : 0
  const executesAt = pending
    ? new Date(pending.ends_at).toLocaleTimeString('es-PY', {
        hour: '2-digit',
        minute: '2-digit',
      })
    : null

  const locked = !pin || busy !== null

  const toastStyles =
    toast?.tone === 'error'
      ? 'border-neon/50 bg-neon/10 text-neon-soft'
      : toast?.tone === 'info'
        ? 'border-ember/50 bg-ember/10 text-ember'
        : 'border-emerald-500/40 bg-emerald-500/10 text-emerald-300'

  return (
    <div className="relative min-h-full overflow-hidden">
      <div className="grid-bg pointer-events-none fixed inset-0" aria-hidden="true" />
      <div className="scanlines pointer-events-none fixed inset-0" aria-hidden="true" />

      <main className="relative mx-auto flex min-h-full w-full max-w-xl flex-col gap-5 px-4 py-8 sm:px-6">
        <header className="flex items-start justify-between gap-4">
          <div className="flex items-center gap-3">
            <div className="grid size-11 shrink-0 place-items-center border border-neon/50 bg-neon/5 text-neon shadow-[0_0_28px_-12px_#ff2d3f]">
              <PowerIcon className="size-5" />
            </div>
            <div>
              <p className="text-[10px] uppercase tracking-[0.4em] text-neon/70">
                t-800 // terminal
              </p>
              <h1 className="flicker text-xl font-bold tracking-tight text-white sm:text-2xl">
                PC POWER <span className="text-glow text-neon">REMOTE</span>
              </h1>
            </div>
          </div>

          <div className="flex flex-col items-end gap-2">
            <span
              className={`flex items-center gap-2 border px-2.5 py-1 text-[10px] font-bold uppercase tracking-[0.2em] ${
                health.ok === false
                  ? 'border-neon/50 bg-neon/10 text-neon'
                  : 'border-emerald-500/40 bg-emerald-500/10 text-emerald-300'
              }`}
            >
              <span
                className={`size-1.5 rounded-full ${
                  health.ok === false
                    ? 'led bg-neon'
                    : health.ok === true
                      ? 'led-ok bg-emerald-400'
                      : 'bg-zinc-500'
                }`}
              />
              {health.ok === null ? 'enlazando' : health.ok ? 'online' : 'offline'}
            </span>
            <button
              type="button"
              onClick={() => {
                setPinDraft('')
                setPinError('')
                setPinOpen(true)
              }}
              className="text-[10px] uppercase tracking-[0.25em] text-zinc-500 transition hover:text-neon"
            >
              pin {pin ? '••••' : 'sin definir'} · cambiar
            </button>
          </div>
        </header>

        <section className="border border-edge bg-panel/80 p-5">
          <div className="flex items-center justify-between gap-3">
            <p className="text-[10px] uppercase tracking-[0.35em] text-emerald-400/80">
              wake-on-lan
            </p>
            <button
              type="button"
              onClick={openMac}
              className="text-[10px] uppercase tracking-[0.25em] text-zinc-500 transition hover:text-emerald-300"
            >
              mac · editar
            </button>
          </div>

          <button
            type="button"
            onClick={wakePc}
            disabled={locked}
            className="mt-4 flex w-full items-center justify-center gap-3 border border-emerald-500/60 bg-emerald-500/10 py-4 text-xs font-bold uppercase tracking-[0.3em] text-emerald-300 shadow-[0_0_40px_-18px_#34d399] transition hover:bg-emerald-400 hover:text-void disabled:cursor-not-allowed disabled:opacity-40 disabled:hover:bg-emerald-500/10 disabled:hover:text-emerald-300"
          >
            <PowerIcon className="size-4" />
            {busy === 'wake' ? 'Enviando paquete…' : 'Encender PC'}
          </button>

          <p className="mt-3 flex items-center justify-center gap-2 text-[10px] uppercase tracking-[0.2em] text-zinc-600">
            <span className="truncate">
              destino: {mac || backendMac || 'sin mac disponible'}
            </span>
            {!mac && backendMac && (
              <span className="shrink-0 border border-emerald-500/40 px-1.5 py-0.5 text-[9px] tracking-[0.15em] text-emerald-400/90">
                {backendSource === 'auto' ? 'autodetectada' : 'backend'}
              </span>
            )}
          </p>
        </section>

        <TelemetryPanel
          key={pin}
          pin={pin}
          onAuthError={(message) => requireNewPin(message)}
        />

        <VoiceCommandButton onCommand={executeVoiceCommand} />

        <ForensicPanel />

        <section className="relative border border-edge bg-panel/80 p-5">
          {pending ? (
            <>
              <div className="flex items-center justify-between gap-3">
                <p className="text-[10px] uppercase tracking-[0.35em] text-neon/80">
                  apagado armado
                </p>
                <p className="text-[10px] uppercase tracking-[0.2em] text-zinc-500">
                  {pending.minutes} min
                </p>
              </div>

              <p className="text-glow mt-4 text-center text-6xl font-bold tabular-nums text-neon">
                {clock}
              </p>
              <p className="mt-2 text-center text-[10px] uppercase tracking-[0.25em] text-zinc-500">
                ejecucion a las {executesAt}
              </p>

              <div className="mt-5 h-1 w-full overflow-hidden bg-edge">
                <div
                  className="h-full bg-neon transition-[width] duration-1000 ease-linear"
                  style={{ width: `${progress}%` }}
                />
              </div>
            </>
          ) : (
            <div className="py-6 text-center">
              <p className="text-[10px] uppercase tracking-[0.35em] text-zinc-600">
                sin apagado programado
              </p>
              <p className="mt-2 text-xs text-zinc-500">
                Selecciona un intervalo para armar el temporizador.
              </p>
            </div>
          )}
        </section>

        <section>
          <div className="mb-3 flex items-center justify-between text-[10px] uppercase tracking-[0.35em] text-zinc-500">
            <span>armar temporizador</span>
            <span className="text-zinc-700">minutos</span>
          </div>

          <div className="flex flex-wrap gap-2">
            {TIMES.map((minutes) => (
              <button
                key={minutes}
                type="button"
                disabled={locked}
                onClick={() => setConfirmMinutes(minutes)}
                className="group min-w-[4.6rem] flex-1 border border-edge bg-panel px-3 py-3 text-left transition hover:border-neon/70 hover:bg-neon/5 disabled:cursor-not-allowed disabled:opacity-40 disabled:hover:border-edge disabled:hover:bg-panel"
              >
                <span className="block text-2xl font-bold tabular-nums text-white transition group-hover:text-neon group-disabled:group-hover:text-white">
                  {String(minutes).padStart(2, '0')}
                </span>
                <span className="block text-[9px] uppercase tracking-[0.3em] text-zinc-600">
                  min
                </span>
              </button>
            ))}
          </div>
        </section>

        {/* Botón central Terminator - Apagado inmediato nivel elite */}
        <div className="mt-6 flex items-center justify-center">
          <button
            type="button"
            onClick={() => {
              const confirmed = window.confirm('¿APAGADO INMEDIATO NIVEL TERMINATOR?\nEl equipo se apagara al instante.\n¿Continuar?');
              if (confirmed) {
                scheduleShutdown(0);
              }
            }}
            className="relative group w-full max-w-sm bg-neon/20 border-2 border-red-500/50 rounded-lg py-4 px-6 text-center text-[12px] uppercase font-bold tracking-[0.3em] text-red-400 shadow-[0_0_30px_-10px_#ff0000] transition-all duration-300 hover:shadow-[0_0_50px_-15px_#ff3333] hover:text-red-300 active:shadow-[0_0_20px_-10px_#cc0000] disabled:opacity-40 disabled:cursor-not-allowed"
            disabled={locked}
            aria-label="Apagado inmediato nivel Terminator"
          >
            <span className="relative">APAGADO AUTOMÁTICO NIVEL TERMINATOR</span>
            <svg class="absolute -inset-0.5 opacity-0 group-hover:opacity-100 transition-opacity duration-300" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
              <path d="M18 6L6 18M6 6l12 12"/>
            </svg>
          </button>
        </div>

        <button
          type="button"
          onClick={cancelShutdown}
          disabled={locked}
          className="w-full border border-neon/60 bg-neon/10 py-4 text-xs font-bold uppercase tracking-[0.3em] text-neon shadow-[0_0_40px_-18px_#ff2d3f] transition hover:bg-neon hover:text-void disabled:cursor-not-allowed disabled:opacity-40 disabled:hover:bg-neon/10 disabled:hover:text-neon"
        >
          {busy === 'cancel' ? 'Abortando…' : 'Cancelar apagado'}
        </button>

        {toast && (
          <div
            role="status"
            className={`flex items-start gap-3 border px-4 py-3 ${toastStyles}`}
          >
            <span className="mt-1 size-1.5 shrink-0 rounded-full bg-current" />
            <div className="flex-1">
              <p className="text-[10px] font-bold uppercase tracking-[0.25em]">
                {toast.title}
              </p>
              <p className="mt-1 text-xs text-zinc-400">{toast.message}</p>
            </div>
            <button
              type="button"
              onClick={() => setToast(null)}
              aria-label="Cerrar notificacion"
              className="text-sm leading-none text-zinc-500 transition hover:text-zinc-200"
            >
              ×
            </button>
          </div>
        )}

        <footer className="mt-auto flex items-center justify-between gap-3 border-t border-edge pt-3 text-[9px] uppercase tracking-[0.25em] text-zinc-700">
          <span>auth · x-app-pin</span>
          <span>{health.system ?? 'windows'} · v0.6.0</span>
        </footer>
      </main>

      {pinOpen && (
        <PinModal
          firstTime={!pin}
          draft={pinDraft}
          error={pinError}
          busy={verifying}
          onChange={setPinDraft}
          onSubmit={submitPin}
          onClose={() => {
            setPinOpen(false)
            setPinError('')
            setPinDraft('')
          }}
        />
      )}

      {macOpen && (
        <MacModal
          draft={macDraft}
          error={macError}
          fallback={backendMac}
          fallbackSource={backendSource}
          onChange={setMacDraft}
          onSubmit={saveMac}
          onClear={() => applyMac('')}
          onClose={() => {
            setMacOpen(false)
            setMacError('')
            setMacDraft('')
          }}
        />
      )}

      {confirmMinutes !== null && (
        <ConfirmModal
          minutes={confirmMinutes}
          busy={busy === 'shutdown'}
          onConfirm={() => scheduleShutdown(confirmMinutes)}
          onCancel={() => setConfirmMinutes(null)}
        />
      )}
    </div>
  )
}
