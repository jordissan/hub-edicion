#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Puente local del Hub de Edición — y núcleo compartido con la nube (cloud/publish.py
importa este mismo archivo; cloud/server.py es una copia idéntica).
- Sirve el dashboard (index.html) en http://localhost:PUERTO
- GET  /api/data     → payload completo del dashboard (Notion en vivo, caché 3 min)
- GET  /api/summary  → resumen compacto para los widgets
- POST /api/session  → registra un sprint de enfoque como sesión en Notion
- POST /api/close    → al terminar un sprint, cierra su escena (y su etapa) en Notion: 🟢 + fecha de fin
- GET/POST /api/sprint-state → estado compartido del sprint entre el dashboard y la
  ventana flotante del Mac (mac/SprintFlotante); solo local, en .sprint-state.json
- GET  /api/outbox   → cola local de envíos a Notion (lo guardado sin internet; .outbox.json)
- POST /api/outbox/flush → sube la cola ya (la app del reloj: volvió la red / despertó el Mac)
- GET  /api/health   → {ok, hasToken}
- El token de Notion NUNCA vive en el HTML: se lee de la variable de entorno
  NOTION_TOKEN o del archivo ~/.notion-dashboard-token

Solo usa la librería estándar de Python 3 (no hay que instalar nada).
Referencia técnica completa: docs/arquitectura.md

Uso:
    python3 server.py            # arranca el servidor
    python3 server.py --check    # prueba el token y lista las bodas detectadas
"""

import os, re, sys, json, time, threading, unicodedata, urllib.request, urllib.error, datetime, socketserver, http.server

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
_lock = threading.Lock()          # protege _cache
_build_lock = threading.Lock()    # una sola extracción a la vez (cada una son ~200 peticiones)


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


# ── Enlaces para Notion (/embed) ─────────────────────────────────────────────
# El botón </> del dashboard pide aquí el enlace de una tarjeta. La clave es la misma que valida
# la nube (functions/embed/data.js): HMAC-SHA256(EMBED_SECRET, "embed:" + boda), 20 hex. El secreto
# sale de la variable EMBED_SECRET o del archivo .embed-secret junto a este script (solo en el Mac;
# no va a git). Debe ser el MISMO valor que el secreto EMBED_SECRET de Cloudflare Pages.
EMBED_ORIGIN = os.environ.get("HUB_EMBED_ORIGIN", "https://hub-edicion.pages.dev")


def get_embed_secret():
    s = os.environ.get("EMBED_SECRET", "").strip()
    if s:
        return s
    path = os.path.join(HERE, ".embed-secret")
    if os.path.isfile(path):
        with open(path, "r") as f:
            return f.read().strip() or None
    return None


def embed_link(boda):
    """{boda, url} para pegar en Notion, o None sin secreto. boda = slug ("ale-lorenzo")."""
    import hmac, hashlib
    secret = get_embed_secret()
    if not secret:
        return None
    k = hmac.new(secret.encode(), ("embed:" + boda).encode(), hashlib.sha256).hexdigest()[:20]
    return {"boda": boda, "url": "%s/embed?boda=%s&k=%s" % (EMBED_ORIGIN, boda, k)}


# ── Cliente Notion ───────────────────────────────────────────────────────────
# Notion limita a ~3 peticiones/segundo de media. Una extracción completa son
# ~200 peticiones (una por sub-DB de escenas/sesiones de cada etapa de cada boda),
# así que sin freno el extractor dispara ráfagas por encima del límite y Notion
# responde 429. Antes eso reventaba el run entero de GitHub Actions (correo de
# "Publicar dashboard failed" cada pocas horas): 4 intentos separados 1-3 s no
# alcanzan cuando el bloqueo dura más. El arreglo es doble: espaciar SIEMPRE las
# peticiones por debajo del límite (así casi nunca se toca el 429) y, si aun así
# aparece, reintentar con backoff exponencial de verdad.
NOTION_MIN_INTERVAL = 0.40          # s entre peticiones → 2.5 req/s, con margen bajo el 3/s
NOTION_TRIES = 6                    # intentos por petición ante 429 / 5xx / red
_rate_lock = threading.Lock()
_last_req = [0.0]


def _throttle():
    """Espacia las peticiones a Notion para no pasar de ~3 req/s."""
    with _rate_lock:
        gap = time.time() - _last_req[0]
        if gap < NOTION_MIN_INTERVAL:
            time.sleep(NOTION_MIN_INTERVAL - gap)
        _last_req[0] = time.time()


class NotionError(RuntimeError):
    """Respuesta de error de Notion (HTTP). code: 429/5xx = temporal; el resto, rechazo."""
    def __init__(self, code, msg):
        RuntimeError.__init__(self, msg)
        self.code = code


# Modo "cola" (solo en el hilo que sube la cola local): sin internet falla en ~1-2 s en vez de
# ~30 s de reintentos, y el POST que CREA una página no se reintenta solo (si la respuesta se
# perdió, Notion ya la creó: la cola lo comprueba antes de volver a crearla).
_notion_opts = threading.local()


def notion(method, path, body=None):
    fast = getattr(_notion_opts, "fast", False)
    creates = method == "POST" and path == "/pages"
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
    for attempt in range(NOTION_TRIES):
        last = attempt == NOTION_TRIES - 1
        _throttle()
        try:
            with urllib.request.urlopen(req, timeout=8 if fast else 30) as r:
                return json.load(r)
        except urllib.error.HTTPError as e:
            # 429 = rate limit · 5xx = fallo temporal de Notion. Ambos se reintentan
            # respetando Retry-After y subiendo la espera (2, 4, 8… hasta 30 s).
            # (Un 5xx al CREAR en modo cola no: pudo crearse igual; la cola lo comprueba.)
            if e.code in (429, 500, 502, 503, 504) and not last and not (fast and creates and e.code != 429):
                try:
                    hinted = float(e.headers.get("Retry-After", "") or 0)
                except ValueError:
                    hinted = 0.0
                time.sleep(min(max(hinted, 2.0 * (2 ** attempt)), 30.0))
                continue
            detail = e.read().decode("utf-8", "ignore")
            raise NotionError(e.code, "Notion %s: %s" % (e.code, detail[:300]))
        except Exception:
            if fast and (creates or attempt >= 1):
                raise                # sin red: que la cola lo guarde y reintente después
            if not last:
                time.sleep(min(1.0 * (2 ** attempt), 15.0))
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


# En Notion las columnas título de las sub-DBs conviven acentuadas y sin acentuar
# ("Sesión" y "Sesion" en la misma boda), así que comparamos sin acentos.
def _sinacento(s):
    s = unicodedata.normalize("NFD", s or "")
    return "".join(c for c in s if unicodedata.category(c) != "Mn").lower().strip()


def _is_sesion(title_prop):
    return _sinacento(title_prop).startswith("sesion")


_db_meta_cache = {}
_db_has_dates = {}   # db_id -> tiene fechas "Inicio" y "Fin" (= registro de sesiones de verdad)
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
    dates = {_sinacento(k) for k, v in d.get("properties", {}).items() if v.get("type") == "date"}
    _db_has_dates[db_id] = {"inicio", "fin"} <= dates
    return name


def is_session_log_db(db_id):
    """OJO: la DB "Tiempo total" de cada etapa TAMBIÉN titula su columna "Sesión"; solo
    la DB de Sesiones de verdad tiene fechas Inicio y Fin. El sprint escribe solo en esa."""
    try:
        db_title_prop(db_id)
    except Exception:
        return False
    return _db_has_dates.get(db_id, False)


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
    if v.get("type") == "formula" and (v.get("formula") or {}).get("type") == "string":
        return v["formula"].get("string") or None
    return None

def p_number(props, name):
    v = props.get(name)
    return v.get("number") if v and v.get("type") == "number" else None

def p_orden(props):
    """Propiedad "Orden" (admite decimales: 4.1…4.4); sin valor va al final."""
    o = p_number(props, "Orden")
    return 99 if o is None else o

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
def read_session_db(sb_id):
    """Lee una DB de 'Sesiones' -> (sessionLog, horas_totales, n_sesiones)."""
    log = []; total_h = 0.0; nsess = 0
    for ses in query_db(sb_id):
        pp = ses.get("properties", {})
        ini = p_date(pp, "Inicio"); fin = p_date(pp, "Fin")
        if not ini:  # fallback: primer prop date con rango
            for k, v in pp.items():
                if v.get("type") == "date" and v.get("date"):
                    ini = v["date"].get("start"); fin = fin or v["date"].get("end"); break
        h = hours_between(ini, fin)
        if h:
            total_h += h; nsess += 1
            ini_local = parse_iso_local(ini)
            esc = None
            for k, v in pp.items():
                if v.get("type") == "relation" and _sinacento(k).startswith("escena") and v.get("relation"):
                    esc = v["relation"][0]["id"]; break
            log.append({
                "name": p_title(pp, "Sesion") or title_any(pp),
                "inicio": ini_local.strftime("%Y-%m-%dT%H:%M") if ini_local else ini,
                "min": int(round(h * 60)),
                "tipo": p_select(pp, "Tipo"),
                "ronda": p_number(pp, "Ronda"),
                "escena": esc,   # para que el sprint proponga la última escena trabajada
            })
    return log, total_h, nsess


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
        "price": p_number(props, "Total"),   # precio cobrado (MXN) para rentabilidad $/h
        "url": page.get("url", ""),
        "projectStart": ps, "projectEnd": pe,
        "stages": [],
    }
    # Encontrar la sub-DB "Tracking de Edición" dentro de la página de la boda
    blocks = children(page["id"])
    tracking_db = None
    for blk in blocks:
        if blk.get("type") == "child_database":
            t = blk["child_database"].get("title", "")
            if "tracking" in t.lower():
                tracking_db = blk["id"]
                break
    if not tracking_db:
        # Bodas de SOLO correcciones / sesiones sueltas: un "Sesiones" directo bajo la
        # página (sin etapas). Capturamos sus sesiones como una etapa "Correcciones".
        for blk in blocks:
            if blk.get("type") != "child_database":
                continue
            bid = blk["id"]; title = blk["child_database"].get("title", "")
            try:
                is_ses = _is_sesion(db_title_prop(bid)) or ("sesi" in _sinacento(title))
            except Exception:
                is_ses = "sesi" in _sinacento(title)
            if is_ses:
                log, th, ns = read_session_db(bid)
                if ns:
                    wedding["stages"].append({
                        "etapa": "Correcciones", "fase": None,
                        "estado": "done", "orden": 99,
                        "start": None, "end": None,
                        "isCorrections": True, "sessionDb": bid if is_session_log_db(bid) else None,
                        "scenes": [], "hours": round(th, 1), "sessions": ns, "sessionLog": log,
                    })
        return wedding

    for st in query_db(tracking_db):
        sp = st.get("properties", {})
        s_start, s_end = first_date(sp)
        s_etapa = p_title(sp, "Etapa") or title_any(sp)
        stage = {
            "id": st["id"],      # página de la etapa (el sprint la pasa a 🔵 si estaba ⚪️)
            "etapa": s_etapa,
            "fase": p_select(sp, "Fase"),
            "estado": norm_estado(p_select(sp, "Estado")),
            "orden": p_orden(sp),
            "start": s_start, "end": s_end,
            # "Cambios"/"Correcciones" se trackean pero NO cuentan como tiempo de edición
            # (dependen de terceros: el estudio). OJO: "correcciones" plural ≠
            # "Corrección de Color y Finalización" (etapa normal de edición, singular).
            "isCorrections": ("cambios" in s_etapa.lower()) or ("correcciones" in s_etapa.lower()),
            "scenes": [], "hours": None, "sessions": 0, "sessionLog": [],
            "sessionDb": None,   # DB "Sesiones" de la etapa (el sprint registra aquí)
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
                # Notion niega el acceso a algunas sub-DBs huérfanas ("Untitled", sin
                # data sources). Antes se saltaba la sub-DB entera, así que si una DB
                # de Sesiones real fallara se perderían sus horas EN SILENCIO. Ahora
                # caemos al nombre del bloque, igual que la rama de solo-correcciones.
                title_prop = None
            if _sinacento(title_prop).startswith("escena"):
                day = parse_day(sb_title)
                for sc in query_db(sb_id):
                    scp = sc.get("properties", {})
                    c_start, c_end = first_date(scp)
                    stage["scenes"].append({
                        "id": sc["id"],
                        "escena": p_title(scp, "Escena") or title_any(scp),
                        "estado": norm_estado(p_select(scp, "Estado")),
                        "orden": p_orden(scp),
                        "cancion": p_rich(scp, "Cancion", "Canción"),
                        "dia": day, "start": c_start, "end": c_end,
                    })
            elif _is_sesion(title_prop) or "sesion" in _sinacento(sb_title):
                log, th, ns = read_session_db(sb_id)
                stage["sessionLog"].extend(log); total_h += th; nsess += ns
                if not stage["sessionDb"] and is_session_log_db(sb_id):
                    stage["sessionDb"] = sb_id
        if nsess:
            stage["hours"] = round(total_h, 1)
            stage["sessions"] = nsess
        stage["scenes"].sort(key=lambda x: x["orden"])
        wedding["stages"].append(stage)
    wedding["stages"].sort(key=lambda x: x["orden"])
    return wedding


# ── Registrar una sesión (sprint de enfoque) ─────────────────────────────────
def _iso_ok(v):
    try:
        return datetime.datetime.fromisoformat(v) if isinstance(v, str) else None
    except ValueError:
        return None


def validate_session(item):
    """Devuelve un mensaje de error o None. item = {id, db, inicio, fin, tipo, escena?, ronda?}."""
    if not isinstance(item, dict) or not item.get("db") or not item.get("id"):
        return "Faltan datos de la sesión"
    a, b = _iso_ok(item.get("inicio")), _iso_ok(item.get("fin"))
    if not a or not b or a.tzinfo is None or b.tzinfo is None:
        return "Inicio/Fin inválidos"
    mins = (b - a).total_seconds() / 60
    if mins < 1:
        return "Sesión de menos de 1 minuto"
    if mins > 8 * 60:
        return "Sesión de más de 8 horas"
    if item.get("tipo") not in (None, "Edición", "Gestión"):
        return "Tipo inválido"
    return None


def _same_instant(notion_iso, dt):
    """¿La fecha de Notion (puede venir en UTC o con milisegundos) es el mismo minuto que dt?"""
    try:
        a = datetime.datetime.fromisoformat((notion_iso or "").replace("Z", "+00:00"))
    except ValueError:
        return False
    if a.tzinfo is None or dt is None:
        return False
    return abs((a - dt).total_seconds()) < 60


def find_session_page(db, schema, item):
    """¿Ya hay en esa DB una sesión con este mismo Inicio y Fin? Pasa cuando un envío se cortó
    justo después de que Notion la creara (la respuesta no llegó): así no se duplica."""
    ini = next((k for k, v in schema.items() if v.get("type") == "date" and _sinacento(k) == "inicio"), None)
    fin = next((k for k, v in schema.items() if v.get("type") == "date" and _sinacento(k) == "fin"), None)
    a, b = _iso_ok(item.get("inicio")), _iso_ok(item.get("fin"))
    if not ini or not fin or not a or not b:
        return None
    since = (a - datetime.timedelta(days=1)).isoformat()
    for r in query_db(db, {"property": ini, "date": {"on_or_after": since}}):
        p = r.get("properties", {})
        if _same_instant(((p.get(ini) or {}).get("date") or {}).get("start"), a) and \
           _same_instant(((p.get(fin) or {}).get("date") or {}).get("start"), b):
            return r
    return None


def create_session(item, step=None, save_step=None):
    """Crea una fila en la DB "Sesiones" de una etapa IGUAL que el registro manual:
    título "Sesión", Inicio, Fin, Tipo, Escena (relación) y Total (relación a la fila
    de "Tiempo total" de la etapa que corresponde a su Tipo: Edición / Gestión).
    Solo llena las propiedades que existen en esa DB (las plantillas varían).
    step/save_step (cola local): lo ya hecho de un envío anterior que se cortó (página
    creada, estados movidos), para retomarlo sin duplicar. save_step() lo guarda en disco."""
    step = step if step is not None else {}
    save_step = save_step or (lambda: None)
    db = item["db"]; tipo = item.get("tipo") or "Edición"
    if step.get("page"):
        return _session_status(item, step, save_step)
    schema = notion("GET", "/databases/%s" % db).get("properties", {})
    dates = {_sinacento(k) for k, v in schema.items() if v.get("type") == "date"}
    if not {"inicio", "fin"} <= dates:      # salvaguarda: nunca escribir en "Tiempo total" u otra DB
        raise RuntimeError("Esa DB no es un registro de Sesiones (sin Inicio/Fin)")
    if step.get("posting"):                 # el envío anterior se cortó al crearla: ¿llegó a Notion?
        dup = find_session_page(db, schema, item)
        if dup:
            step["page"] = {"id": dup.get("id"), "url": dup.get("url")}
            step.pop("posting", None); save_step()
            return _session_status(item, step, save_step)
    props = {}
    for name, p in schema.items():
        t, n = p.get("type"), _sinacento(name)
        if t == "title":
            props[name] = {"title": [{"text": {"content": "Sesión"}}]}
        elif t == "date" and n == "inicio":
            props[name] = {"date": {"start": item["inicio"]}}
        elif t == "date" and n == "fin":
            props[name] = {"date": {"start": item["fin"]}}
        elif t == "select" and n == "tipo":
            if tipo in [o["name"] for o in p["select"].get("options", [])]:
                props[name] = {"select": {"name": tipo}}
        elif t == "number" and n == "ronda" and item.get("ronda") is not None:
            props[name] = {"number": item["ronda"]}
        elif t == "relation" and n.startswith("escena") and item.get("escena"):
            props[name] = {"relation": [{"id": item["escena"]}]}
        elif t == "relation" and n == "total":
            tid = p["relation"].get("database_id")
            if tid:
                for r in query_db(tid):
                    if _sinacento(title_any(r.get("properties", {}))) == _sinacento(tipo):
                        props[name] = {"relation": [{"id": r["id"]}]}
                        break
    step["posting"] = True; save_step()     # a partir de aquí, un corte puede dejarla creada
    page = notion("POST", "/pages", {"parent": {"database_id": db}, "properties": props})
    step["page"] = {"id": page.get("id"), "url": page.get("url")}
    step.pop("posting", None); save_step()
    return _session_status(item, step, save_step)


def _session_status(item, step, save_step):
    """La sesión ya existe: etapa/escena ⚪️ → 🔵. Si es un fallo de red en modo cola, se
    reintenta luego (la sesión no se vuelve a crear); si Notion lo rechaza, se avisa y listo."""
    out = {"id": step["page"]["id"], "url": step["page"]["url"], "moved": list(step.get("moved", []))}
    done = step.setdefault("status", [])
    for kind, pid in (("etapa", item.get("stageId")), ("escena", item.get("escena"))):
        if not pid or kind in done:
            continue
        try:
            if set_in_progress(pid, item["inicio"], kind):
                out["moved"].append(kind)
                step["moved"] = out["moved"]
        except Exception as e:
            if getattr(_notion_opts, "fast", False) and is_transient(e):
                raise
            out.setdefault("warn", []).append("%s: %s" % (kind, str(e)[:120]))
        done.append(kind); save_step()
    return out


def set_in_progress(page_id, start_iso, kind):
    """Lo que harías a mano al empezar a trabajar algo: Estado ⚪️/vacío → 🔵 (nunca
    retrocede un 🔵/🟢) y, si su fecha de inicio está vacía, la llena con la de la sesión.
    kind="etapa": fecha "Del → Al" (solo día) · kind="escena": fecha "Inicio" (con hora).
    Devuelve True si cambió el estado."""
    page = notion("GET", "/pages/%s" % page_id)
    props = page.get("properties", {})
    upd, moved = {}, False
    est = next((n for n in ("Estado (Select)", "Estado")
                if (props.get(n) or {}).get("type") in ("select", "status")), None)
    if est:
        t = props[est]["type"]
        cur = (props[est].get(t) or {}).get("name")
        if norm_estado(cur) == "wait":
            dbid = (page.get("parent") or {}).get("database_id")
            opts = []
            if dbid:
                opts = notion("GET", "/databases/%s" % dbid).get("properties", {}).get(est, {}).get(t, {}).get("options", [])
            blue = next((o["name"] for o in opts if norm_estado(o["name"]) == "live"), None)
            if blue:
                upd[est] = {t: {"name": blue}}
                moved = True
    for name, v in props.items():
        if v.get("type") != "date" or v.get("date"):
            continue
        if kind == "etapa":          # la etapa tiene una sola fecha (rango "Del → Al")
            upd[name] = {"date": {"start": start_iso[:10]}}
            break
        if _sinacento(name) == "inicio":
            upd[name] = {"date": {"start": start_iso}}
            break
    if upd:
        notion("PATCH", "/pages/%s" % page_id, {"properties": upd})
    return moved


def set_done(page_id, fin_iso, kind):
    """Lo que harías a mano al acabar algo: Estado → 🟢 y su fecha de fin, si está vacía.
    kind="escena": "Fin" (con hora) · kind="etapa": el final del rango "Del → Al" (solo día;
    si tampoco tenía inicio, lo pone el mismo día). Devuelve True si cambió el estado."""
    page = notion("GET", "/pages/%s" % page_id)
    props = page.get("properties", {})
    upd, moved = {}, False
    est = next((n for n in ("Estado (Select)", "Estado")
                if (props.get(n) or {}).get("type") in ("select", "status")), None)
    if est:
        t = props[est]["type"]
        cur = (props[est].get(t) or {}).get("name")
        if norm_estado(cur) != "done":
            dbid = (page.get("parent") or {}).get("database_id")
            opts = []
            if dbid:
                opts = notion("GET", "/databases/%s" % dbid).get("properties", {}).get(est, {}).get(t, {}).get("options", [])
            green = next((o["name"] for o in opts if norm_estado(o["name"]) == "done"), None)
            if green:
                upd[est] = {t: {"name": green}}
                moved = True
    for name, v in props.items():
        if v.get("type") != "date":
            continue
        d = v.get("date") or {}
        if kind == "etapa":          # la etapa tiene una sola fecha (rango "Del → Al")
            if not d.get("end"):
                upd[name] = {"date": {"start": d.get("start") or fin_iso[:10], "end": fin_iso[:10]}}
            break
        if _sinacento(name) == "fin":
            if not d.get("start"):
                upd[name] = {"date": {"start": fin_iso}}
            break
    if upd:
        notion("PATCH", "/pages/%s" % page_id, {"properties": upd})
    return moved


def validate_close(item):
    """item = {id, db, cerrar: "escena"|"etapa", fin, stageId?, escena?}."""
    if not isinstance(item, dict) or not item.get("db") or not item.get("id"):
        return "Faltan datos del cierre"
    if item.get("cerrar") not in ("escena", "etapa"):
        return "Cierre inválido"
    f = _iso_ok(item.get("fin"))
    if not f or f.tzinfo is None:
        return "Fin inválido"
    if item["cerrar"] == "escena" and not item.get("escena"):
        return "Falta la escena"
    if item["cerrar"] == "etapa" and not item.get("stageId"):
        return "Falta la etapa"
    return None


def close_targets(item, step=None, save_step=None):
    """Cierra la escena (y la etapa si cerrar="etapa") al terminar un sprint.
    Devuelve las que pasaron a 🟢: ["escena", "etapa"]. step/save_step: como en create_session
    (cerrar es idempotente; solo evita repetir peticiones y conserva lo que pasó a 🟢)."""
    step = step if step is not None else {}
    save_step = save_step or (lambda: None)
    done = step.setdefault("closed", [])
    hecho = step.setdefault("did", [])
    order = [("escena", item.get("escena"))]
    if item.get("cerrar") == "etapa":
        order.append(("etapa", item.get("stageId")))
    for kind, pid in order:
        if not pid or kind in hecho:
            continue
        if set_done(pid, item["fin"], kind):
            done.append(kind)
        hecho.append(kind); save_step()
    return list(done)


def session_targets(data):
    """DB de Sesiones → {etapa: id de su página, escenas: ids}. Es la lista blanca del
    registro: solo se escribe en etapas/escenas que existen en el tablero."""
    out = {}
    for w in (data or {}).get("weddings", []):
        for s in w.get("stages", []):
            if s.get("sessionDb"):
                out[s["sessionDb"]] = {"stage": s.get("id"),
                                       "scenes": {sc.get("id") for sc in s.get("scenes") or [] if sc.get("id")}}
    return out


def target_error(item, targets):
    t = targets.get(item.get("db"))
    if not t:
        return "Etapa desconocida"
    if item.get("stageId") and t["stage"] and item["stageId"] != t["stage"]:
        return "La etapa no corresponde a esa DB de Sesiones"
    if item.get("escena") and item["escena"] not in t["scenes"]:
        return "La escena no es de esa etapa"
    return None


RECENT_DONE_DAYS = 45  # bodas finalizadas editadas en los últimos N días siguen en el tablero

# Estados de Notion que cuentan como "boda terminada/entregada". Se comparan en
# minúsculas. OJO: las opciones del estado en Notion se han renombrado en el
# pasado ("Hecho" → "Finalizadas"), así que filtramos en Python por este conjunto
# en vez de codificar un nombre exacto en la consulta (que reventaba con un 400
# cuando la opción dejaba de existir y tiraba todo a las bodas de respaldo).
DONE_STATUSES = {"hecho", "finalizadas", "finalizada", "complete", "completado", "done"}

# Se pone a True cuando la consulta a Notion falla y caemos a FALLBACK_WEDDING_PAGES.
# Ese respaldo son 2 bodas hardcodeadas: un tablero MUTILADO que parece sano. Sin esta
# marca, publish.py lo subía a KV y borraba el tablero bueno en silencio (ya pasó una
# vez, con el 400 del Status renombrado). Ahora build_data lo etiqueta y el publicador
# se niega a sobrescribir la nube con datos degradados.
DISCOVERY_DEGRADED = [False]

# Páginas de bodas finalizadas que la última consulta dejó FUERA del tablero (más de
# RECENT_DONE_DAYS sin cambios). build_data las usa para rellenar, una sola vez, la
# curva ("ghost") de las entradas del archivo que aún no la tienen.
DROPPED_DONE_PAGES = []


def discover_wedding_pages(archive=None):
    """Trae TODAS las páginas Tipo=Boda y descarta solo las finalizadas que llevan
    inactivas más de RECENT_DONE_DAYS días — para no perder proyectos recién
    cerrados (p.ej. correcciones post-entrega que acabas hoy) ni las que siguen en
    curso o en correcciones. Robusto ante renombrados del estado en Notion.

    "Inactiva" = última SESIÓN trackeada (lastActivity del archivo histórico), no la
    fecha de edición de la página: una edición masiva en Notion (p. ej. la reestructura
    del 1-nov-2026, que añadió "Cliente / Línea" a todas las filas) ponía todas las
    bodas entregadas como "editadas hoy" y las regresaba al tablero. Cuenta la más
    reciente entre esa última sesión y el fin del rango "Fecha" (la entrega); solo si
    no hay ninguna de las dos se usa last_edited_time (así una boda recién cerrada
    nunca se queda fuera sin archivarse)."""
    DISCOVERY_DEGRADED[0] = False
    last_act = {(e.get("name") or "").strip().lower(): (e.get("lastActivity") or e.get("lastEnd"))
                for e in (archive or []) if e.get("name")}
    del DROPPED_DONE_PAGES[:]
    cutoff = (datetime.date.today() - datetime.timedelta(days=RECENT_DONE_DAYS)).isoformat()
    filt = {"property": "Tipo", "select": {"equals": "Boda"}}
    try:
        pages = query_db(TRABAJO_DB_ID, filt)
        if pages:
            kept = []
            for p in pages:
                status = (p_select(p.get("properties", {}), "Status") or "").strip().lower()
                props = p.get("properties", {})
                name = (p_title(props, "Nombre") or title_any(props)).strip().lower()
                ps, pe = first_date(props)  # rango "Fecha" del proyecto: el fin es la entrega
                activity = max(last_act.get(name) or "", (pe or ps or "")[:10]) \
                    or (p.get("last_edited_time") or "")[:10]
                if status in DONE_STATUSES and activity < cutoff:
                    DROPPED_DONE_PAGES.append(p)  # para rellenar su curva en el archivo
                    continue  # finalizada y sin actividad reciente → fuera del tablero
                kept.append(p)
            if kept:
                return kept
    except Exception as e:
        sys.stderr.write("[aviso] consulta a DB raíz falló (%s); usando bodas conocidas\n" % e)
    # Respaldo: traer las páginas conocidas directamente (tablero degradado)
    DISCOVERY_DEGRADED[0] = True
    pages = []
    for pid in FALLBACK_WEDDING_PAGES:
        try:
            pages.append(notion("GET", "/pages/%s" % pid))
        except Exception as e:
            sys.stderr.write("[aviso] no se pudo traer %s (%s)\n" % (pid, e))
    return pages


# ── Archivo histórico de bodas entregadas ────────────────────────────────────
# El tablero solo conserva los datos COMPLETOS (etapas/escenas/sesiones) de bodas
# activas o recién cerradas (RECENT_DONE_DAYS) — así el selector no se vuelve una
# lista infinita y la extracción de Notion no crece sin fin. Para no perder la historia
# cuando una boda sale del tablero, cada extracción guarda/actualiza sus stats compactas
# (horas, escenas, días, precio, rondas) + su "ghost" en un archivo persistente que viaja
# en el payload como "archive". Lo usan la Carrera (fantasma), el Archivo de Proyectos y
# el heatmap. Solo se archivan bodas terminadas CON horas de edición trackeadas: las que
# no tienen sesiones no son referencia válida.
ARCHIVE_FILE = os.path.join(HERE, ".archive.json")


GHOST_VERSION = 3  # v2: + estado y nº de sesiones por etapa (para el Archivo de Proyectos)
                   # v3: + minutos por hora del día (hod), duración de cada sesión (durs) y
                   #     boda de 1 o 2 días (nDays) — para el Historial y "Tu ritmo" con todo

# boda de 2 días = tiene una escena "Día 1…" (misma regla que daysOf del front)
DAY1_RE = re.compile(r"^\s*d[ií]a\s*(1|uno|previo)\b", re.I)


def wedding_days(w):
    for s in w.get("stages") or []:
        for sc in (s.get("scenes") or []):
            if DAY1_RE.match(sc.get("escena") or "") or sc.get("dia") == "Día 1":
                return 2
    return 1


def wedding_ghost(w):
    """Esqueleto compacto de una boda para que la Carrera ("Contra tu fantasma"), el
    ADN, Dinero y el Archivo de Proyectos puedan seguir usándola cuando sale del
    tablero: por etapa, su estado, horas, nº de sesiones y escenas, y los minutos
    trabajados por día (no cada sesión). Desde v3 también los minutos por hora del día
    y la duración de cada sesión: lo poco que hace falta para "Tu ritmo" e Historial."""
    stages = []
    for s in w.get("stages") or []:
        days, hod, durs = {}, {}, []
        for x in (s.get("sessionLog") or []):
            if x.get("inicio"):
                d = x["inicio"][:10]
                m = x.get("min") or 0
                days[d] = days.get(d, 0) + m
                h = x["inicio"][11:13]
                if h.isdigit():
                    hod[str(int(h))] = hod.get(str(int(h)), 0) + m
                durs.append(m)
        stages.append({
            "etapa": s.get("etapa"), "fase": s.get("fase"),
            "isCorrections": bool(s.get("isCorrections")),
            "estado": s.get("estado"), "sessions": s.get("sessions") or 0,
            "hours": s.get("hours"), "nScenes": len(s.get("scenes") or []),
            "days": days, "hod": hod, "durs": durs,
        })
    return {"v": GHOST_VERSION, "projectStart": w.get("projectStart"),
            "projectEnd": w.get("projectEnd"), "nDays": wedding_days(w), "stages": stages}


def wedding_archive_stats(w):
    """Stats compactas de una boda (mismas semánticas que weddingStats del front)."""
    edit = [s for s in w["stages"] if not s.get("isCorrections")]
    hours = round(sum(s.get("hours") or 0 for s in edit), 1)
    scenes = sum(len(s.get("scenes") or []) for s in edit)
    days = sorted(d[:10] for s in edit for d in (s.get("start"), s.get("end")) if d)
    span = None
    if days:
        try:
            a = datetime.date.fromisoformat(days[0])
            b = datetime.date.fromisoformat(days[-1])
            span = max(1, (b - a).days + 1)
        except ValueError:
            pass
    # última actividad real: cualquier sesión (edición o cambios) o fecha de etapa
    acts = days + [(x.get("inicio") or "")[:10] for s in w["stages"] for x in (s.get("sessionLog") or [])]
    acts = [d for d in acts if d]
    rondas, any_corr = set(), False
    for s in w["stages"]:
        if not s.get("isCorrections"):
            continue
        for x in (s.get("sessionLog") or []):
            any_corr = True
            if x.get("ronda") is not None:
                rondas.add(x["ronda"])
    return {
        "name": (w.get("name") or "").strip(), "icon": w.get("icon"),
        "hours": hours, "scenes": scenes, "span": span,
        "price": w.get("price"), "rounds": len(rondas) or (1 if any_corr else 0),
        "lastEnd": days[-1] if days else None,
        "lastActivity": max(acts) if acts else None,  # lo usa discover_wedding_pages
        "ghost": wedding_ghost(w),
    }


def _write_json_atomic(path, obj):
    """Escribe a un temporal y lo renombra encima. Si el Mac se apaga o el proceso muere a
    media escritura, el archivo anterior queda intacto (antes podía quedar truncado: y un
    .archive.json ilegible se leía como "sin historia" y se sobrescribía vacío)."""
    tmp = path + ".tmp"
    with open(tmp, "w") as f:
        json.dump(obj, f, ensure_ascii=False)
        f.flush()
        os.fsync(f.fileno())
    os.replace(tmp, path)


def load_archive():
    try:
        with open(ARCHIVE_FILE, "r") as f:
            arc = json.load(f)
        return arc if isinstance(arc, list) else []
    except Exception:
        return []


def save_archive(archive):
    try:
        _write_json_atomic(ARCHIVE_FILE, archive)
    except Exception as e:
        sys.stderr.write("[archivo] no se pudo guardar %s: %s\n" % (ARCHIVE_FILE, e))


def merge_archive(prev, weddings):
    """Upsert de las bodas terminadas con horas trackeadas del tablero actual sobre el
    archivo previo; las que ya salieron del tablero se conservan tal cual. Mientras una
    boda archivada siga visible (ventana de 45 días) sus stats se refrescan en cada
    extracción (p. ej. si le corriges una sesión en Notion)."""
    by = {e["name"].strip().lower(): e for e in prev if e.get("name")}
    today = datetime.date.today().isoformat()
    for w in weddings:
        status = (w.get("status") or "").strip().lower()
        if status not in DONE_STATUSES:
            continue
        st = wedding_archive_stats(w)
        if not st["name"] or st["hours"] <= 0:
            continue
        key = st["name"].lower()
        st["archivedAt"] = (by.get(key) or {}).get("archivedAt") or today
        by[key] = st
    return sorted(by.values(), key=lambda e: e.get("lastEnd") or e.get("archivedAt") or "")


BACKFILL_MAX = 2  # bodas viejas a reconstruir por extracción (~1 min c/u: cabe en los 10 min de Actions)


def backfill_ghosts(archive):
    """Entradas archivadas sin "ghost" o con uno de versión vieja (bodas ya fuera del
    tablero): se reconstruyen desde Notion una sola vez. Después viajan en el archivo y
    no se vuelven a consultar."""
    missing = {e["name"].strip().lower(): e for e in archive
               if e.get("name") and (e.get("ghost") or {}).get("v", 1) < GHOST_VERSION}
    done = 0
    for p in DROPPED_DONE_PAGES:
        if not missing or done >= BACKFILL_MAX:
            break
        props = p.get("properties", {})
        key = ((p_title(props, "Nombre") or title_any(props)) or "").strip().lower()
        entry = missing.pop(key, None)
        if not entry:
            continue
        try:
            entry["ghost"] = wedding_ghost(build_wedding(p))
            done += 1
        except Exception as e:
            sys.stderr.write("[archivo] no se pudo reconstruir %s (%s)\n" % (key, e))


def build_data(prev_archive=None):
    prev = load_archive() if prev_archive is None else prev_archive
    pages = discover_wedding_pages(prev)
    weddings = [build_wedding(p) for p in pages]
    # ordenar: activas (con etapa en progreso) primero
    weddings.sort(key=lambda w: 0 if any(s["estado"] == "live" for s in w["stages"]) else 1)
    # archivo histórico: local se persiste en disco; el extractor de la nube pasa
    # el previo leído de KV (prev_archive) y publica el resultado él mismo.
    archive = merge_archive(prev, weddings)
    backfill_ghosts(archive)
    save_archive(archive)
    now = datetime.datetime.now()
    return {
        "generatedAt": now.isoformat(timespec="seconds"),
        "today": now.strftime("%Y-%m-%d"),
        "live": True,
        "degraded": DISCOVERY_DEGRADED[0],   # True = solo las bodas de respaldo; no publicar
        "weddings": weddings,
        "archive": archive,
    }


# ── Resumen compacto para widgets (iPhone Scriptable / Mac SwiftBar) ──────────
# Color por FASE, igual que el dashboard (tokens --f-prep, --f-teas, --sun-block,
# --violeta, --naranja de index.html) — antes era un mapa por nombre de etapa de la
# plantilla vieja y las etapas nuevas caían en colores al azar.
PHASE_COLORS = {"prep": "#5aa3ec", "teas": "#40d9c1", "doc": "#d9ed2f", "hl": "#685bc7", "cam": "#de6b45"}
_PREP_ROLES = ("importacion", "setup", "separacion", "escenas", "limpieza", "sincroniz")

def phase_of(st):
    """Fase de una etapa: misma regla que phaseOf() de deriveModel (plantilla nueva por
    la propiedad Fase; en la vieja, "Documental" incluía la preparación)."""
    if st.get("isCorrections"):
        return "cam"
    f, n = _sinacento(st.get("fase")), _sinacento(st.get("etapa"))
    if "teas" in f or "(teas" in n:
        return "teas"
    if "hl" in f or "sf" in f or "(hl" in n or "(sf" in n or "hl/sf" in n:
        return "hl"
    if "prep" in f or any(n.startswith(r) or (" " + r) in n for r in _PREP_ROLES):
        return "prep"
    return "doc"

def stage_color(st):
    return PHASE_COLORS[phase_of(st)]

def stage_prog(st):
    """Avance 0..1 de UNA etapa (escenas hechas; en curso cuenta media). Para la
    barra de la etapa activa del widget."""
    scenes = st.get("scenes") or []
    if scenes:
        d = sum(1 for x in scenes if x.get("estado") == "done")
        l = sum(1 for x in scenes if x.get("estado") == "live")
        return (d + l * 0.5) / len(scenes)
    e = st.get("estado")
    return 1.0 if e == "done" else 0.5 if e == "live" else 0.0

def wed_prog(w):
    """Avance 0..1 de una boda = etapas de edición hechas / etapas de edición — el mismo
    "Avance %" del dashboard (Cambios no cuenta)."""
    work = [s for s in (w.get("stages") or []) if not s.get("isCorrections")]
    if not work:
        return 0.0
    return sum(1 for s in work if s.get("estado") == "done") / len(work)

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
        live_stage = next((s for s in stages if s.get("estado") == "live" and not s.get("isCorrections")), None)
        if live_stage:
            live_scene = next((sc for sc in (live_stage.get("scenes") or []) if sc.get("estado") == "live"), None)
            active = {
                "wedding": live_w.get("name"),
                "icon": live_w.get("icon"),
                "stage": live_stage.get("etapa"),
                "stageColor": stage_color(live_stage),
                "stageProgress": round(stage_prog(live_stage), 3),
                "stageHours": live_stage.get("hours"),
                "scene": (live_scene or {}).get("escena"),
            }
        else:
            active = {"wedding": live_w.get("name"), "icon": live_w.get("icon"),
                      "stage": None, "stageColor": PHASE_COLORS["doc"], "stageProgress": None}

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
        _write_json_atomic(CACHE_FILE, {"at": _cache["at"], "data": _cache["data"]})
    except Exception:
        pass

def _do_build(wait=False):
    """Reconstruye los datos y actualiza caché (memoria + disco). Si ya hay una
    extracción en curso no lanza otra: con wait=True espera a que termine y usa su
    resultado (botón ↻, registro de sesiones); sin wait, simplemente no hace nada."""
    if not _build_lock.acquire(blocking=False):
        if wait:
            with _build_lock:
                pass
        return
    try:
        data = build_data()
        with _lock:
            _cache["data"] = data
            _cache["at"] = time.time()
        _save_disk_cache()
    except Exception as e:
        sys.stderr.write("[refresh] error: %s\n" % e)
    finally:
        _build_lock.release()


def _refresh_in_background():
    if not _build_lock.locked():
        threading.Thread(target=_do_build, daemon=True).start()


def get_data(fresh=False):
    """Stale-while-revalidate: responde YA con lo cacheado y refresca en 2º plano."""
    if fresh:                       # botón ↻ Actualizar → síncrono
        _do_build(wait=True)
        return _cache["data"]
    with _lock:
        cached = _cache["data"]
        age = time.time() - _cache["at"]
    if cached is None:              # primera vez sin caché → construir ya
        _do_build(wait=True)
        return _cache["data"]
    if age > CACHE_TTL:             # caché viejo → refrescar sin bloquear
        _refresh_in_background()
    return cached                   # respuesta instantánea


# ── Refresco de la nube desde el Mac (cada 15 min) ───────────────────────────
# El cron de GitHub ("*/30") no se cumple: GitHub lo retrasa o lo descarta en horas
# de carga y en la práctica corría ~5 veces al día (mediana ~4 h entre corridas,
# medido sep-nov 2026). Un "workflow_dispatch" sí arranca al momento, así que el
# server local (siempre encendido por launchd) lo pide cada 15 min con el `gh` ya
# autenticado del Mac. Si en los últimos 12 min ya hubo una corrida (cron, manual
# o de este mismo aviso) no pide otra → como mucho ~4 por hora. Con el Mac dormido
# o sin red no pasa nada: el cron de GitHub sigue de respaldo.
# Solo corre en el server local del puerto por defecto (no en Actions, que importa
# este archivo sin llamar a main(), ni en copias de prueba con otro puerto).
# Apagar: HUB_CLOUD_PING=0 en el entorno.
CLOUD_REPO = "jordissan/hub-edicion"
CLOUD_WORKFLOW = "publish.yml"
CLOUD_PING_EVERY = 15 * 60       # s entre avisos
CLOUD_PING_MIN_GAP = 12 * 60     # no pedir otra si la última corrida empezó hace menos
_GH_CANDIDATES = ("/Users/jordi/bin/gh", "/opt/homebrew/bin/gh", "/usr/local/bin/gh")


def _gh_path():
    import shutil
    for p in _GH_CANDIDATES:
        if os.path.exists(p):
            return p
    return shutil.which("gh")


def cloud_ping_once(force=False):
    """Pide a GitHub una corrida del extractor de la nube si no hubo una reciente
    (force=True: la pide siempre). Devuelve un texto corto con lo que hizo (para el log)."""
    import subprocess
    gh = _gh_path()
    if not gh:
        return "sin gh"
    try:
        if not force:
            out = subprocess.run(
                [gh, "run", "list", "-R", CLOUD_REPO, "-w", CLOUD_WORKFLOW, "-L", "1",
                 "--json", "createdAt", "--jq", ".[0].createdAt // \"\""],
                capture_output=True, text=True, timeout=30)
            last = (out.stdout or "").strip()
            if out.returncode == 0 and last:
                started = datetime.datetime.fromisoformat(last.replace("Z", "+00:00"))
                age = (datetime.datetime.now(datetime.timezone.utc) - started).total_seconds()
                if age < CLOUD_PING_MIN_GAP:
                    return "reciente (%d min)" % (age // 60)
        r = subprocess.run([gh, "workflow", "run", CLOUD_WORKFLOW, "-R", CLOUD_REPO],
                           capture_output=True, text=True, timeout=30)
        return "pedida" if r.returncode == 0 else "error: %s" % (r.stderr or "").strip()[:200]
    except Exception as e:
        return "error: %s" % e


def _cloud_ping_loop():
    # Se mide con la hora del reloj (time.time) y se revisa cada minuto: el sleep de macOS no
    # cuenta el tiempo con el Mac dormido, así que un sleep(15 min) seguido podía tardar hasta
    # 15 min de Mac despierto tras abrir la tapa (9-nov: durmió 18:25-19:50 y no pidió nada al
    # despertar). Tras un error (p. ej. sin red al despertar) reintenta a los 3 min.
    time.sleep(90)                   # deja arrancar el server (y no pide nada en reinicios rápidos)
    next_at = 0.0
    while True:
        if time.time() >= next_at:
            res = cloud_ping_once()
            if not res.startswith("reciente"):
                sys.stderr.write("[nube] %s · %s\n" % (time.strftime("%H:%M"), res))
            next_at = time.time() + (180 if res.startswith(("error", "sin gh")) else CLOUD_PING_EVERY)
        time.sleep(60)


# Aviso inmediato tras registrar una sesión o cerrar escena/etapa. Sin esto, si Jordi terminaba
# y cerraba la tapa, la nube (y el iPhone) no veían la sesión hasta el respaldo de GitHub
# (mediana ~4 h). Agrupa ráfagas (sesión + cierre llegan con segundos de diferencia): espera
# 20 s desde el ÚLTIMO evento y pide una sola corrida, sin el filtro de 12 min. Si ya hay una
# en marcha, GitHub deja la nueva en cola (concurrency "publicar") → siempre lee lo recién
# escrito. Si falla (sin red), reintenta 3 veces cada minuto.
CLOUD_SOON_WAIT = 20
_cloud_soon = {"at": 0.0, "busy": False}
_cloud_soon_lock = threading.Lock()


def cloud_ping_soon():
    if os.environ.get("HUB_CLOUD_PING", "1") == "0" or PORT != 4599:
        return
    with _cloud_soon_lock:
        _cloud_soon["at"] = time.time()
        if _cloud_soon["busy"]:
            return                    # ya hay un aviso esperando: solo se alarga la espera
        _cloud_soon["busy"] = True

    def run():
        while True:
            with _cloud_soon_lock:
                wait = _cloud_soon["at"] + CLOUD_SOON_WAIT - time.time()
                if wait <= 0:
                    _cloud_soon["busy"] = False
                    break
            time.sleep(min(wait, CLOUD_SOON_WAIT))
        for _ in range(4):
            res = cloud_ping_once(force=True)
            sys.stderr.write("[nube] %s · %s (tras sesión)\n" % (time.strftime("%H:%M"), res))
            if not res.startswith("error"):
                break
            time.sleep(60)
    threading.Thread(target=run, daemon=True).start()


def start_cloud_ping():
    if os.environ.get("HUB_CLOUD_PING", "1") == "0" or PORT != 4599:
        return
    threading.Thread(target=_cloud_ping_loop, daemon=True).start()


# ── Servidor HTTP ────────────────────────────────────────────────────────────
_session_done = {}   # id del sprint -> resultado (evita duplicados si el navegador reintenta)
_session_lock = threading.Lock()   # un registro a la vez: si llega un reintento del MISMO sprint
                                   # mientras el primero sigue escribiendo en Notion (lento / 429),
                                   # espera y recibe su resultado en vez de crear la sesión dos veces
_close_done = {}     # id del cierre -> resultado (ídem)


# ── Cola local de envíos a Notion (sesiones y cierres del sprint) ───────────
# Todo lo que el sprint manda a Notion se apunta PRIMERO aquí, en disco (.outbox.json):
# sobrevive a cerrar la app, a matar el server y a reiniciar el Mac. Luego se sube en
# orden de llegada (una sesión antes que el cierre de su escena). Cada entrada sale de la
# cola solo cuando Notion confirma. Sin internet se queda y se reintenta sola: cada
# 30-120 s, y al instante cuando la app del reloj avisa que volvió la red o que el Mac
# despertó (POST /api/outbox/flush). Un fallo de red corta la ronda (respeta el orden);
# un rechazo de Notion (4xx) deja esa entrada aparte, reintentándose cada 15 min, y sigue.
# "step" guarda lo ya hecho de cada envío → reanudar un envío cortado no duplica nada.
OUTBOX_FILE = os.environ.get("HUB_OUTBOX_FILE") or os.path.join(HERE, ".outbox.json")
OUTBOX_PERM_RETRY = 15 * 60
_ob = {"items": [], "sent": None}      # sent = {"at": ms, "n": cuántas en la última subida}
_ob_lock = threading.RLock()           # datos de la cola + su archivo
_ob_send_lock = threading.Lock()       # una subida a la vez (y en orden)
_ob_wake = threading.Event()


def is_transient(e):
    """¿Fallo pasajero (sin red, Notion caído, límite de ritmo, sin token) o rechazo de Notion?"""
    if isinstance(e, NotionError):
        return e.code == 429 or e.code >= 500
    if isinstance(e, RuntimeError):
        return str(e) == "NO_TOKEN"
    return True                          # URLError, timeout, conexión cortada…


def outbox_load():
    try:
        with open(OUTBOX_FILE, "r") as f:
            d = json.load(f)
        if isinstance(d, dict) and isinstance(d.get("items"), list):
            with _ob_lock:
                _ob["items"] = [e for e in d["items"] if isinstance(e, dict) and e.get("id")]
                _ob["sent"] = d.get("sent")
    except FileNotFoundError:
        pass
    except Exception as e:
        sys.stderr.write("[cola] no se pudo leer %s: %s\n" % (OUTBOX_FILE, e))


def _ob_save():
    with _ob_lock:
        for attempt in range(3):           # (si el hilo de subida tocaba un "step" justo ahora, otra vez)
            try:
                _write_json_atomic(OUTBOX_FILE, _ob)
                return
            except RuntimeError:
                time.sleep(0.05)
            except Exception as e:
                sys.stderr.write("[cola] no se pudo guardar: %s\n" % e)
                return


def _now_ms():
    return int(time.time() * 1000)


def outbox_add(kind, item, label=None):
    """Apunta un envío en la cola (en disco). Si ya estaba (mismo id), no lo repite."""
    with _ob_lock:
        for e in _ob["items"]:
            if e["id"] == item["id"]:
                return e
        e = {"kind": kind, "id": item["id"], "item": item, "label": (label or "")[:120],
             "at": _now_ms(), "tries": 0, "err": None, "perm": False, "next": 0, "step": {}}
        _ob["items"].append(e)
        _ob_save()
        return e


def outbox_has(item_id):
    with _ob_lock:
        return any(e["id"] == item_id for e in _ob["items"])


def outbox_drop(item_id):
    with _ob_lock:
        _ob["items"] = [e for e in _ob["items"] if e["id"] != item_id]
        _ob_save()


def outbox_summary():
    """Lo que ven la ventana y el reloj: qué espera subir y cuándo fue la última subida."""
    with _ob_lock:
        items = []
        for e in _ob["items"]:
            it = e.get("item") or {}
            mins = None
            if e["kind"] == "session":
                a, b = _iso_ok(it.get("inicio")), _iso_ok(it.get("fin"))
                mins = round((b - a).total_seconds() / 60) if a and b else None
            items.append({"kind": e["kind"], "label": e.get("label") or "", "mins": mins,
                          "cerrar": it.get("cerrar"), "at": e.get("at"), "err": e.get("err"),
                          "perm": bool(e.get("perm"))})
        return {"n": len(items), "items": items, "sent": _ob["sent"]}


def _ob_send_one(e):
    def save_step():
        _ob_save()
    if e["kind"] == "session":
        res = create_session(e["item"], e["step"], save_step)
        out = {"ok": True, "url": res.get("url"), "moved": res.get("moved", [])}
        if res.get("warn"):
            out["warn"] = res["warn"]
        return out
    return {"ok": True, "closed": close_targets(e["item"], e["step"], save_step)}


def outbox_flush(force=False, until=None):
    """Sube la cola en orden. Devuelve (estado, resultado) del envío `until` si se intentó:
    ("ok", out) · ("perm", error) · ("wait", error) · (None, None) si no llegó a intentarse."""
    result = (None, None)
    sent = 0
    with _ob_send_lock:
        _notion_opts.fast = True
        try:
            with _ob_lock:
                todo = list(_ob["items"])
            for e in todo:
                now = time.time()
                if e.get("perm") and not force and e["id"] != until and now < e.get("next", 0):
                    continue                          # rechazada por Notion: aparte, cada 15 min
                if not e.get("perm") and not force and not until and now < e.get("next", 0):
                    break                             # sin red hace poco: espera su turno (en orden)
                try:
                    out = _ob_send_one(e)
                except Exception as ex:
                    transient = is_transient(ex)
                    with _ob_lock:
                        e["tries"] = e.get("tries", 0) + 1
                        e["err"] = str(ex)[:200] or ex.__class__.__name__
                        e["perm"] = not transient
                        e["next"] = time.time() + (min(30 * e["tries"], 120) if transient else OUTBOX_PERM_RETRY)
                        _ob_save()
                    if e["id"] == until:
                        result = ("wait" if transient else "perm", e["err"])
                    if e["tries"] == 1 or e["tries"] % 20 == 0:
                        sys.stderr.write("[cola] %s · %s %s: %s\n" % (
                            time.strftime("%H:%M"), e["kind"], e["id"][:8], e["err"]))
                    if transient:
                        break                         # sin red: lo demás esperaría igual (y en orden)
                    continue
                (_session_done if e["kind"] == "session" else _close_done)[e["id"]] = out
                deferred = bool(e.get("tries")) or e["id"] != until   # no es el envío en vivo que acaba de llegar
                with _ob_lock:
                    _ob["items"] = [x for x in _ob["items"] if x["id"] != e["id"]]
                    if deferred:                      # subida diferida (la avisa la ventana y el reloj)
                        prev = _ob["sent"] or {}
                        recent = _now_ms() - (prev.get("at") or 0) < 10 * 60 * 1000
                        _ob["sent"] = {"at": _now_ms(), "n": (prev.get("n", 0) if recent else 0) + 1}
                    _ob_save()
                if deferred:
                    sys.stderr.write("[cola] %s · subida: %s %s\n" % (time.strftime("%H:%M"), e["kind"], e["id"][:8]))
                sent += 1
                if e["id"] == until:
                    result = ("ok", out)
        finally:
            _notion_opts.fast = False
    if sent:
        _refresh_in_background()   # que el tablero lo muestre en cuanto se reconstruya
        cloud_ping_soon()          # y la nube (iPhone) en ~3 min
    return result


def outbox_poke():
    """Volvió la red / despertó el Mac / "Subir ahora": que el hilo de la cola lo intente ya."""
    _ob_wake.set()


def _outbox_loop():
    forced = False
    while True:
        with _ob_lock:
            pending = bool(_ob["items"])
        if pending:
            try:
                outbox_flush(force=forced)
            except Exception as e:
                sys.stderr.write("[cola] error inesperado: %s\n" % e)
        forced = _ob_wake.wait(timeout=30)
        _ob_wake.clear()


def start_outbox():
    outbox_load()
    threading.Thread(target=_outbox_loop, daemon=True).start()


# ── Estado compartido del sprint (dashboard ⇄ ventana flotante del Mac) ─────
# Cada cliente guarda su sprint en localStorage; aquí vive la copia común. Gana la
# versión con "rev" (ms) más reciente. La ventana flotante pregunta con ?from=mini y
# eso sirve de latido: el dashboard sabe si está abierta (miniOpen).
SPRINT_FILE = os.path.join(HERE, ".sprint-state.json")
SPRINT_KEYS = ("scSprint", "scSprintPend", "scSprintDest", "scSprintMode", "scSprintBrk", "scSprintCyc",
               # cierre de escena/etapa en espera y ids recién cerrados: el front ya los sincronizaba, pero
               # aquí se descartaban → el reloj del Mac nunca veía «Deshacer el cierre» ni su aviso de error
               "scSprintClose", "scSprintClosed")
_sprint_lock = threading.Lock()
_sprint = {"rev": 0, "data": {}}
_mini_seen = [0.0]
try:
    with open(SPRINT_FILE, "r") as f:
        _prev = json.load(f)
    if isinstance(_prev, dict) and isinstance(_prev.get("data"), dict):
        _sprint = {"rev": int(_prev.get("rev") or 0), "data": _prev["data"]}
except Exception:
    pass


def sprint_state(from_mini=False, incoming=None):
    with _sprint_lock:
        if from_mini:
            _mini_seen[0] = time.time()
        if incoming is not None:
            rev, data = incoming.get("rev"), incoming.get("data")
            if isinstance(rev, (int, float)) and isinstance(data, dict) and rev > _sprint["rev"]:
                _sprint["rev"] = int(rev)
                _sprint["data"] = {k: data.get(k) for k in SPRINT_KEYS}
                try:
                    _write_json_atomic(SPRINT_FILE, _sprint)
                except Exception as e:
                    sys.stderr.write("[sprint] no se pudo guardar: %s\n" % e)
        return {"rev": _sprint["rev"], "data": _sprint["data"],
                "miniOpen": time.time() - _mini_seen[0] < 6,
                "outbox": outbox_summary()}     # cola local de envíos a Notion (ventana y reloj)


class Handler(http.server.BaseHTTPRequestHandler):
    def _send(self, code, body, ctype="application/json; charset=utf-8", cache="no-store"):
        if isinstance(body, str):
            body = body.encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Cache-Control", cache)
        self.end_headers()
        self.wfile.write(body)

    def _send_payload(self, build):
        """Responde JSON con build() o {"error": ...} legible (siempre 200: el front
        lo distingue por la clave "error")."""
        try:
            self._send(200, json.dumps(build(), ensure_ascii=False))
        except RuntimeError as e:
            msg = str(e)
            if msg == "NO_TOKEN":
                msg = ("Falta el token de Notion. Crea una integración en "
                       "notion.so/my-integrations, comparte tu workspace 'Trabajo' con ella "
                       "y guarda el token en ~/.notion-dashboard-token")
            self._send(200, json.dumps({"error": msg}, ensure_ascii=False))
        except Exception as e:
            self._send(200, json.dumps({"error": str(e)}, ensure_ascii=False))

    def _close(self):
        """POST /api/close: cierra la escena (y la etapa) del sprint que acaba de terminar."""
        try:
            n = int(self.headers.get("Content-Length") or 0)
            item = json.loads(self.rfile.read(min(n, 20000)).decode("utf-8") or "{}")
        except Exception:
            self._send(400, json.dumps({"ok": False, "error": "JSON inválido"}))
            return
        label = item.pop("label", None) if isinstance(item, dict) else None
        err = validate_close(item)
        if err:
            self._send(400, json.dumps({"ok": False, "error": err}, ensure_ascii=False))
            return
        if item["id"] in _close_done:
            self._send(200, json.dumps(_close_done[item["id"]]))
            return
        if outbox_has(item["id"]):
            self._queued()
            return
        targets = session_targets(_cache.get("data"))      # misma lista blanca que /api/session
        terr = target_error(item, targets)
        if terr:
            self._send(400, json.dumps({"ok": False, "error": terr}, ensure_ascii=False))
            return
        self._via_outbox("close", item, label)

    def _queued(self):
        """Guardado en la cola del Mac: se sube solo a Notion cuando se pueda."""
        self._send(200, json.dumps({"ok": True, "queued": True, "local": True,
                                    "pending": outbox_summary()["n"]}))

    def _via_outbox(self, kind, item, label):
        """Apunta el envío en la cola (en disco) y sube la cola hasta él. Con internet: igual
        que antes (registrado en Notion). Sin internet: queda guardado → ok + queued/local.
        Si Notion lo RECHAZA (4xx) al primer intento, sale de la cola y la página lo muestra
        como siempre (Reintentar / Descartar), porque no es cosa de la red."""
        outbox_add(kind, item, label)
        st, res = outbox_flush(until=item["id"])
        if st == "ok":
            self._send(200, json.dumps(res))
        elif st == "perm":
            outbox_drop(item["id"])
            self._send(502, json.dumps({"ok": False, "error": res}, ensure_ascii=False))
        else:
            self._queued()

    def do_POST(self):
        path = self.path.split("?")[0]
        if path == "/api/sprint-state":
            try:
                n = int(self.headers.get("Content-Length") or 0)
                body = json.loads(self.rfile.read(min(n, 50000)).decode("utf-8") or "{}")
            except Exception:
                self._send(400, json.dumps({"ok": False, "error": "JSON inválido"}))
                return
            self._send(200, json.dumps(sprint_state("from=mini" in self.path, body), ensure_ascii=False))
            return
        if path == "/api/close":
            self._close()
            return
        if path == "/api/outbox/flush":       # la app del reloj: volvió la red, despertó el Mac o "Subir ahora"
            outbox_poke()
            self._send(200, json.dumps(outbox_summary(), ensure_ascii=False))
            return
        if path != "/api/session":
            self._send(404, json.dumps({"ok": False, "error": "No existe"}))
            return
        try:
            n = int(self.headers.get("Content-Length") or 0)
            item = json.loads(self.rfile.read(min(n, 20000)).decode("utf-8") or "{}")
        except Exception:
            self._send(400, json.dumps({"ok": False, "error": "JSON inválido"}))
            return
        label = item.pop("label", None) if isinstance(item, dict) else None
        err = validate_session(item)
        if err:
            self._send(400, json.dumps({"ok": False, "error": err}, ensure_ascii=False))
            return
        with _session_lock:
            if item["id"] in _session_done:
                self._send(200, json.dumps(_session_done[item["id"]]))
                return
            if outbox_has(item["id"]):        # ya está guardada en el Mac (reintento de la página)
                self._queued()
                return
            # solo DBs de Sesiones / etapas / escenas del tablero (no escribe donde le pidan)
            targets = session_targets(_cache.get("data"))
            if not any(t["stage"] for t in targets.values()):
                _do_build(wait=True)  # caché de antes del sprint (sin ids de etapa) → reconstruir una vez
                targets = session_targets(_cache.get("data"))
            terr = target_error(item, targets)
            if terr:
                self._send(400, json.dumps({"ok": False, "error": terr}, ensure_ascii=False))
                return
            # cola local: con internet se registra ya (y el tablero/la nube se refrescan al subir);
            # sin internet queda guardada en el Mac y se sube sola al volver la red
            self._via_outbox("session", item, label)

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
        if path == "/api/sprint-state":
            self._send(200, json.dumps(sprint_state("from=mini" in self.path), ensure_ascii=False))
            return
        if path == "/api/outbox":
            self._send(200, json.dumps(outbox_summary(), ensure_ascii=False))
            return
        if path == "/api/embed-link":
            from urllib.parse import urlparse, parse_qs
            boda = (parse_qs(urlparse(self.path).query).get("boda") or [""])[0].strip().lower()
            if not re.fullmatch(r"[a-z0-9]+(-[a-z0-9]+)*", boda):
                self._send(400, json.dumps({"error": "Falta la boda."}, ensure_ascii=False))
                return
            link = embed_link(boda)
            if not link:
                self._send(503, json.dumps({"error": "Falta .embed-secret en el Mac."}, ensure_ascii=False))
                return
            self._send(200, json.dumps(link, ensure_ascii=False))
            return
        fresh = "fresh=1" in self.path
        if path == "/api/data":
            self._send_payload(lambda: get_data(fresh=fresh))
            return
        if path == "/api/summary":
            self._send_payload(lambda: build_summary(get_data(fresh=fresh)))
            return
        # Estáticos de la PWA (lista blanca, sin acceso libre al disco)
        statics = {
            "/manifest.json": "application/manifest+json",
            "/icon-180.png": "image/png",
            "/icon-192.png": "image/png",
            "/icon-512.png": "image/png",
            # fuentes del dashboard (alfabeto latino; el nombre lleva versión → caché larga)
            "/fonts/archivo-latin-v1.woff2": "font/woff2",
            "/fonts/inter-latin-v1.woff2": "font/woff2",
            "/fonts/jetbrains-mono-latin-v1.woff2": "font/woff2",
        }
        if path in statics:
            try:
                with open(os.path.join(HERE, path.lstrip("/")), "rb") as f:
                    self._send(200, f.read(), statics[path],
                               "public, max-age=31536000, immutable" if path.startswith("/fonts/") else "no-store")
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
        _refresh_in_background()
    start_cloud_ping()                       # la nube se refresca cada 15 min mientras el Mac esté encendido
    start_outbox()                           # lo que quedó guardado sin internet se sube solo
    # solo este Mac (antes 0.0.0.0: cualquiera en la misma Wi-Fi podía leer los datos o registrar sesiones)
    ThreadingServer(("127.0.0.1", PORT), Handler).serve_forever()


if __name__ == "__main__":
    main()
