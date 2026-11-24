// Netice soru üretici: isteği doğrulama, istem (prompt) hazırlama ve
// yanıtı temizleme. Ağ ve kota işleri index.js'tedir.

export const LANGUAGES = {
  tr: "Turkish",
  en: "English",
  az: "Azerbaijani",
  de: "German",
  ar: "Arabic",
  es: "Spanish",
  ru: "Russian",
  it: "Italian",
  fr: "French",
  zh: "Simplified Chinese",
  ja: "Japanese",
};

export const DIFFICULTIES = ["mixed", "easy", "medium", "hard"];

export const LIMITS = {
  maxQuestions: 10,
  maxTextChars: 60000,
  maxImages: 6,
  // base64 uzunluğu; ~1,5 MB görsel.
  maxImageChars: 2_000_000,
};

export class RequestError extends Error {
  constructor(code, message, status = 400) {
    super(message);
    this.code = code;
    this.status = status;
  }
}

const str = (v, max = 400) => (typeof v === "string" ? v.trim().slice(0, max) : "");

/** Uygulamadan gelen gövdeyi doğrular ve sadeleştirir. */
export function parseRequest(body) {
  if (!body || typeof body !== "object") throw new RequestError("bad_request", "JSON body expected");
  const note = body.note && typeof body.note === "object" ? body.note : {};
  const text = typeof note.text === "string" ? note.text.trim() : "";
  if (text.length > LIMITS.maxTextChars) throw new RequestError("too_long", "Note text is too long");

  const images = Array.isArray(note.images) ? note.images : [];
  if (images.length > LIMITS.maxImages) throw new RequestError("too_many_images", "Too many images");
  const cleanImages = images.map((im) => {
    const data = typeof im?.data === "string" ? im.data : "";
    const type = im?.type === "image/png" ? "image/png" : "image/jpeg";
    if (!data || data.length > LIMITS.maxImageChars || !/^[A-Za-z0-9+/=]+$/.test(data)) {
      throw new RequestError("bad_image", "Image is missing or too large");
    }
    return { type, data };
  });
  if (text.length < 40 && cleanImages.length === 0) {
    throw new RequestError("too_short", "The note is too short to write questions from");
  }

  const count = Math.round(Number(body.count) || 5);
  if (count < 1 || count > LIMITS.maxQuestions) throw new RequestError("bad_count", "count must be 1-10");
  const choices = Math.round(Number(body.choices) || 5);
  if (choices < 3 || choices > 5) throw new RequestError("bad_choices", "choices must be 3-5");
  const difficulty = DIFFICULTIES.includes(body.difficulty) ? body.difficulty : "mixed";
  const lang = LANGUAGES[body.lang] ? body.lang : "tr";

  const avoid = Array.isArray(body.avoid) ? body.avoid.filter((s) => typeof s === "string").slice(0, 30).map((s) => s.slice(0, 300)) : [];

  return {
    count,
    choices,
    difficulty,
    lang,
    avoid,
    note: {
      title: str(note.title),
      subject: str(note.subject),
      grade: str(note.grade),
      topic: str(note.topic),
      outcome: str(note.outcome, 600),
      text,
      images: cleanImages,
    },
  };
}

export const SYSTEM_PROMPT = `You are an experienced assessment writer helping a teacher build a question bank from their own lesson notes.

Write multiple-choice questions that a teacher could put on a real classroom exam:
- Every question must be answerable from the note's content (text and images). Do not test facts the note does not cover.
- Exactly one choice is correct. Distractors are plausible: common misconceptions, calculation slips, or partly true statements — never joke answers, never "all of the above" / "none of the above".
- Choices are short, parallel in grammar and similar in length, so the longest choice is not a giveaway. Spread the correct answers over different positions.
- Question stems are self-contained, clear and age-appropriate for the stated grade or level; avoid negative stems unless the negation is emphasised (e.g. in capitals).
- Mix question kinds where the material allows: recall, understanding, application, interpreting a table/graph/figure from the note.
- Do not repeat questions and do not write near-duplicates of the questions listed under "Avoid".
- Write the solution as a short explanation (1–3 sentences) of why the correct choice is right, in the same language.
- Use plain text. For formulas use ordinary characters (x², √, π, ≤, →); no LaTeX, no Markdown.
- Do not put choice letters (A), B) …) inside the choice texts.

If the note does not contain enough material for the requested number of good questions, write as many good ones as you can and explain briefly in "note_problem". If the note is not lesson material at all, return no questions and explain in "note_problem". Otherwise "note_problem" is an empty string.`;

/** Claude'a gönderilecek kullanıcı mesajının içerik blokları. */
export function buildContent(req) {
  const n = req.note;
  const language = LANGUAGES[req.lang];
  const diff =
    req.difficulty === "mixed"
      ? "a mix of easy, medium and hard"
      : `${req.difficulty} (all questions)`;
  const meta = [
    n.subject && `Subject: ${n.subject}`,
    n.grade && `Grade / level: ${n.grade}`,
    n.topic && `Topic: ${n.topic}`,
    n.outcome && `Learning outcome: ${n.outcome}`,
    n.title && `Note title: ${n.title}`,
  ].filter(Boolean);

  const blocks = [];
  for (const im of n.images) {
    blocks.push({ type: "image", source: { type: "base64", media_type: im.type, data: im.data } });
  }
  let text = "";
  if (meta.length) text += meta.join("\n") + "\n\n";
  if (n.text) text += `<note>\n${n.text}\n</note>\n\n`;
  if (n.images.length) text += `The note also has ${n.images.length} image(s) above (pages, photos or figures from the teacher's material).\n\n`;
  if (req.avoid.length) text += `Avoid (already in the bank):\n${req.avoid.map((s) => `- ${s}`).join("\n")}\n\n`;
  text += `Write ${req.count} multiple-choice question(s) with exactly ${req.choices} choices each. Difficulty: ${diff}. Write everything (stems, choices, solutions, note_problem) in ${language}.`;
  blocks.push({ type: "text", text });
  return blocks;
}

/** Yapılandırılmış çıktı şeması. */
export function outputSchema() {
  return {
    type: "object",
    additionalProperties: false,
    required: ["questions", "note_problem"],
    properties: {
      note_problem: { type: "string" },
      questions: {
        type: "array",
        items: {
          type: "object",
          additionalProperties: false,
          required: ["text", "choices", "correct_index", "difficulty", "solution"],
          properties: {
            text: { type: "string" },
            choices: { type: "array", items: { type: "string" } },
            correct_index: { type: "integer" },
            difficulty: { type: "string", enum: ["easy", "medium", "hard"] },
            solution: { type: "string" },
          },
        },
      },
    },
  };
}

const LETTER_PREFIX = /^\s*(?:[A-Ea-e]|[1-5])\s*[).:-]\s+/;

/** Modelin çıktısını uygulamaya gidecek biçime getirir; bozuk soruları atar. */
export function cleanOutput(parsed, req) {
  const out = [];
  const seen = new Set();
  for (const q of Array.isArray(parsed?.questions) ? parsed.questions : []) {
    const text = str(q?.text, 4000);
    const choices = (Array.isArray(q?.choices) ? q.choices : []).map((c) => str(c, 1000).replace(LETTER_PREFIX, ""));
    const correct = Number.isInteger(q?.correct_index) ? q.correct_index : -1;
    if (!text || choices.length !== req.choices || choices.some((c) => !c)) continue;
    if (correct < 0 || correct >= choices.length) continue;
    if (new Set(choices.map((c) => c.toLowerCase())).size !== choices.length) continue;
    const key = text.toLowerCase().replace(/\s+/g, " ");
    if (seen.has(key)) continue;
    seen.add(key);
    out.push({
      text,
      choices,
      correct,
      difficulty: ["easy", "medium", "hard"].includes(q.difficulty) ? q.difficulty : "medium",
      solution: str(q?.solution, 2000),
    });
    if (out.length >= req.count) break;
  }
  return { questions: out, problem: str(parsed?.note_problem, 600) };
}

/** Kota anahtarları için tarih parçaları (UTC). */
export function periods(now = new Date()) {
  const iso = now.toISOString();
  return { month: iso.slice(0, 7), day: iso.slice(0, 10) };
}
