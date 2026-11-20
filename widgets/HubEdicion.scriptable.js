// ╔══════════════════════════════════════════════════════════════════╗
// ║  Hub de Edición — Widget de iPhone (Scriptable)                    ║
// ║  Reproduce la gráfica "Horas por día — últimos 7 días" del         ║
// ║  dashboard (mismos colores, leyenda y layout).                    ║
// ╠══════════════════════════════════════════════════════════════════╣
// ║  Instalar:                                                         ║
// ║   1. App "Scriptable" (gratis, App Store).                        ║
// ║   2. Scriptable → "+" → pega TODO este archivo → nómbralo         ║
// ║      "Hub Edición · Barras".                                      ║
// ║   3. Pega tu CLIENT_ID y CLIENT_SECRET del Service Token abajo.    ║
// ║   4. Pantalla de inicio: mantén pulsado → "+" → Scriptable →      ║
// ║      tamaño Mediano (recomendado) o Pequeño.                      ║
// ║   5. Toca el widget → "Script: Hub Edición · Barras".            ║
// ║   Funciona desde CUALQUIER lugar (la Mac puede estar apagada).     ║
// ╚══════════════════════════════════════════════════════════════════╝

// ── Configuración ────────────────────────────────────────────────────
const HOST = "https://hub-edicion.pages.dev";
const API  = HOST + "/api/summary";

// Service Token de Cloudflare Access (Zero Trust → Access → Service credentials).
// Pega aquí los dos valores. El Client ID no es secreto; el Secret sí —
// solo vive en este script, en tu teléfono.
const ACCESS_CLIENT_ID     = "PEGA_AQUI_TU_CLIENT_ID";
const ACCESS_CLIENT_SECRET = "PEGA_AQUI_TU_CLIENT_SECRET";

// ── Tema: claro/oscuro (lo voltea el toggle global "Dark Mode") ───────
// Identidad A · "Difusión" (nov-2026): misma paleta Pantone, luz ambiente, grano y halos que el
// dashboard. SOLO apariencia: la geometría de las barras (alto, ancho, huecos, radios) no cambia.
const DARK_MODE = true;
const PALETTES = {
  dark:  { bg:"#050506", card:"#0b0b0d", prev:"#685bc7", hoy:"#d9ed2f", rec:"#de6b45", sat:"#9a8fe3",
           title:"#a6a6ae", leg:"#a6a6ae", hrs:"#f0eee9", day:"#66666f", meta:"#45454e", track:"#232329",
           // luz ambiente (lima arriba-izq., violeta a la derecha, naranja abajo) · grano · halos
           amb:[["#d9ed2f",.17],["#685bc7",.2],["#de6b45",.09]], grain:.275, glow:.72, fadeTo:.42,
           halo:{ r:6.6, peak:.155 } },   // halo de hoy/récord: radio ≈ 6,6 pt y pico 15,5 % (antes ≈ 10 pt y 20,5 %)
  light: { bg:"#f0eee9", card:"#f7f6f2", prev:"#685bc7", hoy:"#58700f", rec:"#e0713a", sat:"#a99ff0",
           title:"#585a56", leg:"#585a56", hrs:"#1a1b15", day:"#7a7a80", meta:"#c4c2ba", track:"#e3e1da",
           amb:[["#58700f",.26],["#685bc7",.12],["#e0713a",0]], grain:.225, glow:.3, fadeTo:.61,
           fadeAlpha:true,   // claro: el velo es TRANSPARENCIA (como el dashboard), no mezcla con el crema
           halo:{ r:6.6, peak:.155 } },   // mismo halo que en oscuro (antes casi invisible en claro)
};
const _P = DARK_MODE ? PALETTES.dark : PALETTES.light;
const COL = {
  bg: new Color(_P.bg), card: new Color(_P.card), prev: new Color(_P.prev), hoy: new Color(_P.hoy),
  rec: new Color(_P.rec), sat: new Color(_P.sat), title: new Color(_P.title), leg: new Color(_P.leg),
  hrs: new Color(_P.hrs), day: new Color(_P.day), meta: new Color(_P.meta), track: new Color(_P.track),
};
const DOW = ["Dom", "Lun", "Mar", "Mié", "Jue", "Vie", "Sáb"];

// ── Datos ────────────────────────────────────────────────────────────
// Memoria (nov-2026): cada lectura buena se guarda en el teléfono. Si la siguiente falla (sin
// internet, o el acceso de Cloudflare caducó) el widget pinta la última con su hora
// ("GUARDADO · 18:13", en naranja) en vez de quedarse sin gráfica.
const MEM = (() => { try { const fm = FileManager.local();
  return { fm, path: fm.joinPath(fm.libraryDirectory(), "hub-edicion-summary.json") }; } catch (e) { return null; } })();
function saveLast(d) { try { MEM.fm.writeString(MEM.path, JSON.stringify(d)); } catch (e) { /* sin memoria: sigue igual */ } }
function readLast() {
  try { if (MEM.fm.fileExists(MEM.path)) { const d = JSON.parse(MEM.fm.readString(MEM.path)); if (d && d.week) return d; } } catch (e) {}
  return null;
}
function todayKey() { const n = new Date(), p = v => String(v).padStart(2, "0"); return `${n.getFullYear()}-${p(n.getMonth() + 1)}-${p(n.getDate())}`; }
// "18:13" si la lectura es de hoy; "9 NOV 18:13" si es de otro día
function stampOf(d) {
  const g = d.generatedAt || ""; if (g.length < 16) return "";
  const MES = ["ENE", "FEB", "MAR", "ABR", "MAY", "JUN", "JUL", "AGO", "SEP", "OCT", "NOV", "DIC"];
  return (g.slice(0, 10) !== todayKey() ? `${+g.slice(8, 10)} ${MES[+g.slice(5, 7) - 1]} ` : "") + g.slice(11, 16);
}
async function load() {
  const req = new Request(API);
  req.timeoutInterval = 8;
  req.headers = {
    "CF-Access-Client-Id": ACCESS_CLIENT_ID,
    "CF-Access-Client-Secret": ACCESS_CLIENT_SECRET,
  };
  try {
    const d = await req.loadJSON();
    if (d && !d.error && d.week) { saveLast(d); return d; }
  } catch (e) { /* sin red / sin acceso */ }
  const last = readLast();
  if (last) {
    last.stale = true;
    if (last.today !== todayKey()) last.today = "";   // dato de otro día: ninguna barra se marca como "hoy"
    return last;
  }
  return null;
}
function jsDow(key) { return new Date(key + "T00:00:00").getDay(); }
function fmtHM(min) {
  min = Math.round(min || 0);
  const h = Math.floor(min / 60), m = min % 60;
  return h ? (m ? `${h}h ${m}min` : `${h}h`) : `${m}min`;
}
function fmtHMshort(min) {
  min = Math.round(min || 0);
  const h = Math.floor(min / 60), m = min % 60;
  return h ? (m ? `${h}h ${m}m` : `${h}h`) : `${m}m`;
}

// ── Dibujo de la gráfica (DrawContext) ───────────────────────────────
// W,H en puntos. legend/title se ocultan en tamaño pequeño.
function drawChart(d, W, H, full) {
  const ctx = new DrawContext();
  ctx.size = new Size(W, H);
  ctx.opaque = false;
  ctx.respectScreenScale = true;

  // (Sin fondo aquí: el panel del widget lleva un gradiente translúcido detrás;
  //  la gráfica se dibuja en lienzo TRANSPARENTE para que iOS le aplique el vidrio.)

  const padX = full ? 16 : 10;
  const x0 = padX, x1 = W - padX, cw = x1 - x0;

  // Cabecera (solo en mediano)
  let topY = full ? 12 : 6;
  if (full) {
    // flecha de tendencia lima
    arrow(ctx, x0, topY + 12, COL.hoy);
    text(ctx, "HORAS POR DÍA — ÚLTIMOS 7 DÍAS", x0 + 22, topY + 2,
         W, 13, Font.boldMonospacedSystemFont(9.5), COL.title, "left");
    // dato guardado (la última lectura falló): su hora, a la derecha, en naranja
    if (d.stale) text(ctx, "GUARDADO" + (stampOf(d) ? " · " + stampOf(d) : ""), x1 - 130, topY + 2.5,
                      130, 13, Font.boldMonospacedSystemFont(8.5), COL.rec, "right");
    // leyenda
    const leg = [["Previos", COL.prev], ["Hoy", COL.hoy], ["Récord", COL.rec], ["Sábado", COL.sat]];
    let lx = x0, ly = topY + 20;
    for (const [lab, c] of leg) {
      glowDot(ctx, lx + 4, ly + 5, 3.5, c);
      text(ctx, lab, lx + 11, ly, 80, 11, Font.regularMonospacedSystemFont(8.5), COL.leg, "left");
      lx += 11 + lab.length * 5.2 + 14;
    }
  }

  if (!full && d.stale) dot(ctx, x1 - 3, topY + 4, 2.5, COL.rec);   // pequeño: un punto naranja = dato guardado

  // Geometría de barras
  const week = d.week || [];
  const vals = week.map(x => (x.min || 0) / 60);
  const maxRec = Math.max(0, ...vals);
  const maxY = Math.max(6, Math.ceil(maxRec * 1.18) || 6);
  const recVal = Math.max(0, ...week.filter(x => (x.min > 0) && x.key !== d.today).map(x => x.min / 60));

  const yB = H - (full ? 20 : 14);                 // baseline (0h)
  const yT = (full ? topY + 36 : topY + 14);       // tope (maxY)
  const th = yB - yT;
  const n = week.length || 7;
  const gap = full ? 7 : 4;
  const bw = (cw - gap * (n - 1)) / n;
  const Y = v => yB - (v / maxY) * th;

  // Línea de meta (5h) — se abre con un hueco donde una etiqueta la cruza, para que no estorbe
  const metaY = Y(5), lh = full ? 11 : 10, skips = [];
  week.forEach((x, i) => {
    const v = vals[i]; if (!(v > 0 && (full || v >= 1))) return;
    const by = yB - Math.max(4, (v / maxY) * th), labelY = by - (full ? 13 : 11);
    if (metaY >= labelY - 3 && metaY <= labelY + lh + 2) {
      const cx = x0 + i * (bw + gap) + bw / 2, lw = fmtHMshort(x.min).length * (full ? 5.2 : 4.3) + 8;
      skips.push([cx - lw / 2, cx + lw / 2]);
    }
  });
  dashed(ctx, x0, x1, metaY, COL.meta, skips);

  week.forEach((x, i) => {
    const v = vals[i], bx = x0 + i * (bw + gap), cx = bx + bw / 2;
    const dw = jsDow(x.key);
    const isToday = x.key === d.today;
    const isRec = v > 0 && v === recVal && !isToday;
    const isSat = dw === 6;
    const c = isToday ? COL.hoy : (isRec ? COL.rec : (isSat ? COL.sat : COL.prev));
    if (v > 0) {
      const h = Math.max(4, (v / maxY) * th), by = yB - h;
      const r = Math.min(bw / 2, full ? 9 : 6);
      if (isToday || isRec) halo(ctx, bx, by, bw, h, r, c);      // halo solo en lo importante (como .glw)
      gradBar(ctx, bx, by, bw, h, r, c);                         // misma caja que antes; luz arriba
      if (full || v >= 1)
        text(ctx, fmtHMshort(x.min), cx - 30, by - (full ? 13 : 11), 60, 12,
             Font.regularMonospacedSystemFont(full ? 8.5 : 7), COL.leg, "center");  // misma letra y gris que la leyenda
    }
    const dl = full ? `${DOW[dw]} ${x.key.slice(8)}` : DOW[dw][0];
    text(ctx, dl, cx - 30, yB + 3, 60, 12,
         Font.regularMonospacedSystemFont(full ? 8.5 : 7.5), isToday ? COL.hoy : COL.day, "center");
  });

  return ctx.getImage();
}

// ── Materiales de la identidad A ─────────────────────────────────────
function hex2rgb(h) { h = h.replace("#", ""); return [0, 2, 4].map(i => parseInt(h.substr(i, 2), 16)); }
function mixHex(a, b, t) {               // a→b en proporción t (opaco: sin costuras entre franjas)
  const A = hex2rgb(a), B = hex2rgb(b);
  return "#" + A.map((v, i) => Math.round(v + (B[i] - v) * t).toString(16).padStart(2, "0")).join("");
}
// Barra con degradado vertical, pintada por franjas de 1 px de pantalla dentro de la MISMA caja
// redondeada (x, y, w, h, r).
//  · oscuro: color pleno arriba → 42 % hacia el fondo abajo, igual que gfill().
//  · claro (fadeAlpha, 3-nov tarde): el velo vuelve, al nivel del dashboard en claro (−33 %: la base queda
//    al 61 %). Va como TRANSPARENCIA del mismo color, no mezclado con el crema: en la pantalla normal se ve
//    igual que mezclar con el fondo, y en el modo vidrio/tintado la base se funde con el vidrio en vez de
//    volverse blanca (el sistema pasa a blanco lo claro, y el crema mezclado es claro).
//    (Antes, a mediodía: barShade .08, sin velo.)
function gradBar(ctx, x, y, w, h, r, color) {
  const top = color.hex ? "#" + color.hex : color;
  const bot = _P.fadeAlpha ? top : (_P.barShade ? mixHex(top, "#000000", _P.barShade) : mixHex(top, _P.bg, 1 - _P.fadeTo));
  r = Math.min(r, w / 2, h / 2);
  const step = 1 / 3;                    // un píxel físico en pantallas 3x
  for (let t = 0; t < h; t += step) {
    const yc = t + step / 2;             // centro de la franja (desde arriba)
    let d = 0;
    if (yc < r) d = r - Math.sqrt(Math.max(0, r * r - (r - yc) * (r - yc)));
    else if (yc > h - r) { const q = yc - (h - r); d = r - Math.sqrt(Math.max(0, r * r - q * q)); }
    ctx.setFillColor(_P.fadeAlpha ? new Color(top, 1 - (1 - _P.fadeTo) * (t / h)) : new Color(mixHex(top, bot, t / h)));
    ctx.fillRect(new Rect(x + d, y + t, w - 2 * d, Math.min(step + 0.2, h - t)));
  }
}
// Halo suave (≈ feGaussianBlur del dashboard): capas redondeadas que crecen y se desvanecen.
// 3-nov: más fino y discreto (radio −33 %, pico −25 %) y el mismo en claro y oscuro.
// N capas de 1,1 pt; cada una con el alfa que hace que, apiladas, den `peak` junto a la barra.
function halo(ctx, x, y, w, h, r, color) {
  const top = color.hex ? "#" + color.hex : color, N = Math.round(_P.halo.r / 1.1),
        a = 1 - Math.pow(1 - _P.halo.peak, 1 / N);
  for (let k = N; k >= 1; k--) {
    const e = k * 1.1, p = new Path();
    p.addRoundedRect(new Rect(x - e, y - e, w + 2 * e, h + 2 * e), r + e, r + e);
    ctx.addPath(p); ctx.setFillColor(new Color(top, a)); ctx.fillPath();
  }
}
function glowDot(ctx, cx, cy, r, color) {
  const hx = color.hex ? "#" + color.hex : color;
  for (let k = 3; k >= 1; k--) dot(ctx, cx, cy, r + k * 1.2, new Color(hx, 0.07 * _P.glow));
  dot(ctx, cx, cy, r, color);
}
// Fondo: luz ambiente (tres orbes radiales) + grano de película al 50 % + filo de luz, sobre
// lienzo TRANSPARENTE. La base (crema/OLED) NO va aquí: va en widget.backgroundColor (ajuste 3-nov,
// modo vidrio). En el modo normal se ve igual que antes (capa transparente encima de la base).
// En el modo tintado/transparente el sistema pasa todo a blanco según lo claro que sea
// (claro = blanco opaco): una base crema dentro de la imagen se volvía una placa lechosa. Así la
// base es solo el fondo del widget, que el sistema quita y sustituye por su vidrio.
function drawBackground(W, H) {
  const ctx = new DrawContext();
  ctx.size = new Size(W, H);
  ctx.opaque = false;
  ctx.respectScreenScale = false;        // grano de ~1 pt, como el de 1 px CSS del dashboard
  const orbs = [[-0.08 * W, -0.55 * H, 1.15 * H], [W * 1.02, H * 0.55, 0.95 * H], [W * 0.42, H * 1.25, 0.8 * H]];
  orbs.forEach(([ox, oy, R], i) => {
    const [c, peak] = _P.amb[i], N = 26;
    for (let k = 0; k < N; k++) {          // radial: cada anillo suma un poco → centro ≈ peak, borde 0
      const rr = R * (1 - k / N);
      ctx.setFillColor(new Color(c, peak / N * 1.08));
      ctx.fillEllipse(new Rect(ox - rr, oy - rr, rr * 2, rr * 2));
    }
  });
  // grano: puntos blancos/negros con alfa aleatorio (mismo reparto que el canvas del dashboard)
  const n = Math.round(W * H * 0.3), aMax = 44 / 255 * _P.grain * 1.25;   // denso y tenue, no motas
  for (let i = 0; i < n; i++) {
    const rnd = Math.random();
    ctx.setFillColor(new Color(rnd >= .5 ? "#ffffff" : "#000000", Math.abs(rnd - .5) * 2 * aMax));
    ctx.fillRect(new Rect(Math.floor(Math.random() * W), Math.floor(Math.random() * H), 1, 1));
  }
  // filo de vidrio: luz arriba, como --hl de las tarjetas
  ctx.setFillColor(new Color("#ffffff", DARK_MODE ? 0.07 : 0.6)); ctx.fillRect(new Rect(0, 0, W, 1));
  return ctx.getImage();
}

// helpers de dibujo
function fillRound(ctx, x, y, w, h, r, color) {
  const p = new Path();
  p.addRoundedRect(new Rect(x, y, w, h), r, r);
  ctx.addPath(p); ctx.setFillColor(color); ctx.fillPath();
}
function dot(ctx, cx, cy, r, color) {
  ctx.setFillColor(color);
  ctx.fillEllipse(new Rect(cx - r, cy - r, r * 2, r * 2));
}
function text(ctx, s, x, y, w, h, font, color, align) {
  ctx.setFont(font); ctx.setTextColor(color);
  if (align === "center") ctx.setTextAlignedCenter();
  else if (align === "right") ctx.setTextAlignedRight();
  else ctx.setTextAlignedLeft();
  ctx.drawTextInRect(s, new Rect(x, y, w, h));
}
function dashed(ctx, x0, x1, y, color, skips) {
  ctx.setStrokeColor(color); ctx.setLineWidth(1);
  for (let x = x0; x < x1; x += 8) {
    const xe = Math.min(x + 4, x1);
    if (skips && skips.some(s => xe > s[0] && x < s[1])) continue;
    const p = new Path();
    p.move(new Point(x, y)); p.addLine(new Point(xe, y));
    ctx.addPath(p); ctx.strokePath();
  }
}
function arrow(ctx, x, y, color) {
  ctx.setStrokeColor(color); ctx.setLineWidth(2);
  const p = new Path();
  p.move(new Point(x, y));
  p.addLine(new Point(x + 7, y - 6));
  p.addLine(new Point(x + 12, y - 2));
  p.addLine(new Point(x + 19, y - 10));
  ctx.addPath(p); ctx.strokePath();
  const head = new Path();        // punta de flecha
  head.move(new Point(x + 14, y - 10));
  head.addLine(new Point(x + 19, y - 10));
  head.addLine(new Point(x + 19, y - 5));
  ctx.addPath(head); ctx.strokePath();
}

// ── Widget sin conexión ──────────────────────────────────────────────
function offlineWidget() {
  const w = new ListWidget();
  w.backgroundColor = COL.bg;
  w.backgroundImage = drawBackground(360, 170);
  const t = w.addText("Hub de Edición");
  t.font = Font.boldMonospacedSystemFont(11); t.textColor = COL.hrs;
  w.addSpacer(4);
  const s = w.addText("Sin datos todavía");
  s.font = Font.lightSystemFont(13); s.textColor = COL.leg;
  const s2 = w.addText("Sin internet o acceso caducado");
  s2.font = Font.regularMonospacedSystemFont(9.5); s2.textColor = COL.day;
  return w;
}

// ── Main ─────────────────────────────────────────────────────────────
const data = await load();
const fam = config.widgetFamily || "medium";
let widget;

if (!data) {
  widget = offlineWidget();
} else {
  widget = new ListWidget();
  widget.setPadding(0, 0, 0, 0);
  widget.url = HOST;
  const full = fam !== "small";
  const W = full ? 360 : 158, H = full ? 170 : 158;
  // Fondo = identidad A. La base va como COLOR de fondo (el sistema la quita en modo vidrio);
  // luz ambiente + grano van en una imagen transparente encima. Se dibuja aparte de la gráfica.
  widget.backgroundColor = new Color(_P.bg);
  widget.backgroundImage = drawBackground(W, H);
  // La gráfica (lienzo transparente) va como CONTENIDO encima del gradiente.
  const wi = widget.addImage(drawChart(data, W, H, full));
  wi.applyFittingContentMode();   // ajusta sin recortar (conserva el acomodo)
  wi.centerAlignImage();
}
widget.refreshAfterDate = new Date(Date.now() + 30 * 60 * 1000);

if (config.runsInWidget) {
  Script.setWidget(widget);
} else {
  await widget.presentMedium();
}
Script.complete();
