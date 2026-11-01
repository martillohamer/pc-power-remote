# Handoff: pc-power-remote (Sistema T-800)

**Estado: EN ESTABILIZACIÓN. No está listo para producción.**
**Última actualización: 2026-11-01** · Versión de la app: 0.6.0 · Rama de trabajo: `fix/t800-estabilizacion`

Este documento sustituye al Handoff anterior, que declaraba "PRODUCTION READY / COMPLETED" y contenía datos incorrectos (ver sección 9). Está escrito para que una persona o un agente de IA pueda retomar el proyecto exactamente donde se dejó.

## 0. Cómo leer este documento

Cada dato lleva una marca de fiabilidad:

- **[V]** Verificado leyendo el código del repo (estado de `main`, commit `5e7cdd9`).
- **[U]** Confirmado por el usuario en su equipo real (capturas o salida de consola).
- **[?]** No verificado: hay que comprobarlo antes de darlo por bueno.

Los cambios sin commitear de la rama de trabajo **no están revisados**: trátalos como [?].

## 1. Qué es el proyecto

Control remoto de un PC con Windows 11 desde el móvil: apagado inmediato y temporizado, cancelar apagado, suspensión, bloqueo de sesión, Wake-on-LAN, telemetría en vivo, panel forense de procesos, comandos de voz y acceso por internet con un túnel Cloudflare. Estética cyberpunk "T-800".

- Repo público: `github.com/martillohamer/pc-power-remote`.
- El PC está conectado por cable (Ethernet) con IP fija en la LAN [U].
- Lo usa una sola persona. Se maneja desde el navegador del móvil.

## 2. Arquitectura real

| Capa | Tecnología y versión | Puerto | Fuente |
|---|---|---|---|
| Backend | FastAPI (`fastapi>=0.115,<1.0`), uvicorn, pydantic 2.9+, psutil 5.9+, wakeonlan 3.1+ | 8000 | [V] `backend/requirements.txt` |
| Frontend | React 19.3, Vite 8.3, Tailwind 4.3 (`@tailwindcss/vite`), `@vitejs/plugin-react` 6.1 | 5173 | [V] `frontend/package.json` |
| Proxy dev | Vite reenvía `/api` y `/ws` (con `ws: true`) a `127.0.0.1:8000` (se puede cambiar con la variable `API_TARGET`) | | [V] `frontend/vite.config.js` |
| Túnel | `cloudflared.exe` local, quick tunnel (URL `trycloudflare.com` nueva en cada arranque) | | [V]/[U] |
| Tests | pytest + httpx en `backend/tests/` (entorno virtual en `backend/.venv`) | | [U] |

Cosas que NO existen todavía:

- FastAPI **no sirve** el frontend compilado (`npm run build` hoy no sirve para nada en producción). Está planificado como "modo producción" (Fase 4 de `PROMPT_T800.md`).
- No hay límite de intentos de PIN, ni tickets para el WebSocket, ni CORS restringido.

## 3. Estructura del repo

```
pc-power-remote/
├── backend/
│   ├── main.py              # API completa (FastAPI v0.6.0)
│   ├── requirements.txt
│   ├── requirements-dev.txt # pytest, httpx (añadido en la Fase 0)
│   ├── run_backend.bat      # arranque del backend (modo dev|prod, en revisión)
│   ├── tests/               # conftest.py, test_shutdown.py, ... (19 tests en verde)
│   └── .env                 # NO versionado (gitignored): APP_PIN, MAC autodetectada
├── frontend/
│   ├── vite.config.js
│   ├── run_frontend.bat
│   └── src/
│       ├── App.jsx              # componente principal; incluye los modales de PIN y MAC
│       ├── TelemetryPanel.jsx   # WebSocket de telemetría (CPU, RAM, disco, uptime)
│       ├── ForensicPanel.jsx    # procesos y log de eventos críticos
│       ├── VoiceCommandButton.jsx  # voz es-ES (Web Speech API)
│       ├── index.css, main.jsx
├── iniciar_todo.bat         # lanzador general (en revisión)
├── run_tunnel.bat           # túnel Cloudflare (en revisión)
├── click_apagadoeinico.bat  # lanzador duplicado (candidato a eliminar)
├── cloudflared.exe          # ~54 MB, versionado: debe salir de git
├── tunnel_output.txt        # evidencia del fallo original del túnel
├── PROMPT_T800.md           # plan maestro por fases (aún sin commitear)
├── ESTADO_T800.md           # estado de las fases (lo mantiene el agente)
├── README.md, Handoff.md
```

Aviso: `PinModal.jsx` y `MacModal.jsx`, que nombraba el Handoff anterior, **no existen como archivos**. Esos modales están dentro de `App.jsx` [V].

## 4. API real [V]

Todas exigen la cabecera `X-App-Pin` salvo `/` y `/api/health`. El WebSocket recibe el PIN por query string.

| Ruta | Método | Función |
|---|---|---|
| `/` y `/api/health` | GET | Healthcheck público (devuelven `{"status":"online","system":"Windows"}`) |
| `/api/state` | GET | Estado del apagado programado |
| `/api/shutdown` | POST | Apagar. `minutes=0` o cuerpo vacío: inmediato (`shutdown /s /f /t 0`). `minutes>0`: temporizado (`shutdown /a` previo + `shutdown /s /t N`). Máximo 24 h |
| `/api/cancel` | POST | Cancelar (`shutdown /a`). El código 1116 ("no había apagado pendiente") se trata como respuesta controlada |
| `/api/wake` | POST | Envía el paquete mágico WOL **desde el propio PC** (ver sección 8) |
| `/api/config` | GET | MAC, broadcast, puerto y origen de la configuración WOL |
| `/api/system/suspend` | POST | Suspende el equipo (con espera opcional, máximo 60 min; sin valor, ahora) |
| `/api/windows/lock` | GET | Bloquea la sesión (`rundll32 user32.dll,LockWorkStation`) |
| `/api/windows/unlock` | GET | **PELIGROSO**, ver sección 7 |
| `/api/forensic/processes` | GET | Procesos de mayor consumo (Top 10) |
| `/api/forensic/logs` | GET | Log circular de eventos críticos |
| `/ws/telemetry` | WebSocket | Telemetría cada 1,5 s (CPU, RAM, disco, uptime) |

El guardián de suspensión automática ("Smart Sleep") usa por defecto: CPU por debajo del 5 %, 30 min de inactividad, 3 lecturas bajas consecutivas, muestreo cada 10 s [V].

## 5. Configuración

Variables de entorno que lee el backend [V]:

| Variable | Para qué sirve |
|---|---|
| `APP_PIN` | PIN exigido en `X-App-Pin`. Si no se define, usa el PIN por defecto histórico que está en `main.py` (`DEFAULT_PIN`) y solo avisa |
| `APP_MAC_ADDRESS` | MAC de la tarjeta de red. Si falta, se autodetecta con `ipconfig /all` (inglés y español) y se guarda en `backend/.env` |
| `APP_WOL_BROADCAST` | Broadcast del paquete mágico (por defecto `255.255.255.255`) |
| `APP_WOL_PORT` | Puerto UDP de WOL (por defecto 9) |
| `APP_DRY_RUN` | Con valor `1` simula apagados y no ejecuta nada. **Obligatorio en tests y en pruebas de agentes** |

El PIN se cambia con una línea `APP_PIN=...` en `backend/.env` (el archivo está en `.gitignore`) y reiniciando el backend. **No existe** ninguna página `/pin`, aunque el Handoff anterior la mencionaba.

## 6. Estado del trabajo

### 6.1 Git [U]

- Rama `fix/t800-estabilizacion`, creada desde `main` (`5e7cdd9`, igual que `origin/main`). `main` está intacto.
- Commits de la rama: `c19b9bd` (Fase 0), `990e5d2` (Fase 1), `8a65a33` (T2.1 forense), `c7230dd` (T2.2 telemetría).
- Tests: **19 passed** (`cd backend` y `.\.venv\Scripts\python.exe -m pytest -q`). El único aviso es una deprecación de httpx, ignorable.
- Copia de seguridad: `stash@{0}` llamado "backup-wip-fase2" con todo el trabajo sin commitear. **No borrar.**
- Sin commitear, **no revisado** [?]: `ESTADO_T800.md`, `backend/run_backend.bat`, `click_apagadoeinico.bat`, `frontend/run_frontend.bat`, `frontend/src/App.jsx`, `frontend/src/VoiceCommandButton.jsx`, `iniciar_todo.bat`, `run_tunnel.bat`, `PROMPT_T800.md` y `backend/tests/test_launcher.py`. Los hizo un agente anterior cuya cuota se agotó a mitad de la Fase 2.
- `ForensicPanel.jsx` no aparece modificado: sus arreglos están pendientes.

### 6.2 Hecho

- **Fase 0**: auditoría, dependencias de test, `conftest.py` con `APP_DRY_RUN=1` y `subprocess` mockeado.
- **Fase 1**: `ShutdownRequest.minutes` con `default=0, ge=0`; Terminator (0) acepta cuerpo vacío y ejecuta `shutdown /s /f /t 0`; los temporizadores cancelan antes uno previo; `/api/cancel` maneja el código 1116; `_run_shutdown` registra código de retorno y salidas. 10 tests.
- **T2.1**: lectura de CPU de procesos con muestra previa y orden por CPU y luego memoria.
- **T2.2**: la telemetría tolera errores de muestra sin cerrar el WebSocket y el frontend ignora los mensajes con clave `error`.
- **Verificado en el PC real [U]**: el apagado desde el móvil funciona.

### 6.3 Pendiente, en este orden

1. **T2.3**: `backend/run_backend.bat` ya tiene modo `dev|prod` (prod sin `--reload`). Corregir `--reload-dir backend` por `--reload-dir .` (el script ya está dentro de `backend`), verificar los dos modos y commitear.
2. Crear `.gitattributes` con `*.bat text eol=crlf` y ejecutar `git add --renormalize .`
3. **Triage** de los archivos sin commitear: `git diff` de cada uno, clasificar (T2.3 / Fase 3 / Fase 4 / incorrecto) y anotarlo en `ESTADO_T800.md`.
4. **Fase 3** (frontend): T3.1 (`scheduleShutdown` con `minutes === 0`, `class=` por `className=`), T3.2 (`ForensicPanel`), T3.3 (espacio inferior para el botón MIC), T3.4 (MIC en contexto no seguro) y T3.5.
5. **Fase 5** (seguridad), después **Fase 4** (túnel y lanzadores), **Fase 6** (relé WOL) y **Fase 7** (E2E y PR). Detalle completo en `PROMPT_T800.md`.

## 7. Problemas conocidos y riesgos

1. **`/api/windows/unlock` cierra la sesión.** Ejecuta `shutdown /l`, que es "cerrar sesión" (log off), no desbloquear. Windows no permite desbloquear en remoto sin la contraseña. Quien tenga el PIN puede cerrar la sesión y **hacer perder el trabajo sin guardar**. Además es un `GET` que cambia el estado del sistema. El frontend no lo usa [V]. Acción propuesta (Fase 5): eliminarlo, y convertir `/api/windows/lock` a `POST`.
2. **PIN por defecto en el repo público.** Aparece en `backend/main.py` (docstring y `DEFAULT_PIN`), `backend/run_backend.bat` y varias veces en `README.md` (ejemplos de `curl` y de WebSocket). El backend arranca igualmente con él. Con el túnel abierto, cualquiera puede probar el PIN.
3. **Sin límite de intentos de PIN**, y el PIN viaja en la URL del WebSocket (`?pin=`), lo que lo deja en historiales y registros.
4. **El túnel apuntaba al puerto 8000** (solo API), pero el móvil necesita la app en 5173 (o servida por FastAPI en modo producción). Estado actual del script: [?].
5. **Causa del fallo original del túnel [V]**: `tunnel_output.txt` contiene el error `"cloudflared tunnel run" requires the ID or name of the tunnel`. Sobraba la palabra `run` en un quick tunnel. Además `run_tunnel.bat` original tenía `usebacktokens` (typo), un `&` final inútil en `cmd`, `%TUNNEL_PID%` sin definir y extraía la URL con `find`/`findstr` (el error "filtro de búsqueda"). `iniciar_todo.bat` original tenía el parámetro inválido `/WANAKA`, un bloque multilínea roto y comprobaba `/health` en vez de `/api/health`.
6. **Panel forense [V]**: barras siempre llenas, porcentaje con `absolute` sin padre `relative`, tabla de 5 columnas que en móvil deja fuera Memoria y Status, y clase inexistente `transition-width`.
7. **Higiene del repo**: `cloudflared.exe` (~54 MB) está versionado. `.gitignore` no incluye `.pytest_cache/` ni `.cloudflared/`.
8. **Suspensión**: se usa `rundll32 powrprof.dll,SetSuspendState 0,1,0`. Si la hibernación está activa en Windows, el equipo hiberna en vez de suspender [?].
9. Los `.bat` guardados con LF (Git avisó) y con caracteres no ASCII bajo `chcp 65001` pueden fallar de formas raras.

## 8. Limitaciones físicas (no son bugs)

- **Con el PC apagado no hay backend ni túnel.** El botón "Encender PC" de la web envía el paquete mágico desde el propio PC, así que solo tiene sentido si el equipo ya está encendido.
- En la misma red local, la app **WolOn** del móvil sí enciende el PC (modo LAN, puerto 9) [U].
- Para encender desde fuera de casa hace falta un dispositivo siempre encendido en la red (Raspberry Pi, Android viejo con Termux, router con WOL), o un enchufe inteligente con "Restore on AC Power Loss = Power On" en la BIOS. Está previsto como Fase 6 (`wake_relay/`).
- Requisitos del PC para WOL: conexión por cable, WOL activado en la BIOS y en la tarjeta de red.
- Un quick tunnel cambia de URL en cada arranque. Una URL fija exige túnel con nombre y dominio propio (guía prevista en `docs/TUNEL_ESTABLE.md`).

## 9. Correcciones respecto al Handoff anterior

| El Handoff anterior decía | Realidad |
|---|---|
| "PRODUCTION READY / COMPLETED" | Falsa. Hay seguridad, túnel, lanzadores y UI pendientes |
| Fase 3 (túnel) "Complete" | El túnel fallaba por la palabra `run`; no está verificado desde datos móviles |
| Existen `PinModal.jsx` y `MacModal.jsx` | No existen; están dentro de `App.jsx` |
| React 18, Vite 5+, Tailwind 4.0 | React 19.3, Vite 8.3, Tailwind 4.3 |
| `requirements.txt` incluye `python-multipart` | No lo incluye; versiones reales en la sección 2 |
| Configurar el PIN en `http://127.0.0.1:8000/pin` | No existe esa ruta; se usa `APP_PIN` en `backend/.env` |
| `.env` en la raíz del repo | Es `backend/.env` (y no se versiona) |
| "Logging con archivo rotativo" | No hay manejador de archivo: el log sale por consola |
| Túnel: "Authentication: no additional auth (LAN-local only)" | El túnel expone la app a internet; la única barrera es el PIN |
| "Check COM port/MAC address detection" | No hay puertos COM; la MAC se autodetecta con `ipconfig /all` |
| "Rebuild frontend: npm run build" como paso de actualización | FastAPI no sirve el build; solo se usa Vite en desarrollo |
| Lista de endpoints incompleta | Faltaban `/api/state`, `/api/config`, `/api/wake`, `/api/system/suspend`, `/api/windows/lock` y `/unlock` |

## 10. Reglas para agentes de IA

- Autonomía total, sin pedir confirmaciones. Todo en español: código, comentarios, commits e informes.
- TDD: test rojo, implementación, test verde. Los tests mockean `subprocess` y `socket`. **Prohibido** ejecutar un apagado real o enviar WOL real (usar `APP_DRY_RUN=1`).
- Rama `fix/t800-estabilizacion`. **Prohibido** el push directo a `main`. Un commit por tarea, formato convencional y en español. Al final, PR.
- Arreglos de UI primero con CSS. No tocar WOL, telemetría ni voz salvo que lo pida una tarea.
- **Prohibido**: `git reset --hard`, `git checkout -- .`, `git restore` sobre cambios sin guardar, `git stash drop` y reescribir historial.
- Trabajar por fases pequeñas: hacer solo lo que se pide en cada mensaje, actualizar `ESTADO_T800.md`, entregar mini-informe y detenerse.
- Los `.bat` se guardan en UTF-8 sin BOM, con CRLF y sin caracteres no ASCII.
- Un solo agente sobre el repo a la vez.
- No escribir en documentos el PIN por defecto, la MAC ni la IP del equipo: el repo es público.

## 11. Cómo ejecutar y probar

Desde la raíz del repo, en PowerShell:

```
# Tests (backend)
cd backend
.\.venv\Scripts\python.exe -m pytest -q

# Backend en desarrollo (con recarga) o producción (sin recarga)
.\run_backend.bat dev
.\run_backend.bat prod

# Frontend
cd ..\frontend
npm install
npm run dev
npm run lint
npm run build
```

No ejecutar `iniciar_todo.bat` hasta revisar los scripts [?].

## 12. Verificación manual pendiente (la hace el usuario con el PC real)

1. Reiniciar el backend y abrir la web en el móvil: la telemetría debe pasar a **LIVE TELEMETRY** y no quedarse en RECONNECTING.
2. Programar un temporizador de 3 minutos, comprobar el aviso de Windows y cancelarlo desde el móvil. Probar Terminator el último, con el trabajo guardado.
3. Con el Wi-Fi del móvil apagado, abrir la URL `trycloudflare.com` y comprobar que la app carga y controla el PC.
4. Definir un `APP_PIN` propio en `backend/.env` antes de exponer el túnel.