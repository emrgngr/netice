import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../bank/bank_models.dart';
import '../bank/bank_store.dart';
import '../core/help_content.dart';
import '../core/search.dart';
import '../l10n/l10n.dart';
import '../main.dart';
import '../core/models.dart';
import 'bank/booklet_wizard_screen.dart';
import 'common_exam_ui.dart';
import 'exam_settings_screen.dart';
import 'grade_export_screen.dart';
import 'mastery_screen.dart';
import 'onboarding_screen.dart';
import 'open_scores_screen.dart';
import 'parent_send_screen.dart';
import 'personal_review_ui.dart';
import 'sections_screen.dart';
import 'teaching_screen.dart';
import 'bank/extract_screen.dart';
import 'bank/library_screen.dart';
import 'bank/note_screens.dart';
import 'bank/outcome_lists_screen.dart';
import 'bank/question_editor_screen.dart';
import 'compare_screen.dart';
import 'download_links.dart';
import 'exam_screen.dart' show ExamScreen, openCardsPreview;
import 'general_stats_screen.dart';
import 'grade_scale_screen.dart';
import 'help_screen.dart';
import 'home_screen.dart' show startScanFlow;
import 'invite_screen.dart';
import 'lan_sync_screen.dart';
import 'new_exam_screen.dart';
import 'pro_screen.dart';
import 'sample_reports_screen.dart';
import 'school_offer_screen.dart';
import 'school_screen.dart';
import 'section_icons.dart';
import 'settings_screen.dart' show pickLanguage;
import 'student_detail_screen.dart';
import 'students_screen.dart';
import 'template_screen.dart';
import 'term_screen.dart';
import 'theme.dart';
import 'video_guide_screen.dart';
import 'why_screen.dart';
import 'widgets.dart';

/// Arama sonucunu açan işlem. [tab] verilirse ana ekranın o sekmesine geçilir.
typedef SearchTab = void Function(int tab);

class _Target {
  final Widget Function()? page;
  final int? tab;
  final Future<void> Function(BuildContext)? action;

  /// Bir sınav üzerinde çalışan özellik: sınav birden çoksa sorulur.
  final Future<void> Function(BuildContext, Exam)? exam;

  /// Bir sınıf üzerinde çalışan özellik: sınıf birden çoksa sorulur.
  final Future<void> Function(BuildContext, String)? cls;
  final IconData icon;
  final Section? section;
  const _Target({this.page, this.tab, this.action, this.exam, this.cls, this.icon = Icons.search_rounded, this.section});
}

Future<void> _push(BuildContext c, Widget w) => Navigator.of(c).push(MaterialPageRoute(builder: (_) => w));

/// Sınav seçtirir (tek sınav varsa doğrudan onu verir).
Future<Exam?> _pickExam(BuildContext context) async {
  final exams = [...StoreScope.of(context).exams]..sort((a, b) => b.date.compareTo(a.date));
  if (exams.isEmpty) {
    toast(context, tr('Önce bir sınav oluşturun.'));
    return null;
  }
  if (exams.length == 1) return exams.first;
  return showModalBottomSheet<Exam>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) => SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.7),
        child: ListView(shrinkWrap: true, children: [
          ListTile(title: Text(tr('Hangi sınav?'), style: const TextStyle(fontWeight: FontWeight.w800))),
          for (final e in exams)
            ListTile(
              leading: const GlossyIcon(Icons.description_rounded, Color(0xFF60A5FA), Color(0xFF1D4ED8), size: 36),
              title: Text(e.name),
              subtitle: Text([if (e.className.isNotEmpty) e.className, dmy(e.date)].join(' · ')),
              onTap: () => Navigator.pop(ctx, e),
            ),
        ]),
      ),
    ),
  );
}

/// Sınıf seçtirir (tek sınıf varsa doğrudan onu verir).
Future<String?> _pickClass(BuildContext context) async {
  final store = StoreScope.of(context);
  final classes = store.classNames;
  if (classes.isEmpty) {
    toast(context, tr('Önce öğrenci ekleyin.'));
    return null;
  }
  if (classes.length == 1) return classes.first;
  return showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: ListView(shrinkWrap: true, children: [
        ListTile(title: Text(tr('Hangi sınıf?'), style: const TextStyle(fontWeight: FontWeight.w800))),
        for (final c in classes)
          ListTile(
            leading: const GlossyIcon(Icons.groups_rounded, Color(0xFFA78BFA), Color(0xFF6D28D9), size: 36),
            title: Text(c),
            subtitle: Text(tr('{0} öğrenci', [store.studentsOf(c).length])),
            onTap: () => Navigator.pop(ctx, c),
          ),
      ]),
    ),
  );
}

SearchEntry _feature(String title, String subtitle, String keywords, _Target t, {double boost = 0}) =>
    SearchEntry(SearchKind.feature, title, subtitle: subtitle, keywords: keywords, ref: t, boost: boost);

/// Uygulamanın özellikleri: başlık, açıklama ve (Türkçe + İngilizce) ek sözcükler.
List<SearchEntry> featureEntries() => [
  _feature(tr('Yeni sınav'), tr('Cevap anahtarıyla başlayın'), 'sinav olustur ekle cevap anahtari quiz test exam new',
      _Target(page: () => const NewExamScreen(), section: Section.newExam), boost: 2),
  _feature(tr('Kâğıt okut'), tr('PDF, tarama veya telefondan'), 'okut oku tara kamera optik form kagit scan read',
      _Target(action: startScanFlow, section: Section.scan), boost: 2),
  _feature(tr('Sınıflar ve öğrenciler'), tr('Öğrenci ekleyin, listeyi Excel ya da e-Okul\'dan aktarın'),
      'ogrenci sinif sube liste ekle excel e-okul eokul aktar pdf word students class import',
      _Target(tab: 1, section: Section.classes)),
  _feature(tr('Genel analiz'), tr('Tüm sınıflar ve sınava giren tüm öğrenciler bir arada'),
      'istatistik analiz ortalama basari grafik statistics', _Target(page: () => const GeneralStatsScreen(), section: Section.stats)),
  _feature(tr('Şube karşılaştırması'), tr('Şubeleri yan yana karşılaştırın'), 'sube sinif karsilastir compare',
      _Target(page: () => const CompareScreen(), section: Section.compare)),
  _feature(tr('Örnek raporlar'), tr('Uygulamanın hazırladığı raporların örnekleri'),
      'rapor ornek pdf karne word excel report sample', _Target(page: () => const SampleReportsScreen(), section: Section.samples)),
  _feature(tr('Kütüphane'), tr('Soru bankası, notlar ve kitapçıklar'), 'soru bankasi kutuphane library question bank',
      _Target(tab: 2, section: Section.library)),
  _feature(tr('Yeni soru ekle'), tr('Soru bankasına soru yazın'), 'soru ekle yaz bankasi question add',
      _Target(action: (c) => QuestionEditorScreen.open(c), icon: Icons.add_comment_rounded)),
  _feature(tr('Kitapçık hazırla'), tr('Soru bankasından sınav kâğıdı'),
      'kitapcik sinav kagidi a b c d karisik word pdf booklet', _Target(action: (c) => BookletWizardScreen.open(c), section: Section.booklet)),
  _feature(tr('Belgeden soruları ayıkla'), tr('PDF, Word ya da fotoğraftaki soruları bankaya alın'),
      'ayikla belge pdf word fotograf yapay zeka soru extract', _Target(page: () => const ExtractQuestionsScreen(), icon: Icons.document_scanner_outlined)),
  _feature(tr('Notlar'), tr('Konu notları ve hap bilgiler'), 'not hap bilgi konu ozet notes',
      _Target(page: () => const LibraryScreen(initialTab: 1), icon: Icons.sticky_note_2_outlined)),
  _feature(tr('Soru bankası analizi'), tr('Güçlük, ayırt edicilik ve belirtke tablosu'),
      'analiz guclik ayirt edicilik belirtke bloom', _Target(page: () => const LibraryScreen(initialTab: 3), icon: Icons.insights_rounded)),
  _feature(tr('Kazanım listeleri'), tr('Müfredat kazanımlarını içe aktarın'), 'kazanim mufredat liste outcome curriculum',
      _Target(page: () => const OutcomeListsScreen(), icon: Icons.checklist_rounded)),
  _feature(tr('Dönem sonu raporu'), tr('Dönem notu, kazanım karnesi, e-Okul ve Excel'),
      'donem sonu not karne e-okul eokul excel word term report', _Target(page: () => const TermScreen(), section: Section.term)),
  _feature(tr('Kurum bilgileri'), tr('Resmî yazı başlığı ve imza alanı'),
      'kurum okul resmi yazi baslik imza mudur ogretmen school', _Target(page: () => const SchoolScreen(), section: Section.school)),
  _feature(tr('Not sistemi'), tr('Puanların nota çevrilmesi'), 'not sistemi harf not olcek grade scale',
      _Target(page: () => const GradeScaleScreen(), icon: Icons.grade_rounded)),
  _feature(tr('Optik form şablonları'), tr('Kendi formunuz ya da yayınevi formu'),
      'optik form sablon yayinevi template', _Target(page: () => const TemplatesScreen(), icon: Icons.grid_on_rounded)),
  _feature(tr('Wi-Fi ile aktarma'), tr('Telefondan bilgisayara sınav ve sonuç aktarın'),
      'wifi aktar telefon bilgisayar esitle senkron transfer sync', _Target(page: () => const LanSyncScreen(), icon: Icons.wifi_rounded)),
  _feature(tr('Netice Pro'), tr('Tüm özellikler, reklamsız'), 'pro abonelik satin al fiyat premium subscription',
      _Target(page: () => const ProScreen(), section: Section.pro)),
  _feature(tr('Arkadaşını davet et'), tr('Davet edin, ikiniz de kazanın'), 'davet arkadas indirim kod invite',
      _Target(page: () => const InviteScreen(), icon: Icons.card_giftcard_rounded)),
  _feature(tr('Okul paketi teklifi'), tr('Tüm öğretmenler için toplu lisans'), 'okul paketi teklif kurum lisans school',
      _Target(page: () => const SchoolOfferScreen(), icon: Icons.apartment_rounded)),
  _feature(tr('Profil'), tr('Pro, hesap ve kurum bilgileri'), 'profil hesap google drive yedek account',
      _Target(tab: 3, section: Section.profile)),
  _feature(tr('Ayarlar'), tr('Yedekleme, tema, dil ve ses'), 'ayar yedek geri yukle tema gece modu dil ses titresim settings backup',
      _Target(tab: 4, section: Section.settings)),
  _feature(tr('Dil'), tr('Uygulamanın dilini değiştirin'), 'dil language english turkce',
      _Target(action: pickLanguage, icon: Icons.translate_rounded)),
  _feature(tr('Kullanma kılavuzu'), tr('Adım adım anlatım'), 'yardim kilavuz nasil help guide pdf indir',
      _Target(page: () => const HelpScreen(), section: Section.help)),
  _feature(tr('Sık sorulan sorular'), tr('Aranabilir cevaplar'), 'sss soru cevap faq',
      _Target(page: () => const HelpScreen(initialTab: 1), icon: Icons.quiz_outlined)),
  _feature(tr('Video rehber'), tr('Açılıştan raporlara kadar, sesli anlatımla adım adım.'), 'video rehber izle egitim',
      _Target(action: (c) => VideoGuideScreen.open(c), icon: Icons.play_circle_outline_rounded)),
  _feature(tr('Tanıtım videosu'), tr('Netice\'yi 3 dakikada tanıyın. İndirip Instagram, YouTube ya da WhatsApp\'ta paylaşabilirsiniz.'),
      'tanitim video reels shorts paylas',
      _Target(action: (c) => VideoGuideScreen.open(c, section: VideoGuide.promo, title: tr('Tanıtım videosu')), icon: Icons.movie_rounded)),
  _feature(tr('Neden Netice?'), tr('Ne kadar zaman kazandırır?'), 'neden zaman kazanc why',
      _Target(page: () => const WhyNeticeScreen(), section: Section.why)),
  _feature(tr('Uygulamayı indir'), tr('Telefon, tablet ve bilgisayar için'), 'indir android iphone windows mac download',
      _Target(page: () => const DownloadScreen(), icon: Icons.download_rounded)),
  // Bir sınav üzerinde çalışanlar.
  _feature(tr('Sınav sonuçları ve raporu'), tr('Puanlar, madde analizi ve PDF rapor'),
      'sonuc rapor puan madde analizi pdf karne result', _Target(exam: (c, e) => _push(c, ExamScreen(examId: e.id)), section: Section.exams)),
  _feature(tr('Sınav ayarları'), tr('Cevap anahtarı, puanlama ve kitapçıklar'), 'ayar cevap anahtari puanlama kitapcik degistir duzenle',
      _Target(exam: (c, e) => _push(c, ExamSettingsScreen(examId: e.id)), icon: Icons.tune_rounded)),
  _feature(tr('Klasik puan gir'), tr('Açık uçlu soruların puanları'), 'klasik acik uclu yazili puan rubrik',
      _Target(exam: (c, e) => _push(c, OpenScoresScreen(examId: e.id)), icon: Icons.edit_note_rounded)),
  _feature(tr('Öğrenci karneleri'), tr('Her öğrenciye ayrı karne'), 'karne ogrenci pdf paylas veli',
      _Target(exam: (c, e) => openCardsPreview(c, e), icon: Icons.badge_rounded)),
  _feature(tr('Velilere gönder'), tr('Sonuçları WhatsApp ya da e-postayla iletin'), 'veli whatsapp e-posta gonder sms parent',
      _Target(exam: openBulkParentSend, icon: Icons.send_rounded)),
  _feature(tr('Notları aktar'), tr('Google Classroom ya da Moodle'), 'classroom moodle not aktar gonder export',
      _Target(exam: openGradeExport, icon: Icons.upload_rounded)),
  _feature(tr('Kişisel tekrar testi'), tr('Her öğrenciye yanlışlarından test'), 'tekrar test yanlis kisisel telafi review',
      _Target(exam: (c, e) => openPersonalReview(c, e), icon: Icons.replay_rounded)),
  _feature(tr('Kavram yanılgıları'), tr('Çalışma grupları ve benzer yanlışlar'), 'kavram yanilgisi calisma grubu yanlis ogretim',
      _Target(exam: (c, e) => TeachingScreen.open(c, e), icon: Icons.psychology_rounded)),
  _feature(tr('Çok dersli deneme'), tr('TYT ve LGS düzeni, ders ders net ve puan'), 'deneme tyt lgs ders net puan katsayi',
      _Target(exam: (c, e) => SectionsScreen.open(c, e.id), icon: Icons.view_week_rounded)),
  _feature(tr('Ortak sınav'), tr('Birden çok şubenin aynı sınavı'), 'ortak sinav sube birlestir',
      _Target(exam: openCommonExamMenu, icon: Icons.merge_rounded)),
  _feature(tr('Kazanım takibi'), tr('Sınıfın kazanım başarısı'), 'kazanim takip basari sinif mastery',
      _Target(cls: MasteryScreen.open, icon: Icons.track_changes_rounded)),
  // Ayarlar sayfasındaki işler.
  _feature(tr('Yedekle ve geri yükle'), tr('Verilerinizi dosyaya kaydedin'), 'yedek geri yukle yedekleme backup restore',
      _Target(tab: 4, icon: Icons.backup_rounded)),
  _feature(tr('Gece modu'), tr('Açık ya da koyu görünüm'), 'gece modu karanlik koyu tema dark',
      _Target(tab: 4, icon: Icons.dark_mode_rounded)),
  _feature(tr('Okuma sesi ve titreşim'), tr('Kâğıt okununca ses ve titreşim'), 'ses titresim melodi okuma sesi',
      _Target(tab: 4, icon: Icons.volume_up_rounded)),
  _feature(tr('Gizlilik politikası'), tr('Veriler yalnızca bu cihazda'), 'gizlilik kvkk veri privacy',
      _Target(tab: 4, icon: Icons.lock_outline_rounded)),
  _feature(tr('Geri bildirim'), tr('Görüşlerinizi dosya olarak kaydedip iletin'), 'geri bildirim oneri hata sikayet feedback',
      _Target(tab: 4, icon: Icons.chat_bubble_outline_rounded)),
  _feature(tr('Tanıtımı yeniden izle'), tr('Netice\'yi 4 adımda tanıyın'), 'tanitim baslangic onboarding',
      _Target(page: () => const OnboardingScreen(), icon: Icons.play_circle_outline)),
];

/// Öğrenciler, sınıflar, sınavlar, soru bankası ve yardım içeriği.
List<SearchEntry> dataEntries(BuildContext context) {
  final store = StoreScope.of(context);
  final bank = BankStore.instance;
  final out = <SearchEntry>[];
  for (final c in store.classNames) {
    out.add(SearchEntry(SearchKind.className, c,
        subtitle: tr('{0} öğrenci', [store.studentsOf(c).length]), keywords: 'sinif sube class', ref: c));
  }
  for (final s in store.students) {
    out.add(SearchEntry(SearchKind.student, s.fullName,
        subtitle: [if (s.number.isNotEmpty) tr('No {0}', [s.number]), if (s.className.isNotEmpty) s.className].join(' · '),
        keywords: '${s.number} ${s.className}',
        ref: s.id));
  }
  for (final e in store.exams) {
    out.add(SearchEntry(SearchKind.exam, e.name,
        subtitle: [if (e.className.isNotEmpty) e.className, dmy(e.date), tr('{0} soru', [e.questionCount])].join(' · '),
        keywords: e.className,
        ref: e.id));
  }
  for (final q in bank.questions) {
    final text = q.text.replaceAll(RegExp(r'\s+'), ' ').trim();
    out.add(SearchEntry(SearchKind.question, text.isEmpty ? tr('Görselli soru') : text,
        subtitle: [q.subject, q.grade, q.topic].where((x) => x.isNotEmpty).join(' · '),
        keywords: '${q.outcome} ${q.choices.join(' ')}',
        ref: q));
  }
  for (final n in bank.notes) {
    out.add(SearchEntry(SearchKind.note, n.title,
        subtitle: [n.subject, n.topic].where((x) => x.isNotEmpty).join(' · '), keywords: n.body, ref: n.id));
  }
  for (final b in bank.booklets) {
    out.add(SearchEntry(SearchKind.booklet, b.name, subtitle: tr('{0} soru', [b.questionIds.length]), ref: b));
  }
  for (final sec in guideSections) {
    for (final t in sec.topics) {
      // Yardım, aynı eşleşmede özelliklerin ardından gelsin.
      out.add(SearchEntry(SearchKind.help, t.title,
          boost: -4,
          subtitle: sec.title, keywords: t.steps.join(' '), ref: _HelpItem(t.title, [...t.steps, if (t.tip != null) t.tip!])));
    }
  }
  for (final f in faqs) {
    out.add(SearchEntry(SearchKind.help, f.q, boost: -4, subtitle: tr('Sık sorulan sorular'), keywords: f.a, ref: _HelpItem(f.q, [f.a])));
  }
  return out;
}

class _HelpItem {
  final String title;
  final List<String> lines;
  const _HelpItem(this.title, this.lines);
}

String _kindLabel(SearchKind k) => switch (k) {
  SearchKind.feature => tr('Özellikler'),
  SearchKind.student => tr('Öğrenciler'),
  SearchKind.className => tr('Sınıflar'),
  SearchKind.exam => tr('Sınavlar'),
  SearchKind.question => tr('Sorular'),
  SearchKind.note => tr('Notlar'),
  SearchKind.booklet => tr('Kitapçıklar'),
  SearchKind.help => tr('Yardım'),
};


Widget _kindIcon(SearchEntry e, {double size = 36}) {
  if (e.ref is _Target) {
    final t = e.ref as _Target;
    if (t.section != null) return SectionIcon(t.section!, size: size);
    return GlossyIcon(t.icon, const Color(0xFF34D399), const Color(0xFF047857), size: size);
  }
  final (icon, light, deep) = switch (e.kind) {
    SearchKind.feature => (Icons.auto_awesome_rounded, const Color(0xFF34D399), const Color(0xFF047857)),
    SearchKind.student => (Icons.person_rounded, const Color(0xFFA78BFA), const Color(0xFF6D28D9)),
    SearchKind.className => (Icons.groups_rounded, const Color(0xFFA78BFA), const Color(0xFF6D28D9)),
    SearchKind.exam => (Icons.description_rounded, const Color(0xFF60A5FA), const Color(0xFF1D4ED8)),
    SearchKind.question => (Icons.quiz_rounded, const Color(0xFFFBBF24), const Color(0xFFD97706)),
    SearchKind.note => (Icons.sticky_note_2_rounded, const Color(0xFFFBBF24), const Color(0xFFD97706)),
    SearchKind.booklet => (Icons.auto_stories_rounded, const Color(0xFFF472B6), const Color(0xFFBE185D)),
    _ => (Icons.lightbulb_rounded, const Color(0xFF38BDF8), const Color(0xFF0369A1)),
  };
  return GlossyIcon(icon, light, deep, size: size);
}

/// Her yerde görünen arama kutusu. Dokununca (bilgisayarda tıklayınca) arama
/// açılır ve hemen yazılabilir; bilgisayarda Ctrl+F de açar.

// ---------------------------------------------------------------- arama kutusu

/// Her zaman görünen arama kutusu. Dokununca (bilgisayarda tıklayınca) arama
/// açılır ve hemen yazılabilir; bilgisayarda Ctrl+F de açar.
class SearchBox extends StatelessWidget {
  final SearchTab? onTab;
  const SearchBox({super.key, this.onTab});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final dark = t.brightness == Brightness.dark;
    final muted = t.colorScheme.onSurface.withValues(alpha: 0.55);
    final desktop = MediaQuery.sizeOf(context).width >= 900;
    return Semantics(
      button: true,
      label: tr('Ara'),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(color: (dark ? Colors.black : NColors.ink).withValues(alpha: dark ? 0.3 : 0.07), blurRadius: 18, offset: const Offset(0, 6)),
          ],
        ),
        child: Material(
          color: dark ? NColors.darkSurface : Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: BorderSide(color: dark ? Colors.white12 : NColors.ink.withValues(alpha: 0.08)),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: () => openSearch(context, onTab: onTab),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 10, 8),
              child: Row(children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(gradient: emeraldGradient, borderRadius: BorderRadius.circular(12)),
                  child: const Icon(Icons.search_rounded, color: Colors.white, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(tr('Öğrenci, sınav, soru ya da özellik arayın'),
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: muted, fontSize: 15)),
                ),
                if (desktop) _Key('Ctrl F'),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

class _Key extends StatelessWidget {
  final String label;
  const _Key(this.label);

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: t.colorScheme.outlineVariant),
        color: t.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
      ),
      child: Text(label, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: t.colorScheme.onSurfaceVariant)),
    );
  }
}

/// Aramayı açar: telefonda tam ekran, geniş ekranda üstte açılan pencere.
Future<void> openSearch(BuildContext context, {SearchTab? onTab}) async {
  final wide = MediaQuery.sizeOf(context).width >= 900;
  final picked = wide
      ? await showGeneralDialog<SearchEntry>(
          context: context,
          barrierDismissible: true,
          barrierLabel: tr('Kapat'),
          barrierColor: NColors.ink.withValues(alpha: 0.45),
          transitionDuration: const Duration(milliseconds: 180),
          transitionBuilder: (_, a, _, child) => FadeTransition(
            opacity: a,
            child: SlideTransition(
              position: Tween(begin: const Offset(0, -0.03), end: Offset.zero).animate(CurvedAnimation(parent: a, curve: Curves.easeOut)),
              child: child,
            ),
          ),
          pageBuilder: (ctx, _, _) => SafeArea(
            child: Align(
              alignment: const Alignment(0, -0.55),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 780, maxHeight: 640), child: const SearchPanel()),
              ),
            ),
          ),
        )
      : await Navigator.of(context).push<SearchEntry>(MaterialPageRoute(builder: (_) => const SearchScreen()));
  if (picked == null || !context.mounted) return;
  await openSearchEntry(context, picked, onTab: onTab);
}

Future<void> openSearchEntry(BuildContext context, SearchEntry e, {SearchTab? onTab}) async {
  void push(Widget w) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => w));
  final ref = e.ref;
  switch (e.kind) {
    case SearchKind.feature:
      final t = ref as _Target;
      if (t.exam != null) {
        final ex = await _pickExam(context);
        if (ex != null && context.mounted) await t.exam!(context, ex);
      } else if (t.cls != null) {
        final c = await _pickClass(context);
        if (c != null && context.mounted) await t.cls!(context, c);
      } else if (t.tab != null && onTab != null) {
        onTab(t.tab!);
      } else if (t.tab != null) {
        push(switch (t.tab) { 1 => const StudentsScreen(), 2 => const LibraryScreen(), _ => const HelpScreen() });
      } else if (t.page != null) {
        push(t.page!());
      } else if (t.action != null) {
        await t.action!(context);
      }
    case SearchKind.student:
      push(StudentDetailScreen(studentId: ref as String));
    case SearchKind.className:
      push(StudentsScreen(initialClass: ref as String));
    case SearchKind.exam:
      push(ExamScreen(examId: ref as String));
    case SearchKind.question:
      await QuestionEditorScreen.open(context, ref as BankQuestion);
    case SearchKind.note:
      push(NoteViewScreen(noteId: ref as String));
    case SearchKind.booklet:
      await BookletWizardScreen.open(context, booklet: ref as Booklet);
    case SearchKind.help:
      final h = ref as _HelpItem;
      await showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        builder: (ctx) => SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(h.title, style: Theme.of(ctx).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 12),
              for (final (i, l) in h.lines.indexed)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Text(h.lines.length > 1 ? '${i + 1}. $l' : l, style: const TextStyle(fontSize: 15, height: 1.4)),
                ),
              const SizedBox(height: 4),
              TextButton.icon(
                onPressed: () {
                  Navigator.pop(ctx);
                  push(const HelpScreen());
                },
                icon: const Icon(Icons.menu_book_outlined),
                label: Text(tr('Kullanma kılavuzu')),
              ),
            ]),
          ),
        ),
      );
  }
}

/// Telefonda tam ekran arama.
class SearchScreen extends StatelessWidget {
  const SearchScreen({super.key});

  @override
  Widget build(BuildContext context) => const Scaffold(body: SafeArea(child: SearchPanel(fullScreen: true)));
}

/// Arama alanı ve sonuçlar. Sonuç seçilince Navigator.pop(entry).
/// Klavyeyle: ↑↓ sonuçlar arasında gezinir, Enter açar, Esc kapatır.
class SearchPanel extends StatefulWidget {
  final bool fullScreen;
  const SearchPanel({super.key, this.fullScreen = false});

  /// Testler ve önizleme için başlangıç sorgusu.
  static String? debugQuery;

  @override
  State<SearchPanel> createState() => _SearchPanelState();
}

class _SearchPanelState extends State<SearchPanel> {
  late final _ctl = TextEditingController(text: SearchPanel.debugQuery ?? '');
  late final _focus = FocusNode(onKeyEvent: _onKey);
  List<SearchEntry>? _all;
  late final List<SearchEntry> _features = featureEntries();
  int _sel = 0;
  List<SearchEntry> _shown = const [];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _all ??= [..._features, ...dataEntries(context)];
  }

  @override
  void dispose() {
    _ctl.dispose();
    _focus.dispose();
    super.dispose();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) return KeyEventResult.ignored;
    final k = e.logicalKey;
    if (k == LogicalKeyboardKey.arrowDown || k == LogicalKeyboardKey.arrowUp) {
      if (_shown.isEmpty) return KeyEventResult.handled;
      setState(() => _sel = (_sel + (k == LogicalKeyboardKey.arrowDown ? 1 : -1)) % _shown.length);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.escape) {
      Navigator.pop(context);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final dark = t.brightness == Brightness.dark;
    final q = _ctl.text;
    final results = q.trim().isEmpty ? null : runSearch(_all!, q);
    final words = searchWords(q);

    final field = TextField(
      controller: _ctl,
      focusNode: _focus,
      autofocus: true,
      textInputAction: TextInputAction.search,
      style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w600),
      onChanged: (_) => setState(() => _sel = 0),
      onSubmitted: (_) {
        if (_shown.isNotEmpty) Navigator.pop(context, _shown[_sel.clamp(0, _shown.length - 1)]);
      },
      decoration: InputDecoration(
        hintText: tr('Öğrenci, sınav, soru ya da özellik arayın'),
        hintStyle: TextStyle(fontSize: 17, fontWeight: FontWeight.w500, color: t.colorScheme.onSurface.withValues(alpha: 0.45)),
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        filled: false,
        isDense: true,
      ),
    );
    final header = Container(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
      child: Row(children: [
        if (widget.fullScreen)
          IconButton(
            tooltip: MaterialLocalizations.of(context).backButtonTooltip,
            icon: const Icon(Icons.arrow_back_rounded),
            onPressed: () => Navigator.pop(context),
          )
        else
          const Padding(
            padding: EdgeInsets.only(left: 6, right: 4),
            child: GlossyIcon(Icons.search_rounded, Color(0xFF34D399), Color(0xFF047857), size: 38),
          ),
        const SizedBox(width: 8),
        Expanded(child: field),
        if (q.isNotEmpty)
          IconButton(
            tooltip: tr('Temizle'),
            icon: const Icon(Icons.cancel_rounded),
            color: t.colorScheme.onSurfaceVariant,
            onPressed: () => setState(() {
              _ctl.clear();
              _sel = 0;
            }),
          )
        else if (!widget.fullScreen)
          const Padding(padding: EdgeInsets.only(right: 8), child: _Key('Esc')),
      ]),
    );

    final Widget body;
    if (results == null) {
      _shown = _features.take(8).toList();
      body = ListView(padding: const EdgeInsets.fromLTRB(12, 6, 12, 16), children: [
        _header(context, tr('Sık kullanılanlar')),
        _grid(context, _shown),
        _header(context, tr('Neler aranabilir?')),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Wrap(spacing: 8, runSpacing: 8, children: [
            for (final (k, ex) in [
              (SearchKind.student, tr('Öğrenci adı ya da numarası')),
              (SearchKind.exam, tr('Sınav adı')),
              (SearchKind.question, tr('Soru metni ya da konu')),
              (SearchKind.feature, '"e-Okul", "Word", "yedek"'),
              (SearchKind.help, tr('Nasıl yapılır?')),
            ])
              Chip(
                avatar: _kindIcon(SearchEntry(k, ''), size: 22),
                label: Text(ex),
                side: BorderSide(color: t.colorScheme.outlineVariant),
              ),
          ]),
        ),
      ]);
    } else if (results.isEmpty) {
      _shown = const [];
      body = Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            GlossyIcon(Icons.search_off_rounded, const Color(0xFF94A3B8), const Color(0xFF475569), size: 64),
            const SizedBox(height: 14),
            Text(tr('"{0}" için sonuç bulunamadı.', [q.trim()]),
                textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            const SizedBox(height: 6),
            Text(tr('Daha kısa ya da farklı bir sözcük deneyin.'),
                textAlign: TextAlign.center, style: TextStyle(color: t.colorScheme.onSurfaceVariant)),
          ]),
        ),
      );
    } else {
      final ordered = <SearchEntry>[];
      final children = <Widget>[];
      // Gruplar en iyi sonucun sırasıyla (öğrenci adı yazılınca öğrenciler üstte).
      final kinds = {for (final e in results) e.kind}.toList()
        ..sort((a, b) => results.indexWhere((e) => e.kind == a).compareTo(results.indexWhere((e) => e.kind == b)));
      for (final k in kinds) {
        final group = results.where((e) => e.kind == k).toList();
        if (group.isEmpty) continue;
        children.add(_header(context, _kindLabel(k), count: group.length));
        for (final e in group) {
          children.add(_tile(context, e, words, ordered.length));
          ordered.add(e);
        }
      }
      _shown = ordered;
      body = ListView(padding: const EdgeInsets.fromLTRB(10, 4, 10, 16), children: children);
    }

    final footer = widget.fullScreen || results == null || results.isEmpty
        ? null
        : Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
            decoration: BoxDecoration(border: Border(top: BorderSide(color: t.colorScheme.outlineVariant))),
            child: Row(children: [
              const _Key('↑ ↓'),
              const SizedBox(width: 6),
              Text(tr('seç'), style: _hint(t)),
              const SizedBox(width: 14),
              const _Key('Enter'),
              const SizedBox(width: 6),
              Text(tr('aç'), style: _hint(t)),
              const Spacer(),
              Text(tr('{0} sonuç', [results.length]), style: _hint(t)),
            ]),
          );

    final content = Column(children: [
      header,
      Divider(height: 1, color: t.colorScheme.outlineVariant),
      Expanded(child: body),
      ?footer,
    ]);
    if (widget.fullScreen) return content;
    return Container(
      decoration: BoxDecoration(
        color: dark ? NColors.darkSurface : Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.28), blurRadius: 40, offset: const Offset(0, 18))],
        border: Border.all(color: dark ? Colors.white12 : Colors.white),
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(type: MaterialType.transparency, child: content),
    );
  }

  TextStyle _hint(ThemeData t) => TextStyle(fontSize: 12, color: t.colorScheme.onSurfaceVariant);

  Widget _header(BuildContext context, String s, {int? count}) {
    final t = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 14, 10, 6),
      child: Row(children: [
        Text(s.toUpperCase(),
            style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, letterSpacing: .8, color: t.colorScheme.onSurfaceVariant)),
        if (count != null) ...[
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
            decoration: BoxDecoration(color: NColors.emerald.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(99)),
            child: Text('$count', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: NColors.deepEmerald)),
          ),
        ],
      ]),
    );
  }

  /// Boş sorguda sık kullanılan özellikler: yuvarlak köşeli kart ızgarası.
  Widget _grid(BuildContext context, List<SearchEntry> items) {
    final t = Theme.of(context);
    final dark = t.brightness == Brightness.dark;
    return LayoutBuilder(builder: (context, c) {
      final cols = c.maxWidth >= 640 ? 4 : 2;
      const gap = 10.0;
      final w = (c.maxWidth - 16 - gap * (cols - 1)) / cols;
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Wrap(spacing: gap, runSpacing: gap, children: [
          for (final (i, e) in items.indexed)
            SizedBox(
              width: w,
              child: Material(
                color: i == _sel && _focus.hasFocus && MediaQuery.sizeOf(context).width >= 900
                    ? NColors.emerald.withValues(alpha: 0.12)
                    : (dark ? Colors.white.withValues(alpha: 0.05) : const Color(0xFFF5F7FB)),
                borderRadius: BorderRadius.circular(18),
                child: InkWell(
                  borderRadius: BorderRadius.circular(18),
                  onTap: () => Navigator.pop(context, e),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      _kindIcon(e, size: 38),
                      const SizedBox(height: 10),
                      Text(e.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800)),
                      const SizedBox(height: 2),
                      Text(e.subtitle,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 12, height: 1.25, color: t.colorScheme.onSurfaceVariant)),
                    ]),
                  ),
                ),
              ),
            ),
        ]),
      );
    });
  }

  Widget _tile(BuildContext context, SearchEntry e, List<String> words, int index) {
    final t = Theme.of(context);
    final selected = index == _sel && MediaQuery.sizeOf(context).width >= 900;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Material(
        color: selected ? NColors.emerald.withValues(alpha: 0.12) : Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => Navigator.pop(context, e),
          onHover: (h) {
            if (h && _sel != index) setState(() => _sel = index);
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
            child: Row(children: [
              _kindIcon(e, size: 40),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text.rich(
                    _highlight(e.title, words, const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                        TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: t.brightness == Brightness.dark ? NColors.emerald : NColors.deepEmerald)),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (e.subtitle.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(e.subtitle,
                        maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, color: t.colorScheme.onSurfaceVariant)),
                  ],
                ]),
              ),
              Icon(selected ? Icons.keyboard_return_rounded : Icons.chevron_right_rounded,
                  size: 20, color: selected ? NColors.deepEmerald : t.colorScheme.onSurfaceVariant),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Başlıkta aranan sözcüklerin geçtiği yerleri vurgular (aksan farkı gözetmeden).
TextSpan _highlight(String text, List<String> words, TextStyle base, TextStyle hit) {
  if (words.isEmpty) return TextSpan(text: text, style: base);
  // foldSearch harf sayısını korur (ß hariç); korumuyorsa vurgulamadan göster.
  final folded = text.split('').map((c) => foldSearch(c).isEmpty ? ' ' : foldSearch(c)).toList();
  if (folded.any((f) => f.length != 1)) return TextSpan(text: text, style: base);
  final f = folded.join();
  final mark = List.filled(text.length, false);
  for (final w in words) {
    var i = f.indexOf(w);
    while (i >= 0) {
      for (var j = i; j < i + w.length && j < mark.length; j++) {
        mark[j] = true;
      }
      i = f.indexOf(w, i + w.length);
    }
  }
  final spans = <TextSpan>[];
  var start = 0;
  for (var i = 1; i <= text.length; i++) {
    if (i == text.length || mark[i] != mark[start]) {
      spans.add(TextSpan(text: text.substring(start, i), style: mark[start] ? hit : base));
      start = i;
    }
  }
  return TextSpan(children: spans);
}
