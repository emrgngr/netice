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
