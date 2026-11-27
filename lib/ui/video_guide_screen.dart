import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:material_ui/material_ui.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';

import '../core/legal.dart';
import '../l10n/l10n.dart';
import 'theme.dart';
import 'widgets.dart';

/// Seslendirmeli kullanım rehberi videoları (her uygulama dili için ayrı).
/// Videolar GitHub'daki "rehber-videolari" sürümünden oynatılır; internet gerekir.
class VideoGuide {
  static const baseUrl = 'https://github.com/emrgngr/netice/releases/download/rehber-videolari';

  /// Videosu hazır olan diller.
  static const languages = ['tr', 'en', 'de', 'fr', 'ru', 'az', 'es', 'it', 'ar', 'zh', 'ja', 'pt', 'hi', 'id', 'ko'];

  /// Kılavuzun bölüm videoları (GuideSection.icon ile aynı adlar).
  static const sections = ['start', 'exam', 'print', 'scan', 'report', 'library', 'fix', 'data', 'pro'];

  /// [section] verilmezse tüm uygulamayı anlatan rehber videosu.
  static String urlFor(String lang, [String? section]) =>
      section == null ? '$baseUrl/rehber_$lang.mp4' : '$baseUrl/kilavuz_${section}_$lang.mp4';

  /// Videoyu telefonun paylaşım menüsüyle gönderir (WhatsApp, e-posta…).
  /// Önce video dosyası indirilir; olmazsa bağlantısı paylaşılır.
  static Future<void> share(BuildContext context, {required String lang, String? section, required String title}) async {
    final url = urlFor(lang, section);
    final text = tr('{0} · Netice ile optik kâğıtları telefonla saniyeler içinde okuyun.\n\nİndir: {1}', [title, downloadUrl]);
    final box = context.findRenderObject() as RenderBox?;
    final origin = box == null ? null : box.localToGlobal(Offset.zero) & box.size;
    toast(context, tr('Video paylaşıma hazırlanıyor…'));
    try {
      final r = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 60));
      if (r.statusCode != 200) throw Exception(r.statusCode);
      final dir = await getTemporaryDirectory();
      final f = File('${dir.path}/${url.split('/').last}');
      await f.writeAsBytes(r.bodyBytes);
      await SharePlus.instance.share(ShareParams(
        files: [XFile(f.path, mimeType: 'video/mp4')],
        text: text,
        subject: title,
        sharePositionOrigin: origin,
      ));
    } catch (_) {
      try {
        await SharePlus.instance.share(ShareParams(text: '$text\n\n$url', subject: title, sharePositionOrigin: origin));
      } catch (_) {
        if (context.mounted) toast(context, tr('Paylaşım açılamadı.'));
      }
    }
  }

  static String defaultLang() =>
      languages.contains(L10n.code) ? L10n.code : (languages.contains('en') ? 'en' : languages.first);

  /// Uygulama içinde oynatılabilir mi (yalnız Linux'ta tarayıcıda açılır).
  static bool get inApp => !Platform.isLinux;

  /// Bilgisayarda video önce bu cihaza indirilip dosyadan oynatılır (Windows'un
  /// oynatıcısı yönlendirmeli adresleri her zaman açamıyor); sonraki açılışta
  /// indirmeden oynar.
  static bool get playFromFile => Platform.isWindows || Platform.isMacOS;

  static Future<File> cacheFile(String lang, [String? section]) async {
    final dir = Directory('${(await getApplicationSupportDirectory()).path}/rehber_videolari');
    await dir.create(recursive: true);
    return File('${dir.path}/${urlFor(lang, section).split('/').last}');
  }

  /// Videoyu bu cihaza indirir ([onProgress] 0–1). İndirilmişse yeniden indirmez.
  static Future<File> fetch(String lang, String? section, {void Function(double)? onProgress}) async {
    final f = await cacheFile(lang, section);
    if (await f.exists() && await f.length() > 0) return f;
    final client = http.Client();
    try {
      final res = await client.send(http.Request('GET', Uri.parse(urlFor(lang, section))));
      if (res.statusCode != 200) throw HttpException('${res.statusCode}');
      final total = res.contentLength ?? 0;
      final tmp = File('${f.path}.part');
      final sink = tmp.openWrite();
      var got = 0;
      await for (final chunk in res.stream) {
        sink.add(chunk);
        got += chunk.length;
        if (total > 0) onProgress?.call(got / total);
      }
      await sink.close();
      return await tmp.rename(f.path);
    } finally {
      client.close();
    }
  }

  /// Videoyu İndirilenler klasörüne (yoksa belgeler klasörüne) kaydeder.
  static Future<void> download(BuildContext context, {required String lang, String? section}) async {
    toast(context, tr('Video indiriliyor…'));
    try {
      final src = await fetch(lang, section);
      final dir = await getDownloadsDirectory() ?? await getApplicationDocumentsDirectory();
      final name = 'Netice_${urlFor(lang, section).split('/').last}';
      final out = await src.copy('${dir.path}${Platform.pathSeparator}$name');
      if (context.mounted) toast(context, tr('Video kaydedildi: {0}', [out.path]));
    } catch (_) {
      if (context.mounted) toast(context, tr('Video indirilemedi. İnternet bağlantınızı kontrol edin.'));
    }
  }
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
            Builder(
              builder: (ctx) => IconButton(
                tooltip: tr('Videoyu paylaş'),
                icon: const Icon(Icons.share_rounded),
                onPressed: () => VideoGuide.share(ctx, lang: VideoGuide.defaultLang(), title: tr('Video rehber')),
              ),
            ),
            const Icon(Icons.chevron_right_rounded),
          ]),
        ),
      ),
    );
  }
}

class VideoGuideScreen extends StatefulWidget {
  /// Kılavuz bölümü (ör. 'scan'); boşsa tüm rehber videosu.
  final String? section;
  final String? title;
  const VideoGuideScreen({super.key, this.section, this.title});

  static Future<void> open(BuildContext context, {String? section, String? title}) async {
    if (!VideoGuide.inApp) {
      await launchUrl(Uri.parse(VideoGuide.urlFor(VideoGuide.defaultLang(), section)), mode: LaunchMode.externalApplication);
      return;
    }
    await Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => VideoGuideScreen(section: section, title: title)));
  }

  @override
  State<VideoGuideScreen> createState() => _VideoGuideScreenState();
}

class _VideoGuideScreenState extends State<VideoGuideScreen> {
  late String _lang = VideoGuide.defaultLang();
  VideoPlayerController? _c;
  bool _error = false;
  double? _progress;

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
      _progress = null;
    });
    await old?.dispose();
    VideoPlayerController c;
    try {
      if (VideoGuide.playFromFile) {
        final lang = _lang;
        final f = await VideoGuide.fetch(lang, widget.section, onProgress: (p) {
          if (mounted && lang == _lang) setState(() => _progress = p);
        });
        if (!mounted || lang != _lang) return;
        c = VideoPlayerController.file(f);
      } else {
        c = VideoPlayerController.networkUrl(Uri.parse(VideoGuide.urlFor(_lang, widget.section)));
      }
    } catch (_) {
      if (mounted) setState(() => _error = true);
      return;
    }
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
        title: Text(widget.title ?? tr('Video rehber')),
        actions: [
          IconButton(
            tooltip: tr('Videoyu indir'),
            icon: const Icon(Icons.download_rounded),
            onPressed: () => VideoGuide.download(context, lang: _lang, section: widget.section),
          ),
          Builder(
            builder: (ctx) => IconButton(
              tooltip: tr('Videoyu paylaş'),
              icon: const Icon(Icons.share_rounded),
              onPressed: () => VideoGuide.share(ctx,
                  lang: _lang, section: widget.section, title: widget.title ?? tr('Video rehber')),
            ),
          ),
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
                      ? Column(mainAxisSize: MainAxisSize.min, children: [
                          CircularProgressIndicator(color: NColors.emerald, value: _progress),
                          if (_progress != null) ...[
                            const SizedBox(height: 14),
                            Text(tr('Video yükleniyor… %{0}', [(_progress! * 100).round()]),
                                style: const TextStyle(color: Colors.white70)),
                          ],
                        ])
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
