import 'package:material_ui/material_ui.dart';

import '../core/analysis.dart';
import '../core/models.dart';
import '../core/pro.dart';
import '../l10n/l10n.dart';
import '../main.dart';
import 'ad_admin_screen.dart';
import 'exam_screen.dart';
import 'illustrations.dart';
import 'new_exam_screen.dart';
import 'pro_screen.dart';
import 'section_icons.dart';
import 'social_links.dart';
import 'theme.dart';
import 'widgets.dart';

/// Masaüstü yan menüsündeki bir satır.
class DesktopNavItem {
  /// Bölüm logosu ve varsayılan adı buradan gelir.
  final Section section;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  /// Sağda küçük sayı rozeti (ör. sınav sayısı); [warn] ise sarı.
  final int? badge;
  final bool warn;
  DesktopNavItem({
    required this.section,
    String? label,
    required this.onTap,
    this.selected = false,
    this.badge,
    this.warn = false,
  }) : label = label ?? section.label;
}

class DesktopNavGroup {
  final String title;
  final List<DesktopNavItem> items;
  const DesktopNavGroup(this.title, this.items);
}

/// Masaüstü yan menüsü: geniş, lacivert, gruplu ve yazılı. Pencere daraldığında
/// ([compact]) simgelerin altında kısa adlarla dar bir şeride dönüşür.
/// Zemin her iki temada da koyu olduğundan yazılar her zaman açık renklidir.
class DesktopSidebar extends StatelessWidget {
  final List<DesktopNavGroup> groups;
  final List<DesktopNavItem> footer;
  final bool compact;
  const DesktopSidebar({super.key, required this.groups, this.footer = const [], this.compact = false});

  static const wideWidth = 264.0;
  static const compactWidth = 92.0;

  static const _bgTop = Color(0xFF14224A);
  static const _bgBottom = Color(0xFF0B1430);
  static const _text = Color(0xFFD3DAF0);
  static const _muted = Color(0xFF8C97BD);

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final showPro = !store.adFree && !ProService.salesDisabled;
    return Container(
      width: compact ? compactWidth : wideWidth,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: dark ? const [Color(0xFF0F1A3C), Color(0xFF070D22)] : const [_bgTop, _bgBottom],
        ),
        border: dark ? const BorderDirectional(end: BorderSide(color: Color(0xFF1E2A52))) : null,
      ),
      child: SafeArea(
        right: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _brand(),
            Expanded(
              child: ListView(
                padding: EdgeInsets.symmetric(horizontal: compact ? 8 : 14),
                children: [
                  for (final g in groups) ...[
                    if (!compact)
                      Padding(
                        padding: const EdgeInsetsDirectional.fromSTEB(12, 16, 12, 8),
                        child: Text(
                          g.title.toUpperCase(),
                          style: const TextStyle(
                            color: _muted,
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.3,
                          ),
                        ),
                      )
                    else
                      const SizedBox(height: 10),
                    for (final it in g.items) _Tile(item: it, compact: compact),
                  ],
                ],
              ),
            ),
            if (showPro && !compact) const _ProCard(),
            for (final it in footer)
              Padding(
                padding: EdgeInsets.symmetric(horizontal: compact ? 8 : 14),
                child: _Tile(item: it, compact: compact),
              ),
            // Sosyal medya hesapları (adres girilmemişse yer kaplamaz).
            if (!compact)
              const Padding(
                padding: EdgeInsets.only(top: 10),
                child: SocialLinks(showTitle: false, size: 30, onDark: true),
              ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  Widget _brand() {
    if (compact) {
      return const Padding(
        padding: EdgeInsets.fromLTRB(0, 22, 0, 6),
        child: Center(child: SecretAdminTap(child: AppLogo(size: 42))),
      );
    }
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(24, 24, 16, 8),
      child: Row(
        children: [
          // Gizli hareket: logoya 4 sn içinde 5 tıklama → Reklam yönetimi.
          const SecretAdminTap(child: AppLogo(size: 42)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tr('Netice'),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 21,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.4,
                  ),
                ),
                Text(
                  tr('Optik okuma ve analiz'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: _muted, fontSize: 11.5),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Tile extends StatefulWidget {
  final DesktopNavItem item;
  final bool compact;
  const _Tile({required this.item, required this.compact});

  @override
  State<_Tile> createState() => _TileState();
}

class _TileState extends State<_Tile> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final it = widget.item;
    final sel = it.selected;
    final bg = sel
        ? NColors.emerald.withValues(alpha: 0.16)
        : (_hover ? Colors.white.withValues(alpha: 0.06) : Colors.transparent);
    final fg = sel ? Colors.white : DesktopSidebar._text;
    final badge = it.badge == null || it.badge == 0
        ? null
        : Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
              color: it.warn ? NColors.amber : Colors.white.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(99),
            ),
            child: Text(
              '${it.badge}',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                fontFeatures: tabular,
                color: it.warn ? const Color(0xFF3A2800) : Colors.white,
              ),
            ),
          );

    final Widget body;
    if (widget.compact) {
      body = Padding(
        padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Badge(
              isLabelVisible: badge != null,
              backgroundColor: it.warn ? NColors.amber : NColors.emerald,
              textColor: it.warn ? const Color(0xFF3A2800) : Colors.white,
              label: Text('${it.badge ?? ''}'),
              child: SectionIcon(it.section, size: 34, dim: !sel),
            ),
            const SizedBox(height: 5),
            Text(
              it.label,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: fg, fontSize: 11, fontWeight: FontWeight.w600, height: 1.15),
            ),
          ],
        ),
      );
    } else {
      body = Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        child: Row(
          children: [
            SectionIcon(it.section, size: 30, dim: !sel),
            const SizedBox(width: 13),
            Expanded(
              child: Text(
                it.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: fg, fontSize: 14.5, fontWeight: sel ? FontWeight.w700 : FontWeight.w600),
              ),
            ),
            ?badge,
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Tooltip(
        message: widget.compact ? it.label : '',
        child: MouseRegion(
          onEnter: (_) => setState(() => _hover = true),
          onExit: (_) => setState(() => _hover = false),
          cursor: SystemMouseCursors.click,
          child: Material(
            color: bg,
            borderRadius: BorderRadius.circular(12),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: it.onTap,
              child: Container(
                decoration: sel && !widget.compact
                    ? const BoxDecoration(
                        border: BorderDirectional(start: BorderSide(color: NColors.emerald, width: 3)),
                      )
                    : null,
                child: body,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Yan menünün altındaki Pro kartı (reklamsız Pro'da gösterilmez).
class _ProCard extends StatelessWidget {
  const _ProCard();

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final trial = store.inTrial;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
      child: Material(
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: Ink(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF0E9F6E), Color(0xFF056A4B)],
            ),
          ),
          child: InkWell(
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ProScreen())),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.workspace_premium_rounded, color: Colors.white, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          tr('Netice Pro'),
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    trial
                        ? tr('Deneme süreniz: {0} gün kaldı', [store.trialDaysLeft])
                        : tr('Gelişmiş grafikler, dönem raporu ve reklamsız kullanım.'),
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.88), fontSize: 12, height: 1.4),
                  ),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(9)),
                    child: Text(
                      tr('Pro\'ya geç'),
                      style: const TextStyle(color: Color(0xFF065F46), fontWeight: FontWeight.w800, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Masaüstü "Sınavlar" çalışma alanı: solda aranabilir sınav listesi, sağda
/// seçilen sınavın tüm ayrıntısı. Sınavdan sınava ekrandan çıkmadan geçilir.
class DesktopExamsWorkspace extends StatefulWidget {
  const DesktopExamsWorkspace({super.key});

  @override
  State<DesktopExamsWorkspace> createState() => _DesktopExamsWorkspaceState();
}

class _DesktopExamsWorkspaceState extends State<DesktopExamsWorkspace> {
  String? _selectedId;
  String _query = '';
  int _filter = 0; // 0 tümü, 1 bu hafta, 2 kontrol bekleyen

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final t = Theme.of(context);
    final dark = t.brightness == Brightness.dark;
    final q = _query.trim().toLowerCase();
    final weekAgo = DateTime.now().subtract(const Duration(days: 7));
    int reviewOf(Exam e) => store.sheetsOf(e.id).where((s) => s.needsReview).length;
    final exams = [
      for (final e in store.exams)
        if ((q.isEmpty || e.name.toLowerCase().contains(q) || e.className.toLowerCase().contains(q)) &&
            (_filter != 1 || e.date.isAfter(weekAgo)) &&
            (_filter != 2 || reviewOf(e) > 0))
          e,
    ];
    final selected = store.examById(_selectedId ?? '') ?? (store.exams.isEmpty ? null : store.exams.first);

    final listBg = dark ? const Color(0xFF101B3E) : Colors.white;
    final line = t.colorScheme.outlineVariant;
    final muted = t.colorScheme.onSurface.withValues(alpha: 0.62);

    final list = Container(
      width: 360,
      decoration: BoxDecoration(
        color: listBg,
        border: BorderDirectional(end: BorderSide(color: line)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 22, 16, 0),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    tr('Sınavlar'),
                    style: t.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.4),
                  ),
                ),
                IconButton.filled(
                  style: IconButton.styleFrom(
                    backgroundColor: NColors.buttonBg(dark),
                    foregroundColor: NColors.buttonFg(dark),
                  ),
                  tooltip: tr('Yeni sınav'),
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const NewExamScreen())),
                  icon: const Icon(Icons.add_rounded),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: TextField(
              onChanged: (v) => setState(() => _query = v),
              decoration: InputDecoration(
                isDense: true,
                prefixIcon: const Icon(Icons.search_rounded),
                hintText: tr('Sınavlarda ara…'),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final (i, label) in [tr('Tümü'), tr('Bu hafta'), tr('Kontrol bekleyen')].indexed)
                  ChoiceChip(
                    label: Text(label),
                    selected: _filter == i,
                    showCheckmark: false,
                    onSelected: (_) => setState(() => _filter = i),
                  ),
              ],
            ),
          ),
          Expanded(
            child: exams.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        store.exams.isEmpty ? tr('Henüz sınav yok') : tr('Eşleşen sınav yok'),
                        textAlign: TextAlign.center,
                        style: TextStyle(color: muted),
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(10, 4, 10, 16),
                    itemCount: exams.length,
                    itemBuilder: (context, i) {
                      final e = exams[i];
                      final rs = store.resultsOf(e);
                      final mean = rs.isEmpty ? null : Analysis.examStats(e, rs).mean / e.rule.maxScore * 100;
                      final total = store.studentsOf(e.className).length;
                      final review = reviewOf(e);
                      final on = selected?.id == e.id;
                      final c = mean == null
                          ? NColors.gray
                          : mean >= 70
                          ? NColors.emerald
                          : (mean >= 50 ? NColors.amber : NColors.coral);
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Material(
                          color: on ? NColors.emerald.withValues(alpha: dark ? 0.16 : 0.10) : Colors.transparent,
                          borderRadius: BorderRadius.circular(14),
                          clipBehavior: Clip.antiAlias,
                          child: InkWell(
                            onTap: () => setState(() => _selectedId = e.id),
                            child: Container(
                              decoration: on
                                  ? const BoxDecoration(
                                      border: BorderDirectional(start: BorderSide(color: NColors.emerald, width: 3)),
                                    )
                                  : null,
                              padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                              child: Row(
                                children: [
                                  Container(
                                    width: 44,
                                    height: 44,
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(
                                      color: c.withValues(alpha: dark ? 0.20 : 0.14),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Text(
                                      mean == null ? '–' : mean.round().toString(),
                                      style: TextStyle(
                                        fontWeight: FontWeight.w800,
                                        fontSize: 14,
                                        fontFeatures: tabular,
                                        color: NColors.readable(
                                          mean == null ? t.colorScheme.onSurface : (dark ? c : _deep(c)),
                                          dark: dark,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          e.name,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          '${e.className.isEmpty ? '–' : e.className} · ${dmy(e.date)} · '
                                          '${rs.length}${total > 0 ? '/$total' : ''}',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(color: muted, fontSize: 12),
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (review > 0)
                                    Tooltip(
                                      message: tr('{0} kâğıt kontrol bekliyor', [review]),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: NColors.amber,
                                          borderRadius: BorderRadius.circular(99),
                                        ),
                                        child: Text(
                                          '$review',
                                          style: const TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w800,
                                            color: Color(0xFF3A2800),
                                          ),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );

    final Widget detail = selected == null
        ? Center(
            child: SingleChildScrollView(
              child: EmptyState(
                kind: IllustrationKind.exams,
                title: tr('İlk sınavınızı oluşturun'),
                message: tr(
                  'Cevap anahtarını girin, formları yazdırın ve kâğıtları okutun. Sonuçlar burada listelenir.',
                ),
                action: FilledButton.icon(
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const NewExamScreen())),
                  icon: const Icon(Icons.add_rounded),
                  label: Text(tr('Yeni sınav')),
                ),
              ),
            ),
          )
        // Ayrıntı bölmesi kendi genişliğini "ekran" sanar: dar bölmede
        // sınav ekranı düğmelerini menüye toplar, taşma olmaz.
        : LayoutBuilder(
            builder: (context, c) => MediaQuery(
              data: MediaQuery.of(context).copyWith(size: Size(c.maxWidth, c.maxHeight)),
              child: ExamScreen(key: ValueKey(selected.id), examId: selected.id),
            ),
          );

    return Row(
      children: [
        list,
        Expanded(child: ClipRect(child: detail)),
      ],
    );
  }

  /// Açık zeminde rozet yazısı için rengin koyu tonu.
  static Color _deep(Color c) => Color.lerp(c, Colors.black, 0.35)!;
}
