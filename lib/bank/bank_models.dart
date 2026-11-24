// Soru bankası, konu notları (hap bilgi) ve kitapçık veri modelleri.
//
// Bütün içerik cihazda durur; görseller ayrı dosyalarda, burada yalnız
// kimlikleri tutulur (bkz. BankStore).

import '../l10n/l10n.dart';

/// Sorunun zorluk derecesi.
enum Difficulty {
  easy,
  medium,
  hard;

  String get label => switch (this) {
        Difficulty.easy => tr('Kolay'),
        Difficulty.medium => tr('Orta'),
        Difficulty.hard => tr('Zor'),
      };

  /// Gerçek doğru oranından (p) zorluk: p ≥ 0,70 kolay, p < 0,40 zor.
  static Difficulty fromP(double p) => p >= 0.70 ? Difficulty.easy : (p < 0.40 ? Difficulty.hard : Difficulty.medium);

  static Difficulty parse(String? s) {
    final t = (s ?? '').trim().toLowerCase();
    if (t.isEmpty) return Difficulty.medium;
    if (t.startsWith('k') || t.startsWith('e') || t == '1' || t.startsWith('leicht') || t.startsWith('f')) {
      return Difficulty.easy;
    }
    if (t.startsWith('z') || t.startsWith('h') || t.startsWith('d') || t == '3' || t.startsWith('sch') || t.startsWith('ç')) {
      return Difficulty.hard;
    }
    return Difficulty.medium;
  }
}

/// Soru türü.
enum QuestionType {
  /// Çoktan seçmeli (optik formla okunur).
  multiple,

  /// Doğru / yanlış (formda A = Doğru, B = Yanlış).
  trueFalse,

  /// Boşluk doldurma (öğretmen puanlar).
  fill,

  /// Klasik / açık uçlu (öğretmen puanlar).
  open;

  String get label => switch (this) {
        QuestionType.multiple => tr('Çoktan seçmeli'),
        QuestionType.trueFalse => tr('Doğru / Yanlış'),
        QuestionType.fill => tr('Boşluk doldurma'),
        QuestionType.open => tr('Klasik (açık uçlu)'),
      };

  /// Optik formda okunabilir mi?
  bool get optical => this == QuestionType.multiple || this == QuestionType.trueFalse;
}

String _letter(int i) => String.fromCharCode(65 + i);

/// Bankadaki bir soru.
class BankQuestion {
  final String id;

  /// Ders (Fizik, Matematik…), düzey (9, 10, "TYT"…), konu ve kazanım.
  final String subject;
  final String grade;
  final String topic;
  final String outcome;
  final Difficulty difficulty;
  final QuestionType type;

  /// Soru kökü (yazılı soru). Görselli sorularda boş olabilir.
  final String text;

  /// Şık metinleri. Şıklar görselin içindeyse boş, sayısı [choiceCount].
  final List<String> choices;

  /// Şık sayısı (çoktan seçmelide 2–5; doğru/yanlışta 2).
  final int choiceCount;

  /// Doğru şık(lar), 0 = A. Doğru/yanlışta 0 = Doğru, 1 = Yanlış.
  final Set<int> correct;

  /// Klasik ve boşluk doldurma için beklenen cevap / cevap anahtarı.
  final String answerText;

  /// Sorunun görseli (PDF'ten ya da fotoğraftan kesilmiş). null = yok.
  final String? imageId;

  /// Çözüm açıklaması ve görseli.
  final String solution;
  final String? solutionImageId;

  /// Serbest etiketler (ör. "LGS", "çıkmış soru").
  final List<String> tags;

  /// Kaynak notu (ör. "Kendi notlarım, s. 12").
  final String source;

  /// Önerilen puan (kitapçıkta değiştirilebilir).
  final double points;

  /// Klasik sorularda kâğıtta bırakılacak cevap satırı sayısı.
  final int answerLines;

  final bool favorite;
  final DateTime created;
  final DateTime updated;

  const BankQuestion({
    required this.id,
    this.subject = '',
    this.grade = '',
    this.topic = '',
    this.outcome = '',
    this.difficulty = Difficulty.medium,
    this.type = QuestionType.multiple,
    this.text = '',
    this.choices = const [],
    this.choiceCount = 5,
    this.correct = const {},
    this.answerText = '',
    this.imageId,
    this.solution = '',
    this.solutionImageId,
    this.tags = const [],
    this.source = '',
    this.points = 1,
    this.answerLines = 4,
    this.favorite = false,
    required this.created,
    required this.updated,
  });

  /// Şık sayısı (yazılı şıklar varsa onların sayısı).
  int get optionCount => type == QuestionType.trueFalse ? 2 : (choices.isNotEmpty ? choices.length : choiceCount);

  bool get hasImage => imageId != null;
  bool get hasSolution => solution.trim().isNotEmpty || solutionImageId != null;

  /// Şıklar yazıyla verilmiş mi (karıştırılabilir mi)?
  /// (Şıklar görselin içindeyse karıştırılamaz.)
  bool get shufflableChoices => type == QuestionType.multiple && choices.length >= 2;

  /// Konu yoksa kazanım, o da yoksa ders: analizde kullanılan başlık.
  String get topicLabel => topic.trim().isNotEmpty ? topic.trim() : (outcome.trim().isNotEmpty ? outcome.trim() : subject.trim());

  /// Kısa cevap gösterimi: "C", "Doğru", "A/C" ya da cevap metni.
  String get answerLabel => switch (type) {
        QuestionType.trueFalse => correct.contains(1) ? tr('Yanlış') : tr('Doğru'),
        QuestionType.multiple => correct.isEmpty ? '–' : (correct.toList()..sort()).map(_letter).join('/'),
        _ => answerText.trim().isEmpty ? '–' : answerText.trim(),
      };

  /// Bütün alanları içinde arama için tek satır.
  String get searchText =>
      [subject, grade, topic, outcome, text, ...choices, answerText, solution, ...tags, source].join(' ').toLowerCase();

  /// Bu soru kullanılabilir durumda mı (çoktan seçmelide cevap seçilmiş mi)?
  bool get complete => switch (type) {
        QuestionType.multiple || QuestionType.trueFalse => correct.isNotEmpty && (text.trim().isNotEmpty || imageId != null),
        _ => text.trim().isNotEmpty || imageId != null,
      };

  BankQuestion copyWith({
    String? subject,
    String? grade,
    String? topic,
    String? outcome,
    Difficulty? difficulty,
    QuestionType? type,
    String? text,
    List<String>? choices,
    int? choiceCount,
    Set<int>? correct,
    String? answerText,
    String? imageId,
    bool clearImage = false,
    String? solution,
    String? solutionImageId,
    bool clearSolutionImage = false,
    List<String>? tags,
    String? source,
    double? points,
    int? answerLines,
    bool? favorite,
    DateTime? updated,
  }) =>
      BankQuestion(
        id: id,
        subject: subject ?? this.subject,
        grade: grade ?? this.grade,
        topic: topic ?? this.topic,
        outcome: outcome ?? this.outcome,
        difficulty: difficulty ?? this.difficulty,
        type: type ?? this.type,
        text: text ?? this.text,
        choices: choices ?? this.choices,
        choiceCount: choiceCount ?? this.choiceCount,
        correct: correct ?? this.correct,
        answerText: answerText ?? this.answerText,
        imageId: clearImage ? null : (imageId ?? this.imageId),
        solution: solution ?? this.solution,
        solutionImageId: clearSolutionImage ? null : (solutionImageId ?? this.solutionImageId),
        tags: tags ?? this.tags,
        source: source ?? this.source,
        points: points ?? this.points,
        answerLines: answerLines ?? this.answerLines,
        favorite: favorite ?? this.favorite,
        created: created,
        updated: updated ?? DateTime.now(),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        if (subject.isNotEmpty) 'subject': subject,
        if (grade.isNotEmpty) 'grade': grade,
        if (topic.isNotEmpty) 'topic': topic,
        if (outcome.isNotEmpty) 'outcome': outcome,
        'difficulty': difficulty.name,
        'type': type.name,
        if (text.isNotEmpty) 'text': text,
        if (choices.isNotEmpty) 'choices': choices,
        'choiceCount': choiceCount,
        'correct': correct.toList()..sort(),
        if (answerText.isNotEmpty) 'answerText': answerText,
        if (imageId != null) 'imageId': imageId,
        if (solution.isNotEmpty) 'solution': solution,
        if (solutionImageId != null) 'solutionImageId': solutionImageId,
        if (tags.isNotEmpty) 'tags': tags,
        if (source.isNotEmpty) 'source': source,
        'points': points,
        'answerLines': answerLines,
        if (favorite) 'favorite': true,
        'created': created.toIso8601String(),
        'updated': updated.toIso8601String(),
      };

  factory BankQuestion.fromJson(Map<String, dynamic> j) => BankQuestion(
        id: j['id'] as String,
        subject: j['subject'] as String? ?? '',
        grade: j['grade'] as String? ?? '',
        topic: j['topic'] as String? ?? '',
        outcome: j['outcome'] as String? ?? '',
        difficulty: Difficulty.values.asNameMap()[j['difficulty']] ?? Difficulty.medium,
        type: QuestionType.values.asNameMap()[j['type']] ?? QuestionType.multiple,
        text: j['text'] as String? ?? '',
        choices: (j['choices'] as List?)?.cast<String>() ?? const [],
        choiceCount: j['choiceCount'] as int? ?? 5,
        correct: (j['correct'] as List?)?.cast<int>().toSet() ?? const {},
        answerText: j['answerText'] as String? ?? '',
        imageId: j['imageId'] as String?,
        solution: j['solution'] as String? ?? '',
        solutionImageId: j['solutionImageId'] as String?,
        tags: (j['tags'] as List?)?.cast<String>() ?? const [],
        source: j['source'] as String? ?? '',
        points: (j['points'] as num?)?.toDouble() ?? 1,
        answerLines: j['answerLines'] as int? ?? 4,
        favorite: j['favorite'] as bool? ?? false,
        created: DateTime.tryParse(j['created'] as String? ?? '') ?? DateTime.now(),
        updated: DateTime.tryParse(j['updated'] as String? ?? '') ?? DateTime.now(),
      );
}

/// Not türü: uzun konu özeti / ders notu ya da kısa hap bilgi.
enum NoteKind {
  summary,
  tip;

  String get label => this == NoteKind.summary ? tr('Konu özeti') : tr('Hap bilgi');
}

/// Konu özeti, ders notu ya da hap bilgi.
class BankNote {
  final String id;
  final NoteKind kind;
  final String subject;
  final String grade;
  final String topic;
  final String outcome;
  final String title;

  /// Not metni. Satır başında "• " ya da "- " madde sayılır.
  final String body;

  /// Not görselleri (PDF sayfası, fotoğraf, kesilmiş bölüm).
  final List<String> imageIds;
  final List<String> tags;
  final String source;
  final bool favorite;
  final DateTime created;
  final DateTime updated;

  const BankNote({
    required this.id,
    this.kind = NoteKind.summary,
    this.subject = '',
    this.grade = '',
    this.topic = '',
    this.outcome = '',
    this.title = '',
    this.body = '',
    this.imageIds = const [],
    this.tags = const [],
    this.source = '',
    this.favorite = false,
    required this.created,
    required this.updated,
  });

  String get topicLabel => topic.trim().isNotEmpty ? topic.trim() : (outcome.trim().isNotEmpty ? outcome.trim() : subject.trim());

  String get displayTitle => title.trim().isNotEmpty ? title.trim() : (topicLabel.isNotEmpty ? topicLabel : tr('Adsız not'));

  String get searchText => [subject, grade, topic, outcome, title, body, ...tags, source].join(' ').toLowerCase();

  BankNote copyWith({
    NoteKind? kind,
    String? subject,
    String? grade,
    String? topic,
    String? outcome,
    String? title,
    String? body,
    List<String>? imageIds,
    List<String>? tags,
    String? source,
    bool? favorite,
  }) =>
      BankNote(
        id: id,
        kind: kind ?? this.kind,
        subject: subject ?? this.subject,
        grade: grade ?? this.grade,
        topic: topic ?? this.topic,
        outcome: outcome ?? this.outcome,
        title: title ?? this.title,
        body: body ?? this.body,
        imageIds: imageIds ?? this.imageIds,
        tags: tags ?? this.tags,
        source: source ?? this.source,
        favorite: favorite ?? this.favorite,
        created: created,
        updated: DateTime.now(),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'kind': kind.name,
        if (subject.isNotEmpty) 'subject': subject,
        if (grade.isNotEmpty) 'grade': grade,
        if (topic.isNotEmpty) 'topic': topic,
        if (outcome.isNotEmpty) 'outcome': outcome,
        if (title.isNotEmpty) 'title': title,
        if (body.isNotEmpty) 'body': body,
        if (imageIds.isNotEmpty) 'imageIds': imageIds,
        if (tags.isNotEmpty) 'tags': tags,
        if (source.isNotEmpty) 'source': source,
        if (favorite) 'favorite': true,
        'created': created.toIso8601String(),
        'updated': updated.toIso8601String(),
      };

  factory BankNote.fromJson(Map<String, dynamic> j) => BankNote(
        id: j['id'] as String,
        kind: NoteKind.values.asNameMap()[j['kind']] ?? NoteKind.summary,
        subject: j['subject'] as String? ?? '',
        grade: j['grade'] as String? ?? '',
        topic: j['topic'] as String? ?? '',
        outcome: j['outcome'] as String? ?? '',
        title: j['title'] as String? ?? '',
        body: j['body'] as String? ?? '',
        imageIds: (j['imageIds'] as List?)?.cast<String>() ?? const [],
        tags: (j['tags'] as List?)?.cast<String>() ?? const [],
        source: j['source'] as String? ?? '',
        favorite: j['favorite'] as bool? ?? false,
        created: DateTime.tryParse(j['created'] as String? ?? '') ?? DateTime.now(),
        updated: DateTime.tryParse(j['updated'] as String? ?? '') ?? DateTime.now(),
      );
}

/// Kitapçıkta soruların sıralanışı.
enum QuestionOrder {
  /// Seçildiği / elle düzenlendiği sırayla.
  manual,

  /// Kolaydan zora.
  easyFirst,

  /// Derse, sonra konuya göre gruplanmış.
  byTopic,

  /// Karışık (rastgele).
  random;

  String get label => switch (this) {
        QuestionOrder.manual => tr('Seçtiğim sırayla'),
        QuestionOrder.easyFirst => tr('Kolaydan zora'),
        QuestionOrder.byTopic => tr('Ders ve konuya göre'),
        QuestionOrder.random => tr('Karışık'),
      };
}

/// Kitapçık sayfa boyutu.
/// Kitapçığın görünümü: klasik (lise, kurum sınavları) ya da çocuk (ilkokul):
/// iri ve okunaklı yazı, renkli numaralar, A–B–C şıkları ve köşede küçük cevap kutusu.
enum BookletStyle {
  classic,
  kids;

  String get label => switch (this) {
        BookletStyle.classic => tr('Klasik şablon'),
        BookletStyle.kids => tr('Çocuk / İlkokul'),
      };
}

enum PaperSize {
  a4,
  a5,
  letter;

  String get label => switch (this) {
        PaperSize.a4 => 'A4',
        PaperSize.a5 => 'A5',
        PaperSize.letter => 'Letter',
      };
}

/// Kitapçık oluştururken seçilebilen her ayar.
class BookletOptions {
  // — Başlık ve kapak
  final String title;
  final String subtitle;

  /// Kurum bilgilerindeki resmi başlık (T.C., okul adı…) basılsın mı?
  final bool officialHeader;
  final DateTime? date;

  /// Sınav süresi (dakika); 0 = yazılmaz.
  final int durationMinutes;
  final String instructions;

  /// Ayrı bir kapak sayfası (yönergeler ve öğrenci bilgileri).
  final bool coverPage;

  /// Ad, soyad, numara, sınıf kutusu.
  final bool studentBox;

  // — Sayfa düzeni
  final PaperSize paper;
  final int columns;
  final double fontSize;

  /// Sütunlar arasında çizgi.
  final bool columnRule;

  /// Sorular arasında ince ayraç.
  final bool questionRule;

  /// Her sorunun yanında puanı yazsın mı?
  final bool showPoints;

  /// Her sorunun altında konusu (küçük, gri) yazsın mı?
  final bool showTopic;

  /// Şıklar yan yana mı (kısa şıklarda) yoksa alt alta mı?
  final bool compactChoices;

  /// Her sayfa sonunda "Diğer sayfaya geçiniz."
  final bool nextPageHint;

  /// Bölüm başlıkları (derse göre).
  final bool sectionHeaders;

  /// Sayfa altına filigran / not (boş = yok).
  final String watermark;

  /// Sayfa numarası biçimi: "Sayfa 1 / 4".
  final bool pageNumbers;

  // — Sıra ve kitapçıklar
  final QuestionOrder order;

  /// Kitapçık türü sayısı (1 = yalnız A, en çok 8 = A–H).
  final int bookletCount;
  final bool shuffleQuestions;
  final bool shuffleChoices;

  /// Karıştırırken soruları kendi bölümünde (dersinde) tut.
  final bool shuffleWithinSections;

  // — Ekler
  final bool answerKeyPage;
  final bool solutionsBooklet;
  final bool opticalForm;

  /// Kitapçığın sonuna seçilen konuların hap bilgileri.
  final bool tipsAppendix;

  // — Puanlama (sınav olarak oluştururken)
  final double totalScore;

  /// Puanları sorulara eşit böl (yoksa her sorunun kendi puanı).
  final bool equalPoints;

  /// Kaç yanlış bir doğruyu götürür (0 = götürmez).
  final int wrongsPerCorrect;

  final int seed;

  /// Görünüm şablonu.
  final BookletStyle style;

  bool get kids => style == BookletStyle.kids;

  const BookletOptions({
    this.title = '',
    this.subtitle = '',
    this.officialHeader = true,
    this.date,
    this.durationMinutes = 40,
    this.instructions = '',
    this.coverPage = false,
    this.studentBox = true,
    this.paper = PaperSize.a4,
    this.columns = 2,
    this.fontSize = 10.5,
    this.columnRule = true,
    this.questionRule = false,
    this.showPoints = false,
    this.showTopic = false,
    this.compactChoices = true,
    this.nextPageHint = true,
    this.sectionHeaders = true,
    this.watermark = '',
    this.pageNumbers = true,
    this.order = QuestionOrder.manual,
    this.bookletCount = 1,
    this.shuffleQuestions = true,
    this.shuffleChoices = false,
    this.shuffleWithinSections = true,
    this.answerKeyPage = true,
    this.solutionsBooklet = false,
    this.opticalForm = false,
    this.tipsAppendix = false,
    this.totalScore = 100,
    this.equalPoints = true,
    this.wrongsPerCorrect = 0,
    this.seed = 1,
    this.style = BookletStyle.classic,
  });

  static String defaultInstructions() => tr(
      'Sınav süresi {0} dakikadır. Her sorunun yalnız bir doğru cevabı vardır. Cevaplarınızı optik forma kurşun kalemle, daireyi tamamen doldurarak işaretleyiniz.');

  BookletOptions copyWith({
    String? title,
    String? subtitle,
    bool? officialHeader,
    DateTime? date,
    int? durationMinutes,
    String? instructions,
    bool? coverPage,
    bool? studentBox,
    PaperSize? paper,
    int? columns,
    double? fontSize,
    bool? columnRule,
    bool? questionRule,
    bool? showPoints,
    bool? showTopic,
    bool? compactChoices,
    bool? nextPageHint,
    bool? sectionHeaders,
    String? watermark,
    bool? pageNumbers,
    QuestionOrder? order,
    int? bookletCount,
    bool? shuffleQuestions,
    bool? shuffleChoices,
    bool? shuffleWithinSections,
    bool? answerKeyPage,
    bool? solutionsBooklet,
    bool? opticalForm,
    bool? tipsAppendix,
    double? totalScore,
    bool? equalPoints,
    int? wrongsPerCorrect,
    int? seed,
    BookletStyle? style,
  }) =>
      BookletOptions(
        title: title ?? this.title,
        subtitle: subtitle ?? this.subtitle,
        officialHeader: officialHeader ?? this.officialHeader,
        date: date ?? this.date,
        durationMinutes: durationMinutes ?? this.durationMinutes,
        instructions: instructions ?? this.instructions,
        coverPage: coverPage ?? this.coverPage,
        studentBox: studentBox ?? this.studentBox,
        paper: paper ?? this.paper,
        columns: columns ?? this.columns,
        fontSize: fontSize ?? this.fontSize,
        columnRule: columnRule ?? this.columnRule,
        questionRule: questionRule ?? this.questionRule,
        showPoints: showPoints ?? this.showPoints,
        showTopic: showTopic ?? this.showTopic,
        compactChoices: compactChoices ?? this.compactChoices,
        nextPageHint: nextPageHint ?? this.nextPageHint,
        sectionHeaders: sectionHeaders ?? this.sectionHeaders,
        watermark: watermark ?? this.watermark,
        pageNumbers: pageNumbers ?? this.pageNumbers,
        order: order ?? this.order,
        bookletCount: bookletCount ?? this.bookletCount,
        shuffleQuestions: shuffleQuestions ?? this.shuffleQuestions,
        shuffleChoices: shuffleChoices ?? this.shuffleChoices,
        shuffleWithinSections: shuffleWithinSections ?? this.shuffleWithinSections,
        answerKeyPage: answerKeyPage ?? this.answerKeyPage,
        solutionsBooklet: solutionsBooklet ?? this.solutionsBooklet,
        opticalForm: opticalForm ?? this.opticalForm,
        tipsAppendix: tipsAppendix ?? this.tipsAppendix,
        totalScore: totalScore ?? this.totalScore,
        equalPoints: equalPoints ?? this.equalPoints,
        wrongsPerCorrect: wrongsPerCorrect ?? this.wrongsPerCorrect,
        seed: seed ?? this.seed,
        style: style ?? this.style,
      );

  Map<String, dynamic> toJson() => {
        'title': title,
        'subtitle': subtitle,
        'officialHeader': officialHeader,
        if (date != null) 'date': date!.toIso8601String(),
        'durationMinutes': durationMinutes,
        'instructions': instructions,
        'coverPage': coverPage,
        'studentBox': studentBox,
        'paper': paper.name,
        'columns': columns,
        'fontSize': fontSize,
        'columnRule': columnRule,
        'questionRule': questionRule,
        'showPoints': showPoints,
        'showTopic': showTopic,
        'compactChoices': compactChoices,
        'nextPageHint': nextPageHint,
        'sectionHeaders': sectionHeaders,
        'watermark': watermark,
        'pageNumbers': pageNumbers,
        'order': order.name,
        'bookletCount': bookletCount,
        'shuffleQuestions': shuffleQuestions,
        'shuffleChoices': shuffleChoices,
        'shuffleWithinSections': shuffleWithinSections,
        'answerKeyPage': answerKeyPage,
        'solutionsBooklet': solutionsBooklet,
        'opticalForm': opticalForm,
        'tipsAppendix': tipsAppendix,
        'totalScore': totalScore,
        'equalPoints': equalPoints,
        'wrongsPerCorrect': wrongsPerCorrect,
        'seed': seed,
        if (style != BookletStyle.classic) 'style': style.name,
      };

  factory BookletOptions.fromJson(Map<String, dynamic> j) {
    const d = BookletOptions();
    T v<T>(String k, T def) => j[k] is T ? j[k] as T : def;
    return BookletOptions(
      title: v('title', d.title),
      subtitle: v('subtitle', d.subtitle),
      officialHeader: v('officialHeader', d.officialHeader),
      date: DateTime.tryParse(j['date'] as String? ?? ''),
      durationMinutes: v('durationMinutes', d.durationMinutes),
      instructions: v('instructions', d.instructions),
      coverPage: v('coverPage', d.coverPage),
      studentBox: v('studentBox', d.studentBox),
      paper: PaperSize.values.asNameMap()[j['paper']] ?? d.paper,
      columns: v('columns', d.columns),
      fontSize: (j['fontSize'] as num?)?.toDouble() ?? d.fontSize,
      columnRule: v('columnRule', d.columnRule),
      questionRule: v('questionRule', d.questionRule),
      showPoints: v('showPoints', d.showPoints),
      showTopic: v('showTopic', d.showTopic),
      compactChoices: v('compactChoices', d.compactChoices),
      nextPageHint: v('nextPageHint', d.nextPageHint),
      sectionHeaders: v('sectionHeaders', d.sectionHeaders),
      watermark: v('watermark', d.watermark),
      pageNumbers: v('pageNumbers', d.pageNumbers),
      order: QuestionOrder.values.asNameMap()[j['order']] ?? d.order,
      bookletCount: v('bookletCount', d.bookletCount),
      shuffleQuestions: v('shuffleQuestions', d.shuffleQuestions),
      shuffleChoices: v('shuffleChoices', d.shuffleChoices),
      shuffleWithinSections: v('shuffleWithinSections', d.shuffleWithinSections),
      answerKeyPage: v('answerKeyPage', d.answerKeyPage),
      solutionsBooklet: v('solutionsBooklet', d.solutionsBooklet),
      opticalForm: v('opticalForm', d.opticalForm),
      tipsAppendix: v('tipsAppendix', d.tipsAppendix),
      totalScore: (j['totalScore'] as num?)?.toDouble() ?? d.totalScore,
      equalPoints: v('equalPoints', d.equalPoints),
      wrongsPerCorrect: v('wrongsPerCorrect', d.wrongsPerCorrect),
      seed: v('seed', d.seed),
      style: BookletStyle.values.asNameMap()[j['style']] ?? d.style,
    );
  }
}

/// Kaydedilmiş bir kitapçık (taslak ya da basılmış).
class Booklet {
  final String id;
  final String name;

  /// Soruların ana (A) sıradaki kimlikleri.
  final List<String> questionIds;
  final BookletOptions options;

  /// Bu kitapçıktan oluşturulan sınavlar.
  final List<String> examIds;
  final DateTime created;
  final DateTime updated;

  const Booklet({
    required this.id,
    required this.name,
    this.questionIds = const [],
    this.options = const BookletOptions(),
    this.examIds = const [],
    required this.created,
    required this.updated,
  });

  Booklet copyWith({String? name, List<String>? questionIds, BookletOptions? options, List<String>? examIds}) => Booklet(
        id: id,
        name: name ?? this.name,
        questionIds: questionIds ?? this.questionIds,
        options: options ?? this.options,
        examIds: examIds ?? this.examIds,
        created: created,
        updated: DateTime.now(),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'questionIds': questionIds,
        'options': options.toJson(),
        if (examIds.isNotEmpty) 'examIds': examIds,
        'created': created.toIso8601String(),
        'updated': updated.toIso8601String(),
      };

  factory Booklet.fromJson(Map<String, dynamic> j) => Booklet(
        id: j['id'] as String,
        name: j['name'] as String? ?? '',
        questionIds: (j['questionIds'] as List?)?.cast<String>() ?? const [],
        options: j['options'] is Map ? BookletOptions.fromJson((j['options'] as Map).cast<String, dynamic>()) : const BookletOptions(),
        examIds: (j['examIds'] as List?)?.cast<String>() ?? const [],
        created: DateTime.tryParse(j['created'] as String? ?? '') ?? DateTime.now(),
        updated: DateTime.tryParse(j['updated'] as String? ?? '') ?? DateTime.now(),
      );
}

/// Bankada süzme ölçütleri.
class BankFilter {
  final String query;
  final Set<String> subjects;
  final Set<String> grades;
  final Set<String> topics;
  final Set<Difficulty> difficulties;
  final Set<QuestionType> types;
  final Set<String> tags;
  final bool favoritesOnly;

  /// Hiç sınavda kullanılmamış olanlar.
  final bool unusedOnly;

  const BankFilter({
    this.query = '',
    this.subjects = const {},
    this.grades = const {},
    this.topics = const {},
    this.difficulties = const {},
    this.types = const {},
    this.tags = const {},
    this.favoritesOnly = false,
    this.unusedOnly = false,
  });

  bool get isEmpty =>
      query.trim().isEmpty &&
      subjects.isEmpty &&
      grades.isEmpty &&
      topics.isEmpty &&
      difficulties.isEmpty &&
      types.isEmpty &&
      tags.isEmpty &&
      !favoritesOnly &&
      !unusedOnly;

  int get activeCount =>
      (subjects.isEmpty ? 0 : 1) +
      (grades.isEmpty ? 0 : 1) +
      (topics.isEmpty ? 0 : 1) +
      (difficulties.isEmpty ? 0 : 1) +
      (types.isEmpty ? 0 : 1) +
      (tags.isEmpty ? 0 : 1) +
      (favoritesOnly ? 1 : 0) +
      (unusedOnly ? 1 : 0);

  BankFilter copyWith({
    String? query,
    Set<String>? subjects,
    Set<String>? grades,
    Set<String>? topics,
    Set<Difficulty>? difficulties,
    Set<QuestionType>? types,
    Set<String>? tags,
    bool? favoritesOnly,
    bool? unusedOnly,
  }) =>
      BankFilter(
        query: query ?? this.query,
        subjects: subjects ?? this.subjects,
        grades: grades ?? this.grades,
        topics: topics ?? this.topics,
        difficulties: difficulties ?? this.difficulties,
        types: types ?? this.types,
        tags: tags ?? this.tags,
        favoritesOnly: favoritesOnly ?? this.favoritesOnly,
        unusedOnly: unusedOnly ?? this.unusedOnly,
      );

  bool matches(BankQuestion q, {bool used = false}) {
    if (subjects.isNotEmpty && !subjects.contains(q.subject)) return false;
    if (grades.isNotEmpty && !grades.contains(q.grade)) return false;
    if (topics.isNotEmpty && !topics.contains(q.topic)) return false;
    if (difficulties.isNotEmpty && !difficulties.contains(q.difficulty)) return false;
    if (types.isNotEmpty && !types.contains(q.type)) return false;
    if (tags.isNotEmpty && !q.tags.any(tags.contains)) return false;
    if (favoritesOnly && !q.favorite) return false;
    if (unusedOnly && used) return false;
    final s = query.trim().toLowerCase();
    if (s.isNotEmpty && !s.split(RegExp(r'\s+')).every(q.searchText.contains)) return false;
    return true;
  }

  bool matchesNote(BankNote n) {
    if (subjects.isNotEmpty && !subjects.contains(n.subject)) return false;
    if (grades.isNotEmpty && !grades.contains(n.grade)) return false;
    if (topics.isNotEmpty && !topics.contains(n.topic)) return false;
    if (tags.isNotEmpty && !n.tags.any(tags.contains)) return false;
    if (favoritesOnly && !n.favorite) return false;
    final s = query.trim().toLowerCase();
    if (s.isNotEmpty && !s.split(RegExp(r'\s+')).every(n.searchText.contains)) return false;
    return true;
  }
}

/// Otomatik soru seçimi isteği.
class AutoPick {
  final int count;

  /// Kolay / orta / zor yüzdeleri (toplamı 100).
  final int easyPct;
  final int mediumPct;
  final int hardPct;

  /// Konulara eşit dağıt (yoksa bankadaki oranla).
  final bool balanceTopics;

  /// Daha önce sınavda kullanılmışları en sona bırak.
  final bool preferUnused;

  /// Yalnız optik formla okunabilen sorular (çoktan seçmeli, D/Y).
  final bool opticalOnly;
  final int seed;

  const AutoPick({
    this.count = 20,
    this.easyPct = 30,
    this.mediumPct = 50,
    this.hardPct = 20,
    this.balanceTopics = true,
    this.preferUnused = true,
    this.opticalOnly = false,
    this.seed = 1,
  });
}
