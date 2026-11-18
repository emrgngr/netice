/// Netice çekirdek veri modeli (MVP).
///
/// Ürün tasarım dokümanındaki varlıkların sadeleştirilmiş hâli: sınav,
/// soru, cevap anahtarı, öğrenci, öğrenci cevabı ve sonuç.
library;

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

  String get fullName => '$firstName $lastName';

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

class Exam {
  final String id;
  final String name;
  final String className;
  final DateTime date;

  /// 4 veya 5.
  final int choiceCount;
  final List<Question> questions;
  final ScoringRule rule;

  const Exam({
    required this.id,
    required this.name,
    required this.className,
    required this.date,
    required this.choiceCount,
    required this.questions,
    this.rule = const ScoringRule(),
  });

  int get questionCount => questions.length;

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

  Exam copyWith({List<Question>? questions, ScoringRule? rule, String? name, String? className, DateTime? date}) =>
      Exam(
        id: id,
        name: name ?? this.name,
        className: className ?? this.className,
        date: date ?? this.date,
        choiceCount: choiceCount,
        questions: questions ?? this.questions,
        rule: rule ?? this.rule,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'className': className,
        'date': date.toIso8601String(),
        'choiceCount': choiceCount,
        'questions': questions.map((q) => q.toJson()).toList(),
        'rule': rule.toJson(),
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
  final List<Answer> answers;

  const Sheet({required this.examId, this.studentId, required this.answers});

  bool get needsReview =>
      studentId == null || answers.any((a) => a.needsReview);

  Sheet copyWith({String? studentId, List<Answer>? answers}) => Sheet(
        examId: examId,
        studentId: studentId ?? this.studentId,
        answers: answers ?? this.answers,
      );

  Map<String, dynamic> toJson() => {
        'examId': examId,
        'studentId': studentId,
        'answers': answers.map((a) => a.toJson()).toList(),
      };

  factory Sheet.fromJson(Map<String, dynamic> j) => Sheet(
        examId: j['examId'] as String,
        studentId: j['studentId'] as String?,
        answers: (j['answers'] as List)
            .map((e) => Answer.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

/// Okul ve öğretmen bilgileri. Raporlarda resmi yazı başlığı olarak kullanılır.
class SchoolInfo {
  final String province; // il
  final String district; // ilçe
  final String name; // okul adı
  final String principal; // okul müdürü
  final String teacher; // ders öğretmeni
  final String subject; // ders / branş

  /// Raporlarda "T.C. ... Kaymakamlığı ... Müdürlüğü" başlığı ve imza alanı.
  final bool officialHeader;

  const SchoolInfo({
    this.province = '',
    this.district = '',
    this.name = '',
    this.principal = '',
    this.teacher = '',
    this.subject = '',
    this.officialHeader = true,
  });

  bool get isEmpty => name.trim().isEmpty;

  /// Resmi başlık kullanılacak mı?
  bool get official => officialHeader && !isEmpty;

  /// Türkçe büyük harf (i → İ, ı → I).
  static String upper(String s) => s.replaceAll('i', 'İ').replaceAll('ı', 'I').toUpperCase();

  /// "ÇANKAYA KAYMAKAMLIĞI" ya da "ANKARA VALİLİĞİ" (ilçe merkez veya boşsa).
  String get authority {
    final d = district.trim(), p = province.trim();
    if (d.isNotEmpty && upper(d) != 'MERKEZ') return '${upper(d)} KAYMAKAMLIĞI';
    if (p.isNotEmpty) return '${upper(p)} VALİLİĞİ';
    return '';
  }

  /// "ATATÜRK ANADOLU LİSESİ MÜDÜRLÜĞÜ"
  String get directorate {
    final n = upper(name.trim());
    if (n.isEmpty) return '';
    return n.endsWith('MÜDÜRLÜĞÜ') ? n : '$n MÜDÜRLÜĞÜ';
  }

  /// Eğitim-öğretim yılı: eylülden itibaren yeni yıl başlar.
  static String academicYear(DateTime d) {
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
    bool? officialHeader,
  }) =>
      SchoolInfo(
        province: province ?? this.province,
        district: district ?? this.district,
        name: name ?? this.name,
        principal: principal ?? this.principal,
        teacher: teacher ?? this.teacher,
        subject: subject ?? this.subject,
        officialHeader: officialHeader ?? this.officialHeader,
      );

  Map<String, dynamic> toJson() => {
        'province': province,
        'district': district,
        'name': name,
        'principal': principal,
        'teacher': teacher,
        'subject': subject,
        'officialHeader': officialHeader,
      };

  factory SchoolInfo.fromJson(Map<String, dynamic> j) => SchoolInfo(
        province: j['province'] as String? ?? '',
        district: j['district'] as String? ?? '',
        name: j['name'] as String? ?? '',
        principal: j['principal'] as String? ?? '',
        teacher: j['teacher'] as String? ?? '',
        subject: j['subject'] as String? ?? '',
        officialHeader: j['officialHeader'] as bool? ?? true,
      );
}
