import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:qr/qr.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';

import '../core/ads.dart';
import '../core/store.dart';
import '../l10n/l10n.dart';
import '../main.dart';
import 'theme.dart';
import 'widgets.dart';

/// Video oynatılabilen platformlar (Windows için video_player_win eklidir).
bool get adVideoSupported =>
    !AdSlot.debugNoVideo && (Platform.isAndroid || Platform.isIOS || Platform.isMacOS || Platform.isWindows);

/// Cihazın ülke kodu (tr_TR → TR), bilinmiyorsa boş.
String deviceCountry() {
  if (AdSlot.debugCountry != null) return AdSlot.debugCountry!;
  try {
    final parts = Platform.localeName.split(RegExp('[_.@-]'));
    for (final p in parts.skip(1)) {
      if (p.length == 2 && RegExp(r'^[A-Za-z]{2}$').hasMatch(p)) return p.toUpperCase();
    }
  } catch (_) {}
  return '';
}

/// Ağırlığa (öncelik 1–5) göre dönüş sırası: 3,2,1 → A B C A B A.
List<Ad> weightedRotation(List<Ad> list) {
  if (list.length < 2) return list;
  final top = list.map((a) => a.weight).reduce(math.max);
  return [
    for (var r = 0; r < top; r++)
      for (final a in list)
        if (a.weight > r) a,
  ];
}

/// Gösterilecek ana dosyalar: gece modunda gece görseli, A/B'de sıradaki görsel.
List<File>? adDisplayFiles(Ad ad, {required bool dark, bool variantB = false}) {
  final ads = AdService.instance;
  final main = ads.filesFor(ad);
  if (main == null || ad.type != AdType.image) return main;
  if (dark) {
    final d = ads.optionalFile(ad.mediaDark);
    if (d != null) return [d];
  }
  if (variantB) {
    final b = ads.optionalFile(ad.mediaB);
    if (b != null) return [b];
  }
  return main;
}

/// Geri sayım rozeti metni (bitişe 7 günden az kaldıysa).
String? adCountdownText(Ad ad, DateTime now) {
  if (!ad.countdown) return null;
  final rem = ad.remaining(now);
  if (rem == null || rem <= Duration.zero || rem > const Duration(days: 7)) return null;
  if (rem.inHours < 24) return tr('Bitmesine {0} saat', [math.max(1, (rem.inMinutes / 60).ceil())]);
  final days = (rem.inHours / 24).ceil();
  return tr('Bitmesine {0} gün', [days]);
}

/// Sayfadaki reklam alanı. Uygun reklam yoksa hiç yer kaplamaz (ayar açıksa
/// kart alanlarında "Burada reklamınız olsun" kartı çıkar).
/// Reklamsız kullanıcılara (Pro vb.) hiçbiri gösterilmez.
class AdSlot extends StatefulWidget {
  final AdPage page;
  final AdFormat format;
  final EdgeInsetsGeometry padding;

  const AdSlot.card(this.page, {super.key, this.padding = const EdgeInsets.symmetric(vertical: 8)})
    : format = AdFormat.card;
  const AdSlot.banner(this.page, {super.key, this.padding = EdgeInsets.zero}) : format = AdFormat.banner;

  /// Testlerde video oynatıcıyı açmamak için.
  static bool debugNoVideo = false;

  /// Testlerde ülke kodu.
  static String? debugCountry;

  /// Testlerde geniş ekran (QR) davranışını zorlamak için.
  static bool? debugDesktop;

  static bool get isDesktop => debugDesktop ?? (Platform.isWindows || Platform.isMacOS || Platform.isLinux);

  @override
  State<AdSlot> createState() => _AdSlotState();
}

class _AdSlotState extends State<AdSlot> {
  final _ads = AdService.instance;
  int _index = 0;
  Timer? _timer;
  String? _shownKey;
  bool _variantB = false;

  @override
  void initState() {
    super.initState();
    _ads.addListener(_changed);
    _ads.refresh();
  }

  @override
  void dispose() {
    _ads.removeListener(_changed);
    _timer?.cancel();
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  List<Ad> _eligible(AppStore store) {
    final aud = AdAudience(
      lang: L10n.code,
      country: deviceCountry(),
      institution: store.school.type.name,
      now: DateTime.now(),
    );
    final list = _ads.adsFor(widget.page, widget.format, aud);
    if (!adVideoSupported) return list.where((a) => a.type != AdType.video).toList();
    return list;
  }

  void _next() {
    if (!mounted) return;
    setState(() => _index++);
  }

  /// Yeni reklam ekrana gelince: gösterimi say, A/B sırasını belirle,
  /// sabit görselde süre sonunda sıradakine geç.
  void _schedule(Ad ad, int unique) {
    final key = '$_index/${ad.id}';
    if (_shownKey == key) return;
    _shownKey = key;
    _variantB = _ads.useVariantB(ad);
    _ads.recordImpression(ad, variantB: _variantB);
    _timer?.cancel();
    if (unique > 1 && ad.type == AdType.image) {
      _timer = Timer(Duration(seconds: ad.seconds), _next);
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    if (store.adFree || _ads.isDismissed(widget.page, widget.format)) return const SizedBox.shrink();
    final list = _eligible(store);
    if (list.isEmpty) {
      final s = _ads.activeSettings;
      if (widget.format == AdFormat.card && s.emptySlotCard) {
        return _frame(AdEmptyCard(email: s.contactEmail, onClose: () => _ads.dismiss(widget.page, widget.format)));
      }
      return const SizedBox.shrink();
    }
    final rotation = weightedRotation(list);
    final ad = rotation[_index % rotation.length];
    _schedule(ad, list.length);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final files = adDisplayFiles(ad, dark: dark, variantB: _variantB) ?? _ads.filesFor(ad)!;
    return _frame(
      AdView(
        ad: ad,
        files: files,
        banner: widget.format == AdFormat.banner,
        showQr: AdSlot.isDesktop,
        loopVideo: list.length == 1,
        onCycle: list.length > 1 ? _next : null,
        onClose: () => _ads.dismiss(widget.page, widget.format),
        onOpen: () => _ads.recordClick(ad, variantB: _variantB),
      ),
    );
  }

  Widget _frame(Widget box) {
    final banner = widget.format == AdFormat.banner;
    return Padding(
      padding: widget.padding,
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: banner ? 728 : 720),
          child: ClipRRect(borderRadius: BorderRadius.circular(banner ? 10 : 18), child: box),
        ),
      ),
    );
  }
}

/// Tek bir reklamın görünümü: medya + "Reklam" etiketi, düğme, indirim kodu,
/// geri sayım ve bilgisayarda QR kodu. Cihaz önizlemesinde de kullanılır.
class AdView extends StatelessWidget {
  final Ad ad;
  final List<File> files;
  final bool banner;
  final bool showQr;
  final bool loopVideo;
  final VoidCallback? onCycle;
  final VoidCallback? onClose;

  /// Bağlantı açılınca (tıklama sayacı).
  final VoidCallback? onOpen;

  /// Geri sayım için "şimdi" (önizlemede sabitlenebilir).
  final DateTime? now;

  const AdView({
    super.key,
    required this.ad,
    required this.files,
    this.banner = false,
    this.showQr = false,
    this.loopVideo = true,
    this.onCycle,
    this.onClose,
    this.onOpen,
    this.now,
  });

  Future<void> _open() async {
    if (ad.link.isEmpty) return;
    onOpen?.call();
    try {
      await launchUrl(Uri.parse(ad.link), mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final file = files.first;
    final media = switch (ad.type) {
      AdType.video =>
        adVideoSupported
            ? _AdVideo(key: ValueKey('${ad.id}${file.path}'), file: file, loop: loopVideo, onEnd: onCycle ?? () {})
            : const SizedBox.shrink(),
      AdType.slider => AdSlider.files(
        files,
        key: ValueKey('${ad.id}/${ad.style.key}/${files.length}'),
        style: ad.style,
        seconds: ad.seconds,
        onCycle: onCycle,
      ),
      AdType.image => Image.file(
        file,
        key: ValueKey(file.path),
        fit: BoxFit.cover,
        gaplessPlayback: true,
        errorBuilder: (_, _, _) => const SizedBox.shrink(),
      ),
    };
    final countdown = adCountdownText(ad, now ?? DateTime.now());
    final qr = showQr && !banner && ad.link.isNotEmpty;

    return AspectRatio(
      aspectRatio: banner ? 5 : 16 / 9,
      child: LayoutBuilder(
        builder: (context, box) {
          // Küçük alanlarda öğeler orantılı küçülür.
          final k = (banner ? box.maxHeight / 80 : box.maxWidth / 380).clamp(0.75, 1.35);
          final showCode = ad.code.isNotEmpty && (!banner || box.maxWidth >= 460);
          return Stack(
            fit: StackFit.expand,
            children: [
              Material(
                color: NColors.ink.withValues(alpha: 0.06),
                child: InkWell(
                  onTap: ad.link.isEmpty ? null : _open,
                  child: AnimatedSwitcher(duration: const Duration(milliseconds: 400), child: media),
                ),
              ),
              PositionedDirectional(
                start: 6,
                top: 6,
                child: IgnorePointer(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _pill(tr('Reklam'), Colors.black.withValues(alpha: 0.45), 10),
                      if (countdown != null) ...[
                        const SizedBox(width: 5),
                        _pill(countdown, NColors.coral, 10 * k, icon: Icons.timer_outlined),
                      ],
                    ],
                  ),
                ),
              ),
              if (onClose != null)
                PositionedDirectional(
                  end: 2,
                  top: 2,
                  child: Tooltip(
                    message: tr('Reklamı kapat'),
                    child: InkResponse(
                      radius: 18,
                      onTap: onClose,
                      child: Container(
                        margin: const EdgeInsets.all(4),
                        padding: const EdgeInsets.all(3),
                        decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.45), shape: BoxShape.circle),
                        child: const Icon(Icons.close_rounded, size: 14, color: Colors.white),
                      ),
                    ),
                  ),
                ),
              if (ad.cta.isNotEmpty || showCode || qr)
                PositionedDirectional(
                  start: banner ? null : 10 * k,
                  end:
                      (banner
                          ? 34
                          : ad.type == AdType.video
                          ? 40
                          : 10) *
                      k,
                  bottom: banner ? 0 : 10 * k,
                  top: banner ? 0 : null,
                  child: Align(
                    alignment: banner ? AlignmentDirectional.centerEnd : AlignmentDirectional.bottomEnd,
                    child: Row(
                      mainAxisSize: banner ? MainAxisSize.min : MainAxisSize.max,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        if (showCode) _CodeChip(code: ad.code, scale: k),
                        if (!banner) const Spacer(),
                        if (banner && showCode && ad.cta.isNotEmpty) SizedBox(width: 6 * k),
                        if (ad.cta.isNotEmpty)
                          _CtaPill(label: ad.cta, scale: banner ? k * 0.85 : k, onTap: ad.link.isEmpty ? null : _open),
                        if (qr) ...[SizedBox(width: 8 * k), _QrTile(data: ad.link, size: 62 * k)],
                      ],
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  static Widget _pill(String text, Color bg, double size, {IconData? icon}) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
    decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(5)),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[Icon(icon, size: size + 2, color: Colors.white), const SizedBox(width: 3)],
        Text(
          text,
          style: TextStyle(color: Colors.white, fontSize: size, fontWeight: FontWeight.w700),
        ),
      ],
    ),
  );
}

/// Görsel üstündeki düğme: zümrüt zemin, daima beyaz yazı.
class _CtaPill extends StatelessWidget {
  final String label;
  final double scale;
  final VoidCallback? onTap;
  const _CtaPill({required this.label, required this.scale, this.onTap});

  @override
  Widget build(BuildContext context) => Material(
    color: NColors.nightEmerald,
    elevation: 3,
    shape: const StadiumBorder(),
    child: InkWell(
      customBorder: const StadiumBorder(),
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 14 * scale, vertical: 7 * scale),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              maxLines: 1,
              style: TextStyle(color: Colors.white, fontSize: 13 * scale, fontWeight: FontWeight.w800),
            ),
            SizedBox(width: 4 * scale),
            Icon(Icons.arrow_forward_rounded, size: 15 * scale, color: Colors.white),
          ],
        ),
      ),
    ),
  );
}

/// İndirim kodu: dokununca panoya kopyalanır.
class _CodeChip extends StatelessWidget {
  final String code;
  final double scale;
  const _CodeChip({required this.code, required this.scale});

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white,
    elevation: 3,
    borderRadius: BorderRadius.circular(9),
    child: InkWell(
      borderRadius: BorderRadius.circular(9),
      onTap: () async {
        await Clipboard.setData(ClipboardData(text: code));
        if (context.mounted) toast(context, tr('Kod kopyalandı: {0}', [code]));
      },
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 10 * scale, vertical: 6 * scale),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: NColors.coral, width: 1.4),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.local_offer_rounded, size: 14 * scale, color: NColors.coral),
            SizedBox(width: 5 * scale),
            Text(
              code,
              style: TextStyle(color: NColors.ink, fontSize: 13 * scale, fontWeight: FontWeight.w900, letterSpacing: 1),
            ),
            SizedBox(width: 5 * scale),
            Icon(Icons.copy_rounded, size: 13 * scale, color: NColors.ink.withValues(alpha: 0.55)),
          ],
        ),
      ),
    ),
  );
}

/// Bilgisayarda: telefonla okutulacak QR kodu.
class _QrTile extends StatelessWidget {
  final String data;
  final double size;
  const _QrTile({required this.data, required this.size});

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tr('Telefonunuzla okutun'),
    child: Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4)],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox.square(dimension: size, child: AdQr(data)),
          const SizedBox(height: 2),
          Text(
            tr('Telefonla aç'),
            style: TextStyle(color: NColors.ink, fontSize: math.max(8, size / 7.5), fontWeight: FontWeight.w700),
          ),
        ],
      ),
    ),
  );
}

/// Bağımlılıksız QR çizimi.
class AdQr extends StatelessWidget {
  final String data;
  const AdQr(this.data, {super.key});

  @override
  Widget build(BuildContext context) {
    QrImage? img;
    try {
      img = QrImage(QrCode.fromData(data: data, errorCorrectLevel: QrErrorCorrectLevel.M));
    } catch (_) {}
    if (img == null) return const SizedBox.shrink();
    return CustomPaint(painter: _QrPainter(img));
  }
}

class _QrPainter extends CustomPainter {
  final QrImage img;
  _QrPainter(this.img);

  @override
  void paint(Canvas canvas, Size size) {
    final n = img.moduleCount;
    final cell = size.shortestSide / n;
    final p = Paint()..color = NColors.ink;
    for (var r = 0; r < n; r++) {
      for (var c = 0; c < n; c++) {
        if (img.isDark(r, c)) canvas.drawRect(Rect.fromLTWH(c * cell, r * cell, cell + 0.3, cell + 0.3), p);
      }
    }
  }

  @override
  bool shouldRepaint(_QrPainter old) => old.img != img;
}

/// Boş kart alanı: "Burada reklamınız olsun".
class AdEmptyCard extends StatelessWidget {
  final String email;
  final VoidCallback? onClose;
  const AdEmptyCard({super.key, required this.email, this.onClose});

  Future<void> _mail() async {
    final uri = Uri(scheme: 'mailto', path: email, query: 'subject=${Uri.encodeComponent(tr('Netice reklam alanı'))}');
    try {
      await launchUrl(uri);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) => AspectRatio(
    aspectRatio: 16 / 9,
    child: LayoutBuilder(
      builder: (context, box) {
        final k = (box.maxWidth / 380).clamp(0.75, 1.35);
        return Stack(
          fit: StackFit.expand,
          children: [
            DecoratedBox(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [NColors.ink, Color(0xFF1E3A8A)],
                ),
              ),
              child: Padding(
                padding: EdgeInsets.all(18 * k),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.campaign_rounded, color: NColors.amber, size: 34 * k),
                    SizedBox(height: 8 * k),
                    Text(
                      tr('Burada reklamınız olsun'),
                      style: TextStyle(color: Colors.white, fontSize: 20 * k, fontWeight: FontWeight.w900),
                    ),
                    SizedBox(height: 4 * k),
                    Text(
                      tr('Öğretmenlere ve kurumlara ulaşın. Bu alan için bize yazın.'),
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 12.5 * k),
                    ),
                    SizedBox(height: 12 * k),
                    _CtaPill(label: tr('Bize yazın'), scale: k, onTap: _mail),
                  ],
                ),
              ),
            ),
            if (onClose != null)
              PositionedDirectional(
                end: 2,
                top: 2,
                child: InkResponse(
                  radius: 18,
                  onTap: onClose,
                  child: Container(
                    margin: const EdgeInsets.all(4),
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.18), shape: BoxShape.circle),
                    child: const Icon(Icons.close_rounded, size: 14, color: Colors.white),
                  ),
                ),
              ),
          ],
        );
      },
    ),
  );
}

/// Alt kenardaki şerit reklam (Scaffold.bottomNavigationBar için).
class AdBannerBar extends StatelessWidget {
  final AdPage page;
  const AdBannerBar(this.page, {super.key});

  @override
  Widget build(BuildContext context) =>
      SafeArea(top: false, child: AdSlot.banner(page, padding: const EdgeInsets.fromLTRB(12, 6, 12, 8)));
}

/// Birden çok görseli [seconds] saniyede bir, seçilen geçişle değiştiren slider.
/// Son görselden sonra [onCycle] çağrılır (başka reklam varsa ona geçilir),
/// yoksa başa döner.
class AdSlider extends StatefulWidget {
  final List<Widget> items;
  final SlideStyle style;
  final int seconds;
  final VoidCallback? onCycle;
  final bool dots;
  const AdSlider({
    super.key,
    required this.items,
    required this.style,
    this.seconds = 3,
    this.onCycle,
    this.dots = true,
  });

  AdSlider.files(
    List<File> files, {
    Key? key,
    required SlideStyle style,
    int seconds = 3,
    VoidCallback? onCycle,
    bool dots = true,
  }) : this(
         key: key,
         items: [
           for (final f in files)
             Image.file(
               f,
               fit: BoxFit.cover,
               gaplessPlayback: true,
               errorBuilder: (_, _, _) => const SizedBox.shrink(),
             ),
         ],
         style: style,
         seconds: seconds,
         onCycle: onCycle,
         dots: dots,
       );

  @override
  State<AdSlider> createState() => _AdSliderState();
}

class _AdSliderState extends State<AdSlider> with SingleTickerProviderStateMixin {
  int _i = 0;
  int? _prev;
  Timer? _timer;
  late final AnimationController _c =
      AnimationController(
        vsync: this,
        duration: Duration(milliseconds: widget.style == SlideStyle.flip ? 700 : 600),
      )..addStatusListener((st) {
        if (st == AnimationStatus.completed && mounted) setState(() => _prev = null);
      });

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void didUpdateWidget(AdSlider old) {
    super.didUpdateWidget(old);
    if (old.seconds != widget.seconds || old.items.length != widget.items.length) {
      _i = _i % widget.items.length;
      _prev = null;
      _start();
    }
  }

  void _start() {
    _timer?.cancel();
    if (widget.items.length < 2) return;
    _timer = Timer.periodic(Duration(seconds: widget.seconds.clamp(2, 60)), (_) {
      if (!mounted || !TickerMode.valuesOf(context).enabled) return;
      if (_i == widget.items.length - 1 && widget.onCycle != null) {
        _timer?.cancel();
        widget.onCycle!();
        return;
      }
      setState(() {
        _prev = _i;
        _i = (_i + 1) % widget.items.length;
      });
      _c.forward(from: 0);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _c.dispose();
    super.dispose();
  }

  Widget _item(int k) => KeyedSubtree(
    key: ValueKey(k),
    child: SizedBox.expand(child: widget.items[k]),
  );

  /// Geçişin [t] (0→1) anındaki görünümü.
  List<Widget> _frame(double t, Widget out, Widget inc) {
    Widget flip(Widget w, double angle) => Transform(
      alignment: Alignment.center,
      transform: Matrix4.identity()
        ..setEntry(3, 2, 0.0015)
        ..rotateY(angle),
      child: w,
    );
    switch (widget.style) {
      case SlideStyle.slide:
        return [
          FractionalTranslation(translation: Offset(-t, 0), child: out),
          FractionalTranslation(translation: Offset(1 - t, 0), child: inc),
        ];
      case SlideStyle.vertical:
        return [
          FractionalTranslation(translation: Offset(0, -t), child: out),
          FractionalTranslation(translation: Offset(0, 1 - t), child: inc),
        ];
      case SlideStyle.fade:
        return [out, Opacity(opacity: t, child: inc)];
      case SlideStyle.zoom:
        return [
          out,
          Opacity(
            opacity: t,
            child: Transform.scale(scale: 1.18 - 0.18 * t, child: inc),
          ),
        ];
      case SlideStyle.flip:
        return [
          Container(color: Colors.black.withValues(alpha: 0.08)),
          if (t < 0.5) flip(out, -t * math.pi) else flip(inc, (1 - t) * math.pi),
        ];
    }
  }

  @override
  Widget build(BuildContext context) {
    final n = widget.items.length;
    if (n == 0) return const SizedBox.shrink();
    final i = _i % n;
    return Stack(
      fit: StackFit.expand,
      children: [
        ClipRect(
          child: AnimatedBuilder(
            animation: _c,
            builder: (_, _) {
              final prev = _prev;
              if (prev == null || !_c.isAnimating) return Stack(fit: StackFit.expand, children: [_item(i)]);
              final t = Curves.easeInOutCubic.transform(_c.value);
              return Stack(fit: StackFit.expand, children: _frame(t, _item(prev % n), _item(i)));
            },
          ),
        ),
        if (widget.dots && n > 1)
          PositionedDirectional(
            bottom: 6,
            start: 0,
            end: 0,
            child: IgnorePointer(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var k = 0; k < n; k++)
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 250),
                      margin: const EdgeInsets.symmetric(horizontal: 2.5),
                      width: k == i ? 16 : 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: k == i ? 0.95 : 0.55),
                        borderRadius: BorderRadius.circular(3),
                        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 3)],
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

/// Sessiz, kendiliğinden başlayan video. Ses düğmesiyle açılır; sayfa
/// arkada kalınca durur.
class _AdVideo extends StatefulWidget {
  final File file;
  final bool loop;
  final VoidCallback onEnd;
  const _AdVideo({super.key, required this.file, required this.loop, required this.onEnd});

  @override
  State<_AdVideo> createState() => _AdVideoState();
}

class _AdVideoState extends State<_AdVideo> {
  VideoPlayerController? _c;
  bool _muted = true;
  bool _ended = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final c = VideoPlayerController.file(widget.file, videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true));
    try {
      await c.initialize();
      await c.setVolume(0);
      await c.setLooping(widget.loop);
      if (!mounted) {
        await c.dispose();
        return;
      }
      c.addListener(_tick);
      setState(() => _c = c);
      _sync();
    } catch (_) {
      await c.dispose();
      if (mounted) {
        setState(() => _failed = true);
        widget.onEnd();
      }
    }
  }

  void _tick() {
    final c = _c;
    if (c == null || !mounted) return;
    final v = c.value;
    if (!widget.loop &&
        !_ended &&
        v.duration > Duration.zero &&
        v.position >= v.duration - const Duration(milliseconds: 150)) {
      _ended = true;
      widget.onEnd();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  /// Sayfa görünmüyorsa (üstüne başka sayfa açıldıysa) durdur.
  void _sync() {
    final c = _c;
    if (c == null) return;
    if (TickerMode.valuesOf(context).enabled) {
      if (!c.value.isPlaying) c.play();
    } else if (c.value.isPlaying) {
      c.pause();
    }
  }

  @override
  void dispose() {
    _c?.removeListener(_tick);
    _c?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _c;
    if (_failed) return const SizedBox.shrink();
    if (c == null) {
      return const Center(child: SizedBox.square(dimension: 22, child: CircularProgressIndicator(strokeWidth: 2)));
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        FittedBox(
          fit: BoxFit.cover,
          clipBehavior: Clip.hardEdge,
          child: SizedBox(width: c.value.size.width, height: c.value.size.height, child: VideoPlayer(c)),
        ),
        PositionedDirectional(
          end: 6,
          bottom: 6,
          child: InkResponse(
            radius: 18,
            onTap: () {
              setState(() => _muted = !_muted);
              c.setVolume(_muted ? 0 : 1);
            },
            child: Container(
              padding: const EdgeInsets.all(5),
              decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.45), shape: BoxShape.circle),
              child: Icon(_muted ? Icons.volume_off_rounded : Icons.volume_up_rounded, size: 16, color: Colors.white),
            ),
          ),
        ),
      ],
    );
  }
}
