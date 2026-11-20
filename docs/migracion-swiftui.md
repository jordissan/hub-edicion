# Migración del Dashboard a app nativa SwiftUI — nota de decisión

> **Estado:** explorado · **no iniciado** · aparcado para futuro
> **Fecha:** 2026-06-28
> **Alcance:** migrar **solo el dashboard** (Hub de Edición) a una app nativa Mac + iPhone (SwiftUI).
> **NO incluye:** reemplazar Notion. Notion **sigue siendo** donde se captura todo (bodas, etapas, sesiones, escenas, avances, links, precios).

---

## 1. Contexto / arquitectura actual

```
Notion (workspace "Trabajo")  ← captura y fuente de verdad (NO se toca)
        │  API
        ▼
server.py (extractor)  →  build_data / build_wedding  →  modelo del dashboard (JSON)
        │
        ├─ Local:  http://localhost:4599  (launchd · backup/dev con datos reales)
        └─ Cloud:  GitHub Actions (cron 30 min) → Cloudflare KV
                   Cloudflare Pages: index.html + /api/edicion + /api/summary
                   Protegido con Cloudflare Access (PIN mensual)
        │
        ▼
Frontend hoy:
  · index.html (dashboard web · PWA instalada en iPhone + Mac)
  · Widgets: Scriptable (iPhone) + SwiftBar (Mac) leen /api/summary
```

Repos/archivos: dashboard web es `index.html` (raíz local + `cloud/` desplegado).
Detalle en [`README.md`](guia-de-uso.md) y [`cloud/README.md`](../README.md).

## 2. La pregunta

¿Vale la pena migrar el **dashboard** a una app nativa SwiftUI (Mac + iPhone), o lo que ya hay
(PWA web) resuelve bien la necesidad y no se notaría tanta mejora?

## 3. Conclusión

Es **viable y de esfuerzo moderado** — *si se reutiliza el backend actual* (el extractor en
Cloudflare ya sirve el JSON; la app Swift solo lo consume). Pero es un **upgrade de
calidad/experiencia, no arregla nada roto**: la PWA actual ya cubre lo esencial.

**Recomendación:** no reescribir todo de golpe. **Reusar el backend, hacer swap solo del
frontend**, y **empezar por los widgets nativos** (mayor ganancia, menor riesgo).

## 4. Qué mejoraría de verdad (áreas)

- **Widgets nativos (WidgetKit):** Home / Lock Screen / StandBy en iPhone + menú-bar en Mac,
  un solo código. Es la parte más débil/frágil hoy (Scriptable/SwiftBar — el widget ya se
  rompió una vez). **Mayor ganancia, menor esfuerzo.**
- **Notificaciones:** "entrega estimada hoy", "te faltan 2h para la meta", deadline de etapa.
  La web no puede; la app nativa sí.
- **Sin el PIN de Cloudflare Access:** credenciales en Keychain → la app abre directo, sin
  re-login mensual.
- **Offline + lanzamiento instantáneo:** cachea el último dato y funciona sin señal.
- **Swift Charts:** dejar de pelear con SVG hecho a mano (colisiones de etiquetas, viewBox,
  responsive). Gráficas nativas, interactivas, gratis.
- **Integración con el OS:** Atajos/Siri ("¿cuántas horas llevo hoy?"), Spotlight, Handoff
  Mac↔iPhone, y posible Live Activity con el cronómetro de la sesión activa.

## 5. Costos / implicaciones reales

- **Velocidad de iteración (el costo clave):** hoy iteramos rapidísimo (editar `index.html`
  → push → recargar). Con Swift cada cambio es build en Xcode + provisioning + instalar en
  los dispositivos. Pesa **mucho** si todavía se va a iterar bastante el dashboard.
- **Cuenta Apple Developer:** ~$99/año para instalar cómodo (con cuenta gratis se puede, pero
  hay que re-firmar cada 7 días).
- **Reimplementar las vistas en SwiftUI** (hero, KPIs, donut, barras, gantt, drilldown,
  evolución) y **portar o reusar** la lógica de parseo de Notion.
- Diferencias por plataforma (Mac vs iPhone) aunque SwiftUI comparte la mayoría.

## 6. La jugada inteligente (plan por fases)

**Fase 0 — Reusar backend.** No tocar el extractor (`server.py`) ni Cloudflare. La app Swift
consume el JSON existente (`/api/edicion`, `/api/summary`). Cero riesgo en datos.

**Fase 1 — Widgets nativos primero (WidgetKit).** Reemplazar Scriptable/SwiftBar leyendo el
mismo `/api/summary`. Mayor salto nativo con el menor trabajo, sin tocar el dashboard.

**Fase 2 — App del dashboard en SwiftUI.** Solo si la Fase 1 convence. Consume el mismo JSON;
reimplementa las vistas con SwiftUI + Swift Charts. Capa visual nueva, datos intactos.

**Fase 3 (opcional) — Extras nativos.** Notificaciones, Atajos/Siri, Live Activity, Handoff.

## 7. Cuándo NO hacerlo (todavía)

- Si se va a **seguir iterando mucho** en el contenido/lógica del dashboard → quedarse en web;
  la velocidad de iteración vale más que el barniz nativo.
- Si la PWA actual ya "se siente suficiente" en el día a día.

## 8. Próximo paso concreto (cuando se retome)

Estimar el alcance de la **Fase 1 (widgets nativos)**: qué tamaños/pantallas (small/medium/large,
Lock Screen, menú-bar), qué métricas mostrar, y cuánto código. Es la decisión de menor riesgo y
mayor rendimiento para "probar lo nativo" sin comprometerse a reescribir todo.

> Nota: el código de la app **Musical** (Swift, descarga música desde links de Notion) no está
> en este repo; si se reusa su arquitectura/infra, hay que revisarlo aparte.
