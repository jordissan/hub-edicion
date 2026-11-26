# P4 · Cerrar la información sensible del repo público

- **Estado:** En curso
- **Dónde se ejecuta:** Nube + Mac
- **Creado:** 2026-11-23, desde la web
- **Resumen:** Auditoría hecha, historial reescrito (el repo sigue público), PRs viejos y commits
  purgados por GitHub Support y clon de la Mac realineado. Quedan solo los menores (pasos 5 a 7).

## Plan
1. ~~Decidir la ruta~~: reescribir el historial y seguir público (2026-11-23).
2. ~~Reescribir con `git filter-repo`~~ sin tocar el árbol actual de `main`; force push a `main`.
3. ~~Mac: realinear `~/HubEdicion/cloud` a la nueva `main`, nuevo `.sync-base` y correo noreply en git~~ (2026-11-25).
4. ~~GitHub Support: pedir que borren los PRs #1–#4 y purguen los commits viejos~~ (2026-11-26).
5. ~~Borrar la rama `claude/project-thread-cixs7o` en GitHub~~ (ya no existe).
5. Menores: IDs de Notion de `server.py` y el precio por defecto a configuración local (solo si sigue público).
6. Notion: confirmar que ninguna página publicada en la web lleve el enlace de «todo el tablero».
7. GitHub: activar «Automatically delete head branches» y borrar las ramas `claude/*` mergeadas.

## Registro
- 2026-11-23: creado. Auditoría completa (archivos, historial, PRs, logs de Actions, endpoints sin sesión).
  Ninguna llave se filtró: no hay que rotar credenciales. PR #4 abierto.
- 2026-11-23: Jordi eligió reescribir y seguir público. PR #4 cerrado (no quiere publicar desde la Mac).
  Historial reescrito: nombres, montos, correos (también el del autor de los commits, ahora noreply) e IDs
  de cuenta fuera de todos los commits; el árbol de `main` quedó idéntico. Respaldo del historial viejo
  solo en la Mac (`~/HubEdicion/.respaldo-historial-2026-11-23.bundle`).
- 2026-11-26: GitHub Support borró los PRs #1–#4 y, tras un segundo aviso, purgó los commits viejos:
  los hashes viejos dan 404 en la web y en la API sin sesión. Ticket cerrado de nuestro lado.
  El clon de la Mac ya estaba realineado: el P5 dejó `--traer` «Al día» sobre la nueva `main` y
  publica con el correo noreply. Quedan los pasos menores 5 a 7.
