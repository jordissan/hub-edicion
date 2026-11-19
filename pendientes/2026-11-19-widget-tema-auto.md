# P3 · Widgets de Scriptable: tema claro/oscuro sin abrir la app

- **Estado:** Por hacer
- **Dónde se ejecuta:** Mac (para leer los scripts de iCloud) + prueba en el iPhone
- **Creado:** 2026-11-19, desde el teléfono
- **Resumen:** hoy, al tocar el widget para cambiar entre claro y oscuro, se abre Scriptable, corre
  el script y la app se queda abierta. iOS no deja que Scriptable se cierre sola. Objetivo: que el
  tema no requiera tocar nada, o al menos un solo toque que regrese al inicio.

## Plan

**Privacidad, antes que nada:** el script lleva el Service Token de Cloudflare Access (Client ID y
Secret). No se copia al repo (es público) ni se pega en chats. Se edita en su sitio, en iCloud.

### 1. Ver lo que hay
- [ ] Scripts en `~/Library/Mobile Documents/iCloud~dk~simonbs~Scriptable/Documents/`. Identificar
      los de los widgets y cómo funciona hoy el cambio de tema (qué hace el toque: `widget.url`,
      `config.runsInApp`, un archivo o `Keychain` con el tema elegido, etc.).
- [ ] Hacer una lista de qué partes del widget son colores (texto, fondos, stacks) y cuáles son
      imágenes dibujadas (`DrawContext`, `Image`).
- [ ] Respaldo de cada script antes de tocarlo (copia `*.bak.js` en la misma carpeta de iCloud).

### 2. Opción 1 (preferida): que el widget siga el modo del sistema
- [ ] Colores con `Color.dynamic(claro, oscuro)`: iOS los cambia solo, sin volver a correr el script.
      No usar `Device.isUsingDarkAppearance()` dentro del widget (no es fiable ahí).
- [ ] Las partes que son imagen no cambian solas. Opciones, de mejor a peor:
  - rehacerlas con stacks y colores dinámicos si son simples (barras, puntos, retículas);
  - si no se puede, dibujar con colores neutros que funcionen en ambos temas;
  - si tampoco, aceptar que esas partes se actualicen en el siguiente refresco del widget.
- [ ] Mantener una opción para forzar claro u oscuro, como el «Auto ◐ / ☀ / ☾» del dashboard.
      Por ejemplo, con el parámetro del widget (mantener presionado → Editar widget → Parameter).
- [ ] El toque del widget pasa a abrir el dashboard, o nada, en vez de cambiar el tema.

### 3. Opción 2 (si la 1 no queda bien): un toque que regresa al inicio
- [ ] Atajo «Tema widget» en la app Atajos: acción de Scriptable *Run Script* (con «Run In App»
      apagado), que alterne el tema, y luego **«Ir a la pantalla de inicio»**.
- [ ] `widget.url = "shortcuts://run-shortcut?name=Tema%20widget"`.
- [ ] Comprobar que el widget se redibuja al momento. Si no, probar a refrescarlo desde el script.

### 4. Probar en el iPhone
- [ ] Cambiar el modo en Centro de control: el widget cambia sin tocarlo (opción 1), o un toque
      cambia y vuelve al inicio (opción 2).
- [ ] Los datos se siguen cargando (el Service Token sigue funcionando).
- [ ] Revisar los dos temas a la vista: legibilidad y contraste.

### 5. Documentar
- [ ] Una línea en `docs/arquitectura.md` (widgets) y en `README.md` de `cloud/` sobre cómo
      elige ahora el tema el widget. Publicar con `sync-cloud.sh`. Sin el script ni el token.

**Listo cuando:** ya no hace falta cerrar Scriptable a mano para cambiar el tema del widget.

## Registro
- 2026-11-19: creado.
