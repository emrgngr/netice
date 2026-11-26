// Kitapçık planı: soruların ana (A) sırası, her kitapçığın soru ve şık
// karışımı, cevap anahtarları ve okunabilir sınava dönüştürme.

import 'dart:math' as math;

import '../core/models.dart';
import '../omr/kid_layout.dart';
import 'bank_models.dart';
import 'bank_store.dart';

/// Bir kitapçıkta basılan soru: hangi banka sorusu, hangi şık sırası.
class PrintedQuestion {
  final BankQuestion question;

  /// Kitapçıktaki numarası (1'den; test ve klasik kısım ayrı numaralanır).
  final int no;

  /// Şıkların basılı sırası: [i]. basılı şık, sorunun [order[i]]. şıkkı.
  final List<int> choiceOrder;

  /// Basılı sıradaki doğru şık(lar).
  final Set<int> printedCorrect;

  /// Bu sorunun puanı.
  final double points;

  const PrintedQuestion({
    required this.question,
    required this.no,
    required this.choiceOrder,
    required this.printedCorrect,
    required this.points,
  });

  /// Basılı sıradaki şık metinleri.
  List<String> get choices => [for (final i in choiceOrder) i < question.choices.length ? question.choices[i] : ''];
}

/// Bir kitapçık türü (A, B, C…).
class BookletVariant {
  final int index;
  final List<PrintedQuestion> test;
  final List<PrintedQuestion> open;
  const BookletVariant(this.index, this.test, this.open);

  String get letter => Exam.bookletLetter(index);
}

class BookletPlan {
  /// Ana (A) sırada sorular: önce optik okunanlar, sonra klasik/boşluk doldurma.
  final List<BankQuestion> testMaster;
  final List<BankQuestion> openMaster;
  final List<BookletVariant> variants;
  final BookletOptions options;

  /// Test kısmının şık sayısı (optik form: 4 ya da 5).
  final int choiceCount;

  /// Ana sıradaki puanlar.
  final List<double> testPoints;
  final List<double> openPoints;

  BookletPlan._(this.testMaster, this.openMaster, this.variants, this.options, this.choiceCount, this.testPoints, this.openPoints);

  int get questionCount => testMaster.length + openMaster.length;

  /// Köşedeki küçük cevap kutusuyla okunur mu? (Çocuk şablonu, en çok 30 test sorusu.)
  bool get kidBox => options.kids && testMaster.isNotEmpty && testMaster.length <= KidLayout.maxQuestions;

  /// Çoktan seçmeli şıklarda "Hepsi", "Hiçbiri" gibi sona ait şıklar.
  static final _anchored = RegExp(
      r'(hepsi|hiçbiri|hicbiri|yukarıdaki|yukaridaki|all of the above|none of the above|both|alle|keine|todas|ninguna|все|ни одн|tutti|nessun|toutes|aucune|以上|以上都|上記)',
      caseSensitive: false);

  static List<int> _shuffleChoices(BankQuestion q, math.Random rnd) {
    final n = q.optionCount;
    final order = List.generate(n, (i) => i);
    if (!q.shufflableChoices) return order;
    // Sondaki "hepsi / hiçbiri" şıkları yerinde kalır.
    var fixedFrom = n;
    while (fixedFrom > 0 && _anchored.hasMatch(q.choices[fixedFrom - 1])) {
      fixedFrom--;
    }
    final head = order.sublist(0, fixedFrom)..shuffle(rnd);
    return [...head, ...order.sublist(fixedFrom)];
  }

  /// [questions] seçilen sorular (öğretmenin sırasıyla).
  factory BookletPlan.build(List<BankQuestion> questions, BookletOptions o) {
    final sorted = BankStore.sortQuestions(questions, o.order, seed: o.seed);
    // Eşleştirme, tablo ve kelime havuzu her maddesiyle ayrı optik satır olur;
    // sıralama sorusunun şıkları burada üretilir.
    final test = [for (final q in sorted.where((q) => q.type.optical)) ...q.expanded(kids: o.kids)];
    final open = sorted.where((q) => !q.type.optical).toList();
    // Çocuk şablonunda şık sayısı soruların kendisinden gelir (genellikle 3: A, B, C).
    final choiceCount = o.kids
        ? test.fold(2, (m, q) => math.max(m, q.optionCount)).clamp(2, 5)
        : (test.any((q) => q.optionCount >= 5) ? 5 : 4);

    // Puanlar: eşit bölüştür ya da her sorunun kendi puanı, toplam = totalScore.
    final all = [...test, ...open];
    List<double> pts;
    if (all.isEmpty) {
      pts = const [];
    } else if (o.equalPoints) {
      pts = _evenSplit(o.totalScore, all.length);
    } else {
      final w = all.fold(0.0, (a, q) => a + (q.points <= 0 ? 1 : q.points));
      pts = [for (final q in all) o.totalScore * (q.points <= 0 ? 1 : q.points) / w];
      pts = [for (final p in pts) (p * 100).round() / 100];
    }
    final testPts = pts.take(test.length).toList();
    final openPts = pts.skip(test.length).toList();

    final variants = <BookletVariant>[];
    // Çocuk şablonunda tek kitapçık: köşedeki kutuda kitapçık dairesi yoktur.
    final count = o.kids ? 1 : o.bookletCount.clamp(1, Exam.maxBooklets);
    for (var b = 0; b < count; b++) {
      final rnd = math.Random(o.seed * 7919 + b * 104729);
      var order = List.generate(test.length, (i) => i);
      if (b > 0 && o.shuffleQuestions) {
        // Bir grubun maddeleri (eşleştirme vb.) birlikte ve kendi sırasıyla kalır.
        final units = <List<int>>[];
        for (final i in order) {
          final g = test[i].parent;
          if (g != null && g.type.grouped && units.isNotEmpty && test[units.last.last].parent == g) {
            units.last.add(i);
          } else {
            units.add([i]);
          }
        }
        if (o.shuffleWithinSections) {
          // Her dersin soruları kendi bölümünde karışır.
          final groups = <String, List<List<int>>>{};
          for (final u in units) {
            groups.putIfAbsent(test[u.first].subject, () => []).add(u);
          }
          order = [for (final g in groups.values) ...(g..shuffle(rnd)).expand((u) => u)];
        } else {
          order = (units..shuffle(rnd)).expand((u) => u).toList();
        }
        // Karışım A ile aynı çıktıysa (az soru) bir birim kaydır.
        if (units.length > 1 && List.generate(order.length, (i) => i).toString() == order.toString()) {
          final first = order.takeWhile((i) => units.first.contains(i)).length;
          order = [...order.sublist(first), ...order.sublist(0, first)];
        }
      }
      final printed = <PrintedQuestion>[];
      for (var i = 0; i < order.length; i++) {
        final q = test[order[i]];
        final co = b > 0 && o.shuffleChoices ? _shuffleChoices(q, rnd) : List.generate(q.optionCount, (k) => k);
        printed.add(PrintedQuestion(
          question: q,
          no: i + 1,
          choiceOrder: co,
          printedCorrect: {for (final c in q.correct) co.indexOf(c)}..remove(-1),
          points: testPts[order[i]],
        ));
      }
      final opens = [
        for (var i = 0; i < open.length; i++)
          PrintedQuestion(question: open[i], no: i + 1, choiceOrder: const [], printedCorrect: const {}, points: openPts[i]),
      ];
      variants.add(BookletVariant(b, printed, opens));
    }
    return BookletPlan._(test, open, variants, o, choiceCount, testPts, openPts);
  }

  static List<double> _evenSplit(double total, int n) {
    // Yüzde birlik hassasiyetle; kalan ilk sorulara dağıtılır.
    final cents = (total * 100).round();
    final base = cents ~/ n;
    var left = cents - base * n;
    return [
      for (var i = 0; i < n; i++) (base + (left-- > 0 ? 1 : 0)) / 100,
    ];
  }

  /// Kitapçıklardan okunabilir bir sınav oluşturur.
  Exam toExam({required String id, required String name, required String className, DateTime? date, String? commonId}) {
    final qs = [
      for (var i = 0; i < testMaster.length; i++)
        Question(
          no: i + 1,
          correct: testMaster[i].correct,
          points: testPoints[i],
          outcomeCode: _code(testMaster[i]),
          bankId: testMaster[i].parent?.id ?? testMaster[i].id,
          misconceptions: {
            for (var c = 0; c < testMaster[i].misconceptions.length; c++)
              if (testMaster[i].misconceptionOf(c).isNotEmpty) c: testMaster[i].misconceptionOf(c)
          },
        ),
    ];
    final orders = <List<int>>[];
    final choiceOrders = <List<List<int>>>[];
    var anyChoice = false;
    for (final v in variants.skip(1)) {
      orders.add([for (final p in v.test) testMaster.indexOf(p.question)]);
      final co = [
        for (final p in v.test)
          p.choiceOrder.asMap().entries.every((e) => e.key == e.value) ? <int>[] : p.choiceOrder,
      ];
      if (co.any((c) => c.isNotEmpty)) anyChoice = true;
      choiceOrders.add(co);
    }
    final openMax = openPoints.fold(0.0, (a, b) => a + b);
    final testMax = testPoints.fold(0.0, (a, b) => a + b);
    return Exam(
      id: id,
      name: name,
      className: className,
      date: date ?? options.date ?? DateTime.now(),
      choiceCount: choiceCount,
      questions: qs,
      rule: ScoringRule(
        wrongsPerCorrect: options.wrongsPerCorrect,
        maxScore: ((testMax + openMax) * 100).round() / 100,
      ),
      bookletOrders: orders,
      bookletChoiceOrders: anyChoice ? choiceOrders : const [],
      kidForm: kidBox,
      kidReports: options.kids,
      kidTheme: options.kidTheme,
      openQuestions: [
        for (var i = 0; i < openMaster.length; i++)
          OpenQuestion(label: _openLabel(openMaster[i], i), maxPoints: openPoints[i], bankId: openMaster[i].id),
      ],
    );
  }

  static String? _code(BankQuestion q) {
    final t = q.topicLabel;
    return t.isEmpty ? null : t;
  }

  static String _openLabel(BankQuestion q, int i) {
    final t = q.topicLabel;
    return t.isEmpty ? 'K${i + 1}' : 'K${i + 1} · $t';
  }
}
