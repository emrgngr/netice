/// Netice çekirdek veri modeli (MVP).
///
/// Ürün tasarım dokümanındaki varlıkların sadeleştirilmiş hâli: sınav,
/// soru, cevap anahtarı, öğrenci, öğrenci cevabı ve sonuç.
library;

import '../l10n/l10n.dart';

/// Bir sorunun öğrenci formundaki okunma durumu.
enum MarkState {
  /// Tek şık net biçimde işaretli.
  filled,

  /// Hiç işaret yok.
  blank,

  /// Birden çok şık işaretli (varsayılan: geçersiz, öğretmene sorulur).
  multiple,

  /// Doluluk oranı eşik bandında; öğretmen onayı gerekir.
  uncertain,
}

/// Bir sorunun nasıl değerlendirildiği.
enum Outcome { correct, wrong, blank, cancelled }

class Student {
  final String id;
  final String firstName;
  final String lastName;
  final String number;
  final String className;

  /// Velinin telefonu (isteğe bağlı; karneyi WhatsApp'tan göndermek için).
  /// Yalnızca bu cihazda tutulur; ortak sınav dosyalarına yazılmaz.
  final String parentPhone;

  /// Öğrencinin e-postası (isteğe bağlı). Google Classroom ve Moodle'a not
  /// aktarırken öğrenciyi kesin eşleştirmek için kullanılır.
  final String email;

  /// Velinin konuştuğu dil (uygulama dil kodu: 'ar', 'de'…). Boşsa karne
  /// uygulamanın dilinde hazırlanır.
  final String parentLanguage;

  /// Öğrencinin kişisel hedefi: başarı yüzdesi (0–100); yoksa null.
  final double? goal;

  const Student({
    required this.id,
    required this.firstName,
    required this.lastName,
    required this.number,
    required this.className,
    this.parentPhone = '',
    this.email = '',
    this.parentLanguage = '',
    this.goal,
  });

  Student copyWith({
    String? number,
    String? className,
    String? parentPhone,
    String? email,
    String? parentLanguage,
    double? goal,
    bool clearGoal = false,
  }) =>
      Student(
        id: id,
        firstName: firstName,
        lastName: lastName,
        number: number ?? this.number,
        className: className ?? this.className,
        parentPhone: parentPhone ?? this.parentPhone,
        email: email ?? this.email,
        parentLanguage: parentLanguage ?? this.parentLanguage,
        goal: clearGoal ? null : (goal ?? this.goal),
      );

  /// Çince ve Japonca adlar arasında boşluk bırakılmaz (王伟).
  String get fullName => _cjk.hasMatch(firstName) && _cjk.hasMatch(lastName) ? '$firstName$lastName' : '$firstName $lastName';
  static final _cjk = RegExp(r'^[\u3040-\u30FF\u3400-\u9FFF]+$');

  Map<String, dynamic> toJson() => {
        'id': id,
        'firstName': firstName,
        'lastName': lastName,
        'number': number,
        'className': className,
        if (parentPhone.isNotEmpty) 'parentPhone': parentPhone,
        if (email.isNotEmpty) 'email': email,
        if (parentLanguage.isNotEmpty) 'parentLanguage': parentLanguage,
        if (goal != null) 'goal': goal,
      };

  factory Student.fromJson(Map<String, dynamic> j) => Student(
        id: j['id'] as String,
        firstName: j['firstName'] as String,
        lastName: j['lastName'] as String,
        number: j['number'] as String,
        className: j['className'] as String,
        parentPhone: j['parentPhone'] as String? ?? '',
        email: j['email'] as String? ?? '',
        parentLanguage: j['parentLanguage'] as String? ?? '',
        goal: (j['goal'] as num?)?.toDouble(),
      );
}

class Question {
  /// 1'den başlayan soru numarası.
  final int no;

  /// Doğru kabul edilen şık indeksleri (0 = A). Birden çok olabilir.
  final Set<int> correct;
  final double points;
  final bool cancelled;
  final String? outcomeCode; // kazanım kodu

  /// Soru bankasından geldiyse bankadaki kimliği (analizler için).
  final String? bankId;

  /// Yanlış şıkların yakaladığı kavram yanılgıları (A sırasındaki şık → yanılgı).
  final Map<int, String> misconceptions;

  /// Sorunun düşünme düzeyi (yenilenmiş Bloom: remember, understand, apply,
  /// analyze, evaluate, create); bilinmiyorsa null.
  final String? cognitive;

  const Question({
    required this.no,
    required this.correct,
    this.points = 1,
    this.cancelled = false,
    this.outcomeCode,
    this.bankId,
    this.misconceptions = const {},
    this.cognitive,
  });

  /// [choice] şıkkının yanılgısı (doğru şıksa ya da yazılmamışsa boş).
  String misconceptionOf(int choice) => correct.contains(choice) ? '' : (misconceptions[choice] ?? '').trim();

  Question copyWith(
          {Set<int>? correct, double? points, bool? cancelled, String? outcomeCode, Map<int, String>? misconceptions, String? cognitive, bool clearCognitive = false}) =>
      Question(
        no: no,
        correct: correct ?? this.correct,
        points: points ?? this.points,
        cancelled: cancelled ?? this.cancelled,
        outcomeCode: outcomeCode ?? this.outcomeCode,
        bankId: bankId,
        misconceptions: misconceptions ?? this.misconceptions,
        cognitive: clearCognitive ? null : (cognitive ?? this.cognitive),
      );

  Map<String, dynamic> toJson() => {
        'no': no,
        'correct': correct.toList(),
        'points': points,
        'cancelled': cancelled,
        'outcomeCode': outcomeCode,
        if (bankId != null) 'bankId': bankId,
        if (misconceptions.values.any((m) => m.trim().isNotEmpty))
          'misconceptions': {for (final e in misconceptions.entries) if (e.value.trim().isNotEmpty) '${e.key}': e.value},
        if (cognitive != null) 'cognitive': cognitive,
      };

  factory Question.fromJson(Map<String, dynamic> j) => Question(
        no: j['no'] as int,
        correct: (j['correct'] as List).cast<int>().toSet(),
        points: (j['points'] as num).toDouble(),
        cancelled: j['cancelled'] as bool? ?? false,
        outcomeCode: j['outcomeCode'] as String?,
        bankId: j['bankId'] as String?,
        misconceptions: {
          for (final e in ((j['misconceptions'] as Map?) ?? const {}).entries)
            if (int.tryParse('${e.key}') != null) int.parse('${e.key}'): '${e.value}'
        },
        cognitive: j['cognitive'] as String?,
      );
}

/// Puanlama kuralı.
class ScoringRule {
  /// Kaç yanlış bir doğruyu götürür. 0 ise götürme yok (ör. 4 → 4Y = 1D).
  final int wrongsPerCorrect;

  /// Tam puan (ham puan bu değere ölçeklenir).
  final double maxScore;

  /// Geçme puanı (öğretmen belirler). Boşsa tam puanın yarısı.
  final double? passScore;

  const ScoringRule({this.wrongsPerCorrect = 0, this.maxScore = 100, this.passScore});

  double get pass => passScore ?? maxScore / 2;

  Map<String, dynamic> toJson() =>
      {'wrongsPerCorrect': wrongsPerCorrect, 'maxScore': maxScore, if (passScore != null) 'passScore': passScore};

  factory ScoringRule.fromJson(Map<String, dynamic> j) => ScoringRule(
        wrongsPerCorrect: j['wrongsPerCorrect'] as int? ?? 0,
        maxScore: (j['maxScore'] as num?)?.toDouble() ?? 100,
        passScore: (j['passScore'] as num?)?.toDouble(),
      );
}

/// Klasik (açık uçlu) soru: öğretmen elle puanlar.
/// Ölçütlü (rubrikli) puanlamada bir ölçüt: adı, puanı ve dört düzeyin
/// açıklamaları (Başlangıç, Gelişmekte, Yeterli, Örnek).
class RubricCriterion {
  final String name;
  final double maxPoints;

  /// Düzey açıklamaları (isteğe bağlı; [levelCount] tane).
  final List<String> descriptors;

  const RubricCriterion({required this.name, required this.maxPoints, this.descriptors = const []});

  static const levelCount = 4;

  static String levelLabel(int level) => switch (level) {
        0 => tr('Başlangıç'),
        1 => tr('Gelişmekte'),
        2 => tr('Yeterli'),
        _ => tr('Örnek'),
      };

  /// [level] düzeyinin puanı (0 = başlangıç … 3 = örnek).
  double pointsAt(int level) => level < 0 ? 0 : (maxPoints * (level + 1) / levelCount * 100).round() / 100;

  String descriptor(int level) => level >= 0 && level < descriptors.length ? descriptors[level].trim() : '';

  Map<String, dynamic> toJson() => {
        'name': name,
        'maxPoints': maxPoints,
        if (descriptors.any((d) => d.trim().isNotEmpty)) 'descriptors': descriptors,
      };

  factory RubricCriterion.fromJson(Map<String, dynamic> j) => RubricCriterion(
        name: j['name'] as String? ?? '',
        maxPoints: (j['maxPoints'] as num?)?.toDouble() ?? 1,
        descriptors: (j['descriptors'] as List?)?.cast<String>() ?? const [],
      );
}

class OpenQuestion {
  final String label;
  final double maxPoints;

  /// Soru bankasından geldiyse bankadaki kimliği.
  final String? bankId;

  /// Ölçütler (boşsa puan elle yazılır). Doluysa [maxPoints] ölçütlerin toplamıdır.
  final List<RubricCriterion> rubric;

  const OpenQuestion({required this.label, required this.maxPoints, this.bankId, this.rubric = const []});

  bool get hasRubric => rubric.isNotEmpty;

  Map<String, dynamic> toJson() => {
        'label': label,
        'maxPoints': maxPoints,
        if (bankId != null) 'bankId': bankId,
        if (rubric.isNotEmpty) 'rubric': [for (final c in rubric) c.toJson()],
      };
  factory OpenQuestion.fromJson(Map<String, dynamic> j) => OpenQuestion(
      label: j['label'] as String? ?? '',
      maxPoints: (j['maxPoints'] as num).toDouble(),
      bankId: j['bankId'] as String?,
      rubric: [for (final c in (j['rubric'] as List?) ?? const []) RubricCriterion.fromJson(c as Map<String, dynamic>)]);
}

/// Çocuk şablonunun renk teması (kitapçık, cevap kartları, karne, raporlar).
/// Renkler 0xAARRGGBB; ekran ve PDF aynı değerleri kullanır.
enum KidTheme {
  rainbow([0xFFFFE7A8, 0xFFFFD1DC, 0xFFCDEAFE], 0xFFE0567A, 0xFFF5F9FF,
      [0xFFFF8A5B, 0xFF4CB6E8, 0xFF7CC25A, 0xFFB38AE6, 0xFFF6B632, 0xFFEF6F9A]),
  forest([0xFFE3F4C8, 0xFFC9EBD6, 0xFFFFF0C2], 0xFF2F8F4E, 0xFFF4FAF1,
      [0xFF7CC25A, 0xFF3FA66B, 0xFFF6B632, 0xFF9BC53D, 0xFFE8894A, 0xFF4CB6A0]),
  ocean([0xFFCDEFFB, 0xFFBFE3F5, 0xFFD7F2EC], 0xFF1E7FB8, 0xFFF1F8FD,
      [0xFF2E9BD6, 0xFF26B5A8, 0xFF5C7FE0, 0xFFF28B66, 0xFF3CC0E8, 0xFF7A9CF0]),
  space([0xFFDCD3FA, 0xFFCFDBFF, 0xFFFBD8EE], 0xFF7A4FD0, 0xFFF6F3FE,
      [0xFF8E6CEF, 0xFF5B8DEF, 0xFFEF6FB4, 0xFFF6B632, 0xFF4CB6E8, 0xFFB38AE6]);

  const KidTheme(this.gradient, this.accent, this.soft, this.badges);

  /// Başlık bandının üç rengi (soldan sağa).
  final List<int> gradient;

  /// Vurgu rengi (soru sayısı, puan, övgü).
  final int accent;

  /// Bölüm kutularının zemini.
  final int soft;

  /// Soru numarası rozetleri ve grafik çubukları.
  final List<int> badges;

  String get label => switch (this) {
        KidTheme.rainbow => tr('Gökkuşağı'),
        KidTheme.forest => tr('Orman'),
        KidTheme.ocean => tr('Deniz'),
        KidTheme.space => tr('Uzay'),
      };

  static KidTheme byName(Object? name) => KidTheme.values.asNameMap()[name] ?? KidTheme.rainbow;
}

/// Çok dersli deneme sınavında bir ders bölümü: A kitapçığındaki ardışık
/// [count] soru ([start]'tan başlayarak, 0'dan) ve ağırlıklı puandaki katsayısı.
class ExamSection {
  final String name;
  final int start;
  final int count;

  /// Ağırlıklı puanda bu dersin bir netinin değeri (ör. 3,3). 0 = puana katılmaz.
  final double weight;

  const ExamSection({required this.name, required this.start, required this.count, this.weight = 0});

  int get end => start + count;

  bool contains(int i) => i >= start && i < end;

  Map<String, dynamic> toJson() => {'name': name, 'start': start, 'count': count, if (weight != 0) 'weight': weight};

  factory ExamSection.fromJson(Map<String, dynamic> j) => ExamSection(
        name: j['name'] as String? ?? '',
        start: j['start'] as int? ?? 0,
        count: j['count'] as int? ?? 0,
        weight: (j['weight'] as num?)?.toDouble() ?? 0,
      );

  /// Adlar ve soru sayılarından ardışık bölümler kurar.
  static List<ExamSection> fromCounts(List<(String, int, double)> parts) {
    var at = 0;
    return [
      for (final p in parts) ExamSection(name: p.$1, start: (at += p.$2) - p.$2, count: p.$2, weight: p.$3),
    ];
  }

  /// Bölümler geçerli mi? Ardışık, boşluksuz ve tam [questionCount] soruyu
  /// kapsamalı. Sorun varsa açıklaması, yoksa null.
  static String? validate(List<ExamSection> sections, int questionCount) {
    if (sections.isEmpty) return null;
    var at = 0;
    for (final s in sections) {
      if (s.name.trim().isEmpty) return tr('Her dersin bir adı olmalı.');
      if (s.count <= 0) return tr('"{0}" dersinin soru sayısı en az 1 olmalı.', [s.name.trim()]);
      if (s.start != at) return tr('Ders bölümleri ardışık olmalı.');
      at = s.end;
    }
    if (at != questionCount) return tr('Derslerin soru sayıları toplamı {0}, sınavda {1} soru var.', [at, questionCount]);
    return null;
  }
}

class Exam {
  final String id;
  final String name;
  final String className;
  final DateTime date;

  /// 4 veya 5 (çocuk formunda 2–5).
  final int choiceCount;
  final List<Question> questions;
  final ScoringRule rule;

  /// Ek kitapçıklar (B, C, D…): [bookletOrders][k][i], (k+1). kitapçıktaki
  /// [i]. sorunun A kitapçığındaki karşılığıdır (0'dan). Şıklar aynı, yalnızca
  /// soru sırası değişik. Boş liste = tek kitapçık.
  final List<List<int>> bookletOrders;

  /// Kitapçıkların (B, C…) kendi cevap anahtarları, o kitapçığın basılı
  /// sırasıyla. Öğretmen her kitapçığın anahtarını ayrı girdiğinde (soruların
  /// A'daki karşılığı bilinmez) dolu olur; o kitapçığın sırası birebirdir ve
  /// kâğıtları bu anahtarla puanlanır. Boş = sıra eşlemesi kullanılır.
  final List<List<Set<int>>> bookletKeys;

  /// Şıkları da karıştırılmış kitapçıklar (soru bankasından basılanlar):
  /// [bookletChoiceOrders][k][i][c], (k+1). kitapçıkta [i]. basılı sorunun
  /// [c]. şıkkının A'daki karşılığı. Boş liste = şıklar A ile aynı.
  final List<List<List<int>>> bookletChoiceOrders;

  /// Bir sınavda en fazla kaç kitapçık türü olabilir (A–H).
  static const maxBooklets = 8;

  /// Klasik sorular. Varsa tam puan = test kısmı + klasik kısım; test kısmı
  /// (tam puan − klasik toplamı) üzerinden ölçeklenir.
  final List<OpenQuestion> openQuestions;

  /// Başka firma formu kullanılıyorsa şablonun kimliği; null = Netice formu.
  final String? templateId;

  /// Ortak sınav kimliği: farklı öğretmenlerin farklı şubelerde okuduğu aynı
  /// sınavın kopyaları bu kimliği paylaşır. null = yalnız bu sınıfın sınavı.
  final String? commonId;

  /// Formdaki öğrenci numarası hane sayısı (6 ya da 10). Eski sınavlar 6.
  final int numberDigits;

  /// Çocuk (ilkokul) kitapçığının köşesindeki küçük cevap kutusuyla okunur.
  /// Bu sınavlarda şık sayısı 2–5 olabilir (genellikle 3: A, B, C).
  final bool kidForm;

  /// Raporlar (karne, sınıf raporu) çocuk şablonuyla hazırlanır. Çocuk
  /// kitapçığından oluşan sınavlarda açıktır; ayarlardan da açılabilir.
  final bool kidReports;

  /// Çocuk görünümlü raporlar kullanılsın mı?
  bool get kidStyle => kidForm || kidReports;

  /// Çocuk görünümünün renk teması.
  final KidTheme kidTheme;

  /// Çok dersli deneme sınavının ders bölümleri (boş = tek ders).
  final List<ExamSection> sections;

  /// Ağırlıklı puanın taban puanı (ör. 100). null = ağırlıklı puan yok;
  /// doluysa puan = taban + Σ(ders neti × katsayı).
  final double? baseScore;

  const Exam({
    required this.id,
    required this.name,
    required this.className,
    required this.date,
    required this.choiceCount,
    required this.questions,
    this.rule = const ScoringRule(),
    this.bookletOrders = const [],
    this.bookletKeys = const [],
    this.bookletChoiceOrders = const [],
    this.openQuestions = const [],
    this.templateId,
    this.commonId,
    this.numberDigits = 10,
    this.kidForm = false,
    this.kidReports = false,
    this.kidTheme = KidTheme.rainbow,
    this.sections = const [],
    this.baseScore,
  });

  /// Çok dersli deneme sınavı mı (en az iki ders bölümü)?
  bool get isMultiSubject => sections.length > 1;

  /// Ağırlıklı (katsayılı) puan hesaplanır mı?
  bool get hasWeightedScore => isMultiSubject && baseScore != null;

  /// A sırasındaki [i]. sorunun dersi (bölüm yoksa null).
  ExamSection? sectionOf(int i) {
    for (final s in sections) {
      if (s.contains(i)) return s;
    }
    return null;
  }

  bool get isCommon => commonId != null;

  int get questionCount => questions.length;

  bool get hasOpen => openQuestions.isNotEmpty;
  double get openMax => openQuestions.fold(0.0, (a, q) => a + q.maxPoints);

  /// Test (optik) kısmın tam puanı.
  double get testMax => (rule.maxScore - openMax).clamp(0, rule.maxScore).toDouble();

  bool get hasBooklets => bookletOrders.isNotEmpty;

  /// Kitapçık türü sayısı (tek kitapçıkta 1).
  int get bookletCount => 1 + bookletOrders.length;

  /// Kitapçığın harfi (0 = A).
  static String bookletLetter(int b) => String.fromCharCode(65 + b);

  /// [booklet] kitapçığının kendi cevap anahtarı var mı?
  bool hasOwnKey(int booklet) =>
      booklet > 0 && booklet <= bookletKeys.length && bookletKeys[booklet - 1].length == questions.length;

  /// [booklet] kitapçığındaki kâğıtların [i]. cevabı (A sırasıyla saklanmış)
  /// hangi soruyla puanlanır? Kendi anahtarı olan kitapçıkta doğru şık o
  /// kitapçığın anahtarından gelir; puan, iptal ve kazanım A'dakiyle aynıdır.
  Question questionAt(int booklet, int i) {
    final q = questions[i];
    if (!hasOwnKey(booklet)) return q;
    final k = bookletKeys[booklet - 1][i];
    return k.isEmpty ? q : q.copyWith(correct: k);
  }

  /// [booklet] kitapçığındaki [i]. sorunun A'daki karşılığı.
  int masterIndex(int booklet, int i) {
    if (booklet <= 0 || booklet > bookletOrders.length) return i;
    final o = bookletOrders[booklet - 1];
    return i < o.length ? o[i] : i;
  }

  /// A'daki [aIndex]. soru [booklet] kitapçığında kaçıncı sırada basılı?
  int printedIndex(int booklet, int aIndex) {
    if (booklet <= 0 || booklet > bookletOrders.length) return aIndex;
    final b = bookletOrders[booklet - 1].indexOf(aIndex);
    return b < 0 ? aIndex : b;
  }

  /// [booklet] kitapçığında [printed]. sorunun şık eşlemesi (basılı → A);
  /// şıklar karıştırılmamışsa null.
  List<int>? _choiceMap(int booklet, int printed) {
    if (booklet <= 0 || booklet > bookletChoiceOrders.length) return null;
    final m = bookletChoiceOrders[booklet - 1];
    if (printed < 0 || printed >= m.length || m[printed].isEmpty) return null;
    return m[printed];
  }

  /// A'daki [aIndex]. sorunun A'daki [masterChoice] şıkkı [booklet]
  /// kitapçığında hangi şık olarak basılı?
  int printedChoice(int booklet, int aIndex, int masterChoice) {
    final m = _choiceMap(booklet, printedIndex(booklet, aIndex));
    if (m == null) return masterChoice;
    final c = m.indexOf(masterChoice);
    return c < 0 ? masterChoice : c;
  }

  /// [booklet] kitapçığının cevap anahtarı (o kitapçığın sırasıyla).
  List<Question> questionsOf(int booklet) {
    if (hasOwnKey(booklet)) return [for (var i = 0; i < questions.length; i++) questionAt(booklet, i)];
    if (booklet <= 0 || booklet > bookletOrders.length) return questions;
    final order = bookletOrders[booklet - 1];
    return [
      for (var i = 0; i < order.length; i++)
        Question(
          no: i + 1,
          correct: {for (final c in questions[order[i]].correct) printedChoice(booklet, order[i], c)},
          points: questions[order[i]].points,
          cancelled: questions[order[i]].cancelled,
          outcomeCode: questions[order[i]].outcomeCode,
          bankId: questions[order[i]].bankId,
          misconceptions: {
            for (final e in questions[order[i]].misconceptions.entries) printedChoice(booklet, order[i], e.key): e.value
          },
          cognitive: questions[order[i]].cognitive,
        ),
    ];
  }

  /// [booklet] kitapçığının cevaplarını A sırasına (ve şıklar karıştırılmışsa
  /// A'nın şıklarına) çevirir.
  List<Answer> toMasterOrder(int booklet, List<Answer> b) {
    if (booklet <= 0 || booklet > bookletOrders.length) return b;
    final order = bookletOrders[booklet - 1];
    final a = List<Answer>.filled(questions.length, const Answer.blank());
    for (var i = 0; i < order.length && i < b.length; i++) {
      final m = _choiceMap(booklet, i);
      a[order[i]] = m == null
          ? b[i]
          : Answer(b[i].state, {for (final c in b[i].marked) c < m.length ? m[c] : c}, confirmed: b[i].confirmed);
    }
    return a;
  }

  /// "3, 1, 2, …" biçimindeki sırayı çözer; 1..n'in tam bir permütasyonu değilse null.
  static List<int>? parseBookletOrder(String text, int n) {
    final parts = text.split(RegExp(r'[^0-9]+')).where((e) => e.isNotEmpty).map(int.parse).toList();
    if (parts.length != n) return null;
    final set = parts.toSet();
    if (set.length != n || set.any((v) => v < 1 || v > n)) return null;
    return [for (final v in parts) v - 1];
  }

  /// "ABCDA…" biçimindeki cevap anahtarından sınav oluşturur.
  factory Exam.fromKeyString({
    required String id,
    required String name,
    required String className,
    required String key,
    int choiceCount = 5,
    ScoringRule rule = const ScoringRule(),
    DateTime? date,
  }) {
    final qs = <Question>[];
    final letters = key.toUpperCase().replaceAll(RegExp(r'\s'), '');
    for (var i = 0; i < letters.length; i++) {
      final idx = letters.codeUnitAt(i) - 65;
      if (idx < 0 || idx >= choiceCount) {
        throw FormatException('Geçersiz şık "${letters[i]}" (soru ${i + 1})');
      }
      qs.add(Question(no: i + 1, correct: {idx}));
    }
    return Exam(
      id: id,
      name: name,
      className: className,
      date: date ?? DateTime.now(),
      choiceCount: choiceCount,
      questions: qs,
      rule: rule,
    );
  }

  Exam copyWith({
    List<Question>? questions,
    ScoringRule? rule,
    String? name,
    String? className,
    DateTime? date,
    List<List<int>>? bookletOrders,
    List<List<Set<int>>>? bookletKeys,
    List<List<List<int>>>? bookletChoiceOrders,
    List<OpenQuestion>? openQuestions,
    String? templateId,
    bool clearTemplate = false,
    String? id,
    String? commonId,
    int? numberDigits,
    bool? kidForm,
    bool? kidReports,
    KidTheme? kidTheme,
    List<ExamSection>? sections,
    double? baseScore,
    bool clearBaseScore = false,
  }) =>
      Exam(
        id: id ?? this.id,
        name: name ?? this.name,
        className: className ?? this.className,
        date: date ?? this.date,
        choiceCount: choiceCount,
        questions: questions ?? this.questions,
        rule: rule ?? this.rule,
        bookletOrders: bookletOrders ?? this.bookletOrders,
        bookletKeys: bookletKeys ?? this.bookletKeys,
        bookletChoiceOrders: bookletChoiceOrders ?? this.bookletChoiceOrders,
        openQuestions: openQuestions ?? this.openQuestions,
        templateId: clearTemplate ? null : (templateId ?? this.templateId),
        commonId: commonId ?? this.commonId,
        numberDigits: numberDigits ?? this.numberDigits,
        kidForm: kidForm ?? this.kidForm,
        kidReports: kidReports ?? this.kidReports,
        kidTheme: kidTheme ?? this.kidTheme,
        sections: sections ?? this.sections,
        baseScore: clearBaseScore ? null : (baseScore ?? this.baseScore),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'className': className,
        'date': date.toIso8601String(),
        'choiceCount': choiceCount,
        'questions': questions.map((q) => q.toJson()).toList(),
        'rule': rule.toJson(),
        if (bookletOrders.isNotEmpty) 'bookletOrders': bookletOrders,
        // Eski sürümler yalnız B'yi tanır.
        if (bookletOrders.isNotEmpty) 'bookletOrder': bookletOrders.first,
        if (bookletKeys.isNotEmpty)
          'bookletKeys': [
            for (final k in bookletKeys) [for (final c in k) c.toList()]
          ],
        if (bookletChoiceOrders.isNotEmpty) 'bookletChoiceOrders': bookletChoiceOrders,
        if (templateId != null) 'templateId': templateId,
        if (commonId != null) 'commonId': commonId,
        'numberDigits': numberDigits,
        if (kidForm) 'kidForm': true,
        if (kidReports) 'kidReports': true,
        if (kidTheme != KidTheme.rainbow) 'kidTheme': kidTheme.name,
        if (openQuestions.isNotEmpty) 'openQuestions': openQuestions.map((q) => q.toJson()).toList(),
        if (sections.isNotEmpty) 'sections': [for (final s in sections) s.toJson()],
        if (baseScore != null) 'baseScore': baseScore,
      };

  factory Exam.fromJson(Map<String, dynamic> j) => Exam(
        id: j['id'] as String,
        name: j['name'] as String,
        className: j['className'] as String,
        date: DateTime.parse(j['date'] as String),
        choiceCount: j['choiceCount'] as int,
        questions: (j['questions'] as List)
            .map((e) => Question.fromJson(e as Map<String, dynamic>))
            .toList(),
        rule: ScoringRule.fromJson(j['rule'] as Map<String, dynamic>),
        bookletOrders: j['bookletOrders'] is List
            ? [for (final o in j['bookletOrders'] as List) (o as List).map((e) => e as int).toList()]
            : [if (j['bookletOrder'] is List) (j['bookletOrder'] as List).map((e) => e as int).toList()],
        bookletKeys: [
          for (final k in (j['bookletKeys'] as List?) ?? const [])
            [for (final c in k as List) (c as List).map((e) => e as int).toSet()]
        ],
        bookletChoiceOrders: [
          for (final k in (j['bookletChoiceOrders'] as List?) ?? const [])
            [for (final q in k as List) (q as List).map((e) => e as int).toList()]
        ],
        templateId: j['templateId'] as String?,
        commonId: j['commonId'] as String?,
        // Alan yoksa eski sürümde basılmış 6 haneli formdur.
        numberDigits: j['numberDigits'] == 10 ? 10 : 6,
        kidForm: j['kidForm'] == true,
        kidReports: j['kidReports'] == true,
        kidTheme: KidTheme.byName(j['kidTheme']),
        openQuestions: [
          for (final e in (j['openQuestions'] as List?) ?? const []) OpenQuestion.fromJson(e as Map<String, dynamic>)
        ],
        sections: [for (final e in (j['sections'] as List?) ?? const []) ExamSection.fromJson(e as Map<String, dynamic>)],
        baseScore: (j['baseScore'] as num?)?.toDouble(),
      );
}

/// Bir sorunun öğrenci cevabı.
class Answer {
  final MarkState state;

  /// İşaretlenen şıklar (0 = A).
  final Set<int> marked;

  /// Öğretmen tarafından onaylandı/düzeltildi mi.
  final bool confirmed;

  const Answer(this.state, this.marked, {this.confirmed = false});

  const Answer.blank()
      : state = MarkState.blank,
        marked = const {},
        confirmed = false;

  factory Answer.choice(int i) => Answer(MarkState.filled, {i});

  bool get needsReview =>
      !confirmed &&
      (state == MarkState.uncertain || state == MarkState.multiple);

  Map<String, dynamic> toJson() => {
        'state': state.name,
        'marked': marked.toList(),
        'confirmed': confirmed,
      };

  factory Answer.fromJson(Map<String, dynamic> j) => Answer(
        MarkState.values.byName(j['state'] as String),
        (j['marked'] as List).cast<int>().toSet(),
        confirmed: j['confirmed'] as bool? ?? false,
      );
}

/// Bir öğrencinin bir sınavdaki cevap kâğıdı.
class Sheet {
  final String examId;
  final String? studentId;
  /// Cevaplar her zaman A kitapçığı sırasıyla saklanır.
  final List<Answer> answers;

  /// Öğrencinin kitapçığı (0 = A, 1 = B, 2 = C…).
  final int booklet;

  /// Klasik soru puanları (öğretmen girer; girilmeyen null).
  final List<double?> openScores;

  /// İşaretli kâğıt görüntüsünün dosya adı (cihazdaki kagitlar/ klasöründe).
  final String? imageId;

  /// Öğrenci eşleşmediğinde kâğıttan okunan numara ('?' = okunamayan rakam).
  final String? readNumber;

  /// Formun ad soyad alanından okunan ad (yalnızca başka firma formlarında).
  final String? readName;

  /// Başka firma formunun diğer kodlama alanlarından okunanlar
  /// (alan adı → değer; doğum tarihi, cinsiyet, sınıf…).
  final Map<String, String> fields;

  /// Kâğıt çeyrek A4 kısa quiz formuydu (işaretli görüntü buna göre çizilir).
  final bool mini;

  /// Ölçütlü klasik sorularda seçilen düzeyler: klasik soru sırası →
  /// ölçüt başına düzey (0–3; seçilmemiş −1).
  final Map<int, List<int>> rubricLevels;

  const Sheet({
    required this.examId,
    this.studentId,
    required this.answers,
    this.booklet = 0,
    this.openScores = const [],
    this.imageId,
    this.readNumber,
    this.readName,
    this.fields = const {},
    this.mini = false,
    this.rubricLevels = const {},
  });

  bool get needsReview =>
      studentId == null || answers.any((a) => a.needsReview);

  Sheet copyWith({
    String? studentId,
    List<Answer>? answers,
    List<double?>? openScores,
    String? imageId,
    Map<int, List<int>>? rubricLevels,
  }) =>
      Sheet(
        examId: examId,
        studentId: studentId ?? this.studentId,
        answers: answers ?? this.answers,
        booklet: booklet,
        openScores: openScores ?? this.openScores,
        imageId: imageId ?? this.imageId,
        readNumber: readNumber,
        readName: readName,
        fields: fields,
        mini: mini,
        rubricLevels: rubricLevels ?? this.rubricLevels,
      );

  Map<String, dynamic> toJson() => {
        'examId': examId,
        'studentId': studentId,
        'answers': answers.map((a) => a.toJson()).toList(),
        if (booklet != 0) 'booklet': booklet,
        if (openScores.isNotEmpty) 'openScores': openScores,
        if (imageId != null) 'imageId': imageId,
        if (readNumber != null) 'readNumber': readNumber,
        if (readName != null) 'readName': readName,
        if (fields.isNotEmpty) 'fields': fields,
        if (mini) 'mini': true,
        if (rubricLevels.isNotEmpty) 'rubricLevels': {for (final e in rubricLevels.entries) '${e.key}': e.value},
      };

  factory Sheet.fromJson(Map<String, dynamic> j) => Sheet(
        examId: j['examId'] as String,
        studentId: j['studentId'] as String?,
        answers: (j['answers'] as List)
            .map((e) => Answer.fromJson(e as Map<String, dynamic>))
            .toList(),
        booklet: j['booklet'] as int? ?? 0,
        openScores: [for (final v in (j['openScores'] as List?) ?? const []) (v as num?)?.toDouble()],
        imageId: j['imageId'] as String?,
        readNumber: j['readNumber'] as String?,
        readName: j['readName'] as String?,
        fields: {for (final e in ((j['fields'] as Map?) ?? const {}).entries) '${e.key}': '${e.value}'},
        mini: j['mini'] as bool? ?? false,
        rubricLevels: {
          for (final e in ((j['rubricLevels'] as Map?) ?? const {}).entries)
            if (int.tryParse('${e.key}') != null) int.parse('${e.key}'): (e.value as List).cast<int>()
        },
      );
}

/// Kurum türü: okul, üniversite/MYO, polis eğitim kurumları, askerî okullar,
/// kurslar ve diğer kurumlar. Başlık, imza unvanları ve grup adı buna göre gelir.
enum InstitutionType {
  school,
  university,
  police,
  military,
  course,
  other;

  static InstitutionType byName(String? n) =>
      InstitutionType.values.firstWhere((e) => e.name == n, orElse: () => InstitutionType.school);

  String get label => switch (this) {
        school => tr('Okul (ilkokul, ortaokul, lise)'),
        university => tr('Üniversite, fakülte, meslek yüksekokulu'),
        police => tr('Polis Akademisi'),
        military => tr('Askerî okul, askerî lise, harp okulu, askerî üniversite'),
        course => tr('Kurs, dershane, eğitim merkezi'),
        other => tr('Diğer kurum (şirket, kamu eğitimi)'),
      };

  /// Üst kurum için örnek.
  String get parentHint => switch (this) {
        school => '',
        university => tr('Örn. Ankara Üniversitesi Rektörlüğü'),
        police => tr('Örn. Polis Akademisi Başkanlığı'),
        military => tr('Örn. Millî Savunma Üniversitesi Rektörlüğü'),
        course => tr('Örn. Millî Eğitim Bakanlığı'),
        other => tr('Örn. Bakanlık ya da şirket adı'),
      };

  String get nameHint => switch (this) {
        school => tr('Örn. Atatürk Anadolu Lisesi'),
        university => tr('Örn. Sağlık Hizmetleri Meslek Yüksekokulu'),
        police => tr('Örn. Ankara Polis Meslek Eğitim Merkezi Müdürlüğü'),
        military => tr('Örn. Kara Harp Okulu Dekanlığı'),
        course => tr('Örn. Bilgi Kurs Merkezi'),
        other => tr('Örn. Eğitim Daire Başkanlığı'),
      };

  String get defaultHeadTitle => switch (this) {
        school => tr('Okul Müdürü'),
        university => tr('Müdür'),
        police => tr('Müdür'),
        military => tr('Komutan'),
        course => tr('Kurum Müdürü'),
        other => tr('Kurum Yöneticisi'),
      };

  /// Türkiye biçiminde başlık varsayılan olarak Valilik / Kaymakamlık
  /// altından mı başlar (MEB'e bağlı okul ve kurslar)?
  bool get defaultLocalChain => this == school || this == course;

  String get defaultInstructorTitle => switch (this) {
        school => tr('Ders Öğretmeni'),
        university => tr('Öğretim Elemanı'),
        police => tr('Öğretim Görevlisi'),
        military => tr('Öğretim Elemanı'),
        course => tr('Eğitmen'),
        other => tr('Eğitmen'),
      };

  String get defaultGroupLabel => switch (this) {
        school => tr('Sınıf'),
        university => tr('Sınıf'),
        police => tr('Sınıf'),
        military => tr('Bölük'),
        course => tr('Grup'),
        other => tr('Grup'),
      };
}

/// Kurum ve eğitici bilgileri. Raporlarda resmi yazı başlığı olarak kullanılır.
class SchoolInfo {
  final String province; // il / eyalet
  final String district; // ilçe / şehir
  final String name; // kurum adı
  final String principal; // kurum amiri (müdür, dekan, komutan…)
  final String teacher; // ders öğretmeni / eğitici
  final String subject; // ders / branş
  final InstitutionType type;

  /// Bağlı olduğu üst kurum (üniversite, Polis Akademisi Başkanlığı, MSÜ…).
  final String parent;
  final String country;

  /// Boşsa kurum türüne göre varsayılan kullanılır.
  final String headTitle;
  final String instructorTitle;
  final String groupLabel;

  /// Türkiye resmi yazı biçimi (T.C. ile başlar). null: uygulama diline göre.
  final bool? turkishFormat;

  /// Başlık Valilik / Kaymakamlık altından mı? null: kurum türüne göre.
  final bool? localHeader;

  /// Valilik / Kaymakamlık altındaki müdürlük ("Millî Eğitim Müdürlüğü";
  /// başına il/ilçe gelir). null: Millî Eğitim Müdürlüğü, boş: satır yok.
  final String? localUnit;

  /// Üst kurum ile kurum arasındaki ara birimler (fakülte, daire, komutanlık…).
  final List<String> units;

  /// Unvan listelerinin ülkesi (tr, en, de…). null: uygulama diline göre.
  final String? titleSystem;

  /// Raporların yazı tipi: netice, times, arial.
  final String fontFamily;

  /// Resmi başlığın punto ve karakteri.
  final double headerSize;
  final bool headerBold;
  final bool headerItalic;
  final bool headerUnderline;

  /// İmza alanının puntosu.
  final double signSize;

  /// Raporlarda resmi yazı başlığı ve imza alanı.
  final bool officialHeader;

  const SchoolInfo({
    this.province = '',
    this.district = '',
    this.name = '',
    this.principal = '',
    this.teacher = '',
    this.subject = '',
    this.type = InstitutionType.school,
    this.parent = '',
    this.country = '',
    this.headTitle = '',
    this.instructorTitle = '',
    this.groupLabel = '',
    this.turkishFormat,
    this.localHeader,
    this.localUnit,
    this.units = const [],
    this.titleSystem,
    this.fontFamily = 'netice',
    this.headerSize = 10.5,
    this.headerBold = true,
    this.headerItalic = false,
    this.headerUnderline = false,
    this.signSize = 9.5,
    this.officialHeader = true,
  });

  static const fontFamilies = ['netice', 'times', 'arial'];

  static String fontLabel(String f) => switch (f) {
        'times' => tr('Times New Roman benzeri (tırnaklı)'),
        'arial' => tr('Arial benzeri (sade)'),
        _ => tr('Netice (modern)'),
      };

  bool get isEmpty => name.trim().isEmpty;

  /// Resmi başlık kullanılacak mı?
  bool get official => officialHeader && !isEmpty;

  /// Büyük harf; Türkçe ve Azericede i → İ, ı → I.
  static String upper(String s) => L10n.code == 'tr' || L10n.code == 'az'
      ? s.replaceAll('i', 'İ').replaceAll('ı', 'I').toUpperCase()
      : s.toUpperCase();

  /// Başlık için büyük harf: Türkiye biçiminde (ve Azericede) i → İ; başka
  /// ülkelerin biçiminde dilin kendi kuralı (BERLIN, ROMA…).
  String _up(String s) => turkishStyle || L10n.code == 'az'
      ? s.replaceAll('i', 'İ').replaceAll('ı', 'I').toUpperCase()
      : s.toUpperCase();

  /// Türkiye'deki resmi yazı biçimi mi (T.C. ile başlayan)?
  bool get turkishStyle => turkishFormat ?? L10n.code == 'tr';

  String get headRole => headTitle.trim().isNotEmpty ? headTitle.trim() : type.defaultHeadTitle;

  String get instructorRole {
    if (instructorTitle.trim().isNotEmpty) return instructorTitle.trim();
    if (type == InstitutionType.school && subject.trim().isNotEmpty) return tr('{0} Öğretmeni', [subject.trim()]);
    return type.defaultInstructorTitle;
  }

  String get group => groupLabel.trim().isNotEmpty ? groupLabel.trim() : type.defaultGroupLabel;

  /// Başlıktaki grup ifadesi: okulda "9-A SINIFI", diğerlerinde "BÖLÜK: 3".
  String classLine(String className) {
    if (type == InstitutionType.school && groupLabel.trim().isEmpty) {
      return tr('{0} SINIFI', [upper(className)]);
    }
    return '${upper(group)}: ${upper(className)}';
  }

  /// Başlık Valilik / Kaymakamlık altından mı başlar (MEB okulları, kurslar,
  /// il emniyet müdürlüğü…)? Kapalıysa bakanlık ya da üst kurum altından başlar.
  bool get localChain => localHeader ?? type.defaultLocalChain;

  /// İlçe boş ya da "Merkez" ise il düzeyi (Valilik), değilse ilçe (Kaymakamlık).
  bool get provincial {
    final d = district.trim();
    return d.isEmpty || upper(d) == 'MERKEZ';
  }

  /// Başlığın ikinci satırı (idarenin adı, büyük harfle): "ANKARA VALİLİĞİ",
  /// "ÇANKAYA KAYMAKAMLIĞI" ya da üst kurum ("POLİS AKADEMİSİ BAŞKANLIĞI").
  /// Türkiye dışı biçimde yer bilgisi.
  String get authority {
    final d = district.trim(), p = province.trim();
    if (!turkishStyle) return [d, p, country.trim()].where((e) => e.isNotEmpty).map(_up).join(', ');
    if (!localChain) return upper(parent.trim());
    if (!provincial) return '${upper(d)} KAYMAKAMLIĞI';
    if (p.isNotEmpty) return '${upper(p)} VALİLİĞİ';
    return '';
  }

  /// Valilik / Kaymakamlık altındaki müdürlük: "İl Millî Eğitim Müdürlüğü",
  /// "İlçe Millî Eğitim Müdürlüğü", "İl Emniyet Müdürlüğü"… Boş: satır yok.
  String get localDirectorate {
    if (!turkishStyle || !localChain) return '';
    final u = (localUnit ?? defaultLocalUnit).trim();
    if (u.isEmpty) return '';
    final lower = u.toLowerCase();
    if (lower.startsWith('il ') || lower.startsWith('ilçe ') || lower.startsWith('i̇l ')) return titleCase(u);
    return '${provincial ? 'İl' : 'İlçe'} ${titleCase(u)}';
  }

  static const defaultLocalUnit = 'Millî Eğitim Müdürlüğü';

  /// Ara birimler (her biri ayrı satır, ilk harfleri büyük).
  List<String> get unitLines => [for (final u in units) if (u.trim().isNotEmpty) titleCase(u.trim())];

  /// Kurumun kendi satırı. Türkiye biçiminde ilk harfleri büyük (yönetmelik
  /// md. 10: birim adı ilk harfleri büyük, diğerleri küçük); okulda sonuna
  /// "Müdürlüğü" eklenir. Diğer ülkelerde büyük harf.
  String get directorate {
    final n = name.trim();
    if (n.isEmpty) return '';
    if (!turkishStyle) return _up(n);
    final t = titleCase(n);
    if (type != InstitutionType.school) return t;
    const ends = ['Müdürlüğü', 'Başkanlığı', 'Dekanlığı', 'Rektörlüğü', 'Komutanlığı', 'Müdürlük'];
    return ends.any(t.endsWith) ? t : '$t Müdürlüğü';
  }

  /// Resmi başlığın satırları, yukarıdan aşağıya. Türkiye biçimi, Resmî
  /// Yazışmalarda Uygulanacak Usul ve Esaslar Hakkında Yönetmelik md. 10'a
  /// göre: 1. satır "T.C.", 2. satır idarenin adı büyük harfle, alttaki
  /// satırlar birimler (hiyerarşi sırasıyla) ilk harfleri büyük.
  /// Örn. T.C. / ANKARA VALİLİĞİ / İl Millî Eğitim Müdürlüğü / Atatürk Lisesi Müdürlüğü.
  List<String> get letterhead => turkishStyle
      ? [
          'T.C.',
          if (authority.isNotEmpty) authority,
          if (localDirectorate.isNotEmpty) localDirectorate,
          ...unitLines,
          if (directorate.isNotEmpty) directorate,
        ]
      : [
          if (parent.trim().isNotEmpty) _up(parent.trim()),
          ...[for (final u in units) if (u.trim().isNotEmpty) _up(u.trim())],
          if (directorate.isNotEmpty) directorate,
          if (authority.isNotEmpty) authority,
        ];

  /// Kelimelerin ilk harfini büyütür ("atatürk anadolu lisesi" → "Atatürk
  /// Anadolu Lisesi"). Tümü büyük yazılmışsa önce küçültür. "ve", "ile",
  /// "veya" bağlaçları küçük kalır; "T.C.", "MEB", "PMYO" gibi kısaltmalar korunur.
  static String titleCase(String s) {
    String lo(String x) => x.replaceAll('I', 'ı').replaceAll('İ', 'i').toLowerCase();
    String up(String x) => x.replaceAll('i', 'İ').replaceAll('ı', 'I').toUpperCase();
    String bare(String x) => x.replaceAll(RegExp(r'[^A-Za-zÇĞİÖŞÜçğıöşüÂÎÛâîû]'), '');
    final letters = bare(s);
    final allUpper = letters.length > 3 && letters == up(letters);
    const small = {'ve', 'ile', 'veya'};
    const abbr = {'MEB', 'PMYO', 'MYO', 'MSÜ', 'POMEM', 'TSK', 'YÖK', 'JSGA', 'EGM', 'AB', 'ABD'};
    final words = s.split(' ');
    return [
      for (var i = 0; i < words.length; i++)
        () {
          final w = words[i], b = bare(w);
          if (w.isEmpty || b.isEmpty) return w;
          // Kısaltmalar olduğu gibi kalır.
          if (w.contains('.') || abbr.contains(b) || (!allUpper && b.length > 1 && b == up(b))) return w;
          final body = allUpper ? lo(w) : w;
          if (i > 0 && small.contains(lo(body))) return lo(body);
          return up(body.substring(0, 1)) + body.substring(1);
        }(),
    ].join(' ');
  }

  /// Eğitim-öğretim yılı: eylülden itibaren yeni yıl başlar (Japonyada
  /// nisandan başlar ve tek yılla yazılır).
  static String academicYear(DateTime d) {
    // Japonya ve Kore'de (nisan / mart) ve Brezilya'da (şubat) öğretim yılı
    // tek yılla yazılır; Hindistan'da nisanda, Endonezya'da temmuzda başlar.
    if (L10n.code == 'ja') return '${d.month >= 4 ? d.year : d.year - 1}';
    if (L10n.code == 'ko') return '${d.month >= 3 ? d.year : d.year - 1}';
    if (L10n.code == 'pt') return '${d.month >= 2 ? d.year : d.year - 1}';
    final startMonth = switch (L10n.code) { 'hi' => 4, 'id' => 7, _ => 9 };
    final start = d.month >= startMonth ? d.year : d.year - 1;
    return '$start-${start + 1}';
  }

  SchoolInfo copyWith({
    String? province,
    String? district,
    String? name,
    String? principal,
    String? teacher,
    String? subject,
    InstitutionType? type,
    String? parent,
    String? country,
    String? headTitle,
    String? instructorTitle,
    String? groupLabel,
    bool? officialHeader,
  }) =>
      SchoolInfo(
        province: province ?? this.province,
        district: district ?? this.district,
        name: name ?? this.name,
        principal: principal ?? this.principal,
        teacher: teacher ?? this.teacher,
        subject: subject ?? this.subject,
        type: type ?? this.type,
        parent: parent ?? this.parent,
        country: country ?? this.country,
        headTitle: headTitle ?? this.headTitle,
        instructorTitle: instructorTitle ?? this.instructorTitle,
        groupLabel: groupLabel ?? this.groupLabel,
        turkishFormat: turkishFormat,
        localHeader: localHeader,
        localUnit: localUnit,
        units: units,
        titleSystem: titleSystem,
        fontFamily: fontFamily,
        headerSize: headerSize,
        headerBold: headerBold,
        headerItalic: headerItalic,
        headerUnderline: headerUnderline,
        signSize: signSize,
        officialHeader: officialHeader ?? this.officialHeader,
      );

  Map<String, dynamic> toJson() => {
        'province': province,
        'district': district,
        'name': name,
        'principal': principal,
        'teacher': teacher,
        'subject': subject,
        'type': type.name,
        'parent': parent,
        'country': country,
        'headTitle': headTitle,
        'instructorTitle': instructorTitle,
        'groupLabel': groupLabel,
        if (turkishFormat != null) 'turkishFormat': turkishFormat,
        if (localHeader != null) 'localHeader': localHeader,
        if (localUnit != null) 'localUnit': localUnit,
        if (units.isNotEmpty) 'units': units,
        if (titleSystem != null) 'titleSystem': titleSystem,
        'fontFamily': fontFamily,
        'headerSize': headerSize,
        'headerBold': headerBold,
        'headerItalic': headerItalic,
        'headerUnderline': headerUnderline,
        'signSize': signSize,
        'officialHeader': officialHeader,
      };

  factory SchoolInfo.fromJson(Map<String, dynamic> j) => SchoolInfo(
        province: j['province'] as String? ?? '',
        district: j['district'] as String? ?? '',
        name: j['name'] as String? ?? '',
        principal: j['principal'] as String? ?? '',
        teacher: j['teacher'] as String? ?? '',
        subject: j['subject'] as String? ?? '',
        type: InstitutionType.byName(j['type'] as String?),
        parent: j['parent'] as String? ?? '',
        country: j['country'] as String? ?? '',
        headTitle: j['headTitle'] as String? ?? '',
        instructorTitle: j['instructorTitle'] as String? ?? '',
        groupLabel: j['groupLabel'] as String? ?? '',
        turkishFormat: j['turkishFormat'] as bool?,
        localHeader: j['localHeader'] as bool?,
        localUnit: j['localUnit'] as String?,
        units: [for (final u in (j['units'] as List?) ?? const []) '$u'],
        titleSystem: j['titleSystem'] as String?,
        fontFamily: j['fontFamily'] as String? ?? 'netice',
        headerSize: (j['headerSize'] as num?)?.toDouble() ?? 10.5,
        headerBold: j['headerBold'] as bool? ?? true,
        headerItalic: j['headerItalic'] as bool? ?? false,
        headerUnderline: j['headerUnderline'] as bool? ?? false,
        signSize: (j['signSize'] as num?)?.toDouble() ?? 9.5,
        officialHeader: j['officialHeader'] as bool? ?? true,
      );
}
