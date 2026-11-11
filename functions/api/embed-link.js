// Pages Function: GET /api/embed-link  → los enlaces para pegar en Notion, uno por boda.
//   /api/embed-link              → lista de todas las bodas (tablero + archivo) con su enlace
//   /api/embed-link?boda=<boda>  → solo esa
// Detrás de Cloudflare Access (como todo /api): solo Jordi puede sacar enlaces. Los enlaces
// apuntan a /embed, que sí va fuera de Access y valida la clave (ver functions/embed/data.js).
const enc = new TextEncoder();

// igual que embedKey() en functions/embed/data.js
async function embedKey(secret, boda) {
  const key = await crypto.subtle.importKey("raw", enc.encode(secret), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  const sig = new Uint8Array(await crypto.subtle.sign("HMAC", key, enc.encode("embed:" + boda)));
  return [...sig.slice(0, 10)].map(b => b.toString(16).padStart(2, "0")).join("");
}
const slug = s => (s || "").trim().toLowerCase().normalize("NFD").replace(/[̀-ͯ]/g, "")
  .replace(/[^a-z0-9]+/g, "-").replace(/^-|-$/g, "");
const json = (status, body) => new Response(JSON.stringify(body, null, 2), {
  status, headers: { "content-type": "application/json; charset=utf-8", "cache-control": "no-store" },
});

export async function onRequest({ request, env }) {
  if (!env.EMBED_SECRET) return json(503, { error: "Falta la variable secreta EMBED_SECRET en Pages." });
  const url = new URL(request.url), want = (url.searchParams.get("boda") || "").trim().toLowerCase();
  const raw = await env.HUB_KV.get("edicion:data");
  if (!raw) return json(503, { error: "Sin datos aún." });
  const P = JSON.parse(raw), seen = new Set(), out = [];
  for (const w of [...(P.weddings || []), ...(P.archive || [])]) {
    const b = slug(w.name); if (!b || seen.has(b) || (want && b !== want)) continue; seen.add(b);
    out.push({ boda: w.name, url: `${url.origin}/embed?boda=${b}&k=${await embedKey(env.EMBED_SECRET, b)}` });
  }
  if (want && !out.length) return json(404, { error: "No encuentro esa boda." });
  return json(200, want ? out[0] : out);
}
