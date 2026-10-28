// Pages Function: POST /api/session → registra un sprint de enfoque como sesión en Notion.
// Igual que el registro manual: fila en la DB "Sesiones" de la etapa con título "Sesión",
// Inicio, Fin, Tipo, Escena y Total (fila de "Tiempo total" de su Tipo).
//
// - Con la variable secreta NOTION_TOKEN (Pages → Settings → Variables and Secrets) escribe
//   directo en Notion.
// - Sin ella (o si Notion falla) la deja en cola en KV (edicion:pending:<id>) y el publicador
//   de GitHub Actions la crea en su siguiente corrida (≤30 min). Nunca se pierde.
// Solo acepta DBs de Sesiones de etapas del tablero publicado (edicion:data).

const NOTION = "https://api.notion.com/v1";
const json = (o, status = 200) =>
  new Response(JSON.stringify(o), { status, headers: { "content-type": "application/json; charset=utf-8", "cache-control": "no-store" } });
const norm = s => (s || "").normalize("NFD").replace(/[\u0300-\u036f]/g, "").toLowerCase().trim();

function validate(it) {
  if (!it || typeof it !== "object" || !it.db || !it.id) return "Faltan datos de la sesión";
  const a = Date.parse(it.inicio), b = Date.parse(it.fin);
  const tz = /([+-]\d\d:\d\d|Z)$/;
  if (!a || !b || !tz.test(it.inicio || "") || !tz.test(it.fin || "")) return "Inicio/Fin inválidos";
  const mins = (b - a) / 60000;
  if (mins < 1) return "Sesión de menos de 1 minuto";
  if (mins > 8 * 60) return "Sesión de más de 8 horas";
  if (it.tipo && !["Edición", "Gestión"].includes(it.tipo)) return "Tipo inválido";
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

// ⚪️ / vacío → 🔵 (nunca retrocede) + fecha de inicio si está vacía — mismo criterio que server.set_in_progress
const estadoOf = s => { if (!s) return "wait"; const t = s.toLowerCase();
  if (s.includes("🟢") || /complet|hecho/.test(t)) return "done";
  if (s.includes("🔵") || /progreso|curso/.test(t)) return "live"; return "wait"; };
async function setInProgress(token, pageId, startIso, kind) {
  const page = await notion(token, "GET", `/pages/${pageId}`);
  const props = page.properties || {}, upd = {};
  let moved = false;
  const est = ["Estado (Select)", "Estado"].find(n => props[n] && ["select", "status"].includes(props[n].type));
  if (est) {
    const t = props[est].type, cur = (props[est][t] || {}).name;
    if (estadoOf(cur) === "wait" && page.parent && page.parent.database_id) {
      const db = await notion(token, "GET", `/databases/${page.parent.database_id}`);
      const opts = ((db.properties[est] || {})[t] || {}).options || [];
      const blue = opts.find(o => estadoOf(o.name) === "live");
      if (blue) { upd[est] = { [t]: { name: blue.name } }; moved = true; }
    }
  }
  for (const [name, v] of Object.entries(props)) {
    if (v.type !== "date" || v.date) continue;
    if (kind === "etapa") { upd[name] = { date: { start: startIso.slice(0, 10) } }; break; }
    if (norm(name) === "inicio") { upd[name] = { date: { start: startIso } }; break; }
  }
  if (Object.keys(upd).length) await notion(token, "PATCH", `/pages/${pageId}`, { properties: upd });
  return moved;
}

// mismo criterio que server.create_session
async function createSession(token, it) {
  const tipo = it.tipo || "Edición";
  const schema = (await notion(token, "GET", `/databases/${it.db}`)).properties || {};
  // salvaguarda: "Tiempo total" también titula su columna "Sesión"; solo Sesiones tiene Inicio y Fin
  const dates = new Set(Object.entries(schema).filter(([, p]) => p.type === "date").map(([k]) => norm(k)));
  if (!dates.has("inicio") || !dates.has("fin")) throw new Error("Esa DB no es un registro de Sesiones");
  const props = {};
  for (const [name, p] of Object.entries(schema)) {
    const t = p.type, n = norm(name);
    if (t === "title") props[name] = { title: [{ text: { content: "Sesión" } }] };
    else if (t === "date" && n === "inicio") props[name] = { date: { start: it.inicio } };
    else if (t === "date" && n === "fin") props[name] = { date: { start: it.fin } };
    else if (t === "select" && n === "tipo") {
      if ((p.select.options || []).some(o => o.name === tipo)) props[name] = { select: { name: tipo } };
    } else if (t === "number" && n === "ronda" && it.ronda != null) props[name] = { number: it.ronda };
    else if (t === "relation" && n.startsWith("escena") && it.escena) props[name] = { relation: [{ id: it.escena }] };
    else if (t === "relation" && n === "total" && p.relation.database_id) {
      const q = await notion(token, "POST", `/databases/${p.relation.database_id}/query`, {});
      const row = (q.results || []).find(r => {
        const tp = Object.values(r.properties || {}).find(v => v.type === "title");
        return tp && norm(tp.title.map(x => x.plain_text).join("")) === norm(tipo);
      });
      if (row) props[name] = { relation: [{ id: row.id }] };
    }
  }
  const page = await notion(token, "POST", "/pages", { parent: { database_id: it.db }, properties: props });
  const moved = [];
  for (const [kind, id] of [["etapa", it.stageId], ["escena", it.escena]]) {
    if (!id) continue;
    try { if (await setInProgress(token, id, it.inicio, kind)) moved.push(kind); } catch (e) { /* la sesión ya quedó */ }
  }
  return { url: page.url, moved };
}

export async function onRequestPost({ request, env }) {
  let it;
  try { it = await request.json(); } catch { return json({ ok: false, error: "JSON inválido" }, 400); }
  const err = validate(it);
  if (err) return json({ ok: false, error: err }, 400);

  // ¿ya registrada? (el navegador puede reintentar)
  const doneKey = `edicion:done:${it.id}`;
  const prev = await env.HUB_KV.get(doneKey);
  if (prev) return json(JSON.parse(prev));

  // solo DBs de Sesiones de etapas del tablero publicado
  let data = {};
  try { data = JSON.parse((await env.HUB_KV.get("edicion:data")) || "{}"); } catch {}
  // lista blanca: DB de Sesiones → su etapa y sus escenas (igual que server.target_error)
  let target = null;
  for (const w of data.weddings || []) for (const s of w.stages || [])
    if (s.sessionDb === it.db) target = { stage: s.id, scenes: new Set((s.scenes || []).map(x => x.id).filter(Boolean)) };
  if (!target) return json({ ok: false, error: "Etapa desconocida" }, 400);
  if (it.stageId && target.stage && it.stageId !== target.stage) return json({ ok: false, error: "La etapa no corresponde a esa DB de Sesiones" }, 400);
  if (it.escena && !target.scenes.has(it.escena)) return json({ ok: false, error: "La escena no es de esa etapa" }, 400);

  if (env.NOTION_TOKEN) {
    try {
      const r = await createSession(env.NOTION_TOKEN, it);
      const out = { ok: true, url: r.url, moved: r.moved };
      await env.HUB_KV.put(doneKey, JSON.stringify(out), { expirationTtl: 86400 });
      return json(out);
    } catch (e) { /* Notion falló: cae a la cola, no se pierde */ }
  }
  await env.HUB_KV.put(`edicion:pending:${it.id}`, JSON.stringify(it));
  const out = { ok: true, queued: true };
  await env.HUB_KV.put(doneKey, JSON.stringify(out), { expirationTtl: 86400 });
  return json(out);
}
