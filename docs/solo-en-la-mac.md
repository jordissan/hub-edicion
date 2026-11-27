# Lo que vive solo en la Mac (y por qué)

El repo es **público**. Aquí está todo lo necesario para entender, mantener y reconstruir el
Hub de Edición. Lo que sigue se queda en `~/HubEdicion` de la Mac a propósito: o tiene datos
reales (clientes, parejas, precios, llaves) o se regenera solo.

## Cómo se mantiene al día

`./sync-cloud.sh` (en la raíz de `~/HubEdicion`) copia todo lo que sube. Hay dos maneras de copiar:

- **Tal cual:** `index.html`, `server.py` y `fonts/`, que son el dashboard que se despliega.
- **Con limpieza** (`privacidad.py copiar`): docs, `mac/`, `widgets/` y las herramientas de la
  raíz. Los nombres reales de parejas y estudios se cambian por nombres de ejemplo, los montos
  en pesos por `$XX,XXX`, y los enlaces de los `.md` se re-apuntan a su lugar en el repo.

Antes de publicar, `privacidad.py revisar` lee **todo** lo que git subiría. Si encuentra una
llave real, un correo, un ID de Notion o Cloudflare, un nombre real o una captura, se detiene
y no sube nada. Las llaves que busca tal cual son el token de Notion, el secreto de `/embed` y
el Service Token de los widgets. Las lee de la Mac y nunca las muestra.

| En la Mac (`~/HubEdicion`) | En el repo |
|---|---|
| `README.md` (guía de uso) | `docs/guia-de-uso.md` |
| `docs/*.md`, `docs/propuestas/auditoria-diseno-2026-11-10.md` | igual |
| `mac/SprintFlotante/`, `mac/Siri/make-shortcuts.py` | igual |
| `widgets/` (scripts de Scriptable, SwiftBar, `atajo/make-atajo.py`) | igual |
| `sync-cloud.sh`, `privacidad.py`, `snapshot-demo.py`, `start.command`, `com.jordi.hub-edicion.plist` | `scripts/` |
| `CLAUDE.md` (solo apunta a `cloud/`) | `CLAUDE.md` del repo |

`publish.py`, `functions/`, `embed/`, `pendientes/`, `README.md` y `CLAUDE.md` del repo viven
solo en `cloud/` y se editan ahí.

## Lo que no sube

| Qué | Por qué |
|---|---|
| `.cache.json`, `.archive.json`, `.sprint-state.json`, `.outbox.json` | Son los datos reales de Notion y del sprint. |
| `.embed-secret`, `~/.notion-dashboard-token`, `.privacidad.json` | Son llaves, y el mapa de nombres reales a nombres de ejemplo. |
| Llaves de los widgets (iCloud → Scriptable) | En el repo los scripts llevan `PEGA_AQUI_…`. La llave real solo está en el teléfono. |
| `docs/reportes/` (reporte de bodas) | Está hecho de datos de clientes: nombres, precios y horas por boda. |
| `docs/capturas/`, PNG/JPG de `docs/propuestas/` y el PDF de la auditoría | Casi la mitad de las capturas muestra parejas o montos reales. Además pesan ~100 MB, y la auditoría ya está en `.md`. |
| Maquetas HTML de `docs/propuestas/` (identidad, carrera, reacomodo) | Llevan datos reales embebidos. Esos diseños ya son parte de `index.html`. |
| `docs/historico/` (respaldos de `index.html`, widgets y app) | Son versiones viejas, pesadas y con datos reales. La historia buena está en `git log`. |
| `*.shortcut` (atajos firmados) | Se regeneran con `make-atajo.py` / `make-shortcuts.py`, y la firma lleva un identificador de la cuenta de Apple. |
| `docs/propuestas/trazo/patch_trazo.py` | Fue un parche de una sola vez y ya está aplicado. |
| `icon-*.png`, `manifest.json` de la raíz | Ya están en el repo, son los mismos. |
| `.retirado/` | Piezas del sync GitHub → Mac que se apagó el 27-nov-2026 (se borra tras unos días sin problemas). |

## Migrar a otra máquina

1. Clona el repo, y en la Mac nueva copia `index.html`, `server.py`, `fonts/` y lo de
   `scripts/` a la raíz de `~/HubEdicion`. Clona el repo dentro, como `cloud/`.
2. Pon el token de Notion en `~/.notion-dashboard-token` (ver `docs/guia-de-uso.md`) y el
   secreto de `/embed` en `.embed-secret`. Es el mismo valor que `EMBED_SECRET` en Cloudflare Pages.
3. App del sprint: `mac/SprintFlotante/build.sh`. Atajos: `python3 mac/Siri/make-shortcuts.py`
   y `python3 widgets/atajo/make-atajo.py`.
4. Servidor al arrancar: `scripts/com.jordi.hub-edicion.plist` → `~/Library/LaunchAgents/`.
5. `.cache.json` se rehace solo desde Notion. `.archive.json` (las bodas que ya salieron del
   tablero) cópialo a mano de la Mac vieja; la nube guarda su propia copia en Cloudflare KV.
