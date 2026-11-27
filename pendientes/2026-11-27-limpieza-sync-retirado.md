# P6 · Limpiar los restos del sync GitHub → Mac

- **Estado:** Por hacer
- **Dónde se ejecuta:** Mac
- **Creado:** 2026-11-27, desde la Mac
- **Resumen:** el 27-nov se volvió a «local primero» y se apagó el sync al revés. Tras unos días
  sin problemas, se borran las piezas que quedaron guardadas por si había que regresar.

## Plan
1. Confirmar que se publicó al menos una vez con `./sync-cloud.sh --publicar` sin problemas.
2. Con el ok de Jordi, borrar en `~/HubEdicion`: `.retirado/`, `.sync-base`, `.sync-estado`,
   `.sync-avisado` (si existe) y `sync-cloud.sh.antes-sync`.
3. Borrar `~/Library/Logs/hub-edicion-sync.log` (lo pega Jordi en Terminal).
4. Quitar la fila de `.retirado/` en `docs/solo-en-la-mac.md` y publicar.

## Registro
- 2026-11-27: creado.
