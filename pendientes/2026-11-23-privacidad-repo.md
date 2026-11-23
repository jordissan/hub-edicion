# P4 · Cerrar la información sensible del repo público

- **Estado:** En curso
- **Dónde se ejecuta:** Nube + Mac
- **Creado:** 2026-11-23, desde la web
- **Resumen:** Auditoría hecha. Lo actual está limpio y el dashboard está cerrado tras Access; falta
  decidir cómo cerrar el historial de git (repo privado o reescribirlo). El detalle vive fuera del repo.

## Plan
1. Decidir la ruta del historial: repo privado (recomendada, reversible) o reescribir historial.
2. PR #4: publicar desde la Mac (`publish.py` con `~/.hub-cloudflare`), Actions solo de respaldo cada 6 h.
   Requisito para volver privado sin rebasar los minutos gratis de Actions.
3. En la Mac: crear el token de Cloudflare (solo KV Edit) y `~/.hub-cloudflare`; comprobar en el log
   «publicada desde el Mac».
4. Ejecutar la ruta elegida (cambiar visibilidad, o `git filter-repo` + force push + rehacer el clon).
5. Menores: IDs de Notion de `server.py` y el precio por defecto a configuración local (solo si sigue público).
6. Notion: confirmar que ninguna página publicada en la web lleve el enlace de «todo el tablero».
7. GitHub: activar «Automatically delete head branches» y borrar las ramas `claude/*` mergeadas.

## Registro
- 2026-11-23: creado. Auditoría completa (archivos, historial, PRs, logs de Actions, endpoints sin sesión).
  Ninguna llave se filtró: no hay que rotar credenciales. PR #4 abierto.
