# P5 · Traer a la Mac el cambio de GitHub en docs/arquitectura.md

- **Estado:** Hecho
- **Dónde se ejecuta:** Mac
- **Creado:** 2026-11-25, desde la app (proyecto Trabajo)
- **Resumen:** el sync marca un cambio de GitHub en `docs/arquitectura.md` que no pudo traer solo
  porque la copia local también cambió o lleva nombres reales. Mientras no se junte, `sync-cloud.sh`
  no publica.

## Plan
1. `cd ~/HubEdicion && ./sync-cloud.sh --traer` y leer `.sync-estado` para confirmar qué falta.
2. Comparar `cloud/docs/arquitectura.md` con `docs/arquitectura.md`: pasar a la copia local solo
   las líneas nuevas de GitHub, sin pisar los nombres reales ni lo que cambió en la Mac.
   Nunca copiar el archivo del repo encima.
3. Aprovechar la pasada (opcional): agregar en §1 o §8 una nota corta de que el contexto de
   negocio vive en Notion › Trabajo › 🤖 Contexto Claude y la regla de «cuándo se actualiza qué»
   (ver `CLAUDE.md` del repo).
4. `./sync-cloud.sh` → revisar el diff → `./sync-cloud.sh --publicar "Arquitectura: …"`.
5. Listo cuando `.sync-estado` diga «Al día» y la publicación pase.

## Registro
- 2026-11-25: creado. `.sync-estado` del 24-nov 20:53 decía «Cambios de GitHub por traer a mano —
  docs/arquitectura.md».
- 2026-11-25: hecho desde la Mac. La copia local ya tenía el bloque nuevo de §5.1 («Finalizar sin
  bloque en marcha»); solo sobraba una línea en blanco, que impedía que el sync lo diera por igual.
  Se quitó, `--traer` quedó «Al día» (c7fd581) y se agregó en el encabezado la nota de que el
  contexto de negocio vive en Notion › Trabajo › 🤖 Contexto Claude, con la regla de «cuándo se
  actualiza qué» (sin el enlace con ID, porque el repo es público). Publicado en 9a1a236.
