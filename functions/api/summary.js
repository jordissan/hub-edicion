// Pages Function: GET /api/summary  → devuelve el summary.json desde Cloudflare KV.
// Lo consumen los widgets (iPhone Scriptable / Mac SwiftBar). Como está detrás de
// Cloudflare Access, los widgets se autentican con un Service Token (cabeceras
// CF-Access-Client-Id / CF-Access-Client-Secret) — el navegador usa Google.
export async function onRequest({ env }) {
  const v = await env.HUB_KV.get("edicion:summary");
  return new Response(v ?? '{"error":"Sin datos aún."}', {
    headers: {
      "content-type": "application/json; charset=utf-8",
      "cache-control": "no-store",
    },
  });
}
