// Soru bankası deposu: sorular, notlar, kitapçıklar ve görselleri cihazda,
// uygulama verisinin yanında "soru_bankasi" klasöründe tutar.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../core/models.dart';
import 'bank_models.dart';

class BankStore extends ChangeNotifier {
  BankStore._();

  /// Uygulamanın tek bankası.
  static BankStore instance = BankStore._();

  /// Testler için ayrı bir depo.
  @visibleForTesting
  factory BankStore.forTest() => BankStore._();

  final List<BankQuestion> questions = [];
  final List<BankNote> notes = [];
  final List<Booklet> booklets = [];

  /// Okuma parçaları (birden çok sorunun ortak metni / görseli).
  final List<BankPassage> passages = [];

  /// İçe aktarılmış kazanım listeleri (müfredat).
  final List<OutcomeList> outcomeLists = [];

  /// Son kullanılan etiket değerleri (yeni soru eklerken önerilir).
  String lastSubject = '';
  String lastGrade = '';
  String lastTopic = '';

  Directory? _dir;
  bool loaded = false;

  static final _rnd = math.Random();
  static String newId(String prefix) =>
      '$prefix${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}${_rnd.nextInt(1 << 24).toRadixString(36)}';

  File? get _file => _dir == null ? null : File('${_dir!.path}${Platform.pathSeparator}banka.json');
  Directory? get _imageDir => _dir == null ? null : Directory('${_dir!.path}${Platform.pathSeparator}gorseller');

  /// Kütüphanenin (sorular, notlar, kitapçıklar ve görseller) cihazda kapladığı yer, bayt.
  Future<int> diskUsage() async {
    final d = _dir;
    if (d == null || !await d.exists()) return 0;
    var total = 0;
    await for (final e in d.list(recursive: true, followLinks: false)) {
      if (e is File) {
        try {
          total += await e.length();
        } catch (_) {}
      }
    }
    return total;
  }

  /// [dir]: uygulama verisinin klasörü (verilmezse uygulama destek klasörü).
  Future<void> load({Directory? dir}) async {
    final base = dir ?? await getApplicationSupportDirectory();
    _dir = Directory('${base.path}${Platform.pathSeparator}soru_bankasi');
    questions.clear();
    notes.clear();
    booklets.clear();
    outcomeLists.clear();
    passages.clear();
    final f = _file!;
    if (await f.exists()) {
      try {
        _apply(jsonDecode(await f.readAsString()) as Map<String, dynamic>);
      } catch (_) {
        // Bozuk dosyayı kenara al, boş bankayla devam et.
        try {
          await f.rename('${f.path}.bozuk');
        } catch (_) {}
      }
    }
    loaded = true;
    notifyListeners();
  }

  Map<String, dynamic> toJsonMap() => {
        'app': 'netice-bank',
        'version': 1,
        'savedAt': DateTime.now().toIso8601String(),
        'questions': questions.map((q) => q.toJson()).toList(),
        'notes': notes.map((n) => n.toJson()).toList(),
        'booklets': booklets.map((b) => b.toJson()).toList(),
        if (outcomeLists.isNotEmpty) 'outcomeLists': outcomeLists.map((l) => l.toJson()).toList(),
        if (passages.isNotEmpty) 'passages': passages.map((p) => p.toJson()).toList(),
        'lastSubject': lastSubject,
        'lastGrade': lastGrade,
        'lastTopic': lastTopic,
      };

  void _apply(Map<String, dynamic> j) {
    questions.addAll([for (final e in (j['questions'] as List? ?? [])) BankQuestion.fromJson((e as Map).cast<String, dynamic>())]);
    notes.addAll([for (final e in (j['notes'] as List? ?? [])) BankNote.fromJson((e as Map).cast<String, dynamic>())]);
    booklets.addAll([for (final e in (j['booklets'] as List? ?? [])) Booklet.fromJson((e as Map).cast<String, dynamic>())]);
    outcomeLists.addAll([for (final e in (j['outcomeLists'] as List? ?? [])) OutcomeList.fromJson((e as Map).cast<String, dynamic>())]);
    passages.addAll([for (final e in (j['passages'] as List? ?? [])) BankPassage.fromJson((e as Map).cast<String, dynamic>())]);
    lastSubject = j['lastSubject'] as String? ?? '';
    lastGrade = j['lastGrade'] as String? ?? '';
    lastTopic = j['lastTopic'] as String? ?? '';
  }

  Future<void>? _saving;

  Future<void> save() {
    final prev = _saving;
    final next = prev == null ? _write() : prev.catchError((_) {}).then((_) => _write());
    _saving = next;
    return next;
  }

  Future<void> _write() async {
    final f = _file;
    if (f == null) return;
    await f.parent.create(recursive: true);
    final tmp = File('${f.path}.tmp');
    await tmp.writeAsString(jsonEncode(toJsonMap()));
    await tmp.rename(f.path);
  }

  void _changed() {
    notifyListeners();
    save();
  }

  // ———————————————————————————— Görseller

  /// Görseli kaydeder ve kimliğini döndürür. [bytes] JPEG ya da PNG.
  Future<String> saveImage(Uint8List bytes) async {
    final d = _imageDir;
    final id = newId('g');
    if (d == null) {
      _memImages[id] = bytes;
      return id;
    }
    await d.create(recursive: true);
    await File('${d.path}${Platform.pathSeparator}$id${_ext(bytes)}').writeAsBytes(bytes, flush: true);
    return id;
  }

  /// Bellekte tutulan görseller (klasörsüz testler ve önbellek).
  final _memImages = <String, Uint8List>{};

  static String _ext(Uint8List b) => b.length > 4 && b[0] == 0x89 && b[1] == 0x50 ? '.png' : '.jpg';

  File? imageFile(String? id) {
    final d = _imageDir;
    if (id == null || d == null) return null;
    for (final ext in const ['.jpg', '.png']) {
      final f = File('${d.path}${Platform.pathSeparator}$id$ext');
      if (f.existsSync()) return f;
    }
    return null;
  }

  Uint8List? imageBytes(String? id) {
    if (id == null) return null;
    final m = _memImages[id];
    if (m != null) return m;
    final f = imageFile(id);
    if (f == null) return null;
    try {
      return _memImages[id] = f.readAsBytesSync();
    } catch (_) {
      return null;
    }
  }

  Set<String> get _usedImages => {
        for (final q in questions) ...[if (q.imageId != null) q.imageId!, if (q.solutionImageId != null) q.solutionImageId!],
        for (final q in questions) ...q.choiceImages.whereType<String>(),
        for (final p in passages) ?p.imageId,
        for (final n in notes) ...n.imageIds,
      };

  /// Hiçbir soruya ya da nota bağlı olmayan görselleri siler.
  void cleanImages() {
    final d = _imageDir;
    final used = _usedImages;
    _memImages.removeWhere((k, _) => !used.contains(k));
    if (d == null || !d.existsSync()) return;
    for (final f in d.listSync().whereType<File>()) {
      final name = f.uri.pathSegments.last;
      final id = name.contains('.') ? name.substring(0, name.lastIndexOf('.')) : name;
      if (!used.contains(id)) {
        try {
          f.deleteSync();
        } catch (_) {}
      }
    }
  }

  // ———————————————————————————— Sorular

  BankQuestion? questionById(String? id) => id == null ? null : questions.where((q) => q.id == id).firstOrNull;

  // ———————————————————————————— Okuma parçaları

  BankPassage? passageById(String? id) => id == null ? null : passages.where((p) => p.id == id).firstOrNull;

  BankPassage newPassage() {
    final now = DateTime.now();
    return BankPassage(id: newId('p'), subject: lastSubject, created: now, updated: now);
  }

  void upsertPassage(BankPassage p) {
    final i = passages.indexWhere((x) => x.id == p.id);
    if (i < 0) {
      passages.insert(0, p);
    } else {
      passages[i] = p;
    }
    _changed();
  }

  /// Parçaya bağlı sorular (bankadaki sırasıyla).
  List<BankQuestion> questionsOfPassage(String id) => [for (final q in questions) if (q.passageId == id) q];

  /// Parçayı siler; bağlı soruların bağı kaldırılır (sorular silinmez).
  void removePassage(String id) {
    passages.removeWhere((p) => p.id == id);
    for (var i = 0; i < questions.length; i++) {
      if (questions[i].passageId == id) questions[i] = questions[i].copyWith(clearPassage: true, updated: questions[i].updated);
    }
    _changed();
  }

  BankQuestion newQuestion() {
    final now = DateTime.now();
    return BankQuestion(
      id: newId('q'),
      subject: lastSubject,
      grade: lastGrade,
      topic: lastTopic,
      created: now,
      updated: now,
    );
  }

  void _remember(String subject, String grade, String topic) {
    if (subject.trim().isNotEmpty) lastSubject = subject.trim();
    if (grade.trim().isNotEmpty) lastGrade = grade.trim();
    lastTopic = topic.trim();
  }

  void upsertQuestion(BankQuestion q) {
    final i = questions.indexWhere((x) => x.id == q.id);
    if (i < 0) {
      questions.insert(0, q);
    } else {
      questions[i] = q;
    }
    _remember(q.subject, q.grade, q.topic);
    _changed();
  }

  void addQuestions(Iterable<BankQuestion> list) {
    final l = list.toList();
    if (l.isEmpty) return;
    questions.insertAll(0, l);
    _remember(l.last.subject, l.last.grade, l.last.topic);
    _changed();
  }

  /// Soruları siler; geri almak için silinenleri ve yerlerini döndürür.
  List<(int, BankQuestion)> removeQuestions(Iterable<String> ids) {
    final set = ids.toSet();
    final removed = <(int, BankQuestion)>[];
    for (var i = 0; i < questions.length; i++) {
      if (set.contains(questions[i].id)) removed.add((i, questions[i]));
    }
    questions.removeWhere((q) => set.contains(q.id));
    _changed();
    return removed;
  }

  void restoreQuestions(List<(int, BankQuestion)> removed) {
    for (final (i, q) in removed) {
      if (questions.any((x) => x.id == q.id)) continue;
      questions.insert(i.clamp(0, questions.length), q);
    }
    _changed();
  }

  /// Silinen soruların görsellerini temizler (geri alma süresi bittikten sonra).
  void forgetRemoved() => cleanImages();

  /// Birçok soruya aynı değişikliği uygular (toplu düzenleme).
  void updateMany(Iterable<String> ids, BankQuestion Function(BankQuestion) f) {
    final set = ids.toSet();
    for (var i = 0; i < questions.length; i++) {
      if (set.contains(questions[i].id)) questions[i] = f(questions[i]);
    }
    _changed();
  }

  BankQuestion duplicate(BankQuestion q) {
    final now = DateTime.now();
    final c = BankQuestion.fromJson({...q.toJson(), 'id': newId('q'), 'created': now.toIso8601String(), 'updated': now.toIso8601String()});
    final i = questions.indexWhere((x) => x.id == q.id);
    questions.insert(i < 0 ? 0 : i + 1, c);
    _changed();
    return c;
  }

  void toggleFavorite(String id) {
    final i = questions.indexWhere((x) => x.id == id);
    if (i < 0) return;
    questions[i] = questions[i].copyWith(favorite: !questions[i].favorite, updated: questions[i].updated);
    _changed();
  }

  // ———————————————————————————— Notlar

  BankNote? noteById(String? id) => id == null ? null : notes.where((n) => n.id == id).firstOrNull;

  BankNote newNote({NoteKind kind = NoteKind.summary}) {
    final now = DateTime.now();
    return BankNote(id: newId('n'), kind: kind, subject: lastSubject, grade: lastGrade, topic: lastTopic, created: now, updated: now);
  }

  void upsertNote(BankNote n) {
    final i = notes.indexWhere((x) => x.id == n.id);
    if (i < 0) {
      notes.insert(0, n);
    } else {
      notes[i] = n;
    }
    _remember(n.subject, n.grade, n.topic);
    _changed();
  }

  void addNotes(Iterable<BankNote> list) {
    final l = list.toList();
    if (l.isEmpty) return;
    notes.insertAll(0, l);
    _changed();
  }

  List<(int, BankNote)> removeNotes(Iterable<String> ids) {
    final set = ids.toSet();
    final removed = <(int, BankNote)>[];
    for (var i = 0; i < notes.length; i++) {
      if (set.contains(notes[i].id)) removed.add((i, notes[i]));
    }
    notes.removeWhere((n) => set.contains(n.id));
    _changed();
    return removed;
  }

  void restoreNotes(List<(int, BankNote)> removed) {
    for (final (i, n) in removed) {
      if (notes.any((x) => x.id == n.id)) continue;
      notes.insert(i.clamp(0, notes.length), n);
    }
    _changed();
  }

  /// Bir konuya (ya da kazanıma) ait notlar: önce hap bilgiler.
  List<BankNote> notesFor(String topicOrOutcome, {String? subject}) {
    final key = _norm(topicOrOutcome);
    if (key.isEmpty) return const [];
    final out = notes.where((n) {
      if (subject != null && subject.isNotEmpty && n.subject.isNotEmpty && _norm(n.subject) != _norm(subject)) return false;
      return _norm(n.topic) == key || _norm(n.outcome) == key || (n.title.isNotEmpty && _norm(n.title) == key);
    }).toList()
      ..sort((a, b) => a.kind == b.kind ? b.updated.compareTo(a.updated) : (a.kind == NoteKind.tip ? -1 : 1));
    return out;
  }

  static String _norm(String s) => s.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

  // ———————————————————————————— Kitapçıklar

  Booklet? bookletById(String? id) => id == null ? null : booklets.where((b) => b.id == id).firstOrNull;

  void upsertBooklet(Booklet b) {
    final i = booklets.indexWhere((x) => x.id == b.id);
    if (i < 0) {
      booklets.insert(0, b);
    } else {
      booklets[i] = b;
    }
    _changed();
  }

  List<(int, Booklet)> removeBooklets(Iterable<String> ids) {
    final set = ids.toSet();
    final removed = <(int, Booklet)>[];
    for (var i = 0; i < booklets.length; i++) {
      if (set.contains(booklets[i].id)) removed.add((i, booklets[i]));
    }
    booklets.removeWhere((b) => set.contains(b.id));
    _changed();
    return removed;
  }

  void restoreBooklets(List<(int, Booklet)> removed) {
    for (final (i, b) in removed) {
      if (booklets.any((x) => x.id == b.id)) continue;
      booklets.insert(i.clamp(0, booklets.length), b);
    }
    _changed();
  }

  // ———————————————————————————— Listeler (öneriler ve süzgeçler için)

  static List<String> _distinct(Iterable<String> xs) {
    final seen = <String, String>{};
    for (final x in xs) {
      final t = x.trim();
      if (t.isEmpty) continue;
      seen.putIfAbsent(t.toLowerCase(), () => t);
    }
    return seen.values.toList()..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  }

  List<String> get subjects => _distinct([...questions.map((q) => q.subject), ...notes.map((n) => n.subject)]);
  List<String> get grades => _distinct([...questions.map((q) => q.grade), ...notes.map((n) => n.grade)]);
  List<String> topicsOf([String? subject]) => _distinct([
        ...questions.where((q) => subject == null || subject.isEmpty || q.subject == subject).map((q) => q.topic),
        ...notes.where((n) => subject == null || subject.isEmpty || n.subject == subject).map((n) => n.topic),
      ]);
  List<String> outcomesOf([String? subject]) => _distinct([
        ...questions.where((q) => subject == null || subject.isEmpty || q.subject == subject).map((q) => q.outcome),
        ...notes.where((n) => subject == null || subject.isEmpty || n.subject == subject).map((n) => n.outcome),
        for (final l in outcomeLists)
          if (subject == null || subject.isEmpty || l.subject.isEmpty || l.subject.toLowerCase() == subject.toLowerCase()) ...l.labels,
      ]);

  void upsertOutcomeList(OutcomeList l) {
    final i = outcomeLists.indexWhere((x) => x.id == l.id);
    i < 0 ? outcomeLists.add(l) : outcomeLists[i] = l;
    _changed();
  }

  void deleteOutcomeList(String id) {
    outcomeLists.removeWhere((l) => l.id == id);
    _changed();
  }
  List<String> get tags => _distinct([...questions.expand((q) => q.tags), ...notes.expand((n) => n.tags)]);

  // ———————————————————————————— Sınavlarla bağlantı

  /// Sınavlarda kullanılmış banka soruları: kimlik → kaç sınavda.
  static Map<String, int> usage(Iterable<Exam> exams) {
    final out = <String, int>{};
    for (final e in exams) {
      for (final id in e.questions.map((q) => q.bankId).whereType<String>().toSet()) {
        out[id] = (out[id] ?? 0) + 1;
      }
      for (final id in e.openQuestions.map((q) => q.bankId).whereType<String>().toSet()) {
        out[id] = (out[id] ?? 0) + 1;
      }
    }
    return out;
  }

  // ———————————————————————————— Otomatik seçim

  /// [pool] içinden ölçütlere göre soru seçer. Sonuç ana (A) sıradır:
  /// önce konular, her konuda kolaydan zora.
  static List<BankQuestion> autoPick(List<BankQuestion> pool, AutoPick p, {Map<String, int> used = const {}}) {
    final rnd = math.Random(p.seed);
    var candidates = pool.where((q) => q.complete && (!p.opticalOnly || q.type.optical)).toList()..shuffle(rnd);
    if (p.preferUnused) {
      candidates.sort((a, b) => (used[a.id] ?? 0).compareTo(used[b.id] ?? 0));
    }
    final n = math.min(p.count, candidates.length);
    if (n == 0) return const [];

    // Zorluk kotaları (en büyük kalan yöntemiyle yuvarlanır).
    final pcts = [p.easyPct, p.mediumPct, p.hardPct];
    final sum = pcts.fold(0, (a, b) => a + b);
    final quotas = _apportion(n, sum == 0 ? [1, 1, 1] : pcts);

    final byDiff = {for (final d in Difficulty.values) d: candidates.where((q) => q.difficulty == d).toList()};
    final picked = <BankQuestion>[];
    final topicCount = <String, int>{};
    final levelCount = <CognitiveLevel, int>{};

    BankQuestion? take(List<BankQuestion> from) {
      if (from.isEmpty) return null;
      var best = 0;
      if (p.balanceTopics || p.balanceLevels) {
        var bestScore = 1 << 30;
        for (var i = 0; i < from.length; i++) {
          final q = from[i];
          // Düzeyi belirtilmemiş soru, dengeleme açıkken en sona kalır.
          final level = !p.balanceLevels ? 0 : (q.cognitive == CognitiveLevel.none ? 50 : (levelCount[q.cognitive] ?? 0));
          final s = (p.balanceTopics ? (topicCount[q.topicLabel] ?? 0) : 0) * 100000 +
              level * 1000 +
              (p.preferUnused ? (used[q.id] ?? 0) : 0) * 10 +
              i ~/ 50;
          if (s < bestScore) {
            bestScore = s;
            best = i;
          }
        }
      }
      final q = from.removeAt(best);
      topicCount[q.topicLabel] = (topicCount[q.topicLabel] ?? 0) + 1;
      levelCount[q.cognitive] = (levelCount[q.cognitive] ?? 0) + 1;
      return q;
    }

    for (final (i, d) in Difficulty.values.indexed) {
      for (var k = 0; k < quotas[i]; k++) {
        final q = take(byDiff[d]!);
        if (q == null) break;
        picked.add(q);
      }
    }
    // Bir zorlukta yeterli soru yoksa yakın zorluktan tamamla.
    const fallback = {
      Difficulty.easy: [Difficulty.medium, Difficulty.hard],
      Difficulty.medium: [Difficulty.easy, Difficulty.hard],
      Difficulty.hard: [Difficulty.medium, Difficulty.easy],
    };
    for (final (i, d) in Difficulty.values.indexed) {
      final missing = quotas[i] - picked.where((q) => q.difficulty == d).length;
      for (var k = 0; k < missing && picked.length < n; k++) {
        BankQuestion? q;
        for (final alt in fallback[d]!) {
          q = take(byDiff[alt]!);
          if (q != null) break;
        }
        if (q == null) break;
        picked.add(q);
      }
    }
    return sortQuestions(picked, QuestionOrder.byTopic);
  }

  static List<int> _apportion(int n, List<int> weights) {
    final total = weights.fold(0, (a, b) => a + b);
    final raw = [for (final w in weights) n * w / total];
    final out = [for (final r in raw) r.floor()];
    var left = n - out.fold(0, (a, b) => a + b);
    final order = List.generate(weights.length, (i) => i)..sort((a, b) => (raw[b] - out[b]).compareTo(raw[a] - out[a]));
    for (final i in order) {
      if (left <= 0) break;
      out[i]++;
      left--;
    }
    return out;
  }

  /// Soruları istenen düzende sıralar (karışık için [seed] kullanılır).
  static List<BankQuestion> sortQuestions(List<BankQuestion> qs, QuestionOrder order, {int seed = 1}) {
    final l = [...qs];
    switch (order) {
      case QuestionOrder.manual:
        break;
      case QuestionOrder.easyFirst:
        mergeSortStable(l, (a, b) => a.difficulty.index.compareTo(b.difficulty.index));
      case QuestionOrder.byTopic:
        final subjOrder = <String, int>{};
        final topicOrder = <String, int>{};
        for (final q in l) {
          subjOrder.putIfAbsent(q.subject, () => subjOrder.length);
          topicOrder.putIfAbsent('${q.subject}\u0000${q.topic}', () => topicOrder.length);
        }
        mergeSortStable(l, (a, b) {
          final s = subjOrder[a.subject]!.compareTo(subjOrder[b.subject]!);
          if (s != 0) return s;
          final t = topicOrder['${a.subject}\u0000${a.topic}']!.compareTo(topicOrder['${b.subject}\u0000${b.topic}']!);
          if (t != 0) return t;
          return a.difficulty.index.compareTo(b.difficulty.index);
        });
      case QuestionOrder.random:
        l.shuffle(math.Random(seed));
    }
    return l;
  }

  static void mergeSortStable<T>(List<T> l, int Function(T, T) cmp) {
    final indexed = [for (var i = 0; i < l.length; i++) (i, l[i])];
    indexed.sort((a, b) {
      final c = cmp(a.$2, b.$2);
      return c != 0 ? c : a.$1.compareTo(b.$1);
    });
    for (var i = 0; i < l.length; i++) {
      l[i] = indexed[i].$2;
    }
  }

  // ———————————————————————————— Dışa / içe aktarma (.netbank = zip)

  /// Seçilen soruları ve notları (görselleriyle) tek dosyaya paketler.
  Uint8List exportPack({Iterable<String>? questionIds, Iterable<String>? noteIds, bool booklets = true}) {
    final qs = questionIds == null ? questions : [for (final id in questionIds) ?questionById(id)];
    final ns = noteIds == null ? notes : [for (final id in noteIds) ?noteById(id)];
    final ps = [for (final id in {for (final q in qs) ?q.passageId}) ?passageById(id)];
    final imgs = {
      for (final q in qs) ...[if (q.imageId != null) q.imageId!, if (q.solutionImageId != null) q.solutionImageId!],
      for (final q in qs) ...q.choiceImages.whereType<String>(),
      for (final p in ps) ?p.imageId,
      for (final n in ns) ...n.imageIds,
    };
    final a = Archive();
    final json = utf8.encode(jsonEncode({
      'app': 'netice-bank',
      'version': 1,
      'questions': qs.map((q) => q.toJson()).toList(),
      'notes': ns.map((n) => n.toJson()).toList(),
      if (ps.isNotEmpty) 'passages': ps.map((p) => p.toJson()).toList(),
      if (booklets && questionIds == null) 'booklets': this.booklets.map((b) => b.toJson()).toList(),
    }));
    a.addFile(ArchiveFile('banka.json', json.length, json));
    for (final id in imgs) {
      final b = imageBytes(id);
      if (b != null) a.addFile(ArchiveFile('gorseller/$id${_ext(b)}', b.length, b));
    }
    return Uint8List.fromList(ZipEncoder().encode(a));
  }

  /// Paketi bankaya ekler. Aynı kimlikli kayıtlar güncellenir.
  /// Dönen değer: (soru, not, kitapçık) sayıları.
  Future<(int, int, int)> importPack(Uint8List bytes) async {
    final a = ZipDecoder().decodeBytes(bytes);
    final jf = a.findFile('banka.json');
    if (jf == null) throw const FormatException('banka.json yok');
    final j = jsonDecode(utf8.decode(jf.content as List<int>)) as Map<String, dynamic>;
    final ids = <String, String>{};
    for (final f in a.files) {
      if (!f.isFile || !f.name.startsWith('gorseller/')) continue;
      final name = f.name.substring('gorseller/'.length);
      final oldId = name.contains('.') ? name.substring(0, name.lastIndexOf('.')) : name;
      ids[oldId] = await saveImage(Uint8List.fromList(f.content as List<int>));
    }
    String? mapId(String? id) => id == null ? null : ids[id];
    var nq = 0, nn = 0, nb = 0;
    for (final e in (j['questions'] as List? ?? [])) {
      final m = (e as Map).cast<String, dynamic>();
      final q = BankQuestion.fromJson({
        ...m,
        'imageId': mapId(m['imageId'] as String?),
        'solutionImageId': mapId(m['solutionImageId'] as String?),
        if (m['choiceImages'] is List) 'choiceImages': [for (final c in m['choiceImages'] as List) mapId(c as String?)],
      });
      final i = questions.indexWhere((x) => x.id == q.id);
      if (i < 0) {
        questions.add(q);
      } else {
        questions[i] = q;
      }
      nq++;
    }
    for (final e in (j['passages'] as List? ?? [])) {
      final m = (e as Map).cast<String, dynamic>();
      final p = BankPassage.fromJson({...m, 'imageId': mapId(m['imageId'] as String?)});
      final i = passages.indexWhere((x) => x.id == p.id);
      if (i < 0) {
        passages.add(p);
      } else {
        passages[i] = p;
      }
    }
    for (final e in (j['notes'] as List? ?? [])) {
      final m = (e as Map).cast<String, dynamic>();
      final n = BankNote.fromJson({...m, 'imageIds': [for (final id in (m['imageIds'] as List? ?? []).cast<String>()) ?ids[id]]});
      final i = notes.indexWhere((x) => x.id == n.id);
      if (i < 0) {
        notes.add(n);
      } else {
        notes[i] = n;
      }
      nn++;
    }
    for (final e in (j['booklets'] as List? ?? [])) {
      final b = Booklet.fromJson((e as Map).cast<String, dynamic>());
      if (booklets.any((x) => x.id == b.id)) continue;
      booklets.add(b);
      nb++;
    }
    _changed();
    return (nq, nn, nb);
  }

  /// Bankadaki her şeyi siler (Ayarlar > Tüm verileri sil).
  Future<void> wipe() async {
    questions.clear();
    notes.clear();
    booklets.clear();
    outcomeLists.clear();
    passages.clear();
    lastSubject = lastGrade = lastTopic = '';
    _memImages.clear();
    final d = _dir;
    if (d != null && await d.exists()) {
      try {
        await d.delete(recursive: true);
      } catch (_) {}
    }
    notifyListeners();
    await save();
  }
}
