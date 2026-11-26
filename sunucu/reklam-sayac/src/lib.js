// Saf yardımcılar (testlerde Node ile çalışır).

export const ID_RE = /^[A-Za-z0-9_-]{1,40}$/;
export const MAX_ITEMS = 200;
export const MAX_COUNT = 1000;

export class RequestError extends Error {
  constructor(code, message, status = 400) {
    super(message);
    this.code = code;
    this.status = status;
  }
}

/** YYYY-MM-DD (UTC). */
export function dayString(date) {
  return date.toISOString().slice(0, 10);
}

/**
 * Uygulamadan gelen olay listesini doğrular ve birleştirir.
 * Biçim: {"olaylar":[{"gun":"2026-11-26","reklam":"r1","surum":"a","tur":"g","n":3}]}
 * surum: a | b (A/B testi), tur: g (görülme) | t (tıklama).
 * Gün, bugünden en çok 3 gün önce ya da 1 gün sonra olabilir (saat farkı).
 */
export function parseEvents(body, now = new Date()) {
  const list = body && Array.isArray(body.olaylar) ? body.olaylar : null;
  if (!list) throw new RequestError("bad_request", "olaylar missing");
  if (list.length === 0) return [];
  if (list.length > MAX_ITEMS) throw new RequestError("too_many", "Too many items");
  const allowed = new Set();
  for (let d = -3; d <= 1; d++) allowed.add(dayString(new Date(now.getTime() + d * 86400000)));
  const merged = new Map();
  for (const e of list) {
    if (!e || typeof e !== "object") continue;
    const gun = String(e.gun ?? "");
    const reklam = String(e.reklam ?? "");
    const surum = e.surum === "b" ? "b" : "a";
    const tur = e.tur === "t" ? "t" : e.tur === "g" ? "g" : null;
    const n = Math.floor(Number(e.n));
    if (!allowed.has(gun) || !ID_RE.test(reklam) || !tur || !(n >= 1)) continue;
    const key = `${gun}|${reklam}|${surum}|${tur}`;
    merged.set(key, Math.min(MAX_COUNT, (merged.get(key) || 0) + Math.min(n, MAX_COUNT)));
  }
  return [...merged.entries()].map(([k, n]) => {
    const [gun, reklam, surum, tur] = k.split("|");
    return { gun, reklam, surum, tur, n };
  });
}

/** Veritabanı satırlarını reklam başına özet hâline getirir. */
export function summarize(rows) {
  const out = {};
  for (const r of rows) {
    const ad = (out[r.reklam] ??= { a: { g: 0, t: 0 }, b: { g: 0, t: 0 }, gunluk: {} });
    const v = r.surum === "b" ? "b" : "a";
    const k = r.tur === "t" ? "t" : "g";
    ad[v][k] += r.n;
    const day = (ad.gunluk[r.gun] ??= { g: 0, t: 0 });
    day[k] += r.n;
  }
  return out;
}
