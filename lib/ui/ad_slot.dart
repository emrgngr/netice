import 'dart:async';
import 'dart:io';

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
    if (!adVideoSupported) return list.where((a) => a.type == AdType.image).toList();
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
    if (store.hasSubscription || _ads.isDismissed(widget.page, widget.format)) return const SizedBox.shrink();
    final list = _eligible();
    if (list.isEmpty) return const SizedBox.shrink();
    final ad = list[_index % list.length];
    _schedule(ad, list.length);
    final banner = widget.format == AdFormat.banner;
    final file = _ads.fileFor(ad)!;

    final media = ad.type == AdType.video
        ? _AdVideo(key: ValueKey('${ad.id}${file.path}'), file: file, loop: list.length == 1, onEnd: _next)
        : Image.file(file, key: ValueKey(file.path), fit: BoxFit.cover, gaplessPlayback: true,
            errorBuilder: (_, _, _) => const SizedBox.shrink());

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
