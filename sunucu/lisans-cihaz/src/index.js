// Netice cihaz sınırı — Cloudflare Worker. "Bir öğretmen, bir lisans."
//
// Pro aboneliği aynı anda en fazla 1 telefon/tablet ve 1 bilgisayarda açık
// olur. Hesap yoktur: uygulama mağaza fişinin SHA-256 özetini (anahtar) ve
// isimsiz, rastgele cihaz kodunu gönderir.
//
//   POST /kayit  { anahtar, cihaz, tur: "telefon"|"bilgisayar", ad, devret? }
//     → { durum: "tamam", devirKalan } ya da
//       { durum: "dolu", diger: { ad, son }, devirKalan, sonrakiDevir? }
//   POST /birak  { anahtar, cihaz, tur } → { durum: "tamam" }
//
// "ad" yalnız cihazın türüdür (android, iphone, ipad, windows, mac); cihaz
// adı, e-posta, IP adresi ya da mağaza fişinin kendisi saklanmaz.

import { DurableObject } from "cloudflare:workers";
import { RequestError, claim, emptyState, parseRequest, release } from "./lib.js";

const APP_KEY = "netice-app-1";

const cors = {
  "access-control-allow-origin": "*",
  "access-control-allow-headers": "content-type, x-netice-app",
  "access-control-allow-methods": "GET, POST, OPTIONS",
};

const json = (data, status = 200) =>
  new Response(JSON.stringify(data), {
    status,
    headers: { "content-type": "application/json; charset=utf-8", "cache-control": "no-store", ...cors },
  });

const fail = (code, message, status) => json({ error: code, message }, status);

/** Her lisans için ayrı küçük nesne; durum tek kayıt olarak tutulur. */
export class Lisans extends DurableObject {
  async run(op, req, opts) {
    const state = (await this.ctx.storage.get("durum")) || emptyState();
    const out = op === "birak" ? release(state, req) : claim(state, req, Date.now(), opts);
    if (out.changed) await this.ctx.storage.put("durum", out.state);
    // Bir yıl hiç kullanılmayan lisansın kaydı kendiliğinden silinir.
    await this.ctx.storage.setAlarm(Date.now() + 400 * 86400000);
    return out.result;
  }

  async alarm() {
    await this.ctx.storage.deleteAll();
  }
}

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    if (request.method === "OPTIONS") return new Response(null, { status: 204, headers: cors });
    if (request.method === "GET" && url.pathname === "/") return json({ ok: true, service: "netice-lisans" });

    const op = url.pathname === "/kayit" ? "kayit" : url.pathname === "/birak" ? "birak" : null;
    if (request.method !== "POST" || !op) return fail("not_found", "Not found", 404);
    if (request.headers.get("x-netice-app") !== APP_KEY) return fail("forbidden", "Unknown client", 403);
    if (Number(request.headers.get("content-length") || 0) > 4096) return fail("too_large", "Too large", 413);

    let req;
    try {
      req = parseRequest(await request.json());
    } catch (e) {
      if (e instanceof RequestError) return fail(e.code, e.message, e.status);
      return fail("bad_request", "Invalid JSON", 400);
    }
    const stub = env.LISANS.get(env.LISANS.idFromName(req.anahtar));
    const result = await stub.run(op, req, {
      transferLimit: Number(env.TRANSFER_LIMIT) || 3,
      staleDays: Number(env.STALE_DAYS) || 45,
    });
    return json(result);
  },
};
