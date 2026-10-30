# pc-power-remote

Control remoto del estado/energía de un PC Windows desde la red local (móvil incluido).

```
pc-power-remote/
├── backend/
│   ├── main.py            # API FastAPI: PIN + apagado/cancelacion + Wake-on-LAN
│   ├── requirements.txt   # fastapi, uvicorn, pydantic, wakeonlan
│   ├── run_backend.bat    # venv + deps + uvicorn en 0.0.0.0:8000
│   ├── .env               # (autogenerado) APP_MAC_ADDRESS detectada
│   └── .venv/             # (generado por el .bat)
└── frontend/              # React + Vite + Tailwind CSS v4
    ├── src/
    ├── vite.config.js     # plugin Tailwind + proxy /api -> :8000
    ├── package.json
    └── run_frontend.bat   # npm install (si hace falta) + vite
```

## Requisitos

- Python 3.10+ (`python --version`)
- Node.js 20+ (`node --version`)

## Arranque rápido (Windows)

Doble clic o desde una terminal, en dos ventanas separadas:

```bat
backend\run_backend.bat
```

```bat
frontend\run_frontend.bat
```

Luego abre <http://localhost:5173>. El PIN por defecto es **`134113`**
(cámbialo definiendo `APP_PIN` antes de arrancar el backend).

Ambos scripts imprimen la **IP local** y las URLs para abrir la app desde el móvil:

```
==================================================================
  pc-power-remote  ·  servidor listo
  Backend local   : http://localhost:8000
  Backend red     : http://192.168.0.42:8000
  Swagger         : http://192.168.0.42:8000/docs
  Frontend (Vite) : http://192.168.0.42:5173
  PIN             : por defecto (134113) - define APP_PIN para cambiarlo
  Wake-on-LAN     : AA:BB:CC:DD:EE:FF
==================================================================
```

## Arranque manual

```bat
cd backend
python -m venv .venv
.venv\Scripts\activate
pip install -r requirements.txt
set APP_PIN=134113
uvicorn main:app --host 0.0.0.0 --port 8000 --reload
```

```bat
cd frontend
npm install
npm run dev
```

## Variables de entorno

| Variable            | Default           | Descripción                                                                 |
| ------------------- | ----------------- | --------------------------------------------------------------------------- |
| `APP_PIN`           | `134113`          | PIN exigido en la cabecera `X-App-Pin`. Cámbialo antes de usarlo.           |
| `APP_DRY_RUN`       | _(vacío)_         | `1` = simula el apagado sin ejecutar `shutdown.exe` (para pruebas).         |
| `APP_MAC_ADDRESS`   | _(autodetectada)_ | MAC de la NIC a encender. Si se define en el entorno tiene prioridad; si falta se detecta y se guarda en `.env`. |
| `APP_WOL_BROADCAST` | `255.255.255.255` | Dirección de broadcast del paquete mágico (usa la de tu subred, p. ej. `192.168.1.255`). |
| `APP_WOL_PORT`      | `9`               | Puerto UDP de Wake-on-LAN (algunos equipos usan `7`).                       |

## Wake-on-LAN automático

No hace falta escribir la MAC a mano. Al arrancar, el backend:

1. Lee `backend/.env` (si existe) sin sobrescribir variables ya definidas.
2. Si `APP_MAC_ADDRESS` está definida en el **entorno real**, la usa tal cual.
3. Si no, detecta la NIC activa principal:
   - Windows: `ipconfig /all`, cruzando la IP de la ruta por defecto con el bloque
     del adaptador y su *Dirección física*.
   - Fallback portable: `uuid.getnode()` (se descarta si devuelve una MAC aleatoria).
4. Guarda el resultado en `backend/.env` como `APP_MAC_ADDRESS=AA:BB:CC:DD:EE:FF`
   (solo reescribe si cambió, para no provocar recargas infinitas con `--reload`).

Así `/api/wake` funciona con un solo clic y sin body. El log de la terminal lo confirma:

```
13:38:57 [INFO] Wake-on-LAN listo: MAC 34:5A:60:7E:14:B2 (origen: auto)
13:39:17 [INFO] Wake-on-LAN enviado a 34:5A:60:7E:14:B2 via 255.255.255.255:9
```

El frontend muestra esa MAC en la tarjeta con la etiqueta **AUTODETECTADA**. Si el
usuario guarda una MAC distinta en el navegador, esa tiene prioridad para sus envíos;
el botón *Usar la del backend* la borra y vuelve a la autodetectada.

Para forzar otra MAC (p. ej. la de un PC distinto al que corre el backend), define
`APP_MAC_ADDRESS` en el entorno antes de arrancar; el `.env` no la pisa.

## Endpoints

| Método | Ruta           | Auth | Descripción                                        |
| ------ | -------------- | ---- | -------------------------------------------------- |
| GET    | `/`            | —    | Healthcheck: `{"status":"online","system":"Windows"}` |
| GET    | `/api/health`  | —    | Igual que `/`, para consumirse vía proxy de Vite   |
| GET    | `/api/state`   | PIN  | Estado del temporizador (`pending`, `seconds_left`)|
| POST   | `/api/shutdown`| PIN  | Body `{"minutes": int}` (1–1440) → `shutdown /s /t N` |
| POST   | `/api/cancel`  | PIN  | `shutdown /a`                                      |
| GET    | `/api/config`  | PIN  | MAC/broadcast/puerto WOL + `source` (`auto`, `env`, `env-file`, `none`) |
| POST   | `/api/wake`    | PIN  | Envía un paquete mágico Wake-on-LAN                 |
| GET    | `/docs`        | —    | Swagger UI (probar con el botón *Authorize*)       |

La cabecera obligatoria es `X-App-Pin`. Sin ella o con un valor incorrecto la API
responde `401`:

```bat
curl -X POST http://localhost:8000/api/shutdown ^
  -H "X-App-Pin: 134113" -H "Content-Type: application/json" ^
  -d "{\"minutes\": 15}"
```

```bat
curl -X POST http://localhost:8000/api/cancel -H "X-App-Pin: 134113"
```

Wake-on-LAN usa `APP_MAC_ADDRESS` si no se envía body, o la MAC indicada:

```bat
curl -X POST http://localhost:8000/api/wake -H "X-App-Pin: 134113"

curl -X POST http://localhost:8000/api/wake ^
  -H "X-App-Pin: 134113" -H "Content-Type: application/json" ^
  -d "{\"mac\": \"AA:BB:CC:DD:EE:FF\"}"
```

Respuestas de `/api/wake`: `200` con `{mac, broadcast, port}`, `401` sin PIN válido,
`409` si no hay MAC configurada, `422` si la MAC es inválida y `503` si falta la
librería `wakeonlan`.

## Frontend

- PIN por defecto `134113` (`DEFAULT_PIN` en `App.jsx`): si `localStorage` no tiene
  un PIN guardado se siembra ese valor, así la app funciona sin configuración manual.
  Se envía como `X-App-Pin` en cada llamada; si el backend lo rechaza (`401`), se borra
  y se muestra el modal para pedir el correcto.
- Botones rápidos: 5, 15, 30, 60 y 90 minutos, con confirmación previa.
- Countdown en vivo (sincronizado con `/api/state` cada 10 s) y botón destacado
  **Cancelar apagado**.
- Notificaciones de éxito/error y estado del enlace (online/offline).
- Tarjeta **Wake-on-LAN** con el botón destacado **Encender PC**. La MAC se puede
  editar en un modal (`MAC · editar`), se guarda en `localStorage`
  (`pc-power-remote.mac`) y se formatea automáticamente a `AA:BB:CC:DD:EE:FF`.
  Si no hay MAC local se usa la **autodetectada** por el backend (etiqueta
  *AUTODETECTADA*); si tampoco existe, la API responde `409` y la app abre el modal.

## Acceso desde el móvil

1. `ipconfig` → anota la IPv4 de tu PC (ej. `192.168.0.42`).
2. Ambos equipos en la misma red Wi-Fi.
3. Abre `http://192.168.0.42:5173` (frontend) o `http://192.168.0.42:8000/docs` (API).
4. Si no carga, permite Python/Node en el Firewall de Windows para redes privadas.

## Notas de arquitectura

- **Autenticación**: un único Dependency (`require_pin`) valida `X-App-Pin` contra
  `APP_PIN` con `hmac.compare_digest` (comparación en tiempo constante). Se aplica
  por endpoint con `dependencies=[Depends(require_pin)]`; `GET /` queda público.
- **Estado del temporizador**: se guarda en memoria (protegido por `threading.Lock`),
  no en el SO. `shutdown /a` sigue siendo la fuente de verdad: si Windows responde
  "no hay apagado pendiente" (código 1116) se devuelve `409` y se limpia el estado.
- **Errores del SO**: `FileNotFoundError`, `TimeoutExpired`, `OSError` y códigos de
  salida distintos de cero se traducen a `HTTPException` con el mensaje original de
  `shutdown.exe` (decodificado desde cp850, la codificación de Windows en español).
- **IP local en consola**: al arrancar, el backend detecta la IPv4 de la ruta por
  defecto con un socket UDP (sin enviar tráfico) y la imprime junto a los puertos
  `8000` (API) y `5173` (Vite). Los `.bat` hacen lo mismo con `ipconfig`.
- **CORS**: el backend permite cualquier origen porque el frontend en dev corre en otro
  puerto. En producción, limitar `allow_origins`.
- **Wake-on-LAN**: al arrancar, `_resolve_mac()` aplica la prioridad
  `APP_MAC_ADDRESS` real → autodetección (`ipconfig /all` + `uuid.getnode()`) →
  `.env`. La MAC detectada se persiste en `backend/.env` sin tocar otras claves.
  `POST /api/wake` normaliza la MAC (acepta `-`, `:` o sin separadores) y llama a
  `wakeonlan.send_magic_packet(mac, ip_address=APP_WOL_BROADCAST, port=APP_WOL_PORT)`.
  El envío es UDP broadcast: no necesita que el PC destino esté encendido, pero **sí**
  que el backend siga corriendo en otro equipo (o en el mismo, si se usa para despertar
  a un tercero). En la BIOS/UEFI y en el adaptador de red hay que habilitar
  *Wake on Magic Packet* / *Wake on LAN*.
- **Proxy de Vite**: el frontend llama a `/api/*` y Vite lo reenvía sin reescritura a
  `127.0.0.1:8000` (el backend ya expone sus rutas bajo `/api`). Así el navegador del
  móvil nunca necesita conocer la IP del backend ni hay CORS de por medio. Con
  `API_TARGET=http://127.0.0.1:8010 npm run dev` se puede apuntar a otro puerto.
- **Tailwind v4**: no requiere `tailwind.config.js`; el tema se declara en `src/index.css`
  con `@theme` y se activa con el plugin `@tailwindcss/vite`.

## Límites de seguridad conocidos

- El PIN viaja en texto plano por HTTP y se guarda en `localStorage`: cualquiera con
  acceso a la red local puede interceptarlo. Para uso real, publica el backend detrás
  de HTTPS (Tailscale, Caddy, Cloudflare Tunnel) y no lo expongas a Internet.
- No hay límite de intentos: añade rate limiting (p. ej. `slowapi`) si el equipo está
  en una red compartida.
- `shutdown /s /t N` solo programa el apagado; no hay endpoints de reinicio ni de
  suspensión todavía.
