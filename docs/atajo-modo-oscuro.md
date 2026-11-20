# Atajo «Modo oscuro» del iPhone (12-nov-2026)

Un solo toque cambia todo entre **claro y oscuro** (ida y vuelta):

1. el **iPhone** (aspecto del sistema);
2. los **widgets del Hub** en Scriptable («Hub Edición · Barras», «Hub Edición · Donas» y «Notion Dashboard»);
3. las **tarjetas del Hub en Notion** (siguen solas al iPhone si el interruptor está en **Auto**).

La Mac **no** cambia: sus tarjetas siguen el aspecto de la propia Mac.

---

## Preparar una sola vez

1. **Notion (iPhone):** Ajustes → Apariencia → **Usar ajuste del sistema**.
2. **Tarjetas:** en la tarjeta **«Tema de los widgets»** de Notion toca **Auto** (el tercer símbolo: círculo
   mitad lleno; los otros dos son sol = claro y luna = oscuro).
   Así todas las tarjetas siguen el aspecto del teléfono, al momento.
   - Si tocas el sol/luna de UNA tarjeta, esa se queda fija. Para soltarla, vuelve a tocar **Auto**.
   - El Auto del iPhone y el de la Mac son independientes (cada aparato recuerda el suyo).

## Instalar el atajo ya hecho (recomendado)

1. En el iPhone abre **Archivos → iCloud Drive → Scriptable** → toca **«Modo oscuro.shortcut»**.
2. Se abre Atajos → **Añadir atajo**.
3. Ábrelo una vez para revisarlo: la acción de Scriptable debe decir **Dark Mode**. Si sale vacía,
   toca el campo del script y elige **Dark Mode**.
4. Pruébalo: un toque pasa todo a oscuro; otro, a claro.

El archivo se genera con `widgets/atajo/make-atajo.py` (firmado con `shortcuts sign`; copia en
`widgets/atajo/Modo oscuro.shortcut`). En el Mac solo se comprobó que abre y que la firma vale:
Scriptable no está en el Mac, así que la prueba de verdad es en el iPhone.

## Armarlo a mano (si el archivo fallara)

1. Atajos → **+** (nuevo atajo) → nómbralo **«Modo oscuro»**.
2. Busca **Scriptable** → acción **Run Script**:
   - **Script:** `Dark Mode`
   - **Parameter:** escribe `alternar`
   - Toca la flecha ⌄ y deja **Run In App** y **Show When Run** apagados.
3. Busca **Si** → acción **Si**:
   - **Entrada:** el resultado de *Run Script* (sale solo).
   - **Condición:** **es** → escribe `oscuro`.
4. Busca **aspecto** → acción **Definir aspecto** → arrástrala **dentro** del «Si» → **Oscuro**.
5. Otra acción **Definir aspecto** → arrástrala **dentro** del «De lo contrario» → **Claro**.
6. Listo. El atajo queda así:

```
Run Script  [Dark Mode]  Parameter: alternar
Si  [Resultado]  es  oscuro
    Definir aspecto  →  Oscuro
De lo contrario
    Definir aspecto  →  Claro
Fin de Si
```

**Para tenerlo a mano:** ponlo en la pantalla de inicio (⋯ del atajo → Añadir a inicio), en el
Centro de control, o en Ajustes → Accesibilidad → Tocar → **Toque posterior** (doble toque atrás).

### Variantes (opcional)
- **Solo oscuro / solo claro:** en *Run Script* pon `oscuro` (o `claro`) y usa una sola
  *Definir aspecto* con ese mismo modo, sin el «Si».

---

## Automático: que los widgets cambien solos a la hora del iPhone (12-nov)

Atajos no tiene un disparador de «cambió el aspecto», así que se usa **la misma hora** a la que el iPhone
cambia solo. Para eso hay dos atajos que **solo** tocan los widgets (fijan su modo y los refrescan al momento;
el aspecto del iPhone ya lo cambia iOS):

**1. Instalar los dos atajos** (una vez): Archivos → iCloud Drive → Scriptable → toca **«Widgets oscuro.shortcut»**
→ Añadir atajo. Igual con **«Widgets claro.shortcut»**.

**2. Ver a qué hora cambia tu iPhone:** Ajustes → Pantalla y brillo → **Automático** → Opciones:
- **Del atardecer al amanecer**, o
- **Horario personalizado** (anota las dos horas).

**3. Automatización de la noche:** Atajos → pestaña **Automatización** → **+** → **Hora del día**:
- Elige **Atardecer** (o la hora de «oscuro» de tu horario personalizado) → **Diario**.
- Marca **Ejecutar inmediatamente** y apaga **Notificar al ejecutar**.
- Siguiente → **Ejecutar atajo** → **Widgets oscuro** → OK.

**4. Automatización de la mañana:** igual, con **Amanecer** (o la hora de «claro») → **Widgets claro**.

Si «Atardecer» ofrece un desfase (por ejemplo «15 minutos antes»), déjalo **A la hora del atardecer**.
Si un día cambias el aspecto a mano desde el Centro de control, usa el atajo «Modo oscuro».

## Un toque en el widget «Dark Mode» (18-nov)

Tocar el widget abre el atajo **«Tema widget»**: alterna el tema de los widgets, los redibuja y regresa a la
pantalla de inicio, sin dejar Scriptable abierta. No cambia el aspecto del iPhone. Se instala una vez desde
Archivos → iCloud Drive → Scriptable → **«Tema widget.shortcut»**, sin cambiarle el nombre, porque el widget lo
abre por ese nombre.

## Qué esperar

- **iPhone:** cambia al instante.
- **Tarjetas en Notion:** cambian al momento si están en **Auto** (o al volver a abrir Notion).
- **Widgets de Scriptable (con «Modo oscuro» o las automatizaciones):** «Tema widget» y «Widgets oscuro/claro»
  piden a iOS redibujarlos al momento («Refresh All Widgets»); con «Modo oscuro» cambian **cuando iOS los redibuja**. Suele ser en unos minutos y a veces
  hasta media hora. Ningún método lo hace al instante: el momento lo decide iOS.

## Cómo funciona (técnico)

- `Dark Mode.js` (Scriptable, iCloud; copia en `widgets/Dark Mode (global).js`): con parámetro del atajo
  `oscuro` | `claro` | `alternar` (vacío = alternar) **fija** `const DARK_MODE` en los widgets de su lista,
  sin ventanas, y devuelve al atajo el modo final (`Script.setShortcutOutput`: `"oscuro"`/`"claro"`).
  El atajo pone el iPhone en ese mismo modo, así todo queda sincronizado aunque estuviera desparejado.
  Tocado a mano (sin atajo) sigue alternando como siempre.
- Tarjetas `/embed`: el interruptor general tiene **Auto** = borra `scEmbedTheme` y los
  `scEmbedTheme:<tarjeta>:<boda>`. Sin tema guardado cada tarjeta sigue `prefers-color-scheme` y escucha
  su `change` en vivo (`SYS_LIGHT` + `embWantedLight()` en index.html). Es localStorage del iframe: por aparato.
- «Widgets oscuro» / «Widgets claro»: Texto → Run Script `Dark Mode` con `oscuro`/`claro` → Scriptable
  «Refresh All Widgets» (`dk.simonbs.Scriptable.RefreshAllWidgetsIntent`). No tocan el aspecto del iPhone.
  Las automatizaciones de Atajos no se pueden importar como archivo: se crean a mano en el iPhone.
- Sin servidor ni token: nada pasa por la nube.
- Por comprobar en el aparato: que la app de Notion del iPhone pase el aspecto al iframe (debería, con
  Apariencia = sistema). Si no, plan B: tema guardado en la nube vía endpoint con token (afectaría a la Mac).
