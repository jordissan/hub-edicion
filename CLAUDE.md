# Hub de Edición (cloud)

Contexto general: `README.md` (operar la nube), `docs/arquitectura.md` (referencia técnica) y
`docs/guia-de-uso.md` (guía de uso, el README de la Mac).

## Mapa del repo
- Dashboard desplegado: `index.html`, `server.py`, `fonts/`, `functions/`, `embed/`, `publish.py`.
- Sistema de la Mac (copias): `mac/` (app del sprint, Siri), `widgets/` (Scriptable, SwiftBar),
  `scripts/` (`sync-cloud.sh`, `privacidad.py`…), `docs/`. La fuente de verdad es `~/HubEdicion` en la Mac:
  ahí se editan y `sync-cloud.sh` los copia aquí con limpieza. Lo que no sube: `docs/solo-en-la-mac.md`.
- **El repo es público:** nada de llaves, IDs, correos, nombres de parejas o clientes, ni precios.
  `privacidad.py revisar` lo vigila antes de cada publicación.

## Pendientes entre sesiones
@pendientes/README.md

Cuando Jordi diga «revisa los pendientes», «guárdalo como pendiente» o «ejecuta el pendiente…»,
sigue ese protocolo. La lista está en `pendientes/INDICE.md` de la rama `main`.
