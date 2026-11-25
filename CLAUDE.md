# Hub de Edición (cloud)

Contexto general: `README.md` (operar la nube), `docs/arquitectura.md` (referencia técnica) y
`docs/guia-de-uso.md` (guía de uso, el README de la Mac).

## Dónde vive cada cosa (léelo primero)
Cada cosa vive en un solo lugar; los demás apuntan a él, no la copian.

| Pieza | Qué guarda | Quién la cambia |
|---|---|---|
| Notion › Trabajo › **🤖 Contexto Claude** (busca «Contexto Claude») | Negocio, estado, decisiones y el mapa del sistema. Puerta de entrada para cualquier proyecto de Claude. | El proyecto «Trabajo» de Claude |
| Bases de Notion (Trabajo, Sesiones por boda/etapa) | Los datos. El Hub solo los lee y registra sesiones. | Jordi, el sprint y los widgets |
| Este repo (público) | Lo técnico: código, `CLAUDE.md`, `docs/`, `pendientes/`. Nada privado. | Sesiones de Claude (PR o `main`, según las reglas de abajo) |
| `~/HubEdicion` en la Mac | El sistema vivo: datos reales, llaves, servidor local, app y widgets. | Jordi y Claude Code en la Mac |
| Cloudflare Pages (`hub-edicion.pages.dev`) | Solo muestra: lo publica GitHub Actions. Notion lo embebe y los widgets lo leen. | Nadie a mano |

**Cuándo se actualiza qué:**
- Un cambio que altera cómo funciona algo (PR mergeado o publicación desde la Mac) → `docs/arquitectura.md`
  en la Mac y una línea en el Registro de la página de Notion.
- Una decisión de negocio → solo la página de Notion.
- Una idea para después → un pendiente en `pendientes/`.
- Un dato → solo su base de Notion.
- Desde otro proyecto de Claude (Finanzas, Iglesia, Personal): se lee la página de Notion y este repo; no se
  editan.

## Mapa del repo
- Dashboard desplegado: `index.html`, `server.py`, `fonts/`, `functions/`, `embed/`, `publish.py`.
- Sistema de la Mac (copias): `mac/` (app del sprint, Siri), `widgets/` (Scriptable, SwiftBar),
  `scripts/` (`sync-cloud.sh`, `privacidad.py`…), `docs/`. La fuente de verdad es `~/HubEdicion` en la Mac:
  ahí se editan y `sync-cloud.sh` los copia aquí con limpieza. Lo que no sube: `docs/solo-en-la-mac.md`.
- Viven solo en el repo (se editan aquí): `README.md`, `CLAUDE.md`, `pendientes/`, `publish.py`,
  `functions/`, `embed/`, `.github/`, `.gitignore`.
- **El repo es público:** nada de llaves, IDs, correos, nombres de parejas o clientes, ni precios.
  `privacidad.py revisar` lo vigila antes de cada publicación.

## Las dos carpetas de la Mac
- `~/HubEdicion/` es el sistema vivo: tiene los datos reales y lo que corre (servidor, app, widgets).
  **No es un clon de git.**
- `~/HubEdicion/cloud/` es el clon de este repo. `sync-cloud.sh` lleva lo local hacia aquí con
  limpieza de privacidad.
- **Sync automático GitHub → Mac:** el LaunchAgent `com.jordi.hub-edicion.sync` corre
  `sync-cloud.sh --traer` al iniciar sesión y cada 15 min. Pone `cloud/` al día (solo fast-forward)
  y trae a `~/HubEdicion` lo que cambió en GitHub, pero solo si la copia local no se tocó desde la
  última sincronización. Si `cloud/` tiene cambios a mano, commits sin subir o divergió, avisa con
  una notificación y no toca nada. Estado de la última corrida: `~/HubEdicion/.sync-estado`.
- Lo que no puede traer solo (la copia local también cambió, o el repo lleva nombres de ejemplo,
  como los `.md`) lo avisa, y `sync-cloud.sh` **no publica** hasta que se pase a mano; así un PR
  mergeado nunca se deshace en silencio. `--forzar` pisa lo de GitHub con lo local.
- Nunca copies a ciegas del repo a `~/HubEdicion/`: los `.md`, la app y los widgets del repo pueden
  llevar nombres de ejemplo en lugar de los reales.

## Flujo de trabajo (reglas)
1. **Primero, lo último de GitHub.** En la nube: `git fetch origin main`. En la Mac:
   `~/HubEdicion/sync-cloud.sh --traer` (en Claude Code lo corre solo un hook al abrir la sesión).
   Si avisa de cambios locales sin subir, divergencia o archivos por traer a mano,
   **detente y pregunta**; no fuerces nada.
2. **Directo a `main`** (commit claro en español): documentación, `pendientes/`, `CLAUDE.md`,
   `README.md`, `.gitignore`.
3. **Por PR** para que Jordi lo revise, **sin merge sin su ok**: el dashboard (`index.html`,
   `server.py`, `functions/`, `publish.py`, el workflow), los widgets (`widgets/`), la app de la Mac
   (`mac/`) y las herramientas de `scripts/`.
4. Al abrir o cerrar un pendiente, actualiza `pendientes/INDICE.md`.
5. Nunca subas secretos (`.env`, tokens, credenciales), medios pesados ni bibliotecas de Final Cut.

## Diagnóstico (no hay pruebas automáticas)
Antes de dar un cambio por bueno:

```bash
python3 scripts/privacidad.py revisar .          # nada privado en lo que sube
python3 -m py_compile server.py publish.py scripts/*.py
for f in functions/*/*.js widgets/*.js; do node --check "$f"; done
bash -n scripts/*.sh
python3 - <<'EOF'                                # el JS embebido en index.html
import re, subprocess, tempfile, os
h = open("index.html", encoding="utf-8").read()
for b in re.findall(r"<script(?![^>]*\bsrc=)[^>]*>(.*?)</script>", h, re.S):
    p = tempfile.mktemp(suffix=".js"); open(p, "w").write(b)
    r = subprocess.run(["node", "--check", p]); os.remove(p)
    assert r.returncode == 0
print("index.html: JS sin errores de sintaxis")
EOF
```

Después de un merge a `main`, revisa la corrida de «Publicar dashboard» (Actions) y el deploy de
Cloudflare Pages.

## Qué solo se prueba en la Mac
- El dashboard con **datos reales**: `http://localhost:4599` (servidor de `com.jordi.hub-edicion`).
- La app del sprint (`mac/SprintFlotante/build.sh`), el detector de Final Cut y los atajos de Siri.
- Los widgets: Scriptable en el iPhone y SwiftBar en la barra de menús.
- `privacidad.py revisar` completo: en la nube no tiene las llaves ni los nombres reales, así que
  solo atrapa correos, IDs y binarios.

## Pendientes entre sesiones
@pendientes/README.md

Cuando Jordi diga «revisa los pendientes», «guárdalo como pendiente» o «ejecuta el pendiente…»,
sigue ese protocolo. La lista está en `pendientes/INDICE.md` de la rama `main`.
