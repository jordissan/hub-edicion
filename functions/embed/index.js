// Pages Function: GET /embed?boda=<boda>&k=<clave>  → el MISMO index.html, en modo embebido.
// Es la URL que se pega con /embed en la página de la boda en Notion (una tarjeta sola: la dona
// "Horas y $ por etapa"). La página detecta /embed y solo pinta esa tarjeta, sin sprint.
//
// Esta ruta (y /embed/data y /fonts) va FUERA de Cloudflare Access: dentro del iframe de Notion
// el login de Access no funciona (cookie de terceros). La página en sí no trae datos reales
// (el código ya es público en GitHub); los pide a /embed/data, que exige la clave de la boda.
export async function onRequest({ request, env }) {
  const page = await env.ASSETS.fetch(new URL("/", request.url));
  const headers = new Headers(page.headers);
  headers.set("cache-control", "no-cache");      // siempre la versión publicada más reciente
  headers.set("x-robots-tag", "noindex");
  return new Response(page.body, { status: page.status, headers });
}
