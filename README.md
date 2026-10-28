# Hub de Edición — nube (DESPLEGADO Y OPERATIVO)

Dashboard de métricas de edición de bodas, en la nube. Accesible desde cualquier lugar, con la Mac
apagada, detrás de login, **100% gratis**.

- **URL:** https://hub-edicion.pages.dev
- **Login:** Cloudflare Access — **One-time PIN por correo** (jor.jorwww@gmail.com), sesión 1 mes.
- **Repo:** `github.com/jordissan/hub-edicion` (**público**). Nunca tokens. ⚠️ `index.html` lleva embebido el
  snapshot (`SNAPSHOT_DATA`) con datos reales de las bodas — ver "Privacidad" en `docs/arquitectura.md` §9.

## Arquitectura

```
GitHub Actions (cron cada 30 min · TZ America/Mexico_City)
  publish.py → server.py extrae Notion → escribe data.json + summary.json en Cloudflare KV (namespace "hub")
  (+ archivo histórico: lee edicion:archive de KV, server.merge_archive lo actualiza con las
   bodas entregadas con horas trackeadas, y lo re-publica — viaja embebido en data.json como "archive")
        │
Cloudflare Pages  (siempre encendido, gratis)
  index.html              → el dashboard
  functions/api/edicion   → lee data.json de KV     (lo usa el dashboard)
  functions/api/summary   → lee summary.json de KV   (lo usan los widgets)
  functions/api/session   → POST: registra un sprint como sesión en Notion
                            (directo con el secreto NOTION_TOKEN; si no, cola KV edicion:pending:<id>
                             que publish.py vacía al inicio de cada corrida)
  Cloudflare Access (PIN) → protege TODO; los widgets entran con un Service Token
        │
iPhone / navegador → https://hub-edicion.pages.dev
```

La Mac no participa: el extractor vive en GitHub Actions. (Existe una copia local en `/Users/jordi/HubEdicion/`
con su `server.py` + launchd en el puerto 4599 — es **backup/dev** para probar con datos reales.)

## Archivos
- `server.py` — extracción de Notion (mismo que el local). Devuelve el modelo del dashboard
  (incluye `archive`: stats compactas + curva `ghost` de bodas entregadas — el estado persistente vive en KV
  `edicion:archive`; el `.archive.json` local que escribe en Actions es descartable).
- `publish.py` — corre en Actions: lee `edicion:archive` de KV (`prev_archive`), llama
  `build_data(prev_archive=...)` + `build_summary` → escribe `edicion:data`, `edicion:summary`
  y `edicion:archive` a KV vía API REST.
- `functions/api/edicion.js`, `functions/api/summary.js` — leen de KV (binding `HUB_KV`).
- `functions/api/session.js` — `POST /api/session`: registra un **sprint de enfoque** como sesión en Notion
  (valida contra la lista blanca de `edicion:data`; directo con `NOTION_TOKEN`, si no cola `edicion:pending:<id>`).
- `docs/arquitectura.md` — referencia técnica completa (la copia `sync-cloud.sh`).
- `.github/workflows/publish.yml` — cron + `workflow_dispatch`. Secretos: `NOTION_TOKEN`, `CF_API_TOKEN`,
  `CF_ACCOUNT_ID`, `CF_KV_NAMESPACE_ID`. Lleva `env: TZ: America/Mexico_City` (el runner es UTC).
- `index.html`, `manifest.json`, `icon-*.png` — el sitio estático.

## Cómo se actualizan los datos
- **Solo:** cada 30 min (cron de Actions). GitHub pausa crons si el repo no tiene actividad en 60 días.
- **A mano / ya:** `gh workflow run "Publicar dashboard" -R jordissan/hub-edicion` (o Actions → Run workflow).

## Cómo cambiar el dashboard (mantenimiento)
**Se edita el LOCAL (`~/HubEdicion/`) y se porta aquí** — nunca al revés.
1. Edita `~/HubEdicion/index.html` y/o `server.py` y pruébalo con datos reales en <http://localhost:4599>.
2. `~/HubEdicion/sync-cloud.sh` → copia `index.html`, `server.py` y `docs/arquitectura.md` a esta carpeta
   y muestra el diff (no publica).
3. `~/HubEdicion/sync-cloud.sh --publicar "mensaje"` → commit + push (**Cloudflare Pages despliega solo,
   ~1-2 min**); si cambió `server.py`, además lanza el workflow para republicar KV y reinicia el server local.
4. `publish.py`, `functions/` y `.github/workflows/` viven solo aquí: se editan directamente en `cloud/`.

`server.py` es **idéntico** al de la raíz (se copia tal cual). El deploy de Pages no se reporta a la API de
GitHub: la verificación es visual (en el iPhone, matar la PWA y reabrir).

## Secretos y variables
- **GitHub Actions** (Settings → Secrets): `NOTION_TOKEN`, `CF_API_TOKEN` (Workers KV Storage: Edit),
  `CF_ACCOUNT_ID`, `CF_KV_NAMESPACE_ID`.
- **Cloudflare Pages** (Settings → Variables and Secrets): `NOTION_TOKEN` **opcional** — con él, el sprint
  registra al instante desde la nube; sin él, queda en cola KV y `publish.py` lo crea en la siguiente corrida.
  Binding KV: `HUB_KV`.
- **Widgets**: Service Token de Cloudflare Access (Client ID + Secret) pegado en el script de Scriptable.

## Modelo, reglas y detalles técnicos
Todo lo que explica **cómo** funciona (contrato del payload, extracción, `deriveModel`, Carrera/fantasma,
archivo histórico, sprint y estados, movimiento, claves de KV y del navegador, plantilla de Notion y trampas
conocidas) está en [`docs/arquitectura.md`](docs/arquitectura.md) — copia versionada de
`~/HubEdicion/docs/arquitectura.md`.

## Datos de referencia (Cloudflare)
- Account ID: `3e5d3a65aa4f2a3819cdaacc1c92c6d9` · KV namespace "hub" ID: `c183c5e72d5e48a19d07fd6831ececeb`
- Zero Trust team: `steep-wood-c7bc` · Access app: "Hub" (PIN para humanos + Service Auth para widgets).

---

## Setup original (referencia histórica — ya hecho)
KV namespace `hub` → Pages "Connect to Git" (Framework None, output `/`) → binding `HUB_KV` → secretos en GitHub →
Run workflow → Zero Trust Free → Access app self-hosted sobre `hub-edicion.pages.dev` (login PIN, sesión 1 mes,
policy Allow email) → Service Token + policy Service Auth para los widgets.
GOTCHA UI: para crear el proyecto Pages, en Workers&Pages → Create application → abajo "Looking to deploy Pages? Get started".
