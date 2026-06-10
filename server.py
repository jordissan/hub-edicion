#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Puente local para el Hub de Edición.
- Sirve el dashboard (index.html) en http://localhost:PUERTO
- Expone /api/data que consulta Notion EN VIVO y devuelve el JSON del dashboard
- El token de Notion NUNCA vive en el HTML: se lee de la variable de entorno
  NOTION_TOKEN o del archivo ~/.notion-dashboard-token

Solo usa la librería estándar de Python 3 (no hay que instalar nada).

Uso:
    python3 server.py            # arranca el servidor
    python3 server.py --check    # prueba el token y lista las bodas detectadas
"""

import os, sys, json, time, threading, urllib.request, urllib.error, datetime, socketserver, http.server

# ── Configuración ────────────────────────────────────────────────────────────
PORT = int(os.environ.get("DASHBOARD_PORT", "4599"))
NOTION_VERSION = "2022-06-28"
HERE = os.path.dirname(os.path.abspath(__file__))

# DB raíz "Trabajo" (de aquí se descubren las bodas activas).
TRABAJO_DB_ID = "4cf5fe0b-16f7-4b8c-ae52-4116766307a4"
# Respaldo: si la consulta a la DB raíz falla, se usan estas bodas conocidas.
FALLBACK_WEDDING_PAGES = [
    "3687eb0c-bb92-8159-8fe8-e316e229eabf",  # boda 1
    "34a7eb0c-bb92-8198-b42f-f5fd765ac0d8",  # boda 2
]

CACHE_TTL = 180  # segundos antes de refrescar EN SEGUNDO PLANO; el botón 🔄 fuerza
CACHE_FILE = os.path.join(HERE, ".cache.json")
_cache = {"at": 0, "data": None}
_lock = threading.Lock()
_refreshing = False


# ── Token ────────────────────────────────────────────────────────────────────
def get_token():
    tok = os.environ.get("NOTION_TOKEN", "").strip()
    if tok:
        return tok
    path = os.path.expanduser("~/.notion-dashboard-token")
    if os.path.isfile(path):
        with open(path, "r") as f:
            return f.read().strip()
    return None


# ── Cliente Notion ───────────────────────────────────────────────────────────
def notion(method, path, body=None):
    token = get_token()
    if not token:
        raise RuntimeError("NO_TOKEN")
    data = json.dumps(body).encode("utf-8") if body is not None else None
    req = urllib.request.Request(
        "https://api.notion.com/v1" + path, data=data, method=method,
        headers={
            "Authorization": "Bearer " + token,
            "Notion-Version": NOTION_VERSION,
            "Content-Type": "application/json",
        })
    for attempt in range(4):
        try:
            with urllib.request.urlopen(req, timeout=30) as r:
                return json.load(r)
        except urllib.error.HTTPError as e:
            if e.code == 429 and attempt < 3:            # rate limit -> espera y reintenta
                wait = float(e.headers.get("Retry-After", "1") or "1")
                time.sleep(min(wait, 5))
                continue
            detail = e.read().decode("utf-8", "ignore")
            raise RuntimeError("Notion %s: %s" % (e.code, detail[:300]))
        except Exception as e:
            if attempt < 3:
                time.sleep(0.6)
                continue
            raise


def query_db(db_id, filt=None):
    out, cursor = [], None
    while True:
        body = {"page_size": 100}
        if filt:
            body["filter"] = filt
        if cursor:
            body["start_cursor"] = cursor
        d = notion("POST", "/databases/%s/query" % db_id, body)
        out += d.get("results", [])
        if d.get("has_more"):
            cursor = d.get("next_cursor")
        else:
            break
    return out


def children(block_id):
    out, cursor = [], None
    while True:
        q = "/blocks/%s/children?page_size=100" % block_id
        if cursor:
            q += "&start_cursor=" + cursor
        d = notion("GET", q)
        out += d.get("results", [])
        if d.get("has_more"):
            cursor = d.get("next_cursor")
        else:
            break
    return out


_CONTAINERS = {"column_list", "column", "toggle", "synced_block", "callout",
               "quote", "bulleted_list_item", "numbered_list_item", "to_do", "template"}
def iter_child_databases(block_id, depth=0):
    """Devuelve TODOS los bloques child_database bajo un bloque, incluso si están
    anidados dentro de columnas, toggles, etc."""
    out = []
    if depth > 3:
        return out
    for blk in children(block_id):
        t = blk.get("type")
        if t == "child_database":
            out.append(blk)
        elif blk.get("has_children") and t in _CONTAINERS:
            out += iter_child_databases(blk["id"], depth + 1)
    return out


_db_meta_cache = {}
def db_title_prop(db_id):
    if db_id in _db_meta_cache:
        return _db_meta_cache[db_id]
    d = notion("GET", "/databases/%s" % db_id)
    name = None
    for k, v in d.get("properties", {}).items():
        if v.get("type") == "title":
            name = k
            break
    _db_meta_cache[db_id] = name
    return name


# ── Extractores de propiedades ───────────────────────────────────────────────
def p_title(props, name):
    v = props.get(name)
    if v and v.get("type") == "title":
        return "".join(t["plain_text"] for t in v["title"])
    return ""

def title_any(props):
    for k, v in props.items():
        if v.get("type") == "title":
            return "".join(t["plain_text"] for t in v["title"])
    return ""

def p_select(props, name):
    v = props.get(name)
    if not v:
        return None
    if v.get("type") == "select":
        return v["select"]["name"] if v.get("select") else None
    if v.get("type") == "status":
        return v["status"]["name"] if v.get("status") else None
    return None

def p_number(props, name):
    v = props.get(name)
    return v.get("number") if v and v.get("type") == "number" else None

def p_rich(props, *names):
    for name in names:
        v = props.get(name)
        if v and v.get("type") == "rich_text":
            txt = "".join(t["plain_text"] for t in v["rich_text"])
            if txt:
                return txt
    return ""

def first_date(props):
    for k, v in props.items():
        if v.get("type") == "date" and v.get("date"):
            return v["date"].get("start"), v["date"].get("end")
    return None, None

def p_date(props, name):
    v = props.get(name)
    if v and v.get("type") == "date" and v.get("date"):
        return v["date"].get("start")
    return None

def parse_iso_local(s):
    """Parsea un ISO datetime de Notion (puede venir en UTC 'Z' o con offset)
    y lo convierte a HORA LOCAL de esta Mac. Devuelve datetime naive local."""
    if not s or "T" not in s:
        return None
    try:
        dt = datetime.datetime.fromisoformat(s.replace("Z", "+00:00"))
        if dt.tzinfo is not None:
            dt = dt.astimezone().replace(tzinfo=None)
        return dt
    except Exception:
        try:
            return datetime.datetime.strptime(s[:16], "%Y-%m-%dT%H:%M")
        except Exception:
            return None

def hours_between(ini, fin):
    """Horas entre dos ISO datetimes. Precisión a minuto."""
    a = parse_iso_local(ini)
    b = parse_iso_local(fin)
    if not a or not b:
        return None
    h = (b - a).total_seconds() / 3600.0
    return h if h > 0 else None

def page_icon(page):
    ic = page.get("icon")
    if ic and ic.get("type") == "emoji":
        return ic["emoji"]
    return "⛪"

def norm_estado(s):
    if not s:
        return "wait"
    t = s.lower()
    if "🟢" in s or "complet" in t or "hecho" in t:
        return "done"
    if "🔵" in s or "progreso" in t or "curso" in t:
        return "live"
    return "wait"

def parse_day(title):
    if not title:
        return "Escenas"
    t = title.lower()
    if "día 2" in t or "dia 2" in t or "d2" in t:
        return "Día 2"
    if "día 1" in t or "dia 1" in t or "d1" in t:
        return "Día 1"
    return "Escenas"


# ── Construcción del modelo del dashboard ────────────────────────────────────
def build_wedding(page):
    props = page.get("properties", {})
    name = p_title(props, "Nombre") or title_any(props)
    studio = p_select(props, "Subcategoría")
    status = p_select(props, "Status")
    prioridad = p_select(props, "Prioridad")
    ps, pe = first_date(props)
    wedding = {
        "name": name, "icon": page_icon(page), "studio": studio,
        "status": status, "priority": prioridad,
        "url": page.get("url", ""),
        "projectStart": ps, "projectEnd": pe,
        "stages": [],
    }
    # Encontrar la sub-DB "Tracking de Edición" dentro de la página de la boda
    tracking_db = None
    for blk in children(page["id"]):
        if blk.get("type") == "child_database":
            t = blk["child_database"].get("title", "")
            if "tracking" in t.lower():
                tracking_db = blk["id"]
                break
    if not tracking_db:
        return wedding

    for st in query_db(tracking_db):
        sp = st.get("properties", {})
        s_start, s_end = first_date(sp)
        stage = {
            "etapa": p_title(sp, "Etapa") or title_any(sp),
            "fase": p_select(sp, "Fase"),
            "estado": norm_estado(p_select(sp, "Estado")),
            "orden": p_number(sp, "Orden") if p_number(sp, "Orden") is not None else 99,
            "start": s_start, "end": s_end,
            "scenes": [], "hours": None, "sessions": 0, "sessionLog": [],
        }
        total_h = 0.0
        nsess = 0
        # Sub-DBs dentro de la etapa: "Escena" -> escenas · "Sesion" -> horas efectivas
        for sb in iter_child_databases(st["id"]):
            sb_id = sb["id"]
            sb_title = sb["child_database"].get("title", "")
            try:
                title_prop = db_title_prop(sb_id)
            except Exception:
                continue
            if title_prop == "Escena":
                day = parse_day(sb_title)
                for sc in query_db(sb_id):
                    scp = sc.get("properties", {})
                    c_start, c_end = first_date(scp)
                    stage["scenes"].append({
                        "escena": p_title(scp, "Escena") or title_any(scp),
                        "estado": norm_estado(p_select(scp, "Estado")),
                        "orden": p_number(scp, "Orden") if p_number(scp, "Orden") is not None else 99,
                        "cancion": p_rich(scp, "Cancion", "Canción"),
                        "dia": day, "start": c_start, "end": c_end,
                    })
            elif title_prop == "Sesion" or "sesion" in sb_title.lower():
                for ses in query_db(sb_id):
                    pp = ses.get("properties", {})
                    ini = p_date(pp, "Inicio")
                    fin = p_date(pp, "Fin")
                    if not ini:  # fallback: primer prop date con rango
                        for k, v in pp.items():
                            if v.get("type") == "date" and v.get("date"):
                                ini = v["date"].get("start")
                                fin = fin or v["date"].get("end")
                                break
                    h = hours_between(ini, fin)
                    if h:
                        total_h += h
                        nsess += 1
                        ini_local = parse_iso_local(ini)
                        stage["sessionLog"].append({
                            "name": p_title(pp, "Sesion") or title_any(pp),
                            "inicio": ini_local.strftime("%Y-%m-%dT%H:%M") if ini_local else ini,
                            "min": int(round(h * 60)),
                            "tipo": p_select(pp, "Tipo"),
                        })
        if nsess:
            stage["hours"] = round(total_h, 1)
            stage["sessions"] = nsess
        stage["scenes"].sort(key=lambda x: x["orden"])
        wedding["stages"].append(stage)
    wedding["stages"].sort(key=lambda x: x["orden"])
    return wedding


def discover_wedding_pages():
    """Devuelve las páginas de bodas activas (Tipo=Boda, Status≠Hecho)."""
    filt = {"and": [
        {"property": "Tipo", "select": {"equals": "Boda"}},
        {"property": "Status", "status": {"does_not_equal": "Hecho"}},
    ]}
    try:
        pages = query_db(TRABAJO_DB_ID, filt)
        if pages:
            return pages
    except Exception as e:
        sys.stderr.write("[aviso] consulta a DB raíz falló (%s); usando bodas conocidas\n" % e)
    # Respaldo: traer las páginas conocidas directamente
    pages = []
    for pid in FALLBACK_WEDDING_PAGES:
        try:
            pages.append(notion("GET", "/pages/%s" % pid))
        except Exception as e:
            sys.stderr.write("[aviso] no se pudo traer %s (%s)\n" % (pid, e))
    return pages


def build_data():
    pages = discover_wedding_pages()
    weddings = [build_wedding(p) for p in pages]
    # ordenar: activas (con etapa en progreso) primero
    weddings.sort(key=lambda w: 0 if any(s["estado"] == "live" for s in w["stages"]) else 1)
    now = datetime.datetime.now()
    return {
        "generatedAt": now.isoformat(timespec="seconds"),
        "today": now.strftime("%Y-%m-%d"),
        "live": True,
        "weddings": weddings,
    }


# ── Resumen compacto para widgets (iPhone Scriptable / Mac SwiftBar) ──────────
# Colores de marca por etapa (mismo mapa que el dashboard, index.html).
STAGE_COLORS = {
    "Importación y Organización": "#5b9dff",
    "Separación por Escenas": "#c084fc",
    "Limpieza": "#34d399",
    "Sincronización": "#fbbf24",
    "Musicalización": "#fb7185",
    "Edición Musical": "#c8f24e",
    "Corrección de Color y Finalización": "#fb923c",
    "Selección de Material (HL/SF)": "#a78bfa",
    "Selección Musical (HL/SF)": "#22d3ee",
    "Montaje (HL/SF)": "#f472b6",
}
_PALETTE = ["#c8f24e", "#5b9dff", "#fb7185", "#fbbf24", "#34d399", "#c084fc", "#22d3ee", "#fb923c"]

def stage_color(etapa, i=0):
    return STAGE_COLORS.get(etapa) or _PALETTE[(i or 0) % len(_PALETTE)]

def stage_prog(st):
    """Avance 0..1 de una etapa (mismo cálculo que index.html)."""
    scenes = st.get("scenes") or []
    if scenes:
        d = sum(1 for x in scenes if x.get("estado") == "done")
        l = sum(1 for x in scenes if x.get("estado") == "live")
        return (d + l * 0.5) / len(scenes)
    e = st.get("estado")
    return 1.0 if e == "done" else 0.5 if e == "live" else 0.0

def wed_prog(w):
    stages = w.get("stages") or []
    if not stages:
        return 0.0
    return sum(stage_prog(s) for s in stages) / len(stages)

def _js_dow(d):
    """Día de la semana al estilo JS getDay(): 0=Dom .. 6=Sáb."""
    return (d.weekday() + 1) % 7

def meta_min(date_str):
    """Meta de minutos por día: 5h L-V · 2h Sáb · Dom descanso."""
    try:
        d = datetime.date.fromisoformat(date_str)
    except Exception:
        return 300
    dow = _js_dow(d)
    return 0 if dow == 0 else (120 if dow == 6 else 300)

def _all_sessions(data):
    out = []
    for w in data.get("weddings", []):
        for s in w.get("stages", []):
            for x in (s.get("sessionLog") or []):
                ini = x.get("inicio")
                if ini:
                    out.append({"key": ini[:10], "min": x.get("min") or 0})
    return out

def _day_totals(sessions):
    m = {}
    for s in sessions:
        m[s["key"]] = m.get(s["key"], 0) + s["min"]
    return m

def calc_streak(tot, today_str):
    """Racha de días consecutivos cumpliendo la meta (salta domingos)."""
    try:
        d = datetime.date.fromisoformat(today_str)
    except Exception:
        return 0
    if tot.get(today_str, 0) < meta_min(today_str):
        d = d - datetime.timedelta(days=1)
    s = 0
    for _ in range(120):
        k = d.isoformat()
        if _js_dow(d) != 0:                     # los domingos no suman ni rompen
            if tot.get(k, 0) >= meta_min(k):
                s += 1
            else:
                break
        d = d - datetime.timedelta(days=1)
    return s

def build_summary(data):
    """Resumen compacto que consumen los widgets. Deriva todo de get_data()."""
    today = data.get("today") or datetime.date.today().isoformat()
    weddings = data.get("weddings", [])
    sessions = _all_sessions(data)
    tot = _day_totals(sessions)
    today_min = tot.get(today, 0)
    meta = meta_min(today)
    streak = calc_streak(tot, today)

    # Últimos 7 días (incluye hoy) para el gráfico del widget.
    week = []
    base = datetime.date.fromisoformat(today)
    for i in range(6, -1, -1):
        d = base - datetime.timedelta(days=i)
        k = d.isoformat()
        week.append({"key": k, "min": tot.get(k, 0), "meta": meta_min(k)})

    # Boda + etapa activa (la primera con etapa "live"; si no, la primera boda).
    active = None
    live_w = next((w for w in weddings if any(s.get("estado") == "live" for s in w.get("stages", []))), None)
    if not live_w and weddings:
        live_w = weddings[0]
    if live_w:
        stages = live_w.get("stages", [])
        live_stage = next((s for s in stages if s.get("estado") == "live"), None)
        if live_stage:
            idx = stages.index(live_stage)
            live_scene = next((sc for sc in (live_stage.get("scenes") or []) if sc.get("estado") == "live"), None)
            active = {
                "wedding": live_w.get("name"),
                "icon": live_w.get("icon"),
                "stage": live_stage.get("etapa"),
                "stageColor": stage_color(live_stage.get("etapa"), idx),
                "stageProgress": round(stage_prog(live_stage), 3),
                "stageHours": live_stage.get("hours"),
                "scene": (live_scene or {}).get("escena"),
            }
        else:
            active = {"wedding": live_w.get("name"), "icon": live_w.get("icon"),
                      "stage": None, "stageColor": _PALETTE[0], "stageProgress": None}

    weds = []
    for w in weddings:
        stages = w.get("stages", [])
        weds.append({
            "name": w.get("name"),
            "icon": w.get("icon"),
            "progress": round(wed_prog(w), 3),
            "done": sum(1 for s in stages if s.get("estado") == "done"),
            "live": sum(1 for s in stages if s.get("estado") == "live"),
            "wait": sum(1 for s in stages if s.get("estado") == "wait"),
            "stages": len(stages),
            "hours": round(sum(s.get("hours") or 0 for s in stages), 1),
        })

    overall = round(sum(w["progress"] for w in weds) / len(weds), 3) if weds else 0.0

    return {
        "generatedAt": data.get("generatedAt"),
        "today": today,
        "todayMin": today_min,
        "metaMin": meta,
        "streak": streak,
        "week": week,
        "overallProgress": overall,
        "active": active,
        "weddings": weds,
    }


def _load_disk_cache():
    try:
        with open(CACHE_FILE, "r") as f:
            d = json.load(f)
        _cache["data"] = d.get("data")
        _cache["at"] = d.get("at", 0)
    except Exception:
        pass

def _save_disk_cache():
    try:
        with open(CACHE_FILE, "w") as f:
            json.dump({"at": _cache["at"], "data": _cache["data"]}, f, ensure_ascii=False)
    except Exception:
        pass

def _do_build():
    """Reconstruye los datos y actualiza caché (memoria + disco)."""
    global _refreshing
    try:
        data = build_data()
        with _lock:
            _cache["data"] = data
            _cache["at"] = time.time()
        _save_disk_cache()
    except Exception as e:
        sys.stderr.write("[refresh] error: %s\n" % e)
    finally:
        _refreshing = False

def get_data(fresh=False):
    """Stale-while-revalidate: responde YA con lo cacheado y refresca en 2º plano."""
    global _refreshing
    if fresh:                       # botón 🔄 Actualizar -> síncrono
        _do_build()
        return _cache["data"]
    with _lock:
        cached = _cache["data"]
        age = time.time() - _cache["at"]
    if cached is None:              # primera vez sin caché -> construir ya
        _do_build()
        return _cache["data"]
    if age > CACHE_TTL and not _refreshing:   # caché viejo -> refrescar sin bloquear
        _refreshing = True
        threading.Thread(target=_do_build, daemon=True).start()
    return cached                   # respuesta instantánea


# ── Servidor HTTP ────────────────────────────────────────────────────────────
class Handler(http.server.BaseHTTPRequestHandler):
    def _send(self, code, body, ctype="application/json; charset=utf-8"):
        if isinstance(body, str):
            body = body.encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        path = self.path.split("?")[0]
        if path in ("/", "/index.html"):
            try:
                with open(os.path.join(HERE, "index.html"), "rb") as f:
                    self._send(200, f.read(), "text/html; charset=utf-8")
            except Exception as e:
                self._send(500, "Error: %s" % e, "text/plain; charset=utf-8")
            return
        if path == "/api/health":
            self._send(200, json.dumps({"ok": True, "hasToken": bool(get_token())}))
            return
        if path == "/api/data":
            fresh = "fresh=1" in self.path
            try:
                self._send(200, json.dumps(get_data(fresh=fresh), ensure_ascii=False))
            except RuntimeError as e:
                msg = str(e)
                if msg == "NO_TOKEN":
                    msg = ("Falta el token de Notion. Crea una integración en "
                           "notion.so/my-integrations, comparte tu workspace 'Trabajo' con ella "
                           "y guarda el token en ~/.notion-dashboard-token")
                self._send(200, json.dumps({"error": msg}, ensure_ascii=False))
            except Exception as e:
                self._send(200, json.dumps({"error": str(e)}, ensure_ascii=False))
            return
        if path == "/api/summary":
            fresh = "fresh=1" in self.path
            try:
                self._send(200, json.dumps(build_summary(get_data(fresh=fresh)), ensure_ascii=False))
            except RuntimeError as e:
                msg = str(e)
                if msg == "NO_TOKEN":
                    msg = "Falta el token de Notion (~/.notion-dashboard-token)."
                self._send(200, json.dumps({"error": msg}, ensure_ascii=False))
            except Exception as e:
                self._send(200, json.dumps({"error": str(e)}, ensure_ascii=False))
            return
        # Estáticos de la PWA (lista blanca, sin acceso libre al disco)
        statics = {
            "/manifest.json": "application/manifest+json",
            "/icon-180.png": "image/png",
            "/icon-512.png": "image/png",
        }
        if path in statics:
            try:
                with open(os.path.join(HERE, path.lstrip("/")), "rb") as f:
                    self._send(200, f.read(), statics[path])
            except Exception:
                self._send(404, "Not found", "text/plain; charset=utf-8")
            return
        self._send(404, "Not found", "text/plain; charset=utf-8")

    def log_message(self, *a):
        pass  # silencioso


class ThreadingServer(socketserver.ThreadingMixIn, http.server.HTTPServer):
    daemon_threads = True
    allow_reuse_address = True


def main():
    if "--check" in sys.argv:
        tok = get_token()
        print("Token detectado:" , "sí" if tok else "NO")
        if not tok:
            print("→ Crea el token y guárdalo en ~/.notion-dashboard-token (ver README).")
            return
        try:
            data = build_data()
            print("Conexión a Notion OK. Bodas activas detectadas: %d" % len(data["weddings"]))
            for w in data["weddings"]:
                done = sum(1 for s in w["stages"] if s["estado"] == "done")
                toth = sum(s.get("hours") or 0 for s in w["stages"])
                tots = sum(s.get("sessions") or 0 for s in w["stages"])
                print("  • %s — %d/%d etapas · %.1fh efectivas en %d sesiones" % (
                    w["name"], done, len(w["stages"]), toth, tots))
                for s in w["stages"]:
                    h = s.get("hours")
                    print("      - %-34s %s · %d sesión(es)" % (
                        s["etapa"][:34],
                        ("%.1fh" % h) if h else "sin horas",
                        s.get("sessions") or 0))
        except Exception as e:
            print("ERROR al consultar Notion:", e)
        return

    print("Hub de Edición — puente local")
    print("Abre:  http://localhost:%d" % PORT)
    print("(Ctrl+C para detener)")
    _load_disk_cache()                       # carga instantánea de la última extracción
    if get_token():                          # precalienta en 2º plano para la 1ª carga
        threading.Thread(target=_do_build, daemon=True).start()
    ThreadingServer(("0.0.0.0", PORT), Handler).serve_forever()


if __name__ == "__main__":
    main()
