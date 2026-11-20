#!/usr/bin/env python3
"""Genera los Atajos de Siri del sprint (archivos .shortcut firmados) en esta carpeta.
Cada uno tiene dos acciones: URL → Abrir URL hubsprint://… (lo atiende la app Sprint flotante).
Uso: python3 make-shortcuts.py  →  luego doble clic en cada .shortcut y "Añadir atajo"."""
import os, plistlib, subprocess, tempfile, uuid

HERE = os.path.dirname(os.path.abspath(__file__))
SHORTCUTS = {
    "Iniciamos": "hubsprint://start",
    "Terminamos": "hubsprint://finish",
}

def workflow(url):
    uid = str(uuid.uuid4()).upper()
    return {
        "WFWorkflowClientVersion": "2607.0.4",
        "WFWorkflowMinimumClientVersion": 900,
        "WFWorkflowMinimumClientVersionString": "900",
        "WFWorkflowIcon": {"WFWorkflowIconStartColor": 4292093695, "WFWorkflowIconGlyphNumber": 59511},
        "WFWorkflowTypes": [],
        "WFWorkflowInputContentItemClasses": [],
        "WFWorkflowImportQuestions": [],
        "WFWorkflowHasOutputFallback": False,
        "WFWorkflowActions": [
            {"WFWorkflowActionIdentifier": "is.workflow.actions.url",
             "WFWorkflowActionParameters": {"UUID": uid, "WFURLActionURL": url}},
            {"WFWorkflowActionIdentifier": "is.workflow.actions.openurl",
             "WFWorkflowActionParameters": {"WFInput": {
                 "WFSerializationType": "WFTextTokenAttachment",
                 "Value": {"Type": "ActionOutput", "OutputUUID": uid, "OutputName": "URL"}}}},
        ],
    }

for name, url in SHORTCUTS.items():
    with tempfile.NamedTemporaryFile(suffix=".shortcut", delete=False) as f:
        plistlib.dump(workflow(url), f, fmt=plistlib.FMT_BINARY)
        raw = f.name
    out = os.path.join(HERE, name + ".shortcut")
    subprocess.run(["shortcuts", "sign", "--mode", "anyone", "--input", raw, "--output", out], check=True)
    os.unlink(raw)
    print("listo:", out)
