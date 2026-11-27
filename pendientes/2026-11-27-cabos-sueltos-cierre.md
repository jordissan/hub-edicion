# P7 · Cabos sueltos al cerrar la conversación vieja del Hub

- **Estado:** Por hacer
- **Dónde se ejecuta:** Mac + iPhone (cada punto dice dónde)
- **Creado:** 2026-11-27, desde la Mac
- **Resumen:** lo que quedó abierto en la conversación y las sesiones del Hub de Edición
  (oct–nov 2026) cuando se cerró. Todo lo demás ya está en `docs/` y en Notion › Contexto Claude.
  Cada punto se puede hacer, decidir o descartar por separado.

## Plan
1. **Decidir si se cambia `EMBED_SECRET`** (Cloudflare Pages). Antes del 20-nov, las vistas previas
   de cada deploy servían `/api/embed-link` sin login, así que las claves de las tarjetas de Notion
   pudieron verse. Ya está cerrado (`arquitectura.md` §9), pero las claves viejas siguen valiendo.
   Cambiarlo invalida todas las tarjetas pegadas en Notion: hay que volver a copiar cada enlace con
   el botón `</>`. Si Jordi decide no cambiarlo, anotarlo y cerrar este punto.
2. **Widget Donas, tamaños mediano y grande, modo tintado con tema claro:** el total del centro y
   las cifras en $ siguen tenues. Scriptable no expone el modo de renderizado; en el pequeño se
   resolvió con texto nativo (`nativeCenter`). Probar lo mismo en mediano y grande y verlo en el iPhone.
3. **«Horas acumuladas»:** decidir si el titular y los 3 indicadores de arriba (`.htop`) también se
   pliegan con la tarjeta. La recomendación fue que sí; Jordi no respondió.
4. **Auditoría de diseño del 10-nov:** M6 (barra de estado de iOS en tema claro) no se aplicó y S1
   quedó parcial (`docs/propuestas/auditoria-diseno-2026-11-10.md`). Verlo en el iPhone y decidir.
5. **Proyectos que no son bodas:** no se archivan; al salir del tablero, sus horas dejan de contar
   en Hoy y Tu ritmo. Decidir si se archivan como las bodas.
6. **Confirmar en el iPhone** (cerrar la PWA desde el selector de apps y reabrirla) lo publicado y no
   visto: tarjeta «Horas acumuladas» plegable, «Solo teaser» por Entregables, la boda que dejó de
   compararse consigo misma, y los widgets Donas/Barras en tema claro, oscuro y tintado. En Notion,
   ⌘R para ver las tarjetas quietas al pasar el cursor.

## Registro
- 2026-11-27: creado al cerrar la conversación vieja del Hub. Lo durable (criterios de diseño, lo
  descartado, trampas al probar, cómo se cuentan los días) pasó a `docs/diseno.md` y
  `docs/arquitectura.md`.
