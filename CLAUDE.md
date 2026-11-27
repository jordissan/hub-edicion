# Hub de Edición (cloud)

Contexto general: `README.md` (operar la nube), `docs/arquitectura.md` (referencia técnica) y
`docs/guia-de-uso.md` (guía de uso, el README de la Mac).

## Dónde vive cada cosa (léelo primero)
Cada cosa vive en un solo lugar; los demás apuntan a él, no la copian.

| Pieza | Qué guarda | Quién la cambia |
|---|---|---|
| Notion › Hola 👋 › **📘 Manual de operación** (busca «Manual de operación») | Las reglas comunes a todos los proyectos de Claude: qué leer al empezar, dónde va cada dato y cómo documentar al terminar. Se lee primero. | Cualquier proyecto de Claude, cuando Jordi cambia una regla |
| Notion › Trabajo › **🤖 Contexto Claude** (busca «Contexto Claude») | Negocio, estado, decisiones y el mapa del sistema. Puerta de entrada al área Trabajo. | El proyecto «Trabajo» de Claude |
| Bases de Notion (Trabajo, Sesiones por boda/etapa) | Los datos. El Hub solo los lee y registra sesiones. | Jordi, el sprint y los widgets |
| Este repo (público) | Lo técnico: código, `CLAUDE.md`, `docs/`, `pendientes/`. Nada privado. | Solo `sync-cloud.sh --publicar` desde la Mac |
| `~/HubEdicion` en la Mac | La fuente de verdad: datos reales, llaves, servidor local, app y widgets. Se trabaja aquí primero. | Jordi y Claude Code en la Mac |
| Cloudflare Pages (`hub-edicion.pages.dev`) | Solo muestra: lo publica GitHub Actions. Notion lo embebe y los widgets lo leen. | Nadie a mano |

**Cuándo se actualiza qué:**
- Un cambio que altera cómo funciona algo (publicación desde la Mac) → `docs/arquitectura.md`
  en la Mac y una línea en el Registro de la página de Notion.
- Una decisión de negocio → solo la página de Notion.
- Una idea para después → un pendiente en `pendientes/`.
- Un dato → solo su base de Notion.
- Desde otro proyecto de Claude (Finanzas, Personal): se sigue el Manual de operación (Manual → Contexto
  Claude del área → Registro de las otras áreas). Lo técnico de este repo sigue las reglas de abajo.

## Mapa del repo
- Dashboard desplegado: `index.html`, `server.py`, `fonts/`, `functions/`, `embed/`, `publish.py`.
- Sistema de la Mac (copias): `mac/` (app del sprint, Siri), `widgets/` (Scriptable, SwiftBar),
  `scripts/` (`sync-cloud.sh`, `privacidad.py`…), `docs/`. La fuente de verdad es `~/HubEdicion` en la Mac:
  ahí se editan y `sync-cloud.sh` los copia aquí con limpieza. Lo que no sube: `docs/solo-en-la-mac.md`.
- Viven solo en el repo (se editan aquí): `README.md`, `CLAUDE.md`, `pendientes/`, `publish.py`,
  `functions/`, `embed/`, `.github/`, `.gitignore`.
- **El repo es público:** nada de llaves, IDs, correos, nombres de parejas o clientes, ni precios.
  `privacidad.py revisar` lo vigila antes de cada publicación.

## Las dos carpetas de la Mac (local primero)
- `~/HubEdicion/` es el sistema vivo y **la fuente de verdad**: tiene los datos reales y lo que corre
  (servidor, app, widgets). Todo se edita y se prueba ahí primero. **No es un clon de git.**
- `~/HubEdicion/cloud/` es el clon de este repo. `sync-cloud.sh` lleva lo local hacia aquí con
  limpieza de privacidad; GitHub y Cloudflare solo reciben.
- **Freno:** antes de copiar, `sync-cloud.sh` pone `cloud/` al día con GitHub (solo fast-forward). Si
  GitHub trae cambios de un archivo que nace en la Mac y no salió de ahí, se detiene en lugar de
  pisarlos; `--forzar` los pisa con lo local.
- **Candado:** `cloud/.git/hooks/pre-push` corre `privacidad.py revisar` ante cualquier push.
- Nunca copies a ciegas del repo a `~/HubEdicion/`: los `.md`, la app y los widgets del repo llevan
  nombres de ejemplo en lugar de los reales.
- Del 21 al 27-nov-2026 hubo un sync al revés (GitHub → Mac, `--traer`) para trabajar desde la nube.
  Se retiró; detalle en `docs/arquitectura.md` §8.

## Flujo de trabajo (reglas)
1. **Se trabaja en la Mac**, con Claude Code en `~/HubEdicion`. Antes de empezar, `git -C cloud status`
   debe estar limpio y en `main`; si no, **detente y pregunta**.
2. Lo que nace en la Mac (`index.html`, `server.py`, `docs/`, `mac/`, `widgets/`, las herramientas de
   la raíz) se edita en `~/HubEdicion`, se prueba con datos reales (`http://localhost:4599`, la app o
   los widgets) y se publica con `./sync-cloud.sh --publicar "mensaje"` cuando Jordi da el ok.
3. Lo que vive solo en el repo (`README.md`, `CLAUDE.md`, `pendientes/`, `publish.py`, `functions/`,
   `embed/`, `.github/`, `.gitignore`) se edita en `~/HubEdicion/cloud/` y sale con la misma
   publicación (commit claro en español).
4. No se edita en GitHub ni en sesiones en la nube; si pasa con un archivo que nace en la Mac, el freno
   detiene la siguiente publicación. La única excepción son los pendientes (ver `pendientes/README.md`).
5. Al abrir o cerrar un pendiente, actualiza `pendientes/INDICE.md`.
6. Nunca subas secretos (`.env`, tokens, credenciales), medios pesados ni bibliotecas de Final Cut.

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

Después de publicar, revisa la corrida de «Publicar dashboard» (Actions) y el deploy de
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
