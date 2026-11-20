#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# ╔══════════════════════════════════════════════════════════════════╗
# ║  Hub de Edición — Plugin de SwiftBar (barra de menús del Mac)      ║
# ╠══════════════════════════════════════════════════════════════════╣
# ║  Muestra en el desplegable la MISMA gráfica "Horas por día —       ║
# ║  últimos 7 días" del dashboard (mismos colores y layout),          ║
# ║  renderizada como imagen vía QuickLook (qlmanage) + sips.          ║
# ║                                                                    ║
# ║  Cómo instalar:                                                    ║
# ║   1. brew install --cask swiftbar    (o https://swiftbar.app)      ║
# ║   2. Elige carpeta de plugins (p.ej. ~/SwiftBarPlugins) y enlaza:  ║
# ║        ln -s ~/HubEdicion/widgets/hubedicion.5m.py \              ║
# ║              ~/SwiftBarPlugins/hubedicion.5m.py                    ║
# ║   3. SwiftBar → Refresh all.                                       ║
# ║  El "5m" del nombre = se actualiza cada 5 minutos.                 ║
# ╚══════════════════════════════════════════════════════════════════╝

import json, urllib.request, os, tempfile, subprocess, base64, hashlib, datetime, math

HOST = "http://localhost:4599"
API  = HOST + "/api/summary"

# Paleta de marca (idéntica al dashboard, tema oscuro)
BG      = "#141416"; CARD_STROKE = "#26262b"
C_PREV  = "#8b7ff0"; C_HOY = "#c8f24e"; C_REC = "#fb923c"; C_SAT = "#c4b5fd"
C_TITLE = "#cdcdd4"; C_LEG = "#c2c2ca"; C_HRS = "#f3f3f5"; C_DAY = "#66666f"
C_META  = "#8b8b94"
DOW = ["Dom", "Lun", "Mar", "Mié", "Jue", "Vie", "Sáb"]

# Lima un poco más oscuro para el TÍTULO de la barra (lee bien en barra clara)
LIMA_BAR = "#a8cc2a"; DIM = "#888888"


# ── Datos ────────────────────────────────────────────────────────────
def fetch():
    try:
        req = urllib.request.Request(API, headers={"Accept": "application/json"})
        with urllib.request.urlopen(req, timeout=6) as r:
            d = json.load(r)
        return None if d.get("error") else d
    except Exception:
        return None

def fmt_hm(minutes):
    minutes = int(round(minutes or 0))
    h, m = divmod(minutes, 60)
    if h:
        return f"{h}h {m}min" if m else f"{h}h"
    return f"{m}min"

def pct(x):
    return int(round((x or 0) * 100))

def js_dow(key):
    try:
        d = datetime.date.fromisoformat(key)
        return (d.weekday() + 1) % 7   # 0=Dom..6=Sáb
    except Exception:
        return 1


# ── Gráfica SVG (misma que el dashboard) ─────────────────────────────
def chart_svg(week, today):
    """Dibuja la gráfica de barras centrada en un viewBox cuadrado 600×600
    (para poder recortarla con un crop centrado de sips después)."""
    VB = 600
    cardX, cardY, cardW, cardH, rx = 6, 120, 588, 360, 26
    chartX0, chartX1 = 36, 564
    chartW = chartX1 - chartX0
    yB, yT = 432, 250            # baseline (0h) y tope (maxY)
    th = yB - yT
    n = len(week) or 7
    gap = 16
    bw = (chartW - gap * (n - 1)) / n

    vals = [(d.get("min", 0) / 60.0) for d in week]
    max_rec = max(vals) if vals else 0
    maxY = max(6, math.ceil(max_rec) if max_rec else 6)
    # índice del récord (máximo, >0, que no sea hoy)
    rec_val = max([v for v, d in zip(vals, week) if v > 0 and d.get("key") != today] or [0])

    def Y(v):
        return yB - (v / maxY) * th

    parts = [
        f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {VB} {VB}" '
        f'font-family="-apple-system,Helvetica Neue,Arial,sans-serif">',
        f'<rect x="{cardX}" y="{cardY}" width="{cardW}" height="{cardH}" rx="{rx}" '
        f'fill="{BG}" stroke="{CARD_STROKE}"/>',
    ]
    # Título con flecha de tendencia lima
    ax, ay = chartX0, 156
    parts.append(
        f'<polyline points="{ax},{ay} {ax+9},{ay-8} {ax+15},{ay-3} {ax+24},{ay-13}" '
        f'fill="none" stroke="{C_HOY}" stroke-width="2.2" stroke-linecap="round" '
        f'stroke-linejoin="round"/>'
        f'<polyline points="{ax+18},{ay-13} {ax+24},{ay-13} {ax+24},{ay-7}" '
        f'fill="none" stroke="{C_HOY}" stroke-width="2.2" stroke-linecap="round" '
        f'stroke-linejoin="round"/>')
    parts.append(
        f'<text x="{ax+34}" y="{ay}" font-size="16" font-weight="700" '
        f'letter-spacing="1.5" fill="{C_TITLE}">HORAS POR DÍA — ÚLTIMOS 7 DÍAS</text>')

    # Leyenda
    leg = [("Previos", C_PREV), ("Hoy", C_HOY), ("Récord", C_REC), ("Sábado", C_SAT)]
    lx, ly = chartX0, 192
    for label, col in leg:
        parts.append(f'<circle cx="{lx+6}" cy="{ly-4}" r="6" fill="{col}"/>')
        parts.append(f'<text x="{lx+18}" y="{ly}" font-size="13" fill="{C_LEG}">{label}</text>')
        lx += 18 + len(label) * 8.0 + 24

    # Línea de meta (5h)
    my = Y(5)
    parts.append(
        f'<line x1="{chartX0}" x2="{chartX1}" y1="{my:.1f}" y2="{my:.1f}" '
        f'stroke="{C_META}" stroke-width="1" stroke-dasharray="4 4" opacity="0.5"/>')
    parts.append(
        f'<text x="{chartX1}" y="{my-5:.1f}" text-anchor="end" font-size="11" '
        f'fill="{C_META}">meta 5h</text>')

    # Barras
    for i, d in enumerate(week):
        v = vals[i]
        x = chartX0 + i * (bw + gap)
        cx = x + bw / 2
        key = d.get("key", "")
        dw = js_dow(key)
        is_today = key == today
        is_rec = v > 0 and v == rec_val and not is_today
        is_sat = dw == 6
        col = C_HOY if is_today else (C_REC if is_rec else (C_SAT if is_sat else C_PREV))
        if v > 0:
            h = max(4.0, (v / maxY) * th)
            y = yB - h
            parts.append(
                f'<rect x="{x:.1f}" y="{y:.1f}" width="{bw:.1f}" height="{h:.1f}" '
                f'rx="13" fill="{col}"/>')
            hrs = round(v * 10) / 10
            hrs_txt = (f"{hrs:.1f}h" if hrs != int(hrs) else f"{int(hrs)}h")
            parts.append(
                f'<text x="{cx:.1f}" y="{y-9:.1f}" text-anchor="middle" font-size="14" '
                f'font-weight="700" fill="{C_HRS}">{hrs_txt}</text>')
        # etiqueta del día (siempre)
        parts.append(
            f'<text x="{cx:.1f}" y="{yB+24:.1f}" text-anchor="middle" font-size="12.5" '
            f'fill="{C_DAY}">{DOW[dw]} {key[8:]}</text>')

    parts.append('</svg>')
    return "".join(parts)


def render_chart_png(svg, sig):
    """Convierte el SVG a PNG (qlmanage) y lo recorta centrado (sips).
    Cachea por firma de datos en /tmp para no re-renderizar igual."""
    cache_png = os.path.join(tempfile.gettempdir(), f"hubedicion_chart_{sig}.png")
    if os.path.isfile(cache_png):
        return cache_png
    try:
        d = tempfile.mkdtemp(prefix="hubchart_")
        svg_path = os.path.join(d, "chart.svg")
        with open(svg_path, "w") as f:
            f.write(svg)
        # qlmanage: longest side = 520  → 520×520 con el contenido centrado vertical
        subprocess.run(["qlmanage", "-t", "-s", "520", "-o", d, svg_path],
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=20)
        raw = os.path.join(d, "chart.svg.png")
        if not os.path.isfile(raw):
            return None
        # recorte centrado: la banda útil mide 360/600 del alto → 520*0.6 = 312 px
        subprocess.run(["sips", "-c", "312", "520", raw, "--out", cache_png],
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=20)
        return cache_png if os.path.isfile(cache_png) else None
    except Exception:
        return None


def b64(path):
    with open(path, "rb") as f:
        return base64.b64encode(f.read()).decode("ascii")


def line(text, **params):
    if params:
        kv = " ".join(f"{k}={v}" for k, v in params.items())
        print(f"{text} | {kv}")
    else:
        print(text)


# ── Render del plugin ────────────────────────────────────────────────
def main():
    d = fetch()

    if not d:
        line("· · ·", sfimage="film", color=DIM)
        print("---")
        line("Hub de Edición — sin conexión", color=DIM)
        line("¿Server encendido? (puerto 4599)", color=DIM)
        line("Abrir dashboard", href=HOST)
        return

    overall = pct(d.get("overallProgress"))
    today_min = d.get("todayMin", 0)
    meta = d.get("metaMin", 0)
    met = meta > 0 and today_min >= meta
    streak = d.get("streak", 0)
    today = d.get("today", "")
    week = d.get("week") or []

    # ── Título en la barra de menús ──
    title = f"{overall}%  {fmt_hm(today_min)}" + ("  ✓" if met else "")
    tparams = {"sfimage": "film"}
    if met:
        tparams["color"] = LIMA_BAR
    line(title, **tparams)

    print("---")

    # ── Gráfica de barras (imagen) ──
    if week:
        sig = hashlib.md5(json.dumps([(x["key"], x["min"], x["meta"]) for x in week]).encode()).hexdigest()[:10]
        png = render_chart_png(chart_svg(week, today), sig)
        if png:
            line("", image=b64(png))
        else:
            # respaldo de texto si qlmanage/sips fallan
            line("Horas por día — últimos 7 días", color=DIM)
            for x in week:
                mk = " ✓" if (x["meta"] > 0 and x["min"] >= x["meta"]) else ("" if x["min"] else " ·")
                line(f"{DOW[js_dow(x['key'])]} {x['key'][8:]}:  {fmt_hm(x['min'])}{mk}")
        print("---")

    # ── Resumen ──
    line(f"Avance global: {overall}%", color=LIMA_BAR)
    line(f"Hoy: {fmt_hm(today_min)} / meta {fmt_hm(meta)}" + ("  ✓" if met else ""))
    line(f"Racha: {streak} día" + ("" if streak == 1 else "s"))

    act = d.get("active")
    if act and act.get("stage"):
        print("---")
        wn = (act.get("icon", "") + " " + (act.get("wedding") or "")).strip()
        line(f"En curso — {wn}", color=DIM)
        sp = act.get("stageProgress")
        sptxt = f"  ({pct(sp)}%)" if sp is not None else ""
        sh = act.get("stageHours")
        shtxt = f"  · {sh}h" if sh else ""
        line(f"{act.get('stage')}{sptxt}{shtxt}", color=act.get("stageColor") or LIMA_BAR)

    print("---")
    line("Abrir dashboard", href=HOST)
    line("Refrescar", refresh="true")
    gen = d.get("generatedAt") or ""
    if gen:
        line(f"Datos: {gen.replace('T', ' ')}", color=DIM, size="10")


if __name__ == "__main__":
    main()
