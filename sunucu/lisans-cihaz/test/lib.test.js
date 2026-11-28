import { test } from "node:test";
import assert from "node:assert/strict";
import { RequestError, claim, emptyState, parseRequest, release } from "../src/lib.js";

const KEY = "a".repeat(64);
const DAY = 86400000;
const t0 = Date.parse("2026-11-28T12:00:00Z");
const req = (cihaz, tur = "telefon", extra = {}) => ({ anahtar: KEY, cihaz, tur, ad: "android", devret: false, ...extra });

test("istek doğrulanır, bilinmeyen ad 'diger' olur", () => {
  const r = parseRequest({ anahtar: KEY, cihaz: "abcd1234efgh", tur: "bilgisayar", ad: "Emine'nin bilgisayarı", eposta: "x@y" });
  assert.deepEqual(r, { anahtar: KEY, cihaz: "abcd1234efgh", tur: "bilgisayar", ad: "diger", devret: false });
  assert.throws(() => parseRequest({ anahtar: "kısa", cihaz: "abcd1234", tur: "telefon" }), RequestError);
  assert.throws(() => parseRequest({ anahtar: KEY, cihaz: "x", tur: "telefon" }), RequestError);
  assert.throws(() => parseRequest({ anahtar: KEY, cihaz: "abcd1234", tur: "saat" }), RequestError);
  assert.throws(() => parseRequest(null), RequestError);
});

test("1 telefon + 1 bilgisayar birlikte açılır", () => {
  let s = emptyState();
  let o = claim(s, req("telefon1"), t0);
  assert.equal(o.result.durum, "tamam");
  s = o.state;
  o = claim(s, req("bilgisayar1", "bilgisayar", { ad: "windows" }), t0 + 1000);
  assert.equal(o.result.durum, "tamam");
  s = o.state;
  // Aynı telefon yeniden açılınca yine tamam; saat dolmadan yazılmaz.
  o = claim(s, req("telefon1"), t0 + 5000);
  assert.equal(o.result.durum, "tamam");
  assert.equal(o.changed, false);
  o = claim(s, req("telefon1"), t0 + 2 * 3600000);
  assert.equal(o.changed, true);
});

test("ikinci telefon: dolu, öbür cihaz bilgisiyle", () => {
  const s = claim(emptyState(), req("telefon1"), t0).state;
  const o = claim(s, req("telefon2", "telefon", { ad: "iphone" }), t0 + DAY);
  assert.equal(o.result.durum, "dolu");
  assert.equal(o.result.diger.ad, "android");
  assert.equal(o.result.diger.son, new Date(t0).toISOString());
  assert.equal(o.result.devirKalan, 3);
  assert.equal(o.state.telefon.cihaz, "telefon1");
});

test("devret: öbür cihaz çıkar, 30 günde 3 hak", () => {
  let s = claim(emptyState(), req("t1"), t0).state;
  const ids = ["t2", "t1", "t2"];
  for (let i = 0; i < 3; i++) {
    const o = claim(s, req(ids[i], "telefon", { devret: true }), t0 + (i + 1) * 1000);
    assert.equal(o.result.durum, "tamam");
    assert.equal(o.result.devredildi, true);
    assert.equal(o.result.devirKalan, 2 - i);
    s = o.state;
  }
  // Dördüncü devir reddedilir; ilk devirden 30 gün sonra hak döner.
  let o = claim(s, req("t1", "telefon", { devret: true }), t0 + 10 * DAY);
  assert.equal(o.result.durum, "dolu");
  assert.equal(o.result.devirKalan, 0);
  assert.equal(o.result.sonrakiDevir, new Date(t0 + 1000 + 30 * DAY).toISOString());
  // t2 her gün kullanılıyor; hak dönünce t1 alabilir.
  s = claim(s, req("t2"), t0 + 30 * DAY).state;
  o = claim(s, req("t1", "telefon", { devret: true }), t0 + 31 * DAY);
  assert.equal(o.result.durum, "tamam");
});

test("uzun süre görülmeyen cihazın yeri boşalır", () => {
  const s = claim(emptyState(), req("kayip"), t0).state;
  assert.equal(claim(s, req("yeni"), t0 + 44 * DAY).result.durum, "dolu");
  const o = claim(s, req("yeni"), t0 + 46 * DAY);
  assert.equal(o.result.durum, "tamam");
  assert.equal(o.result.devredildi, undefined);
});

test("bırak: yalnız kendi yerini boşaltır", () => {
  let s = claim(emptyState(), req("t1"), t0).state;
  assert.equal(release(s, req("t2")).changed, false);
  s = release(s, req("t1")).state;
  assert.equal(s.telefon, undefined);
  const o = claim(s, req("t2"), t0 + 1000);
  assert.equal(o.result.durum, "tamam");
  assert.equal(o.result.devredildi, undefined);
});
