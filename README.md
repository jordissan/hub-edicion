# Hub de Edición — nube (DESPLEGADO Y OPERATIVO)

Dashboard de métricas de edición de bodas, en la nube. Accesible desde cualquier lugar, con la Mac
apagada, detrás de login, **100% gratis**.

- **URL:** https://hub-edicion.pages.dev
- **Login:** Cloudflare Access — **One-time PIN por correo** (jor.jorwww@gmail.com), sesión 1 mes.
- **Repo:** `github.com/jordissan/hub-edicion` (público — solo código, nunca datos ni tokens).

## Arquitectura

```
GitHub Actions (cron cada 30 min · TZ America/Mexico_City)
  publish.py → server.py extrae Notion → escribe data.json + summary.json en Cloudflare KV (namespace "hub")
        │
Cloudflare Pages  (siempre encendido, gratis)
  index.html              → el dashboard
  functions/api/edicion   → lee data.json de KV     (lo usa el dashboard)
  functions/api/summary   → lee summary.json de KV   (lo usan los widgets)
  Cloudflare Access (PIN) → protege TODO; los widgets entran con un Service Token
        │
iPhone / navegador → https://hub-edicion.pages.dev
```

La Mac no participa: el extractor vive en GitHub Actions. (Existe una copia local en `/Users/jordi/HubEdicion/`
con su `server.py` + launchd en el puerto 4599 — es **backup/dev** para probar con datos reales.)

## Archivos
- `server.py` — extracción de Notion (mismo que el local). Devuelve el modelo del dashboard.
- `publish.py` — corre en Actions: `build_data` + `build_summary` → escribe a KV vía API REST.
- `functions/api/edicion.js`, `functions/api/summary.js` — leen de KV (binding `HUB_KV`).
- `.github/workflows/publish.yml` — cron + `workflow_dispatch`. Secretos: `NOTION_TOKEN`, `CF_API_TOKEN`,
  `CF_ACCOUNT_ID`, `CF_KV_NAMESPACE_ID`. Lleva `env: TZ: America/Mexico_City` (el runner es UTC).
- `index.html`, `manifest.json`, `icon-*.png` — el sitio estático.

## Cómo se actualizan los datos
- **Solo:** cada 30 min (cron de Actions). GitHub pausa crons si el repo no tiene actividad en 60 días.
- **A mano / ya:** `gh workflow run "Publicar dashboard" -R jordissan/hub-edicion` (o Actions → Run workflow).

## Cómo cambiar el dashboard (mantenimiento)
**Se edita el LOCAL primero, luego se porta al cloud** (no al revés). El local
(`/Users/jordi/HubEdicion/index.html`) es la fuente: tiene `fetch('/api/data')` + el
`window.SNAPSHOT_DATA` real, y se prueba con datos reales vía el server (puerto 4599).
1. Editar `/Users/jordi/HubEdicion/index.html` (y `server.py` si toca la extracción de Notion).
2. **Portar a `cloud/index.html`** con un mini-script Python que copia el local pero **preserva
   2 cosas del cloud**: su bloque `window.SNAPSHOT_DATA` (scrubbeado) y el `fetch('/api/edicion')`
   (el local usa `/api/data`). Revisar `git diff` antes de commitear.
3. `git -C cloud add -A && git -C cloud commit && git -C cloud push` → **Cloudflare Pages auto-despliega (~1-2 min).**
4. Si cambiaste `server.py`: edita **ambos** (raíz + `cloud/server.py`), pushea el del cloud, y
   `gh workflow run "Publicar dashboard"` para republicar KV. Reinicia el local:
   `launchctl kickstart -k gui/$(id -u)/com.jordi.hub-edicion`.

**Verificación**: Claude Preview MCP funciona — `python3 -m http.server` (vía `.claude/launch.json`) +
`preview_screenshot`/`preview_eval`. Para datos reales: `curl localhost:4599/api/data` (server local).
`gh` se instala bajando el binario oficial si falta (auth en keychain). `python3 -m py_compile` valida `server.py`.

## Modelo y comportamiento (decisiones de Jordi)
- **El 100% = terminar el montaje de HL/SF** (última etapa de edición). Una etapa marcada **'done' cuenta 100%**
  y sus escenas como completas — la marca de "hecho" a nivel etapa manda sobre el detalle de escenas.
- **"Cambios" / "Correcciones" = fase post-entrega** (depende de Claudio/Romina). **Excluida** del avance %, horas
  de edición, entrega y donut. Se evalúa aparte por **rondas + horas/sesiones** (campo number "Ronda" en sesiones).
  Detección: nombre de etapa contiene "cambios" o "correcciones" (≠ "Corrección de Color y Finalización", singular).
- **Selector de proyecto = menú desplegable.** Al elegir una boda, **todas las gráficas filtran a ese proyecto**
  (hero, donut, drilldown, KPIs Hoy/Sesiones, alertas, timeline, acumulado, horas/día). **Racha siempre global.**
- **Widgets** (`HubEdicion/widgets/`): iPhone (Scriptable) y Mac (SwiftBar) leen `/api/summary` con el Service Token.
- **Nav por pestañas:** Resumen · Bodas · Evolución (estado en `localStorage`). "Hoy" se fusionó en Resumen.
- **Rentabilidad:** `$/h`, `$/escena`, `$/etapa` sobre el **precio cobrado** = propiedad **Total** (MXN) de cada
  boda en Notion (`build_wedding` la lee como `price`; el dashboard prioriza `w.price`, con default si falta). En
  proyectos en curso, **`$/h proyectado`** = (tasa histórica `horas/escena` de bodas completas) × escenas de la boda
  → horas totales estimadas. Se afina conforme hay más bodas completas.
- **Evolución (boda a boda):** records, deltas y tendencias ($/h, h/escena, días, horas) **solo de bodas COMPLETAS**.
  Las en progreso se muestran en tarjetas pero no entran a la comparación (no es justo comparar a medias vs terminadas).
- **Bodas incluidas:** activas (Status ≠ Hecho) **+ finalizadas en los últimos `RECENT_DONE_DAYS` (45) días**
  (`discover_wedding_pages`, filtro `last_edited_time`) — para no perder el tiempo de proyectos recién cerrados.
- **Proyectos de solo correcciones:** página con un DB **"Sesiones" directo** (sin "Tracking de Edición"/etapas).
  `build_wedding` los lee como una etapa **"Correcciones"** (`isCorrections`), así su tiempo cuenta en el log diario.
- **Selector de proyecto:** etiqueta cada boda por estado — `en curso` · `correcciones` · `finalizada` (Status "Hecho").

## Datos de referencia (Cloudflare)
- Account ID: `3e5d3a65aa4f2a3819cdaacc1c92c6d9` · KV namespace "hub" ID: `c183c5e72d5e48a19d07fd6831ececeb`
- Zero Trust team: `steep-wood-c7bc` · Access app: "Hub" (PIN para humanos + Service Auth para widgets).

---

## Setup original (referencia histórica — ya hecho)
KV namespace `hub` → Pages "Connect to Git" (Framework None, output `/`) → binding `HUB_KV` → secretos en GitHub →
Run workflow → Zero Trust Free → Access app self-hosted sobre `hub-edicion.pages.dev` (login PIN, sesión 1 mes,
policy Allow email) → Service Token + policy Service Auth para los widgets.
GOTCHA UI: para crear el proyecto Pages, en Workers&Pages → Create application → abajo "Looking to deploy Pages? Get started".
