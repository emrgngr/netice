import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/ads.dart';
import '../l10n/l10n.dart';

/// Netice'nin sosyal medya hesapları: renkli yuvarlak simgeler. Adresler
/// Reklam yönetimi > Ayarlar'dan gelir; hiç adres yoksa hiçbir şey çizilmez.
class SocialLinks extends StatelessWidget {
  final bool showTitle;
  final double size;

  /// Önizleme ve testler için: verilirse yayındaki ayarlar yerine bu kullanılır.
  final Map<String, String>? links;

  /// Koyu zemin (masaüstü yan menü): X simgesine ince açık çerçeve.
  final bool onDark;
  const SocialLinks({super.key, this.showTitle = true, this.size = 40, this.links, this.onDark = false});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AdService.instance,
      builder: (context, _) {
        final m = links ?? AdService.instance.settings.social;
        final items = [for (final n in SocialNetwork.values) if (m[n.key] case final u? when u.isNotEmpty) (n, u)];
        if (items.isEmpty) return const SizedBox.shrink();
        final muted = Theme.of(context).colorScheme.onSurfaceVariant;
        return Column(mainAxisSize: MainAxisSize.min, children: [
          if (showTitle) ...[
            Text(tr('Bizi takip edin'), style: TextStyle(color: muted, fontSize: 12, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
          ],
          Wrap(spacing: 12, runSpacing: 8, alignment: WrapAlignment.center, children: [
            for (final (n, u) in items)
              Tooltip(
                message: n.label,
                child: Semantics(
                  link: true,
                  label: n.label,
                  child: InkResponse(
                    radius: size * .65,
                    onTap: () => launchUrl(Uri.parse(u), mode: LaunchMode.externalApplication),
                    child: SocialIcon(n, size: size, onDark: onDark),
                  ),
                ),
              ),
          ]),
        ]);
      },
    );
  }
}

/// Markanın renginde yuvarlak zemin üzerinde beyaz, sade bir işaret.
class SocialIcon extends StatelessWidget {
  final SocialNetwork network;
  final double size;
  final bool onDark;
  const SocialIcon(this.network, {super.key, this.size = 40, this.onDark = false});

  @override
  Widget build(BuildContext context) {
    final dark = onDark || Theme.of(context).brightness == Brightness.dark;
    final insta = network == SocialNetwork.instagram;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: insta ? null : Color(network.color),
        gradient: insta
            ? const LinearGradient(
                begin: Alignment.bottomLeft,
                end: Alignment.topRight,
                colors: [Color(0xFFFEDA75), Color(0xFFFA7E1E), Color(0xFFD62976), Color(0xFF962FBF), Color(0xFF4F5BD5)],
              )
            : null,
        // Gece modunda siyah X zemini kaybolmasın.
        border: dark && network == SocialNetwork.x ? Border.all(color: Colors.white38) : null,
      ),
      child: CustomPaint(painter: _GlyphPainter(network)),
    );
  }
}

class _GlyphPainter extends CustomPainter {
  final SocialNetwork n;
  _GlyphPainter(this.n);

  @override
  void paint(Canvas canvas, Size s) {
    final w = s.width;
    final white = Paint()..color = Colors.white;
    final stroke = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * .075
      ..strokeCap = StrokeCap.round;
    final c = Offset(w / 2, w / 2);
    switch (n) {
      case SocialNetwork.instagram:
        canvas.drawRRect(
            RRect.fromRectAndRadius(Rect.fromCenter(center: c, width: w * .52, height: w * .52), Radius.circular(w * .15)),
            stroke);
        canvas.drawCircle(c, w * .12, stroke);
        canvas.drawCircle(Offset(w * .645, w * .355), w * .035, white);
      case SocialNetwork.facebook:
        // "f": dikey gövde, üstte kıvrım, ortada çizgi.
        final p = Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = w * .1;
        final path = Path()
          ..moveTo(w * .47, w * .8)
          ..lineTo(w * .47, w * .4)
          ..quadraticBezierTo(w * .47, w * .25, w * .62, w * .25)
          ..lineTo(w * .66, w * .25);
        canvas.drawPath(path, p);
        canvas.drawLine(Offset(w * .35, w * .47), Offset(w * .63, w * .47), p);
      case SocialNetwork.youtube:
        canvas.drawRRect(
            RRect.fromRectAndRadius(Rect.fromCenter(center: c, width: w * .56, height: w * .4), Radius.circular(w * .1)),
            white);
        final tri = Path()
          ..moveTo(w * .45, w * .39)
          ..lineTo(w * .62, w * .5)
          ..lineTo(w * .45, w * .61)
          ..close();
        canvas.drawPath(tri, Paint()..color = Color(n.color));
      case SocialNetwork.x:
        final thin = Paint()
          ..color = Colors.white
          ..strokeWidth = w * .05
          ..strokeCap = StrokeCap.round;
        final thick = Paint()
          ..color = Colors.white
          ..strokeWidth = w * .1
          ..strokeCap = StrokeCap.butt;
        canvas.drawLine(Offset(w * .32, w * .3), Offset(w * .68, w * .7), thick);
        canvas.drawLine(Offset(w * .67, w * .3), Offset(w * .33, w * .7), thin);
    }
  }

  @override
  bool shouldRepaint(_GlyphPainter old) => old.n != n;
}
