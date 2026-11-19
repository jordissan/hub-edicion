# Pendientes: cómo se pasan las ideas de una sesión a otra

Aquí quedan los planes que salen de platicar con Claude (desde el teléfono, la web o donde sea)
para ejecutarlos después en otra sesión, normalmente en la Mac. GitHub es el punto de encuentro:
una sesión escribe el pendiente y otra lo lee.

```
pendientes/
  README.md     ← este protocolo
  INDICE.md     ← la lista: qué hay, en qué estado y dónde se ejecuta
  AAAA-MM-DD-nombre.md   ← un archivo por pendiente (el plan completo)
  hechos/       ← los terminados o descartados, con su registro
```

## Frases (para Jordi)

| Dices… | Claude hace… |
|---|---|
| «Guárdalo como pendiente» | Escribe el plan que acordaron como archivo nuevo, lo agrega a `INDICE.md` y lo sube a `main`. |
| «Revisa los pendientes» | Trae lo último de GitHub y te muestra la lista corta: qué hay por hacer y dónde se ejecuta cada uno. |
| «Ejecuta el pendiente P2» (o por nombre) | Lee el plan, lo marca *En curso*, lo hace y al terminar lo marca *Hecho*. |
| «Descarta el P3» | Lo mueve a `hechos/` como *Descartado*, con el motivo. |
| «Actualiza el pendiente P2 con…» | Cambia el plan y deja una nota en su registro. |

## Reglas (para Claude)

1. **Siempre traer lo último antes de leer o escribir.**
   - En la Mac: `git -C ~/HubEdicion/cloud pull --ff-only`. Si falla porque hay cambios locales sin
     subir, avisa y no fuerces nada.
   - En la nube: `git fetch origin main` y leer de `origin/main`.
2. **Dónde viven:** siempre en la rama `main`, carpeta `pendientes/`. Para que el sistema funcione,
   Jordi autoriza que cualquier sesión haga commit y push a `main` **solo de cambios dentro de
   `pendientes/`**. Cualquier otro archivo sigue el camino normal: en la Mac con `sync-cloud.sh`,
   y en la nube en la rama de la sesión.
   - Desde una sesión en la nube sin checkout de `main`: crear un worktree temporal de
     `origin/main`, hacer commit solo en `pendientes/`, `git push origin HEAD:main` y borrar el
     worktree. Si el push falla por cambios nuevos: `pull --rebase` y reintentar.
3. **El repo es público.** En los pendientes no van nombres de clientes ni de parejas, precios,
   tokens, IDs privados ni datos personales. Se describe *qué* hacer, no los datos.
4. **«Revisa los pendientes»** responde corto: una línea por pendiente (ID, título, dónde se
   ejecuta, estado) y la pregunta de cuál ejecutar. Si alguno se ejecuta en otro lugar
   (por ejemplo, «Mac» y estás en la nube), dilo.
5. **Al ejecutar:**
   - marca *En curso* en el archivo y en el índice;
   - sigue el plan; si algo del plan resulta equivocado, ajústalo y anótalo en el registro;
   - al terminar: *Hecho*, una línea de resultado en el registro, mueve el archivo a `hechos/`
     y actualiza el índice;
   - si queda a medias: déjalo *En curso* y apunta en el registro dónde se quedó.
6. **IDs:** `P` + número que no se repite nunca (el siguiente al mayor que exista, contando `hechos/`).

## Formato de un pendiente

```markdown
# P<n> · <título>

- **Estado:** Por hacer | En curso | Hecho | Descartado
- **Dónde se ejecuta:** Mac | Nube | Cualquiera
- **Creado:** AAAA-MM-DD, desde <teléfono / web / Mac>
- **Resumen:** una o dos líneas.

## Plan
(qué se decidió, pasos o fases, cómo probar, cuándo está listo)

## Registro
- AAAA-MM-DD: creado.
```
