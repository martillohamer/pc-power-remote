import { useEffect, useState } from "react"

const FORENSIC_API_BASE = "/api/forensic"

// Estilos T-800 para el panel forense
const forensicStyles = {
  panel: "border border-emerald-500/40 bg-panel/80 p-4 rounded-lg mb-4",
  table: "table-fixed w-full rounded-lg overflow-hidden",
  header: "text-[10px] uppercase tracking-[0.3em] text-emerald-400/80 border-b border-emerald-500/20 pb-2 mb-4",
  title: "text-white font-bold tracking-tight",
  loading: "text-emerald-400 text-sm italic",
  empty: "text-zinc-500 text-sm",
  button: "mt-3 px-4 py-2 text-[10px] uppercase font-bold tracking-[0.2em] transition-colors hover:border-emerald-300 focus:outline-none focus:ring-2 focus:ring-emerald-400/50",
  badge: "inline-flex items-center px-2 py-0.5 text-[8px] uppercase tracking-[0.1em] bg-emerald-500/20 text-emerald-300 rounded border border-emerald-500/40",
  statusGood: "bg-emerald-500/20 border-emerald-500/40 text-emerald-300",
  statusWarning: "bg-amber-500/20 border-amber-500/40 text-amber-300",
  statusCritical: "bg-red-500/20 border-red-500/40 text-red-300",
}

export default function ForensicPanel() {
  const [processes, setProcesses] = useState([])
  const [logs, setLogs] = useState([])
  const [loading, setLoading] = useState({
    processes: false,
    logs: false,
  })
  const [error, setError] = useState(null)

  // Cargar procesos forenses
  const loadProcesses = async () => {
    setLoading((prev) => ({ ...prev, processes: true }))
    setError(null)
    try {
      const res = await fetch(`${FORENSIC_API_BASE}/processes`, {
        headers: { "X-App-Pin": "134113" },
      })
      if (!res.ok) {
        const txt = await res.text()
        throw new Error(`Error ${res.status}: ${txt}`)
      }
      const data = await res.json()
      setProcesses(data)
    } catch (e) {
      console.error("Error loading forensic processes:", e)
      setError(e.message || "Error desconocido cargando procesos")
    } finally {
      setLoading((prev) => ({ ...prev, processes: false }))
    }
  }

  // Cargar logs forenses
  const loadLogs = async () => {
    setLoading((prev) => ({ ...prev, logs: true }))
    setError(null)
    try {
      const res = await fetch(`${FORENSIC_API_BASE}/logs`, {
        headers: { "X-App-Pin": "134113" },
      })
      if (!res.ok) {
        const txt = await res.text()
        throw new Error(`Error ${res.status}: ${txt}`)
      }
      const data = await res.json()
      setLogs(data)
    } catch (e) {
      console.error("Error loading forensic logs:", e)
      setError(e.message || "Error desconocido cargando logs")
    } finally {
      setLoading((prev) => ({ ...prev, logs: false }))
    }
  }

  useEffect(() => {
    loadProcesses()
    loadLogs()
    // Refrescar cada 5 segundos
    const intervalId = setInterval(() => {
      loadProcesses()
      loadLogs()
    }, 5000)
    return () => clearInterval(intervalId)
  }, [])

  // Si hay error mostrar mensaje
  if (error) {
    return (
      <div className="p-4 text-red-400 border border-red-500/20 rounded">
        <p className="text-sm">{error}</p>
      </div>
    )
  }

  // Helper function to get border class based on event type
  function getBorderClass(event) {
    if (event === "suspension") return "border-emerald-500"
    if (event === "cpu_pico") return "border-amber-500"
    if (event === "restart") return "border-red-500"
    return "border-zinc-500"
  }

  return (
    <div className={forensicStyles.panel}>
      <header className={forensicStyles.header}>
        <h2 className={forensicStyles.title}>CÁJA NEGRA FORENSE</h2>
        <p className="text-[10px] text-zinc-400/60">
          Diagnóstico de procesos y eventos críticos del sistema
        </p>
      </header>

      {/* Sección de procesos */}
      <div>
        <div className="flex items-center justify-between gap-2 mb-3">
          <span className="text-[10px] text-zinc-400">
            Procesos de mayor consumo (Top 10)
          </span>
          <button
            onClick={loadProcesses}
            className={forensicStyles.button}
            disabled={loading.processes}
          >
            {loading.processes ? "Actualizando..." : "Actualizar"}
          </button>
        </div>

        {loading.processes && <p className={forensicStyles.loading}>Obteniendo procesos...</p>}

        {processes.length === 0 && !loading.processes && (
          <p className={forensicStyles.empty}>No hay procesos para mostrar</p>
        )}

        {processes.length > 0 && (
          <div className="overflow-x-auto">
            <table className={forensicStyles.table}>
              <thead>
                <tr className="border-b border-emerald-500/20">
                  <th className="text-[9px] font-medium text-zinc-400 uppercase tracking-[0.1em]">
                    PID
                  </th>
                  <th className="text-[9px] font-medium text-zinc-400 uppercase tracking-[0.1em]">
                    Nombre
                  </th>
                  <th className="text-[9px] font-medium text-zinc-400 uppercase tracking-[0.1em]">
                    CPU %
                  </th>
                  <th className="text-[9px] font-medium text-zinc-400 uppercase tracking-[0.1em]">
                    Memoria (MB)
                  </th>
                  <th className="hidden sm:table-cell text-[9px] font-medium text-zinc-400 uppercase tracking-[0.1em]">
                    Status
                  </th>
                </tr>
              </thead>
              <tbody>
                {processes.map((proc) => (
                  <tr
                    key={proc.pid}
                    className="border-b border-emerald-500/10 hover:bg-panel/50"
                  >
                    <td className="text-[9px] font-mono text-zinc-300">{proc.pid}</td>
                    <td className="text-[9px] font-medium text-zinc-200">{proc.name}</td>
                    <td>
                      <div className="relative h-3 w-full overflow-hidden rounded-full bg-panel/50">
                        <div
                          style={{ width: `${Math.min(100, proc.cpu_percent)}%` }}
                          className="h-full rounded-full bg-emerald-500 transition-[width] duration-500"
                        />
                        <span className="absolute inset-y-0 right-1 flex items-center text-[9px] text-emerald-100">
                          {proc.cpu_percent.toFixed(1)}%
                        </span>
                      </div>
                    </td>
                    <td className="text-[9px] font-mono text-zinc-300">
                      {proc.memory_mb.toFixed(1)}
                    </td>
                    <td className="hidden sm:table-cell text-[9px] text-zinc-400">{proc.status}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </div>

      {/* Sección de logs */}
      <div mt-6>
        <div className="flex items-center justify-between gap-2 mb-3">
          <span className="text-[10px] text-zinc-400">
            Log circular de eventos críticos
          </span>
          <button
            onClick={loadLogs}
            className={forensicStyles.button}
            disabled={loading.logs}
          >
            {loading.logs ? "Actualizando..." : "Actualizar"}
          </button>
        </div>

        {loading.logs && <p className={forensicStyles.loading}>Obteniendo logs...</p>}

        {logs.length === 0 && !loading.logs && (
          <p className={forensicStyles.empty}>No hay eventos registrados</p>
        )}

        {logs.length > 0 && (
          <div className="space-y-2 max-h-96 overflow-y-auto">
            {logs.map((entry, index) => (
              <div
                key={index}
                className={getBorderClass(entry.event)}
              >
                <span className="text-[8px] uppercase tracking-[0.1em] text-zinc-500">
                  {entry.timestamp.substring(11, 16)}
                </span>
                <strong className="text-[8px] text-emerald-300">{entry.event}</strong>
                <span className="text-[8px] text-zinc-400 ml-2">
                  {entry.details}
                </span>
              </div>
            ))}
          </div>
        )}
      </div>
    </div>
  )
}
