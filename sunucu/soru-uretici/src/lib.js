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

// Soru türleri: çoktan seçmeli, doğru/yanlış, boşluk doldurma, klasik (açık uçlu).
export const TYPES = ["multiple", "true_false", "fill", "open", "matching", "tf_table", "word_bank", "ordering"];

export const LIMITS = {
  maxQuestions: 20,
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
  if (count < 1 || count > LIMITS.maxQuestions) throw new RequestError("bad_count", "count must be 1-20");
  const choices = Math.round(Number(body.choices) || 5);
  if (choices < 3 || choices > 5) throw new RequestError("bad_choices", "choices must be 3-5");
  const difficulty = DIFFICULTIES.includes(body.difficulty) ? body.difficulty : "mixed";
  const lang = LANGUAGES[body.lang] ? body.lang : "tr";

  const types = Array.isArray(body.types) ? TYPES.filter((t) => body.types.includes(t)) : [];
  if (!types.length) types.push("multiple");

  const avoid = Array.isArray(body.avoid) ? body.avoid.filter((s) => typeof s === "string").slice(0, 30).map((s) => s.slice(0, 300)) : [];

  // Çocuklara (ilkokul) uygun dil; eski istemciler göndermez.
  const kids = body.audience === "kids";

  return {
    count,
    choices,
    difficulty,
    lang,
    types,
    avoid,
    kids,
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

Write questions that a teacher could put on a real classroom exam. The requested question types can be:
- "multiple": multiple choice. Exactly one choice is correct; give its 0-based position in "correct_index".
- "true_false": a single clear statement that is either true or false (no "choices"). "correct_index" is 0 if the statement is TRUE, 1 if it is FALSE. Mix true and false statements about evenly; a false statement must be false because of one specific, checkable error, not vague wording.
- "fill": a sentence from the note's content with one key term replaced by "_____" (exactly one blank). "answer" is the missing term (1–4 words); add acceptable alternatives after " / " if any.
- "open": a short-answer or essay question (explain, compare, calculate, give an example). "answer" is a model answer a teacher can grade against (2–5 sentences or the main points).
- "matching": "text" is a short instruction; "items" are 3–6 short prompts (left column) and "choices" are 3–5 short options (right column, at most 5, may include one extra distractor); "item_keys" gives, for each item, the 0-based index of its matching choice. Each choice is used at most once.
- "tf_table": "text" is a short instruction; "items" are 3–6 independent statements about the note, mixing true and false about evenly; "item_keys" is 0 for a TRUE statement and 1 for a FALSE one.
- "word_bank": "text" is a short instruction; "items" are 3–6 sentences from the note, each with exactly one key term replaced by "_____"; "choices" is the word bank (3–5 single words or short terms, each used at most once, may include one extra distractor); "item_keys" gives the 0-based index of the word for each sentence.
- "ordering": "text" asks for the correct order (e.g. of steps, stages, events or a process); "items" are 3–6 steps written in the CORRECT order; "choices" is empty and "item_keys" is empty (the app shuffles them and builds the choices).
For "true_false", "fill" and "open": "choices" is an empty array and "correct_index" is -1 except for true_false as above. For "multiple": "answer" is an empty string. For every type except the four above, "items" and "item_keys" are empty arrays; for those four, "correct_index" is -1 and "answer" is an empty string.

Rules:
- Every question must be answerable from the note's content (text and images). Do not test facts the note does not cover.
- For multiple choice: exactly one choice is correct. Distractors are plausible: common misconceptions, calculation slips, or partly true statements — never joke answers, never "all of the above" / "none of the above".
- Choices are short, parallel in grammar and similar in length, so the longest choice is not a giveaway. Spread the correct answers over different positions.
- Question stems are self-contained, clear and age-appropriate for the stated grade or level; avoid negative stems unless the negation is emphasised (e.g. in capitals).
- Mix question kinds where the material allows: recall, understanding, application, interpreting a table/graph/figure from the note.
- Do not repeat questions and do not write near-duplicates of the questions listed under "Avoid".
- For each question give "topic": the specific sub-topic or learning outcome it tests, as a short phrase (2–8 words) taken from the note's own headings or terms, so a teacher can group the answer key by topic.
- Write the solution as a short explanation (1–3 sentences) of why the correct choice is right, in the same language. Start it with the basis in the note when there is one (article/section number, rule, law, formula or definition, e.g. "m.7:", "Newton's 2nd law:"), and say briefly why the main distractor is wrong when that helps.
- Spread the correct answers evenly over the choice positions across the whole set.
- Use plain text. For formulas use ordinary characters (x², √, π, ≤, →); no LaTeX, no Markdown.
- Do not put choice letters (A), B) …) inside the choice texts.

If the note does not contain enough material for the requested number of good questions, write as many good ones as you can and explain briefly in "note_problem". If the note is not lesson material at all, return no questions and explain in "note_problem". Otherwise "note_problem" is an empty string.`;

// Çocuk (ilkokul, yaklaşık 6–10 yaş) şablonu için ek kurallar.
export const KIDS_PROMPT = `Audience: young primary-school children (about 6–10 years old, grades 1–4) who are still building reading skills. These questions will be printed in a colourful children's test booklet.
- Speak to the child directly and warmly where it fits (e.g. "Which one is a plant?", "What happens if Ali's flower gets no water?"). Use simple everyday examples, names and situations from a child's life.
- Keep stems short: one or two short sentences, at most about 15 words each. Use common, concrete words; explain or avoid technical terms the note does not teach.
- Keep choices very short (one to four words where possible) and clearly different from each other. Distractors are plausible for a child but never tricky, silly or scary.
- Prefer positive stems. If a negative is unavoidable, write the negative word in capitals (e.g. "Which one is NOT a living thing?").
- Each question tests one idea. No double negatives, no "all/none of the above", no long tables or calculations beyond the grade.
- Solutions are one short, encouraging sentence a teacher can read to the child.`;

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
  const typeNames = {
    multiple: `multiple choice (exactly ${req.choices} choices each)`,
    true_false: "true/false",
    fill: "fill in the blank",
    open: "open-ended (short answer / essay)",
    matching: "matching (items to options)",
    tf_table: "true/false table (several statements)",
    word_bank: "fill in the blanks from a word bank",
    ordering: "put the steps in the correct order",
  };
  const kinds =
    req.types.length === 1
      ? `All questions are of type "${req.types[0]}" — ${typeNames[req.types[0]]}.`
      : `Use these question types, split about evenly over the set: ${req.types.map((t) => `"${t}" (${typeNames[t]})`).join(", ")}.`;
  if (req.kids) text += KIDS_PROMPT + "\n\n";
  text += `Write ${req.count} question(s). ${kinds} Difficulty: ${diff}. Write everything (stems, choices, answers, solutions, note_problem) in ${language}.`;
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
          required: ["type", "text", "topic", "choices", "correct_index", "answer", "items", "item_keys", "difficulty", "solution"],
          properties: {
            type: { type: "string", enum: TYPES },
            text: { type: "string" },
            topic: { type: "string" },
            choices: { type: "array", items: { type: "string" } },
            correct_index: { type: "integer" },
            answer: { type: "string" },
            items: { type: "array", items: { type: "string" } },
            item_keys: { type: "array", items: { type: "integer" } },
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
    const type = TYPES.includes(q?.type) && req.types.includes(q.type) ? q.type : req.types.length === 1 ? req.types[0] : "";
    if (!type) continue;
    const text = str(q?.text, 4000);
    if (!text) continue;
    let choices = [];
    let correct = -1;
    let answer = "";
    let items = [];
    let itemKeys = [];
    const idx = Number.isInteger(q?.correct_index) ? q.correct_index : -1;
    const rawItems = (Array.isArray(q?.items) ? q.items : []).map((c) => str(c, 600).replace(LETTER_PREFIX, ""));
    const rawKeys = Array.isArray(q?.item_keys) ? q.item_keys : [];
    if (type === "matching" || type === "word_bank" || type === "tf_table") {
      if (rawItems.length < 2 || rawItems.length > 8 || rawItems.some((c) => !c)) continue;
      if (rawKeys.length !== rawItems.length || !rawKeys.every(Number.isInteger)) continue;
      if (type === "tf_table") {
        if (!rawKeys.every((k) => k === 0 || k === 1)) continue;
      } else {
        choices = (Array.isArray(q?.choices) ? q.choices : []).map((c) => str(c, 300).replace(LETTER_PREFIX, ""));
        if (choices.length < 2 || choices.length > 5 || choices.some((c) => !c)) continue;
        if (new Set(choices.map((c) => c.toLowerCase())).size !== choices.length) continue;
        if (!rawKeys.every((k) => k >= 0 && k < choices.length)) continue;
        if (type === "word_bank" && !rawItems.every((t) => /_{3,}|…{2,}|\.{4,}/.test(t))) continue;
      }
      items = rawItems;
      itemKeys = rawKeys;
    } else if (type === "ordering") {
      if (rawItems.length < 3 || rawItems.length > 6 || rawItems.some((c) => !c)) continue;
      if (new Set(rawItems.map((c) => c.toLowerCase())).size !== rawItems.length) continue;
      items = rawItems;
    } else if (type === "multiple") {
      choices = (Array.isArray(q?.choices) ? q.choices : []).map((c) => str(c, 1000).replace(LETTER_PREFIX, ""));
      if (choices.length !== req.choices || choices.some((c) => !c)) continue;
      if (idx < 0 || idx >= choices.length) continue;
      if (new Set(choices.map((c) => c.toLowerCase())).size !== choices.length) continue;
      correct = idx;
    } else if (type === "true_false") {
      if (idx !== 0 && idx !== 1) continue;
      correct = idx;
    } else {
      answer = str(q?.answer, 3000);
      if (!answer) continue;
      if (type === "fill" && !/_{3,}|…{2,}|\.{4,}/.test(text)) continue;
    }
    const key = text.toLowerCase().replace(/\s+/g, " ");
    if (seen.has(key)) continue;
    seen.add(key);
    out.push({
      type,
      text,
      topic: str(q?.topic, 200),
      choices,
      correct,
      answer,
      items,
      item_keys: itemKeys,
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
