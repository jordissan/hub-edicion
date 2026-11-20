# ¿Vale la pena la «Arquitectura unificada» de Notion? — análisis y recomendación

> **Fecha:** 3-nov-2026 · **Estado:** análisis. No se tocó nada en Notion ni en el código.
> **Pregunta de Jordi:** el dashboard ya resuelve las mediciones. ¿Vale la pena migrar a la
> arquitectura unificada del Laboratorio? ¿Qué flancos o qué sesgo se me escapan?

---

## En corto

1. **Por las mediciones, no vale la pena.** Lo que el prototipo promete («horas por etapa
   automáticas») ya lo da el dashboard, y mejor. Migrar no cambiaría lo que ves en el tablero.
2. **Sí hay mejoras de verdad, pero en otras partes**: corregir errores (una sesión en la
   etapa equivocada se arreglaría en 2 clics, no rehaciéndola), crear bodas nuevas con mucho
   menos trabajo (o desde la app), un dashboard más simple y unas 10 veces más rápido para leer
   Notion, el histórico consultable sin trucos, y Notion IA y las automatizaciones funcionando
   sobre una sola base.
3. **El prototipo, tal como está, no sirve para migrar.** Lo armamos en julio con datos de
   ejemplo y nunca se probó contra tus datos reales ni contra el sprint. Tiene tres huecos
   grandes (los explico abajo). El más serio: **perdería las horas de 1 de cada 3 sesiones**.
4. **Recomendación: un camino intermedio por fases.** No migrar nada a media producción
   (Renata + Emilio se termina como está). Corregir el prototipo, probarlo con una boda ya
   entregada, y **estrenarlo en la próxima boda nueva**. El dashboard se queda, y durante la
   transición lee los dos formatos. Las bodas viejas no se migran.

---

## 1. Qué hay hoy (la plantilla actual)

Ejemplo real: **Renata + Emilio**, que es una fila de la base **Trabajo**.

```
Trabajo (base)
└─ Renata + Emilio (fila)
   └─ Tracking de Edición (base, 15 etapas)
      └─ Color y finalización (DCT) (fila = página)
         ├─ Corrección de Color   ← escenas (First look, F&F…), con botones
         │                          Sesión / Gestión / Finalización / ⚪️ / 🔵 / 🟢
         ├─ Total                 ← 2 filas: «Edición» y «Gestión»
         ├─ Sesiones              ← cada sesión: Inicio, Fin, Tipo, Escena, Total
         └─ Vista «Consola»       ← tablero de escenas con los botones
```

- **Cada etapa tiene sus propias 2 o 3 bases.** Una boda de 15 etapas son unas **45 bases**.
- Las horas viven en cada base de Sesiones por separado. Por eso Notion no puede sumar
  «horas de esta boda» ni «horas de Color en todas las bodas»: no existe una base que las junte.
- **Volumen real** (según el dashboard): Renata + Emilio lleva **214 sesiones, 53 escenas y
  15 etapas**. Paula + Bruno tuvo 178 sesiones. Más o menos 200 sesiones por boda.

## 2. Qué es el prototipo «Arquitectura unificada»

Está en *Hola › Laboratorio › 🏗️ Arquitectura Unificada — Prototipo* (18-jul-2026), con
datos de ejemplo (Limpieza, Sincronización, Edición Musical; Cóctel, Fiesta, Ceremonia).

Son **3 bases fijas para todo**, en vez de 45 por boda:

| Base | Una fila por… | Lo importante |
|---|---|---|
| **Tracking de Edición** | etapa | `Horas (min)`: suma sola las sesiones · `Estado`: **fórmula** que se pone 🟢 cuando todas sus escenas están 🟢 · `Escenas hechas / total` |
| **Escenas** | escena × etapa | relación `Etapa` · `Estado (Select)` ⚪️/🔵/🟢 · `Tiempo Real` (suma de sesiones) · `TR num` (fórmula-puente) |
| **Sesiones** | sesión | `Inicio`, `Fin`, `Duración` (fórmula), `Tipo` (Edición/Gestión), relación `Escena` |

La cadena es: Sesión → Escena → Etapa. Notion no deja sumar una suma de otra base (un
*rollup* de un *rollup*), así que el prototipo usa una fórmula-puente (`TR num`).

En la Bitácora de reestructura (1-nov) quedó la decisión **D3: «Bodas: no migrar por ahora;
Arquitectura Unificada a Laboratorio»**.

## 3. Los tres huecos del prototipo (lo que se pasa por alto)

Comparé el prototipo con tus datos reales. Estos huecos no se ven con los datos de ejemplo:

### Hueco 1 — Las sesiones sin escena se pierden

En el prototipo, una sesión solo llega a su etapa **a través de la escena**. Pero muchas
sesiones no tienen escena: en Renata + Emilio, **59 de 214**; en Paula + Bruno, **66 de 178**.
Casi siempre son etapas sin escenas: Selección, Música y Montaje del teaser, Montaje HL/SF,
Cambios y Setup. Además, el sprint tiene a propósito la opción «Sin escena».

→ Con el prototipo tal cual, **más o menos un tercio de las horas no se sumaría a ninguna
etapa**. Solución: que cada sesión tenga **relación directa con su Etapa** (y con su Boda),
no solo con la escena.

### Hueco 2 — El estado automático de la etapa no encaja con cómo trabajas

- **9 de las 15 etapas de Renata + Emilio no tienen escenas.** Con la fórmula del prototipo,
  esas etapas se quedarían en ⚪️ para siempre.
- El sprint **cierra etapas** («+ ETAPA») escribiendo el select `Estado` y la fecha de fin de
  `Del → Al`. Una fórmula no se puede escribir, así que ese botón dejaría de funcionar.
- A veces das una etapa por cerrada aunque quede algo suelto. Eso lo decides tú, no una regla.

→ Mejor: **conservar el `Estado` manual** (lo que usan el sprint y el dashboard) y añadir al
lado un **«Estado sugerido»** o un aviso «⚠️ quedan escenas abiertas».

### Hueco 3 — No existe la boda

Ninguna de las 3 bases tiene relación con la **boda** (la fila de Trabajo). Con una sola
boda de ejemplo no se nota. Con varias, «Limpieza» de Renata + Emilio y «Limpieza» de la
siguiente boda quedarían revueltas, y habría 10 escenas llamadas «Ceremonia» en el selector.

→ Hay que añadir la relación **Boda** a Etapas y a Sesiones. En la página de cada boda irían
vistas de esas bases filtradas por «esta boda».

### Otras cosas que faltan (más chicas)

- `Fase` solo tiene Documental y HL/SF. Las reales son PREP, TEAS, DCT, HL/SF y CMB.
- Faltan `Del → Al` y `Notas` en la etapa; `Inicio` y `Fin` en la escena; `Ronda` en Cambios;
  `Canción`; y un campo **«Día»** (hoy «Día 1/Día 2» se deduce del *nombre* de la base).
- Faltan los botones (Sesión, Gestión, Finalización, ⚪️/🔵/🟢) y la Consola. El propio
  prototipo avisa que eso se arma a mano en Notion.
- **Una cosa que el prototipo hace mejor:** no tiene la base «Total» (Edición/Gestión). Basta
  con el `Tipo` de la sesión. Hoy ese dato está **duplicado** (el `Tipo` y la relación a
  «Total»), y por eso pasó lo del 3-nov: 15 sesiones con el Tipo corregido a mano pero la
  relación todavía en «Gestión». Con un solo dato, ese error no puede pasar.

## 4. Comparación frente por frente

| Frente | Hoy (anidada) | Unificada (corregida) | ¿Gana? |
|---|---|---|---|
| **Mediciones en Notion** | Notion no suma nada entre etapas. Lo hace el dashboard. | Horas por etapa, por boda y por semana dentro de Notion, con gráficas nativas. | Unificada, **pero el dashboard ya lo cubre** y mejor (carrera, fantasma, $/h, ritmo). Ganancia real: pequeña. |
| **Lectura por API (dashboard)** | Recorre página por página: ~200 peticiones, **~2 min** por extracción (la nube tarda 105-140 s). Adivina qué base es qué por el título (la trampa de «Tiempo total»). | 3 o 4 consultas filtradas por boda: **segundos**. Sin adivinar nada. | **Unificada, clara.** Menos errores 429, menos código frágil. |
| **Escritura (sprint)** | Escribe en la base de Sesiones *de esa etapa* y busca la fila Edición/Gestión en «Total». | Escribe siempre en la misma base, con Boda, Etapa, Escena y Tipo. Sin «Total». | Unificada (más simple y sin el dato duplicado). |
| **Crear una boda o etapa nueva** | Duplicar la plantilla crea ~45 bases. La API **no puede** duplicar la plantilla, así que la app no podría crear una boda. | Una boda nueva son filas nuevas. La app o un botón pueden generar las 15 etapas y sus escenas. | Unificada. |
| **Corregir errores** (sesión en la etapa equivocada) | Hay que **rehacerla** en la base de la otra etapa: sus relaciones apuntan a las bases de la etapa original. | Cambiar la relación Etapa o Escena: 2 clics. | **Unificada, clara.** |
| **Nuevos errores posibles** | Pocos: cada etapa está aislada. | Elegir la escena de **otra boda** en un selector con todas. Se evita con el botón de fila (pone «esta escena» solo) y con un aviso si Boda o Etapa no cuadran. | Hoy. Es un riesgo a cuidar. |
| **Límites de Notion** | Muchas bases chicas: nada pesa. | ~1 600 sesiones al año en una base. Notion lo aguanta, pero con muchos *rollups* se pone lenta a partir de unas 10 000 filas. Hay que evitar cadenas de sumas largas. | Empate si se diseña bien. |
| **Tiempo real** (el ⌘R) | Lo que escribe la API no aparece hasta recargar. | **Igual.** Migrar no lo arregla. | Ninguna. |
| **Móvil** | Hola › Trabajo › Boda › Etapa › Sesiones: 4 o 5 toques. | Una vista «Hoy» o «Esta boda» directa. | Unificada (poco, porque el registro ya lo hace el sprint). |
| **Automatizaciones de Notion** | Habría que configurarlas en cada una de las ~45 bases de cada boda. | Una automatización sirve para todo. | Unificada. |
| **Notion IA** | Difícil: los datos están repartidos en cientos de bases. | Puede responder «¿cuántas horas de Color en las últimas 3 bodas?». | Unificada. Depende de tu plan de Notion (ver nota). |
| **Histórico y comparar bodas** | El dashboard guarda un archivo compacto (`archive` + `ghost`) porque releer una boda vieja tarda ~1 min. Una pregunta nueva sobre el pasado obliga a reconstruir. | Todo el pasado responde con una consulta. | Unificada, **solo para bodas nuevas** (las viejas siguen en el archivo). |
| **Migración: coste y riesgo** | Cero. | Rehacer botones, vistas y plantilla en Notion; reescribir la lectura y escritura del servidor y de la nube; probar el sprint. | Hoy. |
| **Futura app nativa (SwiftUI)** | La app leería el JSON del servidor. Nada cambia. | Igual. Además la app podría hablar con Notion directo (3 bases simples) y crear bodas. | Ligera ventaja para la unificada. No es decisivo. |

> **Nota sobre tu plan de Notion:** al revisar, la herramienta de Notion rechazó una consulta
> combinada porque «requiere el plan Business». Eso indica que el espacio no es Business.
> Las funciones de IA y algunas automatizaciones dependen del plan. Antes de contar con ellas
> como ventaja, revisa qué incluye el tuyo.

## 5. Sesgos posibles (en los dos sentidos)

### A favor de migrar (sobrevalorar lo nuevo)

- **El prototipo «se ve bien» porque usa datos de ejemplo.** Con 3 escenas que siempre
  tienen sesión, todo cuadra. Con tus datos reales aparecen los tres huecos.
- **El motivo original ya no existe.** El prototipo nació para tener «horas por etapa
  automáticas». Desde entonces el dashboard hace eso y mucho más. Migrar «para medir» sería
  resolver un problema ya resuelto.
- **Lo ordenado atrae.** «3 bases en vez de 45» suena mejor, pero tu día a día en Notion
  (la Consola con botones dentro de cada etapa) funciona y es rápido. Hay que demostrar que
  la versión nueva no lo empeora.
- **El prototipo lo armó Claude**, no salió de una molestia tuya. Su página dice «lo que
  tuve que sumar a mano para el reporte de Carla»: era un dolor de quien hacía el reporte.

### A favor de no migrar (conformarse porque el dashboard tapa los huecos)

- **El dashboard solo resuelve la lectura.** Los dolores que quedan están en **escribir,
  corregir y crear**: la sesión en la etapa equivocada, el Tipo y «Total» que no cuadran,
  duplicar la plantilla de 45 bases. El dashboard no arregla nada de eso.
- **El coste de la estructura existe, aunque no lo veas.** Casi todas las trampas
  documentadas en `docs/arquitectura.md` §9 vienen de ella: adivinar qué base es qué por el
  título, «Tiempo total» que parece Sesiones, ~2 min y ~200 peticiones por lectura, errores
  429, el archivo y los *ghosts* con su versión, el límite de 2 reconstrucciones por corrida.
  Cada función nueva del dashboard paga ese peaje.
- **Las preguntas nuevas sobre el pasado cuestan caro.** El archivo solo guarda lo que
  decidimos guardar. Para preguntar algo nuevo («¿cuánto me tarda la Ceremonia en Limpieza,
  boda por boda?») hay que reconstruir boda por boda.
- **«Funciona» no quiere decir «escala».** Con 6 a 8 bodas al año, la estructura actual no
  se rompe, pero cada boda suma ~45 bases que nadie más que el dashboard puede leer juntas.

**En balance:** los dos sesgos existen. El más fuerte es el primero (migrar por medir),
porque es justo como se planteó la pregunta. El segundo es más sutil: la ganancia real no
está en el tablero, está en **corregir, crear y en la simplicidad del sistema**.

## 6. Las tres opciones, con lo que ganas y pierdes

### Opción A — No migrar

- **Ganas:** cero riesgo y cero trabajo. Todo sigue funcionando.
- **Pierdes:** corregir sigue costando; cada boda nueva duplica 45 bases; el dashboard
  sigue lento para leer Notion y frágil ante cambios de nombre; Notion IA y las
  automatizaciones no sirven para tus horas.
- **Tiene sentido si** casi nunca corriges sesiones y no piensas usar la IA ni las
  automatizaciones de Notion.

### Opción B — Migrar todo (incluidas las bodas en curso y las viejas)

- **Ganas:** un solo formato desde ya; el dashboard podría quitar el archivo y los *ghosts*.
- **Pierdes:** mucho trabajo y riesgo en plena producción (Renata + Emilio está en Color y en
  HL/SF), copiar ~400 sesiones de bodas viejas, y la posibilidad de romper el sprint en un
  día de trabajo.
- **No la recomiendo.**

### Opción C — Por fases: estrenar en la próxima boda nueva (**recomendada**)

- **Ganas:** casi todas las ventajas de la unificada para las bodas futuras, sin tocar las
  actuales. Si no convence, se vuelve a la plantilla vieja con la siguiente boda.
- **Pierdes:** durante un tiempo conviven dos formatos. El servidor lee los dos (unas
  decenas de líneas más) y las bodas viejas no ganan las consultas nuevas (quedan en el
  archivo como hoy).

## 7. Plan por fases (si eliges C)

**Fase 0 — Ahora: nada cambia.** Renata + Emilio se termina con la plantilla actual.

**Fase 1 — Corregir el prototipo** (en el Laboratorio, sin tocar bodas reales; ~1 o 2
sesiones de trabajo):
- Relación **Boda** en Etapas y Sesiones.
- Relación **Etapa directa** en Sesiones (para las sesiones sin escena).
- **`Estado` manual** en la etapa + «Estado sugerido» o aviso.
- Fases reales (PREP, TEAS, DCT, HL/SF, CMB), `Del → Al`, `Notas`, `Día`, `Ronda`,
  `Canción`, `Inicio`/`Fin` de escena, y un campo **«Etapa tipo»** (Limpieza, Montaje…).
  Ese último sirve para comparar entre bodas aunque cambien los nombres: hoy conviven
  «Edición Musical» y «Montaje (DCT)», «Corrección de color…» y «Color y finalización».
- Sin base «Total»: Edición y Gestión salen del `Tipo`.
- Botones de fila y la Consola (esto lo armas tú en la app de Notion, el conector no puede).
- **Por probar ahí mismo:** cómo se llena la Etapa o la Boda de una sesión creada a mano con
  el botón (si el botón puede copiarla de la escena, o hace falta una fórmula), y si el
  selector de escenas se vuelve molesto.

> **✅ Fase 1 hecha (3-nov-2026)** en *Laboratorio › 🏗️ Arquitectura Unificada — Prototipo*.
> Solo se tocaron las 3 bases del prototipo y su página. La base Trabajo no cambió: la
> relación Boda es de un solo sentido.
>
> - **Sesiones:** `Etapa` (relación directa, de ida y vuelta con Etapas), `Boda`, `Ronda`,
>   `Minutos` (número), `Min edición` / `Min gestión`, `Etapa de la escena` y
>   `Boda de la etapa` (rollups) y **`Revisar`** (avisos).
> - **Etapas:** `Estado` manual (select) + `Estado sugerido` (fórmula), `Fase` real,
>   `Etapa tipo`, `Del → Al`, `Notas`, `Boda`, `Min total` / `Min edición` / `Min gestión`
>   (rollups por la relación directa), `Horas`, `Sesiones con aviso` y **`Aviso`**. Se quitó el
>   rollup viejo `Horas (min)`.
> - **Escenas:** `Inicio`, `Fin`, `Día`, `Canción`. Se quitó la fórmula-puente `TR num`.
> - **Vistas:** «📊 Resumen» (Etapas) y «⚠️ Por revisar» (Sesiones).
> - **Datos de ejemplo:** una etapa sin escenas (Montaje HL/SF) y dos errores a propósito
>   (sesión 5: escena de otra etapa; sesión 9: sin Etapa).
> - **Verificado** con filtros de las vistas: «Por revisar» devuelve justo las sesiones 5 y 9.
>   Las 4 etapas dan las horas, el estado sugerido y el aviso esperados (2h 7m, 0h 50m con
>   aviso, 0h 40m, 1h 0m con «—»). No se pudo comprobar directo `Min edición` / `Min gestión`
>   (el conector no deja leer ni filtrar sumas), pero usan el mismo mecanismo que `Min total`.
>
> **Lo aprendido (importa para la fase 3):**
> - El conector de Notion **no deja crear fórmulas que lean datos de otra base**
>   (`prop("Sesiones").map(...)`, `prop("Escena").first().prop(...)`). Por eso todo va con
>   rollups, y las fórmulas solo usan la fila propia (con `toNumber()` sobre los rollups).
>   En la app de Notion sí se pueden escribir esas fórmulas, si algún día hacen falta.
> - Por eso **la Etapa de la sesión es obligatoria**: la suma de la etapa solo cuenta las
>   sesiones ligadas directo. Las que no la tienen salen en «Por revisar». El sprint siempre
>   la pondrá; el botón de fila hay que probarlo.
> - La comprobación «escena de otra etapa» compara **nombres** de etapa. Dentro de una boda
>   funciona; con dos bodas, «Limpieza» y «Limpieza» se verían iguales. La comprobación de
>   Boda lo cubre si la sesión lleva su Boda.
> - Al renombrar la fórmula vieja `Estado` y crear el select `Estado` en la misma llamada,
>   Notion convirtió la fórmula en el select y la fórmula se perdió. Se rehízo como
>   `Estado sugerido`. Lección: renombrar y crear en llamadas separadas.
> - El conector no muestra resultados de fórmulas ni rollups. Para verificar, se filtra una
>   vista y se mira qué filas devuelve.

**Fase 2 — Ensayo con una boda entregada.** Copiar Paula + Bruno (178 sesiones) al
prototipo con un script y comprobar dos cosas: que las horas por etapa coinciden con el
dashboard, y que usar Notion se siente igual o mejor. **Aquí se decide si se sigue.**

**Fase 3 — Adaptar el código** (probado en un puerto de prueba, sin tocar el sprint real):
- `server.py`: lectura nueva para bodas unificadas (consultas filtradas por Boda) que
  produzca **el mismo JSON de siempre**. Así `index.html`, los widgets y la futura app no
  cambian. Las bodas viejas siguen leyéndose como hoy.
- Registro y cierre (`create_session`, `set_done`, `set_in_progress`) en `server.py` y en
  `cloud/functions/api/session.js` y `close.js`: escribir en la base única con Boda, Etapa,
  Escena y Tipo.
- `index.html`: el sprint identifica la etapa por su base de Sesiones (`db`, y `etapa:<db>`
  en el menú del reloj). Con una base única, todas las etapas tendrían el mismo `db`, así que
  hay que pasar a identificarla por la página de la etapa (`stageId`). Es un cambio chico,
  pero toca el sprint y hay que probarlo con cuidado.
- Actualizar `docs/arquitectura.md` (§3, §5, §7 y §9) y los READMEs.

**Fase 4 — Estreno con la próxima boda nueva.** Ideal: que la app o un botón genere las
etapas y escenas desde un catálogo. Después de esa boda, revisar: ¿corregiste más fácil?
¿Notion se siente igual de rápido? Si no, la siguiente boda vuelve a la plantilla vieja.

**Más adelante (opcional):** cuando todas las bodas activas sean unificadas, simplificar el
archivo y los *ghosts* del dashboard, y valorar migrar por script alguna boda vieja si hace
falta para comparar.

## 8. Esfuerzo y riesgo, a ojo

| Pieza | Esfuerzo | Riesgo |
|---|---|---|
| Corregir el prototipo en Notion | 1-2 sesiones (+ ~1 h tuya para botones y vistas) | Bajo (está en el Laboratorio) |
| Ensayo con Paula + Bruno | 1 sesión | Bajo |
| Código (servidor + nube + sprint) | 2-3 sesiones | Medio: el sprint escribe en Notion; se prueba en un puerto aparte |
| Estreno en boda nueva | Tu primera semana de uso | Medio, con vuelta atrás fácil |

## 9. Lo que no cambia con ninguna opción

- El dashboard sigue siendo el lugar de las mediciones buenas (carrera, ritmo, $/h efectivo).
- Notion sigue sin mostrar al instante lo que escribe la API (hace falta ⌘R).
- La futura app SwiftUI se puede hacer igual con cualquiera de las dos estructuras, porque
  lee el JSON del servidor.

---

*Fuentes: página del prototipo y sus 3 bases (Laboratorio), Bitácora de reestructura,
Renata + Emilio › Tracking de Edición › Color y finalización (DCT) (bases Corrección de Color,
Total, Sesiones, vista Consola), `server.py`, `cloud/functions/api/`, `index.html`,
`docs/arquitectura.md`, datos vivos de `/api/data` (3-nov-2026) y tiempos de las corridas
de `publish.yml`.*

---

## Adenda (4-nov-2026) — Bodas distintas (teaser, 1 o 2 días) y la fricción de registrar a mano

**Pregunta de Jordi.** No todas las bodas serán como Renata + Emilio (teaser + 2 días). La plantilla debe
dejar agregar etapas (teaser y todo lo suyo) y modelar el «Día 1» con sus escenas reales, sin el truco de
una sola escena «Día 1» por etapa. Y le da pereza que en el modelo unificado cada sesión nueva obligue a
elegir etapa + escena + boda, y a reconstruir botones por etapa/escena en Notion.

**Lo que hace hoy el sprint** (`server.py` `create_session`): crea la sesión con Inicio, Fin, Tipo, Ronda,
Escena y «Total», y pasa a 🔵 la etapa y la escena. En el modelo unificado haría lo mismo con Etapa/Escena
(y Boda opcional) en **una sola llamada**: para el sprint el cambio es casi nulo y la elección de etapa y
escena sigue siendo la de sus ventanas. El «ligar a mano» solo existe cuando se registra desde Notion.

**Hallazgos**
1. *Boda en la sesión no hace falta ponerla:* sale de la etapa (rollup «Boda de la etapa»). Es opcional;
   solo sirve de doble comprobación. Obligatoria queda solo la **Etapa**.
2. *Flexibilidad de plantilla:* en el prototipo una etapa es una **fila**, no una base copiada. «Teaser»
   = filas de etapa con Fase TEAS (Selección, Música, Montaje, Color del teaser…) añadidas solo a las
   bodas que lo llevan. Hoy agregarla cuesta copiar una base de 3 DB; allí cuesta una fila.
3. *Día 1 real:* las escenas del Día 1 (ensayo, cena, preparativos…) son filas de Escenas con `Día = Día 1`
   dentro de la etapa que corresponda (hoy se deduce del *nombre* de la base). Permite sumar horas por día.
4. *Plantilla viva = catálogo en el dashboard, no una copia en Notion:* un «Nueva boda» que pregunta
   ¿teaser? ¿1 o 2 días? ¿qué entregables? y crea con la API las etapas (desde el catálogo «Etapa tipo»),
   sus escenas y la boda. Alternativa sin código: plantilla de página de boda con vistas enlazadas
   filtradas por «esta página» (por probar).
5. *Registro manual sin botones por etapa/escena:* vista enlazada de Sesiones dentro de cada página de
   etapa, filtrada por «Etapa = esta página»; el «+ Nuevo» de esa vista rellena la etapa solo (por
   probar). Faltaría solo la escena, opcional.

**Honestidad:** el modelo actual (botones dentro de cada etapa) *sí* es más cómodo para registrar a mano;
lo paga con 45 DB por boda y con la rigidez que Jordi describe. El unificado gana flexibilidad y sprint
más simple, y cede algo de comodidad manual salvo que funcionen los puntos «por probar» (4 y 5).

### ✅ Versión 3 del prototipo hecha (4-nov-2026)

Implementada en el Laboratorio como respuesta a la adenda anterior. Solo se tocó el prototipo (sus 3 bases,
su página y una base nueva); Trabajo y las bodas reales no cambiaron.

| Cambio | Para qué |
|---|---|
| **Base nueva «🧩 Catálogo de etapas (plantilla)»** (15 filas, copiadas de las etapas reales de Renata + Emilio) con `Paquete` (Base / Teaser / HL/SF / Cambios / Extra), `Fase`, `Etapa tipo`, `Orden`, `Lleva escenas`, `Escenas sugeridas`, `Cuándo se usa`. Vista «Por paquete». | La plantilla ya no es una copia de 45 bases: es una lista editable. Boda sin teaser = no copiar el paquete Teaser. Etapa nueva = una fila, una vez. |
| Sesiones: `Día de la escena` (rollup), `Min Día 1`, `Min Día 2` | Cada sesión con escena hereda su día. |
| Etapas: `Min Día 1`, `Min Día 2` (rollups) y `Reparto por día` (fórmula de texto) | Saber cuánto tomó el Día 1 y cuánto el Día 2 en cada etapa. |
| Datos de ejemplo: escenas «Ensayo» y «Cena de bienvenida» (Día 1), las demás de Limpieza pasadas a Día 2, etapa «Montaje (TEAS)» con una sesión de 90 min sin escena, sesiones 10-12 | Probar los tres casos: 2 días, teaser, etapa sin escenas. |
| Página de la etapa **Limpieza**: vista «Sesiones de esta etapa» (Sesiones filtradas por esa etapa) | Probar si el «+ Nuevo» de una vista filtrada rellena la Etapa solo. **Sin verificar: es comportamiento de la interfaz de Notion y el conector no lo puede ejecutar.** |
| La Boda en la sesión queda **opcional** (sale de la etapa); lo único obligatorio es la **Etapa** | Menos campos al registrar a mano. |

**Verificado** (filtrando la vista «Resumen» y leyéndola, porque los valores de fórmula no se leen directo):
Limpieza → Día 1 = 1h 25m (50 + 35), Día 2 = 2h 7m; Montaje (TEAS) → 1h 30m.

**Plan B** si el «+ Nuevo» filtrado no rellena la Etapa: cada etapa con una escena «General» y sesiones ligadas
solo a escena (la etapa sale de la escena). Así el botón de fila solo necesita «Escena = esta página». Es un
cambio mayor; no se hizo.

**No resuelto / límites:** copiar las filas del catálogo a una boda nueva sigue siendo manual en Notion (el
conector no puede duplicar filas con relaciones); lo razonable es un «Nueva boda» en el dashboard que lea este
catálogo con la API (pendiente de decidir, ver Fase 2/3). La integración del dashboard aún no tiene acceso al Laboratorio.

---

## Adenda (12-nov-2026) — Boda de prueba «PRUEBA · Arquitectura nueva»

Jordi pidió verla en una boda completa. Se creó con su OK:
- Fila en **Trabajo** con Status *Por hacer* y **Tipo vacío**: así `server.py`, la nube, los widgets y el sprint
  la ignoran sin tocar código. *Por hacer* por sí solo NO la excluye.
- En las bases del prototipo, **15 etapas** del Catálogo (todos los paquetes, 1 día) con `Boda` y **47 escenas**
  en Limpieza, Sincronización y Música/Montaje/Color (DCT).
- **35 vistas enlazadas** creadas con `notion-create-view` (`parent_page_id`): en la boda, Etapas, Sesiones,
  Total (gráfica donut, suma de `Minutos` por `Tipo`) y Por revisar; en cada etapa, **Consola** (tablero de
  Sesiones por Tipo: «+ Nuevo» rellena Etapa y Tipo por el filtro), **Total** y, si lleva escenas, **Escenas**
  (tablero por Estado).

**Aprendido:** el conector sí crea vistas enlazadas dentro de una página, con filtros por relación (`=`, `IN`,
grupos OR + AND) y gráficas sobre fórmulas. No puede: filtrar por rollup (la vista de sesiones de la boda filtra
por la lista de etapas), colocar vistas en columnas (se añaden al final), color condicional ni botones.
La receta de botones (una vez en las bases compartidas) está en la página de la boda.

