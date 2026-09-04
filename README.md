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
  (+ archivo histórico: lee edicion:archive de KV, server.merge_archive lo actualiza con las
   bodas entregadas con horas trackeadas, y lo re-publica — viaja embebido en data.json como "archive")
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
- `server.py` — extracción de Notion (mismo que el local). Devuelve el modelo del dashboard
  (incluye `archive`: stats compactas de bodas entregadas — el estado persistente vive en KV
  `edicion:archive`; el `.archive.json` local que escribe en Actions es descartable).
- `publish.py` — corre en Actions: lee `edicion:archive` de KV (`prev_archive`), llama
  `build_data(prev_archive=...)` + `build_summary` → escribe `edicion:data`, `edicion:summary`
  y `edicion:archive` a KV vía API REST.
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
2. **Portar a `cloud/index.html` = copia directa** (`cp index.html cloud/index.html`). Desde el
   rediseño "Sala de Corte" el MISMO archivo sirve para local y nube: el `loadLive()` intenta
   `/api/data` (local) y luego `/api/edicion` (nube) en orden, y el `window.SNAPSHOT_DATA`
   embebido es el mismo payload real para ambos. Ya no hay que swapear la URL del fetch.
   Refresca el snapshot embebido de vez en cuando con el payload vivo (`curl localhost:4599/api/data`).
   Revisar `git diff` antes de commitear.
3. `git -C cloud add -A && git -C cloud commit && git -C cloud push` → **Cloudflare Pages auto-despliega (~1-2 min).**
4. Si cambiaste `server.py`: edita **ambos** (raíz + `cloud/server.py`), pushea el del cloud, y
   `gh workflow run "Publicar dashboard"` para republicar KV. Reinicia el local:
   `launchctl kickstart -k gui/$(id -u)/com.jordi.hub-edicion`.

**Verificación**: Claude Preview MCP funciona — `python3 -m http.server` (vía `.claude/launch.json`) +
`preview_screenshot`/`preview_eval`. Para datos reales: `curl localhost:4599/api/data` (server local).
`gh` se instala bajando el binario oficial si falta (auth en keychain). `python3 -m py_compile` valida `server.py`.

**Limitaciones del panel de preview** (del entorno, no de la app): no scrollea programáticamente
(verificar posiciones con `getBoundingClientRect`/`elementFromPoint` ocultando lo de arriba); no
bombea frames durante evals — `requestAnimationFrame` no dispara y las transiciones CSS no avanzan
(para leer el estado final de una clase: desactivar transición, aplicar, leer, restaurar). El botón de
tema llama `renderAll(M)` para repintar los SVG con los colores nuevos. También: el fetch vivo se prueba
con `curl localhost:4599/api/data`; en el panel estático (8753) cae al `SNAPSHOT_DATA` embebido (sello
"SNAPSHOT"), que ES el payload real más reciente, así que los números siguen siendo válidos para verificar.

**Gotchas iOS (PWA):** `backdrop-filter` + animación de `transform` exige `will-change:transform`
y animar solo transform (si no, WebKit descarta el blur → "se esfuma"); además el tabbar usa
**curvas de easing distintas por dirección** — reaparecer decelera (`--ease-out`) y ocultarse
acelera (`--ease-in`, `cubic-bezier(.68,0,.77,0)`, mirror del ease-out) — usar la misma curva
para ambas hacía que el ocultado se sintiera como un salto/desvanecido en vez de un deslizamiento;
`:active` solo se activa con un listener `touchstart` registrado (hay uno vacío global); el hover
emulado del tap se queda pegado — hay limpieza en `click` fuera de las gráficas; para ver una
versión nueva hay que **matar la PWA desde el app switcher** (recargar no basta). El deploy de
Pages NO se reporta a la API de GitHub — verificación solo visual (señal de versión nueva: la
barra de navegación flotante inferior).

## Modelo y comportamiento (decisiones de Jordi)
- **El 100% = terminar el montaje de HL/SF** (última etapa de edición). Una etapa marcada **'done' cuenta 100%**
  y sus escenas como completas — la marca de "hecho" a nivel etapa manda sobre el detalle de escenas.
- **"Cambios" / "Correcciones" = fase post-entrega** (depende de Claudio/Romina). **Excluida** de las horas
  de edición *efectivas* (Carrera, ahorro por etapa, $/h) y de la fecha de "edición lista". Se evalúa aparte por
  **rondas + horas/sesiones** (campo number "Ronda" en sesiones).
  Detección: nombre de etapa contiene "cambios" o "correcciones" (≠ "Corrección de Color y Finalización", singular).
  **PERO sí cuenta como tiempo trabajado** en HOY y Ritmo (horas por día — el tooltip desglosa "en cambios" —,
  tiles, racha, heatmap, cronotipo, histograma de sesiones): un día de correcciones es un día trabajado.
  Además, una etapa de Cambios `live` **no "reabre" la boda**: `hasLive` ignora correcciones, así la boda sigue
  siendo "edición terminada" para `refCur`/`refGhost` aunque estés metiendo cambios hoy.
- **Selector de proyecto = la lista de "En la mesa"** (sección Proyectos). **Tocar una boda** re-renderiza su
  donut/etapas/cinta con datos reales (nada de dropdown global). **Solo lista bodas que "miden"** (horas de
  edición efectivas > 0): las de solo correcciones o sin sesiones no aparecen. **Racha siempre global.**
- **Widgets** (`HubEdicion/widgets/`): iPhone (Scriptable) y Mac (SwiftBar) leen `/api/summary` con el Service Token.
- **Nav = rail lateral (desktop, plegable) + tabbar inferior (móvil)**; 6 secciones ancla: Carrera · Hoy ·
  Ritmo · ADN · Proyectos · Tarifa. **Tema claro/oscuro** en `localStorage` (`scTheme`). Todo lo derivan del
  payload en el navegador (`deriveModel`) — no hay estado de pestaña activa que persistir.
- **Rentabilidad:** `$/h`, `$/escena`, `$/etapa` sobre el **precio cobrado** = propiedad **Total** (MXN) de cada
  boda en Notion (`build_wedding` la lee como `price`; el dashboard prioriza `w.price`, con default si falta). En
  proyectos en curso, **`$/h proyectado`** = (tasa histórica `horas/escena` de bodas completas) × escenas de la boda
  → horas totales estimadas. Se afina conforme hay más bodas completas.
- **Carrera / comparación (boda a boda):** el hero enfrenta las **2 bodas con edición terminada más recientes**
  (la última como línea viva, la anterior como fantasma) — retrospectivo, siempre significativo aunque la boda
  en curso apenas arranque. `deriveModel` elige `refCur`/`refGhost` = bodas medidas sin etapas `live`, ordenadas
  por última sesión efectiva. La **anatomía del ahorro** y **El salto** ($/h) usan esa misma pareja. Solo entran
  bodas con `>0 h` de edición efectiva (las de solo correcciones no son referencia válida).
  **Historia a largo plazo:** el archivo histórico (`archive` en el payload, `.archive.json` local /
  KV `edicion:archive`) viaja siempre; `deriveModel` lo usa para que la comparación (Carrera / $/h) no
  pierda bodas cuando salen del tablero a los 45 días. Con los años, el fantasma pasará de "la anterior"
  a la **mediana del historial** (pendiente); el heatmap ya crece solo.
- **Bodas incluidas:** todas (Tipo = Boda) **menos las finalizadas inactivas > `RECENT_DONE_DAYS` (45) días**
  (`discover_wedding_pages`). El filtro de "finalizada" se hace en Python contra `DONE_STATUSES`
  (`Finalizadas`/`Hecho`/`Complete`…), **no en la consulta a Notion** — así renombrar la opción de Status
  ya no rompe el query (antes pedía `Status ≠ "Hecho"` y, al desaparecer esa opción, Notion devolvía 400).
  Robusto además a renombres de tablas/columnas: `build_wedding` parsea por tipo de propiedad, no por nombre exacto
  (y sin acentos: en Notion conviven columnas título `Sesión` y `Sesion` en la misma boda).
- **Límite de Notion (sep-2026):** una extracción son **~209 peticiones** y Notion permite **~3 req/s**. Sin freno
  el extractor se pasaba y Notion devolvía **429**, que tiraba el run entero de Actions (correos recurrentes de
  *"Publicar dashboard failed"*). Ahora `notion()` **espacia todas las peticiones** (`NOTION_MIN_INTERVAL` 0,40 s
  → 2,5 req/s; extracción ~2 min, timeout del job 10) y ante 429/5xx **reintenta con backoff exponencial**
  (`NOTION_TRIES` 6: 2, 4, 8, 16, 30 s respetando `Retry-After` ≈ 60 s de aguante, frente a ~4 s de antes).
- **Nunca publicar datos degradados:** si la consulta a la DB raíz falla, `discover_wedding_pages` cae a
  `FALLBACK_WEDDING_PAGES` (2 bodas hardcodeadas) = tablero mutilado con pinta de sano. `build_data` lo marca
  `degraded: true` y **`publish.py` aborta con exit 1 sin tocar KV**: el run se ve fallido y la nube conserva los
  últimos datos buenos, en vez de que el tablero se vacíe en silencio (ya pasó con el 400 del Status renombrado).
- **Proyectos de solo correcciones:** página con un DB **"Sesiones" directo** (sin "Tracking de Edición"/etapas).
  `build_wedding` los lee como una etapa **"Correcciones"** (`isCorrections`); NO cuentan como horas de edición
  efectivas, así que esas bodas quedan fuera de Proyectos/Carrera/Tarifa (no son referencia válida) — pero sus
  sesiones sí suman como tiempo trabajado en HOY/Ritmo.
- **Nav (nuevo):** **rail lateral** flotante en desktop (≥1200px, plegable: iconos ↔ iconos+labels) y **tabbar
  inferior** flotante en móvil/tablet (blur + safe-area). Scroll-spy resalta la sección activa (IntersectionObserver);
  no hay pestañas ni estado que persistir (una sola vista con anclas). Tema en `localStorage` `scTheme`.
- **Interfaz viva (nuevo, `@media(hover:hover)`):** tarjetas se elevan al cursor; en las gráficas la marca bajo el
  cursor **crece y el resto se atenúa** vía clases `.fx` (en el `<svg>`) + `.hot` (la barra), tras `.settled`; el
  **centro del donut reacciona** (segmentos con listeners `pointerenter`: muestra etapa · horas · $ · % en su color,
  restaura el total al salir). Todo con transform/opacity, respeta `prefers-reduced-motion`.
- **Gráficas que se reconstruyen por breakpoint:** la Carrera y "Horas por día" se re-dibujan al cruzar 640px
  (viewBox y grosores distintos en móvil) vía un registro `regRebuild`; el **heatmap** se re-renderiza al cambiar el
  ancho (rellena semanas previas hasta llenar la tarjeta) y ancla el scroll a hoy. Helper `barPath()` para las barras.

## Datos de referencia (Cloudflare)
- Account ID: `3e5d3a65aa4f2a3819cdaacc1c92c6d9` · KV namespace "hub" ID: `c183c5e72d5e48a19d07fd6831ececeb`
- Zero Trust team: `steep-wood-c7bc` · Access app: "Hub" (PIN para humanos + Service Auth para widgets).

---

## Setup original (referencia histórica — ya hecho)
KV namespace `hub` → Pages "Connect to Git" (Framework None, output `/`) → binding `HUB_KV` → secretos en GitHub →
Run workflow → Zero Trust Free → Access app self-hosted sobre `hub-edicion.pages.dev` (login PIN, sesión 1 mes,
policy Allow email) → Service Token + policy Service Auth para los widgets.
GOTCHA UI: para crear el proyecto Pages, en Workers&Pages → Create application → abajo "Looking to deploy Pages? Get started".
