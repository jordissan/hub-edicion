# P2 · Detector de Final Cut en la barra de menús

- **Estado:** Hecho
- **Dónde se ejecuta:** Mac (`~/HubEdicion/`, con el server local en `:4599`)
- **Creado:** 2026-11-19, desde el teléfono
- **Resumen:** el reloj de la barra de menús pide iniciar una sesión si trabajas en Final Cut sin
  timer. Decisiones: aviso **A → B** y **todos los extras**.

## Qué hace

Si Final Cut está al frente, estás trabajando y no hay bloque en marcha, el reloj te pide iniciar
una sesión. Si lo ignoras, aparece la ventana flotante. Todo vive en la app del reloj
(`mac/SprintFlotante/main.swift`). No necesita permisos de Accesibilidad.

## Comportamiento

| Paso | Cuándo | Qué pasa |
|---|---|---|
| Cuenta | Final Cut (o Premiere) al frente, sin bloque ni descanso, y tocaste teclado o ratón hace < 3 min | Suma segundos «activo». Si cambias de app, se pausa (no se reinicia). |
| **A** | 2 min activo | Reloj → «¿Iniciar?» + sonido `nudge`. Se pone el tipo **Edición**. El menú gana arriba: «Final Cut sin timer — Iniciar» y «Ahora no». |
| **B** | 5 min más sin iniciar | Se muestra la ventana flotante (sin robar el foco) con la boda y la escena propuestas. |
| Silencio | Lo ignoras | No repite en 20 min. |
| «Ahora no» | Lo eliges | Calla hasta que cierres Final Cut. |
| Reinicio | Inicias un bloque (por cualquier vía) | Contador a 0 y aviso apagado. Si la ventana la abrió el detector, se vuelve a ocultar. |
| Al cerrar | Cierras Final Cut con un bloque corriendo | Diálogo: «Llevas X min. ¿Terminar el bloque?» → Terminar / Seguir. |

**Valores de serie** (en `UserDefaults`, editables en *Opciones → Detector*):

- `det.on` = sí
- `det.apps` = Final Cut + Premiere
- `det.wait` = 120 s
- `det.escalate` = 300 s
- `det.snooze` = 1200 s
- `det.idle` = 180 s
- `snd.nudge` = sonido del aviso (*Opciones → Sonidos*)

## Cómo se construye (piezas)

1. **App al frente:** `NSWorkspace.shared.notificationCenter` →
   `didActivateApplicationNotification` y `didTerminateApplicationNotification`.
   - Final Cut = `com.apple.FinalCut`.
   - Premiere = prefijo `com.adobe.PremierePro`, porque el número de versión cambia.
2. **¿Estás activo?** `CGEventSource.secondsSinceLastEventType(.combinedSessionState, …)`.
   No pide permisos.
3. **Estado del sprint:** el sondeo de 1 s que ya existe (`/api/sprint-state`). Solo cuenta en
   reposo: sin `scSprint`, sin `scSprintBrk` y sin cierre pendiente.
4. **Acciones:** nada nuevo en la página. Reusa:
   - `SprintCmd('tipo:Edición')`
   - `SprintCmd('start')` / `SprintCmd('finish')`
   - `togglePanel()`, o `orderFrontRegardless` directo
   - `Sounds.play("nudge")`
   - el `flash` con texto del reloj
5. **Ajustes:** submenú *Opciones → Detector* con el interruptor, las apps (Final Cut / Premiere)
   y los tiempos (presets).

## Fases

**Fase 0. Preparar (5 min)**

- [ ] `git -C ~/HubEdicion/cloud pull --ff-only`.
- [ ] Comprobar que el server responde: `curl -s localhost:4599/api/sprint-state | head -c 200`.
- [ ] Leer `mac/SprintFlotante/main.swift`: dónde vive el sondeo, `render()`, `flash`, `Sounds`,
      `togglePanel` y `menuNeedsUpdate`.

**Fase 1. Detector y aviso A**

- [ ] Clase `FCPWatcher`: observadores de NSWorkspace, contador de activo y estados
      (`idle` → `nudged` → `escalated` / `snoozed` / `muted`).
- [ ] Engancharlo al sondeo de 1 s. Al pasar a `nudged`: sonido, reloj «¿Iniciar?» y `tipo:Edición`.
- [ ] Ítems del menú «Iniciar» y «Ahora no».
- [ ] Contador a 0 cuando arranca un bloque.

**Fase 2. Escalado B y silencios**

- [ ] A los 5 min de `nudged`: mostrar el panel y recordar que lo abrió el detector.
- [ ] Al iniciar el bloque: ocultar el panel solo si lo abrió el detector.
- [ ] Silencio de 20 min. «Ahora no» dura hasta `didTerminate` de la app vigilada.

**Fase 3. Extras**

- [ ] Diálogo al cerrar Final Cut con un bloque corriendo (`NSAlert` + `NSApp.activate`).
      «Terminar» → `SprintCmd('finish')`.
- [ ] Premiere en la lista de apps.
- [ ] *Opciones → Detector* y la acción `nudge` en *Opciones → Sonidos*.

**Fase 4. Probar**

- [ ] **Bundle de prueba**, como dice `docs/arquitectura.md` §5.1: otro bundle id, otro ejecutable
      y `HUB_BASE=http://localhost:4611` contra un server de prueba, para no tocar el sprint real.
- [ ] Bajar los tiempos con `defaults write <id-prueba> det.wait -int 10` (y `det.escalate 10`).
- [ ] Casos:
  - [ ] Final Cut al frente → A a los 10 s → B a los 20 s.
  - [ ] Iniciar con ⌃⌥N apaga el aviso y oculta el panel.
  - [ ] Durante el descanso no avisa.
  - [ ] «Ahora no» calla hasta cerrar Final Cut.
  - [ ] Cerrar Final Cut con un bloque corriendo → aparece el diálogo.
  - [ ] Sin tocar nada 3 min → deja de contar.
  - [ ] Con `det.on` en no → no hace nada.
- [ ] `HUB_LOG=1` para ver en stderr las transiciones del detector.
- [ ] Prueba real: `./build.sh`, abrir Final Cut, esperar los 2 min.

**Fase 5. Documentar y subir**

- [ ] `docs/arquitectura.md` §5.1: subsección «Detector de Final Cut» (piezas, claves `det.*`,
      cómo probar).
- [ ] `README.md` de `cloud/`: una línea en «Sprint desde la barra de menús».
- [ ] `./sync-cloud.sh` → revisar el diff → `./sync-cloud.sh --publicar "Detector de Final Cut en la barra de menús"`.

## Qué toca la nube

**Casi nada.** La app del reloj es solo local y el detector no cambia `index.html`, `server.py`,
`functions/` ni el payload. A `cloud/` solo llega la documentación, con `sync-cloud.sh`. Si
durante el trabajo sale un cambio en `index.html` (por ejemplo, un `SprintCmd` nuevo), se prueba
en `:4599` y se porta por el mismo camino.

## Listo cuando

- [x] Trabajando en Final Cut sin timer, a los 2 min el reloj pide iniciar y a los 7 min aparece la ventana.
- [x] Ningún aviso durante un bloque o un descanso, ni con Final Cut abierto pero sin uso.
- [x] Cerrar Final Cut con un bloque corriendo ofrece terminarlo.
- [x] Todo se apaga o se ajusta desde *Opciones → Detector*.
- [x] Documentado y publicado con `sync-cloud.sh`.

## Registro
- 2026-11-19: creado.
- 2026-11-19: detector construido, instalado en la Mac y documentado. Probado con un bundle aislado y Final Cut simulado: avisos A y B, pausa al cambiar de app, sin actividad, descanso, «Ahora no», cierre con bloque (Terminar y Seguir) y detector apagado. Ajustes al plan: un descanso ya vencido cuenta como reposo (`scSprintBrk` sigue guardado hasta el siguiente bloque) y 20 min sin editar reinician la cuenta.
- 2026-11-19: hecho. Jordi confirmó que el aviso funciona con Final Cut real; los demás casos quedaron comprobados en la prueba simulada.
