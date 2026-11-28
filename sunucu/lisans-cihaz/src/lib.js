// Netice cihaz sınırı: saf kurallar (Cloudflare'a bağlı değil, test edilir).
//
// Bir lisansın (mağaza fişinin özeti) iki yeri vardır: "telefon" (telefon ya
// da tablet) ve "bilgisayar". Her yerde aynı anda tek cihaz bulunur.
//
// Durum: { telefon?: Yer, bilgisayar?: Yer, devirler: [ms, ...] }
// Yer:   { cihaz: string, ad: string, son: ms }

export const KINDS = ["telefon", "bilgisayar"];
export const LABELS = ["android", "iphone", "ipad", "windows", "mac", "diger"];
export const KEY_RE = /^[a-f0-9]{64}$/;
export const DEVICE_RE = /^[A-Za-z0-9-]{8,64}$/;

const DAY = 86400000;
// Cihaz her açılışta bildirir; "son görülme" en çok saatte bir yazılır.
const TOUCH_EVERY = 3600000;

export class RequestError extends Error {
  constructor(code, message, status = 400) {
    super(message);
    this.code = code;
    this.status = status;
  }
}

/** İstek gövdesini doğrular. Fazladan alanlar yok sayılır. */
export function parseRequest(body) {
  if (!body || typeof body !== "object") throw new RequestError("bad_request", "Invalid body");
  const anahtar = String(body.anahtar || "");
  const cihaz = String(body.cihaz || "");
  const tur = String(body.tur || "");
  let ad = String(body.ad || "diger");
  if (!KEY_RE.test(anahtar)) throw new RequestError("bad_key", "License key missing");
  if (!DEVICE_RE.test(cihaz)) throw new RequestError("bad_device", "Device id missing");
  if (!KINDS.includes(tur)) throw new RequestError("bad_kind", "Unknown device kind");
  if (!LABELS.includes(ad)) ad = "diger";
  return { anahtar, cihaz, tur, ad, devret: body.devret === true };
}

export function emptyState() {
  return { devirler: [] };
}

function recentTransfers(state, now) {
  return (state.devirler || []).filter((t) => now - t < 30 * DAY);
}

/**
 * Cihaz bu lisansı kullanmak istiyor. Yer boşsa, bu cihazınsa ya da öbür
 * cihaz [staleDays] gündür görülmediyse alınır. Doluysa [devret] ile öbür
 * cihaz çıkarılır (30 günde [transferLimit] kez).
 *
 * Döner: { state, changed, result }
 *   result.durum: "tamam" | "dolu"
 */
export function claim(state, req, now, { transferLimit = 3, staleDays = 45 } = {}) {
  const s = { ...emptyState(), ...state };
  s.devirler = recentTransfers(s, now);
  const slot = s[req.tur];
  const left = Math.max(0, transferLimit - s.devirler.length);
  const mine = slot && slot.cihaz === req.cihaz;
  const free = !slot || now - slot.son > staleDays * DAY;

  if (mine || free) {
    const changed = !mine || now - slot.son >= TOUCH_EVERY || slot.ad !== req.ad || s.devirler.length !== (state.devirler || []).length;
    s[req.tur] = { cihaz: req.cihaz, ad: req.ad, son: mine && !changed ? slot.son : now };
    return { state: s, changed, result: { durum: "tamam", devirKalan: left } };
  }

  const other = { ad: slot.ad, son: new Date(slot.son).toISOString() };
  if (req.devret && left > 0) {
    s[req.tur] = { cihaz: req.cihaz, ad: req.ad, son: now };
    s.devirler = [...s.devirler, now];
    return { state: s, changed: true, result: { durum: "tamam", devredildi: true, onceki: other, devirKalan: left - 1 } };
  }
  const sonraki = s.devirler.length ? new Date(Math.min(...s.devirler) + 30 * DAY).toISOString() : null;
  return {
    state: s,
    changed: s.devirler.length !== (state.devirler || []).length,
    result: { durum: "dolu", diger: other, devirKalan: left, ...(left === 0 && sonraki ? { sonrakiDevir: sonraki } : {}) },
  };
}

/** Cihaz lisansı bırakır ("Bu cihazdan çıkış"). Yalnız kendi yerini boşaltabilir. */
export function release(state, req) {
  const s = { ...emptyState(), ...state };
  const slot = s[req.tur];
  if (!slot || slot.cihaz !== req.cihaz) return { state: s, changed: false, result: { durum: "tamam" } };
  delete s[req.tur];
  return { state: s, changed: true, result: { durum: "tamam" } };
}
