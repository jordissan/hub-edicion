# Hub de Edición — criterios de diseño

> Lo que Jordi ya decidió sobre cómo se ve y se siente el Hub, para no volver a preguntarlo ni a
> proponer lo descartado. Lo técnico (clases, tokens, trampas) está en `arquitectura.md` §4 y §9;
> las decisiones de negocio, en Notion › Trabajo › 🤖 Contexto Claude.

## Identidad (A · Difusión, oct-2026)

- **El lima es la marca y es luz, no pintura**: halos moderados, vidrio ahumado, negro OLED en oscuro.
  Una recomendación de cambiar a azul se descartó a propósito.
- Paleta con referencia Pantone: sol/lima protagonista, naranja para hoy/récord/pendiente, violeta
  para HL/SF, previos y comparación; crema para el texto. El trío lima-violeta-naranja ya está
  validado para daltonismo: no cambiarlo sin motivo.
- Texturas, degradados con grano y vidrio sí, pero contenidos: el grano va en los materiales,
  nunca encima de los datos (hoy al 50 %, perilla `--grain-k`).
- Tipografía: títulos de sección en la display grande; **títulos de tarjeta siempre en mono
  etiqueta** (mayúsculas, tracking, gris), nunca en display bold; la prosa (ledes, notas,
  leyendas) en la mono del sistema.
- Nombres directos y prácticos («Horas y $ por etapa»), sin títulos poéticos ni numeración.
- Iconos de objeto real, no abstractos (bandera, calendario, metrónomo, reloj de arena,
  claqueta, etiqueta con $).

## Gráficas

- Son guía visual: curvas suaves «con ritmo», trazo fino, hitos en anillo, guías punteadas.
  Las cifras exactas van en el tooltip o la tabla, no en la curva.
- Todas las gráficas de línea siguen el mismo trazo; al pasar el cursor, el elemento se resalta
  y los demás se atenúan (sin desaparecer).
- Dibujadas a tamaño real, sin rótulos pegados al borde, sin columnas cortadas ni textos
  montados sobre líneas de referencia: la asimetría le molesta.
- **Calidad de datos antes que completitud**: las bodas sin trackeo real no entran en
  comparaciones ni récords.

## Interacción

- Que se sienta vivo al cursor y como app nativa en el móvil, pero con criterio: no animar por
  animar. Entradas cortas (~0,5 s), solo `transform`/`opacity`.
- Las tarjetas embebidas en Notion no se levantan al pasar el cursor (el dashboard sí).
- Selectores: píldora compacta de 28 px a la derecha del título, abreviada si no cabe; área
  táctil de 44 px.
- La ventana flotante del sprint se ve igual que la tarjeta de Hoy (mismo vidrio y espaciado).
- Lo que se consulta poco va plegado (por ejemplo «Horas acumuladas», que recuerda la
  elección en cada aparato).

## Cómo trabajar el diseño con Jordi

- Antes de un rediseño grande, enseñar maquetas; después, iteraciones cortas sobre el resultado.
- Funciona bien: dos o tres opciones A/B con capturas, una recomendada. Suele aceptar la
  recomendada.
- Revisar escritorio, dashboard angosto, móvil y tema claro antes de enseñar. Detecta
  desalineaciones finas.
- Si pide un porcentaje de tamaño, partir del valor original que mencione.

## Descartado (no volver a proponer)

| Idea | Por qué |
|---|---|
| Que Notion se refresque solo tras cerrar una escena | No hay forma oficial; Jordi se queda con ⌘R (detalle en `arquitectura.md` §9). |
| Widgets de Scriptable que cambien de tema solos | Son imágenes dibujadas: habría que simplificar su diseño. Basta el toque del widget «Dark Mode» (atajo «Tema widget»). |
| Un botón que cambie iPhone y widgets a la vez | Atajos no avisa cuando cambia el aspecto. |
| Automatizaciones de widgets al atardecer/amanecer | En pausa por decisión de Jordi (`atajo-modo-oscuro.md`). |
| Base unificada de sesiones, Siri de horas, avisos 14:00/18:00 | Ver Contexto Claude › Acuerdos (en espera o descartados). |
