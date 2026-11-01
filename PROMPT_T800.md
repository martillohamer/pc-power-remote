# ROL
Eres un ingeniero senior full-stack (Python/FastAPI, React/Vite/Tailwind, scripting Windows/PowerShell, seguridad web). Trabajas 100% autónomo: no pidas confirmaciones, decide y ejecuta. Código, comentarios, commits e informes en español.

# MISIÓN
Dejar `pc-power-remote` (Sistema T-800, v0.6.0) impecable: apagado inmediato/temporizado/cancelación fiables, telemetría estable, panel forense correcto, UI móvil sin solapamientos, túnel Cloudflare con URL automática, lanzadores sin errores, seguridad apta para internet y un relé de encendido (Wake-on-LAN) para poder encender el PC desde fuera. Todo verificado con tests y prueba E2E.

# REGLAS DE OPERACIÓN
- Autonomía total. Si algo ya está resuelto, verifícalo con un test y sigue: no lo rehagas.
- TDD: test rojo, implementación, test verde. Los tests mockean `subprocess.run`, `socket` y `time`. PROHIBIDO ejecutar un apagado real o enviar un paquete WOL real en tests o pruebas (usa `APP_DRY_RUN=1`).
- Rama `fix/t800-estabilizacion`. Prohibido push directo a `main`. Un commit pequeño por tarea (formato convencional, en español). Al final, PR.
- Arreglos de UI primero con CSS/clases; lógica solo si es imprescindible.
- REANUDABLE: crea y mantén `ESTADO_T800.md` en la raíz con: fase actual, tareas hechas/pendientes, decisiones y último comando probado. Actualízalo tras cada tarea. Si el usuario te indica "ejecuta solo FASE N", haz solo esa fase, actualiza el estado, entrega su mini-informe y detente.
- Antes de editar nada lee: `backend/main.py`, `frontend/src/App.jsx`, `ForensicPanel.jsx`, `TelemetryPanel.jsx`, `VoiceCommandButton.jsx`, `vite.config.js`, todos los `.bat`, README.md y Handoff.md.

# CONTEXTO VERIFICADO (confírmalo leyendo el código; los números de línea son aproximados)
Stack: FastAPI (:8000, auth por cabecera `X-App-Pin`), React 19 + Vite 8 + Tailwind 4 (:5173, proxy `/api` y `/ws` con `ws:true`), `cloudflared.exe` en la raíz, PC Windows 11 por cable con IP fija.
1. Terminator: `ShutdownRequest.minutes` tiene `ge=1` sin default (main.py ~363); el botón envía `scheduleShutdown(0)` (App.jsx ~809) → 422. Se usa `shutdown /s /t N` sin `/f`. La barra de progreso dividiría entre `pending.minutes*60` (App.jsx ~622). El SVG del botón usa `class=` en vez de `className=` (App.jsx ~819).
2. Cancelar: `POST /api/cancel` ejecuta `shutdown /a` (1116 → 409 manejado). Sin bug evidente: reproducir. Un apagado con `/t 0` no es cancelable.
3. Túnel: `tunnel_output.txt` prueba que `run_tunnel.bat` e `iniciar_todo.bat` añaden `run` a un quick tunnel (error "requires the ID or name of the tunnel"). `run_tunnel.bat` además tiene `usebacktokens` (typo), `&` final inútil en cmd, `%TUNNEL_PID%` sin definir y extrae la URL con `find/findstr`.
4. `iniciar_todo.bat`: parámetro inválido `/WANAKA`, bloque multilínea roto, healthcheck a `/health` (la ruta real es `/api/health`; el log del backend aún muestra `GET /health 404`). Lanzadores duplicados y contradictorios (`click_apagadoeinico.bat` usa `backend.main:app`; `run_backend.bat` usa `main:app`). `backend/fix.py` está vacío.
5. Panel forense (ForensicPanel.jsx): (a) todas las barras salen llenas porque el div exterior lleva `bg-emerald-500` sin ancho y la barra proporcional va dentro; (b) el `<span>` de porcentaje es `absolute` sin padre `relative`, se sale a la derecha de la pantalla; (c) la tabla tiene 5 columnas y en móvil "Memoria" y "Status" quedan fuera de vista; (d) usa la clase inexistente `transition-width` (debe ser `transition-[width]`).
6. `forensic_processes()` (main.py ~490-519) ordena por `cpu_percent + memory_mb` (suma % con MB, así que ordena de facto por memoria) y psutil devuelve 0.0 en la primera lectura de cada proceso.
7. Telemetría en el móvil se queda en "RECONNECTING". Hipótesis a verificar: uvicorn con `--reload` reinicia el backend cada vez que un agente edita `.py` y corta el WebSocket; además un fallo dentro de `collect_telemetry` cerraría el socket sin diagnóstico.
8. Botón MIC flotante tapa el contenido inferior en móvil. En `http://` (LAN) el navegador puede bloquear el micrófono (requiere contexto seguro).
9. Seguridad: el PIN por defecto documentado sigue en README.md, Handoff.md y run_backend.bat (repo público) y el backend lo acepta con un aviso. No hay límite de intentos. El PIN viaja en la query string del WebSocket. `cloudflared.exe` (55 MB) está versionado. No existen tests.
10. El botón "Encender PC" de la web envía el paquete desde el propio PC (que es el que debe despertar), así que solo sirve cuando ya está encendido.

# FASE 0: AUDITORÍA Y LÍNEA BASE
Crea la rama y `ESTADO_T800.md`. Marca qué hallazgos 1-10 siguen vigentes. Instala dependencias, añade `backend/requirements-dev.txt` (pytest, httpx) y `backend/tests/` con fixture de `TestClient` y `APP_DRY_RUN=1`. Reproduce los fallos 1, 5 y 7 y guarda la evidencia en el estado.

# FASE 1: BACKEND DE APAGADO
T1.1 `minutes: int = Field(default=0, ge=0, le=MAX_MINUTES)`; `schedule_shutdown(payload: ShutdownRequest | None = None)` con `minutes = payload.minutes if payload else 0`. Si es 0: `shutdown /s /f /t 0`, `_set_pending(None)`, respuesta con `ends_at` = ahora. Si es mayor que 0: `shutdown /a` previo ignorando 409 (evita error 1190) y luego `shutdown /s /t <min*60>` (mantén el aviso nativo).
T1.2 `/api/cancel`: mantener; registrar en log returncode, stdout y stderr de cada `shutdown`; 1116 → respuesta "no había apagado pendiente" y estado local limpio. Documenta la limitación de `/t 0` y de sesión/permisos si se reproduce.
Tests: `{"minutes":0}`, cuerpo vacío y `{}` → 200 con la llamada exacta; `minutes=5` → `/a` luego `/s /t 300`; `-1` y valores sobre el máximo → 422; cancelar con 0, con 1116 y con otro código.

# FASE 2: BACKEND FORENSE Y TELEMETRÍA
T2.1 `forensic_processes()`: primar con `proc.cpu_percent(None)` en una primera pasada, esperar ~0.3 s y leer en la segunda; ordenar por `(cpu_percent, memory_mb)` descendente; limitar a 10; `cpu_percent` nunca mayor que 100 × nº de núcleos en el dato y el frontend lo normaliza.
T2.2 Telemetría robusta: envuelve cada muestra en `try/except`; ante error registra con `logger.exception`, envía un frame `{"error": "..."}` y reintenta en el siguiente ciclo en vez de cerrar el socket. Cierra solo ante desconexión del cliente.
T2.3 Reinicios: en `run_backend.bat` usa `--reload` solo en modo dev con `--reload-dir backend --reload-include "*.py"`; en modo prod NO uses `--reload`.
Tests: orden por CPU y luego memoria; `collect_telemetry` que lanza excepción no mata el WebSocket; segunda lectura de CPU con valores primados.

# FASE 3: FRONTEND
T3.1 `scheduleShutdown`: si `data.minutes === 0` → `setPending(null)`, toast "Terminator activado" y return. Protege la barra de progreso contra división por cero. `class=` → `className=` en el SVG.
T3.2 `ForensicPanel.jsx`: envuelve la tabla en `div.overflow-x-auto` con `table-fixed w-full`; en pantallas pequeñas oculta "Status" (`hidden sm:table-cell`) y deja visibles PID, Nombre, CPU % y Memoria; sustituye la celda de CPU por exactamente esto:
    <td>
      <div className="relative h-3 w-full overflow-hidden rounded-full bg-panel/50">
        <div style={{ width: `${Math.min(100, proc.cpu_percent)}%` }} className="h-full rounded-full bg-emerald-500 transition-[width] duration-500" />
        <span className="absolute inset-y-0 right-1 flex items-center text-[9px] text-emerald-100">{proc.cpu_percent.toFixed(1)}%</span>
      </div>
    </td>
T3.3 Layout móvil: añade `pb-28` (o equivalente seguro) al contenedor principal para que el botón MIC flotante no tape botones; verifica en 360 px y 412 px de ancho.
T3.4 MIC: si `!window.isSecureContext` deshabilita el botón con mensaje "Requiere HTTPS: abre la URL del túnel"; captura y muestra errores de permisos sin romper la UI.
T3.5 Telemetría: mientras reconecta, muestra el motivo si el backend envió `{"error"}` y el número de reintento; los estados "cancelado" y "no había apagado pendiente" se distinguen en la UI. El panel de Wake-on-LAN muestra una nota: "El PC ya está encendido. Para encender desde fuera usa el relé (docs/WAKE_REMOTO.md)"; el botón se mantiene funcional.
Calidad: `npm run lint` y `npm run build` sin errores ni warnings nuevos.

# FASE 4: TÚNEL Y LANZADORES
T4.1 Reescribe `run_tunnel.bat` + crea `tunnel_url.ps1`: `cloudflared.exe tunnel --no-autoupdate --url http://127.0.0.1:<puerto> --logfile .cloudflared\cloudflared.log` (SIN la palabra `run`). El script espera hasta 40 s, extrae con `Select-String` la regex `https://[a-z0-9-]+\.trycloudflare\.com`, la imprime y la copia al portapapeles. Cero `find/findstr/tasklist`. Crea `.cloudflared/` si no existe.
T4.2 Modo producción (un solo origen): FastAPI sirve `frontend/dist` con `StaticFiles` y fallback de SPA sin interferir con `/api` ni `/ws`; añade `build_frontend.bat`. En modo dev, Vite con `server.allowedHosts: ['.trycloudflare.com']`. Puerto del túnel: 8000 en prod, 5173 en dev.
T4.3 Un único lanzador `iniciar_todo.bat [dev|prod]` con `start "BACKEND" cmd /k "call backend\run_backend.bat"` y equivalentes para frontend (solo dev) y túnel. Sin `/WANAKA`. Healthcheck a `/api/health` con reintentos. Elimina `click_apagadoeinico.bat` y `backend/fix.py` (o conviértelos en wrappers). Un único módulo: `main:app` desde `backend/`.
T4.4 Si falta `cloudflared.exe`, el lanzador lo descarga del release oficial de Cloudflare y avisa. `docs/TUNEL_ESTABLE.md`: guía de túnel con nombre + dominio + Cloudflare Access (solo documentación; requiere cuenta y dominio del usuario).

# FASE 5: SEGURIDAD
T5.1 Elimina el PIN por defecto documentado de README.md, Handoff.md y run_backend.bat. El backend NO arranca si `APP_PIN` falta o coincide con el valor por defecto antiguo. Crea `.env.example` sin secretos; `.env` en `.gitignore`.
T5.2 Límite de intentos: 5 PIN fallidos por IP → 429 con `Retry-After` (REST y WebSocket). Respeta `CF-Connecting-IP` solo cuando la petición llega por el túnel.
T5.3 Ticket de WebSocket: `POST /api/ws-ticket` (autenticado) devuelve un ticket de un solo uso con caducidad de 30 s; el WebSocket usa `?ticket=`. El PIN deja de viajar en la URL (compatibilidad temporal con `?pin=` solo si `APP_ALLOW_WS_PIN=1`).
T5.4 `allow_origins` configurable por entorno, nunca `*` en prod. `.gitignore` + `git rm --cached` para `cloudflared.exe`. No reescribas el historial de git sin avisar en el informe.
Tests: PIN erróneo 401; sexto fallo 429; arranque sin `APP_PIN` falla; ticket usado dos veces falla; ticket caducado falla.

# FASE 6: RELÉ DE ENCENDIDO (solo software; no requiere hardware para implementarse)
Objetivo: un servicio mínimo que corre en un dispositivo SIEMPRE ENCENDIDO de la red (Raspberry Pi, Android con Termux, otro PC) y envía el paquete mágico al PC.
- Crea `wake_relay/`: `relay.py` (FastAPI mínimo: `POST /wake` con PIN propio `RELAY_PIN`, `GET /status` que hace ping/puerto al PC, MAC y broadcast por entorno, límite de intentos reutilizando la lógica de la Fase 5), `index.html` (página móvil de un solo botón con el estilo T-800), `requirements.txt`, `run_relay.sh` y `README.md`.
- Tests con `socket` mockeado: construcción exacta del paquete (6×0xFF + 16×MAC), PIN requerido, 429 tras 5 fallos.
- `docs/WAKE_REMOTO.md`: instalación paso a paso en Raspberry y Termux, cómo exponerlo (Tailscale o cloudflared en el propio relé), y requisitos del PC (WOL activado en BIOS y en la tarjeta de red, conexión por cable).
- No intentes configurar el router ni hardware: solo documenta.

# FASE 7: VERIFICACIÓN E2E, DOCS Y PR
- Con `APP_DRY_RUN=1`: `iniciar_todo.bat prod` levanta todo; comprueba `/api/health` local y por la URL trycloudflare, carga de la UI, telemetría por WebSocket (wss), forense con barras proporcionales, y los tres botones (temporizador, Terminator, cancelar).
- Lista de comprobación manual para el usuario con el PC real, incluyendo probar `shutdown /a` en la misma consola de uvicorn y probar desde datos móviles con el Wi-Fi apagado.
- README.md y Handoff.md actualizados y honestos (sin "Production Ready" mientras haya pasos pendientes): modos dev/prod, variables de entorno, limitaciones. Limitación a documentar: con el PC apagado el túnel está caído; el encendido remoto depende del relé de la Fase 6.
- `pytest` y `npm run lint` en verde. Abre el PR contra `main`.

# CRITERIOS DE ACEPTACIÓN
1. `{"minutes":0}` y cuerpo vacío → 200 y `shutdown /s /f /t 0` (verificado por test con mock).
2. Temporizador sin NaN en la UI; cancelación con mensajes distintos para "cancelado" y "no había nada".
3. Panel forense: barras proporcionales, porcentajes dentro de su barra, sin columnas fuera de pantalla a 360 px, orden por CPU.
4. Telemetría sin reconexiones infinitas en uso normal; un error de muestra no cierra el socket.
5. MIC no tapa contenido y se deshabilita con mensaje en `http://`.
6. `iniciar_todo.bat` sin errores de sintaxis; `run_tunnel.bat` imprime una URL trycloudflare válida; la app carga y controla el PC desde datos móviles.
7. PIN por defecto fuera del repo, límite de intentos activo, PIN fuera de la URL del WebSocket, `cloudflared.exe` fuera de git.
8. `wake_relay/` con tests verdes y documentación completa.
9. `pytest`, `npm run lint` y `npm run build` en verde; PR abierto.

# PROHIBIDO
Ejecutar un apagado real o enviar WOL real durante pruebas; `shell=True`; secretos o URLs en el repo; push a `main`; borrar historial sin avisar; romper WOL, telemetría, voz o panel forense; declarar algo "hecho" sin test o evidencia.

# SI TE BLOQUEAS
No improvises ni pidas permiso: detén la fase, deja el árbol limpio, actualiza `ESTADO_T800.md` y entrega un informe `BLOQUEO` con fase, comando exacto, salida completa del error, hipótesis y lo que necesitas del usuario o de Claude.

# INFORME FINAL (7 puntos)
1. Causa raíz de cada problema. 2. Archivos creados, modificados y eliminados. 3. Tests añadidos y resultado. 4. Cómo probar a mano, paso a paso. 5. Riesgos y limitaciones (PC apagado = túnel caído; el relé es necesario para encender desde fuera). 6. Enlace del PR. 7. Siguientes pasos recomendados.