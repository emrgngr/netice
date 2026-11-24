// Nottan soru üretme: ders notunun metni ve görselleri Netice'nin küçük
// sunucusuna gönderilir; sunucu yapay zekâyla (Claude) çoktan seçmeli soru
// önerir. Öneriler bankaya kendiliğinden eklenmez, öğretmen seçip ekler.
//
// Uygulamanın yalnız bu özelliği internet kullanır. API anahtarı uygulamada
// değil, sunucudadır (sunucu/soru-uretici).

import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

import '../core/store.dart';
import '../l10n/l10n.dart';
import 'bank_models.dart';
import 'bank_store.dart';

/// Sunucu adresi. Derlemede `--dart-define=SORU_SERVIS_URL=…` ile değiştirilebilir.
const aiServiceUrl = String.fromEnvironment('SORU_SERVIS_URL', defaultValue: 'https://netice-soru.bilgi-7ff.workers.dev');
const _appKey = 'netice-app-1';

/// Sunucuya bir istekte sorulan en fazla soru. Daha fazlası istenirse
/// uygulama bunu 20'şerlik parçalara böler.
const aiMaxPerRequest = 20;

/// Kullanıcının bir seferde isteyebileceği en fazla soru.
const aiMaxTotal = 100;

enum AiDifficulty {
  mixed,
  easy,
  medium,
  hard;

  String get label => switch (this) {
        AiDifficulty.mixed => tr('Karışık'),
        AiDifficulty.easy => Difficulty.easy.label,
        AiDifficulty.medium => Difficulty.medium.label,
        AiDifficulty.hard => Difficulty.hard.label,
      };
}

class AiOptions {
  final int count;
  final int choices;
  final AiDifficulty difficulty;
  const AiOptions({this.count = 5, this.choices = 5, this.difficulty = AiDifficulty.mixed});
}

class AiResult {
  final List<BankQuestion> questions;

  /// Notla ilgili açıklama (ör. "not kısa, 3 soru yazılabildi"); yoksa boş.
  final String problem;
  const AiResult(this.questions, this.problem);
}

class AiException implements Exception {
  final String message;
  final bool quota;
  const AiException(this.message, {this.quota = false});
  @override
  String toString() => message;
}

/// Kota: ücretli Pro (abonelik, dönem paketi, kurum lisansı) ayda
/// [AiUsage.monthlyLimit] soru; diğer herkes toplam [AiUsage.trialLimit]
/// soruluk deneme hakkı. Sayaç cihazda tutulur; sunucu da cihaz başına
/// aylık sınır uygular.
class AiUsage extends ChangeNotifier {
  AiUsage._();
  static AiUsage instance = AiUsage._();

  @visibleForTesting
  factory AiUsage.forTest() => AiUsage._();

  static const monthlyLimit = 300;
  static const trialLimit = 20;

  String device = '';
  String month = '';
  int monthUsed = 0;
  int trialUsed = 0;

  /// Kullanıcı, notun sunucuya gönderileceğini bir kez onayladı mı?
  bool consent = false;

  File? _file;
  bool loaded = false;

  static String monthOf(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}';

  Future<void> load({Directory? dir}) async {
    if (loaded && dir == null) return;
    try {
      final base = dir ?? await getApplicationSupportDirectory();
      _file = File('${base.path}${Platform.pathSeparator}soru_uretici.json');
      if (await _file!.exists()) {
        final j = jsonDecode(await _file!.readAsString()) as Map<String, dynamic>;
        device = j['device'] as String? ?? '';
        month = j['month'] as String? ?? '';
        monthUsed = (j['monthUsed'] as num?)?.toInt() ?? 0;
        trialUsed = (j['trialUsed'] as num?)?.toInt() ?? 0;
        consent = j['consent'] as bool? ?? false;
      }
    } catch (_) {}
    if (device.isEmpty) {
      final r = math.Random.secure();
      device = List.generate(24, (_) => '0123456789abcdefghijklmnopqrstuvwxyz'[r.nextInt(36)]).join();
      await _save();
    }
    loaded = true;
    notifyListeners();
  }

  Future<void> _save() async {
    try {
      await _file?.parent.create(recursive: true);
      await _file?.writeAsString(jsonEncode({
        'device': device,
        'month': month,
        'monthUsed': monthUsed,
        'trialUsed': trialUsed,
        'consent': consent,
      }));
    } catch (_) {}
  }

  /// Bu cihazda aylık Pro kotası mı geçerli?
  static bool paid(AppStore s) =>
      AppStore.proFreeOnThisPlatform || s.hasSubscription || s.hasTermPass || s.hasLicense;

  int usedThisMonth([DateTime? now]) => month == monthOf(now ?? DateTime.now()) ? monthUsed : 0;

  int limit(bool paid) => paid ? monthlyLimit : trialLimit;

  int remaining(bool paid, [DateTime? now]) =>
      math.max(0, paid ? monthlyLimit - usedThisMonth(now) : trialLimit - trialUsed);

  void record(int n, bool paid, [DateTime? now]) {
    if (n <= 0) return;
    final m = monthOf(now ?? DateTime.now());
    if (month != m) {
      month = m;
      monthUsed = 0;
    }
    monthUsed += n;
    if (!paid) trialUsed += n;
    _save();
    notifyListeners();
  }

  /// Sunucunun bildirdiği aylık kullanım (cihazdaki sayaçtan büyükse).
  void syncServer(int used, [DateTime? now]) {
    final m = monthOf(now ?? DateTime.now());
    if (month != m) {
      month = m;
      monthUsed = 0;
    }
    if (used > monthUsed) {
      monthUsed = used;
      _save();
      notifyListeners();
    }
  }

  void giveConsent() {
    consent = true;
    _save();
    notifyListeners();
  }
}

/// Görseli sunucuya uygun boyuta getirir (en uzun kenar 1568 px, JPEG).
Uint8List shrinkForAi(Uint8List bytes) {
  final im = img.decodeImage(bytes);
  if (im == null) return bytes;
  const maxSide = 1568;
  final big = math.max(im.width, im.height);
  final out = big > maxSide
      ? img.copyResize(im,
          width: im.width >= im.height ? maxSide : null,
          height: im.height > im.width ? maxSide : null,
          interpolation: img.Interpolation.average)
      : im;
  return Uint8List.fromList(img.encodeJpg(out, quality: 82));
}

/// Sunucuya gidecek istek gövdesi.
Map<String, dynamic> aiRequestBody(BankNote note, AiOptions o, {List<String> images = const [], List<String> avoid = const []}) => {
      'count': o.count,
      'choices': o.choices,
      'difficulty': o.difficulty.name,
      'lang': L10n.code,
      'avoid': avoid,
      'note': {
        'title': note.title,
        'subject': note.subject,
        'grade': note.grade,
        'topic': note.topic,
        'outcome': note.outcome,
        'text': note.body.length > 60000 ? note.body.substring(0, 60000) : note.body,
        'images': [for (final d in images) {'type': 'image/jpeg', 'data': d}],
      },
    };

/// Sunucu yanıtını bankaya eklenebilecek taslak sorulara çevirir.
AiResult parseAiResponse(Map<String, dynamic> j, BankNote note, BankStore store, {DateTime? now}) {
  final t = now ?? DateTime.now();
  final tag = tr('yapay zekâ');
  final list = <BankQuestion>[];
  for (final raw in (j['questions'] as List?) ?? const []) {
    if (raw is! Map) continue;
    final choices = [for (final c in (raw['choices'] as List?) ?? const []) '$c'];
    final correct = (raw['correct'] as num?)?.toInt() ?? -1;
    final text = '${raw['text'] ?? ''}'.trim();
    if (text.isEmpty || choices.length < 2 || correct < 0 || correct >= choices.length) continue;
    // Yapay zekânın verdiği alt konu: notta konu varsa kazanım olarak,
    // yoksa konu olarak yazılır (cevap anahtarında konu dağılımı için).
    final sub = '${raw['topic'] ?? ''}'.trim();
    list.add(BankQuestion(
      id: BankStore.newId('q'),
      subject: note.subject,
      grade: note.grade,
      topic: note.topic.trim().isNotEmpty ? note.topic : sub,
      outcome: note.outcome.trim().isNotEmpty ? note.outcome : (note.topic.trim().isNotEmpty ? sub : ''),
      difficulty: switch (raw['difficulty']) {
        'easy' => Difficulty.easy,
        'hard' => Difficulty.hard,
        _ => Difficulty.medium,
      },
      type: QuestionType.multiple,
      text: text,
      choices: choices,
      choiceCount: choices.length,
      correct: {correct},
      solution: '${raw['solution'] ?? ''}'.trim(),
      tags: [...note.tags.where((x) => x != tag), tag],
      source: note.displayTitle,
      created: t,
      updated: t,
    ));
  }
  return AiResult(balanceAnswers(list, seed: t.microsecondsSinceEpoch), '${j['problem'] ?? ''}'.trim());
}

/// Doğru şıkları harflere eşit dağıtır (ör. 20 soru, 5 şık → her harf 4 kez).
/// Şıkların yeri değiştirilir; soru ve cevap anlamı aynı kalır.
List<BankQuestion> balanceAnswers(List<BankQuestion> qs, {int seed = 1}) {
  final rnd = math.Random(seed);
  final byCount = <int, List<int>>{};
  for (var i = 0; i < qs.length; i++) {
    final q = qs[i];
    if (q.type == QuestionType.multiple && q.choices.length >= 2 && q.correct.length == 1) {
      byCount.putIfAbsent(q.choices.length, () => []).add(i);
    }
  }
  final out = [...qs];
  byCount.forEach((n, idx) {
    final targets = [for (var k = 0; k < idx.length; k++) k % n]..shuffle(rnd);
    for (var k = 0; k < idx.length; k++) {
      final q = out[idx[k]];
      final from = q.correct.first, to = targets[k];
      if (from == to) continue;
      final ch = [...q.choices];
      final tmp = ch[from];
      ch[from] = ch[to];
      ch[to] = tmp;
      out[idx[k]] = q.copyWith(choices: ch, correct: {to});
    }
  });
  return out;
}

/// Notun metni ve görsellerinden soru önerileri ister.
Future<AiResult> generateAiQuestions(
  BankNote note,
  AiOptions o, {
  required BankStore store,
  required AiUsage usage,
  required bool paid,
  List<String> alsoAvoid = const [],
  http.Client? client,
  String? url,
}) async {
  final base = (url ?? aiServiceUrl).trim();
  if (base.isEmpty) {
    throw AiException(tr('Soru üretme hizmeti henüz açılmadı. Yakında kullanılabilecek.'));
  }
  if (usage.remaining(paid) < o.count) {
    throw AiException(
        paid
            ? tr('Bu ayki soru üretme hakkınız doldu. Gelecek ay yenilenir.')
            : tr('Deneme hakkınız doldu. Netice Pro ile her ay {0} soru üretebilirsiniz.', [AiUsage.monthlyLimit]),
        quota: true);
  }

  // Görseller (en fazla 6) küçültülüp gönderilir.
  final raws = [for (final id in note.imageIds.take(6)) store.imageBytes(id)].whereType<Uint8List>().toList();
  final images = raws.isEmpty ? const <String>[] : await Isolate.run(() => [for (final b in raws) base64Encode(shrinkForAi(b))]);
  if (note.body.trim().length < 40 && images.isEmpty) {
    throw AiException(tr('Not çok kısa. Soru üretmek için biraz daha metin ya da bir görsel ekleyin.'));
  }

  // Bankada bu konudaki sorular tekrar edilmesin.
  // Aynı seferde önceki parçalarda üretilenler de tekrar edilmesin.
  final avoid = [
    ...alsoAvoid.reversed,
    ...[
      for (final q in store.questions)
        if (q.topicLabel.isNotEmpty && q.topicLabel == note.topicLabel && q.text.trim().isNotEmpty) q.text.trim(),
    ].reversed,
  ].take(30).toList();

  final c = client ?? http.Client();
  http.Response r;
  try {
    r = await c
        .post(
          Uri.parse('${base.replaceAll(RegExp(r'/+$'), '')}/uret'),
          headers: {
            'content-type': 'application/json',
            'x-netice-app': _appKey,
            'x-netice-device': usage.device,
          },
          body: jsonEncode(aiRequestBody(note, o, images: images, avoid: avoid)),
        )
        .timeout(const Duration(seconds: 300));
  } on SocketException {
    throw AiException(tr('İnternet bağlantısı yok. Soru üretmek için internete bağlanın.'));
  } on http.ClientException {
    throw AiException(tr('İnternet bağlantısı yok. Soru üretmek için internete bağlanın.'));
  } catch (_) {
    throw AiException(tr('Sunucu zamanında yanıt vermedi. Daha az soruyla yeniden deneyin.'));
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
    if (code == 'quota') {
      usage.syncServer((j['used'] as num?)?.toInt() ?? AiUsage.monthlyLimit);
    }
    throw AiException(
      switch (code) {
        'quota' => tr('Bu ayki soru üretme hakkınız doldu. Gelecek ay yenilenir.'),
        'busy' => tr('Hizmet şu an çok yoğun. Biraz sonra yeniden deneyin.'),
        'too_short' => tr('Not çok kısa. Soru üretmek için biraz daha metin ya da bir görsel ekleyin.'),
        'refused' => tr('Bu nottan soru üretilemedi. Notun ders içeriği olduğundan emin olun.'),
        'incomplete' => tr('Yanıt yarım kaldı. Daha az soruyla yeniden deneyin.'),
        'not_configured' => tr('Soru üretme hizmeti henüz açılmadı. Yakında kullanılabilecek.'),
        _ => tr('Sorular üretilemedi. Biraz sonra yeniden deneyin.'),
      },
      quota: code == 'quota',
    );
  }
  final result = parseAiResponse(j, note, store);
  usage.record(result.questions.length, paid);
  final used = (j['used'] as num?)?.toInt();
  if (used != null) usage.syncServer(used);
  return result;
}
