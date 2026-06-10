# Hub de Edición — versión nube (Cloudflare Pages + GitHub Actions)

Migra el dashboard a la nube para verlo desde cualquier lugar, con la Mac apagada,
detrás de tu login de Google, y **100% gratis**.

## Arquitectura

```
GitHub Actions (cron 30 min + on-demand)
  publish.py  → server.py extrae Notion → escribe data.json + summary.json en Cloudflare KV
        │
Cloudflare Pages (siempre encendido)
  index.html              → el dashboard
  functions/api/edicion   → lee data.json de KV   (lo usa el dashboard)
  functions/api/summary   → lee summary.json de KV (lo usan los widgets)
  Cloudflare Access       → Google (sesión 1 mes) protege todo; widgets usan Service Token
        │
iPhone / cualquier lugar → https://<tu-proyecto>.pages.dev
```

## Archivos
- `server.py` — lógica de extracción de Notion (igual que el local).
- `publish.py` — corre en Actions: extrae y sube a KV.
- `functions/api/edicion.js`, `functions/api/summary.js` — leen de KV.
- `.github/workflows/publish.yml` — el cron + on-demand.
- `index.html`, `manifest.json`, `icon-*.png` — el sitio (estático).

---

## Pasos (checklist)

### 1. Cuentas
- [ ] Cuenta de GitHub (github.com) — gratis.
- [ ] Cuenta de Cloudflare (dash.cloudflare.com) — gratis.

### 2. Repo
- [ ] Crea un repo **público** llamado p.ej. `hub-edicion`.
- [ ] Sube el contenido de esta carpeta `cloud/` a la raíz del repo.

### 3. Cloudflare KV
- [ ] Cloudflare → Storage & Databases → KV → **Create namespace** → nombre `hub`.
- [ ] Anota el **Namespace ID**.

### 4. Cloudflare Pages
- [ ] Cloudflare → Workers & Pages → **Create** → Pages → **Connect to Git** → elige el repo.
- [ ] Build: framework **None**, build command vacío, output dir `/` (raíz). Deploy.
- [ ] Settings → Functions → **KV namespace bindings** → Variable `HUB_KV` → tu namespace `hub`.
- [ ] Re-deploy para aplicar el binding.

### 5. Token de Cloudflare (para que Actions escriba en KV)
- [ ] Cloudflare → My Profile → API Tokens → **Create Token** → plantilla *Edit Cloudflare Workers*
      (o permiso **Workers KV Storage: Edit**). Anota el token.
- [ ] Anota tu **Account ID** (está en el panel de la cuenta).

### 6. Secretos en GitHub
En el repo → Settings → Secrets and variables → Actions → **New repository secret**:
- [ ] `NOTION_TOKEN` = tu token de integración de Notion.
- [ ] `CF_API_TOKEN` = el token del paso 5.
- [ ] `CF_ACCOUNT_ID` = tu Account ID.
- [ ] `CF_KV_NAMESPACE_ID` = el Namespace ID del paso 3.

### 7. Primera publicación
- [ ] Repo → Actions → "Publicar dashboard" → **Run workflow**.
- [ ] Debe terminar en verde e imprimir "Publicado: …".

### 8. Cloudflare Access (login con Google)
- [ ] Cloudflare → **Zero Trust** → Settings → Authentication → Login methods → **Add Google**.
- [ ] Zero Trust → Access → Applications → **Add a self-hosted application**.
      - Dominio: tu `*.pages.dev`.
      - Session Duration: **1 month**.
      - Policy: Allow → Emails → tu correo de Google.
- [ ] Abre tu URL `*.pages.dev` → debe pedir Google una vez → ver el dashboard.

### 9. Service Token para los widgets
- [ ] Zero Trust → Access → Service Auth → **Create Service Token** → anota Client ID y Secret.
- [ ] En la Access Application del paso 8, añade una segunda policy:
      Allow → **Service Auth** → ese token (así el widget entra sin Google).
- [ ] Pega Client ID/Secret en los widgets (yo edito los scripts).

### 10. Widgets
- [ ] Cambiar `HOST` a `https://<tu-proyecto>.pages.dev` y añadir las cabeceras del token.
      (lo hago yo una vez tengas la URL y el token).

---

> Nota: GitHub pausa los crons si el repo no tiene actividad en 60 días. El refresco
> on-demand desde el teléfono o un commit ocasional lo mantienen activo.
