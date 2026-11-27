import { test } from "node:test";
import assert from "node:assert/strict";
import { RequestError, parseEvents, summarize } from "../src/lib.js";

const now = new Date("2026-11-26T12:00:00Z");

test("olaylar doğrulanır ve birleştirilir", () => {
  const out = parseEvents(
    {
      olaylar: [
        { gun: "2026-11-26", reklam: "r1", surum: "a", tur: "g", n: 3 },
        { gun: "2026-11-26", reklam: "r1", surum: "a", tur: "g", n: 2 },
        { gun: "2026-11-26", reklam: "r1", surum: "b", tur: "t", n: 1 },
        { gun: "2026-11-25", reklam: "r2", tur: "g", n: 1 },
        { gun: "2026-10-01", reklam: "r1", tur: "g", n: 1 }, // çok eski
        { gun: "2026-11-26", reklam: "../x", tur: "g", n: 1 }, // geçersiz kimlik
        { gun: "2026-11-26", reklam: "r1", tur: "x", n: 1 }, // geçersiz tür
        { gun: "2026-11-26", reklam: "r3", tur: "g", n: 0 },
        { gun: "2026-11-26", reklam: "r4", tur: "g", n: 999999 },
      ],
    },
    now,
  );
  assert.deepEqual(out, [
    { gun: "2026-11-26", reklam: "r1", surum: "a", tur: "g", n: 5 },
    { gun: "2026-11-26", reklam: "r1", surum: "b", tur: "t", n: 1 },
    { gun: "2026-11-25", reklam: "r2", surum: "a", tur: "g", n: 1 },
    { gun: "2026-11-26", reklam: "r4", surum: "a", tur: "g", n: 1000 },
  ]);
});

test("kişisel alanlar yok sayılır, liste sınırı", () => {
  const out = parseEvents({ olaylar: [{ gun: "2026-11-26", reklam: "r1", tur: "t", n: 1, cihaz: "abc", ip: "1.2.3.4" }] }, now);
  assert.deepEqual(Object.keys(out[0]).sort(), ["gun", "n", "reklam", "surum", "tur"]);
  assert.throws(() => parseEvents({}, now), RequestError);
  assert.throws(() => parseEvents({ olaylar: new Array(201).fill({}) }, now), RequestError);
});

test("özet: sürüm ve gün toplamları", () => {
  const s = summarize([
    { gun: "2026-11-25", reklam: "r1", surum: "a", tur: "g", n: 10 },
    { gun: "2026-11-26", reklam: "r1", surum: "b", tur: "g", n: 8 },
    { gun: "2026-11-26", reklam: "r1", surum: "b", tur: "t", n: 2 },
  ]);
  assert.deepEqual(s.r1.a, { g: 10, t: 0 });
  assert.deepEqual(s.r1.b, { g: 8, t: 2 });
  assert.deepEqual(s.r1.gunluk["2026-11-26"], { g: 8, t: 2 });
});

import { BASVURU_ID_RE, newApplicationId, parseApplication } from "../src/lib.js";

test("başvuru doğrulanır ve temizlenir", () => {
  const b = parseApplication({
    ad: "  Ayşe Yılmaz ",
    firma: "Ayşe Kırtasiye",
    telefon: "+90 532 111 22 33",
    eposta: "AYSE@ornek.com",
    mesaj: "Ana sayfa kartı için fiyat alabilir miyim?",
    alan: "ana_sayfa/card",
    dil: "tr",
    ulke: "TR",
  });
  assert.equal(b.ad, "Ayşe Yılmaz");
  assert.equal(b.eposta, "ayse@ornek.com");
  assert.equal(b.alan, "ana_sayfa/card");
});

test("eksik ya da hatalı başvuru reddedilir", () => {
  const ok = { ad: "Ali", telefon: "05321112233", mesaj: "Merhaba, reklam" };
  assert.throws(() => parseApplication({ ...ok, ad: "" }), RequestError);
  assert.throws(() => parseApplication({ ...ok, mesaj: "hi" }), RequestError);
  assert.throws(() => parseApplication({ ...ok, telefon: "" }), RequestError);
  assert.throws(() => parseApplication({ ...ok, telefon: "abc" }), RequestError);
  assert.throws(() => parseApplication({ ...ok, eposta: "yok" }), RequestError);
  assert.throws(() => parseApplication({ ...ok, web: "http://spam" }), RequestError);
  assert.equal(parseApplication({ ...ok, alan: "../x" }).alan, "");
  assert.equal(parseApplication({ ...ok, mesaj: "x".repeat(5000) }).mesaj.length, 1000);
});

test("başvuru kimliği biçimi", () => {
  assert.match(newApplicationId(), BASVURU_ID_RE);
  assert.ok(!BASVURU_ID_RE.test("ba_../../x"));
});
