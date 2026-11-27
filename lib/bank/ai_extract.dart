// Soru bankası belgesinden hazır soruları ayıklama (yapay zekâ ile).
//
// Nottan soru üretmenin (ai_questions.dart) kardeşi: burada soru YAZILMAZ,
// test kitabı, yaprak test ya da çıkmış sınav belgesindeki sorular kökü,
// şıkları, cevabı ve konusuyla aynen alınır. Belgede cevap anahtarı yoksa
// isteğe bağlı olarak yapay zekâ çözer; bu sorular "kontrol edin" diye
// işaretlenir. Ayıklanan sorular bankaya kendiliğinden girmez.
//
// Kota: 5 ayıklanan soru = 1 soru hakkı (sunucu da aynı hesabı yapar).

import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../l10n/l10n.dart';
import 'ai_questions.dart';
import 'bank_models.dart';
import 'bank_store.dart';

/// Bir istekte en fazla ayıklanan soru (sunucu sınırı).
const extractMaxPerRequest = 40;

/// Bir istekte gönderilen en fazla metin (karakter).
const extractChunkChars = 14000;

/// Bir istekte gönderilen en fazla sayfa görüntüsü.
const extractPagesPerRequest = 3;

/// En fazla işlenecek sayfa görüntüsü.
const extractMaxPages = 60;

/// Cevabın nereden geldiği.
enum AnswerSource {
  /// Belgedeki cevap anahtarından ya da işaretli şıktan.
  document,

  /// Belgede yoktu, yapay zekâ çözdü: öğretmen kontrol etmeli.
  solved,

  /// Cevap bulunamadı: soru bankada "eksik" görünür.
  unknown;

  String get label => switch (this) {
        AnswerSource.document => tr('Cevap belgeden'),
        AnswerSource.solved => tr('Cevabı yapay zekâ buldu, kontrol edin'),
        AnswerSource.unknown => tr('Cevap bulunamadı'),
      };
}

/// Ayıklanan bir soru ve onunla ilgili bilgiler.
class ExtractedQuestion {
  final BankQuestion q;
  final AnswerSource source;

  /// Belgede basılı soru numarası.
  final String number;

  /// Soru bir şekil, grafik ya da resme dayanıyor.
  final bool needsFigure;

  /// Sorunun geldiği sayfa görüntüsü (görselden ayıklandıysa; şekilli
  /// sorularda soruya eklenebilir).
  final Uint8List? page;
  const ExtractedQuestion(this.q, this.source, {this.number = '', this.needsFigure = false, this.page});
}

class ExtractResult {
  final List<ExtractedQuestion> questions;
  final String problem;

  /// Kotadan düşülen hak.
  final int cost;
  const ExtractResult(this.questions, this.problem, this.cost);
}

/// Bir ayıklama parçası: ya metin ya da birkaç sayfa görüntüsü.
class ExtractChunk {
  final String text;
  final List<Uint8List> pages;

  /// Belgenin cevap anahtarı sayfası (her parçaya eklenir, soru ayıklanmaz).
  final Uint8List? keyPage;
  const ExtractChunk({this.text = '', this.pages = const [], this.keyPage});
}

/// Uzun metni boş satırlardan bölerek parçalara ayırır; bir soru iki
/// parçaya bölünmesin diye bölme noktası numaralı satır başına kaydırılır.
List<String> splitForExtract(String text, {int max = extractChunkChars}) {
  final t = text.replaceAll('\r\n', '\n').trim();
  if (t.length <= max) return t.isEmpty ? const [] : [t];
  final out = <String>[];
  var start = 0;
  final qStart = RegExp(r'\n\s*(\d{1,3})\s*[.)-]\s');
  while (start < t.length) {
    var end = math.min(start + max, t.length);
    if (end < t.length) {
      // Sınırdan geriye doğru en yakın soru başı; yoksa boş satır; yoksa sınır.
      final window = t.substring(start, end);
      final starts = qStart.allMatches(window).map((m) => m.start).where((i) => i > max ~/ 3).toList();
      final blank = window.lastIndexOf('\n\n');
      if (starts.isNotEmpty) {
        end = start + starts.last;
      } else if (blank > max ~/ 3) {
        end = start + blank;
      }
    }
    final part = t.substring(start, end).trim();
    if (part.isNotEmpty) out.add(part);
    start = end;
  }
  return out;
}

/// Belgenin sonundaki cevap anahtarı her parçaya eklenir ki ilk
/// parçalardaki sorular da cevabını bulsun.
String? findAnswerKey(String text) {
  final m = RegExp(r'(cevap\s+anahtar[ıi]|answer\s+key|cevaplar|answers|lösungen|réponses|respuestas|ответы)',
          caseSensitive: false)
      .allMatches(text)
      .lastOrNull;
  if (m == null) return null;
  final tail = text.substring(m.start);
  // Anahtar kısa olur: çok uzunsa (ör. "Cevaplar" kelimesi metnin ortasında) alınmaz.
  return tail.length <= 3000 ? tail.trim() : null;
}

/// Metin ve sayfa görüntülerini sunucuya gidecek parçalara çevirir.
/// [keyLastPage]: son sayfa cevap anahtarıdır; soru sayfası sayılmaz, her
/// parçaya eklenir.
List<ExtractChunk> extractChunks({String text = '', List<Uint8List> pages = const [], bool keyLastPage = false}) {
  final out = <ExtractChunk>[];
  final parts = splitForExtract(text);
  final key = parts.length > 1 ? findAnswerKey(text) : null;
  for (var i = 0; i < parts.length; i++) {
    final p = parts[i];
    final withKey = key != null && !p.contains(key) ? '$p\n\n[${tr('Belgenin sonundaki cevap anahtarı')}]\n$key' : p;
    out.add(ExtractChunk(text: withKey));
  }
  final keyPage = keyLastPage && pages.length > 1 ? pages.last : null;
  final ps = (keyPage != null ? pages.sublist(0, pages.length - 1) : pages).take(extractMaxPages).toList();
  for (var i = 0; i < ps.length; i += extractPagesPerRequest) {
    out.add(ExtractChunk(pages: ps.sublist(i, math.min(i + extractPagesPerRequest, ps.length)), keyPage: keyPage));
  }
  return out;
}

/// Sunucuya gidecek istek gövdesi.
Map<String, dynamic> extractRequestBody(ExtractChunk c,
        {required List<String> images, String subject = '', String grade = '', String title = '', bool solve = true}) =>
    {
      // Son görsel cevap anahtarı sayfasıysa sunucuya söylenir.
      if (c.keyPage != null) 'key_page': true,
      'mode': 'extract',
      'count': extractMaxPerRequest,
      'solve': solve,
      'lang': L10n.code,
      'note': {
        'title': title,
        'subject': subject,
        'grade': grade,
        'text': c.text.length > 60000 ? c.text.substring(0, 60000) : c.text,
        'images': [for (final d in images) {'type': 'image/jpeg', 'data': d}],
      },
    };

/// Sunucu yanıtını taslak sorulara çevirir.
ExtractResult parseExtractResponse(Map<String, dynamic> j,
    {String subject = '', String grade = '', String sourceName = '', Uint8List? page, DateTime? now}) {
  final t = now ?? DateTime.now();
  final tag = tr('belgeden');
  final list = <ExtractedQuestion>[];
  for (final raw in (j['questions'] as List?) ?? const []) {
    if (raw is! Map) continue;
    final type = switch (raw['type']) {
      'true_false' => QuestionType.trueFalse,
      'fill' => QuestionType.fill,
      'open' => QuestionType.open,
      _ => QuestionType.multiple,
    };
    final text = '${raw['text'] ?? ''}'.trim();
    if (text.isEmpty) continue;
    final choices = type == QuestionType.multiple ? [for (final c in (raw['choices'] as List?) ?? const []) '$c'.trim()] : <String>[];
    if (type == QuestionType.multiple && (choices.length < 2 || choices.length > 5)) continue;
    final correct = (raw['correct'] as num?)?.toInt() ?? -1;
    final okCorrect = switch (type) {
      QuestionType.multiple => correct >= 0 && correct < choices.length,
      QuestionType.trueFalse => correct == 0 || correct == 1,
      _ => false,
    };
    final answer = '${raw['answer'] ?? ''}'.trim();
    var source = AnswerSource.values.asNameMap()[raw['answer_source']] ?? AnswerSource.unknown;
    if (!okCorrect && answer.isEmpty) source = AnswerSource.unknown;
    final number = '${raw['number'] ?? ''}'.trim();
    final needsFigure = raw['needs_figure'] == true;
    list.add(ExtractedQuestion(
      BankQuestion(
        id: BankStore.newId('q'),
        subject: subject,
        grade: grade,
        topic: '${raw['topic'] ?? ''}'.trim(),
        difficulty: switch (raw['difficulty']) {
          'easy' => Difficulty.easy,
          'hard' => Difficulty.hard,
          _ => Difficulty.medium,
        },
        type: type,
        text: text,
        choices: choices,
        choiceCount: switch (type) {
          QuestionType.multiple => choices.length,
          QuestionType.trueFalse => 2,
          _ => 5,
        },
        correct: okCorrect ? {correct} : const {},
        answerText: type.optical ? '' : answer,
        solution: '${raw['solution'] ?? ''}'.trim(),
        tags: [tag, if (source == AnswerSource.solved) tr('cevabı kontrol et')],
        source: [sourceName, if (number.isNotEmpty) tr('soru {0}', [number])].where((s) => s.isNotEmpty).join(' · '),
        created: t,
        updated: t,
      ),
      source,
      number: number,
      needsFigure: needsFigure,
      page: needsFigure ? page : null,
    ));
  }
  return ExtractResult(list, '${j['problem'] ?? ''}'.trim(), (j['cost'] as num?)?.toInt() ?? (list.length / 5).ceil());
}

/// Ayıklama hakkı: [n] soru için düşülecek miktar.
int extractCost(int n) => (n / 5).ceil();

/// Bir parçadaki soruları ayıklar.
Future<ExtractResult> extractQuestions(
  ExtractChunk chunk, {
  required AiUsage usage,
  required AiTier tier,
  String subject = '',
  String grade = '',
  String sourceName = '',
  bool solve = true,
  http.Client? client,
  String? url,
}) async {
  final base = (url ?? aiServiceUrl).trim();
  if (base.isEmpty) {
    throw AiException(tr('Soru üretme hizmeti henüz açılmadı. Yakında kullanılabilecek.'));
  }
  if (usage.remaining(tier) < 1) {
    throw AiException(quotaMessage(tier), quota: true);
  }
  final raws = [...chunk.pages, if (chunk.keyPage != null) chunk.keyPage!];
  final images = raws.isEmpty ? const <String>[] : await Isolate.run(() => [for (final b in raws) base64Encode(shrinkForAi(b))]);

  final c = client ?? http.Client();
  http.Response r;
  try {
    r = await c
        .post(
          Uri.parse('${base.replaceAll(RegExp(r'/+$'), '')}/uret'),
          headers: {
            'content-type': 'application/json',
            'x-netice-app': 'netice-app-1',
            'x-netice-device': usage.device,
          },
          body: jsonEncode(extractRequestBody(chunk, images: images, subject: subject, grade: grade, title: sourceName, solve: solve)),
        )
        .timeout(const Duration(seconds: 300));
  } on SocketException {
    throw AiException(tr('İnternet bağlantısı yok. Soru üretmek için internete bağlanın.'));
  } on http.ClientException {
    throw AiException(tr('İnternet bağlantısı yok. Soru üretmek için internete bağlanın.'));
  } catch (_) {
    throw AiException(tr('Sunucu zamanında yanıt vermedi. Biraz sonra yeniden deneyin.'));
  } finally {
    if (client == null) c.close();
  }

  Map<String, dynamic> j;
  try {
    j = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
  } catch (_) {
    throw AiException(tr('Sunucudan beklenmeyen yanıt geldi. Biraz sonra yeniden deneyin.'));
  }
  if (r.statusCode != 200) {
    final code = j['error'];
    if (code == 'quota') usage.syncServer((j['used'] as num?)?.toInt() ?? AiUsage.aiMonthlyLimit);
    throw AiException(
      switch (code) {
        'quota' => tr('Bu ayki soru üretme hakkınız doldu. Gelecek ay yenilenir.'),
        'busy' => tr('Hizmet şu an çok yoğun. Biraz sonra yeniden deneyin.'),
        'too_short' => tr('Bu bölümde okunabilir yazı yok.'),
        'refused' => tr('Bu belgeden soru ayıklanamadı.'),
        'incomplete' => tr('Yanıt yarım kaldı. Biraz sonra yeniden deneyin.'),
        'not_configured' => tr('Soru üretme hizmeti henüz açılmadı. Yakında kullanılabilecek.'),
        // Eski sunucu "extract" modunu tanımaz.
        'bad_count' => tr('Soru sunucusu bu özelliği henüz desteklemiyor. Biraz sonra yeniden deneyin.'),
        _ => tr('Sorular ayıklanamadı. Biraz sonra yeniden deneyin.'),
      },
      quota: code == 'quota',
    );
  }
  final page = chunk.pages.length == 1 ? chunk.pages.first : null;
  final result = parseExtractResponse(j, subject: subject, grade: grade, sourceName: sourceName, page: page);
  usage.record(result.cost, tier);
  final used = (j['used'] as num?)?.toInt();
  if (used != null) usage.syncServer(used);
  return result;
}
