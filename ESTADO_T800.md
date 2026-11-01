# ESTADO_T800.md — Registro de Auditoría y Estado del Sistema

## 1. Fase Actual
- **Fase**: FASE 2: BACKEND FORENSE Y TELEMETRÍA (Completada). Sistema detenido tras completar Fase 2 según la orden del usuario.
- **Rama**: `fix/t800-estabilizacion`
- **Último comando probado**: `backend\.venv\Scripts\pytest backend\tests -v` (19 tests pasados, 0 fallos).
- **Últimos commits (esta sesión)**:
  - `7ccb3f6` feat(launcher): corrige `--reload-dir` en `run_backend.bat` y añade test (T2.3). El script ya está dentro de `backend/` (`cd /d "%~dp0"`), por lo que `--reload-dir backend` apuntaba a un directorio inexistente; se cambia por `--reload-dir .` (UTF-8 sin BOM, CRLF). Test actualizado para verificar `--reload-dir .` y rechazar la ruta obsoleta.
  - `16c4a9b` chore(repo): añade `.gitattributes` con `*.bat text eol=crlf` y aplica `git add --renormalize .` para normalizar finales de línea CRLF en los scripts de Windows.

---

## 2. Auditoría de Hallazgos 1–10 (Línea Base)

| # | Hallazgo | Estado | Evidencia / Diagnóstico |
|---|----------|--------|-------------------------|
| 1 | Terminator: `ShutdownRequest.minutes` validación/default, `shutdown /s /f /t 0`, división por cero en progreso | **RESUELTO EN BACKEND (Fase 1)** / UI pendiente (Fase 3) | Backend soporta `minutes=0` por defecto, cuerpo vacío y `{}`, ejecutando `shutdown /s /f /t 0`. En frontend (Fase 3) queda pendiente proteger división por cero en barra de progreso. |
| 2 | Cancelar: `/api/cancel` ejecuta `shutdown /a` (1116 manejado), limitación `/t 0` | **RESUELTO (Fase 1)** | Registra returncode, stdout y stderr; código 1116 responde con mensaje "No había apagado pendiente para cancelar." y limpia estado local. Documentada limitación de que `/t 0` no es cancelable por Windows. |
| 3 | Túnel: `run` en quick tunnel, sintaxis batch errónea (`usebacktokens`, etc.) | **VIGENTE (Pendiente Fase 4)** | `run_tunnel.bat` e `iniciar_todo.bat` presentan comandos con sintaxis rota o parámetros obsoletos. Requiere reescritura limpia con `tunnel_url.ps1`. |
| 4 | Lanzadores: `/WANAKA`, healthcheck a `/health` en vez de `/api/health`, scripts redundantes | **VIGENTE (Pendiente Fase 4)** | `iniciar_todo.bat` tiene `/WANAKA` y apuntaba a `/health` (404). `click_apagadoeinico.bat` y `backend/fix.py` (vacío) requieren saneamiento. |
| 5 | Panel Forense: barras 100%, span absolute desubicado, tabla desborda en móvil, clase `transition-width` | **VIGENTE (Pendiente Fase 3)** | Div exterior tiene `bg-emerald-500` sin ancho (se muestra al 100%); span con `absolute` sin padre `relative` vuela a la derecha; tabla con `min-w-[600px]` sin scroll horizontal; clase inválida `transition-width`. |
| 6 | Forense CPU: ordenamiento `cpu_percent + memory_mb`, primera lectura psutil devuelve 0.0 | **RESUELTO (Fase 2)** | Primado con `proc.cpu_percent(None)`, pausa de 0.3s y segunda lectura real; tope en `100 * cores`; orden descendente por `(cpu_percent, memory_mb)`. |
| 7 | Telemetría: "RECONNECTING" en móvil, fallo en `collect_telemetry` mata WS | **RESUELTO (Fase 2)** | Telemetría robusta: `try/except` por muestra, logging de excepción y envío de `{"error": ...}` sin cerrar socket; cliente ignora frames de error en `TelemetryPanel.jsx`. |
| 8 | Botón MIC: solapamiento en móvil, contexto inseguro en HTTP | **VIGENTE (Pendiente Fase 3)** | Sin padding inferior suficiente (`pb-28`) en móvil; falta validación `window.isSecureContext` para advertir sobre requerimiento HTTPS. |
| 9 | Seguridad: PIN por defecto en repo, sin rate-limiting, PIN en query string WS, binario 55MB en git | **VIGENTE (Pendiente Fase 5)** | `APP_PIN=134113` documentado públicamente; sin bloqueo ante fuerza bruta; PIN expuesto en URL del WebSocket; `cloudflared.exe` versionado en git. |
| 10 | Encender PC (WOL): botón envía paquete desde el propio PC encendido | **VIGENTE (Pendiente Fase 6)** | Solo funciona si el PC ya está despierto. Para arranque remoto se necesita relé auxiliar independiente. |

---

## 3. Evidencia de Reproducción de Fallos (1, 5, 7)

### Fallo 1: Terminator / Payload de Apagado (Antes de Fase 1)
```
POST /api/shutdown con body {} -> HTTP 422:
{'detail': [{'type': 'missing', 'loc': ['body', 'minutes'], 'msg': 'Field required', 'input': {}}]}

POST /api/shutdown con body vacio (None) -> HTTP 422:
{'detail': [{'type': 'missing', 'loc': ['body'], 'msg': 'Field required', 'input': None}]}
```
*Resolución en Fase 1*: `ShutdownRequest.minutes` ahora tiene `default=0` y `schedule_shutdown(payload: ShutdownRequest | None = None)` asigna `0` si el payload es omitido. Pasa a HTTP 200 con llamada forzada `["shutdown", "/s", "/f", "/t", "0"]`.

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
*Diagnóstico*: El bucle `while True` en `telemetry_socket` carece de bloque `try/except` envolviendo `collect_telemetry()`. Una excepción aborta la corrutina y cierra el canal.

---

## 4. Tareas y Estado de Ejecución

- [x] **Fase 0: Auditoría y Línea Base**
  - [x] Rama verificada: `fix/t800-estabilizacion`
  - [x] Instalación de dependencias de desarrollo (`pytest`, `httpx`)
  - [x] Creación de `backend/requirements-dev.txt`
  - [x] Creación de suite `backend/tests/` con fixtures seguras (`conftest.py`, `APP_DRY_RUN=1`)
  - [x] Reproducción documentada de fallos 1, 5 y 7
  - [x] Creación de `ESTADO_T800.md`

- [x] **Fase 1: Backend de Apagado**
  - [x] T1.1: `ShutdownRequest.minutes` con `default=0, ge=0, le=MAX_MINUTES`; `schedule_shutdown(payload: ShutdownRequest | None = None)` con `minutes = payload.minutes if payload else 0`. Si es 0: `shutdown /s /f /t 0`, `_set_pending(None)`, `ends_at` = ahora. Si es > 0: `shutdown /a` previo ignorando 409 (evita 1190) y luego `shutdown /s /t <min*60>`.
  - [x] T1.2: `/api/cancel`: registro en log de returncode, stdout y stderr; 1116 mapeado a respuesta clara ("No había apagado pendiente para cancelar.") con estado local limpio. Documentada limitación de `/t 0`.
  - [x] Tests Fase 1 (TDD verde): 10 tests unitarios en `backend/tests/test_shutdown.py` pasando al 100%.

- [x] **Fase 2: Backend Forense y Telemetría**
  - [x] T2.1: `forensic_processes()`: primado con `proc.cpu_percent(None)`, espera de 0.3s y segunda lectura real; tope en `100 * cores`; orden descendente por `(cpu_percent, memory_mb)`; límite de 10 procesos. (Tests: 5/5 pasando).
  - [x] T2.2: Telemetría robusta en WebSocket (`try/except` por muestra, logging con `logger.exception`, frame `{"error": ...}`, reintento continuo sin cerrar canal) y filtro en `TelemetryPanel.jsx` (ignora frames con clave "error"). (Tests: 3/3 pasando).
  - [x] T2.3: Control de reinicios en `run_backend.bat` (`--reload` solo en dev con `--reload-dir . --reload-include "*.py"`, sin reload en prod). El script hace `cd /d "%~dp0"` (queda dentro de `backend/`), por lo que `--reload-dir .` es el directorio correcto. Test en `backend/tests/test_launcher.py` que lo verifica y rechaza `--reload-dir backend`. Commit `7ccb3f6`.
- [x] Higiene de reposo: `.gitattributes` con `*.bat text eol=crlf` + `git add --renormalize .` (UTF-8 sin BOM, CRLF). Commit `16c4a9b`.
- [ ] **Fase 3: Frontend** (Pendiente)
- [ ] **Fase 4: Túnel y Lanzadores** (Pendiente)
- [ ] **Fase 5: Seguridad** (Pendiente)
- [ ] **Fase 6: Relé de Encendido (WOL)** (Pendiente)
- [ ] **Fase 7: Verificación E2E, Docs y PR** (Pendiente)

---

## 5. Decisiones Técnicas
- **Seguridad en Pruebas**: Todos los tests se ejecutan con `APP_DRY_RUN=1` y `monkeypatch` en `main.DRY_RUN`, asegurando que bajo ninguna circunstancia se invoque `shutdown.exe` real durante la suite de pruebas.
- **Robustez de Entrada**: `schedule_shutdown` tolera peticiones sin cuerpo, con cuerpo vacío `{}` o con `{"minutes": 0}`, estandarizando la activación de Terminator sin riesgo de HTTP 422.
- **Prevención de Error 1190 de Windows**: Al programar un apagado con temporizador (`minutes > 0`), se ejecuta un `shutdown /a` previo ignorando el código 1116 (409) para limpiar cualquier temporizador preexistente antes de armar el nuevo.
- **Trazabilidad de Subprocesos**: `_run_shutdown` ahora imprime en el logger el comando exacto, su returncode, stdout y stderr para facilitar el diagnóstico forense.
- **Medición Precisa de CPU**: psutil requiere una lectura previa (primado) con `proc.cpu_percent(None)` y un intervalo de espera (~0.3s) para calcular el porcentaje delta real entre ticks de reloj. Se ordena por tupla `(cpu_percent, memory_mb)` descendente.
- **Resiliencia en WebSocket de Telemetría**: El hilo de telemetría captura excepciones por muestra emitiendo un frame `{"error": ...}` y reintentando en el ciclo siguiente en lugar de abortar la conexión; el frontend descarta silenciosamente estos frames de error manteniendo el último estado visual sin entrar en bucle de reconexión.
- **Aislamiento de Recargas uvicorn**: En modo dev se delimitan las recargas exclusivamente al directorio `backend` y archivos `*.py` para evitar que escrituras en logs, `.env` o artefactos reinicien innecesariamente el proceso FastAPI. En modo prod se desactiva `--reload`.
