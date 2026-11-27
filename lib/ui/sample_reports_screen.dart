import 'dart:async';
import 'dart:typed_data';

import 'package:material_ui/material_ui.dart';
import 'package:printing/printing.dart';

import '../l10n/l10n.dart';
import '../main.dart';
import 'report_preview_screen.dart';
import 'sample_reports.dart';
import 'section_icons.dart';
import 'theme.dart';
import 'widgets.dart';

/// "Örnek raporlar": Netice'nin hazırladığı tüm raporların örnek bir sınıfın
/// verisiyle üretilmiş hâli. Kartlarda ilk sayfanın küçük görüntüsü durur;
/// dokununca rapor tam boyutta açılır (yazdırma ve paylaşma dahil).
/// Örnekler uygulamanın kendi verisine dokunmaz, her dilde o dilde üretilir.
class SampleReportsScreen extends StatefulWidget {
  const SampleReportsScreen({super.key});

  static Future<void> open(BuildContext context) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SampleReportsScreen()));

  /// Testlerde ve önizlemelerde küçük görüntüler buradan gelir (PDF çizici yok).
  static Future<Uint8List?> Function(SampleReport r)? thumbOverride;

  @override
  State<SampleReportsScreen> createState() => _SampleReportsScreenState();
}

/// Dile göre örnek veri ve küçük görüntü önbelleği (ekran kapanıp açılınca
/// yeniden üretilmesin).
class _Cache {
  static String? lang;
  static SampleData? data;
  static final Map<SampleReport, Future<Uint8List?>> thumbs = {};
  static Future<void> _queue = Future.value();

  static SampleData dataFor(BuildContext context) {
    if (lang != L10n.code || data == null) {
      lang = L10n.code;
      thumbs.clear();
      data = SampleData.create(own: StoreScope.of(context).school);
    }
    return data!;
  }

  /// Küçük görüntüleri sırayla üretir: aynı anda 20 PDF çizilip arayüz donmasın.
  static Future<Uint8List?> thumb(SampleReport r, SampleData d) => thumbs.putIfAbsent(r, () {
        final c = Completer<Uint8List?>();
        _queue = _queue.then((_) async {
          try {
            final o = SampleReportsScreen.thumbOverride;
            if (o != null) {
              c.complete(await o(r));
              return;
            }
            final pdf = await r.build(d);
            final page = await Printing.raster(pdf, pages: const [0], dpi: 48).first;
            c.complete(await page.toPng());
          } catch (_) {
            c.complete(null);
          }
        });
        return c.future;
      });
}

class _SampleReportsScreenState extends State<SampleReportsScreen> {
  @override
  Widget build(BuildContext context) {
    final d = _Cache.dataFor(context);
    final reports = [for (final r in SampleReport.values) if (r.available) r];
    return Scaffold(
      appBar: AppBar(title: Text(tr('Örnek raporlar'))),
      body: LayoutBuilder(builder: (context, c) {
        final w = c.maxWidth.clamp(0.0, 1280.0);
        final cols = w >= 1100 ? 4 : w >= 760 ? 3 : 2;
        final pad = EdgeInsets.fromLTRB(16, 8, 16, 40 + MediaQuery.paddingOf(context).bottom);
        return Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1280),
            child: ListView(padding: pad, children: [
              _Intro(count: reports.length),
              for (final g in SampleGroup.values) ...[
                SectionTitle(g.label),
                _Grid(columns: cols, children: [
                  for (final r in reports)
                    if (r.group == g) _ReportCard(report: r, data: d),
                ]),
              ],
              const SizedBox(height: 18),
              Center(
                child: Text(
                  tr('Örneklerdeki öğrenciler ve kurum adı gerçek değildir. Raporlarınız kendi sınıflarınızın verileriyle hazırlanır.'),
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6), fontSize: 12.5),
                ),
              ),
            ]),
          ),
        );
      }),
    );
  }
}

class _Intro extends StatelessWidget {
  final int count;
  const _Intro({required this.count});

  @override
  Widget build(BuildContext context) {
    Widget chip(IconData icon, String text) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(99),
            border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 16, color: Colors.white),
            const SizedBox(width: 6),
            Text(text, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12.5)),
          ]),
        );
    return HeroPanel(
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const SectionIcon(Section.samples, size: 52),
        const SizedBox(width: 16),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(tr('Netice ile hazırlayabileceğiniz raporlar'),
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 19, height: 1.25)),
            const SizedBox(height: 6),
            Text(
              tr('Her rapor örnek bir sınıfın verisiyle hazırlandı. Bir rapora dokunun, tam boyutunu görün; isterseniz yazdırın ya da paylaşın.'),
              style: const TextStyle(color: Color(0xFFC9D2EE), fontSize: 13.5, height: 1.4),
            ),
            const SizedBox(height: 14),
            Wrap(spacing: 8, runSpacing: 8, children: [
              chip(Icons.description_rounded, tr('{0} rapor türü', [count])),
              chip(Icons.translate_rounded, tr('15 dilde')),
              chip(Icons.print_rounded, tr('PDF, yazdır, paylaş')),
            ]),
          ]),
        ),
      ]),
    );
  }
}

/// Kartları eşit genişlikte satırlara dizer.
class _Grid extends StatelessWidget {
  final int columns;
  final List<Widget> children;
  const _Grid({required this.columns, required this.children});

  @override
  Widget build(BuildContext context) => Column(children: [
        for (var r = 0; r < children.length; r += columns) ...[
          if (r > 0) const SizedBox(height: 14),
          IntrinsicHeight(
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              for (var c = 0; c < columns; c++) ...[
                if (c > 0) const SizedBox(width: 14),
                Expanded(child: r + c < children.length ? children[r + c] : const SizedBox()),
              ],
            ]),
          ),
        ],
      ]);
}

class _ReportCard extends StatefulWidget {
  final SampleReport report;
  final SampleData data;
  const _ReportCard({required this.report, required this.data});

  @override
  State<_ReportCard> createState() => _ReportCardState();
}

class _ReportCardState extends State<_ReportCard> {
  bool _hover = false;

  void _open() {
    final r = widget.report;
    ReportPreviewScreen.open(context, title: r.title, fileName: 'netice_ornek_${r.slug}.pdf', build: () => r.build(widget.data));
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.report;
    final t = Theme.of(context);
    final dark = t.brightness == Brightness.dark;
    final accent = dark ? Color.lerp(r.color, Colors.white, 0.35)! : r.color;
    final radius = BorderRadius.circular(22);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        transform: Matrix4.translationValues(0, _hover ? -3 : 0, 0),
        decoration: BoxDecoration(borderRadius: radius, boxShadow: [
          if (!dark)
            BoxShadow(
                color: r.color.withValues(alpha: _hover ? 0.18 : 0.08),
                blurRadius: _hover ? 24 : 16,
                offset: Offset(0, _hover ? 10 : 6)),
        ]),
        child: Material(
          color: t.cardTheme.color ?? t.colorScheme.surface,
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
              borderRadius: radius,
              side: BorderSide(color: _hover ? accent.withValues(alpha: 0.6) : t.colorScheme.outlineVariant)),
          child: InkWell(
            onTap: _open,
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              // Üstte sayfanın küçük görüntüsü, rengi bölüme göre yumuşak zemin.
              Container(
                height: 176,
                padding: const EdgeInsets.fromLTRB(22, 18, 22, 0),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [r.color.withValues(alpha: dark ? 0.30 : 0.10), r.color.withValues(alpha: dark ? 0.12 : 0.03)],
                  ),
                ),
                child: _Thumb(report: r, data: widget.data),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  // Başlık simgenin yanında, açıklama tam genişlikte: dar telefon
                  // kartlarında yazı tek kelimelik satırlara bölünmesin.
                  Row(children: [
                    GlossyIcon(r.icon, Color.lerp(r.color, Colors.white, 0.3)!, r.color, size: 30),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(r.title,
                          style: TextStyle(
                              color: t.colorScheme.onSurface, fontWeight: FontWeight.w800, fontSize: 14.5, height: 1.2)),
                    ),
                  ]),
                  const SizedBox(height: 8),
                  Text(r.description,
                      style: TextStyle(
                          color: t.colorScheme.onSurface.withValues(alpha: dark ? 0.72 : 0.62), fontSize: 12.5, height: 1.35)),
                ]),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Sayfanın üst kısmı: beyaz kâğıt, hafif gölge; altı kartın içine taşar.
class _Thumb extends StatelessWidget {
  final SampleReport report;
  final SampleData data;
  const _Thumb({required this.report, required this.data});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
        boxShadow: [BoxShadow(color: NColors.ink.withValues(alpha: 0.18), blurRadius: 14, offset: const Offset(0, 4))],
      ),
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
        child: FutureBuilder<Uint8List?>(
          future: _Cache.thumb(report, data),
          builder: (context, s) {
            final png = s.data;
            if (png == null) {
              return Center(
                child: s.connectionState == ConnectionState.done
                    ? Icon(report.icon, size: 40, color: report.color.withValues(alpha: 0.5))
                    : SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2.4, color: report.color.withValues(alpha: 0.6))),
              );
            }
            return Image.memory(png,
                fit: BoxFit.fitWidth, alignment: Alignment.topCenter, filterQuality: FilterQuality.medium, gaplessPlayback: true);
          },
        ),
      ),
    );
  }
}

/// Yardım ve Profil sayfalarındaki "Örnek raporlar" kartı.
class SampleReportsCard extends StatelessWidget {
  const SampleReportsCard({super.key});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => SampleReportsScreen.open(context),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(children: [
            const SectionIcon(Section.samples, size: 52),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(tr('Örnek raporlar'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                const SizedBox(height: 2),
                Text(tr('Netice\'nin hazırladığı tüm raporları örnekleriyle görün'), style: t.textTheme.bodySmall),
              ]),
            ),
            const Icon(Icons.chevron_right_rounded),
          ]),
        ),
      ),
    );
  }
}
