# P1 · Conectar la Mac al sistema de pendientes

- **Estado:** En curso
- **Dónde se ejecuta:** Mac
- **Creado:** 2026-11-19, desde el teléfono
- **Resumen:** que Claude Code abierto en `~/HubEdicion/` conozca este protocolo, para que basten
  frases como «revisa los pendientes».

## Plan

1. `git -C ~/HubEdicion/cloud pull --ff-only`.
2. En `~/HubEdicion/CLAUDE.md` (créalo si no existe) agrega:

   ```markdown
   ## Pendientes entre sesiones
   @cloud/pendientes/README.md
   Antes de «revisa los pendientes» o «ejecuta el pendiente…»: `git -C cloud pull --ff-only`
   y lee `cloud/pendientes/INDICE.md`.
   ```

   El `@` hace que Claude Code cargue el protocolo al abrir cualquier sesión en `~/HubEdicion/`.
3. Comprobar que `sync-cloud.sh` no toca `cloud/pendientes/` ni `cloud/CLAUDE.md` (solo copia
   archivos concretos). Si los tocara, excluirlos.
4. Ojo con `sync-cloud.sh --publicar`: si una sesión desde el teléfono subió un pendiente, el push
   de la Mac puede ser rechazado. Que el script haga `git pull --rebase` antes del push (o
   anotarlo en `docs/arquitectura.md` §8 como paso manual).
5. Prueba: cerrar y abrir Claude Code en `~/HubEdicion/`, decir «revisa los pendientes» y ver la lista.

**Listo cuando:** en una sesión nueva en la Mac, «revisa los pendientes» muestra P2 sin más explicación.

## Registro
- 2026-11-19: creado.
