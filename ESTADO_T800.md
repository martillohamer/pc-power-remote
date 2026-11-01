# ESTADO_T800.md — Registro de Auditoría y Estado del Sistema

## 1. Fase Actual
- **Fase**: FASE 0: AUDITORÍA Y LÍNEA BASE (Completada) -> Transición a FASE 1: BACKEND DE APAGADO.
- **Rama**: `fix/t800-estabilizacion`
- **Último comando probado**: `.venv\Scripts\pytest backend\tests`

---

## 2. Auditoría de Hallazgos 1–10 (Línea Base)

| # | Hallazgo | Estado | Evidencia / Diagnóstico |
|---|----------|--------|-------------------------|
| 1 | Terminator: `ShutdownRequest.minutes` validación/default, `shutdown /s /f /t 0`, división por cero en progreso | **VIGENTE** | `ShutdownRequest.minutes` no tiene `default=0`. Peticiones `{}` o cuerpo vacío dan HTTP 422 (`Field required`). Falta `shutdown /a` previo en programado para evitar error 1190. `App.jsx:625` divide por `pending.minutes * 60` (genera `NaN`). |
| 2 | Cancelar: `/api/cancel` ejecuta `shutdown /a` (1116 manejado), limitación `/t 0` | **VIGENTE** | `shutdown /a` funciona, pero Windows no permite cancelar un apagado con `/t 0`. Falta registrar en log returncode/stdout/stderr y retornar mensaje específico cuando no había apagado pendiente (1116). |
| 3 | Túnel: `run` en quick tunnel, sintaxis batch errónea (`usebacktokens`, etc.) | **VIGENTE** | `run_tunnel.bat` e `iniciar_todo.bat` presentan comandos con sintaxis rota o parámetros obsoletos. Requiere reescritura limpia con `tunnel_url.ps1`. |
| 4 | Lanzadores: `/WANAKA`, healthcheck a `/health` en vez de `/api/health`, scripts redundantes | **VIGENTE** | `iniciar_todo.bat` tiene `/WANAKA` y apuntaba a `/health` (404). `click_apagadoeinico.bat` y `backend/fix.py` (vacío) requieren saneamiento. |
| 5 | Panel Forense: barras 100%, span absolute desubicado, tabla desborda en móvil, clase `transition-width` | **VIGENTE** | Div exterior tiene `bg-emerald-500` sin ancho (se muestra al 100%); span con `absolute` sin padre `relative` vuela a la derecha; tabla con `min-w-[600px]` sin scroll horizontal; clase inválida `transition-width`. |
| 6 | Forense CPU: ordenamiento `cpu_percent + memory_mb`, primera lectura psutil devuelve 0.0 | **VIGENTE** | `forensic_processes()` suma porcentaje y megabytes, distorsionando el orden; falta primar con lectura inicial y retardo de ~0.3s. |
| 7 | Telemetría: "RECONNECTING" en móvil, fallo en `collect_telemetry` mata WS | **VIGENTE** | Comprobado con TestClient: una excepción en `collect_telemetry` desconecta el socket (`WebSocketDisconnect`) en vez de capturar el error y seguir enviando muestras. |
| 8 | Botón MIC: solapamiento en móvil, contexto inseguro en HTTP | **VIGENTE** | Sin padding inferior suficiente (`pb-28`) en móvil; falta validación `window.isSecureContext` para advertir sobre requerimiento HTTPS. |
| 9 | Seguridad: PIN por defecto en repo, sin rate-limiting, PIN en query string WS, binario 55MB en git | **VIGENTE** | `APP_PIN=134113` documentado públicamente; sin bloqueo ante fuerza bruta; PIN expuesto en URL del WebSocket; `cloudflared.exe` versionado en git. |
| 10 | Encender PC (WOL): botón envía paquete desde el propio PC encendido | **VIGENTE** | Solo funciona si el PC ya está despierto. Para arranque remoto se necesita relé auxiliar independiente. |

---

## 3. Evidencia de Reproducción de Fallos (1, 5, 7)

### Fallo 1: Terminator / Payload de Apagado
```
POST /api/shutdown con body {} -> HTTP 422:
{'detail': [{'type': 'missing', 'loc': ['body', 'minutes'], 'msg': 'Field required', 'input': {}}]}

POST /api/shutdown con body vacio (None) -> HTTP 422:
{'detail': [{'type': 'missing', 'loc': ['body'], 'msg': 'Field required', 'input': None}]}
```
*Causa*: Falta `default=0` en `ShutdownRequest.minutes` y `schedule_shutdown(payload: ShutdownRequest | None = None)`.

### Fallo 5: Panel Forense (ForensicPanel.jsx)
- `className="bg-emerald-500 h-2 rounded-full transition-width duration-500"` contiene dentro la barra con ancho real, pero el contenedor ya tiene fondo verde al 100%.
- `<span className="text-[9px] text-emerald-300 absolute right-1">` está en un contenedor sin `relative`, alineándose respecto a la ventana/panel principal.
- La tabla de 5 columnas desborda en pantallas de 360px-412px al no tener contenedor con `overflow-x-auto` ni ocultar columnas secundarias.
- `transition-width` no es una clase válida de Tailwind v4 (debe ser `transition-[width]`).

### Fallo 7: Telemetría / Cierre Prematuro de WebSocket
```
TestClient conectado a /ws/telemetry?pin=134113 con mock de collect_telemetry lanzando RuntimeError:
15:04:56 [INFO] Telemetria: cliente conectado (Address(host='testclient', port=50000))
15:04:56 [INFO] Telemetria: conexion cerrada (psutil hardware sensor fault)
WebSocket crashed with exception: <class 'starlette.websockets.WebSocketDisconnect'>
```
*Causa*: El bucle `while True` en `telemetry_socket` carece de bloque `try/except` envolviendo `collect_telemetry()`. Una excepción aborta la corrutina y cierra el canal.

---

## 4. Tareas y Estado de Ejecución

- [x] **Fase 0: Auditoría y Línea Base**
  - [x] Rama verificada: `fix/t800-estabilizacion`
  - [x] Instalación de dependencias de desarrollo (`pytest`, `httpx`)
  - [x] Creación de `backend/requirements-dev.txt`
  - [x] Creación de suite `backend/tests/` con fixtures seguras (`conftest.py`, `APP_DRY_RUN=1`)
  - [x] Reproducción documentada de fallos 1, 5 y 7
  - [x] Creación de `ESTADO_T800.md`

- [ ] **Fase 1: Backend de Apagado**
  - [ ] T1.1: `ShutdownRequest.minutes` con `default=0, ge=0, le=MAX_MINUTES`; `schedule_shutdown(payload: ShutdownRequest | None = None)` con soporte para 0 (inmediato forzado `shutdown /s /f /t 0`) y >0 (con `shutdown /a` previo ignorando 409).
  - [ ] T1.2: `/api/cancel` con registro de returncode, stdout y stderr; manejo limpio de 1116 ("no había apagado pendiente"); documentación de `/t 0`.
  - [ ] Tests de Fase 1 (TDD rojo/verde): `minutes: 0`, cuerpo vacío, `{}` -> 200 y comando exacto; `minutes: 5` -> `/a` + `/s /t 300`; valores inválidos -> 422; cancel con 0, 1116 y error.

---

## 5. Decisiones Técnicas
- **Seguridad en Pruebas**: Todos los tests se ejecutan con `APP_DRY_RUN=1` y `monkeypatch` en `main.DRY_RUN`, asegurando que bajo ninguna circunstancia se invoque `shutdown.exe` real durante la suite de pruebas.
- **Compatibilidad de Endpoints**: `schedule_shutdown` aceptará tanto payloads vacíos como `{"minutes": 0}` para robustez frente a clientes REST y disparadores de voz.
