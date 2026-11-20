// Pages middleware para todo /api/* (20-nov-2026).
// Cada deploy de Pages tiene además su propia URL de vista previa (<hash>.hub-edicion.pages.dev) que
// NO pasa por Cloudflare Access, y esas URLs salen publicadas en el check «Cloudflare Pages» de cada
// commit en GitHub (repo público). Sin este filtro, /api/edicion, /api/summary y /api/embed-link
// servían los datos reales ahí sin login, y /api/session y /api/close aceptaban escrituras.
// Regla: /api solo responde en el dominio de producción (que sí está tras Access). Lo demás → 404.
// /embed no pasa por aquí: es público a propósito y sus datos exigen la clave k.
const PRODUCCION = new Set(["hub-edicion.pages.dev"]);
const LOCAL = /^(localhost|127\.0\.0\.1|\[::1\])(:\d+)?$/;   // `wrangler pages dev` para probar

export async function onRequest({ request, next }) {
  const host = new URL(request.url).host.toLowerCase();
  if (PRODUCCION.has(host) || LOCAL.test(host)) return next();
  return new Response('{"error":"No encontrado."}', {
    status: 404,
    headers: { "content-type": "application/json; charset=utf-8", "cache-control": "no-store" },
  });
}
