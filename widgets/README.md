# Widgets del Hub de Edición

Dos widgets que reproducen la gráfica **"Horas por día — últimos 7 días"** del
dashboard (mismos colores, leyenda y layout: Previos morado · Hoy lima · Récord
naranja · Sábado lila claro · línea de meta a 5h). Leen el endpoint compacto
**`/api/summary`** (contrato en [`../docs/arquitectura.md`](../docs/arquitectura.md) §2):

| Widget | Lee de | Requisito |
|---|---|---|
| iPhone (Scriptable) | **la nube** `https://hub-edicion.pages.dev/api/summary` | Service Token de Cloudflare Access |
| Mac (SwiftBar) | **el server local** `http://localhost:4599/api/summary` | server corriendo (launchd `com.jordi.hub-edicion`) |
| iPhone · **dona** (Scriptable, 16-nov) | **la nube** `https://hub-edicion.pages.dev/api/edicion` (payload completo) | el mismo Service Token · ver [la sección de la dona](#-iphone--scriptable-la-dona-hubedicion-donascriptablejs--16-nov-2026) |

El **avance** de cada boda y el **color de la etapa activa** son los mismos del dashboard
(etapas de edición hechas / etapas; color por fase).

Probar el endpoint local:

```bash
curl -s http://localhost:4599/api/summary | python3 -m json.tool
```

---

## 📱 iPhone — Scriptable (`HubEdicion.scriptable.js`)

> **Memoria (9-nov-2026):** cada lectura buena se guarda en el teléfono. Si la siguiente falla (sin
> internet o acceso de Cloudflare caducado) el widget muestra la última con su hora en naranja
> («GUARDADO · 18:13»; en el tamaño pequeño, un punto naranja) en vez de quedarse sin gráfica. Solo
> si nunca hubo una lectura dice «Sin datos todavía · Sin internet o acceso caducado».
> La copia viva es `Hub Edición · Barras.js` (se llamaba `Hub de Edición.js` hasta el 16-nov-2026) en la carpeta de Scriptable de iCloud (lleva tus claves).

1. Instala **Scriptable** (gratis, App Store).
2. Abre Scriptable → **+** → pega TODO el contenido de `HubEdicion.scriptable.js`
   → nómbralo **"Hub Edición · Barras"**.
3. Pega el **Client ID** y **Client Secret** del Service Token (Cloudflare Zero Trust →
   Access → Service credentials) en `ACCESS_CLIENT_ID` / `ACCESS_CLIENT_SECRET`. El secreto
   solo vive en ese script, en tu teléfono.
4. Pantalla de inicio: mantén pulsado → **+** → **Scriptable** → tamaño
   **Mediano** (recomendado) o **Pequeño**.
5. Toca el widget recién puesto → **Script: Hub Edición · Barras**.

Funciona desde **cualquier lugar** (la Mac puede estar apagada); los datos se renuevan
cada 30 min en la nube.

- **Mediano:** la gráfica completa (título + leyenda + 7 barras con horas y línea
  de meta), dibujada con `DrawContext`.
- **Pequeño:** versión compacta de las 7 barras (sin leyenda, iniciales de día).
- **Apariencia = identidad A del dashboard (nov-2026):** paleta Pantone (violeta previos · lima hoy ·
  naranja récord), base OLED con luz ambiente (orbes lima/violeta/naranja) y grano al 50 %, barras con
  degradado vertical (luz arriba → 42 %), halo en hoy y récord, cifras y etiquetas en monoespaciada
  (SF Mono, lo más cercano a JetBrains Mono que hay en iOS; Archivo no se puede cargar en Scriptable).
  **La geometría de las barras no cambió** (mismo alto, ancho, huecos y radios; verificado punto a punto
  contra la versión anterior). Antes/después: *(captura solo en la Mac: `../docs/propuestas/widget-identidad-a-antes-despues.png`)*.
  Versión anterior en `docs/historico/HubEdicion.scriptable.pre-identidad-a.2026-11-01.js`.
- **Ajustes 1-nov:** cifras sobre las barras con la misma letra que la leyenda (monoespaciada regular 8,5, en gris como la leyenda;
  7 en pequeño), halo de hoy/récord −30 % y, en claro, sin el orbe naranja de abajo (se veía como neblina).
  Variantes que se compararon: *(captura solo en la Mac: `../docs/propuestas/widget-variantes-cifras-y-boton.jpg`)*.
- **Ajuste 3-nov (modo claro, barras sin lavado):** la base de las barras se veía lavada porque `gradBar`
  mezclaba el color un 58 % con el crema del fondo (el orbe quitado el 1-nov no era la causa; las barras son
  opacas). En claro (`barShade: .08`) el color queda pleno arriba y solo se oscurece un 8 % hacia abajo. El modo
  oscuro sigue igual (lo comprobamos operación por operación) y no cambian ni la geometría, ni las cifras, ni las etiquetas.
  Antes/después: *(captura solo en la Mac: `../docs/propuestas/widget-barras-sin-lavado-2026-11-03.png`)*.
  Respaldo de la copia de iCloud (claves sustituidas por los textos de ejemplo): `docs/historico/Hub de Edición.icloud.pre-barras-sin-lavado.2026-11-03.js`.
- **Ajuste 3-nov (modo vidrio / tintado, sin placa blanca):** en el escritorio del Mac (y en la pantalla de
  inicio tintada o transparente del iPhone) el sistema pasa todo el widget a blanco según lo claro que sea cada
  color (claro = blanco opaco, oscuro = transparente). La captura lo confirma: la raya de meta (gris muy claro) y
  la barra del sábado salen casi blancas, el título gris oscuro sale tenue y el grano negro deja motas en la
  placa. Desde la versión 1.7.19, Scriptable mantiene la *imagen* de fondo en ese modo, y la nuestra traía la
  base crema dentro: por eso salía la placa lechosa. Scriptable no dice al script en qué modo se muestra el
  widget (`config` no tiene esa información), así que no se puede dibujar una variante aparte. Arreglo: la base va
  solo en `widget.backgroundColor`, el fondo que el sistema quita para poner su vidrio. `drawBackground` dibuja
  ahora sobre un lienzo transparente solo la luz ambiente, el grano y el filo de luz. La gráfica no cambia.
  **Modo normal:** las operaciones de dibujo son las mismas (salvo la base, que va aparte) y, con Core Graphics
  real, la diferencia es de 4/255 como mucho (en 16 bits, 1/255). Es menos de lo que ya cambia el widget entre
  un refresco y otro por el grano aleatorio (unos 30/255).
  Antes/después: *(captura solo en la Mac: `../docs/propuestas/widget-modo-vidrio-normal-igual-2026-11-03.png`)*.
  **Modo vidrio:** no hay simulador, así que hay que comprobarlo en el Mac o el iPhone. Si aun así queda una placa
  blanca *lisa* (sin motas de grano), Scriptable también conserva el color de fondo, y haría falta otra salida
  (por ejemplo, una variante que se active con el parámetro del widget). Las cifras y etiquetas grises seguirán
  algo tenues en ese modo, porque el sistema las aclara según su color y en el modo normal no cambian.
  Respaldo de la copia de iCloud (claves sustituidas): `docs/historico/Hub de Edición.icloud.pre-modo-vidrio.2026-11-03.js`.
- **Ajuste 3-nov (tarde): vuelve el velo en claro y el halo es más fino.**
  - **Velo en claro:** el degradado de las barras vuelve en claro, al mismo nivel que el dashboard en claro: la base queda al 61 %, un velo un 33 % más suave que el original.
    - Ahora es **transparencia** del mismo color (`fadeAlpha`), no una mezcla con el crema.
    - En la pantalla normal se ve igual.
    - En el modo vidrio o tintado, la base se funde con el vidrio en lugar de volverse blanca, como en los widgets vecinos.
    - Se sustituye a `barShade` (mediodía del 3-nov).
  - **Halo de hoy y del récord:** radio de unos 10 pt a 6,6 pt (−33 %) y pico de intensidad del 20,5 % al 15,5 % (−25 %).
    - Es el mismo en claro y en oscuro. Antes, en claro, casi no se veía.
    - Se ajusta en `PALETTES.*.halo`.
  - La geometría de las barras, las cifras y las etiquetas no cambian.
  - Capturas en `../docs/capturas/`: `widget-glow-oscuro-2026-11-03.jpg`, `widget-velo-glow-claro-2026-11-03.jpg` y `widget-transparente-2026-11-03.jpg`. El modo transparente es una simulación: blanco con opacidad según lo claro que sea cada píxel.
  - Respaldo de la copia de iCloud (claves sustituidas): `docs/historico/Hub de Edición.icloud.pre-velo-glow.2026-11-03.js`.
- **`Dark Mode (global).js`** también lleva la identidad A: fondo con luz y grano, luna/sol con halo y un
  selector DARK | LIGHT como los del dashboard. La lógica que voltea los widgets no cambió.
- **Actualizar en el iPhone:** Scriptable guarda sus scripts en iCloud
  (`~/Library/Mobile Documents/iCloud~dk~simonbs~Scriptable/Documents/Hub Edición · Barras.js`). Desde el Mac
  basta con copiar ahí el archivo nuevo **conservando** las 3 líneas de cabecera de Scriptable, el
  Service Token (`ACCESS_CLIENT_ID/SECRET`) y `DARK_MODE` (Jordi lo usa en claro). Así se hizo el 1-nov.
- Tocar el widget abre el dashboard en el navegador.
- `Dark Mode (global).js`: script aparte que voltea `DARK_MODE` en todos tus widgets a la vez.
  **Desde un atajo (12-nov-2026):** «Run Script» con parámetro `oscuro` | `claro` | `alternar` fija ese modo sin
  ventanas y devuelve el modo final al atajo. Atajo «Modo oscuro» del iPhone: [`../docs/atajo-modo-oscuro.md`](../docs/atajo-modo-oscuro.md); el archivo
  ya hecho es `atajo/Modo oscuro.shortcut` (+ `Widgets oscuro` / `Widgets claro` para automatizaciones al atardecer/amanecer) (lo genera `atajo/make-atajo.py`, que también lo copia a la carpeta de Scriptable de iCloud).
  Respaldo previo: `docs/historico/Dark Mode.icloud.pre-atajo.2026-11-12.js`.
  **Tocar la carátula (18-nov-2026):** abre el atajo `atajo/Tema widget.shortcut`, que alterna, redibuja los widgets y
  regresa al inicio (`TAP_URL`; el atajo debe llamarse exactamente «Tema widget»). Respaldo: `docs/historico/Dark Mode.icloud.pre-tema-widget.2026-11-18.js`.
  Desde el 3-nov-2026 cambia al tocarlo, sin pedir confirmación ni mostrar «Listo»; solo avisa si algún
  widget de la lista no se encontró o no tiene el flag. Respaldo: `docs/historico/Dark Mode.icloud.pre-sin-confirmacion.2026-11-03.js`.

---

## 💻 Mac — SwiftBar (`hubedicion.5m.py`)

1. Instala SwiftBar:

   ```bash
   brew install --cask swiftbar
   ```

2. Al abrirlo te pide una **carpeta de plugins** (p.ej. `~/SwiftBarPlugins`).
   Enlaza este plugin ahí:

   ```bash
   mkdir -p ~/SwiftBarPlugins
   ln -s ~/HubEdicion/widgets/hubedicion.5m.py ~/SwiftBarPlugins/hubedicion.5m.py
   ```

3. SwiftBar → **Refresh all**.

En la barra de menús verás `55%  6h 18min ✓`. Al abrir el desplegable se muestra la
**gráfica de barras** (renderizada como imagen vía `qlmanage`+`sips`, idéntica al
dashboard) seguida de avance, horas/meta, racha y etapa en curso. El `5m` del nombre
= se refresca cada 5 minutos (usa el enlace simbólico, así los cambios al script se
reflejan solos).

> Requiere las utilidades de macOS `qlmanage` y `sips` (incluidas en el sistema). Si
> fallan, el plugin cae a una lista de texto con los días y horas.

---

## 🍩 iPhone — Scriptable, la dona (`HubEdicion-dona.scriptable.js`) · 16-nov-2026

Segundo widget de iPhone: la tarjeta **«Horas y $ por etapa»** del dashboard. Dona de la boda con el
tiempo exacto en el centro y, por fase, horas · $ · %. En iCloud es **`Hub Edición · Donas.js`** (lleva la
misma llave que el de barras; la copia del repo trae los textos de ejemplo `PEGA_AQUI_…`).

- **Datos:** `GET /api/edicion` (el mismo payload que el dashboard) con el **mismo Service Token** que el de
  barras. No hace falta nada nuevo en la nube. Guarda en el teléfono una versión recortada de la última
  lectura (`hub-edicion-dona.json`); si la siguiente falla, pinta esa con **GUARDADO · hora** en naranja
  (en pequeño, un punto naranja).
- **Qué boda:** la misma que abre el dashboard (`currentKey`): la boda **en curso**; si no hay, la de edición
  terminada más reciente. **Parameter** opcional del widget = parte del nombre de una boda (`emilio`,
  `paula`…), también las del Archivo. Si no la encuentra lo dice.
- **Cálculo:** copiado de `deriveModel`/`projModel` de `index.html` (`phaseOf`, `inProgress`, precio `Total` o
  $XX,XXX, Cambios · en espera). Si cambia esa lógica en el dashboard, hay que copiarla aquí.
- **Tamaños:** pequeño = solo la dona con el total · mediano = título + boda, dona a la izquierda y leyenda
  (HL / SF abreviado) a la derecha · grande = dona grande + lista completa; la dona crece o se encoge según
  cuántas fases haya (3 → 212 pt, 5 → 171 pt).
- **Dibujo:** igual que el de barras, todo en una imagen de `DrawContext` sobre lienzo transparente; la base
  va en `widget.backgroundColor` (modo vidrio). La dona usa la geometría del SVG (R 140, trazo 18, hueco 30,
  desde las 12, en el orden de Notion) y cada segmento es una figura rellena con puntas redondas; el halo
  (≈ `fxGlowD`) son capas un poco más anchas casi transparentes. Colores = `--f-prep`, `--f-teas`,
  `--sun-data`, `--violeta`, `--naranja` de cada tema. Cifras en SF Mono; el total en SF Pro Light.
- **Tema:** `const DARK_MODE` como el de barras. «Dark Mode» (y el atajo «Modo oscuro») lo cambian: desde el
  16-nov la lista `WIDGETS` de `Dark Mode.js` es `Notion Dashboard`, `Hub Edición · Barras`, `Hub Edición · Donas`.
- **Nombres (16-nov, con OK de Jordi):** el de barras pasó de `Hub de Edición` a `Hub Edición · Barras`. El widget que ya
  estaba en la pantalla hay que volver a apuntarlo (mantener pulsado → Editar widget → Script). Los atajos no cambian
  (solo llaman a «Dark Mode»). Respaldo de Dark Mode antes del cambio: `docs/historico/Dark Mode.icloud.pre-donas.2026-11-16.js`.
- **Tocar** abre el dashboard (la boda en curso ya sale por defecto; el dashboard aún no admite abrir otra
  boda por enlace).
- **Capturas** (simuladas en el Mac): `../docs/propuestas/widget-donas-oscuro-2026-11-16.png` y `…-claro-…png`.
- **Ajuste 19-nov (pantalla de inicio tintada/transparente):** con el tema claro, la dona se veía como una banda
  blanca pareja con óvalos brillantes en los huecos, y el total apenas se leía. **Causa:** en ese modo iOS pasa
  cada píxel de la imagen a blanco según lo claro que sea. La pista era un gris claro opaco (`#e6e4dd`) que
  brillaba más que los segmentos, de color más oscuro, y entre las puntas redondas asomaba como óvalos. El texto
  oscuro del centro casi desaparecía. Scriptable sigue sin decirle al script en qué modo está.
  **Arreglo (sirve en los tres modos):**
  - **Pista y rayas de la leyenda en claro:** son tinta negra casi transparente (4,4 % y 5,6 %). A todo color
    dan el mismo gris; en el modo tintado desaparecen y los huecos quedan limpios.
  - **Pequeño:** la dona es el fondo de una pila y el total va encima como texto **nativo** (`nativeCenter`).
    iOS pinta el texto nativo en blanco en ese modo. A todo color queda en el mismo lugar (menos de 1 pt).
  - **Tema oscuro (corregido la misma noche):** la dona pequeña ahora es el *fondo de una pila*, y iOS la pinta
    en blanco **según su alfa**, no según su claridad, como pasa con la imagen suelta. La pista oscura opaca
    (`#1a1a1e`) salió como un aro blanco continuo, sin huecos: lo confirmó una captura de Jordi justo cuando
    «Dark Mode» pasó los widgets a oscuro. Ahora la pista oscura es luz al 10 % (`#d7d7f6`), con el mismo gris
    a todo color (máx. 28/255 por el grano que se transparenta). Captura: `../docs/propuestas/widget-donas-tintado-oscuro-2026-11-19.png`.
    **Regla:** todo lo que va en la imagen de la dona pequeña debe ser casi transparente si no es el trazo.
  - **Pendiente:** en mediano y grande con tema claro, el total del centro y las cifras en $ siguen tenues en el
    modo tintado. Siguen dentro de la imagen; pasarlos a texto nativo pide rehacer la maquetación.
  Antes y después: `../docs/propuestas/widget-donas-tintado-pequeno-2026-11-19.png` y `…-mediano-…png`.
  Respaldo (llaves sustituidas): `../docs/historico/Hub Edición · Donas.icloud.pre-modo-tintado.2026-11-19.js`.
- **Probarlo sin iPhone:** simulador de Scriptable en node (graba las operaciones de `DrawContext`) + pintor
  en Swift con CoreGraphics y las fuentes del sistema. Se hizo en el scratchpad de la sesión del 16-nov; si
  hace falta otra vez, se rehace en un rato (unas 60 + 80 líneas).
