# Hub de Edición — nube (DESPLEGADO Y OPERATIVO)

Dashboard de métricas de edición de bodas, en la nube. Accesible desde cualquier lugar, con la Mac
apagada, detrás de login, **100% gratis**.

- **URL:** https://hub-edicion.pages.dev
- **Login:** Cloudflare Access — **One-time PIN por correo** (jor.jorwww@gmail.com), sesión 1 mes.
- **Repo:** `github.com/jordissan/hub-edicion` (**público**). Nunca tokens. El snapshot embebido
  (`SNAPSHOT_DATA`) son **datos de ejemplo** desde el 9-nov-2026 (lo genera `snapshot-demo.py` en la
  carpeta raíz; `sync-cloud.sh` no copia uno real). El historial de git anterior sí conserva el de julio
  — ver "Privacidad" en `docs/arquitectura.md` §9.

## Arquitectura

```
GitHub Actions (workflow_dispatch del Mac tras cada sesión y cada 15 min + cron */30 de respaldo · TZ America/Mexico_City)
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
  functions/api/close     → POST: al terminar un sprint, cierra su escena/etapa en Notion (🟢 + fecha fin)
                            (directo con NOTION_TOKEN; si no, cola KV edicion:pending-close:<id>)
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
- `functions/api/close.js` — `POST /api/close`: cierra la escena (y la etapa) del sprint que terminó
  (misma lista blanca; directo con `NOTION_TOKEN`, si no cola `edicion:pending-close:<id>`).
- `functions/embed/index.js` · `functions/embed/data.js` · `functions/api/embed-link.js` — tarjeta para
  Notion (`/embed`): la página (= `index.html` en modo embebido), los datos de UNA boda recortados de
  `edicion:data` (exige la clave `k`) y la lista de enlaces (detrás de Access). Ver «Tarjeta para Notion».
- `embed/plantilla.html` — marcador estático para la **plantilla de boda** de Notion
  (`/embed/plantilla?t=donut|cinta|etapas`): ocupa el recuadro del embed y pide reemplazarlo por el enlace
  de la boda (botón `</>`). Sin datos ni clave; mismo tema que las tarjetas y sin scroll propio.
- `docs/arquitectura.md` — referencia técnica completa (la copia `sync-cloud.sh`).
- `.github/workflows/publish.yml` — cron + `workflow_dispatch`. Secretos: `NOTION_TOKEN`, `CF_API_TOKEN`,
  `CF_ACCOUNT_ID`, `CF_KV_NAMESPACE_ID`. Lleva `env: TZ: America/Mexico_City` (el runner es UTC).
- `index.html`, `manifest.json`, `icon-*.png` — el sitio estático.
- `fonts/*-latin-v1.woff2` — Archivo, Inter y JetBrains Mono (alfabeto latino, mismos archivos de Google Fonts,
  OFL), precargados desde `index.html`. Los copia `sync-cloud.sh`.
- `_headers` — caché de un año para `/fonts/*` (si cambian las fuentes, renombrar a `-v2`).

## Cómo se actualizan los datos
- **Cada 15 min con la Mac encendida:** el `server.py` local (launchd) corre `gh workflow run publish.yml`
  si la última corrida empezó hace más de 12 min. Log: `/tmp/hub-edicion.err` (`[nube] …`). Apagar con
  `HUB_CLOUD_PING=0`.
- **Respaldo (Mac apagada):** el cron `*/30` de Actions. GitHub **no lo cumple**: retrasa o descarta los
  `schedule` en horas de carga; medido sep-nov 2026, ~5 corridas/día (mediana ~4 h entre corridas).
  GitHub pausa crons si el repo no tiene actividad en 60 días.
- **Consumo** (peor caso 96 corridas/día, todo gratis): Actions ~190 min/día (repo público = sin tope);
  Notion ~250 peticiones por corrida a 2,5/s (límite 3/s, sin cuota diaria); KV 288 escrituras/día de 1 000.
  Tabla y fuentes en `docs/arquitectura.md` §10.
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
- **Cloudflare Pages**: `EMBED_SECRET` (texto largo al azar) — firma las claves de la tarjeta para Notion.
  Sin ella `/embed/data` responde 503. Cambiarla invalida todos los enlaces pegados.
- **Widgets**: Service Token de Cloudflare Access (Client ID + Secret) pegado en el script de Scriptable.

## Ajustes visuales rápidos
Se hacen en `~/HubEdicion/index.html` (capa "IDENTIDAD A") y se portan con `sync-cloud.sh`:
- **`--glow`**: intensidad de los halos (0,72 oscuro · 0,3 claro).
- **`--grain-k`**: intensidad del grano de fondo y materiales, ambos temas (0,5 desde el 30-oct = mitad).
- **`--top-bg` / `--top-fx`** (cabecera fija «Tú / Hoy», ≥1024 px): en oscuro, `--bg` al 82 % + `blur(24px)` para igualar la barra de título de macOS en la app del Mac, que unas veces es translúcida (oscurece ~80 %) y otras Safari la pinta sólida con el negro de `--bg` → arriba se ve una sola franja homogénea (3-nov). El tema claro mantiene el 62 % de `--bg`.
- **Tabbar móvil** (`.dock`/`.tabbar`): solo iconos en celdas de 42 px, alto 52 px (1-nov); los textos siguen en el HTML, ocultos, para lectores de pantalla.
- **Intensidad diaria** (`renderHeat`): el ancho visible del heatmap se fija a columnas enteras (22 px por semana) y se centra; `scroll-snap` por columna (1-nov).
- **`--h1…--h5`** (colores del heatmap): en claro, de lima pálido a oliva-lima vivo, `#dae7b7 → #799100` (OKLCH L .90→.62, C .07→.17), con halo en `.s5` escalado por `--glow`. Antes terminaba casi en negro (`#334305`) (3-nov).
- **`--bar-fade`**: opacidad de la base de las barras con degradado (`#gSun/#gVio/#gNar`): 0,42 en oscuro y 0,61 en claro, o sea, velo −33 % (3-nov).
- **`--f-t`** (prosa): fuente de frases, descripciones, notas, leyendas y pie — la mono del sistema, como el widget. Se cambia en la capa "PROSA EN MONO" al final del CSS.

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

## Sprint desde la barra de menús del Mac (nov-2026)
- El reloj de la barra de menús (app `mac/SprintFlotante/`, solo local) tiene **Etapa ▸**, **Escena ▸**, **Tipo ▸**
  (Edición/Gestión) y **Esquema ▸** para elegir destino, tipo y esquema del próximo bloque. En la nube no cambia nada (no hay sincronía del sprint en
  `pages.dev`); el `index.html` solo gana las órdenes `etapa:`/`escena:`/`tipo:`/`modo:`/`tipo-toggle` (atajo ⌃⌥B, Edición ↔ Gestión) de `SprintCmd` (modo mini) y
  respeta «Sin escena» elegida a propósito. Detalle en `docs/arquitectura.md` (Barra de menús).

## Sprint sin internet (10-nov-2026, solo Mac)
- `server.py` local guarda cada sesión y cierre en `.outbox.json` antes de escribir en Notion y lo sube
  solo y en orden al volver la red (la app del reloj avisa con NWPathMonitor; si no, reintento ≤ 2 min).
  Nuevas rutas locales `GET /api/outbox` y `POST /api/outbox/flush`; `/api/sprint-state` lleva `outbox`.
  `create_session`/`close_targets` aceptan un `step` opcional (reanudar sin duplicar); sin él
  (`publish.py`) funcionan igual. `functions/` y el payload no cambian. Detalle: `docs/arquitectura.md` §5.2.

## Carga rápida (nov-2026)
- La PWA pinta al abrir la **última lectura guardada** en el iPhone (`localStorage scLastData`) en vez del
  snapshot de julio, y si `/api/edicion` trae el mismo `generatedAt` no redibuja (solo enciende EN VIVO).
- Fuentes desde el propio sitio, sin la hoja de Google que bloqueaba el primer pintado.
- **(9-nov-2026)** Al volver a primer plano refresca siempre. El sello dice GUARDADO · hora (punto naranja)
  si lo pintado no es una lectura recién llegada. Si la sesión de Access caducó, la página se recarga sola
  (antes se quedaba con datos viejos en silencio). El Mac pide una corrida en cuanto registras una sesión
  (`cloud_ping_soon`). Detalle en `docs/arquitectura.md` (Boot y §10).
- Medido en el Mac: datos reales en pantalla de ~240 ms a ~90 ms. Detalle en `docs/arquitectura.md` §10.


## Reacomodo de tarjetas + sprint compacto (7-nov-2026)
- **Cuadrícula de 12 columnas** (capa «REACOMODO DE TARJETAS» al final del `<style>`): una fila solo junta
  tarjetas de altura natural parecida, nunca se estira una tarjeta para rellenar. Hoy = sprint (1/3) + seis
  cifras 3×2 (2/3), luego *Horas por día* (3/4) + *Plan de hoy* (1/4). El *Insight* va en *Tus sesiones*,
  bajo *Duración*. *Horas por día* se dibuja a escala real (alto fijo).
- **Sprint compacto**: vidrio oscuro como el del sidebar; esquema, destino y «cerrar al terminar» en
  ventanas emergentes. En la nube se comporta igual (no depende de `/api`). La ventana flotante del Mac no cambia.
- Tras publicar, en el iPhone hay que **matar y reabrir la PWA** para saltar su caché.
- Detalle en `docs/arquitectura.md` (capa de render y `Sprint`).

## Trazo único de las gráficas de línea + auditoría (9-nov-2026)
- **Trazo**: Carrera, Historial (Progreso y Carrera de todas) y el salto de Tarifa comparten curva
  (cúbica monótona, «con ritmo»), grosores (`--ln-1/2/3`), puntos en anillo/lleno (`mark()`) y guías
  punteadas (`.gd`). Detalle en `docs/arquitectura.md` §4.
- **Pulidos**: anillos sobre las curvas al pasar el cursor (Carrera), la guía de meta se abre bajo la
  cifra que la cruza (Horas por día), eje de la Carrera sin rayita suelta ni marca pegada a la
  pastilla, nombres completos en Progreso en el iPhone.
- **`server.py`**: escrituras atómicas de la caché y el archivo, registro de sesión sin duplicados
  (`_session_lock`), `SPRINT_KEYS` con el cierre de escena/etapa, y el server local solo en `127.0.0.1`.
  Nada de esto cambia lo que publica `publish.py`.

## Auditoría de diseño: legibilidad y móvil (10-nov-2026)
- Solo presentación (CSS y funciones `render*`); `publish.py`, `functions/` y el payload no cambian.
- Letra mínima de 11 px, `--dim` con 4,5:1, gráficas de barras a tamaño real en el iPhone, lima =
  mejora / violeta = empeora por signo (`tone()`), `--sun-data` para datos en tema claro, lista única
  de etapas en Proyectos, áreas táctiles de 44 px y cabecera fija en móvil. Detalle en
  `docs/arquitectura.md` §4 («Auditoría de diseño»).
- Tras publicar, en el iPhone hay que **matar y reabrir la PWA** para saltar su caché.

## Selectores segmentados (10-nov-2026)
- Solo presentación (CSS «SELECTORES SEGMENTADOS» + `renderRitmoMode` y `seg()` en `renderRaceMode`).
- `.rmode`: píldora de 28 px, área táctil de 44 px por `::after` (salvo `#progMet`, que desliza y la
  recorta), siempre en el renglón del título. Con container queries (`rcard` <340 px, `rsec` <360 px)
  se abrevia: `.rf` texto completo, `.rs` corto (HIST.), `.rk` la fase una vez (TEASER [SIN|CON]);
  «Duración de sesiones» → «Duración»; `.u` de Boda con boda baja bajo el título (<420 px).

## Otros proyectos (no bodas) — 12-nov-2026
- `server.py` añade `projects` al payload (`Tipo = Proyecto` en Trabajo; ver docs/arquitectura.md §2-3).
  Viajan a KV con el resto; `functions/embed/data.js` no los toca.
- `functions/api/session.js` y `close.js` aceptan la DB Sesiones de un proyecto (sin etapa ni escenas);
  `session.js` liga el Total solo si su DB apunta de vuelta a esa tabla (`totalDbOk`).
- `snapshot-demo.py` también anonimiza `projects` (repo público).

## Tarjetas para Notion (/embed) — publicada 10-nov-2026 (7f6bb7d); 9 tarjetas desde el 11-nov
- Tarjetas (`EMB_CARDS` en index.html, `&embed=<tarjeta>`): de una boda `donut` (por defecto), `etapas`,
  `cinta`; del tablero entero `dia7`, `intensidad`, `tarifa-hora`, `tarifa-escena`, `tarifa-eficiencia`,
  `tarifa-salto`. Las del tablero usan `boda=todo` (clave propia; `/embed/data?boda=todo` devuelve el
  payload completo).
Pegar la dona **Horas y $ por etapa** de una boda en su página de Notion (`/embed`), viva.
- `GET /embed?boda=<boda>&k=<clave>[&tema=claro|auto]` → `functions/embed/index.js` sirve el mismo
  `index.html`; la página ve la ruta `/embed` y entra en **modo embebido** (`html.embed`): solo
  `#donutCard`, a tamaño completo del iframe, fondo sólido `--bg` (el material de la tarjeta es
  translúcido), sin sprint, sin `scLastData` (guarda `scEmbed:<boda>`), nunca el snapshot de ejemplo.
- `GET /embed/data?boda=&k=` → `functions/embed/data.js`: valida `k = HMAC-SHA256(EMBED_SECRET,
  "embed:"+boda)` (20 hex) y devuelve `edicion:data` recortado a esa boda (tablero + archivo, ~45 KB).
  403 clave mala · 404 boda no encontrada · 503 sin `EMBED_SECRET`. **No hay almacenamiento por boda.**
- `GET /api/embed-link[?boda=]` → enlaces listos para copiar (detrás de Access, como todo `/api`). Lo usa el
  botón **`</>`** de la tarjeta (dashboard): copia el enlace de la boda abierta (ClipboardItem con promesa
  para Safari; si falla, `prompt` con el enlace). En el Mac lo responde `server.py` (mismo HMAC) leyendo
  `~/HubEdicion/.embed-secret` (permisos 600, fuera de git; MISMO valor que `EMBED_SECRET` de Pages).
- Dentro de Notion la tarjeta se funde con la página (11-nov): `--embbg` #191919 / #FFFFFF en html, body y
  tarjeta; sin borde, radio, sombra, grano (`::before`) ni halo (`.dsegs` sin filtro). `color-scheme` igual al
  de Notion (dark/light): si no coincide, el navegador pinta opaco el lienzo del iframe y asoman esquinas.
- Interruptor general `?embed=tema` (`#temaCard`, sin datos ni clave). **Auto** (12-nov) borra `scEmbedTheme` y
  los de cada tarjeta: entonces siguen `prefers-color-scheme` en vivo (`SYS_LIGHT` change), para el atajo «Modo
  oscuro» del iPhone (`docs/atajo-modo-oscuro.md` en la raíz). Claro/Oscuro: guarda `scEmbedTheme`, borra los
  `scEmbedTheme:<tarjeta>:<boda>` y escribe `scEmbedThemeAt`; las tarjetas abiertas lo oyen (evento `storage`,
  mismo sitio dentro de Notion) y cambian al momento. El sol/luna de cada tarjeta guarda solo el suyo.
- Tema de la tarjeta embebida: botón sol/luna dentro de ella → `localStorage scEmbedTheme` (manda sobre
  `&tema=claro|oscuro` de la URL; sin nada, el del sistema).
- **Scroll (11-nov):** dentro de Notion la rueda / los dos dedos sobre la tarjeta deben mover la página. Antes la
  tarjeta (`.embtarget`, fija a todo el iframe) era `overflow:auto` + `overscroll-behavior:contain` y se quedaba
  con el gesto (incluso sin nada que desplazar). Ahora `overflow:clip` (ni es contenedor de scroll), sin
  `overscroll-behavior`, `.heatwrap` `overflow:hidden` (sigue en la última semana con `scrollLeft`) y, si no
  cabe, `.embcut` (máscara que desvanece los 36 px de abajo; `embCut()` en `renderEmbed`). Regla: **nada
  dentro del modo embebido puede ser desplazable** (el navegador solo pasa el gesto a Notion si nada lo es).
- **Activado (10-nov):** (1) secreto `EMBED_SECRET` en Pages (Settings → Variables and Secrets).
  (2) Zero Trust → Access → Applications → app *self-hosted* `hub-embed`, destinos `hub-edicion.pages.dev`
  con rutas `embed` y `fonts`, política **Bypass · Everyone** (dentro del iframe de Notion el login de
  Access no funciona: la cookie es de terceros). **Trampa:** el desplegable Domain ya trae
  `hub-edicion.pages.dev`; el campo Subdomain va VACÍO (si no, queda `hub-edicion.hub-edicion.pages.dev`).
  Comprobar: `curl -s -o /dev/null -w '%{http_code}' https://hub-edicion.pages.dev/fonts/inter-latin-v1.woff2` → 200
  (y `/` → 302). (3) Enlaces: abrir `/api/embed-link` (con el PIN) y pegar el de la boda con `/embed` en Notion.
- `/manifest.json` e `/icon-*.png` siguen tras Access: dentro de Notion fallan en silencio (no se usan).
- Probado (10-nov): local en `:4599/?embed=donut&boda=ale-lorenzo` con datos reales; camino nube
  simulado (copia con `IS_CLOUD=true`, boda del archivo); funciones con un arnés de Node (claves buenas,
  malas, de otra boda, sin secreto). En la nube real (10-nov): `/embed` de Ale + Lorenzo pinta 83 h con
  fuentes y datos; clave falsa → 403. Falta verlo dentro de Notion (Mac e iPhone).

