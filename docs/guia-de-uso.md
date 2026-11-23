# 📊 Hub de Edición — Dashboard de Bodas ("Sala de Corte")

Tus métricas de edición de bodas, alimentadas desde Notion (workspace **Trabajo**), y un
**sprint de enfoque** que registra tus sesiones en Notion. Vive en dos lugares con el mismo
`index.html`:

- **Local (Mac)** — `server.py` lee Notion en vivo en <http://localhost:4599>. Es la versión
  de trabajo y respaldo.
- **Nube** — <https://hub-edicion.pages.dev>, funciona con la Mac apagada. Sus datos se
  actualizan **en ~3 min tras cada sesión que registras** y cada 15 min mientras la Mac está
  encendida (y, con la Mac apagada, cuando
  GitHub corre su horario de respaldo: en la práctica cada pocas horas).
  Es la que usan el iPhone y su widget. Ver [`cloud/README.md`](../README.md).

Al abrir, el tablero aparece al instante con **tu última lectura** (la guarda el propio
navegador/iPhone) y en una fracción de segundo se confirma **EN VIVO**. La primera vez en un
dispositivo nuevo, o si abres `index.html` sin servidor, muestra el **snapshot** embebido
(sello SNAPSHOT), que son **datos de ejemplo** (parejas inventadas): el repo de la nube es público.
Todo usa solo Python 3 (ya instalado en tu Mac). No hay que instalar nada.

📐 **Cómo está construido** (datos, endpoints, módulos, reglas, mantenimiento):
[`docs/arquitectura.md`](arquitectura.md).

---

## ⚙️ Configurar el token (una sola vez, ~5 min)

Para leer Notion en vivo se necesita un *token de integración*. **Tu token nunca vive en
el HTML** — se guarda aparte, en tu Mac.

1. **Crea la integración**: entra a <https://www.notion.so/my-integrations> →
   *New integration* → tipo **Internal** → nombre p. ej. `Dashboard Edición` →
   workspace **Trabajo** → *Submit*. Copia el **Internal Integration Secret**
   (empieza con `ntn_` o `secret_`).

2. **Dale acceso a tus datos**: en Notion abre la página que contiene tus proyectos de
   trabajo (la de la base **Trabajo**) → menú **•••** arriba a la derecha →
   *Connections* / *Conexiones* → *Connect to* → elige tu integración. Eso le da
   acceso a esa página y todo lo que cuelga de ella. La integración necesita leer y
   **insertar/actualizar contenido** (el sprint crea sesiones y cambia estados).

3. **Guarda el token en tu Mac**: abre **Terminal** y pega esto (reemplaza el texto por
   tu token):
   ```bash
   printf '%s' 'PEGA_AQUI_TU_TOKEN' > ~/.notion-dashboard-token && chmod 600 ~/.notion-dashboard-token
   ```

4. **Prueba que todo conecta**:
   ```bash
   python3 ~/HubEdicion/server.py --check
   ```
   Debe decir *"Conexión a Notion OK"* y listar tus bodas activas.

---

## ▶️ Usarlo (a diario)

El servidor **arranca solo al iniciar sesión** y vive en segundo plano (servicio launchd
ya instalado). Tu flujo es: **clic en "Hub de Edición" en el Dock**. Eso es todo.

- **↻** (arriba a la derecha) → trae los datos más recientes de Notion. Al volver a la app
  después de un rato se refresca sola.
- Arriba a la derecha verás **EN VIVO** con la hora de la última lectura.
- `start.command` queda como respaldo: si el servidor ya corre, solo abre la app; si no,
  lo levanta.

> ⚠️ Esta carpeta vive en **`~/HubEdicion`** (no en Documentos) a propósito: macOS no
> permite que los servicios en segundo plano lean la carpeta Documentos (error
> *Operation not permitted*). Hay un acceso directo en `~/Documents/Claude/HubEdicion` para verla desde ahí.
> No muevas la carpeta de vuelta a Documentos.

### Usarlo como app (Mac y iPhone)

- **Mac**: abre <http://localhost:4599> en **Safari** → menú **Archivo → Añadir al Dock**.
  Queda como app con su propio ícono y ventana.
  - La franja de arriba (la de los tres botones de la ventana) la pone macOS y es
    translúcida. La cabecera «Tú / Hoy» usa el mismo vidrio oscuro, para que arriba se vea
    una sola franja y no dos transparencias distintas (3-nov-2026).
- **iPhone**: abre <https://hub-edicion.pages.dev> en Safari (login con PIN por correo) →
  **Compartir** → **Añadir a pantalla de inicio**. Funciona desde cualquier lugar.
  - (Desde el 9-nov-2026 el server del Mac solo atiende al propio Mac: la dirección
    `jordis-macbook-pro.local:4599` desde otro aparato de la Wi-Fi ya no responde. Antes cualquiera
    en la misma red podía leer tus datos o registrar sesiones. Para volver atrás: en `server.py`,
    última línea de `main()`, cambiar `127.0.0.1` por `0.0.0.0`.)

### Auto-arranque (YA INSTALADO)
El servicio launchd ya está activo. Para gestionarlo:
```bash
# Reinstalar / reactivar (usa bootstrap, NO load — 'load' da "Input/output error" en macOS nuevo):
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.jordi.hub-edicion.plist
# Detenerlo / quitarlo:
launchctl bootout gui/$(id -u)/com.jordi.hub-edicion
# Reiniciar tras cambios en server.py:
launchctl kickstart -k gui/$(id -u)/com.jordi.hub-edicion
```

---

## Qué muestra

Rediseño **"Sala de Corte"** (jul 2026) con la identidad **A · Difusión** (oct 2026): una sola
vista con scroll. Siete secciones, cada una con su acento de la paleta Pantone: **Carrera · Hoy ·
Ritmo · Sesiones · Proyectos · Tarifa · Historial** (Historial desde el 9-nov-2026).

- **Sidebar** (escritorio ≥1024 px), se pliega a un riel de iconos con el botón de su borde y
  recuerda cómo lo dejaste:
  - marca (pistas de timeline con playhead lima, el mismo dibujo que el icono de la app en el
    Dock y en el iPhone) y el sello EN VIVO;
  - un saludo con tu avance del día;
  - las secciones en dos grupos (**Tú** · **Bodas**), cada una con su dato vivo al lado;
  - **En la mesa**: tus bodas con su avance por etapas (tocar una la abre en Proyectos) y el
    **Archivo**;
  - abajo, el **sprint siempre a mano**: espejo de la tarjeta de Hoy, su botón es el mismo.
- **Barra superior fija** que dice en qué sección estás.
- **Móvil / tablet:** barra flotante de secciones **solo con iconos** (compacta, 52 px de alto; la sección activa se marca con una pastilla de su color, 1-nov); en móvil, «Horas por día» usa la misma geometría que «Horas × día de la semana» (380×240, barras al 60 %, meta como tick «5h» a la izquierda); la **Intensidad diaria** muestra solo columnas enteras (ancho visible ajustado a semanas completas, centrado, scroll que encaja por columna y aro de «hoy» por dentro); **La cinta** más baja: 52 px en escritorio (70 %) y 44 px en móvil (60 %), con la aguja de «ahora» proporcional; en **Tarifa** (fila de 4 en escritorio) las cifras de $/hora, $/escena y h/escena crecen (~57 px, escalan con el ancho) y quedan centradas con la comparación al pie; el número del centro del donut «Horas y $ por etapa» es 15 % más chico (37 en vez de 44); **Ahorro por etapa** con escala calibrada: el cero cae según lo ganado vs lo perdido y a cada lado se reserva el ancho de su rótulo más largo, así ningún «+13 h» toca el borde (barras de 14 px y filas compactas en móvil); **prosa en mono**: frases, descripciones de sección, notas, leyendas y pie usan la mono del sistema (`--f-t`, SF Mono regular) como la leyenda del widget del iPhone y un botón redondo con el reloj del sprint.
- **Materiales:** el lima funciona como luz, no como pintura.
  - Vidrio ahumado y grano de película solo en los materiales, nunca encima de los datos.
    El grano está al 50 % (30-oct); su intensidad se ajusta con una sola perilla, `--grain-k` en `index.html`.
  - Halo suave en lo importante: curva, récord y hoy, el donut, las cifras clave.
  - Una luz ambiente que toma el color de la sección en la que estás.
  - Cifras y titulares en Archivo Light.
- **Iconografía certera:** un objeto real por sección.
  - Carrera = bandera a cuadros
  - Hoy = calendario
  - Ritmo = metrónomo
  - Sesiones = reloj de arena
  - Proyectos = claqueta
  - Tarifa = etiqueta de precio
  - Historial = reloj que regresa
- **Tema Auto / claro / oscuro** con un botón que se recorre al tocarlo: ◐ Auto → ☀ Claro → ☾ Oscuro.
  **Auto** (12-nov) sigue el aspecto de la Mac o del iPhone y cambia al momento; recuerda tu elección. El lienzo es oscuro OLED o
  claro *Cloud Dancer*; en claro, los halos casi desaparecen.
- **Interfaz viva:** micro-interacciones al cursor (tarjetas que se elevan, barra señalada que
  crece, centro del donut reactivo) y animaciones al hacer scroll. Todo respeta
  `prefers-reduced-motion`.

**Movimiento:** cada pieza (titular, tarjeta, tile) entra por separado y en cascada al aparecer
en pantalla; al salir del todo **se rearma** y vuelve a entrar al regresar, desde la dirección
por la que vuelves (bajando sube, subiendo baja). Las gráficas se redibujan en cada entrada
(barras, heatmap, curva de la Carrera, cinta). En los **paneles tipo lista** (Etapas, leyenda
del donut, Proyectos, Plan de hoy, Ahorro por etapa) la tarjeta solo se desvanece y las filas
entran **de izquierda a derecha** con un desvanecido suave. Al **elegir una boda** el donut entra
girando, segmento a segmento, y etapas, leyenda y cinta entran igual, de izquierda a derecha.
Las tablas "Ver los datos" y el Archivo se despliegan fila a fila del mismo modo. Botones, filas y navegación tienen presión sutil al
tocar (también en el iPhone).

**Jerarquía tipográfica:** los títulos de **sección** van en la display (Archivo) grande;
los de **tarjeta** en mono con tracking (JetBrains Mono, gris, mayúsculas) — mismo estilo de
etiqueta que los subtítulos, para un look uniforme y minimalista. Nombres al grano ("Duración
de sesiones", "Intensidad diaria"…), sin títulos poéticos.

**Todos los números salen de tus datos reales** (mismo payload de `/api/data`): una capa
`deriveModel()` en el navegador convierte las bodas/etapas/sesiones de Notion en cada gráfica.
Sin datos hardcodeados — cuando entra una boda nueva o editas una sesión, el tablero se adapta
solo. Arriba a la derecha: **↻** (actualiza desde Notion) y el sello **EN VIVO / SNAPSHOT**.

### Trazo de las gráficas de línea (9-nov-2026)
Todas las gráficas de línea (Carrera, Historial · Progreso, Historial · Carrera de todas y el
salto de Tarifa) comparten **un solo trazo**:
- **Curva** suave y continua, sin picos, «con ritmo»: deja ver tus días fuertes y tus pausas.
- **Grosor** por jerarquía: protagonista 2,75 · comparación 2 · contexto 1,5; puntas redondas.
- **Puntos**: anillo = hito (edición lista, cada boda) · lleno = la elegida, tu mejor marca o «ahora».
- **Guías punteadas** (rejilla de valores, promedio, meta, bajada al eje) en todas las gráficas,
  también en las de barras; el eje 0 sigue sólido. Lo que no cuenta (cambios, boda en curso) va punteado.
- En la Carrera, al pasar el cursor aparece un anillo sobre cada curva en ese día.
- En *Horas por día*, la guía de meta se abre donde la cruza la cifra de una barra.
Los datos no cambian: solo cómo se trazan. Elegido por Jordi sobre un A/B
(`docs/propuestas/trazo/`); respaldo previo en `docs/historico/index.pre-trazo.2026-11-09.html`.

### Auditoría de diseño: legibilidad y móvil (10-nov-2026)
Pasada de legibilidad sobre todo el tablero (guía: `docs/propuestas/auditoria-diseno-2026-11-10.md`).
Los datos y cálculos no cambian.
- **Letra mínima de 11 px** en todo el tablero (antes había textos de 5,6 px en el iPhone) y el
  **gris tenue más claro** (todo el texto llega a 4,5:1 de contraste, en oscuro y en claro).
- **Gráficas de barras a tamaño real en el iPhone** (Hora del día, Día de la semana, Duración de
  sesiones, Horas por día): ya no se encogen; la de horas rotula cada 4 h en pantallas angostas.
- **Color con significado**: un cambio se pinta por su signo, no por su lugar. **Lima = mejora,
  violeta = empeora** (titular de la Carrera, tiles, Tarifa). El naranja queda para estados (EN CURSO,
  EN ESPERA, GUARDADO), la fase Cambios y el récord de la semana.
- **Tema claro**: barras, dona, cinta y sidebar con colores que se distinguen sobre blanco.
- **Proyectos**: cada etapa aparece **una sola vez**. La lista de Etapas lleva estado, horas, $ y %;
  bajo la dona va el **resumen por fase** (los totales que antes estaban al pie de La cinta). Pasar
  por un segmento resalta su etapa y viceversa. En el iPhone, las fases completas arrancan plegadas.
- **Historial**: en el iPhone muestra las 3 bodas más recientes y un botón «Ver las N bodas».
  *Carrera de todas*: cada curva lleva su nombre al final y la leyenda se recorre con el teclado.
- **iPhone**: botones y selectores con área táctil de 44 px; **cabecera fija** que dice en qué sección
  estás; Insight en dos filas; etiquetas de las cifras en una línea; el botón flotante del sprint
  muestra ▶ en reposo.
- **Escritorio**: el marcador del sidebar ya no pisa el dato; con la tarjeta del sprint a la vista, el
  botón del sidebar pasa a contorno (un solo botón lima); en ventanas bajas el sprint del sidebar va
  en una fila; «Etapa activa» vacía dice «Sin etapa» y abre el destino del sprint.
- **Tema**: la primera vez sigue el del sistema; la barra del navegador toma el color del tema.
- Formato de horas: exactas `4h 14m`, agregados `20,3 h`, menos de 6 min `N min`.
Respaldo previo: `docs/historico/index.pre-auditoria.2026-11-10.html`.

### Entregables de cada boda (20-nov-2026)
La propiedad **Entregables** de la base Trabajo en Notion (*Teaser* · *DCT + SF/HL* · *Completo*)
dice qué lleva cada boda, y el dashboard la respeta: chip **SOLO TEASER** / **TEASER**, el teaser del
Historial y la frase de «vs tu yo anterior» (si las dos bodas tienen entregables distintos dice
«Una es solo teaser y la otra completa…» en vez de comparar días). Una boda solo de teaser cuenta
siempre como de 1 día. Si Entregables está vacío, se deduce como antes: fase TEAS = teaser y escena
«Día 1…» = boda de 2 días. El archivo guarda el valor de las bodas que ya salieron del tablero.

### Selectores segmentados (10-nov-2026)
Los cinco selectores (*Tablero / Historial* en Tu ritmo y Duración, *Sin / Con teaser* en Horas
acumuladas y Boda con boda, y el de Progreso) siguen un solo sistema (CSS «SELECTORES SEGMENTADOS»):
- **Píldora compacta de 28 px** en todos los tamaños; en el iPhone el área táctil sigue en 44 px con un
  margen invisible (lo visible no crece).
- **Siempre en el renglón del título, a la derecha.** Si el encabezado es angosto (iPhone, columna de
  tableta) se abrevia en vez de bajar de línea: HISTORIAL → **HIST.**, «Sin teaser · Con teaser» →
  **TEASER [SIN | CON]**, «Duración de sesiones» → **Duración**, y «6 TERMINADAS» baja bajo el título.
  Se decide por el ancho de cada encabezado, no por el de la pantalla. En escritorio, textos completos.
- En Horas acumuladas hay 16 px entre el selector y las pastillas de las bodas.
- El de Progreso desliza en horizontal: su área táctil no sale de la píldora (si saliera, también
  deslizaría en vertical).
Respaldo previo: `docs/historico/index.pre-selectores.2026-11-10.html`. Propuestas y capturas en
`docs/propuestas/selectores/`.

### Carrera (hero)
Tu **última boda con edición terminada** corre contra el **fantasma** de la anterior.
Una boda cuenta como *terminada* solo cuando **todas sus etapas de edición están completas, salvo
Cambios** (que es una sesión global de ajustes y no decide nada). Mientras te quede alguna etapa
sin cerrar — aunque aún no la hayas iniciado, p. ej. Montaje HL/SF — la boda sigue **EN CURSO**:
no entra a la Carrera ni a las métricas finales. Si en Notion la marcas *Finalizadas* o
*Correcciones*, se toma como entregada aunque falte una etapa.
- **Arriba:** el titular cuenta las dos caras ("+5 días, −18,9 h vs tu yo anterior"), un
  resumen en una frase y **tres tiles** (horas de edición, horas por escena y día de "edición
  lista" vs el del fantasma). Bajo 1100 px los tiles pasan debajo del titular.
- **Debajo, a todo lo ancho:** la tarjeta *Horas acumuladas* — la curva día a día de ambas
  bodas, con trazo **suavizado** en curvas amplias, sin tirones (guía visual; las cifras exactas siguen en tooltip y tabla). Se dibuja al **tamaño real** de la pantalla (líneas y textos con el mismo grosor a
  cualquier ancho y se redibuja al cambiar el tamaño de la ventana). "Edición lista" = punto en
  la curva + **pastilla en el eje** (D28 / D33) con la **franja de diferencia** entre ambas; lo
  que sigue (Cambios) va **punteado**. Los nombres van al final de cada curva (en móvil, como
  pastillas arriba). Crosshair al pasar el cursor y tabla en "Ver los datos".
- **Se abre y se cierra (18-nov-2026):** *Horas acumuladas* arranca **cerrada**, como un renglón con el
  título, las dos bodas y el resumen (−7 días · 64,3 h vs 53,4 h; en pantallas angostas, solo los días).
  Toda la cabecera abre y cierra; el selector Sin/Con teaser solo aparece abierta y tocarlo no la cierra.
  Cada aparato recuerda cómo la dejaste. Al abrir, el trazo se vuelve a dibujar. Respaldo previo:
  `docs/historico/index.pre-horas-desplegable.2026-11-18.html`; capturas en `docs/propuestas/horas-desplegable/`.
- Con más bodas, el fantasma será la **mediana de tu historial** (pendiente).

El fantasma **no se pierde cuando una boda sale del tablero** (45 días sin cambios): el archivo
histórico guarda una versión compacta de cada boda entregada y el dashboard la reconstruye.

### Hoy
- **Acomodo (7-nov-2026, «reacomodo B»):** fila 1 = el **sprint** (1/3) junto a las **seis cifras**
  en 3×2 (hoy vs meta, sesiones, racha de meta, etapa activa, horas de los últimos 7 días, días
  activos); miden lo mismo de alto. Fila 2 = **Horas por día** (3/4) junto al **Plan de hoy** (1/4).
  En tableta el sprint va a todo lo ancho en una sola franja; en el iPhone, sprint → cifras de dos
  en dos → plan → semana. El *Insight* pasó a **Tus sesiones** (ver ADN).
- **Sprint de enfoque**: cada bloque de foco = **una sesión registrada de verdad en Notion**.
  - **Tarjeta compacta (7-nov-2026):** mismo vidrio oscuro que el sprint del sidebar, reloj en lima
    (Archivo Light) y botón lima. A la vista solo: reloj · **destino** (etapa, tipo y escena) · botón.
    Lo demás va plegado en ventanas emergentes que se abren al tocar y se cierran al tocar fuera,
    con Esc o al elegir: **chip del esquema** arriba (p. ej. «LIBRE ▾»: esquemas, ciclo dibujado y
    *Editar tiempos*; tocar el reloj también lo abre), **destino ▾** junto al reloj (etapa, escena,
    Edición/Gestión) y **⋯** junto a TERMINAR, solo con bloque o descanso (Pausa · Escena · Etapa
    y *Descartar sin registrar* / *Terminar ciclo*). Con el bloque en marcha el destino se vuelve la
    etiqueta fija de lo que se registra. La **ventana flotante** conserva su tarjeta lima de siempre.
  - **Destino:** eliges **etapa** (agrupadas *En curso* / *Por empezar*, sin las terminadas;
    la última trabajada primero), **escena** (agrupadas *En curso* / *Por hacer* / *Terminadas*;
    propone la de tu última sesión si no está terminada, si no la siguiente) y **tipo**
    (Edición / Gestión). Se recuerdan para el siguiente.
  - **Esquemas**, cada botón con sus tiempos a la vista (foco/descanso):
    - *Mediana* (tu sesión típica, sin descanso fijo)
    - *Pomodoro 25/5* (uno largo de 15 cada 4)
    - *52/17*
    - *Profundo 90/20*
    - *Libre* (cronómetro sin meta)
    - *Propio*: tus minutos. Tocas el reloj o **Editar tiempos**, eliges foco y descanso y
      se guarda como *Propio*; el esquema de origen no cambia.

    Bajo los botones, el **ciclo dibujado**: bloques de foco con sus minutos y los descansos
    como huecos. El bloque en curso queda marcado. Se recuerda el esquema.
  - **Ciclo:** al terminar un bloque se registra y arranca el **descanso** (no se registra);
    luego "Empezar bloque N" (en el descanso puedes cambiar de escena). "Terminar ciclo" lo
    reinicia; tras 3 h sin bloques empieza uno nuevo. Aviso sonoro suave al cumplir el bloque
    y al acabar el descanso; el tiempo se ve en el título de la pestaña.
  - **Reloj real:** guarda la hora de inicio (no se congela si bloqueas el iPhone o cierras la
    app; al pasar de la meta cuenta el tiempo extra). La **duración se redondea al minuto más
    cercano** (30 s o más sube; Fin = Inicio + duración), porque Notion cuenta en minutos;
    menos de 30 s no se registra.
  - **Registro:** igual que el manual — título "Sesión", Inicio, Fin, Tipo, Escena y **Total**
    (fila *Edición*/*Gestión* de "Tiempo total" de la etapa). **Entiende los estados:** si la
    etapa o la escena estaban sin iniciar, pasan a **En proceso** y se llena su fecha de inicio
    vacía (etapa: "Del → Al"; escena: "Inicio"); nunca retrocede algo en proceso o terminado.
  - **Sin internet no se pierde nada (Mac, nov-2026):** `server.py` guarda **primero en el Mac**
    cada sesión y cada cierre de escena/etapa (archivo `.outbox.json`; sobrevive a cerrar la app
    o reiniciar) y luego los sube. Sin internet la tarjeta dice *✓ Guardada en el Mac* —sin
    preguntarte nada— y caben todas las sesiones seguidas que hagas. Al volver la red se suben
    **solas y en orden** (la sesión antes que su cierre): al instante si la app del reloj está
    abierta (detecta la red y el despertar del Mac), si no en ≤ 2 min. Cada una sale de la cola
    solo cuando Notion confirma; si un envío se corta a medias, no se duplica. Mientras esperan
    verás **☁︎↑ y el número** en el reloj de la barra (en reposo) y una línea discreta en la
    tarjeta; al subirse, *✓ Subido a Notion a las HH:MM*. En el menú del reloj: **Subir ahora**.
  - **Si Notion lo rechaza** (no es la red: p. ej. la etapa ya no existe), queda *Sin
    registrar* en el dispositivo con **Reintentar** / **Descartar**, en lista (dos fallos
    seguidos ya no se pisan). En la nube escribe la Pages Function (directo si tiene
    `NOTION_TOKEN`; si no, en cola y el publicador lo pasa a Notion en la siguiente
    actualización, ≤15 min con la Mac encendida).
  - **Cerrar escena / etapa al terminar:** mientras corre el sprint, en **⋯** junto a TERMINAR
    (en la ventana flotante, encima de TERMINAR) hay una escalera **Pausa · Escena · Etapa** (empieza siempre en *Pausa*). *Escena* cierra la escena;
    *Etapa* cierra la escena **y** la etapa. Lo que se va a cerrar se marca en su nombre (tinta
    invertida) y el botón lleva una etiqueta pequeña (`+ ESCENA` / `+ ETAPA`) sin crecer. Al
    terminar: Estado → 🟢 y su fecha de fin vacía (escena: "Fin" con hora; etapa: final de
    "Del → Al"). Tienes **8 s para Deshacer** antes de que se escriba en Notion, y el siguiente
    sprint ya te propone la **siguiente escena** (o la **siguiente etapa** de esa boda con su
    primera escena). Si falla, queda *Reintentar / Descartar*.
  - **Ventana flotante (Mac):** el botón ⤢ en la esquina de la tarjeta saca el sprint a una
    ventanita propia, **siempre encima** de todo (también de Premiere/Resolve en pantalla
    completa y en todos los escritorios). La arrastras desde **cualquier zona sin botones**, la
    redimensionas desde los bordes y recuerda dónde la dejaste. En *Opciones* puedes fijarla
    **en el escritorio** (detrás de las ventanas, como un widget) en vez de siempre encima. Es la **misma tarjeta**:
    destino, esquemas, Ajustar, iniciar/terminar, cierre de escena/etapa, descanso, pendientes.
    Se reacomoda según la forma: **vertical** (destino arriba, reloj al centro, acción abajo),
    **apaisada** (destino a la izquierda; reloj y acción a la derecha) y **franja** baja y
    ancha (todo en una fila). Si falta alto se guardan piezas (texto → esquemas → destino) y
    al mínimo queda reloj + escalera + botón.
    El sprint en curso es **uno solo**: lo que hagas en la ventana o en el dashboard se ve en
    el otro en ~1,5 s (la tarjeta del dashboard marca el botón mientras la ventana está
    abierta y entonces solo suena la ventana). En la ventana: ⤡ vuelve al dashboard, ✕ la
    oculta (⌘W también). Es la app `~/Applications/Sprint flotante.app` (también se abre
    desde Spotlight); solo funciona en local (necesita `server.py`). Código y compilación en
    `mac/SprintFlotante/` (`./build.sh`).
  - **Barra de menús (Mac):** la misma app deja un **reloj** arriba: lo que llevas del bloque
    (o lo que falta, en *Opciones*), ☕ con la cuenta del descanso, 🏁 al pasar la meta y ⚠︎ si
    algo quedó sin registrar. Su menú hace lo mismo que la tarjeta sin abrirla: **Terminar /
    Terminar y cerrar la escena / … y la etapa / Descartar**, *Empezar bloque* o *Terminar
    ciclo* en el descanso, *Iniciar sprint* hacia el destino propuesto y *Deshacer* durante
    los 8 s del cierre. En reposo y en el descanso, **Etapa: … ▸** y **Escena: … ▸** dejan
    elegir hacia dónde va el próximo bloque: las mismas listas que la ventana (En curso / Por
    hacer / Terminadas), con ✓ en la actual, y elegir ahí es lo mismo que elegir en la ventana
    (se ve al momento en la ventana y en el dashboard). Con un bloque en marcha no aparecen,
    igual que en la ventana: la sesión se registra con la etapa y escena con las que empezó.
    «Sin escena» elegida a propósito se respeta en todas las vistas. Entre Escena y Esquema,
    **Tipo: … ▸** (Edición / Gestión, con ✓): igual que los dos botones de la ventana; se guarda
    y se ve al momento en la ventana y en el dashboard, y aparece en reposo y en el descanso
    (con un bloque en marcha no: ese bloque conserva el tipo con el que empezó, que se ve en la
    primera línea del menú). En reposo también está
    **Esquema: … ▸** (Mediana, Pomodoro, 52/17, Profundo, Libre, Propio, con sus tiempos): igual
    que tocar el botón en la ventana; *Propio* usa tus minutos guardados (se cambian en la
    ventana, con *Editar tiempos*). En el descanso no aparece, como en la ventana. También muestra/oculta la ventana y abre el dashboard. Cerrar la
    ventana no cierra la app (sigue el reloj); *Salir* o ⌘Q sí. Se abre sola al iniciar sesión
    (se quita en *Opciones*). El aviso de meta/descanso lo da el Mac (con la ventana visible u
    oculta).
  - **Sonidos (Mac):** *Opciones → Sonidos* elige qué suena en cada acción: **Iniciar** (de
    serie *Tink*), **Terminar** (*Hero*), **Descartar** (*Funk*), **Meta y fin del descanso**
    (*Glass*), **Cambiar Edición/Gestión** (*Pop*) y **No se pudo** (el aviso del sistema). Cada una ofrece *Ninguno*, el aviso del
    sistema y los sonidos de macOS (más los que pongas en `~/Library/Sounds`). Al pasar por un
    sonido del menú suena; al elegirlo se guarda. *Restablecer los de serie* vuelve a los de
    fábrica. Valen para los atajos, Siri y el menú (el menú solo suena si algo falla).
  - **Atajos de teclado (Mac, globales):** funcionan con cualquier app al frente (Final Cut
    incluido). **⌃⌥N** inicia el sprint o, si ya corre, lo **termina y registra** en Notion
    (desde el descanso empieza el bloque siguiente). **⌃⌥⇧N** lo **descarta** sin registrar.
    **⌃⌥⌘N** muestra u oculta la ventana flotante (sin quitarle el foco a la app que usas).
    **⌃⌥B** alterna el tipo de sesión **Edición ↔ Gestión** (lo mismo que elegirlo en *Tipo ▸*
    del menú o en los dos botones de la ventana; se ve al momento en la ventana y en el
    dashboard). Funciona en reposo y en el descanso; **con un bloque en marcha no hace nada**
    (suena *No se pudo*): ese bloque conserva el tipo con el que empezó, así la sesión que se
    registra en Notion no se parte. Confirmación discreta: el reloj de la barra muestra 2 s el
    tipo que quedó («Edición» con tijeras, «Gestión» con carpeta) y suena el sonido *Cambiar
    Edición/Gestión* (de serie *Pop*): **un toque = Edición, dos toques = Gestión**. En el menú
    del reloj aparece junto a *Tipo ▸* como «Cambiar a «Gestión»» con su atajo. Final Cut no usa
    ⌃⌥B (sí ⌥B, ⌘B, ⌥⌘B…); lleva siempre los mismos ⌃⌥ que el atajo principal.
    Al pulsarlos suena un aviso y el reloj de la barra destella (▶ / ✓ / ✕); el sonido de
    *No se pudo* (de serie, el pitido del sistema) = no había nada que hacer. Los sonidos se
    eligen en *Opciones → Sonidos*. Se cambian en *Opciones → Atajo de teclado* (⌃⌥B, ⌃⌥P, ⌃⌥J, ⌃⌥K,
    *Grabar otro…* o *Sin atajo*): eliges la tecla base y ⇧ (descartar) y ⌘ (ventana) se añaden
    solos; el de Edición/Gestión sigue a la tecla base con la letra B (si eliges B como base, usa la N).
    El menú muestra cada atajo junto a su acción.
    Se eligió N porque Final Cut ya usa ⌃⌥S (componentes de audio) y ⌃⌥T (rol Títulos).
  - **Siri (Mac):** *"Oye Siri, iniciamos"* arranca un bloque con el esquema y la etapa que
    ya tengas elegidos; *"Oye Siri, terminamos"* lo termina y registra en Notion. Una sola
    palabra que no se parece a nada de Siri ("sprint" lo entendía mal y "nueva sesión" lo tomaba
    por un evento del calendario y preguntaba la fecha). Mismo aviso que el atajo (sonido + destello;
    pitido si ya corría / no había bloque). Son dos Atajos (app Atajos) que abren
    `hubsprint://start` y `hubsprint://finish`; también existe `hubsprint://toggle` (= ⌃⌥N).
    Funciona aunque la app esté cerrada (la abre). **Activarlo (una vez):** doble clic en
    `mac/Siri/Iniciamos.shortcut` y en `Terminamos.shortcut` → *Añadir atajo*. El
    nombre del atajo es la frase; si Siri no lo pilla, renómbralo en Atajos. Regenerarlos:
    `python3 mac/Siri/make-shortcuts.py`. **iPhone: no** (el sprint de la nube no se
    sincroniza y un Atajo no puede abrir la PWA, solo Safari).
- **Plan de hoy**: generado de tu patrón (descanso en domingo, tu ventana de oro, la boda en curso).
- **Horas por día** (últimos 7) contra tu meta (**5 h L–V · 2 h Sáb · Dom descanso**), con **previos en violeta, récord en naranja y hoy en verde**; la guía de meta sigue la meta real de cada día de la ventana móvil. En escritorio se dibuja **a escala real** (el ancho del dibujo = el de la tarjeta, alto fijo): al ensancharse gana aire a los lados, nunca crece de alto; se redibuja al plegar el sidebar.
- **Cifras del día** (hoy vs meta, sesiones, racha, etapa activa) y de la semana (horas de los
  últimos 7 días, días activos), todas de 100 px de alto en el bloque 3×2.
- **Las sesiones de Cambios/Correcciones cuentan como tiempo trabajado** en todo HOY y Ritmo
  (horas por día — con desglose "en cambios" en el tooltip —, tiles, racha, heatmap, cronotipo,
  histograma de sesiones). Siguen **excluidas** de las *horas efectivas de edición* (Carrera,
  ahorro por etapa, $/h) porque dependen de terceros.

### Ritmo (tu cronotipo)
- Botón **Tablero / Historial** (9-nov-2026) junto al título, y también en *Duración de sesiones*:
  *Tablero* = las sesiones de las bodas que siguen en el tablero (como siempre); *Historial* = las de
  **todas tus bodas medidas** (las archivadas aportan lo guardado en el archivo: minutos por día, por
  hora del día y la duración de cada sesión). Mueve hora del día, día de la semana y duración de
  sesiones; la Intensidad diaria ya incluía todo. Se recuerda en el navegador.
- **Horas × hora del día** con tu **ventana de oro** (el rango de 6 h más denso).
- **Horas × día de la semana** (tu mejor día resaltado).
- **Intensidad diaria**: heatmap anclado a hoy; rellena hacia atrás con semanas previas
  ("aún no medías") hasta llenar la tarjeta, y crece con los años. Incluye el **historial**: los
  minutos por día de las bodas entregadas que ya salieron del tablero (archivo → `ghost`), así que
  no se vacía cuando una boda sale a los 45 días. "Días activos" y "mides desde" usan ese mismo rango.
  Colores: en oscuro, de oliva apagado a lima luminoso; en claro (3-nov-2026), de lima pálido a un
  oliva-lima vivo, con un halo suave en los días más fuertes. Antes, en claro, los días de más trabajo
  se veían casi negros.
- **Barras con degradado** (horas por día, días de la semana, cronotipo…): la luz va arriba y la base se
  desvanece. En claro ese «velo» es un 33 % más suave que en oscuro (3-nov-2026).

### ADN (cómo editas)
- **Duración de sesiones**: histograma; tu mediana es la duración del esquema *Mediana* del sprint.
- **Ahorro por etapa**: en qué etapas exactas le ganaste (o cediste) tiempo a tu boda anterior.
- **Pill de Insight** (p. ej. "editas X % más rápido por escena que en tu boda anterior"): desde el
  7-nov va bajo *Duración de sesiones*, junto a *Ahorro por etapa*, porque resume esa misma comparación.
  Si la lista de etapas crece, *Duración* reparte el aire arriba y abajo de su gráfica (no la agranda).

### Cuadrícula (reacomodo 7-nov-2026)
- **12 columnas** con el mismo gap de 14 px. Cada gráfica va en el ancho donde su texto queda a su
  tamaño de diseño: *Horas × hora del día* 7 col + *día de la semana* 5 col (miden lo mismo de alto);
  *Duración + Insight* 5 + *Ahorro* 7; *Horas y $ por etapa* y *Etapas* mitad y mitad; Tarifa 4 × 1/4.
- **Regla:** solo comparten fila tarjetas de altura natural parecida; si no, se apilan piezas en la
  columna corta. Nunca se estira una tarjeta sola para rellenar.
- Propuesta, criterio y capturas: `docs/propuestas/reacomodo-tarjetas.html` (interruptor Antes · A · B)
  y `docs/capturas/reacomodo-*-2026-11-07.png`. Respaldo previo: `docs/historico/index.pre-reacomodo.2026-11-07.html`.

### Proyectos ("En la mesa") — el selector ES la lista
Una fila por boda **con sesiones medidas**, con etiquetas **TEASER** y **2 DÍAS** cuando aplica;
**tocar una la abre al detalle** (nada de dropdown). Debajo, una fila plegada **"Archivo · N bodas
entregadas"**: las entregadas que llevan 45 días sin cambios salen del tablero (para que la lista no
crezca sin fin) pero siguen aquí, la más reciente primero. Se abren igual (donut y etapas con horas,
sesiones y estado); vienen del archivo histórico, sin consultar Notion. No traen el detalle de
escenas ni cada sesión suelta.
- **Horas y $ por etapa** (donut coloreado por fase, con **$ por etapa** sobre el precio
  cobrado y **centro reactivo**: total exacto en reposo, horas·etapa·$·% al hover).
- **Etapas**: checklist **completo agrupado por fase** (Preparación · Teaser · Documental ·
  HL/SF · Cambios), con el estado real de cada etapa (completado / en curso / pendiente) y sus
  horas — las de menos de 0,1 h se muestran en minutos.
- **La cinta** (cada etapa un clip cuyo ancho = horas reales; lo pendiente rayado con playhead;
  leyenda y totales solo de las fases que tiene esa boda).

### Otros proyectos (no bodas) — 12-nov-2026
Proyectos de la DB **Trabajo** con **Tipo = Proyecto** (freelance, iglesia…; el primero, *Video
Origen Musica*). No usan etapas: solo una tabla **Sesiones** directa en su página (más **Total** y
**Panel de Control**, como una etapa). Se ven en la tarjeta **Otros proyectos** al final de
Proyectos: horas, sesiones, días trabajados, barra **edición (lima) vs gestión (violeta)**, **$/h**
(Total de Notion ÷ todas las horas), cliente y estado.
- **Cuentan en Hoy y Tu ritmo** (horas del día, meta, racha, intensidad, horas del día, duración de
  sesiones, widgets). **No** entran en la carrera, Boda con boda, Historial, Tarifa, dona/etapas ni
  el Archivo: esas siguen siendo solo de bodas.
- **Sprint:** los proyectos sin terminar salen como destino («Proyecto de ejemplo 1 · Freelance»);
  sin escenas ni «cerrar etapa». La app del reloj no necesitó cambios.
- Un proyecto **finalizado** solo se lee si su *Fecha* cae en los últimos 45 días (hay ~50 viejos
  de 2021-2025; así no se gastan peticiones). Aún no se archiva: cuando salga, sus horas dejan de
  verse en Hoy/Ritmo.
- **Para un proyecto nuevo:** en su página, una tabla Sesiones con `Inicio`, `Fin`, `Tipo`
  (Edición/Gestión) y `Total` → relación a una tabla **Total** propia con filas *Edición* y
  *Gestión*. ⚠️ Si copias la tabla Sesiones de una boda, su columna Total sigue apuntando a esa
  boda: el sprint ya no la liga ahí (`total_db_ok`), pero hay que crear un Total propio.

### Tarjetas para Notion (/embed) — publicada 10-nov-2026 (7f6bb7d); 9 tarjetas desde el 11-nov
**Qué tarjetas se pueden pegar** (todas con su botón `</>`):
- **De una boda** (la que tengas abierta en Proyectos): *Horas y $ por etapa* (dona), *Etapas*, *La cinta*.
- **Del tablero entero** (un solo enlace, no dependen de la boda): *Horas por día* (Hoy), *Intensidad diaria*
  (Tu ritmo) y los 4 recuadros de *Tarifa* ($ / hora, $ / escena, h / escena, $ / hora por boda).

La tarjeta **Horas y $ por etapa** de una boda se puede pegar con `/embed` en la página de esa boda en
Notion, como los widgets de reloj y clima. Es el **mismo `index.html`** en modo embebido: solo pinta
esa tarjeta (dona + resumen por fase, centro reactivo), sin sprint, y se actualiza sola al abrir la
página (mismo retraso que el dashboard: ~15 min, o ~20 s tras un sprint).
- **No guarda nada nuevo**: lee los mismos datos de siempre y los recorta a esa boda. Sirve también
  para las bodas del Archivo.
- **Sacar el enlace (11-nov):** botón **`</>`** arriba a la derecha de la tarjeta, en el dashboard.
  Copia el enlace de la boda que tengas abierta («Enlace de … copiado»); en Notion: `/embed` y pegar.
  Si el navegador no deja copiar, muestra el enlace para copiarlo a mano. En el Mac lo calcula
  `server.py` con el archivo `.embed-secret`; en la nube, `/api/embed-link` (tras el PIN).
  El enlace es `https://hub-edicion.pages.dev/embed?boda=<boda>&k=<clave>` (clave propia de cada boda).
- **Se funde con Notion (11-nov):** fondo exacto de Notion (#191919 oscuro · #FFFFFF claro), sin borde,
  sin esquinas redondeadas, sin grano y sin halo en la dona.
- **Tema de los widgets (11-nov):** widget aparte con **☀ | ☾ | ◐** (claro, oscuro, auto; solo símbolos desde el 12-nov) que cambia TODAS las tarjetas a la vez
  (también las de otras páginas). Su enlace se copia con el **`</>`** junto al botón de tema de la barra
  superior del dashboard (`https://hub-edicion.pages.dev/embed?embed=tema`, no lleva clave ni datos).
- **Auto (12-nov):** sin tema elegido, las tarjetas siguen el aspecto del iPhone/Mac **al momento**. Lo usa el
  atajo **«Modo oscuro»** del iPhone (pasa a oscuro/claro el iPhone, los widgets de Scriptable y estas tarjetas;
  la Mac no cambia). Cómo armarlo: [`docs/atajo-modo-oscuro.md`](atajo-modo-oscuro.md).
- **Claro / oscuro de una sola tarjeta:** botón **sol/luna** dentro de la tarjeta (solo cambia esa; se recuerda (vale para
  todas las tarjetas pegadas en Notion). Sin elegir, sigue el tema del sistema.
- **En el Mac** (para probar): `http://localhost:4599/?embed=donut&boda=renata-emilio` (no lleva clave).
- **Ya activado en la nube** (10-nov): secreto `EMBED_SECRET` en Pages + app de Access `hub-embed`
  (Bypass · Everyone) para `/embed` y `/fonts` (ver `cloud/README.md`).
- Tamaño: lo da el recuadro de Notion (arrastra la esquina). Ancho y bajo → dona a la izquierda y
  resumen a la derecha; estrecho → uno sobre otro; muy bajo y estrecho → solo la dona.
- **La tarjeta no se mueve al pasar el cursor (18-nov):** en Notion la tarjeta completa se queda quieta. Las gráficas
  de dentro siguen reaccionando igual (segmentos, textos, centro de la dona). En el dashboard las tarjetas siguen
  levantándose 2 px, como siempre.
- **Scroll de Notion encima de la tarjeta (11-nov):** con el puntero sobre una tarjeta, los dos dedos / la rueda
  mueven la página de Notion (como el reloj y el clima). Las tarjetas ya no tienen scroll propio: si el recuadro
  es más bajo que la tarjeta (p. ej. *Etapas* con muchas filas), lo que no cabe se corta y el borde de abajo se
  desvanece → agranda el recuadro en Notion. *Intensidad diaria* muestra siempre las semanas más recientes.
- **Enlace de plantilla (12-nov):** en la **plantilla de boda** de Notion, los recuadros de la dona y de la cinta
  llevan un marcador que conserva su tamaño y dice «Reemplaza este enlace por el de la boda» (sin datos ni clave):
  - Dona: `https://hub-edicion.pages.dev/embed/plantilla?t=donut`
  - La cinta: `https://hub-edicion.pages.dev/embed/plantilla?t=cinta`
  - Etapas (si algún día va en la plantilla): `https://hub-edicion.pages.dev/embed/plantilla?t=etapas`

  En cada boda nueva: dashboard → abre la boda → `</>` de la tarjeta → en Notion, `···` del recuadro →
  **Reemplazar** → pegar. El recuadro no pierde sus dimensiones. Archivo: `cloud/embed/plantilla.html`
  (vive solo en la nube; `sync-cloud.sh` no lo toca).
- **Una sola propiedad de cliente (13-nov-2026):** en la base Trabajo se borró **«Subcategoría»**, que repetía a
  **«Cliente / Línea»** (esta es más fina: distingue Estudio A de Freelance). El dashboard lee solo Cliente / Línea
  (`studio` de las bodas y `client` de los otros proyectos). Las vistas Board, Tabla y Calendario y la ficha de
  cada página ahora muestran Cliente / Línea. La plantilla «Boda» la deja vacía: elígela al crear la boda. Sigue el interruptor «Tema de los widgets» igual
  que las tarjetas (13-nov): Claro / Oscuro, o **Auto** = el aspecto del sistema, que también cambia en vivo
  sin recargar (atajo del iPhone, anochecer). Fondos #191919 / #FFFFFF.

### Plantilla de Notion: fases (oct-2026)
El *Tracking de Edición* se segmenta en 5 fases (propiedad **Fase**), en este orden:

| Fase | Etapas (plantilla nueva) | Color |
|---|---|---|
| **PREP** · Preparación | Setup · Escenas · Limpieza · Sincronización | azul cielo |
| **TEAS** · Teaser | Selección · Música · Montaje · Color (TEAS) | aqua |
| **DCT** · Documental | Música · Montaje · Color y finalización (DCT) | lima |
| **HL/SF** · Highlights / Short film | Selección · Música · Montaje (HL/SF) | violeta |
| **CMB** · Cambios | Cambios | naranja |

- **Avance %** = etapas hechas / etapas de trabajo (Cambios no cuenta). Varias etapas pueden
  ir **en curso a la vez**: HOY las lista todas (tile "Etapas activas · N").
- **Boda con teaser** = tiene etapas con Fase TEAS. No hace falta otra marca.
- **Teaser modular (13-nov-2026):** la tabla *Tracking de Edición* de la plantilla «Tracking de
  Bodas» tiene 4 **plantillas de etapa** (Selección · Música · Montaje · Color (TEAS)). Cada una trae
  su icono naranja, Fase TEAS, Orden 4.1–4.4, Estado ⚪️ y todo su contenido: Sesiones, Total
  gris/azul, Consola amarilla con sus botones y, en Música, los Spotify. Arriba de la dona está el
  botón **«+ Teaser»**: 4 acciones «Agregar página a Tracking de Edición como <plantilla>». Un clic
  agrega las 4 etapas a **esa** boda. Probado: Notion re-apunta el botón a la tabla de cada boda
  nueva, y las relaciones internas (Sesiones↔Total, botones de la Consola) quedan propias de cada
  etapa. Púlsalo **una sola vez**: dos clics duplican las etapas. Sirve también en bodas ya creadas
  desde esta plantilla. El dashboard y el sprint no necesitaron cambios: reconocen las etapas por
  nombre y Fase, y `total_db_ok` da True.
  - **Trampa:** NO llenes una plantilla de base aplicándole otra página por API
    (`PATCH /pages/<plantilla>` con `template`). Notion la deja a la vez como plantilla y como fila
    visible. Lo que funciona: crearla en la app y **Duplicar** desde el menú ··· de la plantilla
    (la copia queda limpia). Nombre, icono y propiedades sí se pueden poner por API sin problema.
- **Preboda modular (13-nov-2026):** botón **«Preboda»** junto a Teaser. Tiene 25 acciones: en cada
  tabla de escenas (Limpieza, Sincronización, Selección musical, Edición Musical y Corrección de Color)
  crea **Civil · Sesión · F&F · Cóctel · Cena (Pre)**. Son plantillas de base con icono, Orden 0.1–0.5,
  ⚪️ y la columna nueva **Día = Preboda**. `server.py` (raíz y cloud) trata Día = Preboda como «Día 1»,
  así que la boda cuenta como de 2 días. El orden y la lista de escenas se pueden ajustar por boda.
  - **Para módulos futuros:** misma receta. Plantillas de base en la tabla
    que corresponda (para el Día 1, las tablas de Escenas) y un botón con una acción por plantilla.
    Guía completa, paso a paso y con las trampas: `~/Documents/Claude/Notion/botones-modulares-notion.md`
    (solo en la Mac).
- **Boda de 2 días** = alguna escena se llama **"Día 1…"** (el día previo como escena que
  recorre Limpieza → Sincronización → Música → Montaje → Color). Sin etapas duplicadas.
- **Las dos plantillas se comparan entre sí**: cada etapa se reduce a *fase + rol*
  (`roleOf`/`phaseOf` en `deriveModel`): Importación→Setup, Separación→Escenas,
  Musicalización→Música (DCT), Edición Musical→Montaje (DCT), Corrección de color→Color y
  finalización (DCT), Selección de material/musical→Selección/Música (HL/SF). En las bodas
  viejas la preparación (que en Notion era "Documental") se reclasifica como PREP.
- **Comparación justa**: Carrera y el titular comparan solo las fases que **ambas** bodas
  tienen (un teaser que el fantasma no tuvo no cuenta como "ir más lento"; el lede lo dice).
  Cuando una de las dos tiene una fase que la otra no (p. ej. teaser), la tarjeta *Horas
  acumuladas* muestra el selector **Sin teaser / Con teaser** (9-nov-2026): *Con teaser* suma
  también esas horas, y el titular, los tiles, la curva y el valor de la barra lateral cambian
  con él. Se recuerda en el navegador; por defecto, *Sin teaser*. Si las dos bodas son del
  tablero y una fue de 2 días y la otra de 1, el lede lo añade ("Boda de 2 días contra una de 1").
  Ojo: la dona de Proyectos cuenta **todo** (teaser y Cambios incluidos), por eso su total es
  mayor que la cifra de la Carrera.
  **h/escena** excluye siempre el teaser (no tiene escenas); **$/h** sí lo incluye (el precio
  lo cobra).

### Boda de prueba con la arquitectura unificada (12-nov-2026)
En **Trabajo** está **«PRUEBA · Arquitectura nueva»** (Status *Por hacer*), para ver la arquitectura
unificada del Laboratorio en una boda completa: 15 etapas (PREP · TEAS · DCT · HL/SF · CMB, 1 día) y
47 escenas, como **filas** de las 3 bases compartidas del prototipo, ligadas a la boda por la relación *Boda*.
- **El dashboard no la ve, a propósito:** su **Tipo está vacío**. `server.py` solo lee filas con Tipo =
  Boda o Proyecto (*Por hacer* NO excluye una boda). Además, la integración no tiene acceso al Laboratorio.
  Tampoco es destino del sprint. No pongas Tipo = Boda hasta que `server.py` sepa leer este formato (fase 3).
- **Página de la boda:** vistas enlazadas «Etapas de esta boda», «Sesiones de esta boda», «Total de la boda»
  (dona de minutos Edición / Gestión) y «⚠️ Por revisar», más los marcadores `/embed/plantilla` de dona y cinta.
  Las vistas de sesiones filtran por la lista de las 15 etapas: si añades una, súmala al filtro.
- **Cada etapa:** **Consola** = tablero de sus sesiones agrupado por Tipo (Edición azul · Gestión gris).
  **+ Nuevo** en una columna crea la sesión con Etapa y Tipo ya puestos. **Total** = dona. Las etapas por
  escenas (Limpieza, Sincronización, Música/Montaje/Color DCT) llevan además el tablero **Escenas** por estado.
- **Botones:** no se pueden crear por API. La receta para hacerlos a mano (una sola vez en las bases
  compartidas, sirven para todas las bodas) está en la propia página de la boda. Lo mismo vale para lo que
  queda a mano: acomodo en columnas y color condicional amarillo de la Consola.

### Tarifa
Una fila con `$/hora`, `$/escena` y `h/escena` de tu última boda entregada, más **$/hora por boda**
(el salto vs la anterior, de la boda anterior a la actual sobre una regla de $/h). Cada cifra
lleva su cambio en color (lima si mejora, violeta si empeora) y el contexto en gris. Todo sobre
el **precio cobrado** (propiedad *Total* en Notion). *Nota:* el $/h usa **horas efectivas de edición** (excluye correcciones).

### Historial (todas tus bodas, boda con boda) — 9-nov-2026
Todas las bodas con horas medidas (tablero + archivo), de la más vieja a la más nueva. La que
estés editando entra al final con **EN CURSO** y no cuenta en promedios ni récords.
- **Boda con boda**: una fila por boda con *Edición* (horas sin Cambios), *h/escena*, *Lista* (día
  de proyecto en que quedó lista la edición), *$/hora*, *h/día* (horas ÷ días con sesión) y
  *h/semana* (horas ÷ semanas entre la primera y la última sesión). Cada cifra en **lima** si es
  mejor que tu promedio y en **violeta** si es peor (h/día y h/semana sin color: más no es mejor ni
  peor); resaltada, tu **mejor marca**; debajo, el **cambio contra la boda anterior**; al pie, el
  **promedio**. Etiquetas TEASER y 2 DÍAS. En móvil cada boda es un bloque con sus 6 datos.
- **Sin teaser / Con teaser**: el mismo selector de la Carrera (cambiar uno cambia el otro).
  *Sin teaser* = todas cuentan lo mismo (video largo + HL/SF). $/hora (el precio incluye el teaser)
  y h/escena (el teaser no tiene escenas) no cambian.
- **Progreso**: el dato que elijas, boda con boda, con tu promedio (línea punteada), la mejor
  marcada y el cambio contra la anterior en el tooltip. Se recuerda el dato elegido.
- **Carrera de todas**: las curvas de horas acumuladas hasta "edición lista" de todas las bodas;
  las viejas más tenues, la elegida en lima. El cursor realza la curva más cercana; tocar una fila,
  una curva o su nombre la elige en las tres tarjetas.
- Sin precio en Notion (p. ej. Paula + Bruno) el $/h se calcula con $XX,XXX y lleva *.


## Alcance

- **Todas las bodas** (Tipo = Boda) **excepto las finalizadas que llevan inactivas más de
  45 días** (→ `RECENT_DONE_DAYS` en `server.py`), para no perder el tiempo de proyectos
  recién cerrados (p. ej. correcciones post-entrega). **"Inactiva" = sin sesiones**: cuenta la
  última sesión trackeada (guardada en el archivo como `lastActivity`) o el fin del rango
  *Fecha* (la entrega), **no** la fecha de edición de la página. Así una edición masiva en
  Notion no regresa las entregadas al tablero (pasó el 1-nov-2026 con la reestructura, que
  agregó "Cliente / Línea" a todas las filas). Solo si no hay ni sesiones ni *Fecha* se usa
  la fecha de edición. Antes de salir del tablero, las
  finalizadas **con horas trackeadas** dejan sus stats en el **archivo histórico**
  (`.archive.json` → `archive` en el payload) que alimenta el fantasma de la Carrera, el Archivo
  de Proyectos y el heatmap. Se detectan solas desde Notion. Cada boda se reconoce por el **ID de
  su página**, no por el nombre: puedes corregir el título en Notion sin que la boda salga dos
  veces ni se compare contra sí misma (pasó el 20-nov-2026); las tarjetas `/embed` pegadas con el
  nombre anterior siguen funcionando. El
  filtro de "finalizada" se hace en Python contra un conjunto de estados (`DONE_STATUSES`:
  `Finalizadas`, `Hecho`, `Complete`…), así un **renombrado de la opción de Status en
  Notion ya no rompe la consulta** (antes pedía `Status ≠ "Hecho"` y, al desaparecer esa
  opción, Notion devolvía 400 y el tablero caía a 2 bodas de respaldo).
- Soporta proyectos de **solo correcciones** (página con un DB **"Sesiones"** directo, sin
  etapas): sus sesiones se leen como una etapa "Correcciones".
- **Precio por boda** = propiedad **Total** (MXN) en Notion → alimenta la Rentabilidad. Si
  una boda no tiene Total, usa un valor por defecto.

## Límite de peticiones y datos degradados

Una extracción son ~200 peticiones a Notion (que permite ~3 por segundo): `server.py` las
espacia y reintenta con espera creciente, y si la consulta principal falla **no publica** un
tablero a medias. Detalle en [`docs/arquitectura.md`](arquitectura.md) §3.

## Versión en la nube (acceso desde cualquier lugar)

Además del modo local, hay una copia desplegada en **Cloudflare Pages**
(<https://hub-edicion.pages.dev>) que funciona **con la Mac apagada**: GitHub Actions
extrae Notion y publica a Cloudflare KV. Es la que usa el widget de iPhone.
- **Cada 15 min** mientras la Mac está encendida: el servidor local le pide a GitHub una
  actualización (si hubo una en los últimos 12 min, no pide otra).
- **Con la Mac apagada**: queda el horario de GitHub ("cada 30 min"), que GitHub cumple mal
  (en la práctica ~5 veces al día). Todo dentro de los planes gratuitos; números en
  `docs/arquitectura.md` §10.
Detalles y mantenimiento en [`cloud/README.md`](../README.md).

## Archivos

| Archivo | Qué es |
|---|---|
| `index.html` | El dashboard (diseño + `deriveModel` + sprint + snapshot de respaldo). **Fuente**: se edita aquí. |
| `server.py` | Puente local y núcleo de extracción (la nube importa el mismo archivo). |
| `sync-cloud.sh` | Porta a `cloud/` (el repo público) **todo lo importante**. Copia tal cual `index.html`, `server.py` y `fonts/`. Copia con limpieza `docs/`, `mac/`, `widgets/`, este README (→ `docs/guia-de-uso.md`) y las herramientas de la raíz (→ `scripts/`). Con `--publicar` hace commit + push. Se niega si el snapshot embebido no es el de ejemplo o si `privacidad.py` encuentra algo privado. |
| `privacidad.py` | Guardián del repo público (20-nov-2026). `copiar` cambia nombres reales por nombres de ejemplo y montos por `$XX,XXX`. `revisar` frena la publicación si ve una llave real, un correo, un ID o un nombre real. Lo usa `sync-cloud.sh`. El mapa real → ejemplo está en `.privacidad.json`, que nunca sube. |
| `snapshot-demo.py` | Renueva el snapshot embebido con **datos de ejemplo** (quita nombres, precios, estudio, enlaces e ids). Es la única forma de refrescarlo. |
| `cloud/` | Copia desplegada en Cloudflare Pages (repo git propio). Ver su README. |
| `widgets/` | Widgets de iPhone (Scriptable: barras por día y, desde el 16-nov, la dona «Horas y $ por etapa») y Mac (SwiftBar). Ver su README. |
| `mac/SprintFlotante/` | App nativa del sprint: ventana flotante + reloj y menú en la barra de menús (`main.swift`, `build.sh` → `~/Applications/Sprint flotante.app`). |
| `docs/arquitectura.md` | Referencia técnica: datos, endpoints, módulos, reglas, mantenimiento. |
| `docs/migracion-swiftui.md` | Idea aparcada: app nativa del dashboard. |
| `docs/historico/` | Dashboard anterior a "Sala de Corte" y la maqueta de diseño (solo referencia). |
| `docs/propuestas/` | Propuestas de diseño con datos reales (`carrera.html`: las 3 opciones del hero; `identidad.html`: sidebar plegable + 3 direcciones de identidad — Difusión, Cinta desenfocada, Monitor). |
| `.cache.json` · `.archive.json` | Caché de la última extracción · archivo histórico de bodas entregadas. |
| `docs/solo-en-la-mac.md` | Qué sube al repo, qué se queda solo en la Mac (y por qué) y cómo migrar a otra máquina. |
| `.sprint-state.json` | Sprint en curso compartido entre el dashboard y la ventana flotante. |
| `start.command` | Doble clic para arrancar el servidor si no corre. |
| `com.jordi.hub-edicion.plist` | Auto-arranque al iniciar sesión (launchd). |
| `~/.notion-dashboard-token` | Tu token (fuera de esta carpeta, no se comparte). |

## Solución de problemas

- **El sello dice GUARDADO (punto naranja)** → lo que ves son los últimos datos guardados en ese
  aparato, con la hora en que se leyeron; el refresco no pudo traer nada nuevo (servidor apagado
  en local, o sin red en el iPhone). Pica ↻ o arranca el servidor (`start.command`). Si la sesión
  de acceso de la nube caducó, la app se recarga sola y te pide el PIN. **SNAPSHOT** = no hay datos
  guardados todavía (primera vez) y muestra el snapshot embebido.
- **El iPhone no muestra la última sesión** → mira la hora del sello: es la de la última lectura
  de la nube. Tras terminar una sesión, el Mac avisa a la nube al momento y en ~3 min ya está;
  la app se refresca sola al volver a primer plano (no hace falta matarla).
- **La nube no se actualiza cada 15 min** → mira `/tmp/hub-edicion.err` (líneas `[nube]`):
  `pedida` = bien; `error: …` suele ser que `gh` perdió la sesión (`gh auth status`). Solo
  funciona con la Mac encendida y el servidor local corriendo.
- **Error de token / 401** → revisa el paso 2 (compartir la página con la integración) y
  que el token en `~/.notion-dashboard-token` sea correcto. Prueba con `--check`.
- **No aparece una boda** → confirma en Notion que su *Tipo* = Boda. Si está **finalizada**
  (`Finalizadas`/`Hecho`/`Complete`), solo aparece si tuvo sesiones (o su *Fecha* termina) en los últimos 45 días
  (ajustable en `RECENT_DONE_DAYS`); mientras le haces correcciones, ponla en *Correcciones*.
  Si renombras o agregas una opción de **Status** que signifique "terminada", añádela a
  `DONE_STATUSES` en `server.py` (y `cloud/server.py`) para que cuente como finalizada.
- **Una sesión no suma** → revisa que esté en el DB de **Sesiones** de su etapa con
  **Inicio y Fin** (de ahí salen las horas). Tras cambiar `server.py`, reinícialo
  (`launchctl kickstart -k gui/$(id -u)/com.jordi.hub-edicion`) y pica ↻.
- **El sprint no ofrece una etapa** → solo salen etapas no terminadas que tengan su DB de
  **Sesiones** con fechas Inicio y Fin. Si es nueva, pica ↻ para que el tablero la lea.
- **El reloj muestra ☁︎↑ con un número** → hay sesiones/cierres guardados en el Mac esperando
  internet; se suben solos. Para forzar: menú del reloj → **Subir ahora**. Si una lleva
  *⚠︎ Notion rechazó…*, se reintenta cada 15 min y se queda guardada (nada se borra solo).
  Ver la cola: `curl localhost:4599/api/outbox`; el registro de subidas, `[cola]` en
  `/tmp/hub-edicion.err`.
- **Un sprint quedó "Sin registrar"** → Notion lo rechazó (o `server.py` no respondía; en ese
  caso se reenvía solo al volver); el motivo sale en la tarjeta. Pica **Reintentar** (o
  **Descartar**). Desde la nube sin `NOTION_TOKEN` el registro llega en la siguiente
  actualización (≤ 15 min con la Mac encendida).
- **La ventana flotante dice "Sin conexión con el Hub local"** → `server.py` no corre; se
  reconecta sola en cuanto arranca. **El botón ⤢ no hace nada** → la app no está instalada:
  `mac/SprintFlotante/build.sh`. El botón solo aparece en el Mac y en local (no en la nube).
- **No veo la versión nueva en el iPhone** → cierra la app desde el selector de apps y ábrela
  de nuevo (recargar no basta en las apps de pantalla de inicio).
- **El widget no carga** → iPhone: revisa el Service Token del script. Mac: el servidor local
  debe estar corriendo. Detalle en [`widgets/README.md`](../widgets/README.md).
