import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';

import '../core/ads.dart';
import '../l10n/l10n.dart';
import '../main.dart';
import 'theme.dart';

/// Video oynatılabilen platformlar (Windows için video_player_win eklidir).
bool get adVideoSupported =>
    !AdSlot.debugNoVideo && (Platform.isAndroid || Platform.isIOS || Platform.isMacOS || Platform.isWindows);

/// Sayfadaki reklam alanı. Uygun reklam yoksa hiç yer kaplamaz.
/// Netice Pro abonelerine reklam gösterilmez.
class AdSlot extends StatefulWidget {
  final AdPage page;
  final AdFormat format;
  final EdgeInsetsGeometry padding;

  const AdSlot.card(this.page, {super.key, this.padding = const EdgeInsets.symmetric(vertical: 8)})
      : format = AdFormat.card;
  const AdSlot.banner(this.page, {super.key, this.padding = EdgeInsets.zero}) : format = AdFormat.banner;

  /// Testlerde video oynatıcıyı açmamak için.
  static bool debugNoVideo = false;

  @override
  State<AdSlot> createState() => _AdSlotState();
}

class _AdSlotState extends State<AdSlot> {
  final _ads = AdService.instance;
  int _index = 0;
  Timer? _timer;
  String? _shownId;

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

  List<Ad> _eligible() {
    final list = _ads.adsFor(widget.page, widget.format);
    if (!adVideoSupported) return list.where((a) => a.type != AdType.video).toList();
    return list;
  }

  void _next() {
    if (!mounted) return;
    setState(() => _index++);
  }

  /// Görseller süresi dolunca, videolar bitince sıradakine geçer.
  void _schedule(Ad ad, int count) {
    if (_shownId == ad.id) return;
    _shownId = ad.id;
    _timer?.cancel();
    if (count > 1 && ad.type == AdType.image) {
      _timer = Timer(Duration(seconds: ad.seconds), _next);
    }
  }

  Future<void> _open(Ad ad) async {
    if (ad.link.isEmpty) return;
    try {
      await launchUrl(Uri.parse(ad.link), mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    if (store.adFree || _ads.isDismissed(widget.page, widget.format)) return const SizedBox.shrink();
    final list = _eligible();
    if (list.isEmpty) return const SizedBox.shrink();
    final ad = list[_index % list.length];
    _schedule(ad, list.length);
    final banner = widget.format == AdFormat.banner;
    final files = _ads.filesFor(ad)!;
    final file = files.first;

    final media = switch (ad.type) {
      AdType.video => _AdVideo(key: ValueKey('${ad.id}${file.path}'), file: file, loop: list.length == 1, onEnd: _next),
      AdType.slider => AdSlider.files(
          files,
          key: ValueKey('${ad.id}/${ad.style.key}/${files.length}'),
          style: ad.style,
          seconds: ad.seconds,
          onCycle: list.length > 1 ? _next : null,
        ),
      AdType.image => Image.file(file, key: ValueKey(file.path), fit: BoxFit.cover, gaplessPlayback: true,
          errorBuilder: (_, _, _) => const SizedBox.shrink()),
    };

    final box = AspectRatio(
      aspectRatio: banner ? 5 : 16 / 9,
      child: Stack(fit: StackFit.expand, children: [
        Material(
          color: NColors.ink.withValues(alpha: 0.06),
          child: InkWell(
            onTap: ad.link.isEmpty ? null : () => _open(ad),
            child: AnimatedSwitcher(duration: const Duration(milliseconds: 400), child: media),
          ),
        ),
        PositionedDirectional(
          start: 6,
          top: 6,
          child: IgnorePointer(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.45),
                borderRadius: BorderRadius.circular(5),
              ),
              child: Text(tr('Reklam'),
                  style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700)),
            ),
          ),
        ),
        PositionedDirectional(
          end: 2,
          top: 2,
          child: Tooltip(
            message: tr('Reklamı kapat'),
            child: InkResponse(
              radius: 18,
              onTap: () => _ads.dismiss(widget.page, widget.format),
              child: Container(
                margin: const EdgeInsets.all(4),
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.45), shape: BoxShape.circle),
                child: const Icon(Icons.close_rounded, size: 14, color: Colors.white),
              ),
            ),
          ),
        ),
      ]),
    );

    if (banner) {
      return Padding(
        padding: widget.padding,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 728),
            child: ClipRRect(borderRadius: BorderRadius.circular(10), child: box),
          ),
        ),
      );
    }
    return Padding(
      padding: widget.padding,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ClipRRect(borderRadius: BorderRadius.circular(18), child: box),
        ),
      ),
    );
  }
}

/// Alt kenardaki şerit reklam (Scaffold.bottomNavigationBar için).
class AdBannerBar extends StatelessWidget {
  final AdPage page;
  const AdBannerBar(this.page, {super.key});

  @override
  Widget build(BuildContext context) => SafeArea(
        top: false,
        child: AdSlot.banner(page, padding: const EdgeInsets.fromLTRB(12, 6, 12, 8)),
      );
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
  const AdSlider({super.key, required this.items, required this.style, this.seconds = 3, this.onCycle, this.dots = true});

  AdSlider.files(List<File> files,
      {Key? key, required SlideStyle style, int seconds = 3, VoidCallback? onCycle, bool dots = true})
      : this(
          key: key,
          items: [
            for (final f in files)
              Image.file(f, fit: BoxFit.cover, gaplessPlayback: true, errorBuilder: (_, _, _) => const SizedBox.shrink()),
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
  late final AnimationController _c = AnimationController(
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

  Widget _item(int k) => KeyedSubtree(key: ValueKey(k), child: SizedBox.expand(child: widget.items[k]));

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
          Opacity(opacity: t, child: Transform.scale(scale: 1.18 - 0.18 * t, child: inc)),
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
    return Stack(fit: StackFit.expand, children: [
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
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
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
            ]),
          ),
        ),
    ]);
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
    if (!widget.loop && !_ended && v.duration > Duration.zero && v.position >= v.duration - const Duration(milliseconds: 150)) {
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
    return Stack(fit: StackFit.expand, children: [
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
    ]);
  }
}
