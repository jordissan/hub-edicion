// Pages Function: GET /embed/data?boda=<boda>&k=<clave>  → los datos de UNA boda, recortados de
// edicion:data (el mismo KV que lee el dashboard; no se guarda nada aparte por boda).
// boda=todo → el tablero entero, para las tarjetas generales (Horas por día, Intensidad, Tarifa).
//
// Va fuera de Cloudflare Access (ver functions/embed/index.js), así que se protege con la clave:
// k = HMAC-SHA256(EMBED_SECRET, "embed:" + boda), 20 caracteres hex. Cada boda tiene la suya: si
// un enlace se filtra, solo enseña esa boda. EMBED_SECRET es una variable secreta de Pages
// (Settings → Variables and Secrets); cambiarla invalida todos los enlaces.
// Los enlaces se sacan de /api/embed-link (ese sí detrás de Access).
const enc = new TextEncoder();

// igual que embedKey() en functions/api/embed-link.js
async function embedKey(secret, boda) {
  const key = await crypto.subtle.importKey("raw", enc.encode(secret), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  const sig = new Uint8Array(await crypto.subtle.sign("HMAC", key, enc.encode("embed:" + boda)));
  return [...sig.slice(0, 10)].map(b => b.toString(16).padStart(2, "0")).join("");
}
// igual que slug() de deriveModel (index.html): "Ale + Lorenzo" → "ale-lorenzo"
const slug = s => (s || "").trim().toLowerCase().normalize("NFD").replace(/[̀-ͯ]/g, "")
  .replace(/[^a-z0-9]+/g, "-").replace(/^-|-$/g, "");
function same(a, b) {                         // comparación sin atajos (no revela cuántos caracteres acertó)
  if (a.length !== b.length) return false;
  let d = 0; for (let i = 0; i < a.length; i++) d |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return d === 0;
}
const json = (status, body) => new Response(JSON.stringify(body), {
  status,
  headers: { "content-type": "application/json; charset=utf-8", "cache-control": "no-store", "x-robots-tag": "noindex" },
});

export async function onRequest({ request, env }) {
  const q = new URL(request.url).searchParams;
  const boda = (q.get("boda") || "").trim().toLowerCase(), k = (q.get("k") || "").trim().toLowerCase();
  if (!env.EMBED_SECRET) return json(503, { error: "Falta la variable secreta EMBED_SECRET en Pages." });
  if (!boda || !same(k, await embedKey(env.EMBED_SECRET, boda))) return json(403, { error: "Enlace no válido." });
  const raw = await env.HUB_KV.get("edicion:data");
  if (!raw) return json(503, { error: "Sin datos aún." });
  const P = JSON.parse(raw);
  if (boda === "todo") return json(200, { ...P, embed: true });
  // mismo recorte que embedSlice() en index.html
  const out = {
    generatedAt: P.generatedAt, today: P.today, live: P.live, degraded: P.degraded, embed: true,
    weddings: (P.weddings || []).filter(w => slug(w.name) === boda),
    archive: (P.archive || []).filter(a => slug(a.name) === boda),
  };
  if (!out.weddings.length && !out.archive.length) return json(404, { error: "No encuentro esa boda." });
  return json(200, out);
}
