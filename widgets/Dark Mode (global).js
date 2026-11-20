// ─────────────────────────────────────────
//  TOGGLE TEMA GLOBAL — Scriptable
//  Carátula en pantalla de inicio + toggle al abrir.
//  Voltea `const DARK_MODE = true/false` en TODOS los widgets de la lista,
//  dejándolos siempre en el MISMO modo.
//  Desde un ATAJO (12-nov-2026): acción de Scriptable «Run Script» con parámetro
//  "oscuro" | "claro" | "alternar" (vacío = alternar). Fija ese modo en silencio y
//  devuelve al atajo el modo final ("oscuro" o "claro") para que «Definir aspecto» lo siga.
// ─────────────────────────────────────────

// Nombre EXACTO de cada widget (sin .js) que tenga `const DARK_MODE = true/false`.
// Agrega aquí los que quieras que cambien juntos.
const WIDGETS = ["Notion Dashboard", "Hub Edición · Barras", "Hub Edición · Donas"]

// Al tocar la carátula: el atajo «Tema widget» alterna, redibuja y regresa al inicio (18-nov-2026).
const TAP_URL = "shortcuts://run-shortcut?name=Tema%20widget"

const fm  = FileManager.iCloud()
const dir = fm.documentsDirectory()
const pathOf = (name) => fm.joinPath(dir, `${name}.js`)
const RE = /const DARK_MODE\s*=\s*(true|false)/

async function readCode(name) {
  const p = pathOf(name)
  if (!fm.fileExists(p)) return null
  await fm.downloadFileFromiCloud(p)
  return fm.readString(p)
}

// ── Modo actual: del primer widget que tenga el flag ──
let isDark = true
for (const name of WIDGETS) {
  const code = await readCode(name)
  const m = code && code.match(RE)
  if (m) { isDark = m[1] === "true"; break }
}

// Parámetro del atajo (texto). Sin atajo → null.
const fromShortcut = config.runsWithSiri || args.shortcutParameter !== undefined && args.shortcutParameter !== null
const param = String(args.shortcutParameter ?? "").trim().toLowerCase()

// ─────────────────────────────────────────
//  MODO WIDGET → carátula
// ─────────────────────────────────────────
if (config.runsInWidget) {
  // Carátula con la identidad A del dashboard: base OLED/cálida, luz ambiente, grano al 50 %,
  // icono con halo lima y un selector OSCURO | CLARO como los del dashboard.
  const P = isDark
    ? { bg:"#050506", txt:"#f0eee9", mut:"#a6a6ae", dim:"#66666f", sun:"#d9ed2f", hair:"#232329",
        glass:["#ffffff", .05], onBg:"#d9ed2f", onTx:"#15160a", amb:[["#d9ed2f",.17],["#685bc7",.2]], grain:.275, glow:.72 }
    : { bg:"#f0eee9", txt:"#1a1b15", mut:"#585a56", dim:"#7a7a80", sun:"#58700f", hair:"#d2d0c8",
        glass:["#ffffff", .7], onBg:"#1a1b15", onTx:"#d9ed2f", amb:[["#58700f",.26],["#685bc7",.12]], grain:.225, glow:.3 }
  const fam = config.widgetFamily || "small"
  const W = fam === "small" ? 158 : 360, H = fam === "small" ? 158 : 170
  const ctx = new DrawContext(); ctx.size = new Size(W, H); ctx.opaque = true; ctx.respectScreenScale = true
  ctx.setFillColor(new Color(P.bg)); ctx.fillRect(new Rect(0, 0, W, H))
  ;[[-0.1 * W, -0.45 * H, 1.1 * H], [W * 1.05, H * 0.6, 0.9 * H]].forEach(([ox, oy, R], i) => {
    const [c, peak] = P.amb[i], N = 26
    for (let k = 0; k < N; k++) { const rr = R * (1 - k / N)
      ctx.setFillColor(new Color(c, peak / N * 1.08)); ctx.fillEllipse(new Rect(ox - rr, oy - rr, rr * 2, rr * 2)) }
  })
  const n = Math.round(W * H * 0.3), aMax = 44 / 255 * P.grain * 1.25
  for (let i = 0; i < n; i++) { const r = Math.random()
    ctx.setFillColor(new Color(r >= .5 ? "#ffffff" : "#000000", Math.abs(r - .5) * 2 * aMax))
    ctx.fillRect(new Rect(Math.floor(Math.random() * W), Math.floor(Math.random() * H), 1, 1)) }
  ctx.setFillColor(new Color("#ffffff", isDark ? .07 : .6)); ctx.fillRect(new Rect(0, 0, W, 1))

  // icono: luna (oscuro) o sol (claro), con halo contenido
  const ix = 16 + 15, iy = 16 + 15
  for (let k = 6; k >= 1; k--) { const e = 15 + k * 2.2
    ctx.setFillColor(new Color(P.sun, .05 * P.glow * .7)); ctx.fillEllipse(new Rect(ix - e, iy - e, e * 2, e * 2)) }
  ctx.setFillColor(new Color(P.glass[0], P.glass[1])); ctx.fillEllipse(new Rect(ix - 15, iy - 15, 30, 30))
  ctx.setStrokeColor(new Color(isDark ? "#ffffff" : "#1a1b15", .09)); ctx.setLineWidth(1); ctx.strokeEllipse(new Rect(ix - 15, iy - 15, 30, 30))
  ctx.setFillColor(new Color(P.sun))
  if (isDark) {                       // luna creciente: disco menos disco desplazado (color de fondo del botón)
    ctx.fillEllipse(new Rect(ix - 7, iy - 7, 14, 14))
    ctx.setFillColor(new Color(P.bg)); ctx.fillEllipse(new Rect(ix - 3.5, iy - 9.5, 13, 13))
    ctx.setFillColor(new Color(P.glass[0], P.glass[1])); ctx.fillEllipse(new Rect(ix - 3.5, iy - 9.5, 13, 13))
  } else {                            // sol: disco + 8 rayos
    ctx.fillEllipse(new Rect(ix - 4.5, iy - 4.5, 9, 9))
    ctx.setStrokeColor(new Color(P.sun)); ctx.setLineWidth(1.6)
    for (let k = 0; k < 8; k++) { const a = k * Math.PI / 4, p = new Path()
      p.move(new Point(ix + Math.cos(a) * 7.5, iy + Math.sin(a) * 7.5)); p.addLine(new Point(ix + Math.cos(a) * 10, iy + Math.sin(a) * 10))
      ctx.addPath(p); ctx.strokePath() }
  }

  const txt = (s, x, y, w, h, f, c, al) => { ctx.setFont(f); ctx.setTextColor(new Color(c))
    if (al === "center") ctx.setTextAlignedCenter(); else ctx.setTextAlignedLeft(); ctx.drawTextInRect(s, new Rect(x, y, w, h)) }
  txt(isDark ? "DARK MODE" : "LIGHT MODE", 16, 60, W - 32, 14, Font.boldMonospacedSystemFont(11), P.txt, "left")
  txt("Toca para cambiar todos", 16, 76, W - 32, 14, Font.lightSystemFont(11), P.mut, "left")

  // selector OSCURO | CLARO (como .fseg del dashboard): el activo va relleno
  const sy = H - 16 - 26, sw = W - 32, half = (sw - 6) / 2
  const seg = new Path(); seg.addRoundedRect(new Rect(16, sy, sw, 26), 13, 13)
  ctx.addPath(seg); ctx.setFillColor(new Color(P.glass[0], P.glass[1])); ctx.fillPath()
  ctx.addPath(seg); ctx.setStrokeColor(new Color(P.hair)); ctx.setLineWidth(1); ctx.strokePath()
  const onX = isDark ? 19 : 19 + half + 0
  const on = new Path(); on.addRoundedRect(new Rect(onX, sy + 3, half, 20), 10, 10)
  if (isDark) for (let k = 4; k >= 1; k--) { const e = k * 1.2, g = new Path(); g.addRoundedRect(new Rect(onX - e, sy + 3 - e, half + 2 * e, 20 + 2 * e), 10 + e, 10 + e)
    ctx.addPath(g); ctx.setFillColor(new Color(P.onBg, .05 * P.glow * .7)); ctx.fillPath() }
  ctx.addPath(on); ctx.setFillColor(new Color(P.onBg)); ctx.fillPath()
  txt("DARK", 19, sy + 8, half, 12, Font.boldMonospacedSystemFont(8.5), isDark ? P.onTx : P.dim, "center")
  txt("LIGHT", 19 + half, sy + 8, half, 12, Font.boldMonospacedSystemFont(8.5), isDark ? P.dim : P.onTx, "center")

  const w = new ListWidget()
  w.backgroundColor = new Color(P.bg)
  w.backgroundImage = ctx.getImage()
  w.url = TAP_URL
  Script.setWidget(w)
  Script.complete()

// ─────────────────────────────────────────
//  MODO APP → voltear TODOS al instante (sin confirmación, pedido 3-nov)
// ─────────────────────────────────────────
} else {
  // nuevo modo (todos quedan igual): el que pida el atajo; si no, el contrario del actual
  const target = /^(oscuro|dark|noche)/.test(param) ? true
               : /^(claro|light|d[ií]a)/.test(param) ? false
               : !isDark

  const missing = []
  for (const name of WIDGETS) {
    const p = pathOf(name)
    if (!fm.fileExists(p)) { missing.push(name); continue }
    await fm.downloadFileFromiCloud(p)
    const code = fm.readString(p)
    if (RE.test(code)) fm.writeString(p, code.replace(RE, `const DARK_MODE = ${target}`))
    else missing.push(`${name} (sin flag)`)
  }

  // Desde un atajo: sin ventanas (en segundo plano no se pueden mostrar); se devuelve el modo final.
  if (fromShortcut) {
    Script.setShortcutOutput(target ? "oscuro" : "claro")
    if (missing.length) console.warn(`No se cambiaron: ${missing.join(", ")}`)
  // Solo avisa si algo falló; si todo salió bien, no pregunta ni confirma nada.
  } else if (missing.length) {
    const warn = new Alert()
    warn.title   = "⚠️ No se cambiaron todos"
    warn.message = `${target ? "🌙 Dark" : "☀️ Light"} no se aplicó a:\n${missing.join(", ")}`
    warn.addAction("OK")
    await warn.present()
  }
  Script.complete()
}
