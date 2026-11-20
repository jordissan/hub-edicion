#!/usr/bin/env python3
"""Genera el atajo «Modo oscuro» del iPhone (archivo .shortcut firmado) — 12-nov-2026.

Un toque = ida y vuelta claro ↔ oscuro:
  Texto «alternar» → Scriptable «Run Script» (Dark Mode, parámetro = el texto)
  → Si el resultado es «oscuro»: Definir aspecto Oscuro · si no: Claro.
El script «Dark Mode» fija DARK_MODE en los widgets y devuelve el modo final, así el iPhone
y los widgets quedan siempre iguales. Las tarjetas de Notion en «Auto» siguen al iPhone solas.

Identificadores sacados de Cherri (compilador de Atajos): Scriptable usa intents SiriKit
(dk.simonbs.Scriptable.ParameterizedRunScriptIntent; script en «fileName», ShowWhenRun con
mayúscula, parámetro como variable). Aspecto = is.workflow.actions.appearance (operation/style).
Además «Widgets oscuro» y «Widgets claro» (para automatizaciones a la hora en que iOS cambia el aspecto):
fijan el modo de los widgets y los refrescan al momento, sin tocar el aspecto del iPhone.
«Tema widget» (18-nov-2026): lo abre el widget «Dark Mode» al tocarlo. Alterna el tema de los widgets,
los redibuja y regresa a la pantalla de inicio, para que Scriptable no se quede abierta.
Uso: python3 make-atajo.py → los .shortcut aquí y en la carpeta de Scriptable de iCloud.
     python3 make-atajo.py "Tema widget" → solo ese atajo.
"""
import os, plistlib, shutil, subprocess, sys, tempfile, uuid

HERE = os.path.dirname(os.path.abspath(__file__))
ICLOUD = os.path.expanduser("~/Library/Mobile Documents/iCloud~dk~simonbs~Scriptable/Documents")
NAME = "Modo oscuro"
ONLY = sys.argv[1] if len(sys.argv) > 1 else None

def U(): return str(uuid.uuid4()).upper()
def out(uid, name): return {"WFSerializationType": "WFTextTokenAttachment",
                            "Value": {"Type": "ActionOutput", "OutputUUID": uid, "OutputName": name}}
def act(ident, **p): return {"WFWorkflowActionIdentifier": ident, "WFWorkflowActionParameters": p}

def sign(name, actions):
    if ONLY and name != ONLY: return
    workflow = {
        "WFWorkflowClientVersion": "2607.0.4",
        "WFWorkflowMinimumClientVersion": 900,
        "WFWorkflowMinimumClientVersionString": "900",
        "WFWorkflowIcon": {"WFWorkflowIconStartColor": 255, "WFWorkflowIconGlyphNumber": 59511},
        "WFWorkflowTypes": [],
        "WFWorkflowInputContentItemClasses": [],
        "WFWorkflowImportQuestions": [],
        "WFWorkflowHasOutputFallback": False,
        "WFWorkflowActions": actions,
    }
    with tempfile.NamedTemporaryFile(suffix=".shortcut", delete=False) as f:
        plistlib.dump(workflow, f, fmt=plistlib.FMT_BINARY); raw = f.name
    dst = os.path.join(HERE, name + ".shortcut")
    subprocess.run(["shortcuts", "sign", "--mode", "anyone", "--input", raw, "--output", dst], check=True)
    os.unlink(raw); os.chmod(dst, 0o644)
    print("listo:", dst)
    if os.path.isdir(ICLOUD):
        shutil.copy2(dst, os.path.join(ICLOUD, name + ".shortcut"))
        print("  copiado a iCloud (Archivos → iCloud Drive → Scriptable)")

def run_dark_mode(param):
    """Texto <param> → Scriptable «Run Script» Dark Mode con ese parámetro. Devuelve (acciones, uuid del script)."""
    t_id, s_id = U(), U()
    return [act("is.workflow.actions.gettext", UUID=t_id, WFTextActionText=param),
            act("dk.simonbs.Scriptable.ParameterizedRunScriptIntent", UUID=s_id,
                fileName="Dark Mode", parameter=out(t_id, "Text"), runInApp=False, ShowWhenRun=False)], s_id

# 1) «Modo oscuro»: ida y vuelta manual (iPhone + widgets)
acts, s_id = run_dark_mode("alternar"); grp = U()
sign(NAME, acts + [
    act("is.workflow.actions.conditional", GroupingIdentifier=grp, WFControlFlowMode=0,
        WFCondition=4, WFConditionalActionString="oscuro",          # 4 = «es»
        WFInput={"Type": "Variable", "Variable": out(s_id, "Output")}),
    act("is.workflow.actions.appearance", operation="set", style="dark"),
    act("is.workflow.actions.conditional", GroupingIdentifier=grp, WFControlFlowMode=1),
    act("is.workflow.actions.appearance", operation="set", style="light"),
    act("is.workflow.actions.conditional", GroupingIdentifier=grp, WFControlFlowMode=2, UUID=U()),
])

# 2) «Widgets oscuro» / «Widgets claro»: para las automatizaciones de Atajos (12-nov). NO tocan el aspecto
#    del iPhone (ya lo cambia iOS a esa hora): solo fijan el modo de los widgets y piden a iOS redibujarlos
#    ya («Refresh All Widgets» de Scriptable = RefreshAllWidgetsIntent, sin parámetros).
for nm, mode in (("Widgets oscuro", "oscuro"), ("Widgets claro", "claro")):
    acts, _ = run_dark_mode(mode)
    sign(nm, acts + [act("dk.simonbs.Scriptable.RefreshAllWidgetsIntent")])

# 3) «Tema widget»: un toque en el widget «Dark Mode» → alterna, redibuja y vuelve al inicio (18-nov).
#    No toca el aspecto del iPhone.
acts, _ = run_dark_mode("alternar")
sign("Tema widget", acts + [act("dk.simonbs.Scriptable.RefreshAllWidgetsIntent"),
                            act("is.workflow.actions.returntohomescreen")])
