// Netice soru üretici — Cloudflare Worker.
//
// Uygulama ders notunu (metin + görseller) POST /uret adresine gönderir;
// bu sunucu Claude API ile çoktan seçmeli soru önerileri üretir ve geri
// döndürür. Not ve sorular burada saklanmaz; yalnız kota sayaçları (cihaz
// kimliği, ay, adet) tutulur. Claude API anahtarı uygulamada değil, burada
// gizli değer (ANTHROPIC_API_KEY) olarak durur.

import Anthropic from "@anthropic-ai/sdk";
import {
  EXTRACT_PROMPT,
  RequestError,
  SYSTEM_PROMPT,
  buildContent,
  buildExtractContent,
  cleanExtract,
  cleanOutput,
  extractSchema,
  outputSchema,
  parseRequest,
  periods,
  quotaCost,
} from "./lib.js";

const DEFAULT_APP_KEY = "netice-app-1";

const json = (data, status = 200) =>
  new Response(JSON.stringify(data), {
    status,
    headers: { "content-type": "application/json; charset=utf-8", "cache-control": "no-store" },
  });

const fail = (code, message, status) => json({ error: code, message }, status);

async function readCount(kv, key) {
  if (!kv) return 0;
  return Number(await kv.get(key)) || 0;
}

async function addCount(kv, key, n, ttlSeconds) {
  if (!kv || n <= 0) return;
  const v = (await readCount(kv, key)) + n;
  await kv.put(key, String(v), { expirationTtl: ttlSeconds });
}

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    if (request.method === "GET" && url.pathname === "/") {
      return json({ ok: true, service: "netice-soru", model: env.MODEL || "claude-opus-5-5" });
    }
    if (request.method !== "POST" || url.pathname !== "/uret") return fail("not_found", "Not found", 404);

    if (request.headers.get("x-netice-app") !== (env.APP_KEY || DEFAULT_APP_KEY)) {
      return fail("forbidden", "Unknown client", 403);
    }
    const device = request.headers.get("x-netice-device") || "";
    if (!/^[A-Za-z0-9-]{8,64}$/.test(device)) return fail("bad_device", "Device id missing", 400);
    if (!env.ANTHROPIC_API_KEY) return fail("not_configured", "Service is not configured yet", 503);

    let req;
    try {
      req = parseRequest(await request.json());
    } catch (e) {
      if (e instanceof RequestError) return fail(e.code, e.message, e.status);
      return fail("bad_request", "Invalid JSON", 400);
    }

    // Kota: cihaz başına aylık, IP başına günlük, herkes için günlük üst sınır.
    const kv = env.KOTA;
    const { month, day } = periods();
    const ip = request.headers.get("cf-connecting-ip") || "unknown";
    const keys = {
      device: `d:${device}:${month}`,
      ip: `i:${ip}:${day}`,
      all: `g:${day}`,
    };
    const limits = {
      device: Number(env.MONTHLY_DEVICE_LIMIT) || 600,
      ip: Number(env.DAILY_IP_LIMIT) || 200,
      all: Number(env.DAILY_LIMIT) || 5000,
    };
    const [usedDevice, usedIp, usedAll] = await Promise.all([
      readCount(kv, keys.device),
      readCount(kv, keys.ip),
      readCount(kv, keys.all),
    ]);
    const ask = quotaCost(req, req.count);
    if (usedDevice + ask > limits.device) {
      return json({ error: "quota", message: "Monthly limit reached", used: usedDevice, limit: limits.device }, 429);
    }
    if (usedIp + ask > limits.ip || usedAll + ask > limits.all) {
      return fail("busy", "Daily limit reached, try again tomorrow", 429);
    }

    const client = new Anthropic({ apiKey: env.ANTHROPIC_API_KEY, maxRetries: 2, timeout: 280_000 });
    let response;
    try {
      // 20 soruya kadar uzun yanıt: akış (stream) ile alınır, zaman aşımı olmaz.
      const stream = client.beta.messages.stream({
        model: env.MODEL || "claude-opus-5-5",
        max_tokens: 32000,
        system: req.mode === "extract" ? EXTRACT_PROMPT : SYSTEM_PROMPT,
        messages: [{ role: "user", content: req.mode === "extract" ? buildExtractContent(req) : buildContent(req) }],
        output_config: {
          effort: req.mode === "extract" ? "low" : "medium",
          format: { type: "json_schema", schema: req.mode === "extract" ? extractSchema() : outputSchema() },
        },
        // Yanlışlıkla reddedilen isteklerde başka modelle yeniden dener.
        betas: ["server-side-fallback-2026-07-01"],
        fallbacks: "default",
      });
      response = await stream.finalMessage();
    } catch (e) {
      if (e instanceof Anthropic.RateLimitError) return fail("busy", "Service is busy, try again shortly", 503);
      if (e instanceof Anthropic.BadRequestError) {
        console.error("bad request", e.message);
        return fail("bad_request", "The note could not be processed", 400);
      }
      if (e instanceof Anthropic.APIError) {
        console.error("api error", e.status, e.message);
        return fail("upstream", "Question service error, try again", 502);
      }
      console.error("network", String(e));
      return fail("upstream", "Question service unreachable", 502);
    }

    if (response.stop_reason === "refusal") {
      return fail("refused", "No questions could be written from this note", 422);
    }
    const text = response.content
      .filter((b) => b.type === "text")
      .map((b) => b.text)
      .join("");
    let parsed;
    try {
      parsed = JSON.parse(text);
    } catch {
      console.error("unparsable output", response.stop_reason);
      return fail("incomplete", "The answer was incomplete, try fewer questions", 502);
    }
    const result = req.mode === "extract" ? cleanExtract(parsed, req) : cleanOutput(parsed, req);

    const n = quotaCost(req, result.questions.length);
    await Promise.all([
      addCount(kv, keys.device, n, 40 * 24 * 3600),
      addCount(kv, keys.ip, n, 2 * 24 * 3600),
      addCount(kv, keys.all, n, 2 * 24 * 3600),
    ]);
    console.log(JSON.stringify({ month, mode: req.mode, count: result.questions.length, in: response.usage?.input_tokens, out: response.usage?.output_tokens }));

    return json({ ...result, cost: n, used: usedDevice + n, limit: limits.device });
  },
};
