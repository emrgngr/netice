import 'package:material_ui/material_ui.dart';

import '../core/help_content.dart';
import 'illustrations.dart';
import 'onboarding_screen.dart';
import 'service_cards.dart';
import 'theme.dart';
import 'video_guide_screen.dart';
import 'widgets.dart';
import '../l10n/l10n.dart';
import '../core/ads.dart';
import 'ad_slot.dart';

/// Kullanma kılavuzu ve sık sorulan sorular (aramalı).
class HelpScreen extends StatefulWidget {
  /// 0: kılavuz, 1: SSS.
  final int initialTab;
  const HelpScreen({super.key, this.initialTab = 0});

  @override
  State<HelpScreen> createState() => _HelpScreenState();
}

class _HelpScreenState extends State<HelpScreen> {
  String _q = '';

  static IconData _icon(String name) => switch (name) {
        'start' => Icons.rocket_launch_outlined,
        'exam' => Icons.edit_note_rounded,
        'print' => Icons.print_outlined,
        'scan' => Icons.document_scanner_outlined,
        'report' => Icons.insights_rounded,
        'library' => Icons.local_library_outlined,
        'fix' => Icons.delete_sweep_outlined,
        'data' => Icons.shield_outlined,
        'pro' => Icons.workspace_premium_outlined,
        _ => Icons.help_outline,
      };

  static String _norm(String s) => s
      .toLowerCase()
      .replaceAll('ı', 'i')
      .replaceAll('İ', 'i')
      .replaceAll('ş', 's')
      .replaceAll('ğ', 'g')
      .replaceAll('ü', 'u')
      .replaceAll('ö', 'o')
      .replaceAll('ç', 'c');

  bool _match(String text) => _q.isEmpty || _norm(text).contains(_norm(_q));

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final muted = t.colorScheme.onSurface.withValues(alpha: 0.6);

    Widget search(String hint) => Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
          child: TextField(
            onChanged: (v) => setState(() => _q = v.trim()),
            decoration: InputDecoration(hintText: hint, prefixIcon: const Icon(Icons.search_rounded), isDense: true),
          ),
        );

    final wide = wideLayout(context);
    final guide = ListView(padding: const EdgeInsets.only(bottom: 32), children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
        child: HeroPanel(
          child: Row(children: [
            const IllustrationBadge(kind: IllustrationKind.guide, size: 72),
            const SizedBox(width: 16),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(tr('Kullanma kılavuzu'),
                    style: TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Text(tr('Okul bilgisinden dönem karnesine, adım adım.'),
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 13)),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white, side: BorderSide(color: Colors.white.withValues(alpha: 0.4))),
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const OnboardingScreen())),
                  icon: const Icon(Icons.play_circle_outline, size: 18),
                  label: Text(tr('Tanıtımı yeniden izle')),
                ),
              ]),
            ),
          ]),
        ),
      ),
      const Padding(padding: EdgeInsets.fromLTRB(16, 12, 16, 0), child: VideoGuideCard()),
      const AdSlot.card(AdPage.help, padding: EdgeInsets.fromLTRB(16, 12, 16, 0)),
      search(tr('Kılavuzda ara (ör. yedek, kitapçık)')),
      TwoColumns(wide: wide, children: [
      for (final s in guideSections)
        if (s.topics.any((tp) => _match('${s.title} ${tp.title} ${tp.steps.join(' ')} ${tp.tip ?? ''}'))) Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 6),
            child: Row(children: [
              IconBadge(_icon(s.icon), size: 30),
              const SizedBox(width: 10),
              Expanded(
                child: Text(s.title, style: t.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
              ),
              if (VideoGuide.sections.contains(s.icon)) ...[
                TextButton.icon(
                  style: TextButton.styleFrom(
                    foregroundColor: NColors.emerald,
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                  ),
                  onPressed: () => VideoGuideScreen.open(context, section: s.icon, title: s.title),
                  icon: const Icon(Icons.play_circle_fill_rounded, size: 20),
                  label: Text(tr('Videoyu izle')),
                ),
                Builder(
                  builder: (ctx) => IconButton(
                    tooltip: tr('Videoyu paylaş'),
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.share_rounded, size: 20),
                    onPressed: () =>
                        VideoGuide.share(ctx, lang: VideoGuide.defaultLang(), section: s.icon, title: s.title),
                  ),
                ),
              ],
            ]),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: RoundedPanel(
              child: Column(children: [
                for (final tp in s.topics)
                  if (_match('${s.title} ${tp.title} ${tp.steps.join(' ')} ${tp.tip ?? ''}'))
                    ExpansionTile(
                      initiallyExpanded: _q.isNotEmpty,
                      shape: const Border(),
                      title: Text(tp.title, style: const TextStyle(fontWeight: FontWeight.w700)),
                      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                      children: [
                        for (var i = 0; i < tp.steps.length; i++)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Container(
                                width: 22,
                                height: 22,
                                alignment: Alignment.center,
                                decoration: const BoxDecoration(color: NColors.ink, shape: BoxShape.circle),
                                child: Text('${i + 1}',
                                    style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800)),
                              ),
                              const SizedBox(width: 10),
                              Expanded(child: Text(tp.steps[i], style: const TextStyle(height: 1.4))),
                            ]),
                          ),
                        if (tp.tip != null)
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                                color: NColors.emerald.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
                            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              const Icon(Icons.lightbulb_outline_rounded, color: NColors.emerald, size: 20),
                              const SizedBox(width: 8),
                              Expanded(child: Text(tp.tip!, style: const TextStyle(height: 1.4))),
                            ]),
                          ),
                      ],
                    ),
              ]),
            ),
          ),
        ]),
      ]),
    ]);

    final cats = <String>{for (final f in faqs) f.category}.toList();
    final faq = ListView(padding: const EdgeInsets.only(bottom: 32), children: [
      search(tr('Soru ara (ör. barkod, e-Okul, silgi)')),
      TwoColumns(wide: wide, children: [
      for (final c in cats)
        if (faqs.any((f) => f.category == c && _match('${f.q} ${f.a}'))) Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 6),
            child: Text(c.toUpperCase(),
                style: TextStyle(color: muted, fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 1.2)),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: RoundedPanel(
              child: Column(children: [
                for (final f in faqs.where((f) => f.category == c && _match('${f.q} ${f.a}')))
                  ExpansionTile(
                    initiallyExpanded: _q.isNotEmpty,
                    shape: const Border(),
                    leading: const Icon(Icons.help_outline_rounded, color: NColors.emerald),
                    title: Text(f.q, style: const TextStyle(fontWeight: FontWeight.w600)),
                    childrenPadding: const EdgeInsets.fromLTRB(56, 0, 16, 14),
                    expandedAlignment: Alignment.centerLeft,
                    children: [Text(f.a, style: const TextStyle(height: 1.45))],
                  ),
              ]),
            ),
          ),
        ]),
      ]),
      if (!faqs.any((f) => _match('${f.q} ${f.a}')))
        Padding(
          padding: const EdgeInsets.all(32),
          child: Text(tr('Aramanıza uygun soru bulunamadı.'), textAlign: TextAlign.center, style: TextStyle(color: muted)),
        ),
    ]);

    return DefaultTabController(
      length: 2,
      initialIndex: widget.initialTab,
      child: Scaffold(
        appBar: AppBar(
          title: Text(tr('Yardım')),
          bottom: TabBar(tabs: [
            Tab(icon: Icon(Icons.menu_book_outlined), text: tr('Kılavuz')),
            Tab(icon: Icon(Icons.quiz_outlined), text: tr('Sık sorulanlar')),
          ]),
        ),
        body: TabBarView(children: [guide, faq]),
      ),
    );
  }
}
