#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Guardián de privacidad del repo público (github.com/jordissan/hub-edicion). Lo llama sync-cloud.sh.

  python3 privacidad.py copiar ORIGEN REPO RUTA  copia ORIGEN (ruta local, relativa a ~/HubEdicion)
                                                a REPO/RUTA cambiando nombres reales por nombres de
                                                ejemplo, montos en pesos por $XX,XXX y, en los .md,
                                                re-apuntando los enlaces a su lugar en el repo
  python3 privacidad.py revisar [CARPETA]       revisa TODO lo que git subiría desde CARPETA (cloud/):
                                                si encuentra una llave, un correo, un ID o un nombre
                                                real, lo dice (sin mostrar el valor) y sale con error

De dónde saca qué es privado (todo vive solo en la Mac, nunca en el repo):
  · nombres de parejas y estudios → .cache.json y .archive.json (los datos reales del server local)
  · cambios fijos real → ejemplo  → .privacidad.json (se crea solo; cada nombre conserva su
                                    sustituto para que los diffs no bailen). Puedes añadir a mano
                                    nombres en "extra": {"Nombre real": "Ejemplo"}.
  · llaves reales                 → ~/.notion-dashboard-token, .embed-secret y los widgets vivos de
                                    Scriptable en iCloud (Service Token de Cloudflare Access, Token.js)
Solo librería estándar.
"""
import json, os, re, subprocess, sys

HERE = os.environ.get("HUB_HOME") or os.path.dirname(os.path.abspath(__file__))
MAPA = os.environ.get("HUB_MAPA") or os.path.join(HERE, ".privacidad.json")
ICLOUD = os.path.expanduser("~/Library/Mobile Documents/iCloud~dk~simonbs~Scriptable/Documents")

# Las mismas parejas inventadas que usa snapshot-demo.py, y nombres sueltos de reserva
PAREJAS = ["Lucía + Mateo", "Sofía + Diego", "Valentina + Tomás", "Renata + Emilio", "Paula + Bruno",
           "Julia + Marcos", "Elena + Iván", "Carla + Hugo", "Marta + Leo", "Nora + Samuel",
           "Irene + Adrián", "Olivia + Gael", "Clara + Rubén", "Daniela + Joel", "Abril + Simón"]
SUELTOS = ["Ana", "Luis", "Eva", "Raúl", "Inés", "Pablo", "Laura", "Óscar", "Rosa", "Alba",
           "Sergio", "Lola", "Martín", "Celia", "Bruno", "Sara", "Mario", "Noa", "Teo"]
# palabras de los nombres de proyecto/etapa que NO son personas
NO_PERSONA = {"Boda", "Teaser", "Video", "Proyecto", "Preboda", "Prueba", "PRUEBA", "Arquitectura",
              "Nueva", "Nuevo", "Origen", "Musica", "Música", "Sesión", "Freelance", "Estudio", "Demo"}
# placeholder de llave aceptado en el repo
PLACEHOLDER = re.compile(r"^(PEGA|PON|TU_|YOUR|xxx|XXX|<)", re.I)
TEXTO = {".md", ".html", ".js", ".py", ".swift", ".sh", ".plist", ".json", ".yml", ".yaml", ".txt",
         ".toml", ".command", ".css", ""}
BINARIOS_OK = {"icon-180.png", "icon-192.png", "icon-512.png"}   # los únicos binarios que pueden subir
IDS_PERMITIDOS = {"server.py"}   # tiene IDs de Notion desde antes (pendiente: moverlos a config)


def _json(p, d):
    try:
        with open(p, encoding="utf-8") as f: return json.load(f)
    except Exception: return d


def _reales():
    """(parejas, estudios, proyectos) tal como vienen de los datos reales."""
    c = _json(os.path.join(HERE, ".cache.json"), {}).get("data", {})
    a = _json(os.path.join(HERE, ".archive.json"), [])
    parejas, estudios, proyectos = [], [], []
    for w in (c.get("weddings") or []) + (a if isinstance(a, list) else []):
        if w.get("name"): parejas.append(w["name"].strip())
        if w.get("studio"): estudios.append(w["studio"].strip())
    for p in c.get("projects") or []:
        if p.get("name"): proyectos.append(p["name"].strip())
        if p.get("studio"): estudios.append(p["studio"].strip())
    return parejas, estudios, proyectos


def mapa():
    """Mapa real → ejemplo, estable entre corridas (se guarda en .privacidad.json, fuera de git)."""
    m = _json(MAPA, {})
    m.setdefault("parejas", {}); m.setdefault("nombres", {}); m.setdefault("extra", {})
    parejas, estudios, proyectos = _reales()
    usados = set(m["parejas"].values())
    for n in parejas:
        if n in m["parejas"]: continue
        libre = [p for p in PAREJAS if p not in usados]
        m["parejas"][n] = libre[0] if libre else "Pareja %d" % (len(m["parejas"]) + 1)
        usados.add(m["parejas"][n])
    # nombres sueltos: cada persona de la pareja real → la persona de la pareja de ejemplo
    usados_n = set(m["nombres"].values())
    for real, demo in m["parejas"].items():
        r = [t for t in re.findall(r"[A-Za-zÁÉÍÓÚÑáéíóúñü]{3,}", real) if t not in NO_PERSONA]
        d = re.findall(r"[A-Za-zÁÉÍÓÚÑáéíóúñü]{2,}", demo)
        for i, t in enumerate(r):
            if t in m["nombres"]: continue
            cand = d[i] if i < len(d) and d[i] not in usados_n else next(
                (s for s in SUELTOS if s not in usados_n), "Persona%d" % len(usados_n))
            m["nombres"][t] = cand; usados_n.add(cand)
    n_est = sum(v.startswith("Estudio ") for v in m["extra"].values())
    for o in estudios:
        if o not in m["extra"] and o not in NO_PERSONA:
            m["extra"][o] = "Estudio %s" % chr(ord("A") + n_est % 26); n_est += 1
    n_pro = sum(v.startswith("Proyecto de ejemplo") for v in m["extra"].values())
    for o in proyectos:
        if o not in m["extra"]:
            n_pro += 1; m["extra"][o] = "Proyecto de ejemplo %d" % n_pro
    with open(MAPA, "w", encoding="utf-8") as f: json.dump(m, f, ensure_ascii=False, indent=1)
    os.chmod(MAPA, 0o600)
    return m


def _caso(src, dst):
    return dst.lower() if src.islower() else dst.upper() if src.isupper() and len(src) > 1 else dst


def limpiar(txt, m):
    for real, demo in sorted({**m["parejas"], **m["extra"]}.items(), key=lambda kv: -len(kv[0])):
        txt = re.sub(r"(?<!\w)" + re.escape(real) + r"(?!\w)", demo, txt)
    for real, demo in sorted(m["nombres"].items(), key=lambda kv: -len(kv[0])):
        txt = re.sub(r"(?<!\w)" + re.escape(real) + r"(?!\w)", lambda g: _caso(g.group(0), demo), txt,
                     flags=re.I)
    # montos en pesos ($ con miles, o «… MXN»)
    txt = re.sub(r"\$\s?\d{1,3}(?:[,  ]\d{3})+(?:\.\d+)?", "$XX,XXX", txt)
    txt = re.sub(r"\b\d{1,3}(?:[,  ]\d{3})+\s?MXN\b", "XX,XXX MXN", txt)
    return txt


MD_LINK = re.compile(r"(!?)\[([^\]]*)\]\(([^)\s]+)\)")
NO_SUBEN = (".png", ".jpg", ".jpeg", ".gif", ".pdf", ".shortcut", ".mov", ".mp4")


def enlaces(txt, src_rel, dst_rel):
    """Los .md locales enlazan con rutas de ~/HubEdicion; en el repo cambian (cloud/X → X,
    README.md → docs/guia-de-uso.md). Las capturas no suben: el enlace se vuelve una nota."""
    def fix(mt):
        bang, label, target = mt.groups()
        if re.match(r"^([a-z][a-z0-9+.-]*:|#|/)", target, re.I): return mt.group(0)
        path, _, frag = target.partition("#")
        local = os.path.normpath(os.path.join(os.path.dirname(src_rel), path))
        if local.lower().endswith(NO_SUBEN):
            return "*(captura solo en la Mac: %s)*" % (label or os.path.basename(local))
        if local.startswith("cloud/"): repo = local[len("cloud/"):]
        elif local == "README.md": repo = "docs/guia-de-uso.md"
        elif local in ("sync-cloud.sh", "privacidad.py", "snapshot-demo.py", "start.command",
                       "com.jordi.hub-edicion.plist"): repo = "scripts/" + local
        else: repo = local
        new = os.path.relpath(repo, os.path.dirname(dst_rel) or ".")
        return "%s[%s](%s%s)" % (bang, label, new, "#" + frag if frag else "")
    return MD_LINK.sub(fix, txt)


def llaves():
    """Valores de llaves reales que viven en la Mac (para buscarlos tal cual; nunca se imprimen)."""
    vals = set()
    def add(v):
        v = (v or "").strip()
        if len(v) >= 16 and not PLACEHOLDER.match(v): vals.add(v)
    for p in (os.path.expanduser("~/.notion-dashboard-token"), os.path.join(HERE, ".embed-secret")):
        try: add(open(p, encoding="utf-8").read())
        except Exception: pass
    if os.environ.get("NOTION_TOKEN"): add(os.environ["NOTION_TOKEN"])
    if os.path.isdir(ICLOUD):
        for fn in os.listdir(ICLOUD):
            if not fn.endswith(".js"): continue
            try: t = open(os.path.join(ICLOUD, fn), encoding="utf-8").read()
            except Exception: continue
            for v in re.findall(r"ACCESS_CLIENT_(?:ID|SECRET)\s*=\s*[\"']([^\"']+)", t): add(v)
            if fn == "Token.js":
                for v in re.findall(r"[\"']([A-Za-z0-9_\-]{20,})[\"']", t): add(v)
    return vals


PATRONES = [
    ("token de Notion", re.compile(r"\b(?:ntn|secret)_[A-Za-z0-9]{20,}")),
    ("Service Token de Access", re.compile(r"ACCESS_CLIENT_(?:ID|SECRET)\s*=\s*[\"'](?!PEGA|PON|TU_)[^\"']{12,}")),
    ("cabecera de Access con valor", re.compile(r"CF-Access-Client-(?:Id|Secret)[\"']?\s*[:,]\s*[\"'][0-9a-f]{20,}")),
    ("enlace con clave ?k=", re.compile(r"[?&]k=[0-9a-f]{10,}")),
    ("correo", re.compile(r"[A-Za-z0-9._%+-]+@(?!anthropic\.com)[A-Za-z0-9-]+\.[A-Za-z0-9.-]*[a-z]{2,}")),
]
IDS = [("ID de 32 hex (Notion/Cloudflare)", re.compile(r"(?<![0-9A-Fa-f])[0-9a-f]{32}(?![0-9A-Fa-f])")),
       ("UUID (ID de Notion)", re.compile(r"[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}"))]
MONTO = re.compile(r"\$\s?\d{1,3}(?:,\d{3})+|\b\d{1,3}(?:,\d{3})+\s?MXN")


def revisar(carpeta):
    m, secretos = mapa(), llaves()
    reales = [r for r in list(m["parejas"]) + list(m["nombres"]) + list(m["extra"]) if len(r) >= 3]
    nom = re.compile(r"(?<!\w)(" + "|".join(map(re.escape, sorted(reales, key=len, reverse=True))) + r")(?!\w)",
                     re.I) if reales else None
    files = subprocess.run(["git", "-C", carpeta, "ls-files", "-co", "--exclude-standard"],
                           capture_output=True, text=True, check=True).stdout.splitlines()
    malos = []
    for rel in files:
        p = os.path.join(carpeta, rel)
        if not os.path.isfile(p): continue
        ext = os.path.splitext(rel)[1].lower()
        if rel.startswith("fonts/") and ext == ".woff2": continue
        if ext not in TEXTO:
            if os.path.basename(rel) not in BINARIOS_OK and rel != ".gitkeep" and not rel.endswith("/.gitkeep"):
                malos.append((rel, 0, "archivo binario (captura, PDF o .shortcut) — no se revisa por dentro"))
            continue
        try: txt = open(p, encoding="utf-8").read()
        except UnicodeDecodeError:
            malos.append((rel, 0, "no es texto UTF-8")); continue
        for v in secretos:
            if v in txt: malos.append((rel, txt[:txt.index(v)].count("\n") + 1, "LLAVE REAL"))
        reglas = PATRONES + ([] if os.path.basename(rel) in IDS_PERMITIDOS else IDS)
        for i, linea in enumerate(txt.splitlines(), 1):
            for nombre, rx in reglas:
                if rx.search(linea): malos.append((rel, i, nombre))
            if nom and nom.search(linea): malos.append((rel, i, "nombre real (pareja o estudio)"))
            if ext == ".md" and MONTO.search(linea): malos.append((rel, i, "monto en pesos"))
    return malos


def main():
    if len(sys.argv) >= 5 and sys.argv[1] == "copiar":
        src, repo, rel = sys.argv[2], sys.argv[3], sys.argv[4]
        dst = os.path.join(repo, rel)
        with open(src, encoding="utf-8") as f: txt = f.read()
        out = limpiar(txt, mapa())
        if src.endswith(".md"): out = enlaces(out, src, rel)
        os.makedirs(os.path.dirname(dst) or ".", exist_ok=True)
        with open(dst, "w", encoding="utf-8") as f: f.write(out)
        os.chmod(dst, os.stat(src).st_mode & 0o777)
        return 0
    if len(sys.argv) >= 2 and sys.argv[1] == "revisar":
        carpeta = sys.argv[2] if len(sys.argv) > 2 else os.path.join(HERE, "cloud")
        malos = revisar(carpeta)
        if malos:
            print("✗ Privacidad: esto no puede subir al repo público:")
            for rel, i, que in malos[:60]: print("   %s%s — %s" % (rel, ":%d" % i if i else "", que))
            if len(malos) > 60: print("   … y %d más" % (len(malos) - 60))
            return 1
        print("✓ Privacidad: sin llaves, correos, IDs ni nombres reales en lo que sube.")
        return 0
    print(__doc__); return 2


if __name__ == "__main__":
    sys.exit(main())
