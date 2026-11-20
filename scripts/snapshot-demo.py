#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Renueva el snapshot embebido de index.html (window.SNAPSHOT_DATA) con DATOS DE EJEMPLO.

El repo de la nube es público: el snapshot NO debe llevar datos reales. Este script toma el
payload vivo del server local, le quita todo lo identificable y lo embebe:
  · nombres de parejas  → parejas inventadas (las mismas en tablero y archivo)
  · estudio             → "Estudio demo"
  · precio              → 15 000 fijo
  · enlaces a Notion    → vacíos
  · ids de Notion       → ids "demo-…" (se conservan las relaciones escena ↔ sesión)
  · escenas / canciones → "Escena N" (se respeta "Día 1 / Día 2") y sin canción
  · nombre de la sesión → "Sesión"
Se conservan fechas, duraciones y etapas (tu ritmo de trabajo): así el respaldo se ve creíble.

Uso:   python3 snapshot-demo.py            (lee http://localhost:4599/api/data)
       python3 snapshot-demo.py ruta.json  (lee un payload guardado)
Después: ./sync-cloud.sh  (se niega a copiar un snapshot que no sea de ejemplo).
Solo librería estándar. El snapshot se embebe por concatenación (nunca con re.sub).
"""
import json, os, re, sys, urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
INDEX = os.path.join(HERE, "index.html")
PAREJAS = ["Lucía + Mateo", "Sofía + Diego", "Valentina + Tomás", "Renata + Emilio", "Paula + Bruno",
           "Julia + Marcos", "Elena + Iván", "Carla + Hugo", "Marta + Leo", "Nora + Samuel",
           "Irene + Adrián", "Olivia + Gael", "Clara + Rubén", "Daniela + Joel", "Abril + Simón"]
DIA_RE = re.compile(r"^\s*d[ií]a\s*(\d|uno|dos|previo)\b", re.I)


def anonymize(d):
    names, ids = {}, {}

    def pareja(n):
        k = (n or "").strip().lower()
        if k not in names:
            i = len(names)
            names[k] = PAREJAS[i] if i < len(PAREJAS) else "Pareja %d" % (i + 1)
        return names[k]

    def fid(x):
        if not x:
            return x
        if x not in ids:
            ids[x] = "demo-%04d" % (len(ids) + 1)
        return ids[x]

    # el archivo va en orden cronológico: se nombra primero para que las parejas salgan en orden
    for e in d.get("archive") or []:
        e["name"] = pareja(e.get("name"))
        if e.get("price") is not None:
            e["price"] = 15000
    for w in d.get("weddings") or []:
        w["name"] = pareja(w.get("name"))
        w["studio"] = "Estudio demo" if w.get("studio") else w.get("studio")
        w["url"] = ""
        if w.get("price") is not None:
            w["price"] = 15000
        for s in w.get("stages") or []:
            if "id" in s:
                s["id"] = fid(s.get("id"))
            s["sessionDb"] = fid(s.get("sessionDb"))
            n = 0
            for sc in s.get("scenes") or []:
                n += 1
                sc["id"] = fid(sc.get("id"))
                nm = sc.get("escena") or ""
                sc["escena"] = nm if DIA_RE.match(nm) and len(nm) <= 8 else "Escena %d" % n
                sc["cancion"] = ""
            for x in s.get("sessionLog") or []:
                x["name"] = "Sesión"
                x["escena"] = fid(x.get("escena"))
    # otros proyectos (no bodas, 12-nov-2026): nombre, cliente y precio de ejemplo
    for i, pj in enumerate(d.get("projects") or []):
        pj["name"] = "Proyecto demo %d" % (i + 1)
        pj["client"] = "Freelance" if pj.get("client") else pj.get("client")
        pj["url"] = ""
        pj["icon"] = "🎬"
        if pj.get("price") is not None:
            pj["price"] = 3000
        pj["sessionDb"] = fid(pj.get("sessionDb"))
        for x in pj.get("sessionLog") or []:
            x["name"] = "Sesión"
            x["escena"] = fid(x.get("escena"))
    d["demo"] = True          # marca que revisa sync-cloud.sh antes de copiar a la nube
    return d


def main():
    if len(sys.argv) > 1:
        with open(sys.argv[1], "r") as f:
            data = json.load(f)
    else:
        with urllib.request.urlopen("http://localhost:4599/api/data", timeout=60) as r:
            data = json.load(r)
    if data.get("error") or not data.get("weddings"):
        sys.exit("✗ El payload no trae bodas: no se toca index.html.")
    real = sorted({(w.get("name") or "").strip() for w in data["weddings"]} |
                  {(e.get("name") or "").strip() for e in data.get("archive") or []} |
                  {(p.get("name") or "").strip() for p in data.get("projects") or []})
    blob = json.dumps(anonymize(data), ensure_ascii=False, separators=(",", ":")).replace("</", "<\\/")
    # comprobación: ningún nombre real (ni sus mitades) sobrevive en lo que se va a embeber
    for full in real:
        for part in [full] + [p.strip() for p in full.split("+")]:
            if len(part) >= 4 and part.lower() in blob.lower() and part not in " ".join(PAREJAS):
                sys.exit("✗ Quedó un dato real en el snapshot (%r): no se toca index.html." % part)
    with open(INDEX, "r") as f:
        s = f.read()
    start = s.find("window.SNAPSHOT_DATA = ")
    end = s.find("\n", start)
    if start < 0 or end < 0 or s.count("window.SNAPSHOT_DATA = ") != 1:
        sys.exit("✗ No encuentro window.SNAPSHOT_DATA en index.html.")
    out = s[:start] + "window.SNAPSHOT_DATA = " + blob + ";" + s[end:]
    with open(INDEX, "w") as f:
        f.write(out)
    print("✓ Snapshot de ejemplo embebido: %d bodas, %d en archivo, %d KB (antes %d KB)." % (
        len(data["weddings"]), len(data.get("archive") or []), len(blob) // 1024, (end - start) // 1024))


if __name__ == "__main__":
    main()
