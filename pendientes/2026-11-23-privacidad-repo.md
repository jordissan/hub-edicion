# P4 · Cerrar la información sensible del repo público

- **Estado:** En curso
- **Dónde se ejecuta:** Nube + Mac
- **Creado:** 2026-11-23, desde la web
- **Resumen:** Auditoría hecha y historial reescrito (el repo sigue público). Faltan pasos de Jordi:
  pedir a GitHub que purgue los PRs viejos y realinear el clon de la Mac. El detalle vive fuera del repo.

## Plan
1. ~~Decidir la ruta~~: reescribir el historial y seguir público (2026-11-23).
2. ~~Reescribir con `git filter-repo`~~ sin tocar el árbol actual de `main`; force push a `main`.
3. Mac: realinear `~/HubEdicion/cloud` a la nueva `main`, nuevo `.sync-base` y correo noreply en git.
4. GitHub Support: pedir que borren los PRs #1–#4 y purguen los commits viejos (siguen accesibles por hash).
5. Borrar la rama `claude/project-thread-cixs7o` en GitHub (ya apunta a la nueva `main`).
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
