# Hub de Edición — arquitectura y referencia técnica

> Referencia única para **mantener** el proyecto. La guía de uso está en el
> [`README.md`](../README.md) de la raíz; la operación de la nube, en [`cloud/README.md`](../cloud/README.md).
> Este archivo vive en `docs/` y `sync-cloud.sh` lo copia a `cloud/docs/` (queda versionado en git).

---

## 1. Piezas y flujo de datos

```
                       Notion (workspace "Trabajo")
                                   │  API (token de integración, lectura + escritura)
          ┌────────────────────────┴────────────────────────┐
   LOCAL (Mac, backup/dev)                         NUBE (siempre encendida)
   server.py · launchd · :4599                     GitHub Actions (aviso del Mac c/15 min
     └─ c/15 min: gh workflow run ───────────▶        + cron */30 de respaldo, ver §10)
     GET  /api/data     payload completo             publish.py → importa server.py
     GET  /api/summary  resumen widgets                ├─ drain_pending(): cola de sprints → Notion
     POST /api/session  registra un sprint             ├─ build_data() / build_summary()
     POST /api/close    cierra escena/etapa (🟢)       │  (drain_pending también aplica cierres)
     GET/POST /api/sprint-state (ventana flotante)     │
     GET  /api/health                                  └─ escribe Cloudflare KV
     caché .cache.json + .archive.json             Cloudflare Pages (detrás de Access)
                                                     index.html
                                                     functions/api/edicion  → KV edicion:data
                                                     functions/api/summary  → KV edicion:summary
                                                     functions/api/session  → Notion o cola KV
                                                     functions/api/close    → Notion o cola KV
          └────────────────────────┬────────────────────────┘
                     index.html (el MISMO archivo en ambos)
                     últimos datos guardados (o snapshot) → loadLive() → deriveModel() → render*
                     Widgets: iPhone (Scriptable → nube) · Mac (SwiftBar → local)
```

- **El local es la fuente.** Se edita en `~/HubEdicion/` y se porta a `cloud/` con
  `./sync-cloud.sh` (ver §8). `cloud/server.py` es una copia **idéntica** del raíz.
- **Todo cálculo vive en el navegador** (`deriveModel`): `server.py` solo extrae y normaliza
  Notion. Excepción: el resumen de widgets (`build_summary`) replica algunas reglas en Python
  (meta diaria, racha, avance, fase/color) — si cambias una, cambia la otra.

## 2. Contrato del payload (`/api/data` · KV `edicion:data` · `SNAPSHOT_DATA`)

```jsonc
{
  "generatedAt": "2026-10-28T00:17:38",   // hora local de la extracción
  "today": "2026-10-28",
  "live": true,
  "degraded": false,                      // true = solo bodas de respaldo → publish.py NO publica
  "weddings": [{                          // tablero: activas + finalizadas con sesiones en ≤45 días
    "name", "icon", "studio", "status", "priority", "url",
    "price": 13000,                       // propiedad "Total" (MXN); el front usa 13000 si falta
    "projectStart", "projectEnd",
    "stages": [{
      "id": "…",                          // página de la etapa (el sprint cambia su estado)
      "etapa": "Montaje (DCT)", "fase": "DCT",
      "estado": "done|live|wait",         // ⚪️ wait · 🔵 live · 🟢 done (norm_estado)
      "orden": 6, "start", "end",         // "Del → Al"
      "isCorrections": false,             // etapa "Cambios"/"Correcciones"
      "hours": 8.4, "sessions": 18,
      "sessionDb": "…",                   // DB "Sesiones" de la etapa (null si no tiene)
      "sessionLog": [{ "name", "inicio": "2026-10-27T17:05", "min": 43,
                       "tipo": "Edición|Gestión", "ronda": null, "escena": "<id>" }],
      "scenes": [{ "id", "escena", "estado", "orden", "cancion", "dia", "start", "end" }]
    }]
  }],
  "archive": [{                           // bodas entregadas con horas (persistente)
    "name", "icon", "hours", "scenes", "span", "price", "rounds", "lastEnd", "archivedAt",
    "ghost": { "v": 2, "projectStart", "projectEnd",
               "stages": [{ "etapa", "fase", "isCorrections", "estado", "sessions",
                            "hours", "nScenes", "days": { "2026-09-07": 26 } }] }
  }]
}
```

**Resumen de widgets** (`/api/summary` · KV `edicion:summary`): `generatedAt, today, todayMin,
metaMin, streak, week[{key,min,meta}], overallProgress, active{wedding, icon, stage, stageColor,
stageProgress, stageHours, scene}, weddings[{name, icon, progress, done, live, wait, stages, hours}]`.
`progress` = etapas de edición hechas / etapas de edición (igual que el "Avance %" del dashboard);
`stageColor` = color de la fase (`PHASE_COLORS`, mismos tokens del dashboard).

## 3. Extracción (`server.py`)

| Función | Qué hace |
|---|---|
| `notion()` | Cliente HTTP: **throttle** 0,40 s entre peticiones (Notion ≈ 3 req/s) + **backoff** ante 429/5xx (6 intentos: 2-4-8-16-30 s, respeta `Retry-After`). Una extracción ≈ 200 peticiones ≈ 2 min. |
| `discover_wedding_pages()` | Páginas `Tipo = Boda` de la DB "Trabajo". Deja fuera las **finalizadas sin sesiones en 45 días** (`RECENT_DONE_DAYS`; la actividad sale de `lastActivity`/`lastEnd` del archivo previo o del fin de *Fecha*, y solo a falta de ambos de `last_edited_time`, para que una edición masiva en Notion no las regrese al tablero; "finalizada" = `DONE_STATUSES`, comparado en Python para que renombrar la opción en Notion no rompa la consulta). Si la consulta falla → `FALLBACK_WEDDING_PAGES` y `degraded: true`. |
| `build_wedding()` | Busca la sub-DB "Tracking de Edición" → etapas → dentro de cada etapa, sub-DBs de **escenas** (título "Escena…") y de **sesiones**. Sin tracking: DB "Sesiones" directa = etapa "Correcciones". Parsea por **tipo** de propiedad y sin acentos (conviven "Sesión"/"Sesion"). |
| `is_session_log_db()` | Una DB es de sesiones solo si tiene fechas **Inicio y Fin**. ⚠️ "Tiempo total" también titula su columna "Sesión". |
| `merge_archive` / `backfill_ghosts` | Upsert del archivo con las finalizadas del tablero; reconstruye desde Notion (máx. `BACKFILL_MAX` = 2 por corrida) las entradas sin `ghost` o con `GHOST_VERSION` vieja. Subir la versión fuerza el re-backfill. |
| `build_summary()` | Resumen para widgets (§2). |
| `create_session()` / `set_in_progress()` | Registro de sprints (§5). |

**Caché local:** stale-while-revalidate de 3 min (`CACHE_TTL`) en memoria + `.cache.json`.
Un **candado** (`_build_lock`) garantiza una sola extracción a la vez: el ↻ o un registro que
llega durante una extracción en curso espera su resultado en vez de lanzar otra.

## 4. El dashboard (`index.html`)

Un solo archivo: CSS (tokens Pantone, tema claro/oscuro) + HTML + un `<script>` en este orden:

1. **`SNAPSHOT_DATA`** — último payload real embebido: render instantáneo y respaldo sin servidor.
2. **`deriveModel(payload)`** (IIFE, sin DOM) — contrato Notion → modelo `M`. Reglas clave:
   - **Fase + rol** (`phaseOf`/`roleOf`/`keyOf`): las plantillas vieja y nueva se comparan.
     Fases: PREP · TEAS · DCT(doc) · HL/SF · CMB(cam).
   - **Cambios/Correcciones**: fuera de las horas *efectivas* (Carrera, ahorro, $/h, "edición
     lista"), dentro del tiempo trabajado (Hoy, Ritmo, racha, heatmap). Una etapa de Cambios
     viva no "reabre" la boda (`hasLive` la ignora).
   - **Boda en curso** (`inProgress`, nov-2026): `hasLive` **o** (con horas efectivas, no archivada,
     con alguna etapa de edición ≠ `done` —en curso o sin iniciar— y `status` que NO sea
     Finalizadas/Hecho/Correcciones). Cambios nunca cuenta. Antes se decía "terminada" cuando no
     había etapa `live`, y una boda con la etapa siguiente aún sin iniciar (Ale + Lorenzo, 5-nov,
     Montaje HL/SF ⚪️) se daba por entregada. Una boda en curso queda fuera de `refCur`/`refGhost`,
     de la Carrera y de las métricas finales; chip EN CURSO en Proyectos y fila en Hoy.
   - **Carrera**: `refCur`/`refGhost` = las 2 bodas con edición terminada más recientes (incluye
     archivadas reconstruidas desde `ghost`); compara **solo fases compartidas**.
   - **h/escena** sin teaser; **$/h** con todo (el precio lo incluye).
   - **Heatmap**: sesiones del tablero + `ghost.days` de las archivadas fuera del tablero.
   - **Avance %** = etapas de edición hechas / etapas de edición (Cambios no cuenta): el 100 %
     es terminar la última etapa (Montaje HL/SF). Varias etapas pueden ir en curso a la vez.
   - **Rentabilidad**: $/h, $/escena, $/etapa sobre el precio cobrado (`Total`) de la última
     boda entregada vs la anterior.
   - **Proyectos**: bodas que miden (horas efectivas > 0) + Archivo (`archOrder`).
   - **`sprintTargets`**: etapas no terminadas con `sessionDb`, en curso primero.
3. **Capa de render** — `fmt/fmtHM/fmtMXN`, `S()` (SVG), `barPath`, tooltip, `liveBar`;
   `render{Chrome,Hero,Race,Hoy,Dia7,Ritmo,Adn,Mesa,Tarifa}`. `renderAll` aísla cada sección
   (si una falla, las demás se pintan). `regRebuild(nombre, fn)` registra las gráficas que cambian
   de geometría al cruzar 640 px (hoy: Horas por día). **Horas por día** en escritorio se dibuja a
   escala real (viewBox = ancho de su tarjeta × 250, alto fijo) y un `ResizeObserver` sobre
   `.dia7card` la redibuja vía `rebuilds.get('dia7')` si cambia el ancho (7-nov-2026). La **Carrera** (`renderRace`) se dibuja al
   tamaño real del contenedor (viewBox = px) y un `ResizeObserver` la redibuja al cambiar el ancho;
   < 560 px usa la versión compacta (nombres como pastillas `#raceChips`). La curva es una guía
   visual (`raceCurve`). Primero, suavizado gaussiano (σ 3,4 días) con reflejo impar en los bordes:
   conserva el primer y el último valor reales y nunca baja. Después, cúbica monótona
   (Fritsch–Carlson) sobre nudos cada 3 días más "edición lista" y el último día. Resultado: curvas
   amplias, sin tirones, con los puntos clave sobre la línea. Tooltip, tabla y cifras usan los
   valores reales. Tramos tras "edición
   lista" = Cambios (punteados, `.fadein`); las curvas de edición son `path.draw` (las anima
   `__playRace`). Las propuestas de diseño que llevaron a este hero están en
   `docs/propuestas/carrera.html`.
4. **`Sprint`** — tarjeta de enfoque (§5). Justo después, el módulo **sprint compacto** (7-nov-2026,
   solo si `!MINI`): reacomoda los nodos reales de `#focus` (mismos ids y listeners) dentro de
   tres ventanas emergentes `.sx-pop` — esquema (`#fMode`, `#fPlan`, `#fAdj`, `#fEdit`), destino
   (`#fPick`) y ⋯ (`#fCut`, `#fDrop`) — y les pone disparadores (`.sx-chip`, `.sx-destbtn`, `.sx-more`)
   cuyos textos y visibilidad sigue un `MutationObserver` (los `hidden` que pone `paint()`). Clase
   `.focuscard.sx`. **La ventana flotante (`?mini=1`) no se toca**: su CSS depende de
   `#focus>div:nth-child(1|2)` y `.fact`, que se conservan en el HTML.
   **Acomodo (reacomodo B, 7-nov-2026):** cuadrícula de 12 columnas (capa «REACOMODO DE TARJETAS» al
   final del `<style>`, con `@container wrap` ≥931 / ≤930 y `@media` ≤640). `.hoy` = `#focus`,
   `.cifras` (envuelve `#tilesRow` y `#miniRow`, que van con `display:contents`), `.dia7card`,
   `.plan`. `#aipBox` vive en `.adn` entre *Duración* y `#anatCard`. Ojo: esa capa usa selectores
   simples y depende de ir **al final** de la hoja principal (no en `<style id="fonts">`).
5. **Navegación + tema**
   - **Sidebar `#side`** (≥1024 px; plegado = `html.side-closed`, guardado en `scSide`). Sin
     preferencia guardada, arranca desplegado desde 1280 px. El pre-script del `<head>` pone la
     clase antes de pintar, así no parpadea.
   - **Marca = icono de la app.** El símbolo `#i-mark` (tres pistas de timeline + playhead
     `--sun`) es la fuente. `icon-180/192/512.png` (apple-touch-icon, favicon y `manifest.json`)
     son ese mismo dibujo sobre tesela OLED `#050506` con vidrio y halo lima, a ancho completo
     (iOS/macOS redondean las esquinas). Si cambia la marca, se regeneran los PNG (y se copian a
     `cloud/` a mano: `sync-cloud.sh` no los porta). `server.py` los sirve por lista blanca.
   - **`renderSide(M)`** pinta el saludo, el dato vivo de cada sección y "En la mesa" (anillo de
     avance + segmentos por etapa). Tocar una boda llama a `renderMesa._select`.
   - **Espejo del sprint:** un `MutationObserver` sobre `#tcode`, `#focus`, `#focusBtn` y la etapa
     copia lo que pinta la tarjeta de Hoy. Su botón hace `click()` en el real, así que no hay
     lógica duplicada. El anillo del riel y el del botón móvil (`.dock .fab`) usan el bloque de
     `scSprint`; tocar el anillo lleva a la tarjeta.
   - **Scroll-spy** (IntersectionObserver sobre `.hero`/`.sec`): marca `nav a` (sidebar y
     tabbar), mueve la pastilla `#sInd`, actualiza la barra superior `.crumb` y pone `--amb1`
     (luz ambiente, propiedad `@property` con transición).
   - **Tema** en `scTheme`; al cambiarlo, `renderAll` + `applyGlow()`.
   - **Identidad A (capa CSS al final del `<style>`):**
     - El grano (`--grain`, ruido generado en un canvas) vive en `.amb::after` y en el `::before`
       de `.card`, `.m` y el sidebar; nunca encima de los datos.
     - Intensidad del grano: una perilla, **`--grain-k`** (0,5 desde el 30-oct = mitad de lo original),
       que multiplica la opacidad por tema (`--grain-o` fondo 0,55/0,45 · `--grain-c` materiales 0,42/0,32).
     - Los halos de los SVG son filtros del sprite (`fxGlow` barras señaladas `.glw`, `fxGlowL`
       la curva, `fxGlowD` el donut). Las barras usan degradados compartidos (`gfill()` →
       `#gSun/#gVio/#gNar`). La opacidad de su base es **`--bar-fade`**: 0,42 en oscuro y 0,61 en claro
       (velo −33 %, 3-nov-2026).
     - Heatmap «Intensidad diaria»: `--h1…--h5` por tema. En claro va de lima pálido a oliva-lima
       vivo (`#dae7b7 → #799100`), sin llegar a oscuro, más un halo en `.s5` (3-nov-2026).
     - Una sola perilla: **`--glow`** (0,72 oscuro, −28 % vs la maqueta; 0,3 claro).
       `applyGlow()` la lleva a los `feFuncA[data-g]`.
     - Las rejillas responden al ancho real del contenido con container queries sobre `.wrap`
       (con sidebar ya no basta el viewport).
     - Rendimiento:
       - Nada se mueve en bucle: la luz ambiente está quieta.
       - El cambio de color por sección funde dos capas (`.amb .o1`) solo por opacidad, en la GPU.
       - El grano son puntos claros y oscuros con alfa, sin `mix-blend-mode`.
       - Los halos se encienden al terminar la entrada (`.settled`), así no se recalculan
         cuadro a cuadro.
       - Donut: el halo va en un solo grupo (`#donut .dsegs`), no en cada segmento, y se apaga
         mientras gira (`#donut.swirl`, se quita al acabar las animaciones). Así, al cambiar de
         boda ya entrada no se recalculan 12 desenfoques por cuadro: el ráster del cambio bajó
         de ~1,9 s a ~0,2 s (Chromium por CPU; en WebKit los filtros SVG van por CPU).
       - Lo que late en bucle (etapa en curso del sidebar, `.wsegs i.l::after`) funde opacidad;
         animar `background` repintaba el sidebar en cada cuadro.
       - `fitLabels` (nombres de la cinta) escribe, lee y escribe en pasadas separadas: un solo
         layout, no uno por clip.
       - Al plegar el sidebar (`html.side-anim`), la Carrera y el salto se redibujan una sola
         vez al final.
     - Duraciones de entrada: piezas 520 ms, cascada 32 ms, curva 950 ms, donut 600 ms.
6. **Reveal** — cada pieza (hijos de `.hero`/`.sec` y de las rejillas) es una unidad `.rv`.
   Entra con WAAPI (no CSS, para no pisar los `transform` de hover) al cruzar el 8 % inferior,
   en cascada; se **rearma al salir del todo** y reentra desde la dirección del scroll (`.up`).
   `.in` dispara las transiciones internas (`.in .gbar`, `.in .heat .cell`…); `.settled` llega a
   los 1,6 s. Paneles-lista (`LIST_ROWS`): la tarjeta hace fade y sus filas entran con `cascade`
   (izquierda → derecha). Ganchos: `__playRace`/`__resetRace`, `__swirlDonut`.
   ⚠️ Si la tarjeta misma lleva la clase del componente (`.card.anat`) usa `.anat.in …`, no `.in .anat …`.
7. **Boot** — pinta al instante la **última lectura viva guardada** en este navegador
   (`localStorage scLastData`); solo si no hay (primera vez, o iOS la borró) usa el snapshot
   embebido. Luego `loadLive()`: en la nube (`*.pages.dev`) pide primero `/api/edicion`, en
   local `/api/data`; el otro de respaldo. Si llega el **mismo `generatedAt`** que ya está
   pintado, no se redibuja nada: solo se enciende EN VIVO (`renderChrome`). Cada lectura viva
   se guarda en `scLastData`. Marcas para medir: `performance.getEntriesByType('mark')` →
   `hub:inicial`, `hub:vivo`, `hub:vivo-igual`. Refresca solo al volver a la app o cada 10 min
   si los datos tienen > 5 min. ↻ = `fresh` (local: extracción síncrona; nube: relee KV).
   **Fuentes**: el alfabeto latino de Archivo, Inter y JetBrains Mono se sirve desde el propio
   sitio (`/fonts/*-latin-v1.woff2`, mismos archivos de Google Fonts, OFL) con `preload`; los
   demás alfabetos siguen apuntando a fonts.gstatic.com y solo se bajan si aparecen. Caché de un
   año (`cloud/_headers`; local, `server.py`): si se cambian, **renombrar** (`-v2`).

**Interfaz viva** (`@media(hover:hover)`, tras `.settled`): la barra bajo el cursor crece y el
resto se atenúa (`.fx` en el `<svg>` + `.hot` en la marca); el centro del donut muestra etapa ·
horas · $ · % al pasar por un segmento. Presión sutil (`:active`) en botones, filas y navegación
—fuera del gate de hover para que también anime al tocar en el iPhone.

Todo respeta `prefers-reduced-motion`. Animaciones solo con transform/opacity.

## 5. Sprint de enfoque (registro de sesiones)

- **Front (`Sprint`)**: destino (etapa · escena · tipo), esquemas (Mediana, Pomodoro 25/5 con
  largo de 15 cada 4, 52/17, 90/20, Libre, Propio), ciclos foco → descanso. Solo los bloques de
  **foco** se registran. Reloj con hora real de inicio; duración **redondeada al minuto**
  (≥ 30 s sube), Fin = Inicio + duración; < 30 s no se registra. Fallo de red/servidor → queda
  pendiente en el dispositivo (reintentar/descartar), nunca se pierde.
- **Petición** `POST /api/session`: `{id, db, stageId, escena, inicio, fin, tipo, ronda}` con
  fechas ISO **con zona horaria**.
- **Validación** (`validate_session` + `target_error`, igual en `session.js`): 1 min–8 h, tipo
  Edición/Gestión, y lista blanca: `db` = una `sessionDb` del tablero, `stageId` su etapa,
  `escena` una de sus escenas. Dedup por `id`.
- **Escritura** (`create_session`, igual al registro manual): título "Sesión", Inicio, Fin,
  Tipo, Escena y **Total** → fila *Edición*/*Gestión* de la DB "Tiempo total" de la etapa.
  Se niega a escribir en una DB sin Inicio/Fin.
- **Estados** (`set_in_progress`): etapa/escena ⚪️ o vacía → 🔵 y llena su fecha de inicio vacía
  (etapa: "Del → Al", solo día; escena: "Inicio", con hora). Nunca retrocede. En la UI los estados
  se muestran como palabras agrupadas, sin emojis.
- **Nube**: con el secreto `NOTION_TOKEN` en Pages escribe directo; sin él (o si Notion falla)
  deja `edicion:pending:<id>` y `publish.py` lo crea en la siguiente corrida (≤ 30 min).
- **Cerrar al terminar** (escalera Pausa · Escena · Etapa, `run.cerrar`; vuelve a *Pausa* en cada
  bloque): al terminar, `queueClose()` guarda el cierre en `scSprintClose` con **8 s de gracia**
  (Deshacer) y lo envía `POST /api/close` `{id, db, stageId, escena, cerrar, fin}`. Lo envía el
  cliente que terminó (el otro solo si aquel desapareció, +6 s). `validate_close` + la misma lista
  blanca (`target_error`); dedup por `id`. **`set_done`**: Estado → 🟢 (nunca toca algo ya 🟢) y
  fecha de fin vacía — escena "Fin" (con hora), etapa final de "Del → Al" (si no tenía inicio,
  el mismo día). *Etapa* cierra escena + etapa. En la nube `functions/api/close.js` hace lo mismo
  o deja `edicion:pending-close:<id>` (lo aplica `drain_pending`). Hasta que el tablero se
  reconstruye, los ids cerrados (`scSprintClosed`, 30 min) se marcan terminados en el selector y
  el destino salta a la siguiente escena abierta o a la siguiente etapa de esa boda (por `orden`).

### 5.1 Ventana flotante del Mac (`mac/SprintFlotante/`)
- **Por qué nativa:** la web app del Mac es de Safari, que no tiene *Document Picture-in-Picture*
  (solo PiP de video, sin controles). La app es un `NSPanel` (`.floating`, `.nonactivatingPanel`,
  `canJoinAllSpaces` + `fullScreenAuxiliary`) con un `WKWebView` que carga
  **`http://localhost:4599/?mini=1`**: el MISMO `index.html`, nada reimplementado. Sin Dock
  (`LSUIElement`), esquema de URL **`hubsprint://`** (el botón ⤢ navega a `hubsprint://open`).
  Arrastre: franja superior de 34 px (menos los 84 px de botones a la derecha) y cualquier zona
  sin controles → `performDrag`. Para saber qué hay bajo el ratón, la vista nativa tiene su
  propio `NSTrackingArea` (`.activeAlways`: el panel casi nunca es key y WebKit no reporta el
  hover ahí) y en cada `mouseMoved` pregunta `window.__hubDragAt(x,y)` (nada de
  `button,a,input,select,…,.fcut,.fmode,.fpick,.fedit`, ni el reloj en reposo, que abre Ajustar).
  Nivel: `.floating` o, en *Opciones → En el escritorio*, `desktopIconWindow + 1` (`.stationary`).
  Puente JS → nativo: `webkit.messageHandlers.hub.postMessage('dashboard'|'close'|{k:'state',…})`
  — `close` y ⌘W **ocultan** (`orderOut`); la app sigue viva en la barra de menús.
- **Barra de menús** (`NSStatusItem`): cada 1 s lee `GET /api/sprint-state` (sin `?from=mini`:
  no es latido) y pinta el reloj con los mismos datos que la tarjeta (`scSprint.start/target`,
  `scSprintBrk.start/secs`, `scSprintPend`, `scSprintClose`). El menú se arma al abrirse
  (`menuNeedsUpdate`; la línea "Llevas…" se actualiza en vivo, timer en `.common`). Las
  acciones **no se reimplementan**: `callAsyncJavaScript` → `window.SprintCmd(c)` en la página
  mini aunque esté oculta, que primero hace `pull()` y luego ejecuta (`finish` /
  `finish-escena` / `finish-etapa` / `discard` / `endcycle` / `start` / `undo`; devuelve
  `'ok'` o por qué no). La página manda `{k:'state', dest, note, pick, etapas, etapa, escenas,
  escena, tipos, tipo, pickModo, modos, modo}` (destino propuesto, último aviso, las listas de
  `#fTarget`/`#fScene` tal cual —cada opción `{v, t, g}` con `g` = su `optgroup`— y los esquemas
  de `SCHEMES` con su `TAG`; `tipos` = los dos botones de `#fTipo`) desde `paint()` y `remember()`.
  **Etapa ▸ / Escena ▸** (nov-2026): submenús del reloj en reposo y en el descanso (`pick` =
  sin bloque y con etapas; con bloque no salen, como en la ventana: `run` fija db/escena del
  registro). Se rellenan al abrirse (`fillPick`, delegado con `identifier` "etapa"/"escena"),
  ✓ en la actual, título "Etapa: …" / "Escena: …" que se refresca si llega un `state` con el
  menú abierto. Elegir = `SprintCmd('etapa:<db>'|'escena:<id>')`: pone el valor en el
  `<select>` y dispara `change` (mismo `fillScenes`/`remember` → `scSprintDest` → sync); con
  bloque devuelve `running`. **Tipo ▸** (3-nov-2026, entre Escena y Esquema; mismas reglas que
  Etapa/Escena: reposo y descanso, nunca con bloque): `SprintCmd('tipo:<Edición|Gestión>')` =
  `setTipo` + `remember()` como tocar el botón de `#fTipo` (→ `scSprintDest.tipo` → sync); valor
  desconocido → `unknown`, con bloque `running`. El bloque en marcha conserva su `run.tipo`
  (fijado en `startBlock`), por eso no se cambia a mitad. **Esquema ▸** solo en reposo (`pickModo` = sin bloque ni
  descanso): `SprintCmd('modo:<k>')` = `setMode(k)` como el botón (reinicia el ciclo; `custom`
  usa `mode.custom` sin abrir Ajustar); con bloque `running`, en descanso `break`. Submenús
  genéricos en `main.swift` (`PICKS`, `can`, `pickers`, `fillPick`). Prueba sin pantalla:
  `swiftc -D DUMP_MENU` imprime el menú y ejecuta `HUB_PICK="modo:pomo,etapa:<db>,tipo:Gestión,…"` por
  `send` (no va en la build de `build.sh`). Al abrir el menú la app pide `SprintCmd('sync')` (oculta, la
  página no hace `pull()` sola). `scSprintDest.escena`: `''` = «Sin escena» elegida a propósito
  (se respeta en esa etapa), `null` = proponer (la recordada / última sesión / primera abierta). Oculta, la página recibe `window.__hubShown=false` (también
  como `WKUserScript` para recargas): no hace latido. En modo mini la página **nunca** pone su tono de
  meta (`chimeOnce` calla si `MINI`): el aviso lo da siempre la app (`Sounds.play("goal")`,
  visible u oculta) si la meta/descanso se cumplió hace < 15 s. Login item con `SMAppService.mainApp`
  (se registra en el primer arranque). Preferencias en `UserDefaults` (`panelVisible`,
  `onDesktop`, `showRemaining`, `hk*`, `snd.*`). `HUB_BASE=http://localhost:4611` apunta la app a otro server
  (pruebas sin tocar el sprint real).
  Frame recordado (`setFrameAutosaveName`). `./build.sh` compila con `swiftc` (sin Xcode), firma
  ad-hoc, instala en `~/Applications` y registra el esquema. `HUB_SNAPSHOT=/ruta.png` (vía
  `open --env`) guarda una captura del contenido al cargar (para pruebas).
- **Atajos globales** (`HotKey` + `registerHotKeys` en `main.swift`): Carbon
  `RegisterEventHotKey` + `InstallEventHandler(kEventHotKeyPressed)` — global y **sin permiso de
  Accesibilidad** (no es un `CGEventTap`). Dos registros con firma `'SPRT'`: id 1 = tecla
  (por defecto **⌃⌥N**), id 2 = la misma con ⇧ (**⌃⌥⇧N**), id 3 = la misma con ⌘ (**⌃⌥⌘N**,
  `togglePanel()`: `orderFrontRegardless`/`orderOut`, sin activar la app; no se registra si la
  tecla base ya lleva ⌘, posible solo con atajos grabados antes). id 1 *alterna*: manda `finish` y,
  si responde `'no-run'`, `start` (así decide con el estado recién sincronizado por `pull()`,
  no con el último sondeo); id 2 manda `discard`. Mismo camino que el menú (`send(cmd)` →
  `SprintCmd`). Feedback: `Sounds.play(acción)` + el icono de la barra cambia 1,5 s a
  `play`/`checkmark`/`xmark.circle` (`flash` en `render()`); si no aplica, `Sounds.play("error")`.
  **id 4 = Edición ↔ Gestión (⌃⌥B, 6-nov-2026)**: mismos modificadores que la tecla base, tecla B
  (`HotKey.tipoKey`; si la base ya es B, N). `toggleTipo()` → `SprintCmd('tipo-toggle')` (index.html,
  junto a `tipo:`): rota `#fTipo` con `setTipo` + `remember()` + `paint()`; devuelve `'ok:<tipo>'`,
  `'running'` con bloque en marcha (misma regla que Tipo ▸: el bloque conserva su `run.tipo`) o
  `'unknown'`. Aviso: `flash` ahora lleva texto (el reloj muestra 2 s «Edición»/«Gestión» con icono
  `scissors`/`folder`) y suena la acción `tipo` (Pop; 1 toque = Edición, 2 = Gestión); en error,
  `Sounds.play("error")`. El menú añade bajo *Tipo ▸* «Cambiar a «…»» con el atajo como `keyEquivalent`.
  Probar sin pantalla: `HUB_PICK="hotkey:4,…"` en la build `-D DUMP_MENU` ejecuta `hotKey(4)` e
  imprime el título de la barra; `HUB_LOG=1` registra el resultado de cada `RegisterEventHotKey`.
- **Sonidos** (`enum Sounds` + `soundsMenu()` en `main.swift`, *Opciones → Sonidos*): acciones
  `start` (de serie Tink), `finish` (Hero), `discard` (Funk), `goal` (Glass, meta/descanso), `tipo` (Pop, ⌃⌥B) y
  `error` (aviso del sistema; también cuando falla una acción del menú). Guardado en
  `UserDefaults` `snd.<acción>`: nombre de un sonido (`NSSound(named:)`, lista de
  `/System/Library/Sounds` + `~/Library/Sounds`), `"·sistema"` = `NSSound.beep()` o `""` =
  ninguno; sin clave = el de serie (*Restablecer* borra las claves). Vista previa: los
  submenús tienen de delegado `SoundPreview` (`menu(_:willHighlight:)` suena al pasar).
  Hasta nov-2026 iniciar era Pop; Jordi lo cambió a Tink. El grabador de atajos sigue usando
  `NSSound.beep()` para rechazar una tecla.
  Configurable en *Opciones → Atajo de teclado* (presets N/B/P/J/K con ⌃⌥, *Grabar otro…* con
  un `NSAlert` + monitor local: exige ⌃ y/o ⌥, sin ⇧ ni ⌘, que se reservan; *Sin atajo*).
  `UserDefaults`: `hkCode` (keyCode virtual), `hkMods` (`NSEvent.ModifierFlags`), `hkChar`,
  `hkOff`. Los ítems Iniciar/Terminar/Descartar y Mostrar/Ocultar ventana muestran el atajo como
  `keyEquivalent`. Conflictos revisados (oct-2026): Final Cut usa ⌃⌥ con 0–6, C D E F L M R S T
  V y flechas, y ⌃⌥⌘ con dígitos, C, O, S, M, flechas (no N/B/P/J/K) (set JORDISSAN ≈ el de serie); Premiere (perfil de Jordi) y macOS no usan ⌃⌥;
  ⌃⌥ es el prefijo de VoiceOver (solo si está activo). `HUB_LOG=1` (vía `open --env`) registra
  cada atajo en stderr. **Probar:** bundle de prueba con otro bundle id **y otro
  `CFBundleExecutable`** (System Events referencia el proceso por nombre y si no abre el menú
  de la app real), `defaults write <id-prueba> loginSetup -bool true` antes del primer arranque
  (si no se apunta como login item), y disparar con `osascript … key code 45 using {control
  down, option down}` con Finder al frente.
- **Siri / Atajos (URLs de orden):** `application(_:open:)` atiende `hubsprint://start`,
  `hubsprint://finish` y `hubsprint://toggle` con `run(cmd, tries: 30)` — el mismo camino y
  feedback que el atajo (`hotKey` también llama a `run`): `start` solo empieza (`'running'` →
  pitido), `finish` solo termina, `toggle` = ⌃⌥N. Cualquier otro host (`open`) muestra la ventana.
  No trae la ventana al frente. **En frío** macOS entrega la URL *antes* de
  `applicationDidFinishLaunching` (sin `web` ni `panel`; antes eso tumbaba la app): se guarda en
  `earlyURLs` y se atiende al final del arranque; mientras la página carga, `run` reintenta cada
  0,5 s si `SprintCmd` responde `not-ready`/`error`/`busy` (~15 s). Siri = dos Atajos de la app
  Atajos ("Iniciamos", "Terminamos" — "sprint" Siri lo entendía mal y "Nueva sesión" lo capturaba el intent nativo de calendario, que pregunta la fecha; el nombre debe no parecerse a órdenes de serie: acciones *URL* → *Abrir URL*), generados y
  firmados (`shortcuts sign --mode anyone`) por `mac/Siri/make-shortcuts.py`; Jordi los importa
  con doble clic. Se descartó App Intents (necesita el procesado de metadatos de Xcode; la app se
  compila con `swiftc` a pelo) y un endpoint del server (el server no sabe arrancar el sprint:
  la lógica vive en la página). **iPhone no:** en `*.pages.dev` `SYNC_ON` es falso (no hay
  `/api/sprint-state` en la nube), el sprint vive en el `localStorage` de la PWA, e iOS no deja
  que un Atajo abra la PWA (abriría Safari, con otro `localStorage`). **Probar las URLs:** el
  bundle de prueba necesita también **otro esquema** (`hubsprinttest`) y vivir en
  `~/Applications` (Launch Services ignora las apps en carpetas temporales); quitarlo después con
  `lsregister -u` + borrar.
- **`build.sh` fija `-target <arch>-apple-macos13.0`:** sin él `swiftc` apunta a la versión del
  SDK (Command Line Tools de macOS 28 en un Mac con 27.2) y la app no abre (`-10825`).
- **Modo mini (`?mini=1`)**: el `<head>` pone `html.mini` antes de pintar; la tarjeta `#focus`
  se mueve a `<body>` (antes del reveal) y el CSS oculta todo lo demás; `bootRender` solo hace
  `Sprint.update(M)` (sin gráficas). Cuadrícula de 3 zonas (A destino/esquema · B reloj ·
  C acción): vertical `a/b/c`; apaisada (≥ 5:4 y ≥ 460 px) `a b / a c`; franja (≤ 230 px de alto,
  ≥ 420 px) `b c`, y ≥ 640 px `a b c`. En vertical, por altura: < 500 sin `.why`, < 420 sin
  esquemas, < 300 sin destino, ≤ 230 (angosta) solo reloj + escalera + botón. Esquemas en
  cuadrícula 3×2 (6 en línea desde 430 px). Tamaño mínimo de la ventana: 240×170.
- **Sincronía** (`GET/POST /api/sprint-state`, solo local; `.sprint-state.json`): cada cliente
  sigue en su `localStorage`; `save()` de las claves del sprint marca `scSprintRev` = ms y sube
  todo (debounce 120 ms). Cada 1,5 s a la vista (y al volver/enfocar) baja la copia común: si
  su `rev` es mayor, la escribe en `localStorage` y `Sprint.reload()` relee variables y repinta;
  si es menor, sube la suya (server recién arrancado). Gana el cambio más reciente. Un estado
  previo a la sincronía cuenta como `rev` 1. La ventana pregunta con `?from=mini` (latido) →
  `miniOpen` → clase `.floating` en la tarjeta del dashboard. El aviso sonoro es **por
  cliente** (`scSprintChimed`, no se sincroniza) y el dashboard calla si la ventana está
  abierta; en la ventana suena la app nativa (*Opciones → Sonidos*), no el tono de la página. Doble "Terminar" del mismo bloque no duplica: `/api/session` deduplica por `id`.
  En la nube (`*.pages.dev`) no hay sincronía ni botón.

## 6. Claves de estado

| Dónde | Clave | Contenido |
|---|---|---|
| KV | `edicion:data` | payload completo (§2) |
| KV | `edicion:summary` | resumen de widgets |
| KV | `edicion:archive` | archivo histórico (estado persistente de la nube) |
| KV | `edicion:pending:<id>` | sprint en cola (sin `NOTION_TOKEN` en Pages) |
| KV | `edicion:done:<id>` | resultado de un sprint ya registrado (dedup, 24 h) |
| KV | `edicion:pending-close:<id>` · `edicion:closed:<id>` | cierre de escena/etapa en cola · ya aplicado (dedup, 24 h) |
| Mac | `.cache.json` · `.archive.json` | caché local · archivo histórico local |
| Mac | `.sprint-state.json` | sprint compartido dashboard ⇄ ventana flotante (`{rev, data}`) |
| Navegador | `scTheme` | tema claro/oscuro |
| Navegador | `scLastData` | última lectura viva (payload completo, ~90 KB) para pintar al abrir |
| Navegador | `scSprint` · `scSprintBrk` · `scSprintCyc` | bloque en curso · descanso · ciclo |
| Navegador | `scSprintMode` · `scSprintDest` · `scSprintPend` | esquema · último destino · registro pendiente |
| Navegador | `scSprintClose` · `scSprintClosed` | cierre en espera (8 s para deshacer) · ids cerrados aún no reflejados en el tablero |
| Navegador | `scSprintRev` · `scSprintChimed` | versión del sprint para la sincronía · último bloque que ya sonó (por cliente) |

## 7. Plantilla de Notion que espera

- DB raíz **Trabajo** (`TRABAJO_DB_ID`) con `Tipo = Boda`, `Status`, `Total`, fecha del proyecto.
- En cada boda, sub-DB **"Tracking de Edición"**: etapas con `Etapa` (título), `Fase`
  (PREP/TEAS/DCT/HL/SF/CMB), `Estado` (⚪️/🔵/🟢), `Orden` (admite decimales), `Del → Al`.
- En cada etapa: DB de **escenas** (título "Escena", `Estado (Select)` + fórmula `Estado`,
  `Orden`, `Inicio`, `Fin`), DB **Sesiones** (`Sesión`, `Inicio`, `Fin`, `Tipo`, `Escena`,
  `Total`, `Ronda` en Cambios) y DB **Tiempo total** (filas *Edición* y *Gestión*).
- Teaser = la boda tiene etapas TEAS. 2 días = una escena "Día 1…".

## 8. Mantenimiento

1. Edita **local**: `index.html` y/o `server.py`. Si tocaste `server.py`:
   `launchctl kickstart -k gui/$(id -u)/com.jordi.hub-edicion`.
2. Verifica con datos reales en <http://localhost:4599> (en Claude Code: configuración
   `hub-vivo` de `.claude/launch.json`).
3. `./sync-cloud.sh` → revisa el diff → `./sync-cloud.sh --publicar "mensaje"`
   (commit + push; Pages despliega en 1-2 min; si cambió `server.py` republica los datos).
4. `publish.py`, `functions/` y el workflow se editan directamente en `cloud/`.
5. Actualiza la documentación en la misma pasada si cambió comportamiento o datos.
6. Para ver la versión nueva en el iPhone: **matar la PWA** desde el app switcher y reabrir.

Datos a mano: `gh workflow run "Publicar dashboard" -R jordissan/hub-edicion`.
`sync-cloud.sh` también copia `fonts/` (las fuentes) a `cloud/fonts/`.

## 9. Trampas conocidas

- **"Tiempo total"** titula su columna "Sesión": nunca la trates como DB de sesiones (§3).
- **Estado de escena** es una fórmula → `p_select` lee fórmulas de texto.
- **iOS / PWA**: `backdrop-filter` + `transform` animado necesita `will-change:transform`; `:active`
  requiere un listener `touchstart` (hay uno global); el hover del tap se queda pegado (hay
  limpieza); campos de < 16 px hacen zoom al enfocar; la caché de la PWA solo se va matando la app.
- **Panel de preview de Claude Code**: si está oculto no corre frames (IntersectionObserver,
  rAF y timers se frenan) — una captura fuerza un frame. Las transiciones no avanzan durante un eval.
- **Barra de título de la app del Mac (Safari, macOS 26+)**: la franja de ~32 pt de arriba
  (semáforos) la dibuja macOS: es translúcida, el contenido pasa por debajo y la oscurece
  ~80 % con gris `#101012`. No se controla desde la página (ni `theme-color` ni safe-area la
  cambian); los `position:fixed/sticky` con `top:0` quedan justo debajo. Por eso la cabecera
  fija «Tú / Hoy» (≥1024 px) usa el mismo vidrio en tema oscuro: tokens `--top-bg`
  (`--bg` al 82 %; primero fue `#101012`, pero Safari a veces pinta la franja sólida con el negro de
  `--bg`) y `--top-fx` (`blur(24px)`) → las dos franjas se leen como una sola
  (3-nov-2026). El tema claro conserva el vidrio anterior (62 % de `--bg`).
- **Snapshot embebido**: refrescarlo por concatenación de texto, nunca con `re.sub` (se come
  las barras invertidas del JSON y rompe el script).
- **Privacidad — el repo de la nube es público**: el código no tiene tokens, pero `index.html`
  lleva embebido `SNAPSHOT_DATA` con datos reales (nombres de parejas, precios, estudio,
  sesiones), visibles en GitHub aunque el sitio esté detrás de Access. Opciones: repo privado
  (Actions deja de ser gratis ilimitado: con el aviso cada 15 min serían hasta 96 corridas/día
  × 2 min ≈ 5 800 min/mes, muy por encima de los ~2 000 del plan Free; habría que quitar el aviso
  del Mac y dejar el cron cada hora) o un snapshot anonimizado en la copia de la nube.

## 10. Refresco de la nube y rendimiento de carga (nov-2026)

**Cada cuánto se actualiza la nube.** El cron `*/30` de `publish.yml` **no se cumple**: GitHub
retrasa o descarta los `schedule` en horas de carga ("some queued jobs may be dropped", docs de
GitHub). Medido sep-nov 2026: ~5 corridas/día, mediana **~4 h 15 min** entre corridas (máx. 10 h).
Un `workflow_dispatch` sí arranca al momento, así que el **server local lo pide cada 15 min**
(`start_cloud_ping` en `server.py`, con el `gh` ya autenticado del Mac; `/Users/jordi/bin/gh`):
- si la última corrida (de cualquier tipo) empezó hace < 12 min, no pide otra → máx. ~4/h;
- solo en el server del puerto 4599 (no en Actions, que no llama a `main()`, ni en copias de
  prueba con otro `DASHBOARD_PORT`); se apaga con `HUB_CLOUD_PING=0`;
- log en `/tmp/hub-edicion.err` (`[nube] HH:MM · pedida` / `error: …`);
- con el Mac dormido o sin red no pasa nada: el cron de GitHub queda de respaldo.

**Consumo (peor caso: 96 corridas/día) frente a los límites gratuitos:**

| Recurso | Por corrida | Al día (96) | Límite gratuito |
|---|---|---|---|
| GitHub Actions | ~1 min 45 s (se factura redondeado a 2 min) | ~190 min | repo **público**: runners estándar gratis, sin tope ([docs](https://docs.github.com/en/billing/concepts/product-billing/github-actions)) |
| Notion API | ~250 peticiones en ~100 s (2,5/s por el throttle) | ~24 000 | 3 peticiones/s de media por integración, sin cuota diaria ([docs](https://developers.notion.com/reference/request-limits)) |
| Cloudflare KV escrituras | 3 (`data`, `summary`, `archive`) | 288 | 1 000/día ([docs](https://developers.cloudflare.com/kv/platform/limits/)) |
| Cloudflare KV lecturas | ~2 + cola | ~200 + aperturas | 100 000/día |
| Pages Functions | — | aperturas de la PWA | cuentan en las 100 000 peticiones/día del plan Free de Workers |

No se puede mover la extracción a un Worker de Cloudflare gratis: admite 50 sub-peticiones por
invocación y una extracción hace ~250. Alternativa si algún día se quiere refresco con la Mac
apagada: un Worker con Cron Trigger (5 por cuenta en Free) que haga el `workflow_dispatch` con un
token de GitHub de solo "Actions: write".

**Carga (medido en el Mac, servidor de prueba con la caché copiada, 5 aperturas c/u):**

| | Antes | Después |
|---|---|---|
| Primer pintado | ~83 ms, con los datos de **julio** (snapshot) | ~90 ms, con la **última lectura real** |
| Datos reales en pantalla | ~240 ms (segundo dibujo completo) | ~90 ms |
| EN VIVO confirmado | ~240 ms | ~110 ms (sin redibujar si no cambió) |
| Fuentes | CSS de fonts.googleapis.com bloqueando el pintado (142 ms en frío) + fonts.gstatic.com | mismo origen, precargadas, sin conexiones extra |

En el iPhone el ahorro absoluto es mayor (CPU más lenta → cada dibujo completo cuesta más; en
datos móviles, cada conexión nueva a Google son 2-3 idas y vueltas). Ya estaban bien y no se
tocaron: la nube no consulta Notion al abrir (lee KV precalculado), Cloudflare ya comprime HTML
y JSON, y paralelizar Notion no acelera nada (manda el límite de 3/s). Pendiente opcional: un
service worker (abrir sin red), con el coste de que cada versión nueva se vea a la segunda apertura.

