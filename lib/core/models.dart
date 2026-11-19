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

  const Student({
    required this.id,
    required this.firstName,
    required this.lastName,
    required this.number,
    required this.className,
  });

  /// Çince ve Japonca adlar arasında boşluk bırakılmaz (王伟).
  String get fullName => _cjk.hasMatch(firstName) && _cjk.hasMatch(lastName) ? '$firstName$lastName' : '$firstName $lastName';
  static final _cjk = RegExp(r'^[\u3040-\u30FF\u3400-\u9FFF]+$');

  Map<String, dynamic> toJson() => {
        'id': id,
        'firstName': firstName,
        'lastName': lastName,
        'number': number,
        'className': className,
      };

  factory Student.fromJson(Map<String, dynamic> j) => Student(
        id: j['id'] as String,
        firstName: j['firstName'] as String,
        lastName: j['lastName'] as String,
        number: j['number'] as String,
        className: j['className'] as String,
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

  const Question({
    required this.no,
    required this.correct,
    this.points = 1,
    this.cancelled = false,
    this.outcomeCode,
  });

  Question copyWith({Set<int>? correct, double? points, bool? cancelled, String? outcomeCode}) =>
      Question(
        no: no,
        correct: correct ?? this.correct,
        points: points ?? this.points,
        cancelled: cancelled ?? this.cancelled,
        outcomeCode: outcomeCode ?? this.outcomeCode,
      );

  Map<String, dynamic> toJson() => {
        'no': no,
        'correct': correct.toList(),
        'points': points,
        'cancelled': cancelled,
        'outcomeCode': outcomeCode,
      };

  factory Question.fromJson(Map<String, dynamic> j) => Question(
        no: j['no'] as int,
        correct: (j['correct'] as List).cast<int>().toSet(),
        points: (j['points'] as num).toDouble(),
        cancelled: j['cancelled'] as bool? ?? false,
        outcomeCode: j['outcomeCode'] as String?,
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
class OpenQuestion {
  final String label;
  final double maxPoints;
  const OpenQuestion({required this.label, required this.maxPoints});

  Map<String, dynamic> toJson() => {'label': label, 'maxPoints': maxPoints};
  factory OpenQuestion.fromJson(Map<String, dynamic> j) =>
      OpenQuestion(label: j['label'] as String? ?? '', maxPoints: (j['maxPoints'] as num).toDouble());
}

class Exam {
  final String id;
  final String name;
  final String className;
  final DateTime date;

  /// 4 veya 5.
  final int choiceCount;
  final List<Question> questions;
  final ScoringRule rule;

  /// B kitapçığı: B'deki [i]. sorunun A kitapçığındaki karşılığı (0'dan).
  /// Şıklar aynı, yalnızca soru sırası değişik. null = tek kitapçık.
  final List<int>? bookletOrder;

  /// Klasik sorular. Varsa tam puan = test kısmı + klasik kısım; test kısmı
  /// (tam puan − klasik toplamı) üzerinden ölçeklenir.
  final List<OpenQuestion> openQuestions;

  /// Başka firma formu kullanılıyorsa şablonun kimliği; null = Netice formu.
  final String? templateId;

  const Exam({
    required this.id,
    required this.name,
    required this.className,
    required this.date,
    required this.choiceCount,
    required this.questions,
    this.rule = const ScoringRule(),
    this.bookletOrder,
    this.openQuestions = const [],
    this.templateId,
  });

  int get questionCount => questions.length;

  bool get hasOpen => openQuestions.isNotEmpty;
  double get openMax => openQuestions.fold(0.0, (a, q) => a + q.maxPoints);

  /// Test (optik) kısmın tam puanı.
  double get testMax => (rule.maxScore - openMax).clamp(0, rule.maxScore).toDouble();

  bool get hasBooklets => bookletOrder != null;

  /// B kitapçığının cevap anahtarı (B sırasıyla).
  List<Question> get bookletBQuestions => [
        for (var i = 0; i < (bookletOrder?.length ?? 0); i++)
          Question(
            no: i + 1,
            correct: questions[bookletOrder![i]].correct,
            points: questions[bookletOrder![i]].points,
            cancelled: questions[bookletOrder![i]].cancelled,
            outcomeCode: questions[bookletOrder![i]].outcomeCode,
          ),
      ];

  /// B kitapçığı cevaplarını A sırasına çevirir.
  List<Answer> toBookletA(List<Answer> b) {
    final order = bookletOrder;
    if (order == null) return b;
    final a = List<Answer>.filled(questions.length, const Answer.blank());
    for (var i = 0; i < order.length && i < b.length; i++) {
      a[order[i]] = b[i];
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
    List<int>? bookletOrder,
    bool clearBooklet = false,
    List<OpenQuestion>? openQuestions,
    String? templateId,
    bool clearTemplate = false,
  }) =>
      Exam(
        id: id,
        name: name ?? this.name,
        className: className ?? this.className,
        date: date ?? this.date,
        choiceCount: choiceCount,
        questions: questions ?? this.questions,
        rule: rule ?? this.rule,
        bookletOrder: clearBooklet ? null : (bookletOrder ?? this.bookletOrder),
        openQuestions: openQuestions ?? this.openQuestions,
        templateId: clearTemplate ? null : (templateId ?? this.templateId),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'className': className,
        'date': date.toIso8601String(),
        'choiceCount': choiceCount,
        'questions': questions.map((q) => q.toJson()).toList(),
        'rule': rule.toJson(),
        if (bookletOrder != null) 'bookletOrder': bookletOrder,
        if (templateId != null) 'templateId': templateId,
        if (openQuestions.isNotEmpty) 'openQuestions': openQuestions.map((q) => q.toJson()).toList(),
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
        bookletOrder: (j['bookletOrder'] as List?)?.map((e) => e as int).toList(),
        templateId: j['templateId'] as String?,
        openQuestions: [
          for (final e in (j['openQuestions'] as List?) ?? const []) OpenQuestion.fromJson(e as Map<String, dynamic>)
        ],
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

  /// Öğrencinin kitapçığı (0 = A, 1 = B).
  final int booklet;

  /// Klasik soru puanları (öğretmen girer; girilmeyen null).
  final List<double?> openScores;

  /// İşaretli kâğıt görüntüsünün dosya adı (cihazdaki kagitlar/ klasöründe).
  final String? imageId;

  /// Öğrenci eşleşmediğinde kâğıttan okunan numara ('?' = okunamayan rakam).
  final String? readNumber;

  const Sheet({
    required this.examId,
    this.studentId,
    required this.answers,
    this.booklet = 0,
    this.openScores = const [],
    this.imageId,
    this.readNumber,
  });

  bool get needsReview =>
      studentId == null || answers.any((a) => a.needsReview);

  Sheet copyWith({String? studentId, List<Answer>? answers, List<double?>? openScores, String? imageId}) => Sheet(
        examId: examId,
        studentId: studentId ?? this.studentId,
        answers: answers ?? this.answers,
        booklet: booklet,
        openScores: openScores ?? this.openScores,
        imageId: imageId ?? this.imageId,
        readNumber: readNumber,
      );

  Map<String, dynamic> toJson() => {
        'examId': examId,
        'studentId': studentId,
        'answers': answers.map((a) => a.toJson()).toList(),
        if (booklet != 0) 'booklet': booklet,
        if (openScores.isNotEmpty) 'openScores': openScores,
        if (imageId != null) 'imageId': imageId,
        if (readNumber != null) 'readNumber': readNumber,
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
        police => tr('Polis Akademisi, PMYO, POMEM'),
        military => tr('Askerî okul, askerî lise, harp okulu, askerî üniversite'),
        course => tr('Kurs, dershane, eğitim merkezi'),
        other => tr('Diğer kurum (şirket, kamu eğitimi)'),
      };

  /// Üst kurum için örnek.
  String get parentHint => switch (this) {
        school => '',
        university => tr('Örn. Ankara Üniversitesi'),
        police => tr('Örn. Polis Akademisi Başkanlığı'),
        military => tr('Örn. Millî Savunma Üniversitesi'),
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

  /// Okulda "ÇANKAYA KAYMAKAMLIĞI" ya da "ANKARA VALİLİĞİ" (ilçe merkez veya
  /// boşsa); diğer kurumlarda üst kurum. Türkiye dışı biçimde yer bilgisi.
  String get authority {
    final d = district.trim(), p = province.trim();
    if (!turkishStyle) return [d, p, country.trim()].where((e) => e.isNotEmpty).map(upper).join(', ');
    if (type != InstitutionType.school) return upper(parent.trim());
    if (d.isNotEmpty && upper(d) != 'MERKEZ') return '${upper(d)} KAYMAKAMLIĞI';
    if (p.isNotEmpty) return '${upper(p)} VALİLİĞİ';
    return '';
  }

  /// Okulda "ATATÜRK ANADOLU LİSESİ MÜDÜRLÜĞÜ"; diğer kurumlarda adı olduğu gibi.
  String get directorate {
    final n = upper(name.trim());
    if (n.isEmpty || !turkishStyle || type != InstitutionType.school) return n;
    return n.endsWith('MÜDÜRLÜĞÜ') ? n : '$n MÜDÜRLÜĞÜ';
  }

  /// Resmi başlığın üst satırları, yukarıdan aşağıya.
  List<String> get letterhead => turkishStyle
      ? ['T.C.', if (authority.isNotEmpty) authority, directorate]
      : [
          if (parent.trim().isNotEmpty) upper(parent.trim()),
          directorate,
          if (authority.isNotEmpty) authority,
        ];

  /// Eğitim-öğretim yılı: eylülden itibaren yeni yıl başlar (Japonyada
  /// nisandan başlar ve tek yılla yazılır).
  static String academicYear(DateTime d) {
    if (L10n.code == 'ja') return '${d.month >= 4 ? d.year : d.year - 1}';
    final start = d.month >= 9 ? d.year : d.year - 1;
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
