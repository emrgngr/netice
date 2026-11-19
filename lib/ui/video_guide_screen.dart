import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';

import '../l10n/l10n.dart';
import 'theme.dart';

/// Seslendirmeli kullanım rehberi videoları (her uygulama dili için ayrı).
/// Videolar GitHub'daki "rehber-videolari" sürümünden oynatılır; internet gerekir.
class VideoGuide {
  static const baseUrl = 'https://github.com/emrgngr/netice/releases/download/rehber-videolari';

  /// Videosu hazır olan diller.
  static const languages = ['tr', 'en', 'de', 'fr', 'ru', 'az', 'es', 'it', 'ar', 'zh', 'ja'];

  static String urlFor(String lang) => '$baseUrl/rehber_$lang.mp4';

  static String defaultLang() =>
      languages.contains(L10n.code) ? L10n.code : (languages.contains('en') ? 'en' : languages.first);

  /// Uygulama içinde oynatılabilir mi (Windows ve Linux'ta tarayıcıda açılır).
  static bool get inApp => !(Platform.isWindows || Platform.isLinux);
}

/// Yardım ekranındaki "Video rehber" kartı.
class VideoGuideCard extends StatelessWidget {
  const VideoGuideCard({super.key});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => VideoGuideScreen.open(context),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [NColors.ink, Color(0xFF1C2E63)]),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Icon(Icons.play_arrow_rounded, color: NColors.emerald, size: 34),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(tr('Video rehber'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                const SizedBox(height: 2),
                Text(tr('Açılıştan raporlara kadar, sesli anlatımla adım adım.'),
                    style: t.textTheme.bodySmall),
              ]),
            ),
            const Icon(Icons.chevron_right_rounded),
          ]),
        ),
      ),
    );
  }
}

class VideoGuideScreen extends StatefulWidget {
  const VideoGuideScreen({super.key});

  static Future<void> open(BuildContext context) async {
    if (!VideoGuide.inApp) {
      await launchUrl(Uri.parse(VideoGuide.urlFor(VideoGuide.defaultLang())), mode: LaunchMode.externalApplication);
      return;
    }
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const VideoGuideScreen()));
  }

  @override
  State<VideoGuideScreen> createState() => _VideoGuideScreenState();
}

class _VideoGuideScreenState extends State<VideoGuideScreen> {
  late String _lang = VideoGuide.defaultLang();
  VideoPlayerController? _c;
  bool _error = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final old = _c;
    setState(() {
      _c = null;
      _error = false;
    });
    await old?.dispose();
    final c = VideoPlayerController.networkUrl(Uri.parse(VideoGuide.urlFor(_lang)));
    try {
      await c.initialize();
      if (!mounted) {
        await c.dispose();
        return;
      }
      c.addListener(() {
        if (mounted) setState(() {});
      });
      await c.play();
      setState(() => _c = c);
    } catch (_) {
      await c.dispose();
      if (mounted) setState(() => _error = true);
    }
  }

  @override
  void dispose() {
    _c?.dispose();
    super.dispose();
  }

  String _time(Duration d) => '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final c = _c;
    return Scaffold(
      backgroundColor: NColors.ink,
      appBar: AppBar(
        backgroundColor: NColors.ink,
        foregroundColor: Colors.white,
        title: Text(tr('Video rehber')),
        actions: [
          PopupMenuButton<String>(
            tooltip: tr('Video dili'),
            icon: const Icon(Icons.translate_rounded),
            onSelected: (l) {
              _lang = l;
              _load();
            },
            itemBuilder: (_) => [
              for (final l in AppLanguage.all)
                if (VideoGuide.languages.contains(l.code))
                  CheckedPopupMenuItem(value: l.code, checked: l.code == _lang, child: Text('${l.flag}  ${l.name}')),
            ],
          ),
        ],
      ),
      body: SafeArea(
        child: Column(children: [
          Expanded(
            child: Center(
              child: _error
                  ? Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        const Icon(Icons.wifi_off_rounded, color: Colors.white70, size: 48),
                        const SizedBox(height: 12),
                        Text(tr('Video açılamadı. Videoyu izlemek için internet bağlantısı gerekir.'),
                            textAlign: TextAlign.center, style: const TextStyle(color: Colors.white)),
                        const SizedBox(height: 16),
                        FilledButton.icon(
                            onPressed: _load, icon: const Icon(Icons.refresh_rounded), label: Text(tr('Tekrar dene'))),
                      ]),
                    )
                  : c == null
                      ? const CircularProgressIndicator(color: NColors.emerald)
                      : GestureDetector(
                          onTap: () => c.value.isPlaying ? c.pause() : c.play(),
                          child: AspectRatio(
                            aspectRatio: c.value.aspectRatio,
                            child: Stack(alignment: Alignment.center, children: [
                              VideoPlayer(c),
                              if (!c.value.isPlaying)
                                Container(
                                  decoration: const BoxDecoration(color: Colors.black45, shape: BoxShape.circle),
                                  padding: const EdgeInsets.all(12),
                                  child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 48),
                                ),
                            ]),
                          ),
                        ),
            ),
          ),
          if (c != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 16, 8),
              child: Row(children: [
                IconButton(
                  color: Colors.white,
                  icon: Icon(c.value.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded),
                  onPressed: () => c.value.isPlaying ? c.pause() : c.play(),
                ),
                Expanded(
                  child: VideoProgressIndicator(c,
                      allowScrubbing: true,
                      colors: const VideoProgressColors(playedColor: NColors.emerald, bufferedColor: Colors.white24)),
                ),
                const SizedBox(width: 10),
                Text('${_time(c.value.position)} / ${_time(c.value.duration)}',
                    style: const TextStyle(color: Colors.white70, fontSize: 12)),
              ]),
            ),
        ]),
      ),
    );
  }
}
