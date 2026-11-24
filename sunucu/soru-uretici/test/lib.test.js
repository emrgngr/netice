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
  assert.throws(() => parseRequest({ count: 50, note }), RequestError);
  assert.throws(() => parseRequest({ count: 5, note: { images: [{ data: "<>" }] } }), RequestError);
});

test("görsel blokları metinden önce gelir", () => {
  const r = parseRequest({ count: 5, note: { images: [{ type: "image/jpeg", data: "QUJD" }] } });
  const b = buildContent(r);
  assert.equal(b[0].type, "image");
  assert.equal(b[1].type, "text");
});

test("bozuk sorular atılır, şık harfleri temizlenir", () => {
  const req = { count: 3, choices: 4 };
  const out = cleanOutput(
    {
      note_problem: "",
      questions: [
        { text: "Soru 1", choices: ["A) bir", "B) iki", "C) üç", "D) dört"], correct_index: 2, difficulty: "easy", solution: "çünkü" },
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
  assert.equal(out.questions[1].difficulty, "medium");
});
