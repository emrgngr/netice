import 'package:material_ui/material_ui.dart';

import 'section_icons.dart';
import 'theme.dart';
import 'widgets.dart' show SectionTitle;

/// Hizmet kartlarını eşit yükseklikte satırlara dizen ızgara. Uzun çeviriler
/// (ör. Almanca) satırı uzatır; aynı satırdaki kartlar birlikte uzar.
class ServiceGrid extends StatelessWidget {
  final int columns;
  final List<Widget> children;
  final double gap;
  const ServiceGrid({super.key, required this.columns, required this.children, this.gap = 14});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var r = 0; r < children.length; r += columns) ...[
          if (r > 0) SizedBox(height: gap),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var c = 0; c < columns; c++) ...[
                  if (c > 0) SizedBox(width: gap),
                  Expanded(child: r + c < children.length ? children[r + c] : const SizedBox()),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// Panodaki hizmet kartı: büyük yuvarlatılmış köşeler, köşede bölüm renginde
/// yumuşak bir daire, üstte simge, altta başlık, açıklama ve yuvarlak ok.
/// [hero] kart lacivert degrade zemin üstünde beyaz yazıyla öne çıkar.
class ServiceCard extends StatefulWidget {
  final Section? section;
  /// [section] yerine serbest simge ve renk (ayarlar, profil gibi bölüm dışı kartlar).
  final IconData? icon;
  final Color? color;
  final String title;
  final String subtitle;
  final Color? accent;
  final VoidCallback onTap;
  final bool hero;
  const ServiceCard({
    super.key,
    this.section,
    this.icon,
    this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.accent,
    this.hero = false,
  });

  @override
  State<ServiceCard> createState() => _ServiceCardState();
}

class _ServiceCardState extends State<ServiceCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final dark = t.brightness == Brightness.dark;
    final hero = widget.hero;
    final style = widget.section?.style ??
        SectionStyle(widget.icon ?? Icons.circle, Color.lerp(widget.color ?? NColors.emerald, Colors.white, 0.25)!,
            widget.color ?? NColors.emerald);
    final accent = widget.accent ?? style.deep;
    final fg = hero ? Colors.white : t.colorScheme.onSurface;
    final sub = hero ? const Color(0xFFC9D2EE) : t.colorScheme.onSurface.withValues(alpha: dark ? 0.72 : 0.62);
    final radius = BorderRadius.circular(24);
    // Yeşil/koyu dolgulu ok dairesinde simge daima beyaz.
    final arrowBg = hero ? NColors.deepEmerald : accent;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        transform: Matrix4.translationValues(0, _hover ? -3 : 0, 0),
        decoration: BoxDecoration(
          borderRadius: radius,
          boxShadow: [
            BoxShadow(
              color: (hero ? NColors.ink : accent).withValues(alpha: dark ? 0.0 : (_hover ? 0.20 : 0.10)),
              blurRadius: _hover ? 26 : 18,
              offset: Offset(0, _hover ? 12 : 8),
            ),
          ],
        ),
        child: Material(
          color: hero ? Colors.transparent : t.cardTheme.color ?? t.colorScheme.surface,
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: radius,
            side: hero
                ? BorderSide.none
                : BorderSide(color: _hover ? accent.withValues(alpha: 0.55) : t.colorScheme.outlineVariant),
          ),
          child: Ink(
            decoration: hero ? BoxDecoration(gradient: inkGradient, borderRadius: radius) : null,
            child: InkWell(
              onTap: widget.onTap,
              child: Stack(
                children: [
                  // Köşedeki yumuşak daireler: kartı düz bir kutu olmaktan çıkarır.
                  PositionedDirectional(
                    top: -46,
                    end: -46,
                    child: Container(
                      width: 128,
                      height: 128,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: hero
                            ? Colors.white.withValues(alpha: 0.07)
                            : accent.withValues(alpha: dark ? 0.20 : (_hover ? 0.14 : 0.09)),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        widget.section != null
                            ? SectionIcon(widget.section!, size: 46)
                            : GlossyIcon(style.icon, style.light, style.deep, size: 46),
                        const SizedBox(height: 14),
                        Text(
                          widget.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: fg, fontWeight: FontWeight.w800, fontSize: 15, height: 1.25),
                        ),
                        if (widget.subtitle.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            widget.subtitle,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: sub, fontSize: 12.5, height: 1.35),
                          ),
                        ],
                        const SizedBox(height: 12),
                        const Spacer(),
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          width: _hover ? 40 : 30,
                          height: 30,
                          decoration: BoxDecoration(
                            color: _hover || hero ? arrowBg : arrowBg.withValues(alpha: dark ? 0.30 : 0.12),
                            borderRadius: BorderRadius.circular(99),
                          ),
                          child: Icon(
                            Icons.arrow_forward_rounded,
                            size: 17,
                            color: _hover || hero ? Colors.white : (dark ? Colors.white : accent),
                          ),
                        ),
                      ],
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


/// Geniş pencere mi? (yan menü hariç içerik genişliği yeterliyse kartlar yan yana dizilir.)
bool wideLayout(BuildContext context) => MediaQuery.sizeOf(context).width >= 1100;

/// Hizmet ızgarasının sütun sayısı, içerik genişliğine göre.
int serviceColumns(double width) => width >= 1150 ? 4 : width >= 820 ? 3 : 2;

/// Başlıklı bölümleri geniş ekranda iki sütuna dizer (ince uzun satırlar yerine
/// yan yana yuvarlatılmış kartlar). Dar ekranda alt alta durur.
class CardSections extends StatelessWidget {
  final List<(String, Widget)> sections;
  const CardSections({super.key, required this.sections});

  @override
  Widget build(BuildContext context) {
    Widget sec((String, Widget) s) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SectionTitle(s.$1),
          RoundedPanel(child: s.$2),
        ]);
    return LayoutBuilder(builder: (context, c) {
      if (c.maxWidth < 900) {
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [for (final s in sections) sec(s)]);
      }
      // Sırayı koruyarak iki sütuna böl: soldakiler önce, sağdakiler sonra okunur.
      final half = (sections.length + 1) ~/ 2;
      return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [for (final s in sections.take(half)) sec(s)])),
        const SizedBox(width: 20),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [for (final s in sections.skip(half)) sec(s)])),
      ]);
    });
  }
}

/// Büyük köşeli, yumuşak gölgeli panel; içindeki satırlar tek bir kartta toplanır.
class RoundedPanel extends StatelessWidget {
  final Widget child;
  const RoundedPanel({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final dark = t.brightness == Brightness.dark;
    final r = BorderRadius.circular(22);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: r,
        boxShadow: [if (!dark) BoxShadow(color: NColors.ink.withValues(alpha: 0.07), blurRadius: 18, offset: const Offset(0, 8))],
      ),
      child: Material(
        color: t.cardTheme.color ?? t.colorScheme.surface,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(borderRadius: r, side: BorderSide(color: t.colorScheme.outlineVariant)),
        child: Theme(
          // İçteki Card'lar panelle birleşsin: ayrı kutu, gölge ve kenar olmasın.
          data: t.copyWith(cardTheme: t.cardTheme.copyWith(elevation: 0, shape: const RoundedRectangleBorder())),
          child: child,
        ),
      ),
    );
  }
}

/// Bölüm başlığı (SectionTitle) ve altındaki kartlardan oluşan bir liste.
/// Dar ekranda olduğu gibi alt alta; geniş ekranda her başlık altındaki
/// öğeler tek bir yuvarlatılmış panelde toplanıp iki sütuna dizilir.
/// Listenin sonundaki [GestureDetector] / [Center] gibi altbilgiler panelin dışında kalır.
class SectionedList extends StatelessWidget {
  final EdgeInsetsGeometry padding;
  final List<Widget> children;
  const SectionedList({super.key, required this.padding, required this.children});

  @override
  Widget build(BuildContext context) {
    if (!wideLayout(context)) return ListView(padding: padding, children: children);
    final lead = <Widget>[];
    final sections = <(String, List<Widget>)>[];
    final footer = <Widget>[];
    for (final w in children) {
      if (w is SectionTitle) {
        sections.add((w.text, []));
      } else if (sections.isEmpty) {
        lead.add(w);
      } else if (w is GestureDetector || footer.isNotEmpty) {
        footer.add(w);
      } else {
        sections.last.$2.add(w);
      }
    }
    // Kart aralarındaki boşluklar panelde ayraç olur; sondaki boşluklar atılır.
    Widget body(List<Widget> ws) {
      final items = [for (final w in ws) if (!(w is SizedBox && w.child == null)) w];
      while (items.isNotEmpty && items.last is SizedBox) {
        items.removeLast();
      }
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (final (i, w) in items.indexed) ...[if (i > 0) const Divider(height: 1), w],
      ]);
    }

    return ListView(padding: padding, children: [
      ...lead,
      CardSections(sections: [for (final s in sections) if (s.$2.isNotEmpty) (s.$1, body(s.$2))]),
      if (footer.isNotEmpty) const SizedBox(height: 8),
      ...footer.where((w) => w is! SizedBox),
    ]);
  }
}

/// Geniş ekranda öğeleri iki sütuna sırayla (soldan sağa) dağıtır; dar ekranda alt alta.
class TwoColumns extends StatelessWidget {
  final bool wide;
  final List<Widget> children;
  const TwoColumns({super.key, required this.wide, required this.children});

  @override
  Widget build(BuildContext context) {
    if (!wide) return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children);
    Widget col(int r) => Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          for (var i = r; i < children.length; i += 2) children[i],
        ]));
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [col(0), col(1)]);
  }
}
