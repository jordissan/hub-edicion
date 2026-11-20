// Variables used by Scriptable.
// These must be at the very top of the file. Do not edit.
// icon-color: deep-green; icon-glyph: chart-pie;
// ╔══════════════════════════════════════════════════════════════════╗
// ║  Hub Edición · Donas — Widget de iPhone (Scriptable)               ║
// ║  Reproduce la tarjeta "Horas y $ por etapa" del dashboard: la      ║
// ║  dona de la boda en curso, el tiempo exacto en el centro y, por    ║
// ║  fase, horas · $ · %. Hermano del widget de barras                 ║
// ║  ("Hub Edición · Barras"): misma nube, misma llave, mismo tema.    ║
// ╠══════════════════════════════════════════════════════════════════╣
// ║  Poner en el iPhone: mantén pulsada la pantalla → "+" →            ║
// ║  Scriptable → Pequeño, Mediano o Grande → toca el widget →         ║
// ║  Script: "Hub Edición · Donas".                                    ║
// ║  Parameter (opcional): parte del nombre de una boda, p. ej.        ║
// ║  "emilio" o "paula". Vacío = la boda en curso (la misma que    ║
// ║  abre el dashboard).                                              ║
// ╚══════════════════════════════════════════════════════════════════╝

// ── Configuración ────────────────────────────────────────────────────
const HOST = "https://hub-edicion.pages.dev";
const API  = HOST + "/api/edicion";       // el mismo payload que lee el dashboard

// Service Token de Cloudflare Access: los MISMOS dos valores que el widget de barras.
const ACCESS_CLIENT_ID     = "PEGA_AQUI_EL_CLIENT_ID.access";
const ACCESS_CLIENT_SECRET = "PEGA_AQUI_EL_CLIENT_SECRET";

// ── Tema: claro/oscuro (lo voltea el script "Dark Mode") ──────────────
// Identidad A · "Difusión": misma base, luz ambiente, grano y halos que el widget de barras;
// colores por fase = los del dashboard (--f-prep, --f-teas, --sun-data, --violeta, --naranja).
const DARK_MODE = false;
const PALETTES = {
  dark:  { bg:"#050506", txt:"#f0eee9", mut:"#a6a6ae", dim:"#878791", title:"#a6a6ae", hair:"#232329",
           track:"#d7d7f6", trackA:.1, warn:"#de6b45",   // pista = luz al 10 % ≈ #1a1a1e sobre el negro
           ph:{ prep:"#5aa3ec", teas:"#40d9c1", doc:"#d9ed2f", hl:"#685bc7", cam:"#de6b45" },
           amb:[["#d9ed2f",.17],["#685bc7",.2],["#de6b45",.09]], grain:.275, glow:.72,
           halo:{ r:6.6, peak:.155 } },
  light: { bg:"#f0eee9", txt:"#1a1b15", mut:"#585a56", dim:"#66666c", title:"#585a56", hair:"#000000", hairA:.056,
           track:"#000000", trackA:.044, warn:"#d9642c",   // pista = tinta negra al 4,4 % ≈ #e6e4dd sobre el crema
           ph:{ prep:"#3b82d6", teas:"#0e9683", doc:"#799100", hl:"#685bc7", cam:"#d9642c" },
           amb:[["#58700f",.26],["#685bc7",.12],["#e0713a",0]], grain:.225, glow:.3,
           halo:{ r:6.6, peak:.155 } },
};
const _P = DARK_MODE ? PALETTES.dark : PALETTES.light;
const col = (hex, a) => new Color(hex, a == null ? 1 : a);

// ── Modelo: lo mismo que deriveModel()/projModel() de index.html ──────
const round1 = n => Math.round(n * 10) / 10;
const isCorr = s => !!s.isCorrections;
const effH = w => (w.stages || []).reduce((a, s) => a + (isCorr(s) ? 0 : (s.hours || 0)), 0);
const totH = w => (w.stages || []).reduce((a, s) => a + (s.hours || 0), 0);
const hasLive = w => (w.stages || []).some(s => s.estado === "live" && !isCorr(s));
const DELIVERED_ST = /^(finalizad|hecho|complet|done|correc)/;
const editPending = w => (w.stages || []).some(s => !isCorr(s) && s.estado !== "done");
const inProgress = w => hasLive(w) ||
  (!w.archived && effH(w) > 0 && editPending(w) && !DELIVERED_ST.test((w.status || "").trim().toLowerCase()));
const noAcc = s => (s || "").normalize("NFD").replace(/[̀-ͯ]/g, "").toLowerCase().trim();
const slug = s => noAcc(s).replace(/[^a-z0-9]+/g, "-").replace(/^-|-$/g, "");
const PREP_ROLES = new Set(["setup", "escenas", "limpieza", "sync"]);
function roleOf(s) {
  const n = noAcc(s.etapa);
  if (isCorr(s)) return "cambios";
  if (/importacion|setup/.test(n)) return "setup";
  if (/separacion|^escenas/.test(n)) return "escenas";
  if (/limpieza/.test(n)) return "limpieza";
  if (/sincroniz/.test(n)) return "sync";
  return n;
}
function phaseOf(s) {
  if (isCorr(s)) return "cam";
  const f = noAcc(s.fase), n = noAcc(s.etapa);
  if (/teas/.test(f) || /\(teas/.test(n)) return "teas";
  if (/hl|sf/.test(f) || /\(hl|\(sf|hl\/sf/.test(n)) return "hl";
  if (/prep/.test(f)) return "prep";
  if (PREP_ROLES.has(roleOf(s))) return "prep";   // plantilla vieja: "Documental" incluía la preparación
  return "doc";
}
const PHASE_ORDER = ["prep", "teas", "doc", "hl", "cam"];
const PH_NM = { prep:"Preparación", teas:"Teaser", doc:"Documental", hl:"Highlights / Same-day", cam:"Cambios" };
const PH_SHORT = { ...PH_NM, hl:"HL / SF" };
const PRICE_DEFAULT = 13000;                      // si una boda no tiene "Total" en Notion

// bodas que ya salieron del tablero: se rearman desde su "ghost" del archivo (como el dashboard)
function fromArchive(P) {
  const onBoard = new Set((P.weddings || []).map(w => (w.name || "").trim().toLowerCase()));
  return (P.archive || []).filter(a => a.ghost && a.name && !onBoard.has(a.name.trim().toLowerCase()))
    .map(a => ({ name:a.name, price:a.price, archived:true, lastEnd:a.lastEnd || a.ghost.projectEnd || "",
      stages:(a.ghost.stages || []).map(s => ({ etapa:s.etapa, fase:s.fase, isCorrections:!!s.isCorrections,
        estado:s.estado === "live" ? "done" : (s.estado || "done"), hours:s.hours })) }))
    .filter(w => effH(w) > 0);
}
const lastEffDate = w => { let m = null;
  for (const s of (w.stages || [])) { if (isCorr(s)) continue;
    for (const x of (s.sessionLog || [])) if (x.inicio && (m == null || x.inicio.slice(0, 10) > m)) m = x.inicio.slice(0, 10); }
  return m || w.projectEnd || w.projectStart || w.lastEnd || ""; };

// La boda a pintar. Sin parámetro: la que abre el dashboard (en curso; si no, la última terminada).
// Con parámetro: la primera cuyo nombre contenga ese texto (también las del archivo).
function pickWedding(P, param) {
  const measured = (P.weddings || []).filter(w => effH(w) > 0);
  const sorted = measured.slice().sort((a, b) => {
    const la = inProgress(a) ? 0 : 1, lb = inProgress(b) ? 0 : 1;
    if (la !== lb) return la - lb;
    return (b.projectStart || "").localeCompare(a.projectStart || "");
  });
  const q = slug(param || "");
  if (q) {
    const pool = sorted.concat(fromArchive(P));
    return pool.find(w => slug(w.name) === q) || pool.find(w => slug(w.name).includes(q)) || null;
  }
  const live = sorted.find(inProgress);
  if (live) return live;
  const done = measured.filter(w => !inProgress(w)).sort((a, b) => lastEffDate(b).localeCompare(lastEffDate(a)));
  return done[0] || sorted[0] || null;
}

function model(w) {
  const st = w.stages || [];
  const total = round1(totH(w)), price = w.price || PRICE_DEFAULT;
  // segmentos de la dona: etapas con horas, en el orden de Notion
  const etapas = st.filter(s => (s.hours || 0) > 0).map(s => ({ h:round1(s.hours), f:phaseOf(s) }));
  const present = new Set(st.filter(s => !isCorr(s)).map(phaseOf));
  const sum = {}; PHASE_ORDER.forEach(k => sum[k] = 0);
  st.forEach(s => { if ((s.hours || 0) > 0) sum[phaseOf(s)] += s.hours; });
  const gt = total || 1, fases = [];
  PHASE_ORDER.forEach(k => { if (k !== "cam" && present.has(k)) fases.push({ k, h:round1(sum[k]), pct:Math.round(sum[k] / gt * 100) }); });
  const pend = st.some(s => isCorr(s) && s.estado !== "done");
  if (sum.cam > 0) fases.push({ k:"cam", h:round1(sum.cam), pct:Math.round(sum.cam / gt * 100) });
  else if (pend) fases.push({ k:"cam", h:null, pct:null, espera:true });
  return { nm:(w.name || "").trim(), total, price, etapas, fases, live:inProgress(w) };
}

// ── Formatos (iguales al dashboard) ──────────────────────────────────
const fmtHM = h => { const m = Math.round(h * 60); return `${Math.floor(m / 60)}h ${String(m % 60).padStart(2, "0")}m`; };
const fmtMXN = v => "$" + String(Math.round(v)).replace(/\B(?=(\d{3})+(?!\d))/g, ",");
const fmtDur = h => h * 60 < 6 ? Math.max(1, Math.round(h * 60)) + " min" : (Math.round(h * 10) / 10).toFixed(1).replace(".", ",") + " h";

// ── Datos (con memoria, como el de barras) ───────────────────────────
// Cada lectura buena se guarda en el teléfono. Si la siguiente falla (sin internet o acceso de
// Cloudflare caducado) se pinta la última con "GUARDADO · hora" en naranja.
const MEM = (() => { try { const fm = FileManager.local();
  return { fm, path:fm.joinPath(fm.libraryDirectory(), "hub-edicion-dona.json") }; } catch (e) { return null; } })();
function saveLast(d) { try { MEM.fm.writeString(MEM.path, JSON.stringify(d)); } catch (e) {} }
function readLast() {
  try { if (MEM.fm.fileExists(MEM.path)) { const d = JSON.parse(MEM.fm.readString(MEM.path)); if (d && d.weddings) return d; } } catch (e) {}
  return null;
}
function todayKey() { const n = new Date(), p = v => String(v).padStart(2, "0"); return `${n.getFullYear()}-${p(n.getMonth() + 1)}-${p(n.getDate())}`; }
function stampOf(d) {                    // "18:13" si es de hoy; "9 NOV 18:13" si es de otro día
  const g = d.generatedAt || ""; if (g.length < 16) return "";
  const MES = ["ENE","FEB","MAR","ABR","MAY","JUN","JUL","AGO","SEP","OCT","NOV","DIC"];
  return (g.slice(0, 10) !== todayKey() ? `${+g.slice(8, 10)} ${MES[+g.slice(5, 7) - 1]} ` : "") + g.slice(11, 16);
}
async function load() {
  const req = new Request(API);
  req.timeoutInterval = 10;
  req.headers = { "CF-Access-Client-Id":ACCESS_CLIENT_ID, "CF-Access-Client-Secret":ACCESS_CLIENT_SECRET };
  try {
    const d = await req.loadJSON();
    if (d && !d.error && d.weddings) {
      // solo lo que la dona necesita (la memoria queda chica)
      const keep = s => ({ etapa:s.etapa, fase:s.fase, estado:s.estado, isCorrections:s.isCorrections, hours:s.hours,
                           sessionLog:(s.sessionLog || []).map(x => ({ inicio:x.inicio })) });
      const slim = { generatedAt:d.generatedAt, archive:d.archive || [],
        weddings:d.weddings.map(w => ({ name:w.name, status:w.status, price:w.price, projectStart:w.projectStart,
                                        projectEnd:w.projectEnd, stages:(w.stages || []).map(keep) })) };
      saveLast(slim); return slim;
    }
  } catch (e) { /* sin red / sin acceso */ }
  const last = readLast();
  if (last) { last.stale = true; return last; }
  return null;
}

// ── Dibujo ───────────────────────────────────────────────────────────
// La dona: misma geometría que el SVG del dashboard (viewBox 360, R 140, trazo 18, puntas
// redondas, hueco 30 entre segmentos, empieza a las 12 y gira a la derecha). Cada segmento es una
// figura rellena (arco + dos puntas), así el halo es la misma figura un poco más ancha.
function ringShape(cx, cy, R, hw, a0, a1) {
  const u = a => [Math.sin(a), -Math.cos(a)], t = a => [Math.cos(a), Math.sin(a)];
  const pts = [], arcN = Math.max(2, Math.ceil((a1 - a0) / 0.03)), capN = 14;
  for (let i = 0; i <= arcN; i++) { const a = a0 + (a1 - a0) * i / arcN, [ux, uy] = u(a); pts.push(new Point(cx + (R + hw) * ux, cy + (R + hw) * uy)); }
  { const [ux, uy] = u(a1), [tx, ty] = t(a1), ex = cx + R * ux, ey = cy + R * uy;
    for (let i = 1; i < capN; i++) { const f = Math.PI * i / capN; pts.push(new Point(ex + hw * (ux * Math.cos(f) + tx * Math.sin(f)), ey + hw * (uy * Math.cos(f) + ty * Math.sin(f)))); } }
  for (let i = arcN; i >= 0; i--) { const a = a0 + (a1 - a0) * i / arcN, [ux, uy] = u(a); pts.push(new Point(cx + (R - hw) * ux, cy + (R - hw) * uy)); }
  { const [ux, uy] = u(a0), [tx, ty] = t(a0), sx = cx + R * ux, sy = cy + R * uy;
    for (let i = 1; i < capN; i++) { const f = Math.PI * i / capN; pts.push(new Point(sx - hw * (ux * Math.cos(f) + tx * Math.sin(f)), sy - hw * (uy * Math.cos(f) + ty * Math.sin(f)))); } }
  const p = new Path(); p.addLines(pts); p.closeSubpath(); return p;
}
function drawDonut(ctx, p, cx, cy, D) {
  const k = D / 360, R = 140 * k, hw = 9 * k, circ = 2 * Math.PI * 140, gap = 30;
  // pista (--panel2). En los dos temas es casi transparente (claro: tinta negra al 4,4 %; oscuro: luz
  // al 10 %): a todo color da el mismo gris que antes. En la pantalla tintada/transparente iOS pinta la
  // dona (fondo de la pila de nativeCenter) en blanco SEGÚN SU ALFA: una pista opaca salía como un aro
  // blanco continuo que tapaba los huecos; casi transparente, los huecos quedan limpios.
  ctx.setStrokeColor(col(_P.track, _P.trackA)); ctx.setLineWidth(18 * k);
  const tr = new Path(); tr.addEllipse(new Rect(cx - R, cy - R, 2 * R, 2 * R)); ctx.addPath(tr); ctx.strokePath();
  const segs = []; let s = 0; const totalGaps = gap * p.etapas.length;
  for (const e of p.etapas) {
    const len = Math.max(e.h / p.total * (circ - totalGaps), 2);
    segs.push({ a0:s / 140, a1:(s + len) / 140, c:_P.ph[e.f] }); s += len + gap;
  }
  // halo (≈ filtro fxGlowD): capas un poco más anchas y casi transparentes, por debajo de todo
  const N = Math.round(_P.halo.r * k * 2.2 / 1.1) || 1, a = 1 - Math.pow(1 - _P.halo.peak * (_P.glow / .72), 1 / N);
  for (let j = N; j >= 1; j--) for (const g of segs) {
    ctx.addPath(ringShape(cx, cy, R, hw + j * 1.1, g.a0, g.a1)); ctx.setFillColor(col(g.c, a)); ctx.fillPath();
  }
  for (const g of segs) { ctx.addPath(ringShape(cx, cy, R, hw, g.a0, g.a1)); ctx.setFillColor(col(g.c)); ctx.fillPath(); }
}
// el centro: "5h 42m" fino y grande + "tiempo exacto invertido"
function drawCenter(ctx, p, cx, cy, D, sub) {
  const big = Math.round(D * 0.155), w = D * 0.7;
  text(ctx, fmtHM(p.total), cx - w / 2, cy - big * 0.78, w, big * 1.3, Font.lightSystemFont(big), col(_P.txt), "center");
  if (sub) text(ctx, sub, cx - w / 2, cy + big * 0.5, w, 14, Font.systemFont(Math.max(8.5, D * 0.05)), col(_P.mut), "center");
}
// Pequeño: la dona es el fondo de una pila y el total va encima como texto NATIVO. Así, en la pantalla
// tintada/transparente, iOS lo pinta en blanco y se lee (dentro de la imagen, el texto oscuro del tema
// claro casi desaparecía). A todo color queda donde drawCenter() lo ponía: mismas letras, colores y
// posición (el bloque va 2 pt abajo del centro, como en el dibujo).
function nativeCenter(widget, p, ringImg) {
  const D = 140, big = Math.round(D * 0.155), fs = Math.max(8.5, D * 0.05), LH = 1.194;   // alto de línea de SF Pro
  const s = widget.addStack(); s.layoutVertically(); s.backgroundImage = ringImg;
  // drawCenter: 1.ª línea arriba en cy − 0,78·big; 2.ª en cy + 0,5·big → el bloque queda bajo el centro
  s.addSpacer(); s.addSpacer(Math.max(0, fs * LH - 0.28 * big));
  const row = (str, font, color, gapTop) => {
    if (gapTop) s.addSpacer(gapTop);
    const r = s.addStack(); r.layoutHorizontally(); r.addSpacer();
    const t = r.addText(str); t.font = font; t.textColor = color; t.lineLimit = 1; t.minimumScaleFactor = 0.7;
    r.addSpacer();
  };
  row(fmtHM(p.total), Font.lightSystemFont(big), col(_P.txt), 0);
  row("invertido", Font.systemFont(fs), col(_P.mut), Math.max(0, 1.28 * big - big * LH));
  s.addSpacer();
}
// la leyenda por fase: punto · nombre · horas · $ · %   (como .dlr bajo la dona)
function drawLegend(ctx, p, x, y, w, rowH, fs, short) {
  p.fases.forEach((F, i) => {
    const ry = y + i * rowH, cy = ry + rowH / 2, tH = fs + 5, ty = cy - tH / 2;
    const c = F.espera ? col(_P.ph.cam, .55) : col(_P.ph[F.k]);
    glowDot(ctx, x + 3.5, cy, 3.2, c);
    const pctW = fs * 2.6, mxW = fs * 4.6, hW = fs * 3.9, gapC = fs * 0.5;
    const xP = x + w - pctW, xM = xP - gapC - mxW, xH = xM - gapC - hW;
    const nm = F.espera ? "Cambios · en espera" : (short ? PH_SHORT[F.k] : PH_NM[F.k]);
    text(ctx, nm, x + 12, ty, (F.espera ? x + w : xH) - x - 12, tH, Font.regularMonospacedSystemFont(fs), col(_P.mut), "left");
    if (F.h != null) {
      text(ctx, fmtDur(F.h), xH, ty, hW, tH, Font.regularMonospacedSystemFont(fs), col(_P.dim), "right");
      text(ctx, fmtMXN(p.price * F.h / p.total), xM, ty, mxW, tH, Font.boldMonospacedSystemFont(fs), col(_P.txt), "right");
      text(ctx, F.pct + "%", xP, ty, pctW, tH, Font.regularMonospacedSystemFont(fs), col(_P.dim), "right");
    }
    if (i < p.fases.length - 1) { ctx.setFillColor(col(_P.hair, _P.hairA)); ctx.fillRect(new Rect(x, ry + rowH - 0.5, w, 0.5)); }
  });
}
// cabecera: título en mono como la tarjeta + la boda a la derecha
function drawHeader(ctx, p, x0, x1, y) {
  ringIcon(ctx, x0 + 6, y + 6.5, col(_P.ph.doc));
  text(ctx, "HORAS Y $ POR ETAPA", x0 + 18, y, 170, 13, Font.boldMonospacedSystemFont(9.5), col(_P.title), "left");
  text(ctx, p.nm.toUpperCase(), x0 + 180, y + 0.5, x1 - x0 - 180, 13, Font.regularMonospacedSystemFont(8.5), col(_P.dim), "right");
}
function drawStamp(ctx, d, x, y, w, align) {
  if (!d.stale) return;
  text(ctx, "GUARDADO" + (stampOf(d) ? " · " + stampOf(d) : ""), x, y, w, 12, Font.boldMonospacedSystemFont(8), col(_P.warn), align);
}

function drawWidget(d, p, fam) {
  const ctx = new DrawContext();
  const W = fam === "small" ? 158 : 360, H = fam === "small" ? 158 : fam === "large" ? 376 : 170;
  ctx.size = new Size(W, H); ctx.opaque = false; ctx.respectScreenScale = true;

  if (fam === "small") {                           // solo la dona con el total
    const D = 140, cx = W / 2, cy = H / 2;
    drawDonut(ctx, p, cx, cy, D);                  // el centro lo pone nativeCenter() encima
    if (d.stale) dot(ctx, W - 9, 9, 2.5, col(_P.warn));   // punto naranja = dato guardado
  } else if (fam === "medium") {                   // dona a la izquierda + leyenda a la derecha
    const x0 = 16, x1 = W - 16;
    drawHeader(ctx, p, x0, x1, 12);
    const D = 124, cx = x0 + D / 2, cy = 34 + D / 2;
    drawDonut(ctx, p, cx, cy, D);
    drawCenter(ctx, p, cx, cy, D, "invertido");
    const lx = x0 + D + 18, rowH = 21, n = p.fases.length, ly = cy - n * rowH / 2;
    drawLegend(ctx, p, lx, ly, x1 - lx, rowH, 8.5, true);
    drawStamp(ctx, d, lx, H - 20, x1 - lx, "right");
  } else {                                         // grande: dona + lista completa
    const x0 = 18, x1 = W - 18;
    drawHeader(ctx, p, x0, x1, 14);
    // la dona crece hasta llenar lo que deja la lista (3 fases → más grande; 5 → más chica)
    const rowH = 25, top = 36, bottom = H - 22, n = p.fases.length;
    const D = Math.min(212, bottom - top - 14 - n * rowH);
    const block = D + 14 + n * rowH, y0 = top + (bottom - top - block) / 2;
    const cx = W / 2, cy = y0 + D / 2;
    drawDonut(ctx, p, cx, cy, D);
    drawCenter(ctx, p, cx, cy, D, "tiempo exacto invertido");
    const ly = y0 + D + 14;
    drawLegend(ctx, p, x0, ly, x1 - x0, rowH, 10, false);
    drawStamp(ctx, d, x0, H - 20, x1 - x0, "right");
  }
  return ctx.getImage();
}

// ── Materiales de la identidad A (iguales al widget de barras) ───────
// Fondo: luz ambiente + grano al 50 % + filo de luz sobre lienzo TRANSPARENTE; la base va en
// widget.backgroundColor para que el modo vidrio/tintado del sistema la pueda quitar.
function drawBackground(W, H) {
  const ctx = new DrawContext();
  ctx.size = new Size(W, H); ctx.opaque = false; ctx.respectScreenScale = false;
  const orbs = [[-0.08 * W, -0.55 * H, 1.15 * H], [W * 1.02, H * 0.55, 0.95 * H], [W * 0.42, H * 1.25, 0.8 * H]];
  orbs.forEach(([ox, oy, R], i) => {
    const [c, peak] = _P.amb[i], N = 26;
    for (let k = 0; k < N; k++) { const rr = R * (1 - k / N);
      ctx.setFillColor(new Color(c, peak / N * 1.08)); ctx.fillEllipse(new Rect(ox - rr, oy - rr, rr * 2, rr * 2)); }
  });
  const n = Math.round(W * H * 0.3), aMax = 44 / 255 * _P.grain * 1.25;
  for (let i = 0; i < n; i++) { const rnd = Math.random();
    ctx.setFillColor(new Color(rnd >= .5 ? "#ffffff" : "#000000", Math.abs(rnd - .5) * 2 * aMax));
    ctx.fillRect(new Rect(Math.floor(Math.random() * W), Math.floor(Math.random() * H), 1, 1)); }
  ctx.setFillColor(new Color("#ffffff", DARK_MODE ? 0.07 : 0.6)); ctx.fillRect(new Rect(0, 0, W, 1));
  return ctx.getImage();
}
function dot(ctx, cx, cy, r, color) { ctx.setFillColor(color); ctx.fillEllipse(new Rect(cx - r, cy - r, r * 2, r * 2)); }
function glowDot(ctx, cx, cy, r, color) {
  for (let k = 3; k >= 1; k--) dot(ctx, cx, cy, r + k * 1.2, new Color(color.hex ? "#" + color.hex : color, 0.07 * _P.glow * color.alpha));
  dot(ctx, cx, cy, r, color);
}
function ringIcon(ctx, cx, cy, color) {          // mini dona del título (en vez de la flecha de las barras)
  ctx.setStrokeColor(color); ctx.setLineWidth(2);
  const p = new Path(); p.addEllipse(new Rect(cx - 5, cy - 5, 10, 10)); ctx.addPath(p); ctx.strokePath();
}
function text(ctx, s, x, y, w, h, font, color, align) {
  ctx.setFont(font); ctx.setTextColor(color);
  if (align === "center") ctx.setTextAlignedCenter();
  else if (align === "right") ctx.setTextAlignedRight();
  else ctx.setTextAlignedLeft();
  ctx.drawTextInRect(s, new Rect(x, y, w, h));
}

// ── Avisos (sin datos / boda no encontrada / sin horas) ──────────────
function noticeWidget(title, line1, line2) {
  const w = new ListWidget();
  w.backgroundColor = new Color(_P.bg);
  w.backgroundImage = drawBackground(360, 170);
  const t = w.addText(title); t.font = Font.boldMonospacedSystemFont(11); t.textColor = col(_P.txt);
  w.addSpacer(4);
  const s = w.addText(line1); s.font = Font.lightSystemFont(13); s.textColor = col(_P.mut);
  if (line2) { const s2 = w.addText(line2); s2.font = Font.regularMonospacedSystemFont(9.5); s2.textColor = col(_P.dim); }
  w.url = HOST;
  return w;
}

// ── Main ─────────────────────────────────────────────────────────────
const fam = config.widgetFamily || "large";
const param = (args.widgetParameter || "").trim();
const data = await load();
let widget;

if (!data) {
  widget = noticeWidget("Horas y $ por etapa", "Sin datos todavía", "Sin internet o acceso caducado");
} else {
  const wed = pickWedding(data, param);
  const p = wed ? model(wed) : null;
  if (!p) widget = noticeWidget("Horas y $ por etapa", param ? `No encuentro «${param}»` : "No hay bodas medidas", param ? "Revisa el Parameter del widget" : "");
  else if (!(p.total > 0)) widget = noticeWidget("Horas y $ por etapa", `${p.nm}: aún sin horas`, "");
  else {
    widget = new ListWidget();
    widget.setPadding(0, 0, 0, 0);
    widget.url = HOST;                              // tocar = abre el dashboard
    const W = fam === "small" ? 158 : 360, H = fam === "small" ? 158 : fam === "large" ? 376 : 170;
    widget.backgroundColor = new Color(_P.bg);
    widget.backgroundImage = drawBackground(W, H);
    if (fam === "small") nativeCenter(widget, p, drawWidget(data, p, fam));
    else {
      const wi = widget.addImage(drawWidget(data, p, fam));
      wi.applyFittingContentMode();
      wi.centerAlignImage();
    }
  }
}
widget.refreshAfterDate = new Date(Date.now() + 30 * 60 * 1000);

if (config.runsInWidget) Script.setWidget(widget);
else if (fam === "small") await widget.presentSmall();
else if (fam === "medium") await widget.presentMedium();
else await widget.presentLarge();
Script.complete();
