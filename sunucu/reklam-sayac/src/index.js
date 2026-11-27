// Netice reklam sayacı — Cloudflare Worker.
//
// Uygulama, kendi tanıtımlarının günlük toplam görülme ve tıklanma sayısını
// POST /olay ile gönderir. Cihaz kimliği, IP adresi ya da kişisel bilgi
// alınmaz ve saklanmaz; yalnız (gün, reklam, A/B sürümü, tür, adet) toplamları
// tutulur. Özeti (GET /ozet) yalnız uygulama sahibinin GitHub yayın anahtarı
// okuyabilir.
//
// Ayrıca "Burada reklamınız olsun" kartındaki form, reklam vermek isteyen
// firmanın kendi yazdığı başvuruyu POST /basvuru ile bırakır (ad, firma,
// telefon/e-posta, mesaj). IP adresi saklanmaz. Başvuruları yalnız uygulama
// sahibi görür ve siler; 365 günden eskiler kendiliğinden silinir.

import { DurableObject } from "cloudflare:workers";
import {
  BASVURU_ID_RE,
  RequestError,
  dayString,
  newApplicationId,
  parseApplication,
  parseEvents,
  summarize,
} from "./lib.js";

const APP_KEY = "netice-app-1";

const cors = {
  "access-control-allow-origin": "*",
  "access-control-allow-headers": "content-type, authorization, x-netice-app",
  "access-control-allow-methods": "GET, POST, DELETE, OPTIONS",
};

const json = (data, status = 200) =>
  new Response(JSON.stringify(data), {
    status,
    headers: { "content-type": "application/json; charset=utf-8", "cache-control": "no-store", ...cors },
  });

const fail = (code, message, status) => json({ error: code, message }, status);

/** Sayaçların tutulduğu tek nesne (SQLite). */
export class Sayac extends DurableObject {
  constructor(ctx, env) {
    super(ctx, env);
    this.sql = ctx.storage.sql;
    this.sql.exec(`CREATE TABLE IF NOT EXISTS olay (
      gun TEXT NOT NULL, reklam TEXT NOT NULL, surum TEXT NOT NULL, tur TEXT NOT NULL, n INTEGER NOT NULL,
      PRIMARY KEY (gun, reklam, surum, tur))`);
    this.sql.exec(`CREATE TABLE IF NOT EXISTS basvuru (
      id TEXT PRIMARY KEY, zaman TEXT NOT NULL, ad TEXT NOT NULL, firma TEXT NOT NULL, telefon TEXT NOT NULL,
      eposta TEXT NOT NULL, mesaj TEXT NOT NULL, alan TEXT NOT NULL, dil TEXT NOT NULL, ulke TEXT NOT NULL)`);
  }

  basvuruEkle(b, limit) {
    const today = dayString(new Date());
    const row = this.sql.exec("SELECT COUNT(*) AS c FROM basvuru WHERE substr(zaman, 1, 10) = ?", today).one();
    if (row.c >= limit) return null;
    const id = newApplicationId();
    this.sql.exec(
      "INSERT INTO basvuru (id, zaman, ad, firma, telefon, eposta, mesaj, alan, dil, ulke) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
      id, new Date().toISOString(), b.ad, b.firma, b.telefon, b.eposta, b.mesaj, b.alan, b.dil, b.ulke,
    );
    this.sql.exec("DELETE FROM basvuru WHERE zaman < ?", new Date(Date.now() - 365 * 86400000).toISOString());
    return id;
  }

  basvurular() {
    return this.sql.exec("SELECT * FROM basvuru ORDER BY zaman DESC LIMIT 500").toArray();
  }

  basvuruSil(id) {
    this.sql.exec("DELETE FROM basvuru WHERE id = ?", id);
    return true;
  }

  ekle(items, limit) {
    const today = dayString(new Date());
    const row = this.sql.exec("SELECT COALESCE(SUM(n), 0) AS s FROM olay WHERE gun = ?", today).one();
    if (row.s >= limit) return 0;
    for (const e of items) {
      this.sql.exec(
        `INSERT INTO olay (gun, reklam, surum, tur, n) VALUES (?, ?, ?, ?, ?)
         ON CONFLICT (gun, reklam, surum, tur) DO UPDATE SET n = n + excluded.n`,
        e.gun, e.reklam, e.surum, e.tur, e.n,
      );
    }
    // 400 günden eski kayıtlar silinir.
    this.sql.exec("DELETE FROM olay WHERE gun < ?", dayString(new Date(Date.now() - 400 * 86400000)));
    return items.length;
  }

  ozet(days) {
    const from = dayString(new Date(Date.now() - (days - 1) * 86400000));
    return summarize(this.sql.exec("SELECT gun, reklam, surum, tur, n FROM olay WHERE gun >= ?", from).toArray());
  }
}

// Doğrulanmış anahtarlar (özet) birkaç dakika hatırlanır.
const verified = new Map();

async function sha256(s) {
  const buf = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(s));
  return [...new Uint8Array(buf)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

/** Anahtar, uygulama sahibinin GitHub hesabına mı ait? */
async function isOwner(token, env) {
  if (!/^[A-Za-z0-9_]{20,255}$/.test(token)) return false;
  const h = await sha256(token);
  const hit = verified.get(h);
  if (hit && hit > Date.now()) return true;
  const r = await fetch("https://api.github.com/user", {
    headers: { authorization: `Bearer ${token}`, "user-agent": "netice-reklam-sayac", accept: "application/vnd.github+json" },
  });
  if (!r.ok) return false;
  const u = await r.json();
  const ok = String(u.login || "").toLowerCase() === String(env.OWNER || "emrgngr").toLowerCase();
  if (ok) verified.set(h, Date.now() + 10 * 60 * 1000);
  return ok;
}

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    if (request.method === "OPTIONS") return new Response(null, { status: 204, headers: cors });
    if (request.method === "GET" && url.pathname === "/") return json({ ok: true, service: "netice-reklam-sayac" });
    const stub = env.SAYAC.get(env.SAYAC.idFromName("sayac"));

    if (request.method === "POST" && url.pathname === "/olay") {
      if (request.headers.get("x-netice-app") !== APP_KEY) return fail("forbidden", "Unknown client", 403);
      if (Number(request.headers.get("content-length") || 0) > 32768) return fail("too_large", "Too large", 413);
      let items;
      try {
        items = parseEvents(await request.json());
      } catch (e) {
        if (e instanceof RequestError) return fail(e.code, e.message, e.status);
        return fail("bad_request", "Invalid JSON", 400);
      }
      const saved = items.length ? await stub.ekle(items, Number(env.DAILY_LIMIT) || 2000000) : 0;
      return json({ ok: true, kayit: saved });
    }

    if (request.method === "GET" && url.pathname === "/ozet") {
      const token = (request.headers.get("authorization") || "").replace(/^Bearer\s+/i, "").trim();
      if (!(await isOwner(token, env))) return fail("forbidden", "Owner key required", 403);
      const days = Math.max(1, Math.min(400, Math.floor(Number(url.searchParams.get("gun")) || 30)));
      return json({ gun: days, reklamlar: await stub.ozet(days) });
    }
    if (request.method === "POST" && url.pathname === "/basvuru") {
      if (request.headers.get("x-netice-app") !== APP_KEY) return fail("forbidden", "Unknown client", 403);
      if (Number(request.headers.get("content-length") || 0) > 8192) return fail("too_large", "Too large", 413);
      let b;
      try {
        b = parseApplication(await request.json());
      } catch (e) {
        if (e instanceof RequestError) return fail(e.code, e.message, e.status);
        return fail("bad_request", "Invalid JSON", 400);
      }
      const id = await stub.basvuruEkle(b, Number(env.APPLICATION_LIMIT) || 200);
      if (!id) return fail("limit", "Daily limit reached", 429);
      return json({ ok: true, id });
    }

    if (url.pathname === "/basvurular" || url.pathname.startsWith("/basvuru/")) {
      const token = (request.headers.get("authorization") || "").replace(/^Bearer\s+/i, "").trim();
      if (!(await isOwner(token, env))) return fail("forbidden", "Owner key required", 403);
      if (request.method === "GET" && url.pathname === "/basvurular") {
        return json({ basvurular: await stub.basvurular() });
      }
      const id = url.pathname.slice("/basvuru/".length);
      if (request.method === "DELETE" && BASVURU_ID_RE.test(id)) {
        await stub.basvuruSil(id);
        return json({ ok: true });
      }
    }
    return fail("not_found", "Not found", 404);
  },
};
