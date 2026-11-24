import 'dart:ui' show ImageFilter;
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../core/analysis.dart';
import '../core/models.dart';
import '../core/progress.dart';
import '../main.dart';
import 'compare_screen.dart';
import 'general_stats_screen.dart';
import 'profile_screen.dart';
import 'onboarding_screen.dart';
import 'school_screen.dart';
import 'settings_screen.dart';
import 'illustrations.dart';
import 'help_screen.dart';
import 'bank/library_screen.dart';
import 'rate_share.dart';
import 'term_screen.dart';
import 'exam_screen.dart';
import 'logo.dart';
import 'new_exam_screen.dart';
import 'camera_scan_screen.dart';
import 'student_detail_screen.dart';
import 'students_screen.dart';
import 'promo_card.dart';
import 'pro_screen.dart';
import '../core/pro.dart';
import 'theme.dart';
import 'widgets.dart';
import '../l10n/l10n.dart';
import '../core/ads.dart';
import 'ad_slot.dart';

/// Ana sayfa / pano. Geniş ekranda (masaüstü) yan menülü pano,
/// dar ekranda (telefon) büyük "Okut" düğmeli mobil düzen.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _tab = 0;
  bool _guideShown = false;
  bool _rateShown = false;

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    if (!store.loaded) {
      return const Scaffold(body: Center(child: NeticeMark(size: 72)));
    }
    if (!store.onboardingDone && !_guideShown) {
      _guideShown = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          Navigator.of(context).push(MaterialPageRoute(builder: (_) => const OnboardingScreen()));
        }
      });
    }
    if (store.onboardingDone && store.shouldAskRating && !_rateShown) {
      _rateShown = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) showRateDialog(context);
      });
    }
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final body = switch (_tab) {
      0 => const _Dashboard(),
      1 => const StudentsScreen(embedded: true),
      2 => const LibraryScreen(embedded: true),
      3 => const ProfileScreen(),
      _ => const SettingsScreen(),
    };
    final page = const [AdPage.home, AdPage.classes, AdPage.help, AdPage.profile, AdPage.settings][_tab.clamp(0, 4)];
    final tabs = [
      (Icons.home_outlined, Icons.home_rounded, tr('Ana sayfa')),
      (Icons.groups_outlined, Icons.groups_rounded, tr('Sınıflar')),
      (Icons.local_library_outlined, Icons.local_library_rounded, tr('Kütüphane')),
      (Icons.person_outline_rounded, Icons.person_rounded, tr('Profil')),
      (Icons.settings_outlined, Icons.settings_rounded, tr('Ayarlar')),
    ];

    if (wide) {
      // Masaüstü kısayolları: Ctrl+N yeni sınav, Ctrl+K şube karşılaştırması.
      return CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.keyN, control: true): () =>
              Navigator.of(context).push(MaterialPageRoute(builder: (_) => const NewExamScreen())),
          const SingleActivator(LogicalKeyboardKey.keyK, control: true): () =>
              Navigator.of(context).push(MaterialPageRoute(builder: (_) => const CompareScreen())),
        },
        child: Focus(autofocus: true, child: Scaffold(
        body: Row(children: [
          NavigationRail(
            selectedIndex: _tab,
            onDestinationSelected: (i) => setState(() => _tab = i),
            labelType: NavigationRailLabelType.all,
            leading: const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: NeticeMark(size: 36),
            ),
            destinations: [
              for (final (i, (icon, sel, label)) in tabs.indexed)
                NavigationRailDestination(
                    icon: Icon(i == 0 ? Icons.space_dashboard_outlined : icon),
                    selectedIcon: Icon(i == 0 ? Icons.space_dashboard : sel),
                    label: Text(i == 0 ? tr('Pano') : label)),
            ],
          ),
          VerticalDivider(width: 1, color: Theme.of(context).colorScheme.outlineVariant),
          Expanded(
            child: Column(children: [
              Expanded(child: Watermark(child: body)),
              AdSlot.banner(page, padding: const EdgeInsets.fromLTRB(16, 6, 16, 10)),
            ]),
          ),
        ]),
      )));
    }
    return Scaffold(
      body: Watermark(child: body),
      bottomNavigationBar: Column(mainAxisSize: MainAxisSize.min, children: [
        AdSlot.banner(page, padding: const EdgeInsets.fromLTRB(14, 6, 14, 6)),
        _Dock(tabs: tabs, index: _tab, onSelect: (i) => setState(() => _tab = i)),
      ]),
    );
  }
}

class _Dashboard extends StatefulWidget {
  const _Dashboard();

  @override
  State<_Dashboard> createState() => _DashboardState();
}

class _DashboardState extends State<_Dashboard> {
  /// Son sınavlar listesinde silmek için seçilenler.
  final _selected = <String>{};
  bool _selecting = false;

  void _toggle(String id) => setState(() {
        if (!_selected.remove(id)) _selected.add(id);
        if (_selected.isEmpty) _selecting = false;
      });

  void _endSelect() => setState(() {
        _selecting = false;
        _selected.clear();
      });

  Future<void> _deleteSelected() async {
    final store = StoreScope.of(context);
    final ids = _selected.where((id) => store.examById(id) != null).toSet();
    if (ids.isEmpty) return;
    final sheetCount = store.sheets.where((s) => ids.contains(s.examId)).length;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ids.length == 1 ? tr('Sınav silinsin mi?') : tr('{0} sınav silinsin mi?', [ids.length])),
        content: Text(tr('Seçilen sınavlar ve okunan {0} kâğıt silinir. Öğrencileriniz, sınıflarınız ve diğer sınavlarınız olduğu gibi kalır.', [sheetCount])),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Vazgeç'))),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(ctx).colorScheme.error),
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.delete_outline_rounded),
            label: Text(tr('Sil')),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final removed = store.removeExams(ids);
    _endSelect();
    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();
    final done = ids.length == 1 ? tr('Sınav silindi.') : tr('{0} sınav silindi.', [ids.length]);
    final closed = messenger
        .showSnackBar(SnackBar(
          content: Text(done),
          duration: const Duration(seconds: 6),
          action: SnackBarAction(label: tr('Geri al'), onPressed: () => store.restoreExams(removed)),
        ))
        .closed;
    closed.then((reason) {
      if (reason != SnackBarClosedReason.action) store.forgetRemoved();
    });
  }

  Future<void> _startScan(BuildContext context) async {
    final store = StoreScope.of(context);
    if (store.exams.isEmpty) {
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => const NewExamScreen()));
      return;
    }
    Exam? exam = store.exams.first;
    if (store.exams.length > 1) {
      exam = await showModalBottomSheet<Exam>(
        context: context,
        showDragHandle: true,
        builder: (ctx) => SafeArea(
          child: ListView(shrinkWrap: true, children: [
            Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(tr('Hangi sınavı okutacaksınız?'), style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            ),
            for (final e in store.exams)
              ListTile(
                title: Text(e.name),
                subtitle: Text('${e.className} · ${tr('{0} soru', [e.questionCount])}'),
                onTap: () => Navigator.pop(ctx, e),
              ),
          ]),
        ),
      );
    }
    if (exam != null && context.mounted) {
      Navigator.of(context).push(scanRoute(exam.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final t = Theme.of(context);
    final wide = MediaQuery.sizeOf(context).width >= 900;

    var reviewCount = 0;
    final allScores = <double>[];
    for (final e in store.exams) {
      final rs = store.resultsOf(e);
      allScores.addAll(rs.map((r) => r.score / e.rule.maxScore * 100));
      reviewCount += store.sheetsOf(e.id).where((s) => s.needsReview).length;
    }
    final avg = allScores.isEmpty ? 0.0 : allScores.reduce((a, b) => a + b) / allScores.length;
    final saved = store.timeSaved;

    final stats = [
      StatCard(
          label: tr('Okunan'),
          value: '${store.readCount}',
          hint: tr('kâğıt · {0} sınav', [store.exams.length]),
          icon: Icons.description_outlined,
          accent: const Color(0xFF6C7FD8)),
      StatCard(
          label: tr('Ortalama'),
          value: fmt1(avg),
          hint: tr('100 üzerinden'),
          icon: Icons.insights_outlined,
          accent: NColors.emerald),
      StatCard(
        label: tr('Kontrol'),
        value: '$reviewCount',
        hint: reviewCount > 0 ? tr('kâğıt bekliyor') : tr('Her şey yolunda'),
        accent: reviewCount > 0 ? NColors.amber : NColors.emerald,
        icon: reviewCount > 0 ? Icons.priority_high_rounded : Icons.verified_outlined,
      ),
      StatCard(
        label: tr('Kazanılan süre'),
        value: tr('{0} sa {1} dk', [saved.inHours, saved.inMinutes % 60]),
        hint: tr('Kâğıt başına elle ~1,5 dk'),
        icon: Icons.timer_outlined,
        accent: const Color(0xFFE29A3B),
      ),
    ];

    final hour = DateTime.now().hour;
    final greeting = hour < 11 ? tr('Günaydın') : (hour < 18 ? tr('İyi günler') : tr('İyi akşamlar'));
    void newExam() => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const NewExamScreen()));
    void openSettings() => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SettingsScreen()));
    void openHelp() => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const HelpScreen()));

    final hero = HeroPanel(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const AppLogo(size: 44),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(greeting, style: const TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w500)),
              Text(tr('Netice'),
                  style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w800, letterSpacing: -0.5)),
            ]),
          ),
          const _ThemeToggle(onDark: true),
          const SizedBox(width: 6),
          IconButton.filledTonal(
            style: IconButton.styleFrom(backgroundColor: Colors.white.withValues(alpha: 0.12), foregroundColor: Colors.white),
            tooltip: tr('Yeni sınav'),
            onPressed: newExam,
            icon: const Icon(Icons.add_rounded),
          ),
        ]),
        const SizedBox(height: 16),
        const LiveClock(onDark: true),
        const SizedBox(height: 18),
        Text(tr('Kâğıttan sonuca, saniyeler içinde.'),
            style: TextStyle(color: Colors.white.withValues(alpha: 0.92), fontSize: 18, fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        Text(
          store.readCount == 0
              ? tr('İlk sınavınızı okutun; sonuçlar ve analiz kendiliğinden hazırlanır.')
              : tr('Bu dönem {0} kâğıt okundu, yaklaşık {1} sa {2} dk kazandınız.', [store.readCount, saved.inHours, saved.inMinutes % 60]),
          style: TextStyle(color: Colors.white.withValues(alpha: 0.65), fontSize: 13, height: 1.4),
        ),
        const SizedBox(height: 20),
        GlowButton(label: tr('Okut'), icon: Icons.document_scanner_outlined, onPressed: () => _startScan(context)),
        const SizedBox(height: 16),
        const OfflineNotice(onDark: true),
      ]),
    );

    return SafeArea(
      child: CustomScrollView(slivers: [
        if (wide)
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(28, 24, 28, 0),
            sliver: SliverToBoxAdapter(
              child: Row(children: [
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(greeting, style: t.textTheme.bodyMedium?.copyWith(color: t.colorScheme.onSurface.withValues(alpha: 0.6))),
                  Text(tr('Pano'), style: t.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.5)),
                ]),
                const Spacer(),
                const LiveClock(),
                const SizedBox(width: 8),
                const _ThemeToggle(),
                IconButton(tooltip: tr('Yardım ve SSS'), onPressed: openHelp, icon: const Icon(Icons.help_outline_rounded)),
                IconButton(tooltip: tr('Ayarlar'), onPressed: openSettings, icon: const Icon(Icons.settings_outlined)),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: () => _startScan(context),
                  icon: const Icon(Icons.upload_file),
                  label: Text(tr('PDF / tarama yükle')),
                ),
                const SizedBox(width: 10),
                FilledButton.icon(onPressed: newExam, icon: const Icon(Icons.add), label: Text(tr('Yeni sınav'))),
              ]),
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            sliver: SliverToBoxAdapter(child: hero),
          ),
        if (store.hasDemo)
          SliverPadding(
            padding: EdgeInsets.fromLTRB(wide ? 28 : 16, 12, wide ? 28 : 16, 0),
            sliver: const SliverToBoxAdapter(child: DemoDataCard()),
          ),
        SliverPadding(
          padding: EdgeInsets.fromLTRB(wide ? 28 : 16, wide ? 20 : 16, wide ? 28 : 16, 0),
          sliver: SliverGrid(
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: wide ? 4 : 2,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              mainAxisExtent: wide ? 138 : 136,
            ),
            delegate: SliverChildListDelegate(stats),
          ),
        ),
        if (store.showPromo)
          SliverPadding(
            padding: EdgeInsets.fromLTRB(wide ? 28 : 16, 4, wide ? 28 : 16, 4),
            sliver: const SliverToBoxAdapter(child: PromoCard()),
          ),
        SliverPadding(
          padding: EdgeInsets.symmetric(horizontal: wide ? 28 : 16),
          sliver: const SliverToBoxAdapter(child: AdSlot.card(AdPage.home)),
        ),
        SliverPadding(
          padding: EdgeInsets.fromLTRB(wide ? 28 : 16, 12, wide ? 28 : 16, 0),
          sliver: SliverToBoxAdapter(child: _Insights(warnings: earlyWarnings(store))),
        ),
        SliverPadding(
          padding: EdgeInsets.symmetric(horizontal: wide ? 28 : 16),
          sliver: SliverToBoxAdapter(
            child: SectionTitle(
              _selecting ? tr('{0} sınav seçildi', [_selected.length]) : tr('Son sınavlar'),
              trailing: store.exams.isEmpty
                  ? null
                  : _selecting
                      ? Row(mainAxisSize: MainAxisSize.min, children: [
                          TextButton(
                            onPressed: () => setState(() {
                              if (_selected.length == store.exams.length) {
                                _selected.clear();
                              } else {
                                _selected.addAll(store.exams.map((e) => e.id));
                              }
                            }),
                            child: Text(_selected.length == store.exams.length ? tr('Seçimi kaldır') : tr('Tümünü seç')),
                          ),
                          IconButton(
                            tooltip: tr('Seçilenleri sil'),
                            onPressed: _selected.isEmpty ? null : _deleteSelected,
                            icon: Icon(Icons.delete_outline_rounded, color: _selected.isEmpty ? null : t.colorScheme.error),
                          ),
                          IconButton(tooltip: tr('Vazgeç'), onPressed: _endSelect, icon: const Icon(Icons.close_rounded)),
                        ])
                      : TextButton.icon(
                          onPressed: () => setState(() => _selecting = true),
                          icon: const Icon(Icons.checklist_rounded, size: 18),
                          label: Text(tr('Seç ve sil')),
                        ),
            ),
          ),
        ),
        if (store.exams.isEmpty)
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            sliver: SliverToBoxAdapter(
              child: Card(
                child: EmptyState(
                  kind: IllustrationKind.exams,
                  title: tr('İlk sınavınızı oluşturun'),
                  message: tr('Cevap anahtarını girin, formları yazdırın ve kâğıtları okutun. Sonuçlar burada listelenir.'),
                  action: FilledButton.icon(
                    onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const NewExamScreen())),
                    icon: const Icon(Icons.add_rounded),
                    label: Text(tr('Yeni sınav')),
                  ),
                ),
              ),
            ),
          ),
        SliverPadding(
          padding: EdgeInsets.fromLTRB(wide ? 28 : 16, 0, wide ? 28 : 16, 32),
          sliver: SliverList.separated(
            itemCount: store.exams.length,
            separatorBuilder: (_, _) => const SizedBox(height: 12),
            itemBuilder: (context, i) {
              final e = store.exams[i];
              final rs = store.resultsOf(e);
              final st = Analysis.examStats(e, rs);
              final review = store.sheetsOf(e.id).where((s) => s.needsReview).length;
              final total = store.studentsOf(e.className).length;
              final picked = _selected.contains(e.id);
              return Card(
                clipBehavior: Clip.antiAlias,
                shape: picked
                    ? RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20), side: const BorderSide(color: NColors.emerald, width: 2))
                    : null,
                child: InkWell(
                  onTap: _selecting
                      ? () => _toggle(e.id)
                      : () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ExamScreen(examId: e.id))),
                  onLongPress: () => setState(() {
                    _selecting = true;
                    _selected.add(e.id);
                  }),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
                    child: Row(children: [
                      Container(
                        width: 46,
                        height: 46,
                        decoration: BoxDecoration(
                            gradient: picked ? emeraldGradient : inkGradient, borderRadius: BorderRadius.circular(14)),
                        alignment: Alignment.center,
                        child: picked
                            ? const Icon(Icons.check_rounded, color: Colors.white)
                            : Text(e.className.isEmpty ? '–' : e.className,
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13)),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(e.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                          const SizedBox(height: 3),
                          Text('${dmy(e.date)} ${hm(e.date)} · ${tr('{0} soru', [e.questionCount])} · '
                              '${rs.length}${total > 0 ? '/$total' : ''} okundu',
                              style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurface.withValues(alpha: 0.6))),
                          if (review > 0) ...[
                            const SizedBox(height: 4),
                            Row(children: [
                              const Icon(Icons.priority_high_rounded, size: 14, color: NColors.amber),
                              Text(tr(' {0} kâğıt kontrol bekliyor', [review]),
                                  style: t.textTheme.bodySmall?.copyWith(color: NColors.amber, fontWeight: FontWeight.w600)),
                            ]),
                          ],
                        ]),
                      ),
                      if (rs.isNotEmpty) ScoreRing(value: st.mean / e.rule.maxScore * 100, size: 54)
                      else Icon(Icons.chevron_right, color: t.colorScheme.onSurface.withValues(alpha: 0.4)),
                    ]),
                  ),
                ),
              );
            },
          ),
        ),
      ]),
    );
  }
}

/// Erken uyarı listesi ve şube karşılaştırması kısayolu.
class _Insights extends StatelessWidget {
  final List<EarlyWarning> warnings;
  const _Insights({required this.warnings});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final muted = t.colorScheme.onSurface.withValues(alpha: 0.6);
    final school = StoreScope.of(context).school;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (school.isEmpty) ...[
      Card(
        clipBehavior: Clip.antiAlias,
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          leading: IconBadge(Icons.account_balance_outlined,
              color: school.isEmpty ? NColors.amber : NColors.emerald),
          title: Text(school.isEmpty ? tr('Kurum bilgilerini girin') : school.name,
              style: const TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text(school.isEmpty
              ? tr('Raporlarda resmi yazı başlığı olarak kullanılır')
              : [
                  if (school.district.isNotEmpty || school.province.isNotEmpty)
                    [school.district, school.province].where((e) => e.isNotEmpty).join(' / '),
                  if (school.subject.isNotEmpty) school.subject,
                  school.official ? tr('Resmi başlık açık') : tr('Resmi başlık kapalı'),
                ].join(' · ')),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SchoolScreen())),
        ),
      ),
      const SizedBox(height: 12),
      ],
      Card(
        clipBehavior: Clip.antiAlias,
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          leading: const IconBadge(Icons.compare_arrows_rounded, color: NColors.emerald),
          title: Text(tr('Sınıf sınıf analiz'), style: TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text(tr('Şubeleri ortalama, yayılım, düzey ve soru soru yan yana görün')),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const CompareScreen())),
        ),
      ),
      const SizedBox(height: 12),
      Card(
        clipBehavior: Clip.antiAlias,
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          leading: const IconBadge(Icons.query_stats_rounded, color: Color(0xFF6C7FD8)),
          title: Text(tr('Genel istatistik'), style: TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text(tr('Tüm sınıflar ve sınava giren tüm öğrenciler bir arada')),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const GeneralStatsScreen())),
        ),
      ),
      const SizedBox(height: 12),
      Card(
        clipBehavior: Clip.antiAlias,
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          leading: const IconBadge(Icons.workspace_premium_outlined, color: NColors.ink),
          title: Text(tr('Dönem raporu'), style: TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text(tr('Dönem sonu notu ve öğrenci kazanım karneleri')),
          trailing: const Icon(Icons.chevron_right),
          onTap: () async {
            if (await requirePro(context, ProFeature.termReport) && context.mounted) {
              Navigator.of(context).push(MaterialPageRoute(builder: (_) => const TermScreen()));
            }
          },
        ),
      ),
      if (warnings.isNotEmpty) ...[
        const SizedBox(height: 12),
        Card(
          clipBehavior: Clip.antiAlias,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
              child: Row(children: [
                const IconBadge(Icons.priority_high_rounded, color: NColors.amber),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(tr('Dikkat gerektiren öğrenciler ({0})', [warnings.length]),
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                    Text(tr('Yalnızca size gösterilen bir hatırlatmadır.'), style: TextStyle(color: muted, fontSize: 12)),
                  ]),
                ),
              ]),
            ),
            for (final w in warnings.take(4))
              ListTile(
                dense: true,
                title: Text(w.student.fullName, style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text('${w.student.className} · ${w.reason}'),
                trailing: Text(L10n.percent(w.lastPct.round()),
                    style: const TextStyle(fontWeight: FontWeight.w800, fontFeatures: tabular, color: NColors.coral)),
                onTap: () => Navigator.of(context)
                    .push(MaterialPageRoute(builder: (_) => StudentDetailScreen(studentId: w.student.id))),
              ),
            if (warnings.length > 4)
              TextButton(
                onPressed: () => showModalBottomSheet(
                  context: context,
                  showDragHandle: true,
                  isScrollControlled: true,
                  builder: (ctx) => SafeArea(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.75),
                      child: ListView(shrinkWrap: true, children: [
                        for (final w in warnings)
                          ListTile(
                            title: Text(w.student.fullName),
                            subtitle: Text('${w.student.className} · ${w.reason}'),
                            trailing: Text(L10n.percent(w.lastPct.round())),
                            onTap: () {
                              Navigator.pop(ctx);
                              Navigator.of(context).push(
                                  MaterialPageRoute(builder: (_) => StudentDetailScreen(studentId: w.student.id)));
                            },
                          ),
                      ]),
                    ),
                  ),
                ),
                child: Text(tr('Tümünü göster ({0})', [warnings.length])),
              ),
            const SizedBox(height: 6),
          ]),
        ),
      ],
    ]);
  }
}

/// Ana ekrandaki bilgi: uygulama çevrimdışı çalışır, veriler bu cihazda kalır.
class OfflineNotice extends StatelessWidget {
  final bool onDark;
  const OfflineNotice({super.key, this.onDark = false});

  static String get title => tr('Çevrimdışı çalışır · Verileriniz bu cihazda');
  static String get adsLine => tr('Üçüncü taraf reklam yok · Sizi izleyen reklam ağı yok');
  static String get adsDetail => tr('Netice\'de üçüncü taraf reklam ve reklam ağı yoktur: reklam kimliğiniz okunmaz, hiçbir reklam şirketi sizi izlemez ve bilgileriniz kimseye satılmaz. Zaman zaman gördüğünüz tanıtımlar yalnızca Netice geliştiricisinin kendi uygulamaları, web siteleri ve ürünleri içindir. Netice Pro\'da bu tanıtımlar da gösterilmez.');
  static String get detail => tr('Netice internet olmadan çalışır. Öğrenci, sınav ve sonuç bilgileriniz yalnızca bu telefonda (veya bilgisayarda), uygulamanın kendi klasöründe saklanır; geliştiriciye ya da başka bir sunucuya gönderilmez.\n\nYalnızca sizin seçtiğiniz durumlarda veri cihazdan çıkar: bir raporu veya yedeği paylaştığınızda ya da Ayarlar > Hesap bölümünden isteğe bağlı Google Drive yedeğini açtığınızda (yedek kendi Google hesabınıza gider).\n\nUygulamayı silmeden önce yedek alın; aksi hâlde veriler telefonla birlikte silinir.');

  static void show(BuildContext context) => showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          icon: const Icon(Icons.phonelink_lock_rounded, color: NColors.emerald),
          title: Text(tr('Verileriniz sizde kalır')),
          content: SingleChildScrollView(child: Text('$detail\n\n$adsDetail')),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('Anladım')))],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final fg = onDark ? Colors.white.withValues(alpha: 0.85) : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.75);
    return Material(
      color: onDark ? Colors.white.withValues(alpha: 0.08) : NColors.emerald.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => show(context),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          child: Row(children: [
            Icon(Icons.wifi_off_rounded, size: 16, color: onDark ? const Color(0xFF7BE0B4) : NColors.emerald),
            const SizedBox(width: 8),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: TextStyle(color: fg, fontSize: 12.5, fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(adsLine, style: TextStyle(color: fg, fontSize: 11.5, fontWeight: FontWeight.w500)),
              ]),
            ),
            Icon(Icons.info_outline_rounded, size: 16, color: fg),
          ]),
        ),
      ),
    );
  }
}

/// Alt menü: yüzen, yuvarlatılmış bir bar. Seçili sekme zümrüt bir hap
/// içinde simge ve adıyla öne çıkar, diğerleri yalnızca simgeyle durur.
/// Gece/gündüz arasında tek dokunuşla geçiş.
class _ThemeToggle extends StatelessWidget {
  final bool onDark;
  const _ThemeToggle({this.onDark = false});

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final icon = AnimatedSwitcher(
      duration: const Duration(milliseconds: 320),
      transitionBuilder: (child, a) => RotationTransition(
        turns: Tween(begin: 0.6, end: 1.0).animate(a),
        child: ScaleTransition(scale: a, child: child),
      ),
      child: Icon(dark ? Icons.light_mode_rounded : Icons.dark_mode_rounded, key: ValueKey(dark)),
    );
    void toggle() {
      HapticFeedback.selectionClick();
      store.setThemeMode(dark ? 'light' : 'dark');
    }

    final tip = dark ? tr('Gündüz moduna geç') : tr('Gece moduna geç');
    if (!onDark) return IconButton(tooltip: tip, onPressed: toggle, icon: icon);
    return IconButton.filledTonal(
      style: IconButton.styleFrom(
          backgroundColor: Colors.white.withValues(alpha: 0.12),
          foregroundColor: dark ? const Color(0xFFFCD34D) : Colors.white),
      tooltip: tip,
      onPressed: toggle,
      icon: icon,
    );
  }
}

/// Alt menü: yüzen cam görünümlü şerit. Seçili sekmenin arkasında kayan
/// zümrüt bir hap durur; tüm sekmelerin adı her zaman görünür.
class _Dock extends StatelessWidget {
  final List<(IconData, IconData, String)> tabs;
  final int index;
  final ValueChanged<int> onSelect;
  const _Dock({required this.tabs, required this.index, required this.onSelect});

  static const _dur = Duration(milliseconds: 320);
  static const _curve = Curves.easeOutBack;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final dark = t.brightness == Brightness.dark;
    final muted = t.colorScheme.onSurface.withValues(alpha: dark ? 0.62 : 0.5);
    final active = dark ? const Color(0xFF6EE7B7) : const Color(0xFF047857);
    final scale = MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 1.15);
    return SafeArea(
      minimum: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 0),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(30),
            boxShadow: [
              BoxShadow(color: NColors.ink.withValues(alpha: dark ? 0.55 : 0.16), blurRadius: 30, offset: const Offset(0, 12)),
              BoxShadow(color: NColors.emerald.withValues(alpha: dark ? 0.10 : 0.06), blurRadius: 40, spreadRadius: -8),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(30),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
              child: Container(
                height: 74,
                padding: const EdgeInsets.symmetric(horizontal: 6),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(30),
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: dark
                        ? [const Color(0xFF1B2A57).withValues(alpha: 0.94), NColors.darkSurface.withValues(alpha: 0.94)]
                        : [Colors.white.withValues(alpha: 0.96), const Color(0xFFF7F8FB).withValues(alpha: 0.94)],
                  ),
                  border: Border.all(color: dark ? Colors.white.withValues(alpha: 0.08) : NColors.ink.withValues(alpha: 0.07)),
                ),
                child: LayoutBuilder(builder: (context, c) {
                  final w = c.maxWidth / tabs.length;
                  const pillW = 52.0, pillH = 32.0;
                  return Stack(children: [
                    // Kayan zümrüt hap.
                    AnimatedPositioned(
                      duration: _dur,
                      curve: _curve,
                      left: w * index + (w - pillW) / 2,
                      top: 9,
                      width: pillW,
                      height: pillH,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: emeraldGradient,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(color: NColors.emerald.withValues(alpha: dark ? 0.45 : 0.38), blurRadius: 14, offset: const Offset(0, 4)),
                          ],
                        ),
                      ),
                    ),
                    Row(children: [
                      for (final (i, (icon, sel, label)) in tabs.indexed)
                        Expanded(
                          child: Semantics(
                            button: true,
                            selected: i == index,
                            label: label,
                            excludeSemantics: true,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(22),
                              splashColor: NColors.emerald.withValues(alpha: 0.12),
                              highlightColor: Colors.transparent,
                              onTap: () {
                                HapticFeedback.selectionClick();
                                onSelect(i);
                              },
                              child: Column(mainAxisAlignment: MainAxisAlignment.start, children: [
                                const SizedBox(height: 9),
                                SizedBox(
                                  height: pillH,
                                  child: Center(
                                    child: AnimatedScale(
                                      duration: _dur,
                                      curve: _curve,
                                      scale: i == index ? 1.08 : 1,
                                      child: Icon(i == index ? sel : icon,
                                          size: 23, color: i == index ? NColors.ink : muted),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 5),
                                Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 2),
                                  child: FittedBox(
                                    fit: BoxFit.scaleDown,
                                    child: AnimatedDefaultTextStyle(
                                      duration: _dur,
                                      style: TextStyle(
                                        fontFamily: t.textTheme.labelSmall?.fontFamily,
                                        fontSize: 11.5,
                                        height: 1.1,
                                        letterSpacing: 0.1,
                                        fontWeight: i == index ? FontWeight.w800 : FontWeight.w600,
                                        color: i == index ? active : muted,
                                      ),
                                      child: Text(label, maxLines: 1, softWrap: false, textScaler: scale),
                                    ),
                                  ),
                                ),
                              ]),
                            ),
                          ),
                        ),
                    ]),
                  ]);
                }),
              ),
            ),
          ),
        ),
      ),
    );
  }
}


/// Ana sayfada örnek veriler varken gösterilir; tek dokunuşla silinir.
class DemoDataCard extends StatelessWidget {
  const DemoDataCard({super.key});

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    return Card(
      color: NColors.amber.withValues(alpha: 0.12),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        child: Row(children: [
          const Icon(Icons.info_outline_rounded, color: NColors.amber),
          const SizedBox(width: 12),
          Expanded(
            child: Text(tr('Gördüğünüz sınıflar ve sınavlar uygulamayı tanımanız için eklenen örneklerdir.'),
                style: const TextStyle(height: 1.35)),
          ),
          TextButton(
            onPressed: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: Text(tr('Örnek veriler silinsin mi?')),
                  content: Text(tr('Örnek öğrenciler, örnek sınavlar ve kâğıtları silinir. Sizin eklediğiniz sınıf ve sınavlara dokunulmaz.')),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Vazgeç'))),
                    FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Sil'))),
                  ],
                ),
              );
              if (ok != true || !context.mounted) return;
              store.clearDemo();
              toast(context, tr('Örnek veriler silindi.'));
            },
            child: Text(tr('Örnekleri sil')),
          ),
        ]),
      ),
    );
  }
}
