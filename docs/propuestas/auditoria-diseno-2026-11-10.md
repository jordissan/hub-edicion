# Auditoria de diseno · Hub de Edicion ("Sala de Corte")

> **Para quien ejecuta (Opus 5.5 en Claude Code, carpeta `~/HubEdicion`).** Este documento es autosuficiente:
> trae el diagnostico, las reglas de trabajo y 25 directrices con su criterio de aceptacion. Ejecutalas por
> fases, en orden. No hace falta pedir confirmacion salvo en las 3 decisiones marcadas en la seccion 3.
>
> - **Auditado:** `index.html` del 10-nov-2026 (07:05), con el snapshot de ejemplo embebido.
> - **Como:** Chromium a 1440 × 900 (escritorio) y 390 × 844 (iPhone), tema oscuro y claro. Tamano de texto,
>   contraste y areas tactiles medidos sobre el DOM con el snippet de la seccion 8.
> - **Tablero visual de la auditoria** (capturas anotadas y antes/despues): artifact "Auditoria de diseno - Hub de Edicion".
> - Los numeros de linea son de la version auditada y se mueven al editar: **localiza siempre por selector o por
>   nombre de funcion**, no por linea.

---

## 1. Diagnostico en una pagina

El tablero cuenta bien su historia (el titular de Carrera resume el resultado en una frase) y tiene identidad
propia. Lo que le falta es **legibilidad** y **escala en el iPhone**.

| Medida (linea base) | Escritorio 1440 | iPhone 390 | Meta |
|---|---|---|---|
| Textos por debajo de 11 px | 305 de 620 (49 %) | 274 de 564 (49 %) | 0 |
| Texto mas chico | 8,3 px | **5,6 px** | >= 11 px (>= 10 px dentro de SVG) |
| Textos con contraste < 4,5 : 1 (oscuro / claro) | 238 / 289 | 209 / 261 | 0 |
| Controles con area < 44 px | 44 de 64 | **48 de 60** | area tactil >= 44 px en iPhone (ver M1) |
| Controles con area < 24 px | 27 | 33 | 0 |
| Largo de la pagina | 6.800 px (7,6 pantallas) | **10.649 px (12,6 pantallas)** | <= 9.300 px en iPhone |
| Desborde horizontal | no | no | no |

Causas raiz (pocas, y casi todas se arreglan en un solo sitio):

1. **`--dim` no alcanza contraste.** `#66666f` da 3,26 : 1 sobre `--panel` y 3,05 : 1 sobre `--panel2`; en claro,
   `#7a7a80` da 3,68 : 1 sobre `--bg`. Lo usan 44 reglas de CSS.
2. **No hay piso tipografico.** 37 valores distintos de `font-size`; las etiquetas mono van de 8,5 a 10,5 px.
3. **Cuatro graficas se encogen con su `viewBox`** en el iPhone (`#hod`, `#week`, `#sprints`, `#dia7`).
4. **El color del cambio no sigue una regla:** lima por posicion (`:first-child`), y "peor" es naranja en Tarifa
   y violeta en Historial y en Ahorro.
5. **Controles pensados para cursor:** selectores de 23 px de alto, "Ver los datos" de 17 px, CTA de 39 px.
6. **Contenido repetido en Proyectos:** la leyenda de la dona y "Etapas" listan las mismas 14 etapas.

---

## 2. Reglas de trabajo (obligatorias)

1. **Fuente unica:** edita solo `~/HubEdicion/index.html`. Nunca edites `cloud/index.html` a mano: se genera con
   `sync-cloud.sh`.
2. **Respaldo antes de empezar:** copia `index.html` a `docs/historico/index.pre-auditoria.2026-11-10.html`
   (misma convencion que `index.pre-trazo.2026-11-09.html`).
3. **No publiques a la nube.** No corras `sync-cloud.sh --publicar` ni hagas push: lo decide Jordi al final.
4. **No toques datos ni logica:** `deriveModel()`, `server.py`, los endpoints, el sprint, el snapshot embebido y
   `snapshot-demo.py` quedan igual. Esto es solo presentacion (CSS, marcado y funciones `render*`).
5. **Una fase a la vez.** Al cerrar cada fase: (a) revisa en el navegador a 1440 × 900 y a 390 × 844, en oscuro
   y en claro (configuracion `hub` de `.claude/launch.json`, puerto 8753, sirve el snapshot); (b) corre el
   snippet de la seccion 8 y anota los numeros; (c) si algo empeora, corrige antes de seguir.
6. **Todo por tokens.** Ningun color ni tamano nuevo escrito a mano dentro de una regla: define el token en
   `:root` (y en `:root[data-theme="light"]` si cambia) y usalo.
7. **Respeta `prefers-reduced-motion`** en cualquier transicion nueva (hay dos bloques `@media` que lo manejan).
8. **Documenta como hace el proyecto:** al terminar, anade en `README.md` ("Que muestra") una nota fechada por
   cada comportamiento que cambie, y actualiza `docs/arquitectura.md` si tocas una funcion `render*`.
9. **El CSS tiene capas.** Las reglas base estan arriba (aprox. lineas 76-800) y la identidad "A · Difusion"
   las sobrescribe mas abajo (aprox. 859-1130). Antes de cambiar una propiedad busca **todas** las reglas del
   selector (`.m .v`, `.kpi .v`, `.dinero`, `.hoy`...) y edita la que gana.

### No cambiar (identidad ya decidida por Jordi)

- Paleta y su papel: lima `#d9ed2f` como luz, violeta, naranja, crema; azul y aqua para fases.
- Tipografias: Archivo Light en cifras y titulares, JetBrains Mono en etiquetas, mono del sistema (`--f-t`) en prosa.
- Vidrio ahumado, grano (`--grain-k`), halos y luz ambiente por seccion.
- Trazo unico de las graficas de linea (9-nov), cuadricula de 12 columnas con gap de 14 px (7-nov).
- Orden y nombre de las siete secciones; iconografia; animaciones de entrada.
- Texto de la interfaz: no reescribas copys salvo donde una directriz lo pide.

---

## 3. Decisiones de Jordi (con valor por defecto)

Si Jordi no dice otra cosa, ejecuta la opcion **por defecto**.

| # | Decision | Por defecto | Alternativa |
|---|---|---|---|
| 1 | Color de "peor que la referencia" (C2) | **Violeta** en todo el tablero; el naranja queda para estado y atencion. Cambia 3 deltas de Tarifa y da color al titular. | Naranja en todo: obliga a recolorear Historial y Ahorro, y la tabla queda muy cargada de naranja. |
| 2 | Proyectos: fusionar leyenda de la dona con Etapas (D2) | **Fusionar** (una sola lista con estado, horas, $ y %). | Dejar las dos listas y solo quitar el estirado con `align-items:start`. |
| 3 | Barra de estado de iOS en tema claro (M6) | **Verificar primero en el iPhone**; aplicar la franja oscura solo si el reloj se ve blanco sobre crema. | No tocar. |

---

## 4. Directrices

Formato de cada una: **problema y evidencia → cambio → donde → criterio de aceptacion.**
Prioridad: **P1** hacer primero · **P2** importante · **P3** pulido.

### Fase 1 · Legibilidad

#### L1 · Subir el contraste del texto tenue — P1
- **Problema.** `--dim` se usa en subtitulos de tarjeta (`.card .cl .u`), etiquetas de tiles (`.m .l`), ejes
  (`.ax`), notas (`.card .note`), valores del sidebar (`.snav .it .val`), cabeceras de tabla y "Ver los datos".
  Contraste: 3,26 : 1 (oscuro, sobre `--panel`) y 3,68 : 1 (claro, sobre `--bg`). 238 textos fallan en
  escritorio oscuro y 289 en claro.
- **Cambio.** En `:root` → `--dim:#878791` (5,21 : 1 sobre `--panel`, 4,88 sobre `--panel2`, 4,77 sobre
  `--tipbg`). En `:root[data-theme="light"]` → `--dim:#66666c` (4,92 : 1 sobre `--bg`, 5,18 sobre `--panel2`,
  5,70 sobre blanco). `--mut` no cambia.
- **Cuidado.** `--dim` tambien colorea cosas que no son texto. Revisa cada uso con `grep -n "var(--dim)"`:
  donde sea relleno, borde o icono decorativo y ahora se vea demasiado presente, cambia ese uso a `--hair2`
  (bordes) o `--debar` (rellenos). `.pchip.wait` usa `color-mix` con `--dim`: se queda.
- **Donde.** `index.html`, bloque de tokens (`:root` y `:root[data-theme="light"]`, lineas ~77-114).
- **Aceptacion.** El snippet da `contrasteBajo45 = 0` en los cuatro casos (1440 y 390, oscuro y claro). La
  jerarquia de tres niveles sigue visible: `--txt` > `--mut` > `--dim`.

#### L2 · Piso tipografico de 11 px — P1
- **Problema.** 305 de 620 textos miden menos de 11 px en escritorio. Tamanos en uso bajo 11 px: 8,5 · 9 · 9,5 ·
  10 · 10,5 (52 declaraciones). Ejemplos: `.rmode button` 9,5 px, `.pchip` 9,5 px, `.htab .hn .pchip` 8,5 px,
  `.m .l` 10 px, `.card .cl .u` 10 px, `.htab th` 10 px, deltas de la tabla 10 px, `.ax` 10 px, `.rec` 10,5 px.
- **Cambio.**
  1. Anade a `:root`: `--fs-micro:11px; --fs-label:12px; --fs-sm:13px; --fs-md:14px; --fs-body:15px;`.
  2. Sustituye **toda** declaracion `font-size` menor de 11 px por `var(--fs-micro)`. Las de 11 y 11,5 px pasan
     tambien a `var(--fs-micro)`; las de 12 y 12,5 px a `var(--fs-label)`. No toques los tamanos de display
     (>= 16 px) ni los `clamp()`.
  3. Para que las etiquetas no se ensanchen: en esas mismas reglas baja el tracking un paso
     (`.14em`/`.12em` → `.1em`; `.1em` → `.08em`). Conserva mayusculas y peso.
  4. `.ax{font-size:11px}` (hoy 10 px) y `#race .ax` se queda en 11 px.
  5. Revisa lo que tenia `white-space:nowrap` o `text-overflow:ellipsis` (p. ej. `.hero .htiles .m .l`,
     `.rmode button`, `.htab th`): si algo se corta a 1440 o a 1280 px, acorta el tracking antes que el tamano.
- **Donde.** Todo el `<style>` principal; `font-size` en linea dentro de las funciones `render*` (busca
  `font-size:` y `font-size=` en el `<script>`).
- **Aceptacion.** El snippet da `bajo11px = 0` a 1440 (SVG incluido). Ninguna etiqueta cortada con puntos
  suspensivos a 1440 ni a 1280 px. El tablero no crece mas de 2 % de alto en escritorio.

#### L3 · Graficas de barras a tamano real en el iPhone — P1
- **Problema.** `renderHod` dibuja en un `viewBox` fijo de 560 × 240, `renderWeek` en 380 × 240, `renderSprints`
  en 430 × 240 y `renderDia7` (rama movil) en 380 × 240. La tarjeta mide 312 px en el iPhone, asi que el texto
  queda en 5,6 px (`#hod`: ejes y "VENTANA DE ORO · 73 %"), 7,3-7,6 px (`#sprints`) y 8,2-8,6 px (`#week`,
  `#dia7`). 46 textos bajo 9 px.
- **Cambio.** Dibuja las cuatro **al ancho real del contenedor**, como ya hacen `renderRace` y la rama de
  escritorio de `renderDia7`: `const W = Math.max(280, Math.round(svg.getBoundingClientRect().width))`, alto
  fijo (240), `viewBox = 0 0 W H`, y redibuja con un `ResizeObserver` (mismo patron que `.dia7card`, linea
  ~2709). Con poco ancho:
  - `#hod`: rotula el eje X cada 4 h (8, 12, 16, 20) cuando `W < 420`; si "VENTANA DE ORO · 73 %" no cabe
    sobre la franja, deja solo "VENTANA DE ORO" (el porcentaje ya esta en el texto de la seccion).
  - `#sprints` y `#week`: mantienen todos sus rotulos (5 y 7 columnas caben a 11 px).
  - `#dia7` movil: usa los rotulos cortos que ya tiene (03, 04...).
  - Quita los `viewBox` fijos del marcado (`<svg id="hod" viewBox="0 0 560 240">`, etc.).
- **Donde.** Funciones `renderHod`, `renderWeek`, `renderSprints`, `renderDia7` (lineas ~2671-2807) y sus
  `<svg>` en el marcado.
- **Aceptacion.** A 390 px ningun texto dentro de un SVG mide menos de 10 px (`minPx >= 10` en el snippet). Al
  girar el telefono o plegar el sidebar las graficas se redibujan sin deformarse. Las etiquetas de valor no se
  enciman.

#### L4 · Marcas de datos visibles en tema claro — P2
- **Problema.** En claro, los rellenos siguen siendo los del tema oscuro. Contra la tarjeta blanca: lima
  `#d9ed2f` 1,30 : 1 (barras de avance de `#proj`, segmentos Documental de la dona y de La cinta, rayitas del
  sidebar), aqua `#40d9c1` 1,76 : 1, azul `#5aa3ec` 2,66 : 1. Una marca de datos necesita 3 : 1.
- **Cambio.**
  1. Crea el token `--sun-data` (relleno lima **para datos**): en `:root` vale `#d9ed2f`; en claro `#799100`
     (3,58 : 1 sobre blanco, 3,09 sobre `--bg`).
  2. Usa `--sun-data` donde el lima es un dato: barra de avance de `#proj`, fase `doc` en `PHASES` (hoy
     `var(--sun-block)`), `.clip.doc`, rayitas de etapas del sidebar, cuadro "hoy" de las leyendas.
  3. `--sun-block` se queda como esta para botones y pastillas con texto en `--ink` (el CTA lima no cambia).
  4. En `:root[data-theme="light"]` anade: `--f-prep:#3b82d6; --f-teas:#0e9683; --naranja:#d9642c;`
     (3,93 · 3,68 · 3,61 : 1 sobre blanco).
- **Donde.** Tokens; `PHASES` (linea ~1701); reglas `.clip.*` (~672 y ~997); render de `#proj` y de `#sMesa`.
- **Aceptacion.** En tema claro, cada barra, segmento y punto de fase tiene >= 3 : 1 contra el fondo de su
  tarjeta. En tema oscuro no cambia nada (compara capturas antes y despues).

### Fase 2 · Color y significado

#### C1 · El color de un cambio depende de su signo — P1
- **Problema.**
  - Hero: `.hero .htiles .m:first-child .v` pinta en lima el primer tile sea cual sea el dato. Con el snapshot,
    "+10,9 h" (20 % **mas** horas) sale en lima con halo.
  - Titular: en `renderHero` solo la palabra "dias" va dentro de `<em>` (lima); "+10,9 h" queda blanco.
  - Tarifa: el mismo "−21 %" es naranja en el tile "$ / hora" y **lima a 42 px** en `.salto .sbig`.
- **Cambio.**
  1. Anade dos clases: `.is-better{color:var(--sun-tx)}` y `.is-worse{color:var(--violeta-tx)}` (ver C2), mas
     `.is-flat{color:var(--txt)}`.
  2. Anade un ayudante en JS: `const tone=(delta,menosEsMejor)=>delta===0?'is-flat':((delta<0)===menosEsMejor?'is-better':'is-worse');`
  3. `renderHero`: envuelve cada mitad del titular en un `<span>` con su clase (`dDays` y `dH`: menos es mejor).
     Aplica la clase tambien al `.v` de los tiles de horas y de h/escena. El tile "D26 vs D33" lleva la clase
     segun `dDays`.
  4. Borra del CSS la parte `.hero .htiles .m:first-child .v` de la regla de la linea ~975 (conserva
     `.dinero .kpi:first-child .v`: "$191/h" es la cifra de la seccion, no un cambio). El halo (`text-shadow`)
     pasa a `.hero .htiles .m .v.is-better`.
  5. `.salto .sbig`: deja de ser lima fijo; lleva `is-better` / `is-worse` segun el signo ($/h: mas es mejor).
- **Donde.** `renderHero` (~2269), CSS ~975 y ~1022, render de Tarifa (~2954).
- **Aceptacion.** Con el snapshot: "−7 dias" en lima, "+10,9 h" y "+14 %" en violeta, "−21 %" del salto en
  violeta. Invirtiendo el signo a mano en la consola, los colores se invierten. Ninguna cifra de cambio toma
  color por su posicion.

#### C2 · Una sola regla para "peor" — P2 (decision 1)
- **Problema.** "Peor que la referencia" es **naranja** en los deltas de Tarifa y **violeta** en Historial y en
  Ahorro por etapa. El naranja ademas significa "record de la semana" (bueno) en Horas por dia y "en curso /
  en espera" en los chips.
- **Cambio (por defecto).** Regla unica, escrita como comentario junto a los tokens:
  - **lima** = hoy, la boda actual, mejor que la referencia, accion primaria;
  - **violeta** = referencia anterior y peor que la referencia;
  - **naranja** = estado y atencion (EN CURSO, EN ESPERA, SNAPSHOT/GUARDADO, sin registrar), fase Cambios y el
    record de la semana;
  - **gris** = contexto.
  Aplicacion: los deltas de Tarifa que hoy salen en `--naranja-tx` cuando el dato empeora (en el snapshot,
  "-21 %" y "+14 %") pasan a `.is-worse` (violeta). Historial y Ahorro ya cumplen.
- **Donde.** Render de Tarifa (clases de los deltas), comentario en `:root`, y la frase del README
  "lima si mejora, naranja si empeora" → "lima si mejora, violeta si empeora".
- **Aceptacion.** No queda ningun delta de comparacion en naranja. El naranja solo aparece en estados, en
  Cambios y en el record de la semana.

#### C3 · `aria-label` de las graficas desde los datos — P2
- **Problema.** Dos etiquetas estan escritas a mano y contradicen la grafica: `#hod` dice "ventana de oro de 10
  a 16 horas" (la grafica y el texto dicen 11:00-17:00) y `#week` dice "el martes es el mas fuerte" (es jueves).
- **Cambio.** En `renderHod` y `renderWeek`, al final, `svg.setAttribute('aria-label', ...)` con `M.goldStart`,
  el porcentaje de la ventana y el dia mas fuerte calculados. Deja en el marcado un texto neutro.
- **Aceptacion.** Las dos etiquetas coinciden con lo que muestra la grafica en "Tablero" y en "Historial".

### Fase 3 · Escritorio

#### D1 · El marcador activo del sidebar pisa el dato — P1
- **Problema.** `.ind::after` (raya de 2 px, `right:9px`) queda a 3 px del valor del item: "+10,9 h|", "2|".
- **Cambio.** `.snav .it{padding-right:24px}` (hoy 14 px). Comprueba el sidebar plegado (`html.side-closed`):
  ahi el valor esta oculto y el relleno debe seguir centrando el icono.
- **Donde.** CSS `.snav .it` (~905) y `.ind::after` (~915).
- **Aceptacion.** >= 10 px entre el final del valor y la raya en los 7 items; plegado sin cambios.

#### D2 · Proyectos: una sola lista de etapas — P2 (decision 2)
- **Problema.** `#dlg` (leyenda de la dona: 14 filas con $, horas y %) y `#etapas` (14 filas con estado y
  horas) muestran las mismas etapas lado a lado. La tarjeta de Etapas mide 702 px de contenido y se estira a
  873 px para igualar a la de la dona: 130 px en blanco, contra la regla del reacomodo ("nunca se estira una
  tarjeta sola"). En el iPhone la leyenda suma 424 px.
- **Cambio (por defecto).**
  1. `#etapas` pasa a ser la lista unica: a cada fila le sumas `$` y `%` (columnas a la derecha, en mono;
     en el iPhone `%` se oculta). El encabezado de cada fase conserva "4/4 · 19,6 h".
  2. Bajo la dona, `#dlg` deja de listar etapas y muestra el **resumen por fase** (hasta 5 filas: punto de
     color, nombre, horas, $, %). Los totales por fase que hoy estan al pie de La cinta se **mueven** aqui
     (La cinta conserva su leyenda y la cinta) para no repetirlos.
  3. El centro reactivo de la dona sigue igual; al pasar por un segmento resalta su fila en `#etapas`, y al
     pasar por una fila resalta su segmento (hoy lo hace con `#dlg`).
  4. `.mesa2{align-items:start}` para que ninguna tarjeta se estire.
- **Donde.** `renderDonut` y `renderEtapas` (~2842-2900), CSS `.mesa2`, `.dlg`, `.dwrap`.
- **Aceptacion.** Cada etapa aparece una sola vez en la seccion. Ninguna tarjeta de `.mesa2` tiene mas de 24 px
  de vacio al pie. Proyectos baja al menos 400 px en el iPhone.

#### D3 · Un solo boton primario de sprint a la vista — P3
- **Problema.** Con la seccion Hoy en pantalla hay dos "INICIAR SPRINT" en lima: `#focusBtn` y `#sSprGo`.
- **Cambio.** Un `IntersectionObserver` sobre `#focus` pone `html.sprint-card-in-view` cuando la tarjeta se ve
  (>= 60 %). Con esa clase, `.spr-go` pasa a contorno (fondo transparente, borde y texto `--sun-tx`). Sin la
  clase vuelve a relleno lima. Con un bloque en marcha no cambies nada (ahi el espejo es util).
- **Aceptacion.** En Hoy solo un boton tiene relleno lima; en cualquier otra seccion el del sidebar lo recupera.

#### D4 · Sidebar en ventanas bajas — P3
- **Problema.** A 800 px de alto, `.spr` (180 px) deja ver una sola boda de "En la mesa".
- **Cambio.** `@media (min-width:1024px) and (max-height:820px)`: `.spr` en una fila (reloj a la izquierda,
  boton a la derecha, sin la linea de destino; alto <= 96 px).
- **Aceptacion.** A 1280 × 800 se ven completas al menos dos bodas de "En la mesa" y el Archivo.

#### D5 · Horas por dia: menos aire arriba — P3
- **Problema.** 74 px entre el titulo y la guia de meta. En `renderDia7` (escritorio) `pt=44` y
  `maxV=Math.max(6, rec*1.15)`: la escala llega a 6 h aunque nada pase de 5 h.
- **Cambio.** `pt=30` y `maxV = Math.max(metaMax, rec) * 1.1`, con `metaMax` = la meta mas alta de la ventana.
- **Aceptacion.** Entre el titulo y el elemento mas alto de la grafica hay de 24 a 40 px. La cifra sobre la barra
  mas alta no se corta.

#### D6 · Carrera de todas: curvas de contexto distinguibles — P2
- **Problema.** Las bodas de contexto comparten gris y grosor; la leyenda repite cinco veces el mismo trazo. Sin
  cursor (iPhone) no se sabe cual es cual. Los nombres de la leyenda son el control para elegir boda y miden
  15 px de alto.
- **Cambio.**
  1. Rotulo al final de cada curva de contexto: el primer nombre (p. ej. "Lucia") en `--dim`, 11 px, con
     separacion vertical minima de 12 px entre rotulos (desplaza y une con una linea fina si chocan).
  2. Rampa de claridad por antiguedad (la mas vieja mas tenue, la mas reciente cerca de `--mut`), sin bajar
     de 3 : 1 contra la tarjeta.
  3. Los items de la leyenda pasan a ser `<button>` con `aria-pressed`, alto minimo 32 px (44 px en tactil).
- **Donde.** `renderHistDraw` (~2494) y la leyenda de `#raceAll`.
- **Aceptacion.** Cada curva se identifica sin interaccion. La leyenda se recorre con Tab y cada item tiene
  nombre accesible.

#### D7 · Estado vacio de "Etapa activa" — P3
- **Problema.** Sin etapa activa el tile muestra solo "—" en naranja.
- **Cambio.** Valor "Sin etapa" en `--mut` (tamano 16 px, como cuando hay etapa) y etiqueta "ELIGE DESTINO EN
  EL SPRINT". El tile entero hace foco en el selector de destino del sprint al tocarlo.
- **Donde.** Plantilla del tile en el render de Hoy (~2659).
- **Aceptacion.** El tile vacio dice que pasa y ofrece una accion; con etapa activa no cambia.

### Fase 4 · Movil

#### M1 · Areas tactiles de 44 px — P1
- **Problema.** 48 de 60 controles miden menos de 44 px en algun lado y 33 menos de 24 px.
- **Cambio.** Todo dentro de `@media (pointer:coarse)` (y tambien `(max-width:640px)` donde aplique). Sube el
  tamano visible y completa el area hasta 44 px con un pseudo-elemento (`position:relative` +
  `::after{content:"";position:absolute;inset:-6px 0}`), sin mover el layout:

  | Control | Hoy | Visible | Area tactil |
  |---|---|---|---|
  | `.rmode button` (Sin/Con teaser, Tablero/Historial, datos de Progreso) | 23 px | 36 px | 44 px |
  | `.tbl summary` ("Ver los datos") | 17 px | 17 px + `padding-block:14px` | 45 px |
  | `.sx-chip` (esquema) | 25 px | 32 px | 44 px |
  | `.fgo` / `#focusBtn` (INICIAR SPRINT) | 39 px | **48 px** | 48 px |
  | `.tabbar a` | 38 × 42 px | pastilla igual | celda de 52 px de alto (`margin:0`, la pastilla va en un `span` interior) |
  | `.refreshbtn`, `.thm` | 31 × 34 px | 40 × 40 px | 44 px |
  | `.legend .k` que eligen boda | 15 px | 32 px | 44 px |
  | `.parch`, `.wd`, `.spr-go` | 38-40 px | 44 px | 44 px |

  `.clip` de La cinta (algunos de 5 px de ancho): quita `tabindex` y el tooltip tactil a los clips de menos de
  24 px de ancho; su dato ya esta en la lista de Etapas.
- **Aceptacion.** A 390 px el snippet da `bajo24 = 0` y cada control cumple su fila de la tabla. `bajo44` puede
  quedar por encima de 0 porque el snippet mide la caja visible, no el pseudo-elemento: lista cuales son y
  comprueba su area con `document.elementFromPoint`. El dock sigue cabiendo a 375 px de ancho.

#### M2 · Cabecera fija con la seccion actual — P2
- **Problema.** `.top` solo es `sticky` desde 1024 px. En el iPhone la cabecera se va y el dock solo tiene
  iconos: ningun texto dice en que seccion estas.
- **Cambio.** Bajo 1024 px: `.top{position:sticky;top:0;z-index:30}` con el mismo vidrio, alto 48 px + area
  segura. Al pasar el hero, la marca se sustituye por la miga `.crumb` (icono + "Tu / Ritmo"), que ya existe y
  ya se actualiza con el scroll. A la derecha quedan el sello y ↻. Ajusta `scroll-margin-top` de `.hero,.sec` a
  la nueva altura.
- **Aceptacion.** En cualquier punto del scroll a 390 px se lee el nombre de la seccion. La cabecera no tapa el
  titulo al navegar desde el dock.

#### M3 · Pagina mas corta en el iPhone — P2
- **Problema.** 10.649 px (12,6 pantallas). Proyectos 2.577 px e Historial 2.545 px son la mitad.
- **Cambio (solo `max-width:640px`).**
  1. Etapas: las fases con todo completado arrancan plegadas (se ve su encabezado "PREPARACION · 4/4 ·
     19,6 h"; tocar despliega). La fase en curso arranca abierta. Usa `<details>` o un boton con
     `aria-expanded`.
  2. Historial "Boda con boda": muestra las 3 bodas mas recientes y un boton "Ver las N bodas".
  3. Con D2 hecho, la leyenda de 14 filas ya no existe.
- **Aceptacion.** `altoPagina <= 9.300 px` a 390 con el snapshot (hoy 10.649; D2 quita ~420 px, las fases
  plegadas ~450 px y la tabla corta ~600 px). Nada se pierde: todo sigue a un toque.

#### M4 · Pastilla de Insight — P3
- **Problema.** `.aip .tag2` ocupa una columna: el titulo se parte en 3 lineas y el detalle en 2.
- **Cambio.** Bajo 640 px: `.aip` en rejilla de dos filas; fila 1 = icono + `INSIGHT` (a la derecha); fila 2 =
  titulo y detalle a todo el ancho.
- **Aceptacion.** Con el texto del snapshot el titulo ocupa como maximo 2 lineas a 390 px.

#### M5 · Etiquetas de cifras a una linea — P3
- **Problema.** "CUMPLIENDO META DIARIA", "HORAS · ULTIMOS 7 DIAS" y "DIAS ACTIVOS · RACHA 0" se parten en dos
  lineas en los tiles de 2 columnas.
- **Cambio.** Version corta bajo 640 px (dos `span`, uno por tamano de pantalla, o `data-short`): "RACHA DE
  META", "HORAS · 7 DIAS", "DIAS ACTIVOS". El dato completo sigue en el tooltip.
- **Aceptacion.** Los seis tiles tienen etiqueta de una linea y la misma altura a 390 px.

#### M6 · Barra de estado de iOS en tema claro — P2 (decision 3, verificar)
- **Hipotesis.** `apple-mobile-web-app-status-bar-style` es `black-translucent`: iOS pinta reloj y bateria en
  blanco. En tema claro la cabecera es crema, asi que quedarian ilegibles. No se pudo comprobar sin el iPhone.
- **Cambio (solo si se confirma).** En tema claro y `@media (display-mode:standalone)`, una franja fija de
  `env(safe-area-inset-top)` de alto con el vidrio oscuro (como la franja superior del Mac, 3-nov).
- **Aceptacion.** En la app instalada, en claro, el reloj del sistema se lee.

#### M7 · Boton flotante del sprint en reposo — P3
- **Problema.** En reposo `#fab` muestra "12" (minutos del esquema): no se entiende que inicia un sprint.
- **Cambio.** En reposo, glifo ▶ (el mismo del CTA) en lugar del numero; con bloque en marcha, el tiempo como
  hoy. `aria-label` segun el estado ("Iniciar sprint" / "Sprint en curso, 12:40").
- **Aceptacion.** Reposo = ▶; en marcha = tiempo; el lector de pantalla anuncia el estado.

### Fase 5 · Sistema

#### S1 · Tokens de tipografia, radio y tracking — P3
- **Problema.** 37 valores de `font-size`, 22 de `border-radius`, 21 de `letter-spacing`.
- **Cambio.** Tras L2, completa la escala y sustituye valores sueltos por el token mas cercano:
  - Tipo: `--fs-micro 11` · `--fs-label 12` · `--fs-sm 13` · `--fs-md 14` · `--fs-body 15` · display 22 / 31 / 42 y los `clamp()`.
  - Radio: `--r-xs 4` · `--r-sm 8` · `--r-md 12` · `--r-lg 18` · `--r-pill 999`.
  - Tracking de etiquetas: `--tr-label .08em` · `--tr-wide .1em`.
- **Aceptacion.** Como maximo 12 valores distintos de `font-size` y 6 de `border-radius` en el CSS. Sin cambio
  visual mayor de 1 px en ningun elemento.

#### S2 · Consolidar las capas de CSS — P3
- **Problema.** Hay reglas definidas hasta tres veces (`.m .v` en ~540 y ~974; `.kpi .v` en ~689, ~976 y
  ~1015; `.dinero` en ~688 y ~1014).
- **Cambio.** Solo en los selectores que ya tocaste en este trabajo: deja una unica regla con el valor final y
  borra las anteriores. No hagas una limpieza general.
- **Aceptacion.** Ningun selector editado en esta auditoria queda declarado en mas de un sitio (salvo `@media`).

#### S3 · Formato unico de duraciones — P3
- **Problema.** Conviven "4h 14m", "20,3 h", "81h 06m", "1 min", "0,7 h" y "12′".
- **Cambio.** Regla (documentala en `docs/arquitectura.md`): duraciones **exactas** de un dia, una sesion o un
  total → `4h 14m`; **agregados y comparaciones** → decimal `20,3 h`; menos de 6 minutos → `N min`. Dentro de
  una misma tarjeta, un solo formato (Etapas mezcla "1 min", "0,7 h" y "1 h": usa decimal y `N min`).
- **Aceptacion.** Ninguna tarjeta mezcla formatos salvo la excepcion de minutos.

#### S4 · Tema inicial y `theme-color` — P3
- **Problema.** La primera visita ignora `prefers-color-scheme` (siempre oscuro) y `<meta name="theme-color">`
  queda en `#050506` aunque el tema sea claro.
- **Cambio.** En el script del `<head>`: si no hay `scTheme` guardado, usa
  `matchMedia('(prefers-color-scheme: light)')`. En el cambio de tema, actualiza el `content` del meta
  (`#050506` / `#f0eee9`).
- **Aceptacion.** Primera visita con el sistema en claro abre en claro; al alternar, la barra del navegador
  cambia de color.

---

## 5. Orden de ejecucion

1. **Fase 1** (L1 → L2 → L3 → L4). Es la que mas mueve las metricas; revisa cortes de texto al acabar L2.
2. **Fase 2** (C1 → C2 → C3).
3. **D1** y **M1** (los dos P1 que quedan).
4. Resto de **Fase 4** (M2 → M3 → M4 → M5 → M7; M6 solo tras verificar).
5. Resto de **Fase 3** (D2 → D6 → D3 → D4 → D5 → D7).
6. **Fase 5** (S1 → S2 → S3 → S4).

Si el tiempo es corto: L1, L2, L3, C1, D1 y M1 son el 80 % del resultado.

## 6. Verificacion final

- [ ] Snippet a 1440 × 900 (oscuro y claro): `bajo11px = 0`, `contrasteBajo45 = 0`.
- [ ] Snippet a 390 × 844 (oscuro y claro): `minPx >= 10`, `contrasteBajo45 = 0`, `bajo24 = 0`,
      `altoPagina <= 9300`, `desborde = false`.
- [ ] Recorrido visual de las 7 secciones en 1440, 1280 × 800, 1024, 820 y 390, en oscuro y en claro.
- [ ] Teclado: Tab recorre sidebar, selectores, leyendas y tablas con foco visible.
- [ ] `prefers-reduced-motion`: sin animaciones nuevas activas.
- [ ] Sprint: iniciar, terminar y descartar siguen funcionando (prueba en local, con `server.py`).
- [ ] README y `docs/arquitectura.md` actualizados; respaldo en `docs/historico/`.
- [ ] Sin publicar a la nube. Deja a Jordi un resumen de lo hecho y de lo que quedo pendiente.

## 7. Lo que ya funciona (no lo rompas)

- Titular de Carrera que cuenta el resultado; lectura de arriba abajo.
- Color por tokens en dos temas; paleta de fases validada para daltonismo.
- Graficas con etiqueta directa, trazo unico, guias punteadas y tabla "Ver los datos".
- `role="img"` + `aria-label` en cada grafica, titulos h1 → h2 → h3 en orden, `:focus-visible`,
  `aria-pressed` en selectores, respeto a `prefers-reduced-motion`.
- Cuadricula de 12 columnas, gap unico de 14 px, cero desbordes a 390 px.
- Sprint a mano en sidebar, dock y ventana flotante con un solo estado.

## 8. Snippet de verificacion

Pegalo en la consola del navegador (o ejecutalo desde la herramienta de vista previa) **despues de recorrer la
pagina hasta el final**, para que todas las tarjetas hayan entrado. Devuelve los numeros de la tabla de la
seccion 1. `contrasteBajo45` ignora el texto sobre pastillas rellenas (falso positivo del calculo de fondo).

```js
(() => {
  const vis = e => { const r = e.getBoundingClientRect(); if (r.width < 1 || r.height < 1) return false;
    for (let p = e; p && p !== document.documentElement; p = p.parentElement) { const s = getComputedStyle(p); if (s.display === 'none' || s.visibility === 'hidden' || +s.opacity === 0) return false; } return true; };
  const rgb = c => { let m = c.match(/rgba?\(([^)]+)\)/); if (m) { const p = m[1].split(/[, \/]+/).map(Number); return [p[0], p[1], p[2], p[3] === undefined ? 1 : p[3]]; }
    m = c.match(/color\(srgb ([\d.]+) ([\d.]+) ([\d.]+)(?: \/ ([\d.]+))?\)/); return m ? [m[1] * 255, m[2] * 255, m[3] * 255, m[4] === undefined ? 1 : +m[4]] : null; };
  const lum = c => { const f = v => { v /= 255; return v <= .03928 ? v / 12.92 : ((v + .055) / 1.055) ** 2.4; }; return .2126 * f(c[0]) + .7152 * f(c[1]) + .0722 * f(c[2]); };
  const ratio = (a, b) => { const A = lum(a), B = lum(b); return (Math.max(A, B) + .05) / (Math.min(A, B) + .05); };
  const bgOf = e => { const L = []; for (let p = e; p; p = p.parentElement) { const c = rgb(getComputedStyle(p).backgroundColor); if (c && c[3] > 0) { L.push(c); if (c[3] >= 1) break; } }
    let b = (rgb(getComputedStyle(document.body).backgroundColor) || [8, 8, 10]).slice(0, 3); for (let i = L.length - 1; i >= 0; i--) b = b.map((v, k) => L[i][k] * L[i][3] + v * (1 - L[i][3])); return b; };
  const texts = [], seen = new Set(), w = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT);
  while (w.nextNode()) { const n = w.currentNode, e = n.parentElement; if (!n.textContent.trim() || !e || seen.has(e) || e.closest('script,style,[hidden]') || !vis(e)) continue; seen.add(e);
    const s = getComputedStyle(e), svg = e instanceof SVGElement; let px = parseFloat(s.fontSize);
    if (svg) { const m = e.getScreenCTM(); px *= Math.sqrt(Math.abs(m.a * m.d - m.b * m.c)); }
    const col = rgb(svg && s.fill !== 'none' ? s.fill : s.color), bg = bgOf(svg ? e.closest('svg') : e); let op = 1; for (let p = e; p; p = p.parentElement) op *= +getComputedStyle(p).opacity;
    const fg = col ? col.slice(0, 3).map((v, k) => v * col[3] * op + bg[k] * (1 - col[3] * op)) : null;
    texts.push({ px, cr: fg ? ratio(fg, bg) : null, t: n.textContent.trim().slice(0, 30) }); }
  const taps = [...document.querySelectorAll('a[href],button,summary,select,input,[role=button],[tabindex]:not([tabindex="-1"]),[onclick]')].filter(vis).map(e => { const r = e.getBoundingClientRect(); return { w: r.width, h: r.height }; });
  const out = { ancho: innerWidth, textos: texts.length, bajo11px: texts.filter(t => t.px < 10.95).length, bajo9px: texts.filter(t => t.px < 9).length,
    minPx: +Math.min(...texts.map(t => t.px)).toFixed(1), contrasteBajo45: texts.filter(t => t.cr && t.cr < 4.5 && t.cr > 1.3 && t.px < 18.5).length,
    controles: taps.length, bajo44: taps.filter(t => t.w < 44 || t.h < 44).length, bajo24: taps.filter(t => t.w < 24 || t.h < 24).length,
    altoPagina: document.documentElement.scrollHeight, pantallas: +(document.documentElement.scrollHeight / innerHeight).toFixed(1), desborde: document.documentElement.scrollWidth > innerWidth };
  console.table(out); return out;
})();
```

Linea base medida el 10-nov-2026 con este mismo snippet:

| Caso | textos | bajo11px | bajo9px | minPx | contrasteBajo45 | controles | bajo44 | bajo24 | altoPagina |
|---|---|---|---|---|---|---|---|---|---|
| 1440 oscuro | 620 | 305 | 6 | 8,3 | 238 | 64 | 44 | 27 | 6.800 |
| 1440 claro | 620 | 305 | 6 | 8,3 | 289 | 64 | 44 | 27 | 6.800 |
| 390 oscuro | 564 | 274 | 46 | 5,6 | 209 | 60 | 48 | 33 | 10.649 |
| 390 claro | 564 | 274 | 46 | 5,6 | 261 | 60 | 48 | 33 | 10.649 |

## 9. Limites de esta auditoria

- Se uso el **snapshot de ejemplo** (2 bodas en la mesa, 6 en el historial). Con mas bodas activas, nombres mas
  largos o una boda sin etapas terminadas pueden aparecer cortes que aqui no se vieron.
- No se probo en un iPhone fisico: la app instalada, la barra de estado (M6), el area segura y el tacto real
  quedan por confirmar.
- No se auditaron el sprint en marcha, las ventanas emergentes del sprint, la ventana flotante del Mac ni los
  widgets de Scriptable y SwiftBar.
- En el escritorio se recomienda 44 px solo para tactil; con cursor bastan 24-32 px.
