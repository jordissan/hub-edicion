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
   server.py · launchd · :4599                     GitHub Actions cada 30 min
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
                     snapshot embebido → loadLive() → deriveModel() → render*
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
  "weddings": [{                          // tablero: activas + finalizadas editadas en ≤45 días
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
| `discover_wedding_pages()` | Páginas `Tipo = Boda` de la DB "Trabajo". Deja fuera las **finalizadas sin cambios en 45 días** (`RECENT_DONE_DAYS`; "finalizada" = `DONE_STATUSES`, comparado en Python para que renombrar la opción en Notion no rompa la consulta). Si la consulta falla → `FALLBACK_WEDDING_PAGES` y `degraded: true`. |
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
   de geometría al cruzar 640 px (hoy: Horas por día). La **Carrera** (`renderRace`) se dibuja al
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
4. **`Sprint`** — tarjeta de enfoque (§5).
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
     - Los halos de los SVG son filtros del sprite (`fxGlow` barras señaladas `.glw`, `fxGlowL`
       la curva, `fxGlowD` el donut). Las barras usan degradados compartidos (`gfill()` →
       `#gSun/#gVio/#gNar`).
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
7. **Boot** — snapshot → `loadLive()`: en la nube (`*.pages.dev`) pide primero `/api/edicion`, en
   local `/api/data`; el otro de respaldo. Refresca solo al volver a la app o cada 10 min si los
   datos tienen > 5 min. ↻ = `fresh` (local: extracción síncrona; nube: relee KV).

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
  `'ok'` o por qué no). La página manda `{k:'state', dest, note}` (destino propuesto y último
  aviso) para el menú en reposo. Oculta, la página recibe `window.__hubShown=false` (también
  como `WKUserScript` para recargas): no hace latido ni suena, y el aviso lo da `NSSound`
  ("Glass") si la meta/descanso se cumplió hace < 15 s. Login item con `SMAppService.mainApp`
  (se registra en el primer arranque). Preferencias en `UserDefaults` (`panelVisible`,
  `onDesktop`, `showRemaining`). `HUB_BASE=http://localhost:4611` apunta la app a otro server
  (pruebas sin tocar el sprint real).
  Frame recordado (`setFrameAutosaveName`). `./build.sh` compila con `swiftc` (sin Xcode), firma
  ad-hoc, instala en `~/Applications` y registra el esquema. `HUB_SNAPSHOT=/ruta.png` (vía
  `open --env`) guarda una captura del contenido al cargar (para pruebas).
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
  abierta. Doble "Terminar" del mismo bloque no duplica: `/api/session` deduplica por `id`.
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

## 9. Trampas conocidas

- **"Tiempo total"** titula su columna "Sesión": nunca la trates como DB de sesiones (§3).
- **Estado de escena** es una fórmula → `p_select` lee fórmulas de texto.
- **iOS / PWA**: `backdrop-filter` + `transform` animado necesita `will-change:transform`; `:active`
  requiere un listener `touchstart` (hay uno global); el hover del tap se queda pegado (hay
  limpieza); campos de < 16 px hacen zoom al enfocar; la caché de la PWA solo se va matando la app.
- **Panel de preview de Claude Code**: si está oculto no corre frames (IntersectionObserver,
  rAF y timers se frenan) — una captura fuerza un frame. Las transiciones no avanzan durante un eval.
- **Snapshot embebido**: refrescarlo por concatenación de texto, nunca con `re.sub` (se come
  las barras invertidas del JSON y rompe el script).
- **Privacidad — el repo de la nube es público**: el código no tiene tokens, pero `index.html`
  lleva embebido `SNAPSHOT_DATA` con datos reales (nombres de parejas, precios, estudio,
  sesiones), visibles en GitHub aunque el sitio esté detrás de Access. Opciones: repo privado
  (Actions deja de ser gratis ilimitado: ~48 corridas/día rebasan los 2 000 min/mes; habría que
  bajar el cron a cada hora) o un snapshot anonimizado en la copia de la nube.
