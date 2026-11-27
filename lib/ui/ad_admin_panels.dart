import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/ad_admin.dart';
import '../core/ads.dart';
import '../main.dart';
import 'ad_slot.dart';
import 'compare_screen.dart';
import 'exam_screen.dart';
import 'help_screen.dart';
import 'home_screen.dart';
import 'student_detail_screen.dart';
import 'term_screen.dart';
import 'theme.dart';
import 'widgets.dart';

// Reklam yönetimi ekranının parçaları: telefon çizimi, Alanlar ve
// Başvurular sekmeleri, "Sayfada göster". (Yönetici ekranı; metinler Türkçedir.)

/// Pembe vurgu ("Sayfada göster" çerçevesi ile aynı).
const adPink = Color(0xFFEC4899);

/// Reklamın şu anki durumu (özet kutuları ve kartlar için).
enum AdStatus {
  live('Yayında', NColors.deepEmerald),
  pending('Bekleyen', Color(0xFF6366F1)),
  paused('Durdu', NColors.amber),
  ended('Bitti', NColors.gray);

  final String label;
  final Color color;
  const AdStatus(this.label, this.color);

  static AdStatus of(Ad a, DateTime now) {
    if (a.end != null && a.end!.isBefore(now)) return ended;
    if (!a.active) return paused;
    if (a.draft || a.isLocal || (a.start != null && a.start!.isAfter(now))) return pending;
    return live;
  }
}

/// Bu alanda görünecek reklamlar (yalnız yayında olanlar ya da hepsi).
List<Ad> adsInPlacement(List<Ad> ads, AdPlacement p, {bool liveOnly = true, DateTime? now}) {
  final t = now ?? DateTime.now();
  return [
    for (final a in ads)
      if (a.format == p.format &&
          (a.allPages || a.pages.contains(p.page)) &&
          (!liveOnly || AdStatus.of(a, t) == AdStatus.live))
        a,
  ];
}

/// Reklamın ilk göründüğü alan (telefon çizimi için).
AdPlacement placementOf(Ad a) {
  final page = a.allPages ? AdPage.home : a.pages.first;
  return AdPlacement.all.firstWhere(
    (p) => p.page == page && p.format == a.format,
    orElse: () => AdPlacement.all.firstWhere((p) => p.format == a.format),
  );
}

/// Küçük telefon çizimi: alanın sayfadaki yeri renkli kutuyla gösterilir.
class AdPhoneMock extends StatelessWidget {
  final AdPlacement placement;
  final double width;

  /// Alan dolu mu (yeşil) yoksa boş mu (kesik çizgi).
  final bool filled;
  const AdPhoneMock({super.key, required this.placement, this.width = 52, this.filled = true});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final frame = dark ? const Color(0xFF8A94B8) : const Color(0xFF9AA3BC);
    final line = dark ? Colors.white.withValues(alpha: 0.16) : const Color(0xFFDDE2EE);
    final h = width * 1.9;
    final screenW = width - 8;
    final screenH = h - 14;
    final banner = placement.banner;
    final slotH = banner ? screenH * 0.075 : screenH * 0.2;
    final top = (screenH - slotH - 4) * placement.position.clamp(0.0, 1.0) + 2;
    final slotColor = filled ? NColors.deepEmerald : adPink;
    return Container(
      width: width,
      height: h,
      padding: const EdgeInsets.fromLTRB(4, 7, 4, 7),
      decoration: BoxDecoration(
        color: dark ? const Color(0xFF0E1838) : Colors.white,
        borderRadius: BorderRadius.circular(width * 0.2),
        border: Border.all(color: frame, width: 1.6),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(width * 0.1),
        child: Stack(
          children: [
            // Sayfa içeriği: birkaç gri satır.
            for (var i = 0; i < 9; i++)
              Positioned(
                left: 3,
                right: i.isEven ? 3 : screenW * 0.3,
                top: 4 + i * screenH / 9.5,
                height: 3,
                child: DecoratedBox(
                  decoration: BoxDecoration(color: line, borderRadius: BorderRadius.circular(2)),
                ),
              ),
            Positioned(
              left: 2,
              right: 2,
              top: top,
              height: slotH,
              child: filled
                  ? Container(
                      alignment: Alignment.center,
                      decoration: BoxDecoration(color: slotColor, borderRadius: BorderRadius.circular(3)),
                      child: banner || width < 44
                          ? null
                          : FittedBox(
                              child: Padding(
                                padding: const EdgeInsets.all(2),
                                child: Text(
                                  'REKLAM',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: width * 0.13,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ),
                            ),
                    )
                  : CustomPaint(
                      painter: DashedFramePainter(color: slotColor, radius: 3, width: 1.2),
                      child: Container(color: adPink.withValues(alpha: 0.12)),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Yönetim ekranının üstünde açılan sayfaya "Reklam yönetimine dön" düğmesi
/// ekler; vurgulanan alan henüz çizilmediyse (uzun listenin altındaysa)
/// sayfayı aşağı kaydırarak bulur.
class _OnPageFrame extends StatefulWidget {
  final Widget child;
  const _OnPageFrame({required this.child});

  @override
  State<_OnPageFrame> createState() => _OnPageFrameState();
}

class _OnPageFrameState extends State<_OnPageFrame> {
  @override
  void initState() {
    super.initState();
    _seek();
  }

  ScrollableState? _scrollable() {
    ScrollableState? found;
    void visit(Element e) {
      if (found != null) return;
      if (e is StatefulElement && e.state is ScrollableState) {
        final st = e.state as ScrollableState;
        if (st.axisDirection == AxisDirection.down && st.position.maxScrollExtent > 0) {
          found = st;
          return;
        }
      }
      e.visitChildElements(visit);
    }

    if (mounted) context.visitChildElements(visit);
    return found;
  }

  Future<void> _seek() async {
    final ads = AdService.instance;
    for (var i = 0; i < 60 && mounted; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 60));
      if (ads.highlightShown || ads.highlightKey == null) return;
      final s = _scrollable();
      if (s == null) continue;
      final pos = s.position;
      if (pos.pixels >= pos.maxScrollExtent) return;
      pos.jumpTo(math.min(pos.pixels + 320, pos.maxScrollExtent));
    }
  }

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      widget.child,
      Positioned(
        left: 0,
        right: 0,
        top: 0,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Center(
              child: Material(
                color: adPink,
                elevation: 6,
                shape: const StadiumBorder(),
                child: InkWell(
                  customBorder: const StadiumBorder(),
                  onTap: () => Navigator.of(context).pop(),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.arrow_back_rounded, color: Colors.white, size: 18),
                        SizedBox(width: 6),
                        Text(
                          'Reklam yönetimine dön',
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ],
  );
}

/// "Sayfada göster": alanın bulunduğu sayfayı yönetim ekranının üstünde açar,
/// alanı bir dakika boyunca pembe çerçeveyle işaretler. Geri gelince
/// (düğme ya da geri hareketi) yönetim ekranına dönülür; PIN yeniden sorulmaz.
Future<void> showPlacementOnPage(BuildContext context, AdPlacement p) async {
  final store = StoreScope.of(context);
  Widget? page = switch (p.page) {
    AdPage.home => const HomeScreen(previewTab: 0),
    AdPage.classes => const HomeScreen(previewTab: 1),
    AdPage.profile => const HomeScreen(previewTab: 3),
    AdPage.settings => const HomeScreen(previewTab: 4),
    AdPage.help => p.banner ? const HomeScreen(previewTab: 2) : const HelpScreen(),
    AdPage.term => const TermScreen(),
    AdPage.compare => const CompareScreen(),
    AdPage.exam => store.exams.isEmpty ? null : ExamScreen(examId: store.exams.first.id),
    AdPage.student => store.students.isEmpty ? null : StudentDetailScreen(studentId: store.students.first.id),
  };
  if (page == null) {
    toast(
      context,
      p.page == AdPage.exam
          ? 'Bu alanı görmek için önce bir sınav oluşturun.'
          : 'Bu alanı görmek için önce bir öğrenci ekleyin.',
    );
    return;
  }
  AdService.instance.highlight(p);
  await Navigator.of(context).push(MaterialPageRoute(builder: (_) => _OnPageFrame(child: page)));
}

/// Pembe "Sayfada göster" düğmesi.
class ShowOnPageButton extends StatelessWidget {
  final AdPlacement placement;
  const ShowOnPageButton({super.key, required this.placement});

  @override
  Widget build(BuildContext context) => FilledButton.icon(
    style: FilledButton.styleFrom(
      backgroundColor: adPink,
      foregroundColor: Colors.white,
      visualDensity: VisualDensity.compact,
      padding: const EdgeInsets.symmetric(horizontal: 12),
    ),
    onPressed: () => showPlacementOnPage(context, placement),
    icon: const Icon(Icons.visibility_outlined, size: 17),
    label: const Text('Sayfada göster', style: TextStyle(fontWeight: FontWeight.w800)),
  );
}

/// Küçük renkli etiket (yeşil zeminde daima beyaz yazı).
class AdBadge extends StatelessWidget {
  final String text;
  final Color color;
  final bool solid;
  const AdBadge(this.text, {super.key, this.color = NColors.deepEmerald, this.solid = true});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2.5),
    decoration: BoxDecoration(
      color: solid ? color : color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(20),
      border: solid ? null : Border.all(color: color.withValues(alpha: 0.6)),
    ),
    child: Text(
      text,
      style: TextStyle(
        color: solid ? (color == NColors.amber ? NColors.ink : Colors.white) : color,
        fontSize: 11,
        fontWeight: FontWeight.w800,
      ),
    ),
  );
}

// ---------------------------------------------------------------- Alanlar

/// Alanlar sekmesi: 17 reklam alanının yeri, dolu/boş durumu.
class AdPlacementsTab extends StatefulWidget {
  /// Boş alana "Reklam ekle".
  final void Function(AdPlacement p) onAdd;
  const AdPlacementsTab({super.key, required this.onAdd});

  @override
  State<AdPlacementsTab> createState() => _AdPlacementsTabState();
}

class _AdPlacementsTabState extends State<AdPlacementsTab> {
  int _filter = 0; // 0 tümü, 1 boş, 2 dolu

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.62);
    final drafts = AdAdmin.instance.drafts;
    final now = DateTime.now();
    final rows = [for (final p in AdPlacement.all) (p, adsInPlacement(drafts, p, now: now))];
    final empty = rows.where((r) => r.$2.isEmpty).length;
    final shown = rows.where((r) => _filter == 0 || (_filter == 1) == r.$2.isEmpty).toList();
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
      children: [
        Text(
          'Uygulamadaki ${AdPlacement.all.length} reklam alanı. Pembe kutu alanın sayfadaki yerini gösterir. '
          '"Sayfada göster"e dokununca o sayfa açılır ve alan bir dakika boyunca pembe çerçeveyle işaretlenir '
          '(boş olsa da görünür). "Reklam yönetimine dön" ile buraya dönersiniz.',
          style: TextStyle(color: muted, fontSize: 12.5, height: 1.4),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          children: [
            for (final (i, label) in ['Tümü (${rows.length})', 'Boş ($empty)', 'Dolu (${rows.length - empty})'].indexed)
              ChoiceChip(label: Text(label), selected: _filter == i, onSelected: (_) => setState(() => _filter = i)),
          ],
        ),
        const SizedBox(height: 8),
        for (final (p, ads) in shown)
          Card(
            margin: const EdgeInsets.symmetric(vertical: 6),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AdPhoneMock(placement: p, width: 58, filled: ads.isNotEmpty),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                p.title.toUpperCase(),
                                style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13.5),
                              ),
                            ),
                            Text('Alan ${p.no}', style: TextStyle(color: muted, fontSize: 11.5)),
                          ],
                        ),
                        const SizedBox(height: 4),
                        ads.isEmpty
                            ? const AdBadge('Boş', color: adPink, solid: false)
                            : AdBadge('Dolu · ${ads.length} reklam yayında'),
                        const SizedBox(height: 6),
                        Text(p.where, style: TextStyle(color: muted, fontSize: 12.5, height: 1.35)),
                        if (ads.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              ads.map((a) => a.name.isEmpty ? 'Adsız reklam' : a.name).join(', '),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
                            ),
                          ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 6,
                          children: [
                            ShowOnPageButton(placement: p),
                            OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact),
                              onPressed: () => widget.onAdd(p),
                              icon: const Icon(Icons.add_rounded, size: 17),
                              label: const Text('Reklam ekle'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

// ------------------------------------------------------------- Başvurular

/// Başvurular sekmesi: "Burada reklamınız olsun" formundan gelen talepler.
class AdApplicationsTab extends StatefulWidget {
  /// Testler ve önizleme için hazır liste.
  final List<AdApplication>? initial;

  /// Önizleme için: daha önce görülmüş sayılan başvurular.
  final Set<String>? initialSeen;
  const AdApplicationsTab({super.key, this.initial, this.initialSeen});

  @override
  State<AdApplicationsTab> createState() => _AdApplicationsTabState();
}

class _AdApplicationsTabState extends State<AdApplicationsTab> {
  final _admin = AdAdmin.instance;
  List<AdApplication>? _list;
  Set<String> _seenBefore = {};
  String? _error;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _seenBefore = {...(widget.initialSeen ?? _admin.seenApplicationIds)};
    _list = widget.initial;
    if (_list == null) _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final (list, err) = await _admin.fetchApplications();
    if (!mounted) return;
    setState(() {
      _loading = false;
      _list = list ?? _list;
      _error = err;
    });
    if (list != null) _admin.markApplicationsSeen(list);
  }

  Future<void> _delete(AdApplication a) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Başvuru silinsin mi?'),
        content: Text('${a.name} adlı kişinin başvurusu kalıcı olarak silinecek.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Vazgeç')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Sil')),
        ],
      ),
    );
    if (ok != true) return;
    final done = await _admin.deleteApplication(a.id);
    if (!mounted) return;
    if (done) {
      setState(() => _list = [...?_list]..removeWhere((x) => x.id == a.id));
    } else {
      toast(context, 'Silinemedi (internet?).');
    }
  }

  static String _when(DateTime? t) => t == null ? '' : '${dmy(t)} ${hm(t)}';

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.62);
    final list = _list ?? const <AdApplication>[];
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
        children: [
          Text(
            'Kullanıcılar boş alanlardaki "Burada reklamınız olsun" kartında "Reklam ver"e basıp formu '
            'doldurunca başvurular buraya düşer. Aşağı çekerek yenileyin.',
            style: TextStyle(color: muted, fontSize: 12.5, height: 1.4),
          ),
          const SizedBox(height: 10),
          if (_loading) const LinearProgressIndicator(),
          if (_error != null)
            Card(
              color: NColors.amber.withValues(alpha: 0.18),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline_rounded, color: NColors.amber),
                    const SizedBox(width: 10),
                    Expanded(child: Text(_error!)),
                  ],
                ),
              ),
            ),
          if (!_loading && list.isEmpty && _error == null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 40),
              child: Column(
                children: [
                  Icon(Icons.inbox_outlined, size: 56, color: muted),
                  const SizedBox(height: 8),
                  Text('Henüz başvuru yok.', style: TextStyle(color: muted)),
                ],
              ),
            ),
          for (final a in list)
            Card(
              margin: const EdgeInsets.symmetric(vertical: 6),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
                side: _seenBefore.contains(a.id)
                    ? BorderSide.none
                    : const BorderSide(color: NColors.deepEmerald, width: 1.5),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 6, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            a.company.isEmpty ? a.name : a.company,
                            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15),
                          ),
                        ),
                        if (!_seenBefore.contains(a.id)) const AdBadge('Yeni'),
                        const SizedBox(width: 8),
                      ],
                    ),
                    if (a.company.isNotEmpty) Text(a.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                    Text(
                      [
                        _when(a.time),
                        if (a.slot.isNotEmpty) AdPlacement.byKey(a.slot)?.title.toUpperCase() ?? a.slot,
                        if (a.country.isNotEmpty) a.country,
                      ].where((e) => e.isNotEmpty).join(' · '),
                      style: TextStyle(color: muted, fontSize: 11.5),
                    ),
                    Container(
                      width: double.infinity,
                      margin: const EdgeInsets.fromLTRB(0, 8, 8, 4),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(a.message, style: const TextStyle(height: 1.35)),
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: Wrap(
                            spacing: 4,
                            children: [
                              if (a.phone.isNotEmpty)
                                TextButton.icon(
                                  style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                                  onPressed: () => launchUrl(Uri(scheme: 'tel', path: a.phone.replaceAll(' ', ''))),
                                  icon: const Icon(Icons.phone_rounded, size: 17),
                                  label: Text(a.phone),
                                ),
                              if (a.email.isNotEmpty)
                                TextButton.icon(
                                  style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                                  onPressed: () => launchUrl(
                                    Uri(
                                      scheme: 'mailto',
                                      path: a.email,
                                      query: 'subject=${Uri.encodeComponent('Netice reklam başvurunuz')}',
                                    ),
                                  ),
                                  icon: const Icon(Icons.mail_outline_rounded, size: 17),
                                  label: Text(a.email),
                                ),
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: 'Sil',
                          color: NColors.coral,
                          onPressed: () => _delete(a),
                          icon: const Icon(Icons.delete_outline_rounded),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
