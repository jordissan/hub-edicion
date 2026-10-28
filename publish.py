#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Extractor para la nube. Lo corre GitHub Actions (cron + on-demand).
- Reusa la lógica de server.py (build_data / build_summary) para consultar Notion.
- Escribe data.json + summary.json en Cloudflare KV vía la API REST.

Variables de entorno (todas son secretos en GitHub Actions):
  NOTION_TOKEN          token de integración de Notion (lo lee server.get_token)
  CF_API_TOKEN          token de Cloudflare con permiso 'Workers KV Storage: Edit'
  CF_ACCOUNT_ID         id de tu cuenta de Cloudflare
  CF_KV_NAMESPACE_ID    id del namespace KV (el que verás al crearlo)

Solo usa la librería estándar de Python 3.
"""
import os, sys, json, urllib.request, urllib.error
import server  # build_data, build_summary (mismo archivo del dashboard)

CF_TOKEN = os.environ["CF_API_TOKEN"]
ACCOUNT  = os.environ["CF_ACCOUNT_ID"]
NS       = os.environ["CF_KV_NAMESPACE_ID"]
BASE     = "https://api.cloudflare.com/client/v4"


def kv_put(key, value):
    url = f"{BASE}/accounts/{ACCOUNT}/storage/kv/namespaces/{NS}/values/{key}"
    req = urllib.request.Request(
        url, data=value.encode("utf-8"), method="PUT",
        headers={"Authorization": f"Bearer {CF_TOKEN}",
                 "Content-Type": "text/plain; charset=utf-8"})
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            return r.status
    except urllib.error.HTTPError as e:
        sys.stderr.write(f"KV PUT {key} -> {e.code}: {e.read().decode('utf-8','ignore')[:300]}\n")
        raise


def kv_get(key):
    url = f"{BASE}/accounts/{ACCOUNT}/storage/kv/namespaces/{NS}/values/{key}"
    req = urllib.request.Request(url, headers={"Authorization": f"Bearer {CF_TOKEN}"})
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            return r.read().decode("utf-8")
    except urllib.error.HTTPError as e:
        if e.code == 404:          # la clave aún no existe (primer run)
            return None
        sys.stderr.write(f"KV GET {key} -> {e.code}: {e.read().decode('utf-8','ignore')[:300]}\n")
        raise


def prev_archive():
    """Archivo histórico previo (stats compactas de bodas entregadas, ver server.py).
    KV es el estado persistente entre corridas de Actions: primero la clave propia
    'edicion:archive'; de respaldo, el 'archive' embebido en el data.json anterior."""
    for key, field in (("edicion:archive", None), ("edicion:data", "archive")):
        try:
            raw = kv_get(key)
        except Exception:
            continue
        if not raw:
            continue
        try:
            j = json.loads(raw)
            arc = j if field is None else j.get(field)
            if isinstance(arc, list):
                return arc
        except Exception:
            pass
    return []


def kv_delete(key):
    url = f"{BASE}/accounts/{ACCOUNT}/storage/kv/namespaces/{NS}/values/{key}"
    req = urllib.request.Request(url, method="DELETE", headers={"Authorization": f"Bearer {CF_TOKEN}"})
    with urllib.request.urlopen(req, timeout=30) as r:
        return r.status


def kv_keys(prefix):
    url = f"{BASE}/accounts/{ACCOUNT}/storage/kv/namespaces/{NS}/keys?prefix={prefix}&limit=1000"
    req = urllib.request.Request(url, headers={"Authorization": f"Bearer {CF_TOKEN}"})
    with urllib.request.urlopen(req, timeout=30) as r:
        return [k["name"] for k in json.loads(r.read().decode("utf-8")).get("result", [])]


def drain_pending():
    """Sesiones de sprint que la nube dejó en cola (KV edicion:pending:<id>) porque la
    Pages Function no tiene NOTION_TOKEN: se crean en Notion ANTES de extraer, así
    salen en este mismo publish. Si una falla, se queda en la cola para el siguiente."""
    try:
        keys = kv_keys("edicion:pending:")
    except Exception as e:
        sys.stderr.write(f"[cola] no se pudo listar: {e}\n")
        return
    for key in keys:
        try:
            item = json.loads(kv_get(key) or "null")
            if item is None:
                continue
            err = server.validate_session(item)
            if err:
                sys.stderr.write(f"[cola] {key} descartada: {err}\n")
            else:
                server.create_session(item)
                print("Sesión registrada desde la cola:", item.get("inicio"), "→", item.get("fin"))
            kv_delete(key)
        except Exception as e:
            sys.stderr.write(f"[cola] {key} falló (se reintenta luego): {e}\n")
    # cierres de escena/etapa (POST /api/close sin NOTION_TOKEN): después de las sesiones
    try:
        keys = kv_keys("edicion:pending-close:")
    except Exception as e:
        sys.stderr.write(f"[cola] no se pudo listar cierres: {e}\n")
        return
    for key in keys:
        try:
            item = json.loads(kv_get(key) or "null")
            if item is None:
                continue
            err = server.validate_close(item)
            if err:
                sys.stderr.write(f"[cola] {key} descartado: {err}\n")
            else:
                print("Cerrado desde la cola:", item.get("cerrar"), server.close_targets(item))
            kv_delete(key)
        except Exception as e:
            sys.stderr.write(f"[cola] {key} falló (se reintenta luego): {e}\n")


def main():
    drain_pending()
    data = server.build_data(prev_archive=prev_archive())
    # Si la consulta a Notion falló, build_data devuelve solo las 2 bodas de respaldo
    # con pinta de payload sano. Publicarlo borraría el tablero bueno de KV en silencio
    # (ya pasó con el 400 del Status renombrado). Mejor salir con error: el run se marca
    # fallido, llega el aviso, y la nube conserva los últimos datos correctos.
    if data.get("degraded"):
        sys.stderr.write(
            "ABORTADO: extracción degradada (respaldo de %d bodas, no el tablero real). "
            "No se toca KV; la nube conserva los últimos datos buenos.\n"
            % len(data.get("weddings", [])))
        sys.exit(1)
    summary = server.build_summary(data)
    kv_put("edicion:data", json.dumps(data, ensure_ascii=False))
    kv_put("edicion:summary", json.dumps(summary, ensure_ascii=False))
    kv_put("edicion:archive", json.dumps(data.get("archive", []), ensure_ascii=False))
    print("Publicado:", summary.get("today"),
          "| bodas:", len(data.get("weddings", [])),
          "| archivo:", len(data.get("archive", [])),
          "| horas hoy:", summary.get("todayMin"), "min")


if __name__ == "__main__":
    main()
