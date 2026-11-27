import { test } from "node:test";
import assert from "node:assert/strict";
import { RequestError, buildContent, cleanOutput, parseRequest } from "../src/lib.js";

const note = { title: "Hücre", subject: "Biyoloji", grade: "9", topic: "Hücre zarı", text: "Hücre zarı seçici geçirgendir. ".repeat(5) };

test("geçerli istek sadeleştirilir", () => {
  const r = parseRequest({ count: 7, choices: 4, difficulty: "hard", lang: "de", note });
  assert.equal(r.count, 7);
  assert.equal(r.choices, 4);
  assert.equal(r.difficulty, "hard");
  assert.equal(r.lang, "de");
  const blocks = buildContent(r);
  assert.equal(blocks.at(-1).type, "text");
  assert.match(blocks.at(-1).text, /in German/);
  assert.match(blocks.at(-1).text, /exactly 4 choices/);
});

test("bilinmeyen dil Türkçeye, zorluk karışığa düşer", () => {
  const r = parseRequest({ count: 5, lang: "xx", difficulty: "?", note });
  assert.equal(r.lang, "tr");
  assert.equal(r.difficulty, "mixed");
  assert.equal(r.choices, 5);
});

test("çok kısa not ve hatalı adet reddedilir", () => {
  assert.throws(() => parseRequest({ count: 5, note: { text: "kısa" } }), RequestError);
  assert.throws(() => parseRequest({ count: 21, note }), RequestError);
  assert.throws(() => parseRequest({ count: 5, note: { images: [{ data: "<>" }] } }), RequestError);
});

test("görsel blokları metinden önce gelir", () => {
  const r = parseRequest({ count: 5, note: { images: [{ type: "image/jpeg", data: "QUJD" }] } });
  const b = buildContent(r);
  assert.equal(b[0].type, "image");
  assert.equal(b[1].type, "text");
});

test("bozuk sorular atılır, şık harfleri temizlenir", () => {
  const req = { count: 3, choices: 4, types: ["multiple"] };
  const out = cleanOutput(
    {
      note_problem: "",
      questions: [
        { text: "Soru 1", topic: "Hız", choices: ["A) bir", "B) iki", "C) üç", "D) dört"], correct_index: 2, difficulty: "easy", solution: "çünkü" },
        { text: "Soru 2", choices: ["a", "b", "c"], correct_index: 0, difficulty: "easy", solution: "" },
        { text: "Soru 3", choices: ["a", "b", "c", "d"], correct_index: 9, difficulty: "easy", solution: "" },
        { text: "Soru 4", choices: ["a", "a", "c", "d"], correct_index: 0, difficulty: "easy", solution: "" },
        { text: "soru 1", choices: ["a", "b", "c", "d"], correct_index: 0, difficulty: "easy", solution: "" },
        { text: "Soru 5", choices: ["a", "b", "c", "d"], correct_index: 3, difficulty: "weird", solution: "" },
      ],
    },
    req,
  );
  assert.equal(out.questions.length, 2);
  assert.deepEqual(out.questions[0].choices, ["bir", "iki", "üç", "dört"]);
  assert.equal(out.questions[0].correct, 2);
  assert.equal(out.questions[0].topic, "Hız");
  assert.equal(out.questions[1].topic, "");
  assert.equal(out.questions[1].difficulty, "medium");
});

test("soru türleri: istek, istem ve temizleme", () => {
  const r = parseRequest({ count: 8, types: ["true_false", "x", "open", "fill"], note });
  assert.deepEqual(r.types, ["true_false", "fill", "open"]);
  assert.deepEqual(parseRequest({ count: 5, note }).types, ["multiple"]);
  assert.match(buildContent(r).at(-1).text, /split about evenly/);

  const out = cleanOutput(
    {
      note_problem: "",
      questions: [
        { type: "true_false", text: "Zar seçici geçirgendir.", topic: "Zar", choices: [], correct_index: 0, answer: "", difficulty: "easy", solution: "" },
        { type: "true_false", text: "Bozuk", choices: [], correct_index: 3, answer: "", difficulty: "easy", solution: "" },
        { type: "fill", text: "Suyun zardan geçişine _____ denir.", choices: [], correct_index: -1, answer: "osmoz", difficulty: "easy", solution: "" },
        { type: "fill", text: "Boşluksuz cümle", choices: [], correct_index: -1, answer: "x", difficulty: "easy", solution: "" },
        { type: "open", text: "Difüzyonu açıklayınız.", choices: [], correct_index: -1, answer: "", difficulty: "hard", solution: "" },
        { type: "open", text: "Osmozu açıklayınız.", choices: [], correct_index: -1, answer: "Suyun yarı geçirgen zardan geçişi.", difficulty: "hard", solution: "" },
        { type: "multiple", text: "İstenmeyen tür", choices: ["a", "b", "c", "d", "e"], correct_index: 0, answer: "", difficulty: "easy", solution: "" },
      ],
    },
    r,
  );
  assert.deepEqual(out.questions.map((q) => q.type), ["true_false", "fill", "open"]);
  assert.equal(out.questions[0].correct, 0);
  assert.equal(out.questions[1].answer, "osmoz");
  assert.deepEqual(out.questions[2].choices, []);
});

test("çocuk (ilkokul) dili isteği istemde ek kurallar olarak yer alır", () => {
  const req = parseRequest({ count: 5, choices: 3, audience: "kids", note: { text: "Bitkiler büyümek için su, hava ve güneş ışığına ihtiyaç duyar. Tohum toprakta çimlenir." } });
  assert.equal(req.kids, true);
  assert.equal(req.choices, 3);
  const text = buildContent(req).at(-1).text;
  assert.match(text, /primary-school children/);
  const adult = parseRequest({ count: 5, note: { text: "Bitkiler büyümek için su, hava ve güneş ışığına ihtiyaç duyar. Tohum toprakta çimlenir." } });
  assert.equal(adult.kids, false);
  assert.doesNotMatch(buildContent(adult).at(-1).text, /primary-school children/);
});

test("yeni soru türleri: eşleştirme, D/Y tablosu, kelime havuzu, sıralama", () => {
  const r = parseRequest({ count: 9, types: ["matching", "tf_table", "word_bank", "ordering"], note });
  assert.deepEqual(r.types, ["matching", "tf_table", "word_bank", "ordering"]);
  const base = { topic: "", correct_index: -1, answer: "", difficulty: "easy", solution: "" };
  const out = cleanOutput(
    {
      note_problem: "",
      questions: [
        { ...base, type: "matching", text: "Eşleştiriniz.", items: ["Kök", "Yaprak", "Çiçek"], choices: ["Su alır", "Besin üretir", "Tohum oluşturur"], item_keys: [0, 1, 2] },
        { ...base, type: "matching", text: "Hatalı anahtar", items: ["a", "b"], choices: ["x", "y"], item_keys: [0, 4] },
        { ...base, type: "tf_table", text: "D/Y", items: ["Bitkiler su ister.", "Taş canlıdır."], choices: [], item_keys: [0, 1] },
        { ...base, type: "tf_table", text: "Bozuk", items: ["a", "b"], choices: [], item_keys: [0, 2] },
        { ...base, type: "word_bank", text: "Doldurunuz.", items: ["Bitki _____ ile su alır.", "Yaprak _____ üretir."], choices: ["kök", "besin", "taş"], item_keys: [0, 1] },
        { ...base, type: "word_bank", text: "Boşluksuz", items: ["Bitki su alır.", "x _____"], choices: ["a", "b"], item_keys: [0, 1] },
        { ...base, type: "ordering", text: "Sıralayınız.", items: ["1. Tohum ekilir", "Çimlenir", "Fide olur", "Çiçek açar"], choices: [], item_keys: [] },
        { ...base, type: "ordering", text: "Kısa", items: ["a", "b"], choices: [], item_keys: [] },
      ],
    },
    r,
  );
  assert.deepEqual(out.questions.map((q) => q.type), ["matching", "tf_table", "word_bank", "ordering"]);
  assert.deepEqual(out.questions[0].item_keys, [0, 1, 2]);
  assert.deepEqual(out.questions[1].item_keys, [0, 1]);
  assert.equal(out.questions[3].items[0], "Tohum ekilir");
});

import { buildExtractContent, cleanExtract, quotaCost } from "../src/lib.js";

test("ayıklama isteği: kısa belge kabul, 40'a kadar soru", () => {
  const r = parseRequest({ mode: "extract", note: { text: "1) 2+2 kaçtır? A) 3 B) 4" } });
  assert.equal(r.mode, "extract");
  assert.equal(r.count, 40);
  assert.equal(r.solve, true);
  assert.throws(() => parseRequest({ mode: "extract", count: 41, note }), RequestError);
  const off = parseRequest({ mode: "extract", solve: false, note });
  assert.match(buildExtractContent(off).at(-1).text, /do not solve/);
  // Eski istemci: mode yoksa üretme.
  assert.equal(parseRequest({ count: 5, note }).mode, "generate");
});

test("ayıklanan sorular temizlenir, cevabı bilinmeyen tutulur", () => {
  const req = parseRequest({ mode: "extract", solve: false, note });
  const out = cleanExtract(
    {
      note_problem: "",
      questions: [
        { type: "multiple", number: "1", text: "2+2 kaçtır?", topic: "Toplama", choices: ["A) 3", "B) 4", "C) 5"], correct_index: 1, answer: "", answer_source: "document", needs_figure: false, difficulty: "easy", solution: "" },
        { type: "multiple", number: "2", text: "3+3 kaçtır?", topic: "Toplama", choices: ["5", "6"], correct_index: 1, answer: "", answer_source: "solved", needs_figure: false, difficulty: "easy", solution: "3+3=6" },
        { type: "multiple", number: "3", text: "Bozuk", topic: "", choices: ["tek"], correct_index: 0, answer: "", answer_source: "document", needs_figure: false, difficulty: "easy", solution: "" },
        { type: "open", number: "4", text: "Açıklayınız.", topic: "", choices: [], correct_index: -1, answer: "", answer_source: "document", needs_figure: true, difficulty: "hard", solution: "" },
      ],
    },
    req,
  );
  assert.equal(out.questions.length, 3);
  assert.deepEqual(out.questions[0].choices, ["3", "4", "5"]);
  assert.equal(out.questions[0].correct, 1);
  assert.equal(out.questions[1].answer_source, "unknown");
  assert.equal(out.questions[1].correct, -1);
  assert.equal(out.questions[1].solution, "");
  assert.equal(out.questions[2].answer_source, "unknown");
  assert.equal(out.questions[2].needs_figure, true);
});

test("kota: ayıklamada 5 soru 1 hak", () => {
  assert.equal(quotaCost({ mode: "extract" }, 11), 3);
  assert.equal(quotaCost({ mode: "generate" }, 11), 11);
});
