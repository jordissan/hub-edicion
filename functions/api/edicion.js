// Pages Function: GET /api/edicion  → devuelve el data.json desde Cloudflare KV.
// Lo consume el dashboard (index.html). El binding KV se llama HUB_KV
// (lo configuras en Pages → Settings → Functions → KV namespace bindings).
export async function onRequest({ env }) {
  const v = await env.HUB_KV.get("edicion:data");
  return new Response(v ?? '{"error":"Sin datos aún. Espera a que corra el extractor."}', {
    headers: {
      "content-type": "application/json; charset=utf-8",
      "cache-control": "no-store",
    },
  });
}
