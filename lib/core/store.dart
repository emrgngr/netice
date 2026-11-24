import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../omr/form_code.dart';
import '../omr/form_layout.dart';
import '../omr/omr_reader.dart';
import '../omr/sheet_reader.dart';
import '../omr/template.dart';
import 'campaigns.dart';
import 'grade_scale.dart';
import 'license.dart';
import 'referral.dart';
import 'report.dart';
import 'models.dart';
import 'scoring.dart';
import '../l10n/l10n.dart';

/// Uygulamanın tüm verisi. İlk sürümde cihazda tek bir JSON dosyasında
/// tutulur (internet gerekmez). Sonraki adım: şifreli SQLite + eşitleme.
/// Geri yüklenen yedekteki kayıt sayıları.
class BackupSummary {
  final int students, exams, sheets;
  const BackupSummary(this.students, this.exams, this.sheets);
}

class AppStore extends ChangeNotifier {
  final List<Student> students = [];
  final List<Exam> exams = [];
  final List<Sheet> sheets = [];

  /// Başka firma formları için şablonlar.
  final List<FormTemplate> templates = [];

  /// Okul ve öğretmen bilgileri (rapor başlıkları için).
  SchoolInfo school = const SchoolInfo();

  /// Seçilen not sistemi; boşsa uygulama dilininki.
  GradeScale? gradeScale;

  /// İlk açılış rehberi gösterildi mi?
  bool onboardingDone = false;

  /// Öğretmenin verdiği yıldız (0: henüz vermedi) ve otomatik sorulup sorulmadığı.
  int rating = 0;

  /// Google hesabı (yalnızca ad ve e-posta; parola veya anahtar saklanmaz).
  String? googleEmail;

  /// Uygulama dili (null = cihazın dili).
  String? language;
  String? googleName;

  /// Google Drive'a son yedek zamanı ve otomatik bulut yedeği açık mı.
  DateTime? lastCloudBackup;
  bool cloudAuto = true;

  /// Açılış animasyonunda melodi çalsın mı.
  bool splashSound = true;

  /// Görünüm: 'system' (cihaza göre), 'light' (gündüz) veya 'dark' (gece).
  String themeMode = 'system';

  /// Günlük otomatik yedek alındığında çağrılır (bulut yedeği için).
  Future<void> Function()? onDailyBackup;
  bool ratePrompted = false;

  /// Netice Pro: son doğrulanan abonelik ve zamanı. Doğrulama 40 gün
  /// geçerlidir (çevrimdışı kullanım kesilmesin).
  String? proProduct;
  DateTime? proConfirmedAt;
  static const proGrace = Duration(days: 40);

  /// Bilgisayar sürümünde Pro özellikleri şimdilik açık.
  static bool proFreeOnThisPlatform = !(Platform.isAndroid || Platform.isIOS);

  /// İlk kurulumdan itibaren 14 gün tüm Pro özellikleri ücretsiz (kart gerekmez).
  DateTime? trialStart;

  /// Deneme 14 gün; okula dönüş kampanyasında kurulduysa 30 gün.
  Duration get trialLength => Campaign.trialFor(trialStart);
  bool get inTrial => trialStart != null && DateTime.now().difference(trialStart!) < trialLength;
  int get trialDaysLeft => !inTrial ? 0 : ((trialLength - DateTime.now().difference(trialStart!)).inHours / 24).ceil();

  /// Sınav dönemi paketi (3 ay, tek seferlik) bu tarihe kadar geçerli.
  DateTime? termPassUntil;
  bool get hasTermPass => termPassUntil != null && DateTime.now().isBefore(termPassUntil!);

  /// Sınav dönemi paketi alındı: süre bugünden ya da kalan süreden 90 gün uzar.
  void addTermPass(DateTime now, [Duration length = const Duration(days: 90)]) {
    final from = termPassUntil != null && termPassUntil!.isAfter(now) ? termPassUntil! : now;
    termPassUntil = from.add(length);
    _changed();
  }

  /// Arkadaşını davet et: bu cihazın davet kodu (ilk istendiğinde üretilir).
  String? inviteCode;

  /// Arkadaşın davet kodu girildiyse (Pro ekranında %15 indirim gösterilir).
  String? appliedInvite;

  /// İndirimli abonelik alındıktan sonra davet edene gönderilecek teşekkür kodu.
  String? thanksCode;

  /// Kullanılmış teşekkür kodlarının arkadaş kimlikleri (her biri bir kez).
  final List<String> redeemedThanks = [];

  /// Davet ödülüyle kazanılan Pro bu tarihe kadar geçerli.
  DateTime? bonusProUntil;
  bool get hasBonusPro => bonusProUntil != null && DateTime.now().isBefore(bonusProUntil!);

  String get myInviteCode {
    if (inviteCode == null) {
      inviteCode = Referral.newInviteCode();
      _changed();
    }
    return inviteCode!;
  }

  /// Arkadaşın davet kodunu uygular. Hata varsa açıklamasını döndürür.
  String? applyInvite(String raw) {
    if (!Referral.isValidInvite(raw)) return tr('Davet kodu geçersiz. Kodu kontrol edip yeniden yazın.');
    final code = Referral.format(raw);
    if (code == myInviteCode) return tr('Kendi davet kodunuzu kullanamazsınız.');
    appliedInvite = code;
    _changed();
    return null;
  }

  void clearInvite() {
    appliedInvite = null;
    _changed();
  }

  /// İndirimli yıllık abonelik alındı: davet edene teşekkür kodu üret.
  void onInvitePurchase() {
    final inv = appliedInvite;
    if (inv == null || thanksCode != null) return;
    thanksCode = Referral.thanksCode(invite: inv, friend: myInviteCode);
    _changed();
  }

  /// Arkadaştan gelen teşekkür kodu: 1 ay ek Pro. Hata varsa açıklamasını döndürür.
  String? redeemThanks(String raw, {DateTime? now}) {
    final friend = Referral.verifyThanks(raw, myInvite: myInviteCode);
    if (friend == null) return tr('Teşekkür kodu geçersiz ya da sizin davet kodunuza ait değil.');
    if (redeemedThanks.contains(friend)) return tr('Bu teşekkür kodu daha önce kullanıldı.');
    if (redeemedThanks.length >= Referral.maxRewards) {
      return tr('Davet ödülü sınırına ulaştınız ({0} ay). Teşekkürler!', [Referral.maxRewards]);
    }
    final t = now ?? DateTime.now();
    var from = t;
    for (final d in [bonusProUntil, termPassUntil]) {
      if (d != null && d.isAfter(from)) from = d;
    }
    bonusProUntil = from.add(Referral.rewardLength);
    redeemedThanks.add(friend);
    _changed();
    return null;
  }

  /// Kurum lisansı (okul, dershane, akademi…): tüm Pro özellikleri; yönetici
  /// koduyla ayrıca kurum yönetici paneli.
  InstitutionLicense? license;
  bool get hasLicense => license != null && license!.activeAt(DateTime.now());
  bool get isInstitutionAdmin => hasLicense && license!.admin;

  /// Kurum yönetici paneli: yönetici lisansında; denemede ve bilgisayar
  /// sürümünde tanıtım için açık.
  bool get canUseAdminPanel => isInstitutionAdmin || proFreeOnThisPlatform || (inTrial && !hasLicense);

  void setLicense(InstitutionLicense? l) {
    license = l;
    if (l != null && school.name.trim().isEmpty) {
      school = school.copyWith(name: l.institution);
    }
    _changed();
  }

  bool get isPro =>
      proFreeOnThisPlatform ||
      inTrial ||
      hasTermPass ||
      hasBonusPro ||
      hasLicense ||
      (proConfirmedAt != null && DateTime.now().difference(proConfirmedAt!) < proGrace);

  /// Abonelik var mı (bilgisayar istisnası hariç)?
  bool get hasSubscription => proConfirmedAt != null && DateTime.now().difference(proConfirmedAt!) < proGrace;

  /// Pro + Yapay Zekâ aboneliğinin son doğrulanma zamanı (ayda 300 soru).
  DateTime? aiPlanConfirmedAt;
  bool get hasAiPlan => aiPlanConfirmedAt != null && DateTime.now().difference(aiPlanConfirmedAt!) < proGrace;

  void confirmPro(String product) {
    // Pro + Yapay Zekâ, sıradan Pro doğrulamasıyla ezilmesin.
    if (product == aiYearlyProductId) {
      aiPlanConfirmedAt = DateTime.now();
      proProduct = product;
    } else if (!hasAiPlan) {
      proProduct = product;
    }
    proConfirmedAt = DateTime.now();
    _changed();
  }

  /// pro.dart'taki kimlikle aynı (döngüsel içe aktarmayı önlemek için burada).
  static const aiYearlyProductId = 'netice_pro_yz_yillik';

  /// Raporlarda kullanılacak okul bilgisi: resmi başlık Pro özelliğidir.
  /// Kurum lisansında kurum adı lisanstan gelir; öğretmenler değiştiremez.
  SchoolInfo get reportSchool {
    var s = isPro ? school : school.copyWith(officialHeader: false);
    if (hasLicense) s = s.copyWith(name: license!.institution);
    return s;
  }

  /// Ana sayfadaki öneri kartı bu tarihe kadar gizli.
  DateTime? promoHiddenUntil;
  bool get showPromo => promoHiddenUntil == null || DateTime.now().isAfter(promoHiddenUntil!);

  void hidePromo([Duration d = const Duration(days: 7)]) {
    promoHiddenUntil = DateTime.now().add(d);
    _changed();
  }

  /// Yeterince kullanıldıysa (30+ kâğıt) bir kez yıldız istenir.
  bool get shouldAskRating => !ratePrompted && rating == 0 && sheets.length >= 30;

  File? _file;
  static final _rnd = math.Random();
  bool loaded = false;

  /// Bu dönem okunan kâğıt sayısı (zaman kazancı sayacı için).
  int get readCount => sheets.length;

  /// Kâğıt başına elle tahmini 1,5 dk (hesaplama ekranda açıklanır).
  Duration get timeSaved => Duration(seconds: (readCount * 90).round());

  Map<String, Student> get studentById => {for (final s in students) s.id: s};

  List<String> get classNames {
    final set = <String>{...students.map((s) => s.className), ...exams.map((e) => e.className)}
      ..removeWhere((c) => c.isEmpty);
    return set.toList()..sort();
  }

  List<Student> studentsOf(String className) => students.where((s) => s.className == className).toList()
    ..sort((a, b) {
      // Sayıca sırala (2, 10); sayı değilse yazı olarak.
      final x = int.tryParse(a.number), y = int.tryParse(b.number);
      if (x != null && y != null && x != y) return x.compareTo(y);
      return a.number.compareTo(b.number);
    });

  List<Sheet> sheetsOf(String examId) => sheets.where((s) => s.examId == examId).toList();

  List<Result> resultsOf(Exam exam) => Scorer.scoreAll(exam, sheetsOf(exam.id));

  Exam? examById(String id) => exams.where((e) => e.id == id).firstOrNull;

  bool _migrated = false;

  Future<void> load({Directory? dir}) async {
    final base = dir ?? await getApplicationSupportDirectory();
    _file = File('${base.path}${Platform.pathSeparator}netice_data.json');
    if (await _file!.exists()) {
      _apply(jsonDecode(await _file!.readAsString()) as Map<String, dynamic>);
      if (numberMissing() > 0 || _migrated) await save();
      _migrated = false;
    } else {
      seedDemo();
      await save();
    }
    if (trialStart == null) {
      trialStart = DateTime.now();
      await save();
    }
    await _loadLicense();
    _cleanImages();
    loaded = true;
    notifyListeners();
  }

  /// Kayıtlı lisans kodu her açılışta yeniden doğrulanır (dosya elle
  /// değiştirilse bile imzasız kod kabul edilmez).
  String? _pendingLicense;
  Future<void> _loadLicense() async {
    final code = _pendingLicense;
    _pendingLicense = null;
    if (code != null) license = await InstitutionLicense.verify(code);
  }

  /// Kayıtlar sırayla yazılır; üst üste gelen iki kayıt aynı geçici dosyayı
  /// paylaşıp birbirini bozmasın.
  Future<void>? _saving;

  Future<void> save() {
    final prev = _saving;
    final next = prev == null ? _write() : prev.catchError((_) {}).then((_) => _write());
    _saving = next;
    return next;
  }

  Map<String, dynamic> toJsonMap() => {
        'app': 'netice',
        'version': 1,
        'savedAt': DateTime.now().toIso8601String(),
        'students': students.map((s) => s.toJson()).toList(),
        'exams': exams.map((e) => e.toJson()).toList(),
        'sheets': sheets.map((s) => s.toJson()).toList(),
        'templates': templates.map((t) => t.toJson()).toList(),
        'school': school.toJson(),
        if (gradeScale != null) 'gradeScale': gradeScale!.toJson(),
        'onboardingDone': onboardingDone,
        'rating': rating,
        'ratePrompted': ratePrompted,
        'googleEmail': googleEmail,
        if (language != null) 'language': language,
        'googleName': googleName,
        'lastCloudBackup': lastCloudBackup?.toIso8601String(),
        'cloudAuto': cloudAuto,
        'splashSound': splashSound,
        'themeMode': themeMode,
        'promoHiddenUntil': promoHiddenUntil?.toIso8601String(),
        'proProduct': proProduct,
        'trialStart': trialStart?.toIso8601String(),
        'proConfirmedAt': proConfirmedAt?.toIso8601String(),
        if (aiPlanConfirmedAt != null) 'aiPlanConfirmedAt': aiPlanConfirmedAt!.toIso8601String(),
        if (termPassUntil != null) 'termPassUntil': termPassUntil!.toIso8601String(),
        if (license != null) 'license': license!.code,
        if (parentSent.isNotEmpty) 'parentSent': {for (final e in parentSent.entries) e.key: e.value.toList()},
        if (inviteCode != null) 'inviteCode': inviteCode,
        if (appliedInvite != null) 'appliedInvite': appliedInvite,
        if (thanksCode != null) 'thanksCode': thanksCode,
        if (redeemedThanks.isNotEmpty) 'redeemedThanks': redeemedThanks,
        if (bonusProUntil != null) 'bonusProUntil': bonusProUntil!.toIso8601String(),
      };

  void _apply(Map<String, dynamic> j) {
    final st = (j['students'] as List).map((e) => Student.fromJson(e as Map<String, dynamic>)).toList();
    final ex = (j['exams'] as List).map((e) => Exam.fromJson(e as Map<String, dynamic>)).toList();
    final sh = (j['sheets'] as List).map((e) => Sheet.fromJson(e as Map<String, dynamic>)).toList();
    // Eski sürümlerde sınavlar 6 haneli numarayla açılıyordu. Henüz hiç
    // form okunmamış sınavları 10 haneye geçir; okunmuş olanlar basılı
    // formlarla uyumlu kalsın diye 6'da kalır (örnek sınavlar hariç).
    final scanned = {for (final s in sh) s.examId};
    final raw = j['exams'] as List;
    for (var i = 0; i < ex.length; i++) {
      final r = raw[i] as Map;
      if (!r.containsKey('numberDigits') && (_isDemoExam(ex[i].id) || !scanned.contains(ex[i].id))) {
        ex[i] = ex[i].copyWith(numberDigits: 10);
        _migrated = true;
      }
    }
    students
      ..clear()
      ..addAll(st);
    exams
      ..clear()
      ..addAll(ex);
    sheets
      ..clear()
      ..addAll(sh);
    templates
      ..clear()
      ..addAll([for (final t in (j['templates'] as List?) ?? const []) FormTemplate.fromJson((t as Map).cast<String, dynamic>())]);
    school = j['school'] is Map ? SchoolInfo.fromJson((j['school'] as Map).cast<String, dynamic>()) : const SchoolInfo();
    gradeScale = GradeScale.fromJson(j['gradeScale']);
    Level.useScale(gradeScale);
    onboardingDone = j['onboardingDone'] as bool? ?? onboardingDone;
    rating = (j['rating'] as num?)?.toInt() ?? rating;
    proProduct = j['proProduct'] as String? ?? proProduct;
    trialStart = DateTime.tryParse('${j['trialStart'] ?? ''}') ?? trialStart;
    proConfirmedAt = DateTime.tryParse('${j['proConfirmedAt'] ?? ''}') ?? proConfirmedAt;
    aiPlanConfirmedAt = DateTime.tryParse('${j['aiPlanConfirmedAt'] ?? ''}') ?? aiPlanConfirmedAt;
    termPassUntil = DateTime.tryParse('${j['termPassUntil'] ?? ''}') ?? termPassUntil;
    if (j['license'] is String) _pendingLicense = j['license'] as String;
    parentSent
      ..clear()
      ..addAll({
        if (j['parentSent'] is Map)
          for (final e in (j['parentSent'] as Map).entries)
            if (e.value is List) '${e.key}': {for (final v in e.value as List) '$v'},
      });
    inviteCode = j['inviteCode'] as String? ?? inviteCode;
    appliedInvite = j['appliedInvite'] as String? ?? appliedInvite;
    thanksCode = j['thanksCode'] as String? ?? thanksCode;
    if (j['redeemedThanks'] is List) {
      redeemedThanks
        ..clear()
        ..addAll([for (final x in j['redeemedThanks'] as List) '$x']);
    }
    bonusProUntil = DateTime.tryParse('${j['bonusProUntil'] ?? ''}') ?? bonusProUntil;
    promoHiddenUntil = DateTime.tryParse('${j['promoHiddenUntil'] ?? ''}') ?? promoHiddenUntil;
    ratePrompted = j['ratePrompted'] as bool? ?? ratePrompted;
    splashSound = j['splashSound'] as bool? ?? splashSound;
    final tm = j['themeMode'];
    if (tm == 'system' || tm == 'light' || tm == 'dark') themeMode = tm as String;
    language = j['language'] as String? ?? language;
    if (j.containsKey('googleEmail')) {
      googleEmail = j['googleEmail'] as String?;
      googleName = j['googleName'] as String?;
      lastCloudBackup = DateTime.tryParse(j['lastCloudBackup'] as String? ?? '');
      cloudAuto = j['cloudAuto'] as bool? ?? true;
    }
  }

  /// Velilere toplu gönderimde karnesi gönderilenler: sınav → öğrenciler.
  final Map<String, Set<String>> parentSent = {};

  bool parentSentFor(String examId, String studentId) => parentSent[examId]?.contains(studentId) ?? false;

  void markParentSent(String examId, String studentId, {bool sent = true}) {
    final set = parentSent.putIfAbsent(examId, () => <String>{});
    if (sent ? !set.add(studentId) : !set.remove(studentId)) return;
    if (set.isEmpty) parentSent.remove(examId);
    _changed();
  }

  /// Gece/gündüz görünümünü değiştirir ('system', 'light', 'dark').
  void setThemeMode(String mode) {
    if (mode == themeMode) return;
    themeMode = mode;
    _changed();
  }

  /// Dili değiştirir; arayüz bu dilde yeniden çizilir.
  void setLanguage(String? code) {
    language = code;
    L10n.use(code);
    _changed();
  }

  void setGoogleAccount(String? email, String? name) {
    googleEmail = email;
    googleName = name;
    _changed();
  }

  void setSplashSound(bool v) {
    splashSound = v;
    _changed();
  }

  void setCloudAuto(bool v) {
    cloudAuto = v;
    _changed();
  }

  void markCloudBackup(DateTime? t) {
    lastCloudBackup = t;
    _changed();
  }

  void setRating(int stars) {
    rating = stars;
    ratePrompted = true;
    _changed();
  }

  void markRatePrompted() {
    ratePrompted = true;
    _changed();
  }

  void finishOnboarding() {
    onboardingDone = true;
    _changed();
  }

  /// Taşınabilir yedek dosyasının içeriği (tüm sınıflar, sınavlar, kâğıtlar ve okul bilgisi).
  String exportBackup() => const JsonEncoder.withIndent(' ').convert(toJsonMap());

  /// Yedeği okur ve mevcut verinin yerine koyar. Dosya Netice yedeği değilse
  /// [FormatException] atar ve hiçbir şeyi değiştirmez.
  Future<BackupSummary> restoreBackup(String text) async {
    final Map<String, dynamic> j;
    try {
      j = jsonDecode(text) as Map<String, dynamic>;
      if (j['students'] is! List || j['exams'] is! List || j['sheets'] is! List) throw const FormatException();
    } catch (_) {
      throw FormatException(tr('Bu dosya bir Netice yedeği değil.'));
    }
    // Önce mevcut hâlin bir yedeğini al; yanlış dosya seçilirse geri dönülebilsin.
    await _autoBackup(force: true);
    final probe = AppStore().._apply(j); // ayrıştırma hatası mevcut veriyi bozmasın
    final (email, name, last, auto) = (googleEmail, googleName, lastCloudBackup, cloudAuto);
    final (pp, pc, ts, aic) = (proProduct, proConfirmedAt, trialStart, aiPlanConfirmedAt);
    final (tp, lic) = (termPassUntil, license);
    final (inv, ai, tc, bp) = (inviteCode, appliedInvite, thanksCode, bonusProUntil);
    final rt = [...redeemedThanks];
    _apply(probe.toJsonMap());
    // Abonelik, paket ve lisans bu cihaza aittir; yedek dosyasından gelmez.
    proProduct = pp;
    proConfirmedAt = pc;
    aiPlanConfirmedAt = aic;
    trialStart = ts;
    termPassUntil = tp;
    license = lic;
    _pendingLicense = null;
    // Davet kodu ve ödülleri de bu cihaza aittir.
    inviteCode = inv;
    appliedInvite = ai;
    thanksCode = tc;
    bonusProUntil = bp;
    redeemedThanks
      ..clear()
      ..addAll(rt);
    // Hesap bu cihaza aittir; yedekten gelmez.
    googleEmail = email;
    googleName = name;
    lastCloudBackup = last;
    cloudAuto = auto;
    notifyListeners();
    await save();
    return BackupSummary(students.length, exams.length, sheets.length);
  }

  Directory? get _backupDir =>
      _file == null ? null : Directory('${_file!.parent.path}${Platform.pathSeparator}yedekler');

  /// Otomatik yedekler, en yenisi başta.
  List<File> autoBackups() {
    final d = _backupDir;
    if (d == null || !d.existsSync()) return [];
    return d.listSync().whereType<File>().where((f) => f.path.endsWith('.json')).toList()
      ..sort((a, b) => b.path.compareTo(a.path));
  }

  /// Günde bir otomatik yedek; son 14 yedek saklanır.
  Future<void> _autoBackup({bool force = false}) async {
    final d = _backupDir;
    if (d == null) return;
    final now = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    final day = '${now.year}${two(now.month)}${two(now.day)}';
    final existing = autoBackups();
    if (!force && existing.any((f) => f.uri.pathSegments.last.startsWith('netice_yedek_$day'))) return;
    await d.create(recursive: true);
    final name = 'netice_yedek_${day}_${two(now.hour)}${two(now.minute)}${two(now.second)}.json';
    await File('${d.path}${Platform.pathSeparator}$name').writeAsString(jsonEncode(toJsonMap()));
    for (final old in autoBackups().skip(14)) {
      try {
        await old.delete();
      } catch (_) {}
    }
    if (!force && onDailyBackup != null) {
      // Bulut yedeği arka planda; hata asıl kaydı etkilemez.
      unawaited(onDailyBackup!().catchError((_) {}));
    }
  }

  Future<void> _write() async {
    final f = _file;
    if (f == null) return;
    final tmp = File('${f.path}.tmp');
    await tmp.writeAsString(jsonEncode(toJsonMap()));
    await tmp.rename(f.path);
    try {
      await _autoBackup();
    } catch (_) {
      // Yedek alınamaması asıl kaydı engellemesin.
    }
  }

  void _changed() {
    notifyListeners();
    save();
  }

  /// Listeler dışarıdan toplu değiştirildikten sonra (ör. ortak sınav
  /// aktarımı) ekranları yeniler ve kaydeder.
  void commit() => _changed();

  static bool _isDemoExam(String id) => id.startsWith('demo_exam');
  static bool _isDemoStudent(String id) => id.startsWith('demo_') || id.startsWith('demoB_');

  /// İlk açılışta eklenen örnek sınıf ve sınavlar duruyor mu?
  bool get hasDemo => exams.any((e) => _isDemoExam(e.id)) || students.any((s) => _isDemoStudent(s.id));

  /// Örnek verileri siler; öğretmenin kendi kayıtlarına dokunmaz.
  /// Bu cihazdaki tüm öğrenci, sınav, kâğıt ve okul bilgilerini siler.
  /// [backups] true ise otomatik yedekler de silinir; değilse silmeden önce
  /// son hâlin bir kopyası otomatik yedeklere eklenir (geri dönüş için).
  Future<void> wipeAll({bool backups = false}) async {
    if (!backups) {
      try {
        await _autoBackup(force: true);
      } catch (_) {}
    }
    students.clear();
    exams.clear();
    sheets.clear();
    school = const SchoolInfo();
    _cleanImages();
    if (backups) {
      for (final f in autoBackups()) {
        try {
          await f.delete();
        } catch (_) {}
      }
    }
    notifyListeners();
    await save();
    if (backups) {
      // Kayıt sırasında alınan günlük yedeği de temizle.
      for (final f in autoBackups()) {
        try {
          await f.delete();
        } catch (_) {}
      }
    }
  }

  void clearDemo() {
    sheets.removeWhere((s) => _isDemoExam(s.examId));
    _cleanImages();
    exams.removeWhere((e) => _isDemoExam(e.id));
    students.removeWhere((s) => _isDemoStudent(s.id));
    _changed();
  }

  void setGradeScale(GradeScale? s) {
    gradeScale = s;
    Level.useScale(s);
    _changed();
  }

  void setSchool(SchoolInfo info) {
    school = info;
    _changed();
  }

  /// Öğrencileri ekler (aynı sınıfta aynı numara ya da numarasızsa aynı ad
  /// varsa atlar). Numarası olmayanlara sıra numarası verilir; kaç kişiye
  /// verildiğini döndürür.
  int addStudents(List<Student> list) {
    final existing = {for (final s in students) '${s.className}|${s.number}'};
    final names = {for (final s in students) '${s.className}|${s.fullName.toLowerCase()}'};
    // Listede kayıtlı öğrencinin veli telefonu geldiyse güncelle.
    for (final s in list.where((s) => s.parentPhone.isNotEmpty && s.number.isNotEmpty)) {
      final i = students.indexWhere((x) => x.className == s.className && x.number == s.number);
      if (i >= 0 && students[i].parentPhone != s.parentPhone) students[i] = students[i].copyWith(parentPhone: s.parentPhone);
    }
    students.addAll(list.where((s) => s.number.isEmpty
        ? !names.contains('${s.className}|${s.fullName.toLowerCase()}')
        : !existing.contains('${s.className}|${s.number}')));
    final n = numberMissing();
    _changed();
    return n;
  }

  void updateStudent(Student st) {
    final i = students.indexWhere((s) => s.id == st.id);
    if (i >= 0) students[i] = st;
    numberMissing();
    _changed();
  }

  /// Numarası olmayan öğrencilere (dershane, kurs… numara kullanmayan
  /// kurumlar) sınıfında kullanılmayan en küçük sayıdan başlayarak sıra
  /// numarası verir; böylece isimli formlar ve işaretlenen numara öğrenciyle
  /// eşleşir. Kaç öğrenciye numara verildiğini döndürür.
  int numberMissing() {
    final used = <String, Set<int>>{};
    for (final s in students) {
      final n = int.tryParse(s.number);
      if (n != null) used.putIfAbsent(s.className, () => {}).add(n);
    }
    // Numarasızlar sınıf içinde ad soyad alfabetik sırasıyla numaralanır.
    final missing = [
      for (var i = 0; i < students.length; i++)
        if (students[i].number.trim().isEmpty) i
    ]..sort((a, b) {
        final x = students[a], y = students[b];
        final c = x.className.compareTo(y.className);
        if (c != 0) return c;
        final n = alphaKey(x.firstName).compareTo(alphaKey(y.firstName));
        return n != 0 ? n : alphaKey(x.lastName).compareTo(alphaKey(y.lastName));
      });
    var count = 0;
    for (final i in missing) {
      final s = students[i];
      final set = used.putIfAbsent(s.className, () => {});
      var n = 1;
      while (set.contains(n)) {
        n++;
      }
      set.add(n);
      students[i] = s.copyWith(number: '$n');
      count++;
    }
    return count;
  }

  /// Öğrenciyi siler; okunmuş kâğıtları "eşleşmeyen" olarak kalır.
  void deleteStudent(String id) {
    students.removeWhere((s) => s.id == id);
    _changed();
  }

  void upsertExam(Exam exam) {
    final i = exams.indexWhere((e) => e.id == exam.id);
    if (i >= 0) {
      exams[i] = exam;
    } else {
      exams.insert(0, exam);
    }
    _changed();
  }

  void deleteExam(String id) {
    exams.removeWhere((e) => e.id == id);
    sheets.removeWhere((s) => s.examId == id);
    _cleanImages();
    _changed();
  }

  /// Seçilen sınavları ve okunan kâğıtlarını kaldırır; öğrenciler ve diğer
  /// sınavlar kalır. Görüntüler hemen silinmez, böylece [restoreExams] ile
  /// geri alınabilir; [forgetRemoved] geri alma süresi bitince çağrılır.
  RemovedExams removeExams(Iterable<String> ids) {
    final set = ids.toSet();
    final removed = RemovedExams(
      [for (var i = 0; i < exams.length; i++) if (set.contains(exams[i].id)) (i, exams[i])],
      sheets.where((s) => set.contains(s.examId)).toList(),
    );
    exams.removeWhere((e) => set.contains(e.id));
    sheets.removeWhere((s) => set.contains(s.examId));
    _changed();
    return removed;
  }

  /// [removeExams] ile kaldırılanları eski yerlerine geri koyar.
  void restoreExams(RemovedExams r) {
    final back = <String>{};
    for (final (i, e) in r.exams) {
      if (exams.any((x) => x.id == e.id)) continue;
      exams.insert(i.clamp(0, exams.length), e);
      back.add(e.id);
    }
    sheets.addAll(r.sheets.where((s) => back.contains(s.examId)));
    _changed();
  }

  /// Tek bir okunan kâğıdı kaldırır (öğrenci ve sınav kalır). Kâğıdın
  /// listedeki yerini döndürür; bulunamazsa -1. Görüntü [forgetRemoved]
  /// çağrılana kadar silinmez, böylece [restoreSheet] ile geri alınabilir.
  int removeSheet(Sheet sheet) {
    final i = sheets.indexWhere((s) => identical(s, sheet));
    if (i < 0) return -1;
    sheets.removeAt(i);
    _changed();
    return i;
  }

  /// [removeSheet] ile kaldırılan kâğıdı eski yerine koyar.
  void restoreSheet(int index, Sheet sheet) {
    if (index < 0 || sheets.any((s) => identical(s, sheet))) return;
    if (examById(sheet.examId) == null) return;
    sheets.insert(index.clamp(0, sheets.length), sheet);
    _changed();
  }

  /// Geri alınmayan silmeden kalan görüntüleri temizler.
  void forgetRemoved() => _cleanImages();

  /// Okunan kâğıdı kaydeder. Aynı öğrencinin önceki kâğıdı varsa yenisiyle değiştirir.
  /// Makine kodundaki sınav koduna karşılık gelen sınav.
  /// Önce tam eşleşen, yoksa kitapçık bitleriyle eşleşen sınav aranır.
  Exam? examByCode(FormCode code) =>
      exams.where((e) => FormCode.examCodeOf(e.id) == code.examCode).firstOrNull ??
      exams.where((e) => code.resolve(FormCode.examCodeOf(e.id)) != null).firstOrNull;

  /// Okunan kâğıdı kaydeder. Formdaki makine kodu başka bir sınavı gösteriyorsa
  /// kâğıt o sınava kaydedilir (dönen kâğıdın examId'si farklı olur).
  /// Öğrenci, işaretlenen numaradan; o yoksa makine kodundan bulunur.
  Sheet addScan(Exam exam, OmrResult r) {
    final code = r.code;
    final other = code == null ? null : examByCode(code);
    // Yalnızca aynı yapıdaki (soru/şık sayısı) sınava yönlendirilir; okuma o yapıya göre yapıldı.
    final target = other != null &&
            other.questionCount == exam.questionCount &&
            other.choiceCount == exam.choiceCount &&
            other.bookletCount == exam.bookletCount
        ? other
        : exam;
    Student? st;
    final numbers = [
      if (r.studentNumber != null) int.tryParse(r.studentNumber!),
      code?.studentNumber,
    ].whereType<int>();
    for (final n in numbers) {
      st = studentsOf(target.className).where((s) => int.tryParse(s.number) == n).firstOrNull;
      if (st != null) break;
    }
    final codeBooklet = code?.resolve(FormCode.examCodeOf(target.id))?.booklet;
    var booklet = target.hasBooklets ? (r.booklet ?? codeBooklet ?? 0) : 0;
    if (booklet >= target.bookletCount) booklet = 0;
    final answers = target.toMasterOrder(booklet, r.answers);
    lastScanStatus = ScanStatus.added;
    var studentId = st?.id;
    var openScores = const <double?>[];
    if (st != null) {
      final old = sheets.where((s) => s.examId == target.id && s.studentId == st!.id).firstOrNull;
      if (old != null) {
        final diff = differingAnswers(old.answers, answers);
        if (diff == 0) {
          // Aynı kâğıt yeniden okutuldu: öncekini (ve verilen kararları) koru.
          lastScanStatus = ScanStatus.duplicate;
          return old;
        }
        if (diff <= math.max(2, answers.length ~/ 10)) {
          // Aynı kâğıdın yeniden okunuşu (birkaç işaret düzeltilmiş): yerine geçer.
          lastScanStatus = ScanStatus.replaced;
          openScores = old.openScores;
          _deleteImage(old);
          sheets.remove(old);
        } else {
          // Aynı numarayla bambaşka cevaplar: büyük olasılıkla numarası yanlış
          // işaretlenmiş başka bir öğrenci. Eskiye dokunma, yeniyi kontrole al.
          lastScanStatus = ScanStatus.conflict;
          studentId = null;
        }
      }
    }
    final sheet = Sheet(
      examId: target.id,
      studentId: studentId,
      answers: answers,
      booklet: booklet,
      openScores: openScores,
      readNumber: studentId == null ? (r.numberPattern ?? r.studentNumber) : null,
      mini: r.mini,
    );
    sheets.add(sheet);
    _changed();
    return sheet;
  }

  /// İşaretli kâğıt görüntüleri: düzleştirilmiş fotoğraf, yalnızca bu cihazda.
  Directory? get _imageDir =>
      _file == null ? null : Directory('${_file!.parent.path}${Platform.pathSeparator}kagitlar');

  File? sheetImageFile(Sheet s) {
    final d = _imageDir;
    if (d == null || s.imageId == null) return null;
    final f = File('${d.path}${Platform.pathSeparator}${s.imageId}.jpg');
    return f.existsSync() ? f : null;
  }

  /// Okunan kâğıdın görüntüsünü kaydeder ve kâğıda bağlar.
  Future<Sheet?> attachSheetImage(Sheet sheet, Uint8List jpeg) async {
    final d = _imageDir;
    if (d == null) return null;
    final i = sheets.indexOf(sheet);
    if (i < 0) return null;
    await d.create(recursive: true);
    final id = '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}${_rnd.nextInt(1 << 20).toRadixString(36)}';
    await File('${d.path}${Platform.pathSeparator}$id.jpg').writeAsBytes(jpeg, flush: true);
    _deleteImage(sheet);
    final j = sheets.indexOf(sheet);
    if (j < 0) return null;
    final updated = sheet.copyWith(imageId: id);
    sheets[j] = updated;
    _changed();
    return updated;
  }

  void _deleteImage(Sheet s) {
    final f = sheetImageFile(s);
    if (f == null) return;
    try {
      f.deleteSync();
    } catch (_) {}
  }

  /// Hiçbir kâğıda bağlı olmayan görüntüleri siler.
  void _cleanImages() {
    final d = _imageDir;
    if (d == null || !d.existsSync()) return;
    final used = {for (final s in sheets) if (s.imageId != null) '${s.imageId}.jpg'};
    for (final f in d.listSync().whereType<File>()) {
      if (!used.contains(f.uri.pathSegments.last)) {
        try {
          f.deleteSync();
        } catch (_) {}
      }
    }
  }

  FormTemplate? templateById(String? id) => id == null ? null : templates.where((t) => t.id == id).firstOrNull;

  /// Şablonu ekler ya da günceller.
  void saveTemplate(FormTemplate t) {
    final i = templates.indexWhere((x) => x.id == t.id);
    if (i >= 0) {
      templates[i] = t;
    } else {
      templates.add(t);
    }
    _changed();
  }

  /// Şablonu siler; onu kullanan sınavlar Netice formuna döner.
  void deleteTemplate(String id) {
    templates.removeWhere((t) => t.id == id);
    for (var i = 0; i < exams.length; i++) {
      if (exams[i].templateId == id) exams[i] = exams[i].copyWith(clearTemplate: true);
    }
    _changed();
  }

  /// Son [addScan] çağrısının sonucu (arayüz uyarıları için).
  ScanStatus lastScanStatus = ScanStatus.added;

  /// İki cevap listesinde işaretleri farklı olan soru sayısı.
  static int differingAnswers(List<Answer> a, List<Answer> b) {
    var d = (a.length - b.length).abs();
    for (var i = 0; i < math.min(a.length, b.length); i++) {
      final x = a[i].marked, y = b[i].marked;
      if (x.length != y.length || !x.containsAll(y)) d++;
    }
    return d;
  }

  /// Kontroldeki kâğıdı öğrenciye verir; öğrencinin bu sınavda başka kâğıdı
  /// varsa o silinir (yeni kâğıt onun yerine geçer).
  void assignSheet(Sheet sheet, String studentId) {
    final i = sheets.indexOf(sheet);
    if (i < 0) return;
    for (final old in sheets.where((s) => s.examId == sheet.examId && s.studentId == studentId && !identical(s, sheet))) {
      _deleteImage(old);
    }
    sheets.removeWhere((s) => s.examId == sheet.examId && s.studentId == studentId && !identical(s, sheet));
    sheets[sheets.indexOf(sheet)] = sheet.copyWith(studentId: studentId);
    _changed();
  }

  /// Okunan numarası birebir tutan ve bu sınavda zaten kâğıdı olan öğrenci
  /// (çakışan kâğıt için "öncekinin yerine geçsin" seçeneği).
  Student? conflictOwner(Sheet sheet) {
    final read = sheet.readNumber;
    final exam = examById(sheet.examId);
    if (read == null || read.contains('?') || exam == null) return null;
    final have = sheetsOf(exam.id).map((s) => s.studentId).toSet();
    return studentsOf(exam.className)
        .where((s) => have.contains(s.id) && numberDistance(read, s.number) == 0)
        .firstOrNull;
  }

  /// Bu sınavda kâğıdı okutulmamış öğrenciler.
  List<Student> missingStudents(Exam exam) {
    final have = sheetsOf(exam.id).map((s) => s.studentId).toSet();
    return studentsOf(exam.className).where((s) => !have.contains(s.id)).toList();
  }

  /// Eşleşmeyen kâğıt için olası öğrenciler: okunan numaraya en yakın olanlar
  /// (bu sınavda kâğıdı olmayanlar). Okunamayan rakamlar ('?') her rakama uyar;
  /// en fazla iki rakam farkı olanlar, en yakından uzağa sıralanır.
  List<Student> suggestStudents(Sheet sheet, {int limit = 3}) {
    final read = sheet.readNumber;
    final exam = examById(sheet.examId);
    if (read == null || exam == null) return const [];
    final taken = sheetsOf(exam.id).map((s) => s.studentId).toSet();
    final scored = <(Student, int)>[];
    for (final s in studentsOf(exam.className)) {
      if (taken.contains(s.id)) continue;
      final d = numberDistance(read, s.number);
      if (d != null && d <= 2) scored.add((s, d));
    }
    scored.sort((a, b) => a.$2.compareTo(b.$2));
    return [for (final e in scored.take(limit)) e.$1];
  }

  /// Okunan numara ile öğrenci numarası arasındaki rakam farkı; numara
  /// karşılaştırılamıyorsa null.
  static int? numberDistance(String read, String number) {
    final digits = number.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty || digits.length > read.length) return null;
    final n = digits.padLeft(read.length, '0');
    var d = 0;
    for (var i = 0; i < read.length; i++) {
      if (read[i] != '?' && read[i] != n[i]) d++;
    }
    // Hepsi okunamadıysa öneri anlamsız.
    if (!read.split('').any((c) => c != '?')) return null;
    return d;
  }

  void replaceSheet(Sheet old, Sheet updated) {
    final i = sheets.indexOf(old);
    if (i >= 0) sheets[i] = updated;
    _changed();
  }

  /// Örnek (kurgusal) veriyle ilk açılış: öğretmen sistemi hemen deneyebilir.
  /// Örnek veride gelişim, erken uyarı ve şube karşılaştırması görünsün
  /// diye: 9-A için daha eski bir quiz, 9-B şubesi için aynı quiz.
  void _seedExtra(int nA) {
    final rnd = math.Random(11);
    final topics = [tr('Hareket'), tr('Kuvvet'), tr('Enerji'), tr('Isı ve sıcaklık')];
    Exam tagged(Exam e) =>
        e.copyWith(questions: [for (final q in e.questions) q.copyWith(outcomeCode: topics[(q.no - 1) ~/ 5])]);
    List<Answer> answers(Exam e, double ability) => [
          for (var q = 0; q < e.questionCount; q++)
            () {
              final key = e.questions[q].correct.first;
              final roll = rnd.nextDouble();
              if (roll < ability) return Answer.choice(key);
              if (roll > 0.96) return const Answer.blank();
              return Answer.choice((key + 1 + rnd.nextInt(4)) % 5);
            }()
        ];

    // 9-A, Fizik Quiz 1: bazı öğrenciler bu sınavda daha iyiydi (düşüş örneği).
    final q1 = tagged(Exam.fromKeyString(
      id: 'demo_exam_q1',
      name: tr('Fizik Quiz 1 (örnek)'),
      className: '9-A',
      key: 'CABDEBCADEACBDECABED',
      date: DateTime.now().subtract(const Duration(days: 16)),
    ));
    exams.add(q1);
    for (var i = 0; i < nA; i++) {
      var ability = 0.35 + 0.6 * (nA - i) / nA;
      if (i % 6 == 5) ability = (ability + 0.3).clamp(0, 0.97);
      sheets.add(Sheet(examId: q1.id, studentId: 'demo_$i', answers: answers(q1, ability)));
    }

    // 9-B şubesi ve aynı Quiz 2.
    final namesB = _demoNames(18, 3) ?? [
      ['Aras', 'Yılmaz'], ['Beren', 'Şen'], ['Cem', 'Avcı'], ['Damla', 'Işık'], ['Eren', 'Toprak'],
      ['Feyza', 'Keskin'], ['Göktuğ', 'Sarı'], ['Hira', 'Ekinci'], ['Kaan', 'Uysal'], ['Melis', 'Aksoy'],
      ['Onur', 'Çakır'], ['Rana', 'Gök'], ['Sarp', 'Duman'], ['Tuana', 'Bayram'], ['Yiğit', 'Coşkun'],
      ['Zehra', 'Önal'], ['Alp', 'Karaca'], ['Bade', 'Tunç'],
    ];
    for (var i = 0; i < namesB.length; i++) {
      students.add(Student(
          id: 'demoB_$i', firstName: namesB[i][0], lastName: namesB[i][1], number: '${2040 + i}', className: '9-B'));
    }
    final q2b = tagged(Exam.fromKeyString(
      id: 'demo_exam_b',
      name: tr('Fizik Quiz 2 (örnek)'),
      className: '9-B',
      key: 'BDACEABDCEBADCEADBCE',
      date: DateTime.now().subtract(const Duration(days: 1)),
    ));
    exams.add(q2b);
    for (var i = 0; i < namesB.length; i++) {
      final ability = 0.45 + 0.5 * (namesB.length - i) / namesB.length;
      sheets.add(Sheet(examId: q2b.id, studentId: 'demoB_$i', answers: answers(q2b, ability)));
    }
  }

  /// Türkçe dışındaki dillerde örnek öğrenciler o dile uygun adlarla gelir.
  static List<List<String>>? _demoNames(int count, int shift) {
    final pool = _demoNamePool[L10n.code];
    if (pool == null) return null;
    final (first, last) = pool;
    // Rusçada kadın adlarıyla soyadı da dişil olur (Иванов → Иванова).
    String fit(String f, String l) => L10n.code == 'ru' && RegExp(r'[ая]$').hasMatch(f) && RegExp(r'(ов|ев|ин)$').hasMatch(l) ? '$lа' : l;
    return [
      for (var i = 0; i < count; i++)
        // Çince, Japonca ve Korecede soyadı önce yazılır.
        if (L10n.code == 'zh' || L10n.code == 'ja' || L10n.code == 'ko')
          [last[(i * 5 + i ~/ last.length + shift * 3) % last.length], first[(i + shift) % first.length]]
        else
          [
            first[(i + shift) % first.length],
            fit(first[(i + shift) % first.length], last[(i * 5 + i ~/ last.length + shift * 3) % last.length])
          ]
    ];
  }

  static const _demoNamePool = {
    'en': (
      ['Olivia', 'Liam', 'Emma', 'Noah', 'Ava', 'Jack', 'Mia', 'Leo', 'Grace', 'Oscar', 'Ella', 'Harry'],
      ['Smith', 'Jones', 'Taylor', 'Brown', 'Wilson', 'Evans', 'Walker', 'Clarke', 'Hughes', 'Wood', 'Hall', 'Green']
    ),
    'de': (
      ['Emma', 'Paul', 'Mia', 'Leon', 'Hannah', 'Felix', 'Lea', 'Jonas', 'Lina', 'Max', 'Sophie', 'Lukas'],
      ['Müller', 'Schmidt', 'Weber', 'Wagner', 'Becker', 'Hoffmann', 'Koch', 'Richter', 'Wolf', 'Klein', 'Braun', 'Krüger']
    ),
    'az': (
      ['Aysel', 'Elvin', 'Nigar', 'Orxan', 'Leyla', 'Tural', 'Günay', 'Rəşad', 'Səbinə', 'Kənan', 'Aytən', 'Murad'],
      ['Məmmədov', 'Əliyev', 'Həsənov', 'Hüseynov', 'Quliyev', 'İsmayılov', 'Rzayev', 'Kərimov', 'Abbasov', 'Nəsirov', 'Babayev', 'Cəfərov']
    ),
    'ar': (
      ['محمد', 'فاطمة', 'أحمد', 'مريم', 'علي', 'سارة', 'يوسف', 'نور', 'عمر', 'ليلى', 'خالد', 'هدى'],
      ['العلي', 'الحسن', 'السالم', 'الأحمد', 'الخطيب', 'المصري', 'النجار', 'الحداد', 'العمر', 'الزين', 'الشامي', 'الرفاعي']
    ),
    'es': (
      ['Lucía', 'Hugo', 'Martina', 'Mateo', 'Sofía', 'Pablo', 'Julia', 'Daniel', 'Paula', 'Álvaro', 'Elena', 'Diego'],
      ['García', 'López', 'Martínez', 'Sánchez', 'Pérez', 'Gómez', 'Ruiz', 'Díaz', 'Moreno', 'Muñoz', 'Romero', 'Navarro']
    ),
    'ru': (
      ['Анна', 'Иван', 'Мария', 'Артём', 'Софья', 'Максим', 'Алиса', 'Дмитрий', 'Ева', 'Михаил', 'Полина', 'Кирилл'],
      ['Иванов', 'Смирнов', 'Кузнецов', 'Попов', 'Соколов', 'Лебедев', 'Козлов', 'Новиков', 'Морозов', 'Волков', 'Зайцев', 'Павлов']
    ),
    'it': (
      ['Giulia', 'Leonardo', 'Sofia', 'Francesco', 'Aurora', 'Lorenzo', 'Alice', 'Mattia', 'Ginevra', 'Tommaso', 'Emma', 'Riccardo'],
      ['Rossi', 'Russo', 'Ferrari', 'Esposito', 'Bianchi', 'Romano', 'Colombo', 'Ricci', 'Marino', 'Greco', 'Bruno', 'Gallo']
    ),
    'fr': (
      ['Louise', 'Gabriel', 'Jade', 'Raphaël', 'Emma', 'Louis', 'Alice', 'Arthur', 'Chloé', 'Jules', 'Léa', 'Hugo'],
      ['Martin', 'Bernard', 'Dubois', 'Thomas', 'Robert', 'Petit', 'Durand', 'Leroy', 'Moreau', 'Simon', 'Laurent', 'Lefebvre']
    ),
    'zh': (
      ['伟', '芳', '娜', '敏', '静', '磊', '洋', '婷', '杰', '欣', '浩', '雪'],
      ['王', '李', '张', '刘', '陈', '杨', '黄', '赵', '吴', '周', '徐', '孙']
    ),
    'ja': (
      ['陽翔', '結衣', '蓮', '葵', '湊', '陽菜', '大翔', '凛', '悠真', '芽依', '颯太', '美咲'],
      ['佐藤', '鈴木', '高橋', '田中', '伊藤', '渡辺', '山本', '中村', '小林', '加藤', '吉田', '山田']
    ),
    'pt': (
      ['Miguel', 'Helena', 'Arthur', 'Alice', 'Gael', 'Laura', 'Heitor', 'Valentina', 'Davi', 'Sophia', 'Bernardo', 'Manuela'],
      ['Silva', 'Santos', 'Oliveira', 'Souza', 'Rodrigues', 'Ferreira', 'Alves', 'Pereira', 'Lima', 'Gomes', 'Costa', 'Ribeiro']
    ),
    'hi': (
      ['आरव', 'अनन्या', 'विहान', 'दिया', 'अर्जुन', 'सान्वी', 'रोहन', 'इशिता', 'कबीर', 'मीरा', 'आदित्य', 'प्रिया'],
      ['शर्मा', 'वर्मा', 'गुप्ता', 'सिंह', 'कुमार', 'पटेल', 'यादव', 'जोशी', 'मिश्रा', 'अग्रवाल', 'चौहान', 'त्रिपाठी']
    ),
    'id': (
      ['Budi', 'Siti', 'Rizky', 'Putri', 'Fajar', 'Ayu', 'Dimas', 'Nadia', 'Bayu', 'Intan', 'Andi', 'Dewi'],
      ['Santoso', 'Wijaya', 'Saputra', 'Lestari', 'Pratama', 'Kusuma', 'Hidayat', 'Nugroho', 'Setiawan', 'Rahayu', 'Siregar', 'Hutapea']
    ),
    'ko': (
      ['민준', '서연', '도윤', '서윤', '시우', '지우', '하준', '하은', '주원', '민서', '지호', '수아'],
      ['김', '이', '박', '최', '정', '강', '조', '윤', '장', '임', '한', '오']
    ),
  };

  void seedDemo() {
    final names = _demoNames(24, 0) ?? [
      ['Deniz', 'Arslan'], ['Elif', 'Kaya'], ['Mert', 'Yıldız'], ['Zeynep', 'Aydın'],
      ['Can', 'Demir'], ['Selin', 'Koç'], ['Ali', 'Şahin'], ['Ece', 'Çelik'],
      ['Burak', 'Öztürk'], ['Defne', 'Kılıç'], ['Emre', 'Aslan'], ['İpek', 'Doğan'],
      ['Kerem', 'Kurt'], ['Lara', 'Özdemir'], ['Ozan', 'Erdem'], ['Pelin', 'Güneş'],
      ['Arda', 'Polat'], ['Duru', 'Tekin'], ['Efe', 'Yalçın'], ['Nehir', 'Ateş'],
      ['Umut', 'Bulut'], ['Yağmur', 'Kara'], ['Baran', 'Uçar'], ['Asya', 'Bozkurt'],
    ];
    for (var i = 0; i < names.length; i++) {
      students.add(Student(
        id: 'demo_$i',
        firstName: names[i][0],
        lastName: names[i][1],
        number: '${1040 + i}',
        className: '9-A',
      ));
    }
    final exam = Exam.fromKeyString(
      id: 'demo_exam',
      name: tr('Fizik Quiz 2 (örnek)'),
      className: '9-A',
      key: 'BDACEABDCEBADCEADBCE',
      date: DateTime.now().subtract(const Duration(days: 2)),
    );
    // Örnek kazanımlar: her 5 soru bir konu.
    final topics = [tr('Hareket'), tr('Kuvvet'), tr('Enerji'), tr('Isı ve sıcaklık')];
    exams.add(exam.copyWith(questions: [
      for (final q in exam.questions) q.copyWith(outcomeCode: topics[(q.no - 1) ~/ 5]),
    ]));
    _seedExtra(names.length);
    final rnd = math.Random(7);
    for (var i = 0; i < names.length; i++) {
      final ability = 0.35 + 0.6 * (names.length - i) / names.length;
      sheets.add(Sheet(
        examId: exam.id,
        studentId: 'demo_$i',
        answers: [
          for (var q = 0; q < exam.questionCount; q++)
            () {
              final roll = rnd.nextDouble();
              final key = exam.questions[q].correct.first;
              // 12. soruda çoğu iyi öğrenci D'yi seçer: anahtar uyarısı örneği.
              if (q == 11 && ability > 0.6) return Answer.choice(3);
              if (roll < ability) return Answer.choice(key);
              if (roll > 0.96) return const Answer.blank();
              return Answer.choice((key + 1 + rnd.nextInt(4)) % 5);
            }()
        ],
      ));
    }
  }
}

/// Sınavın kâğıtlarını okuma bilgisi (Netice formu ya da şablon).
ReadSpec specFor(AppStore store, Exam exam) => ReadSpec(
      questions: exam.questionCount,
      choices: exam.choiceCount,
      booklets: exam.bookletCount,
      digits: exam.numberDigits,
      template: exam.kidForm ? null : store.templateById(exam.templateId),
      kids: exam.kidForm,
    );

/// Sınavın A4 formu ya da (kâğıt kısa quiz formuysa) çeyrek A4 formu yerleşimi.
FormLayout layoutFor(Exam exam, {bool mini = false}) => mini && exam.questionCount <= MiniFormLayout.maxQuestionsFor(exam.numberDigits)
    ? MiniFormLayout(questionCount: exam.questionCount, choiceCount: exam.choiceCount, digits: exam.numberDigits)
    : FormLayout(
        questionCount: exam.questionCount, choiceCount: exam.choiceCount, booklets: exam.bookletCount, digits: exam.numberDigits);

/// Sınav çeyrek A4 kısa quiz formuyla basılabilir mi?
bool miniFormAllowed(Exam exam) =>
    !exam.kidForm && exam.templateId == null && !exam.hasBooklets && exam.questionCount <= MiniFormLayout.maxQuestionsFor(exam.numberDigits);

/// Seçili sınav için okuma motoru oluşturur.
OmrReader readerFor(Exam exam) => OmrReader(
    FormLayout(
        questionCount: exam.questionCount, choiceCount: exam.choiceCount, booklets: exam.bookletCount, digits: exam.numberDigits));

/// Okutulan kâğıdın kaydedilme biçimi.
enum ScanStatus {
  /// Yeni kâğıt.
  added,

  /// Aynı öğrencinin önceki kâğıdının yerine geçti (yeniden okuma).
  replaced,

  /// Aynı kâğıt zaten okunmuştu; değişiklik yapılmadı.
  duplicate,

  /// Bu numarayla farklı cevaplı bir kâğıt zaten var; yenisi kontrole alındı.
  conflict,
}

/// Türkçe alfabeye göre sıralama anahtarı (Ç Ğ I İ Ö Ş Ü doğru yerinde).
String alphaKey(String s) {
  const order = 'aâbcçdefgğhıiîjklmnoöprsştuûüvyzqwx';
  final b = StringBuffer();
  for (final ch in s.replaceAll('I', 'ı').replaceAll('İ', 'i').toLowerCase().split('')) {
    final k = order.indexOf(ch);
    b.writeCharCode(k >= 0 ? 0x100 + k : (ch == ' ' ? 0x20 : 0x200 + ch.codeUnitAt(0)));
  }
  return b.toString();
}

/// Geri alınabilsin diye kaldırılan sınavlar (eski sıralarıyla) ve kâğıtları.
class RemovedExams {
  final List<(int, Exam)> exams;
  final List<Sheet> sheets;
  const RemovedExams(this.exams, this.sheets);
}
