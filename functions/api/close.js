// Pages Function: POST /api/close → al terminar un sprint, cierra su escena (y su etapa)
// en Notion: Estado → 🟢 y su fecha de fin (escena "Fin" con hora · etapa final de "Del → Al").
// Mismo criterio que server.set_done / server.close_targets.
//
// - Con NOTION_TOKEN escribe directo en Notion.
// - Sin él (o si Notion falla) lo deja en cola en KV (edicion:pending-close:<id>) y el
//   publicador de GitHub Actions lo aplica en su siguiente corrida (≤30 min).
// Solo acepta etapas/escenas del tablero publicado (edicion:data).

const NOTION = "https://api.notion.com/v1";
const json = (o, status = 200) =>
  new Response(JSON.stringify(o), { status, headers: { "content-type": "application/json; charset=utf-8", "cache-control": "no-store" } });
const norm = s => (s || "").normalize("NFD").replace(/[\u0300-\u036f]/g, "").toLowerCase().trim();
const estadoOf = s => { if (!s) return "wait"; const t = s.toLowerCase();
  if (s.includes("🟢") || /complet|hecho/.test(t)) return "done";
  if (s.includes("🔵") || /progreso|curso/.test(t)) return "live"; return "wait"; };

function validate(it) {
  if (!it || typeof it !== "object" || !it.db || !it.id) return "Faltan datos del cierre";
  if (!["escena", "etapa"].includes(it.cerrar)) return "Cierre inválido";
  if (!Date.parse(it.fin) || !/([+-]\d\d:\d\d|Z)$/.test(it.fin || "")) return "Fin inválido";
  if (it.cerrar === "escena" && !it.escena) return "Falta la escena";
  if (it.cerrar === "etapa" && !it.stageId) return "Falta la etapa";
  return null;
}

async function notion(token, method, path, body) {
  const r = await fetch(NOTION + path, {
    method,
    headers: { Authorization: `Bearer ${token}`, "Notion-Version": "2022-06-28", "Content-Type": "application/json" },
    body: body ? JSON.stringify(body) : undefined,
  });
  const j = await r.json();
  if (!r.ok) throw new Error(`Notion ${r.status}: ${(j.message || "").slice(0, 200)}`);
  return j;
}

async function setDone(token, pageId, finIso, kind) {
  const page = await notion(token, "GET", `/pages/${pageId}`);
  const props = page.properties || {}, upd = {};
  let moved = false;
  const est = ["Estado (Select)", "Estado"].find(n => props[n] && ["select", "status"].includes(props[n].type));
  if (est) {
    const t = props[est].type, cur = (props[est][t] || {}).name;
    if (estadoOf(cur) !== "done" && page.parent && page.parent.database_id) {
      const db = await notion(token, "GET", `/databases/${page.parent.database_id}`);
      const opts = ((db.properties[est] || {})[t] || {}).options || [];
      const green = opts.find(o => estadoOf(o.name) === "done");
      if (green) { upd[est] = { [t]: { name: green.name } }; moved = true; }
    }
  }
  for (const [name, v] of Object.entries(props)) {
    if (v.type !== "date") continue;
    const d = v.date || {};
    if (kind === "etapa") {
      if (!d.end) upd[name] = { date: { start: d.start || finIso.slice(0, 10), end: finIso.slice(0, 10) } };
      break;
    }
    if (norm(name) === "fin") { if (!d.start) upd[name] = { date: { start: finIso } }; break; }
  }
  if (Object.keys(upd).length) await notion(token, "PATCH", `/pages/${pageId}`, { properties: upd });
  return moved;
}

export async function onRequestPost({ request, env }) {
  let it;
  try { it = await request.json(); } catch { return json({ ok: false, error: "JSON inválido" }, 400); }
  const err = validate(it);
  if (err) return json({ ok: false, error: err }, 400);

  const doneKey = `edicion:closed:${it.id}`;
  const prev = await env.HUB_KV.get(doneKey);
  if (prev) return json(JSON.parse(prev));

  let data = {};
  try { data = JSON.parse((await env.HUB_KV.get("edicion:data")) || "{}"); } catch {}
  let target = null;
  for (const w of data.weddings || []) for (const s of w.stages || [])
    if (s.sessionDb === it.db) target = { stage: s.id, scenes: new Set((s.scenes || []).map(x => x.id).filter(Boolean)) };
  if (!target) return json({ ok: false, error: "Etapa desconocida" }, 400);
  if (it.stageId && target.stage && it.stageId !== target.stage) return json({ ok: false, error: "La etapa no corresponde a esa DB de Sesiones" }, 400);
  if (it.escena && !target.scenes.has(it.escena)) return json({ ok: false, error: "La escena no es de esa etapa" }, 400);

  if (env.NOTION_TOKEN) {
    try {
      const closed = [];
      const order = [["escena", it.escena]];
      if (it.cerrar === "etapa") order.push(["etapa", it.stageId]);
      for (const [kind, id] of order) if (id && await setDone(env.NOTION_TOKEN, id, it.fin, kind)) closed.push(kind);
      const out = { ok: true, closed };
      await env.HUB_KV.put(doneKey, JSON.stringify(out), { expirationTtl: 86400 });
      return json(out);
    } catch (e) { /* Notion falló: cae a la cola */ }
  }
  await env.HUB_KV.put(`edicion:pending-close:${it.id}`, JSON.stringify(it));
  const out = { ok: true, queued: true };
  await env.HUB_KV.put(doneKey, JSON.stringify(out), { expirationTtl: 86400 });
  return json(out);
}
