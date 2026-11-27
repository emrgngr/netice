import 'package:material_ui/material_ui.dart';

import 'section_icons.dart';
import 'theme.dart';

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
  final Section section;
  final String title;
  final String subtitle;
  final Color? accent;
  final VoidCallback onTap;
  final bool hero;
  const ServiceCard({
    super.key,
    required this.section,
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
    final accent = widget.accent ?? widget.section.style.deep;
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
                        SectionIcon(widget.section, size: 46),
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
