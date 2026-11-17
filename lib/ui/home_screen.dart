import 'package:material_ui/material_ui.dart';

import '../core/analysis.dart';
import '../core/models.dart';
import '../main.dart';
import 'exam_screen.dart';
import 'logo.dart';
import 'new_exam_screen.dart';
import 'scan_screen.dart';
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

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    if (!store.loaded) {
      return const Scaffold(body: Center(child: NeticeMark(size: 72)));
    }
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final body = _tab == 0 ? const _Dashboard() : const StudentsScreen(embedded: true);

    if (wide) {
      return Scaffold(
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
          Expanded(child: body),
        ]),
      );
    }
    return Scaffold(
      body: body,
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
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => ScanScreen(examId: exam!.id)));
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
      StatCard(label: 'Okunan kâğıt', value: '${store.readCount}', hint: '${store.exams.length} sınav'),
      StatCard(label: 'Genel ortalama', value: fmt1(avg), hint: '100 üzerinden'),
      StatCard(
        label: 'Kontrol bekleyen',
        value: '$reviewCount',
        hint: reviewCount > 0 ? 'Belirsiz işaret ya da eşleşmeyen öğrenci' : 'Her şey yolunda',
        accent: reviewCount > 0 ? NColors.amber : NColors.emerald,
        icon: reviewCount > 0 ? Icons.error_outline : Icons.check_circle_outline,
      ),
      StatCard(
        label: 'Kazandığınız süre',
        value: '${saved.inHours} sa ${saved.inMinutes % 60} dk',
        hint: 'Kâğıt başına elle ~1,5 dk varsayımıyla',
      ),
    ];

    return SafeArea(
      child: CustomScrollView(slivers: [
        SliverPadding(
          padding: EdgeInsets.fromLTRB(20, 16, 20, 0),
          sliver: SliverToBoxAdapter(
            child: Row(children: [
              if (wide)
                Text('Pano', style: t.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800))
              else
                const NeticeWordmark(height: 28),
              const Spacer(),
              if (wide) ...[
                OutlinedButton.icon(
                  onPressed: () => _startScan(context),
                  icon: const Icon(Icons.upload_file),
                  label: const Text('PDF / tarama yükle'),
                ),
                const SizedBox(width: 10),
              ],
              FilledButton.icon(
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const NewExamScreen())),
                icon: const Icon(Icons.add),
                label: const Text('Yeni sınav'),
                style: wide ? null : FilledButton.styleFrom(minimumSize: const Size(0, 40)),
              ),
            ]),
          ),
        ),
        if (!wide)
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
            sliver: SliverToBoxAdapter(
              child: SizedBox(
                height: 72,
                child: FilledButton.icon(
                  onPressed: () => _startScan(context),
                  icon: const Icon(Icons.document_scanner_outlined, size: 28),
                  label: const Text('Okut', style: TextStyle(fontSize: 20)),
                ),
              ),
            ),
          ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
          sliver: SliverGrid(
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: wide ? 4 : 2,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              mainAxisExtent: wide ? 128 : 150,
            ),
            delegate: SliverChildListDelegate(stats),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          sliver: SliverToBoxAdapter(child: SectionTitle('Son sınavlar')),
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
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
          sliver: SliverList.separated(
            itemCount: store.exams.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (context, i) {
              final e = store.exams[i];
              final rs = store.resultsOf(e);
              final st = Analysis.examStats(e, rs);
              final review = store.sheetsOf(e.id).where((s) => s.needsReview).length;
              final total = store.studentsOf(e.className).length;
              return Card(
                clipBehavior: Clip.antiAlias,
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ExamScreen(examId: e.id))),
                  title: Text(e.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text('${e.className} · ${e.date.day}.${e.date.month}.${e.date.year} · '
                      '${rs.length}${total > 0 ? '/$total' : ''} okundu'),
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    if (review > 0)
                      Padding(
                        padding: const EdgeInsets.only(right: 12),
                        child: Chip(
                          avatar: const Icon(Icons.error_outline, size: 16, color: NColors.amber),
                          label: Text('$review kontrol'),
                          visualDensity: VisualDensity.compact,
                        ),
                      ),
                    Text(rs.isEmpty ? '–' : fmt1(st.mean),
                        style: t.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800, fontFeatures: tabular)),
                  ]),
                ),
              );
            },
          ),
        ),
      ]),
    );
  }
}
