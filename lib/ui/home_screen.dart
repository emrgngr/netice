import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../core/analysis.dart';
import '../core/models.dart';
import '../core/progress.dart';
import '../main.dart';
import 'compare_screen.dart';
import 'onboarding_screen.dart';
import 'school_screen.dart';
import 'settings_screen.dart';
import 'exam_screen.dart';
import 'logo.dart';
import 'new_exam_screen.dart';
import 'camera_scan_screen.dart';
import 'student_detail_screen.dart';
import 'students_screen.dart';
import 'theme.dart';
import 'widgets.dart';

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
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final body = _tab == 0 ? const _Dashboard() : const StudentsScreen(embedded: true);

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
            destinations: const [
              NavigationRailDestination(icon: Icon(Icons.space_dashboard_outlined), selectedIcon: Icon(Icons.space_dashboard), label: Text('Pano')),
              NavigationRailDestination(icon: Icon(Icons.groups_outlined), selectedIcon: Icon(Icons.groups), label: Text('Sınıflar')),
            ],
          ),
          VerticalDivider(width: 1, color: Theme.of(context).colorScheme.outlineVariant),
          Expanded(child: Watermark(child: body)),
        ]),
      )));
    }
    return Scaffold(
      body: Watermark(child: body),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Ana sayfa'),
          NavigationDestination(icon: Icon(Icons.groups_outlined), selectedIcon: Icon(Icons.groups), label: 'Sınıflar'),
        ],
      ),
    );
  }
}

class _Dashboard extends StatelessWidget {
  const _Dashboard();

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
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text('Hangi sınavı okutacaksınız?', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            ),
            for (final e in store.exams)
              ListTile(
                title: Text(e.name),
                subtitle: Text('${e.className} · ${e.questionCount} soru'),
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
          label: 'Okunan',
          value: '${store.readCount}',
          hint: 'kâğıt · ${store.exams.length} sınav',
          icon: Icons.description_outlined,
          accent: const Color(0xFF6C7FD8)),
      StatCard(
          label: 'Ortalama',
          value: fmt1(avg),
          hint: '100 üzerinden',
          icon: Icons.insights_outlined,
          accent: NColors.emerald),
      StatCard(
        label: 'Kontrol',
        value: '$reviewCount',
        hint: reviewCount > 0 ? 'kâğıt bekliyor' : 'Her şey yolunda',
        accent: reviewCount > 0 ? NColors.amber : NColors.emerald,
        icon: reviewCount > 0 ? Icons.priority_high_rounded : Icons.verified_outlined,
      ),
      StatCard(
        label: 'Kazanılan süre',
        value: '${saved.inHours} sa ${saved.inMinutes % 60} dk',
        hint: 'Kâğıt başına elle ~1,5 dk',
        icon: Icons.timer_outlined,
        accent: const Color(0xFFE29A3B),
      ),
    ];

    final hour = DateTime.now().hour;
    final greeting = hour < 11 ? 'Günaydın' : (hour < 18 ? 'İyi günler' : 'İyi akşamlar');
    void newExam() => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const NewExamScreen()));
    void openSettings() => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SettingsScreen()));

    final hero = HeroPanel(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const AppLogo(size: 44),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(greeting, style: const TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w500)),
              const Text('Netice',
                  style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w800, letterSpacing: -0.5)),
            ]),
          ),
          IconButton.filledTonal(
            style: IconButton.styleFrom(backgroundColor: Colors.white.withValues(alpha: 0.12), foregroundColor: Colors.white),
            tooltip: 'Ayarlar',
            onPressed: openSettings,
            icon: const Icon(Icons.settings_outlined),
          ),
          const SizedBox(width: 8),
          IconButton.filledTonal(
            style: IconButton.styleFrom(backgroundColor: Colors.white.withValues(alpha: 0.12), foregroundColor: Colors.white),
            tooltip: 'Yeni sınav',
            onPressed: newExam,
            icon: const Icon(Icons.add_rounded),
          ),
        ]),
        const SizedBox(height: 16),
        const LiveClock(onDark: true),
        const SizedBox(height: 18),
        Text('Kâğıttan sonuca, saniyeler içinde.',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.92), fontSize: 18, fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        Text(
          store.readCount == 0
              ? 'İlk sınavınızı okutun; sonuçlar ve analiz kendiliğinden hazırlanır.'
              : 'Bu dönem ${store.readCount} kâğıt okundu, yaklaşık ${saved.inHours} sa ${saved.inMinutes % 60} dk kazandınız.',
          style: TextStyle(color: Colors.white.withValues(alpha: 0.65), fontSize: 13, height: 1.4),
        ),
        const SizedBox(height: 20),
        GlowButton(label: 'Okut', icon: Icons.document_scanner_outlined, onPressed: () => _startScan(context)),
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
                  Text('Pano', style: t.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.5)),
                ]),
                const Spacer(),
                const LiveClock(),
                const SizedBox(width: 8),
                IconButton(tooltip: 'Ayarlar', onPressed: openSettings, icon: const Icon(Icons.settings_outlined)),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: () => _startScan(context),
                  icon: const Icon(Icons.upload_file),
                  label: const Text('PDF / tarama yükle'),
                ),
                const SizedBox(width: 10),
                FilledButton.icon(onPressed: newExam, icon: const Icon(Icons.add), label: const Text('Yeni sınav')),
              ]),
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            sliver: SliverToBoxAdapter(child: hero),
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
        SliverPadding(
          padding: EdgeInsets.fromLTRB(wide ? 28 : 16, 12, wide ? 28 : 16, 0),
          sliver: SliverToBoxAdapter(child: _Insights(warnings: earlyWarnings(store))),
        ),
        SliverPadding(
          padding: EdgeInsets.symmetric(horizontal: wide ? 28 : 16),
          sliver: const SliverToBoxAdapter(child: SectionTitle('Son sınavlar')),
        ),
        if (store.exams.isEmpty)
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            sliver: SliverToBoxAdapter(
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text('Henüz sınav yok. "Yeni sınav" ile başlayın.', style: t.textTheme.bodyLarge),
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
              return Card(
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ExamScreen(examId: e.id))),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
                    child: Row(children: [
                      Container(
                        width: 46,
                        height: 46,
                        decoration: BoxDecoration(gradient: inkGradient, borderRadius: BorderRadius.circular(14)),
                        alignment: Alignment.center,
                        child: Text(e.className.isEmpty ? '–' : e.className,
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13)),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(e.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                          const SizedBox(height: 3),
                          Text('${dmy(e.date)} ${hm(e.date)} · ${e.questionCount} soru · '
                              '${rs.length}${total > 0 ? '/$total' : ''} okundu',
                              style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurface.withValues(alpha: 0.6))),
                          if (review > 0) ...[
                            const SizedBox(height: 4),
                            Row(children: [
                              const Icon(Icons.priority_high_rounded, size: 14, color: NColors.amber),
                              Text(' $review kâğıt kontrol bekliyor',
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
          title: Text(school.isEmpty ? 'Okul bilgilerini girin' : school.name,
              style: const TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text(school.isEmpty
              ? 'Raporlarda resmi yazı başlığı olarak kullanılır'
              : [
                  if (school.district.isNotEmpty || school.province.isNotEmpty)
                    [school.district, school.province].where((e) => e.isNotEmpty).join(' / '),
                  if (school.subject.isNotEmpty) school.subject,
                  school.official ? 'Resmi başlık açık' : 'Resmi başlık kapalı',
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
          title: const Text('Şube karşılaştırması', style: TextStyle(fontWeight: FontWeight.w700)),
          subtitle: const Text('Aynı sınavı farklı şubelerde yan yana görün'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const CompareScreen())),
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
                    Text('Dikkat gerektiren öğrenciler (${warnings.length})',
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                    Text('Yalnızca size gösterilen bir hatırlatmadır.', style: TextStyle(color: muted, fontSize: 12)),
                  ]),
                ),
              ]),
            ),
            for (final w in warnings.take(4))
              ListTile(
                dense: true,
                title: Text(w.student.fullName, style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text('${w.student.className} · ${w.reason}'),
                trailing: Text('%${w.lastPct.round()}',
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
                            trailing: Text('%${w.lastPct.round()}'),
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
                child: Text('Tümünü göster (${warnings.length})'),
              ),
            const SizedBox(height: 6),
          ]),
        ),
      ],
    ]);
  }
}
