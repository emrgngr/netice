import 'package:file_picker/file_picker.dart';
import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/ad_admin.dart';
import '../core/ads.dart';
import '../l10n/l10n.dart';
import 'ad_admin_panels.dart';
import 'ad_device_preview.dart';
import 'ad_slot.dart';
import 'social_links.dart';
import 'ad_stats_screen.dart';
import 'service_cards.dart';
import 'theme.dart';
import 'widgets.dart';

/// Uygulama sahibinin reklamları eklediği, düzenlediği ve yayınladığı ekran.
/// (Yalnızca sahibin cihazında açılır; metinler Türkçedir.)
class AdAdminScreen extends StatefulWidget {
  final int initialTab;

  /// Önizleme görüntüleri için hazır başvurular.
  final List<AdApplication>? previewApplications;
  final Set<String>? previewSeen;
  final Map<String, AdStats>? previewStats;
  const AdAdminScreen({super.key, this.initialTab = 0, this.previewApplications, this.previewSeen, this.previewStats});

  @override
  State<AdAdminScreen> createState() => _AdAdminScreenState();
}

class _AdAdminScreenState extends State<AdAdminScreen> {
  final _admin = AdAdmin.instance;
  bool _syncing = true;

  /// Toplu işlem için seçilen reklamlar (uzun basınca seçim başlar).
  final Set<String> _selected = {};
  bool get _selecting => _selected.isNotEmpty;

  void _toggleSelect(Ad a) => setState(() => _selected.contains(a.id) ? _selected.remove(a.id) : _selected.add(a.id));

  Future<void> _bulkDelete() async {
    final n = _selected.length;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('$n reklam silinsin mi?'),
        content: const Text('Seçilen reklamlar listeden kaldırılacak. Yayınlayınca kullanıcılarda da kaybolur.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Vazgeç')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Sil')),
        ],
      ),
    );
    if (ok != true) return;
    _admin.removeMany({..._selected});
    setState(_selected.clear);
    _refreshPreview();
  }

  void _bulkActive(bool on) {
    _admin.setActiveMany({..._selected}, on);
    if (mounted) toast(context, on ? '${_selected.length} reklam açıldı.' : '${_selected.length} reklam kapatıldı.');
    setState(_selected.clear);
    _refreshPreview();
  }

  void _bulkDraft(bool on) {
    for (final a in _admin.drafts.where((a) => _selected.contains(a.id)).toList()) {
      _admin.upsert(a.copyWith(draft: on));
    }
    setState(_selected.clear);
    _refreshPreview();
  }

  @override
  void initState() {
    super.initState();
    _admin.addListener(_changed);
    AdService.instance.addListener(_changed);
    _admin.syncFromPublished().whenComplete(() {
      if (mounted) setState(() => _syncing = false);
    });
  }

  @override
  void dispose() {
    _admin.removeListener(_changed);
    AdService.instance.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  bool get _previewOn => AdService.instance.preview != null;

  void _togglePreview(bool on) {
    AdService.instance.setPreview(on ? _admin.drafts : null, _admin.settings);
    toast(context, on ? 'Taslak reklamlar bu cihazda gösteriliyor (yalnızca sizde).' : 'Önizleme kapatıldı.');
  }

  void _refreshPreview() {
    if (_previewOn) {
      AdService.instance.setPreview(_admin.drafts, _admin.settings);
    }
  }

  Future<void> _edit([Ad? ad, AdPlacement? placement]) async {
    final out = await Navigator.of(context).push<Ad>(
      MaterialPageRoute(
        builder: (_) => AdEditScreen(ad: ad, placement: placement),
      ),
    );
    if (out != null) {
      _admin.upsert(out);
      _refreshPreview();
    }
  }

  Future<void> _publish() async {
    if (_admin.token.isEmpty) {
      await _tokenDialog();
      if (_admin.token.isEmpty || !mounted) return;
    }
    final status = ValueNotifier('Hazırlanıyor…');
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        content: Row(
          children: [
            const SizedBox.square(dimension: 26, child: CircularProgressIndicator(strokeWidth: 3)),
            const SizedBox(width: 18),
            Expanded(
              child: ValueListenableBuilder(valueListenable: status, builder: (_, v, _) => Text(v)),
            ),
          ],
        ),
      ),
    );
    final err = await _admin.publish(progress: (s) => status.value = s);
    if (!mounted) return;
    Navigator.of(context).pop();
    if (err == null) {
      _refreshPreview();
      showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          icon: const Icon(Icons.check_circle_rounded, color: NColors.emerald, size: 40),
          title: const Text('Reklamlar yayınlandı'),
          content: const Text(
            'Kullanıcılar uygulamayı bir sonraki açışlarında (en geç bir saat içinde) yeni reklamları görür. '
            'Netice Pro abonelerine reklam gösterilmez.',
          ),
          actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('Tamam'))],
        ),
      );
    } else {
      showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          icon: const Icon(Icons.error_outline_rounded, color: Colors.redAccent, size: 40),
          title: const Text('Yayınlanamadı'),
          content: Text(err),
          actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('Tamam'))],
        ),
      );
    }
  }

  Future<void> _tokenDialog() async {
    final c = TextEditingController(text: _admin.token);
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Yayın anahtarı'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Reklamlar GitHub deponuzdan tüm kullanıcılara dağıtılır. Bunun için bir kez anahtar oluşturun:\n\n'
                '1. Aşağıdaki düğmeyle GitHub sayfasını açın (hesabınıza giriş yapın).\n'
                '2. Token name: Netice reklam · Expiration: 1 yıl.\n'
                '3. Repository access: Only select repositories → emrgngr/netice.\n'
                '4. Permissions → Repository permissions → Contents: Read and write.\n'
                '5. Generate token\'a basın, çıkan anahtarı kopyalayıp buraya yapıştırın.\n\n'
                'Anahtar yalnızca bu cihazda saklanır; yedeklere ve başka kullanıcılara gitmez.',
                style: TextStyle(fontSize: 13.5),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                icon: const Icon(Icons.open_in_new_rounded),
                label: const Text('GitHub\'da anahtar oluştur'),
                onPressed: () => launchUrl(
                  Uri.parse('https://github.com/settings/personal-access-tokens/new'),
                  mode: LaunchMode.externalApplication,
                ),
              ),
              const SizedBox(height: 12),
              SecretField(controller: c, label: 'Anahtar (github_pat_…)'),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Vazgeç')),
          FilledButton(
            onPressed: () async {
              await _admin.setToken(c.text);
              final err = await _admin.checkToken();
              if (!ctx.mounted) return;
              if (err != null) {
                toast(ctx, err);
              } else {
                Navigator.pop(ctx);
                toast(ctx, 'Anahtar doğrulandı.');
              }
            },
            child: const Text('Kaydet'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final drafts = _admin.drafts;
    final newApps = _admin.newApplications;
    Tab tab(IconData icon, String label, {int badge = 0}) => Tab(
      height: 58,
      icon: Badge(
        isLabelVisible: badge > 0,
        label: Text('$badge'),
        backgroundColor: NColors.coral,
        child: Icon(icon, size: 22),
      ),
      child: FittedBox(child: Text(label)),
    );
    final tabs = TabBar(
      labelPadding: EdgeInsets.zero,
      labelStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5),
      unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12.5),
      tabs: [
        tab(Icons.campaign_outlined, 'Reklamlar'),
        tab(Icons.grid_view_rounded, 'Alanlar'),
        tab(Icons.bar_chart_rounded, 'İstatistik'),
        tab(Icons.mark_email_unread_outlined, 'Başvurular', badge: newApps),
        tab(Icons.tune_rounded, 'Ayarlar'),
      ],
    );
    return DefaultTabController(
      length: 5,
      initialIndex: widget.initialTab,
      child: Scaffold(
        appBar: _selecting
            ? AppBar(
                leading: IconButton(
                  tooltip: 'Seçimi kapat',
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => setState(_selected.clear),
                ),
                title: Text('${_selected.length} seçili'),
                actions: [
                  IconButton(
                    tooltip: 'Tümünü seç',
                    icon: const Icon(Icons.select_all_rounded),
                    onPressed: () => setState(() => _selected.addAll(drafts.map((a) => a.id))),
                  ),
                  IconButton(
                    tooltip: 'Aç',
                    icon: const Icon(Icons.visibility_rounded),
                    onPressed: () => _bulkActive(true),
                  ),
                  IconButton(
                    tooltip: 'Kapat',
                    icon: const Icon(Icons.visibility_off_rounded),
                    onPressed: () => _bulkActive(false),
                  ),
                  PopupMenuButton<String>(
                    onSelected: (v) => switch (v) {
                      'draft' => _bulkDraft(true),
                      'live' => _bulkDraft(false),
                      _ => _bulkDelete(),
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'draft', child: Text('Taslağa al')),
                      PopupMenuItem(value: 'live', child: Text('Taslaktan çıkar')),
                      PopupMenuItem(value: 'del', child: Text('Sil')),
                    ],
                  ),
                ],
                bottom: tabs,
              )
            : AppBar(
                titleSpacing: 8,
                title: const Row(
                  children: [
                    Icon(Icons.campaign_rounded, color: adPink),
                    SizedBox(width: 10),
                    Text('Reklam Yönetimi', style: TextStyle(fontWeight: FontWeight.w900)),
                  ],
                ),
                actions: [
                  if (_syncing)
                    const Padding(
                      padding: EdgeInsets.only(right: 16),
                      child: SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                    ),
                ],
                bottom: tabs,
              ),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Center(
              heightFactor: 1,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 828),
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                    backgroundColor: NColors.nightEmerald,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: _admin.dirty ? _publish : null,
                  icon: const Icon(Icons.campaign_rounded),
                  label: Text(_admin.dirty ? 'Değişiklikleri yayınla' : 'Her şey yayında'),
                ),
              ),
            ),
          ),
        ),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 860),
            child: TabBarView(
              children: [
                Builder(builder: _adsTab),
                AdPlacementsTab(onAdd: (p) => _edit(null, p)),
                AdStatsScreen(embedded: true, initial: widget.previewStats),
                AdApplicationsTab(initial: widget.previewApplications, initialSeen: widget.previewSeen),
                Builder(builder: _settingsTab),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------- Reklamlar

  Widget _adsTab(BuildContext context) {
    final drafts = _admin.drafts;
    final muted = Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6);
    final now = DateTime.now();
    final counts = {for (final s in AdStatus.values) s: drafts.where((a) => AdStatus.of(a, now) == s).length};
    final empty = [
      for (final p in AdPlacement.all)
        if (adsInPlacement(drafts, p, now: now).isEmpty) p,
    ];
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
      children: [
        FilledButton.icon(
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(50),
            backgroundColor: NColors.nightEmerald,
            foregroundColor: Colors.white,
          ),
          onPressed: () => _edit(),
          icon: const Icon(Icons.add_rounded),
          label: const Text('Yeni reklam ekle', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
        ),
        const SizedBox(height: 12),
        RoundedPanel(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    for (final s in AdStatus.values)
                      Expanded(
                        child: Container(
                          margin: const EdgeInsets.symmetric(horizontal: 3),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          decoration: BoxDecoration(
                            color: s.color.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Column(
                            children: [
                              Text(
                                '${counts[s]}',
                                style: TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w900,
                                  color: s == AdStatus.paused ? NColors.on(context, const Color(0xFFB7791F)) : s.color,
                                ),
                              ),
                              Text(s.label, style: TextStyle(color: muted, fontSize: 12)),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                Text(
                  'Boş alanlar: ${empty.length} / ${AdPlacement.all.length}',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 132,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: [
                      for (final p in empty.take(8))
                        Padding(
                          padding: const EdgeInsets.only(right: 12),
                          child: SizedBox(
                            width: 64,
                            child: Column(
                              children: [
                                AdPhoneMock(placement: p, width: 52, filled: false),
                                const SizedBox(height: 5),
                                Text(
                                  p.title.split(' · ').first.toUpperCase(),
                                  maxLines: 2,
                                  textAlign: TextAlign.center,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(color: muted, fontSize: 9.5, fontWeight: FontWeight.w700),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact),
                    onPressed: () => DefaultTabController.of(context).animateTo(1),
                    icon: const Icon(Icons.grid_view_rounded, size: 17),
                    label: const Text('Tüm alanları gör'),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (drafts.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 32),
            child: Column(
              children: [
                Icon(Icons.campaign_outlined, size: 56, color: muted),
                const SizedBox(height: 8),
                Text('Henüz reklam yok. "Yeni reklam ekle" ile başlayın.', style: TextStyle(color: muted)),
              ],
            ),
          ),
        if (drafts.length > 1 && !_selecting)
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 12, 4, 0),
            child: Text(
              'İpucu: Birden çok reklamı birlikte açıp kapatmak ya da silmek için birine uzun basın.',
              style: TextStyle(color: muted, fontSize: 12),
            ),
          ),
        for (final (i, a) in drafts.indexed) _adCard(context, i, a, now),
      ],
    );
  }

  Widget _adCard(BuildContext context, int i, Ad a, DateTime now) {
    final drafts = _admin.drafts;
    final muted = Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6);
    final status = AdStatus.of(a, now);
    final p = placementOf(a);
    final slots = AdPlacement.all.where((x) => x.format == a.format && (a.allPages || a.pages.contains(x.page))).length;
    final left = a.remaining(now);
    final chips = [
      if (a.cta.isNotEmpty) 'Düğme',
      if (a.code.isNotEmpty) 'Kod ${a.code}',
      if (a.countdown) 'Geri sayım',
      if (a.mediaDark.isNotEmpty) 'Gece görseli',
      if (a.hasAB) 'A/B',
      if (a.targeted) 'Hedefli',
      if (a.timeLimited) 'Saatli',
      if (a.dailyCap > 0) 'Günde ${a.dailyCap}',
      if (a.weight > 1) 'Öncelik ${a.weight}',
    ];
    return Card(
      margin: const EdgeInsets.only(top: 12),
      clipBehavior: Clip.antiAlias,
      color: _selected.contains(a.id) ? NColors.emerald.withValues(alpha: 0.14) : null,
      child: InkWell(
        onTap: () => _selecting ? _toggleSelect(a) : _edit(a),
        onLongPress: () => _toggleSelect(a),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 4, 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Column(
                    children: [
                      AdPhoneMock(placement: p, width: 58),
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: SizedBox(
                          width: 58,
                          height: a.format == AdFormat.card ? 33 : 12,
                          child: AdThumb(ad: a),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text.rich(
                          TextSpan(
                            children: [
                              TextSpan(
                                text: (a.allPages ? 'Tüm sayfalar' : a.pages.map((x) => x.label).join(', '))
                                    .toUpperCase(),
                                style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13.5),
                              ),
                              TextSpan(
                                text: ' · $slots alan',
                                style: TextStyle(color: muted, fontSize: 12),
                              ),
                            ],
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (a.name.isNotEmpty)
                          Text(
                            a.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        Text(
                          '${switch (a.type) {
                            AdType.video => 'Video',
                            AdType.slider => 'Slider · ${a.style.label} · ${a.seconds} sn · ${a.slides.length} görsel',
                            AdType.image => 'Sabit görsel',
                          }} · ${a.format == AdFormat.card ? 'Kart' : 'Şerit'}',
                          style: TextStyle(color: muted, fontSize: 12),
                        ),
                        if (a.start != null || a.end != null)
                          Text(
                            '${a.start == null ? '…' : dmy(a.start!)} → ${a.end == null ? '…' : dmy(a.end!)}',
                            style: TextStyle(color: muted, fontSize: 12),
                          ),
                        const SizedBox(height: 3),
                        Row(
                          children: [
                            Icon(Icons.circle, size: 9, color: status.color),
                            const SizedBox(width: 5),
                            Flexible(
                              child: Text(
                                [
                                  status.label,
                                  if (status == AdStatus.live && left != null && left > Duration.zero)
                                    left.inHours < 24
                                        ? '${left.inHours + 1} saat kaldı'
                                        : '${(left.inHours / 24).ceil()} gün kaldı',
                                  if (a.draft) 'taslak',
                                  if (a.isLocal) 'yayınlanmadı',
                                ].join(' · '),
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                  color: status == AdStatus.paused
                                      ? NColors.on(context, const Color(0xFFB7791F))
                                      : status.color,
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (a.link.isNotEmpty)
                          Text(
                            a.link,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: muted, fontSize: 11.5),
                          ),
                        if (chips.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Wrap(
                              spacing: 5,
                              runSpacing: 5,
                              children: [for (final c in chips) AdBadge(c, color: NColors.deepEmerald, solid: false)],
                            ),
                          ),
                        const SizedBox(height: 8),
                        ShowOnPageButton(placement: p),
                      ],
                    ),
                  ),
                ],
              ),
              const Divider(height: 18),
              Row(
                children: [
                  if (_selecting)
                    Checkbox(value: _selected.contains(a.id), onChanged: (_) => _toggleSelect(a))
                  else
                    Switch(
                      value: a.active,
                      onChanged: (v) {
                        _admin.upsert(a.copyWith(active: v));
                        _refreshPreview();
                      },
                    ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      a.active ? 'Yayında' : 'Durdu',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: muted),
                    ),
                  ),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact),
                    onPressed: () => _edit(a),
                    icon: const Icon(Icons.edit_outlined, size: 17),
                    label: const Text('Düzenle'),
                  ),
                  PopupMenuButton<String>(
                    onSelected: (v) async {
                      switch (v) {
                        case 'up':
                          _admin.move(i, i - 1);
                        case 'down':
                          _admin.move(i, i + 1);
                        case 'dup':
                          _admin.duplicate(a);
                          if (context.mounted) toast(context, 'Kopya taslak olarak eklendi.');
                        case 'preview':
                          await Navigator.of(context)
                              .push(MaterialPageRoute(builder: (_) => AdDevicePreviewScreen(ad: a)));
                        case 'select':
                          _toggleSelect(a);
                      }
                      _refreshPreview();
                    },
                    itemBuilder: (_) => [
                      if (i > 0) const PopupMenuItem(value: 'up', child: Text('Yukarı taşı')),
                      if (i < drafts.length - 1) const PopupMenuItem(value: 'down', child: Text('Aşağı taşı')),
                      const PopupMenuItem(value: 'dup', child: Text('Çoğalt')),
                      const PopupMenuItem(value: 'preview', child: Text('Cihazlarda önizle')),
                      const PopupMenuItem(value: 'select', child: Text('Seç (toplu işlem)')),
                    ],
                  ),
                  IconButton(
                    tooltip: 'Sil',
                    color: NColors.coral,
                    icon: const Icon(Icons.delete_outline_rounded),
                    onPressed: () => _deleteOne(a),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _deleteOne(Ad a) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reklam silinsin mi?'),
        content: Text('"${a.name}" listeden kaldırılacak. Yayınlayınca kullanıcılarda da kaybolur.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Vazgeç')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Sil')),
        ],
      ),
    );
    if (ok == true) {
      _admin.remove(a.id);
      _refreshPreview();
    }
  }

  // ------------------------------------------------------------ Ayarlar

  AdSettings _withSocial(AdSettings s, SocialNetwork n, String raw) {
    final m = Map<String, String>.of(s.social);
    final u = SocialNetwork.normalize(n, raw);
    if (u == null) {
      m.remove(n.key);
    } else {
      m[n.key] = u;
    }
    return s.copyWith(social: m);
  }

  void _setSettings(AdSettings s) {
    _admin.setSettings(s);
    _refreshPreview();
  }

  Widget _settingsTab(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6);
    final s = _admin.settings;
    TextStyle sub() => TextStyle(color: muted, fontSize: 12.5, height: 1.35);
    const bold = TextStyle(fontWeight: FontWeight.w800);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 120),
      children: [
        SectionTitle('Boş alanlar'),
        RoundedPanel(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('"Burada reklamınız olsun" kartı', style: bold),
                  subtitle: Text(
                    'Reklam girilmemiş alanlarda, reklam vermek isteyenlerin size başvurabileceği bir kart çıkar. '
                    'Başvurular "Başvurular" sekmesine düşer. Pro kullanıcılar görmez.',
                    style: sub(),
                  ),
                  value: s.emptySlotCard,
                  onChanged: (v) => _setSettings(s.copyWith(emptySlotCard: v)),
                ),
                const SizedBox(height: 6),
                const Text('Ne sıklıkla çıksın?', style: bold),
                const SizedBox(height: 2),
                Text('Aynı boş alan her açılışta değil, seçtiğiniz sıklıkla davet kartı gösterir.', style: sub()),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    for (final n in [1, 2, 3, 4, 5])
                      ChoiceChip(
                        label: Text(n == 1 ? 'Her seferinde' : '$n gösterimde 1'),
                        selected: s.emptyEvery == n,
                        onSelected: s.emptySlotCard ? (_) => _setSettings(s.copyWith(emptyEvery: n)) : null,
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                TextFormField(
                  key: ValueKey('wa-${s.whatsapp}'),
                  initialValue: s.whatsapp,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: 'WhatsApp numarası (isteğe bağlı)',
                    hintText: '905xxxxxxxxx',
                    prefixIcon: Icon(Icons.chat_rounded),
                    border: OutlineInputBorder(),
                  ),
                  onFieldSubmitted: (v) => _setSettings(s.copyWith(whatsapp: v.replaceAll(RegExp(r'[^0-9]'), ''))),
                  onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
                  onChanged: (v) {
                    final d = v.replaceAll(RegExp(r'[^0-9]'), '');
                    if (d != _admin.settings.whatsapp) _admin.setSettings(_admin.settings.copyWith(whatsapp: d));
                  },
                ),
                const SizedBox(height: 4),
                Text('Ülke koduyla yazın (ör. 90 532 …). Yazarsanız formda "WhatsApp" düğmesi de çıkar.', style: sub()),
                const SizedBox(height: 12),
                TextFormField(
                  key: ValueKey('mail-${s.contactEmail}'),
                  initialValue: s.contactEmail,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'İletişim e-postası',
                    prefixIcon: Icon(Icons.alternate_email_rounded),
                    border: OutlineInputBorder(),
                  ),
                  onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
                  onChanged: (v) {
                    final m = v.trim();
                    if (m.contains('@') && m != _admin.settings.contactEmail) {
                      _admin.setSettings(_admin.settings.copyWith(contactEmail: m));
                    }
                  },
                ),
                const SizedBox(height: 18),
                const Text('Sosyal medya hesapları', style: bold),
                const SizedBox(height: 2),
                Text('Kullanıcı adını ya da tam adresi yazın. Uygulamada Ayarlar\'ın en altında, '
                    'bilgisayar programında ve sitenin alt kısmında simge olarak çıkar. Boş bırakılan gösterilmez.',
                    style: sub()),
                const SizedBox(height: 8),
                for (final n in SocialNetwork.values) ...[
                  TextFormField(
                    key: ValueKey('sosyal-${n.key}-${s.social[n.key] ?? ''}'),
                    initialValue: s.social[n.key] ?? '',
                    keyboardType: TextInputType.url,
                    decoration: InputDecoration(
                      labelText: n.label,
                      hintText: n == SocialNetwork.youtube ? '@neticeoptik' : 'neticeoptik',
                      prefixIcon: Padding(padding: const EdgeInsets.all(10), child: SocialIcon(n, size: 24)),
                      border: const OutlineInputBorder(),
                      helperText: (s.social[n.key] ?? '').isEmpty ? null : s.social[n.key],
                    ),
                    onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
                    onFieldSubmitted: (v) => _setSettings(_withSocial(_admin.settings, n, v)),
                    onChanged: (v) {
                      final next = _withSocial(_admin.settings, n, v);
                      if (next.social[n.key] != _admin.settings.social[n.key]) _admin.setSettings(next);
                    },
                  ),
                  const SizedBox(height: 8),
                ],
                const SizedBox(height: 14),
                const Text('Önizleme', style: bold),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: AdEmptyCard(email: s.contactEmail, whatsapp: s.whatsapp),
                ),
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: AdEmptyCard(email: s.contactEmail, whatsapp: s.whatsapp, banner: true),
                ),
              ],
            ),
          ),
        ),
        SectionTitle('Uygulamadaki öneriler'),
        RoundedPanel(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Ürün öneri kartı (SepetMix ürünleri)', style: bold),
              subtitle: Text(
                'Ana sayfadaki "Önerilen" ürün kartı. Kapatıp "Değişiklikleri yayınla"ya basarsanız '
                'tüm kullanıcılarda kaybolur.',
                style: sub(),
              ),
              value: s.promoCard,
              onChanged: (v) => _setSettings(s.copyWith(promoCard: v)),
            ),
          ),
        ),
        SectionTitle('Sayaç ve önizleme'),
        RoundedPanel(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Column(
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Görülme ve tıklama sayacı', style: bold),
                  subtitle: Text(
                    'Her reklamın günlük toplam görülme ve tıklama sayısı kimliksiz olarak sayılır; '
                    'kimin gördüğü bilinmez. Kapatırsanız yeni sayım yapılmaz.',
                    style: sub(),
                  ),
                  value: s.stats,
                  onChanged: (v) => _admin.setSettings(s.copyWith(stats: v)),
                ),
                const Divider(height: 1),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Taslağı bu cihazda önizle', style: bold),
                  subtitle: Text('Yayınlamadan önce sayfalarda nasıl durduğunu yalnız siz görürsünüz.', style: sub()),
                  value: _previewOn,
                  onChanged: _togglePreview,
                ),
              ],
            ),
          ),
        ),
        SectionTitle('Yayın'),
        RoundedPanel(
          child: Column(
            children: [
              ListTile(
                leading: Icon(
                  _admin.token.isEmpty ? Icons.key_off_rounded : Icons.key_rounded,
                  color: _admin.token.isEmpty ? NColors.amber : NColors.deepEmerald,
                ),
                title: const Text('Yayın anahtarı', style: bold),
                subtitle: Text(
                  _admin.token.isEmpty
                      ? 'Girilmedi. Yayınlamak ve istatistik/başvuruları görmek için gerekir.'
                      : _admin.lastPublish == null
                      ? 'Kayıtlı'
                      : 'Kayıtlı · son yayın ${dmy(_admin.lastPublish!)} ${hm(_admin.lastPublish!)}',
                  style: sub(),
                ),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: _tokenDialog,
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.cloud_download_outlined),
                title: const Text('Yayındakini geri yükle', style: bold),
                subtitle: Text('Bu cihazdaki taslakları silip yayındaki listeyi getirir.', style: sub()),
                onTap: () async {
                  final ok = await _admin.syncFromPublished(overwrite: true);
                  if (!context.mounted) return;
                  toast(context, ok ? 'Yayındaki liste yüklendi.' : 'Liste alınamadı (internet?).');
                },
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.help_outline_rounded),
                title: const Text('Nasıl çalışır?', style: bold),
                subtitle: Text(
                  'Kart: sayfa içinde büyük kutu (1280×720). Şerit: sayfanın altında ince bant (1200×240). '
                  '"Değişiklikleri yayınla"ya basınca tüm kullanıcılar en geç bir saat içinde görür. '
                  'Pro abonelere reklam gösterilmez; kamera ile okuma ve kâğıt kontrol ekranlarında reklam yoktur.',
                  style: sub(),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Listede küçük önizleme.
class AdThumb extends StatelessWidget {
  final Ad ad;
  const AdThumb({super.key, required this.ad});

  @override
  Widget build(BuildContext context) {
    final fg = NColors.on(context, NColors.ink);
    Widget icon(IconData i) => Container(
      color: fg.withValues(alpha: 0.08),
      child: Center(child: Icon(i, color: fg.withValues(alpha: 0.6))),
    );
    if (ad.type == AdType.video) return icon(Icons.play_circle_outline_rounded);
    final f = AdService.instance.fileFor(ad);
    if (f != null && f.existsSync()) {
      return Image.file(f, fit: BoxFit.cover, errorBuilder: (_, _, _) => icon(Icons.broken_image_outlined));
    }
    if (!ad.isLocal) {
      return Image.network(ad.media, fit: BoxFit.cover, errorBuilder: (_, _, _) => icon(Icons.image_outlined));
    }
    return icon(Icons.image_outlined);
  }
}

/// Reklamı yapılan kendi siteleri (hazır bağlantı düğmeleri).
const _ownSites = ['www.neticeoptik.com', 'www.sepetmix.com', 'www.cooktatlihayat.com', 'www.amare.com'];

/// Tek reklamı ekleme/düzenleme.
class AdEditScreen extends StatefulWidget {
  final Ad? ad;

  /// "Alanlar"dan "Reklam ekle": biçim ve sayfa bu alana göre seçili gelir.
  final AdPlacement? placement;
  const AdEditScreen({super.key, this.ad, this.placement});

  @override
  State<AdEditScreen> createState() => _AdEditScreenState();
}

class _AdEditScreenState extends State<AdEditScreen> {
  late final String _id = widget.ad?.id ?? AdAdmin.newId();
  late final _name = TextEditingController(text: widget.ad?.name ?? '');
  late final _link = TextEditingController(text: widget.ad?.link ?? '');
  late final _url = TextEditingController(text: (widget.ad?.isLocal ?? true) ? '' : widget.ad!.media);
  late String? _media = widget.ad?.media;
  late AdType _type = widget.ad?.type ?? AdType.image;
  late AdFormat _format = widget.ad?.format ?? widget.placement?.format ?? AdFormat.card;
  late Set<AdPage> _pages = {...?widget.ad?.pages, if (widget.placement != null) widget.placement!.page};
  late bool _active = widget.ad?.active ?? true;
  late DateTime? _start = widget.ad?.start;
  late DateTime? _end = widget.ad?.end;
  late int _seconds = widget.ad?.seconds ?? 8;
  late List<String> _slides = [...?widget.ad?.slides];
  late SlideStyle _style = widget.ad?.style ?? SlideStyle.slide;
  late final _cta = TextEditingController(text: widget.ad?.cta ?? '');
  late final _code = TextEditingController(text: widget.ad?.code ?? '');
  late bool _countdown = widget.ad?.countdown ?? false;
  late String _mediaDark = widget.ad?.mediaDark ?? '';
  late String _mediaB = widget.ad?.mediaB ?? '';
  late final Set<String> _langs = {...?widget.ad?.languages};
  late final _countries = TextEditingController(text: widget.ad?.countries.join(', ') ?? '');
  late final Set<String> _insts = {...?widget.ad?.institutions};
  late int _dailyCap = widget.ad?.dailyCap ?? 0;
  late int _weight = widget.ad?.weight ?? 1;
  late RangeValues _hours = RangeValues((widget.ad?.hourFrom ?? 0).toDouble(), (widget.ad?.hourTo ?? 24).toDouble());
  late final Set<int> _weekdays = {...?widget.ad?.weekdays};
  late bool _draft = widget.ad?.draft ?? false;
  bool _loading = false;

  static const _ctaIdeas = ['Hemen al', 'İncele', 'Sipariş ver', 'İndir', 'Fırsatı yakala'];
  static const _dayNames = ['Pzt', 'Sal', 'Çar', 'Per', 'Cum', 'Cmt', 'Paz'];
  static const _instNames = {
    'school': 'Okul',
    'university': 'Üniversite / MYO',
    'police': 'Polis eğitimi',
    'military': 'Askerî okul',
    'course': 'Kurs / dershane',
    'other': 'Diğer kurum',
  };

  static final _whiteOnGreen = FilledButton.styleFrom(
    backgroundColor: NColors.nightEmerald,
    foregroundColor: Colors.white,
  );

  /// Gece görseli ya da A/B için ikinci görsel.
  Future<void> _pickExtra(bool dark) async {
    final files = await FilePicker.pickFiles(
      dialogTitle: dark ? 'Gece modu görseli seçin' : 'İkinci (B) görseli seçin',
      type: FileType.custom,
      allowedExtensions: ['jpg', 'jpeg', 'png', 'webp', 'gif'],
    );
    if (files.isEmpty) return;
    try {
      final f = files.first;
      final bytes = await f.readAsBytes();
      if (bytes.length > AdAdmin.maxImageBytes) {
        if (mounted) toast(context, 'Görsel en çok ${AdAdmin.maxImageBytes ~/ 1048576} MB olabilir.');
        return;
      }
      final path = await AdAdmin.instance.importBytes(bytes, f.name, '$_id${dark ? 'g' : 'b'}');
      setState(() => dark ? _mediaDark = path : _mediaB = path);
    } catch (e) {
      if (mounted) toast(context, 'Dosya okunamadı: $e');
    }
  }

  Widget _extraImage({required bool dark, required Color muted}) {
    final src = dark ? _mediaDark : _mediaB;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: 112,
                height: _format == AdFormat.card ? 63 : 22.4,
                child: src.isEmpty
                    ? Container(
                        color: (dark ? NColors.darkBg : NColors.ink.withValues(alpha: 0.06)),
                        child: Icon(
                          dark ? Icons.dark_mode_outlined : Icons.filter_2_outlined,
                          color: dark ? Colors.white70 : muted,
                          size: 20,
                        ),
                      )
                    : _srcImage(src),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    dark ? 'Gece modu görseli' : 'A/B testi: ikinci görsel',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  Text(
                    dark
                        ? 'Telefon gece modundayken bu görsel çıkar (koyu zeminli tasarım).'
                        : 'Kullanıcılar sırayla A ve B görselini görür; hangisinin işe yaradığını karşılaştırın.',
                    style: TextStyle(color: muted, fontSize: 12),
                  ),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 6,
                    children: [
                      OutlinedButton(
                        onPressed: () => _pickExtra(dark),
                        child: Text(src.isEmpty ? 'Görsel seç' : 'Değiştir'),
                      ),
                      if (src.isNotEmpty)
                        TextButton(
                          onPressed: () => setState(() => dark ? _mediaDark = '' : _mediaB = ''),
                          child: const Text('Kaldır'),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _devicePreview() async {
    final ad = _build();
    if (ad == null) return;
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => AdDevicePreviewScreen(ad: ad)));
  }

  static const maxSlides = 10;

  void _setType(AdType t) => setState(() {
    if (t == AdType.slider && _type != AdType.slider) {
      _seconds = 3;
      if (_slides.isEmpty && _media != null && _type == AdType.image) _slides = [_media!];
    } else if (t != AdType.slider && _type == AdType.slider) {
      _seconds = 8;
    }
    _type = t;
  });

  /// Slider'a birden çok görsel ekler.
  Future<void> _addSlides() async {
    final files = await FilePicker.pickFiles(
      dialogTitle: 'Slider görsellerini seçin (birden çok seçebilirsiniz)',
      type: FileType.custom,
      allowedExtensions: ['jpg', 'jpeg', 'png', 'webp'],
    );
    if (files.isEmpty) return;
    setState(() => _loading = true);
    try {
      for (final f in files) {
        if (_slides.length >= maxSlides) {
          if (mounted) toast(context, 'Bir slider\'da en çok $maxSlides görsel olabilir.');
          break;
        }
        final bytes = await f.readAsBytes();
        if (bytes.length > AdAdmin.maxImageBytes) {
          if (mounted) toast(context, '${f.name} çok büyük (en çok 5 MB).');
          continue;
        }
        final path = await AdAdmin.instance.importBytes(bytes, f.name, '${_id}_s');
        _slides = [..._slides, path];
        if (_name.text.trim().isEmpty) {
          _name.text = f.name.contains('.') ? f.name.substring(0, f.name.lastIndexOf('.')) : f.name;
        }
      }
    } catch (e) {
      if (mounted) toast(context, 'Dosya okunamadı: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Widget _srcImage(String src) {
    final f = AdService.instance.fileOf(src);
    if (f != null && f.existsSync()) return Image.file(f, fit: BoxFit.cover);
    if (!Ad.isLocalPath(src)) return Image.network(src, fit: BoxFit.cover, errorBuilder: (_, _, _) => const SizedBox());
    return Container(color: NColors.ink.withValues(alpha: 0.08));
  }

  /// Geçiş örneği için renkli örnek kareler (görsel yokken).
  static List<Widget> get _demoItems => [
    for (final (i, c) in [(1, NColors.emerald), (2, NColors.amber), (3, NColors.ink)])
      Container(
        decoration: BoxDecoration(gradient: LinearGradient(colors: [c, Color.lerp(c, Colors.white, 0.35)!])),
        alignment: Alignment.center,
        child: Text(
          '$i',
          style: const TextStyle(color: Colors.white, fontSize: 30, fontWeight: FontWeight.w800),
        ),
      ),
  ];

  List<Widget> get _sliderItems => _slides.length >= 2 ? [for (final s in _slides) _srcImage(s)] : _demoItems;

  Widget _sliderEditor(Color muted) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      ClipRRect(
        borderRadius: BorderRadius.circular(_format == AdFormat.card ? 18 : 10),
        child: AspectRatio(
          aspectRatio: _format == AdFormat.card ? 16 / 9 : 5,
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : AdSlider(
                  key: ValueKey('onizleme/${_style.key}/$_seconds/${_slides.length}'),
                  items: _sliderItems,
                  style: _style,
                  seconds: _seconds,
                ),
        ),
      ),
      const SizedBox(height: 6),
      Text(
        _slides.length < 2
            ? 'En az 2 görsel ekleyin (en çok $maxSlides). Görseller seçtiğiniz sırayla, $_seconds saniyede bir değişir.'
            : '${_slides.length} görsel · $_seconds saniyede bir değişir',
        style: TextStyle(color: muted, fontSize: 12),
      ),
      const SizedBox(height: 10),
      SizedBox(
        height: 74,
        child: ListView(
          scrollDirection: Axis.horizontal,
          children: [
            for (final (i, src) in _slides.indexed)
              Padding(
                padding: const EdgeInsetsDirectional.only(end: 8),
                child: Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: SizedBox(width: 110, height: 74, child: _srcImage(src)),
                    ),
                    PositionedDirectional(
                      start: 4,
                      top: 4,
                      child: CircleAvatar(
                        radius: 10,
                        backgroundColor: Colors.black54,
                        child: Text(
                          '${i + 1}',
                          style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                    PositionedDirectional(
                      end: 2,
                      top: 2,
                      child: InkResponse(
                        onTap: () => setState(() => _slides = [..._slides]..removeAt(i)),
                        child: const CircleAvatar(
                          radius: 11,
                          backgroundColor: Colors.black54,
                          child: Icon(Icons.close_rounded, size: 14, color: Colors.white),
                        ),
                      ),
                    ),
                    if (i > 0)
                      PositionedDirectional(
                        start: 2,
                        bottom: 2,
                        child: InkResponse(
                          onTap: () => setState(() {
                            final l = [..._slides];
                            final x = l.removeAt(i);
                            l.insert(i - 1, x);
                            _slides = l;
                          }),
                          child: const CircleAvatar(
                            radius: 11,
                            backgroundColor: Colors.black54,
                            child: Icon(Icons.arrow_back_rounded, size: 14, color: Colors.white),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            if (_slides.length < maxSlides)
              InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: _loading ? null : _addSlides,
                child: Ink(
                  width: 110,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: muted.withValues(alpha: 0.4)),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.add_photo_alternate_outlined, color: muted),
                      const SizedBox(height: 4),
                      Text(
                        'Görsel ekle',
                        style: TextStyle(color: muted, fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
      const SizedBox(height: 14),
      const Text('Geçiş çeşidi', style: TextStyle(fontWeight: FontWeight.w700)),
      const SizedBox(height: 8),
      LayoutBuilder(
        builder: (context, c) {
          final w = ((c.maxWidth - 16) / 3).clamp(96.0, 160.0);
          return Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final st in SlideStyle.values)
                InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => setState(() => _style = st),
                  child: Container(
                    width: w,
                    padding: const EdgeInsets.all(5),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      color: st == _style ? NColors.emerald.withValues(alpha: 0.12) : null,
                      border: Border.all(
                        color: st == _style ? NColors.emerald : muted.withValues(alpha: 0.3),
                        width: st == _style ? 2 : 1,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: AspectRatio(
                            aspectRatio: 16 / 9,
                            child: AdSlider(
                              key: ValueKey('ornek/${st.key}'),
                              items: _demoItems,
                              style: st,
                              seconds: 2,
                              dots: false,
                            ),
                          ),
                        ),
                        const SizedBox(height: 5),
                        Row(
                          children: [
                            if (st == _style) const Icon(Icons.check_circle_rounded, size: 15, color: NColors.emerald),
                            if (st == _style) const SizedBox(width: 3),
                            Expanded(
                              child: Text(
                                st.label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          );
        },
      ),
      const SizedBox(height: 6),
      Text(_style.detail, style: TextStyle(color: muted, fontSize: 12)),
      const SizedBox(height: 10),
      Text('Her görsel $_seconds saniye kalsın', style: const TextStyle(fontWeight: FontWeight.w700)),
      Slider(
        value: _seconds.toDouble().clamp(2, 10),
        min: 2,
        max: 10,
        divisions: 8,
        label: '$_seconds sn',
        onChanged: (v) => setState(() => _seconds = v.round()),
      ),
    ],
  );

  Future<void> _pick(AdType type) async {
    final exts = type == AdType.video ? ['mp4', 'mov', 'm4v'] : ['jpg', 'jpeg', 'png', 'webp', 'gif'];
    final files = await FilePicker.pickFiles(
      dialogTitle: type == AdType.video ? 'Reklam videosu seçin' : 'Reklam görseli seçin',
      type: FileType.custom,
      allowedExtensions: exts,
    );
    if (files.isEmpty) return;
    setState(() => _loading = true);
    try {
      final f = files.first;
      final bytes = await f.readAsBytes();
      final limit = type == AdType.video ? AdAdmin.maxVideoBytes : AdAdmin.maxImageBytes;
      if (bytes.length > limit) {
        if (mounted) {
          toast(
            context,
            'Dosya çok büyük (${(bytes.length / 1048576).toStringAsFixed(1)} MB). En çok ${limit ~/ 1048576} MB olabilir.',
          );
        }
        return;
      }
      final path = await AdAdmin.instance.importBytes(bytes, f.name, _id);
      setState(() {
        _media = path;
        _type = type;
        _url.clear();
        if (_name.text.trim().isEmpty) {
          final n = f.name.contains('.') ? f.name.substring(0, f.name.lastIndexOf('.')) : f.name;
          _name.text = n;
        }
      });
    } catch (e) {
      if (mounted) toast(context, 'Dosya okunamadı: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pickDate(bool start) async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: (start ? _start : _end) ?? now,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 5),
    );
    if (d != null) setState(() => start ? _start = d : _end = d);
  }

  void _save() {
    final ad = _build();
    if (ad != null) Navigator.of(context).pop(ad);
  }

  /// Formdaki reklam; eksik varsa uyarıp null döner.
  Ad? _build() {
    if (_type == AdType.slider) {
      if (_slides.length < 2) {
        toast(context, 'Slider için en az 2 görsel ekleyin.');
        return null;
      }
      _media = _slides.first;
      _url.clear();
    }
    final url = _url.text.trim();
    String? media = _media;
    var type = _type;
    if (url.isNotEmpty) {
      if (!url.startsWith('https://')) {
        toast(context, 'Dosya adresi https:// ile başlamalı.');
        return null;
      }
      media = url;
      type = Ad.isVideoPath(url) ? AdType.video : AdType.image;
    }
    if (media == null || media.isEmpty) {
      toast(context, 'Önce bir görsel ya da video seçin.');
      return null;
    }
    final link = _link.text.trim();
    if (link.isNotEmpty && !link.startsWith('http')) {
      toast(context, 'Bağlantı http:// ya da https:// ile başlamalı.');
      return null;
    }
    if (_start != null && _end != null && _end!.isBefore(_start!)) {
      toast(context, 'Bitiş tarihi başlangıçtan önce olamaz.');
      return null;
    }
    final countries = _countries.text
        .split(RegExp(r'[,;\s]+'))
        .map((c) => c.trim().toUpperCase())
        .where((c) => RegExp(r'^[A-Z]{2}$').hasMatch(c))
        .toSet()
        .toList();
    final cta = _cta.text.trim();
    if (cta.length > 24) {
      toast(context, 'Düğme yazısı en çok 24 harf olsun.');
      return null;
    }
    final img = type == AdType.image;
    return Ad(
      id: _id,
      name: _name.text.trim(),
      type: type,
      media: media,
      link: link,
      format: _format,
      pages: AdPage.values.where(_pages.contains).toList(),
      active: _active,
      start: _start,
      end: _end,
      seconds: _seconds,
      slides: type == AdType.slider ? _slides : const [],
      style: _style,
      cta: cta,
      code: _code.text.trim().toUpperCase(),
      countdown: _countdown && _end != null,
      mediaDark: img ? _mediaDark : '',
      mediaB: img ? _mediaB : '',
      languages: AppLanguage.all.map((l) => l.code).where(_langs.contains).toList(),
      countries: countries,
      institutions: _instNames.keys.where(_insts.contains).toList(),
      dailyCap: _dailyCap,
      weight: _weight,
      hourFrom: _hours.start.round(),
      hourTo: _hours.end.round(),
      weekdays: [
        for (var d = 1; d <= 7; d++)
          if (_weekdays.contains(d)) d,
      ],
      draft: _draft,
    );
  }

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6);
    final preview = _media == null || _type == AdType.slider || (Ad.isVideoPath(_media!) != (_type == AdType.video))
        ? null
        : Ad(id: _id, type: _type, media: _media!, format: _format);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.ad == null ? 'Yeni reklam' : 'Reklamı düzenle'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: FilledButton(style: _whiteOnGreen, onPressed: _loading ? null : _save, child: const Text('Kaydet')),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
        children: [
          SectionTitle('1. Reklam türü'),
          SegmentedButton<AdType>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: AdType.image, icon: Icon(Icons.image_outlined), label: Text('Sabit')),
              ButtonSegment(value: AdType.slider, icon: Icon(Icons.view_carousel_outlined), label: Text('Slider')),
              ButtonSegment(value: AdType.video, icon: Icon(Icons.movie_outlined), label: Text('Video')),
            ],
            selected: {_type},
            onSelectionChanged: (s) => _setType(s.first),
          ),
          const SizedBox(height: 6),
          Text(switch (_type) {
            AdType.image => 'Tek görsel, sabit durur.',
            AdType.slider => 'Birden çok görsel, seçtiğiniz geçişle sırayla değişir.',
            AdType.video => 'Sessiz başlayan video; kullanıcı isterse sesi açar.',
          }, style: TextStyle(color: muted, fontSize: 12)),
          const SizedBox(height: 12),
          if (_type == AdType.slider)
            _sliderEditor(muted)
          else ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(_format == AdFormat.card ? 18 : 10),
              child: AspectRatio(
                aspectRatio: _format == AdFormat.card ? 16 / 9 : 5,
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : preview == null
                    ? Container(
                        color: NColors.ink.withValues(alpha: 0.06),
                        child: Center(
                          child: Text('Henüz dosya seçilmedi', style: TextStyle(color: muted)),
                        ),
                      )
                    : AdThumb(ad: preview),
              ),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: _loading ? null : () => _pick(_type),
              icon: Icon(_type == AdType.video ? Icons.movie_outlined : Icons.image_outlined),
              label: Text(_type == AdType.video ? 'Video seç' : 'Görsel seç'),
            ),
            const SizedBox(height: 6),
            Text(
              'Görsel en çok 5 MB (JPG/PNG), video en çok 40 MB (MP4, kısa ve sessiz izlenebilir olmalı; '
              'ses kullanıcı açarsa çalar).',
              style: TextStyle(color: muted, fontSize: 12),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _url,
              decoration: const InputDecoration(
                labelText: 'ya da dosya adresi (isteğe bağlı)',
                hintText: 'https://…/reklam.jpg veya .mp4',
                border: OutlineInputBorder(),
              ),
            ),
            if (_type == AdType.image) ...[
              const SizedBox(height: 12),
              _extraImage(dark: true, muted: muted),
              _extraImage(dark: false, muted: muted),
            ],
          ],
          SectionTitle('2. Bilgiler'),
          TextField(
            controller: _name,
            decoration: const InputDecoration(
              labelText: 'Reklam / firma adı (yalnızca siz görürsünüz)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _link,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(
              labelText: 'Dokununca açılacak adres (isteğe bağlı)',
              hintText: 'https://www.ornek.com/kampanya',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final site in _ownSites)
                ActionChip(
                  avatar: const Icon(Icons.storefront_outlined, size: 18),
                  label: Text(site),
                  onPressed: () => setState(() {
                    _link.text = 'https://$site/';
                    _link.selection = TextSelection.collapsed(offset: _link.text.length);
                  }),
                ),
            ],
          ),
          Text(
            'Kendi siteleriniz için düğmeye dokunup ürün sayfasının adresini tamamlayın. Başka bir firmanın reklamı için '
            'o firmanın adresini yukarıdaki kutuya yazın ya da yapıştırın.',
            style: TextStyle(color: muted, fontSize: 12),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _cta,
            maxLength: 24,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              labelText: 'Görsel üstünde düğme (isteğe bağlı)',
              hintText: 'Örn. Hemen al',
              border: OutlineInputBorder(),
            ),
          ),
          Wrap(
            spacing: 6,
            runSpacing: 2,
            children: [
              for (final c in _ctaIdeas) ActionChip(label: Text(c), onPressed: () => setState(() => _cta.text = c)),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _code,
            textCapitalization: TextCapitalization.characters,
            maxLength: 20,
            decoration: const InputDecoration(
              labelText: 'İndirim kodu (isteğe bağlı)',
              hintText: 'Örn. NETICE15',
              helperText: 'Görselin üstünde çıkar; kullanıcı dokununca kod kopyalanır.',
              border: OutlineInputBorder(),
            ),
          ),
          SectionTitle('3. Biçim'),
          SegmentedButton<AdFormat>(
            segments: const [
              ButtonSegment(value: AdFormat.card, icon: Icon(Icons.crop_16_9_rounded), label: Text('Kart (1280×720)')),
              ButtonSegment(
                value: AdFormat.banner,
                icon: Icon(Icons.view_stream_rounded),
                label: Text('Şerit (1200×240)'),
              ),
            ],
            selected: {_format},
            onSelectionChanged: (s) => setState(() => _format = s.first),
          ),
          const SizedBox(height: 6),
          Text(
            _format == AdFormat.card
                ? 'Kart sayfanın içinde, içeriklerin arasında görünür.'
                : 'Şerit sayfanın en altında, menünün üstünde ince bir bant olarak görünür.',
            style: TextStyle(color: muted, fontSize: 12),
          ),
          SectionTitle('4. Sayfalar'),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              FilterChip(
                label: const Text('Tüm sayfalar'),
                selected: _pages.isEmpty,
                onSelected: (_) => setState(() => _pages = {}),
              ),
              for (final p in AdPage.values)
                FilterChip(
                  label: Text(p.label),
                  selected: _pages.contains(p),
                  onSelected: (v) => setState(() => v ? _pages.add(p) : _pages.remove(p)),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Reklamınız burada çıkar',
            style: TextStyle(color: muted, fontSize: 12.5, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 140,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (final p in AdPlacement.all.where(
                  (p) => p.format == _format && (_pages.isEmpty || _pages.contains(p.page)),
                ))
                  Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: SizedBox(
                      width: 70,
                      child: Column(
                        children: [
                          AdPhoneMock(placement: p, width: 54),
                          const SizedBox(height: 5),
                          Text(
                            '${p.no} · ${p.title.split(' · ').first}',
                            maxLines: 2,
                            textAlign: TextAlign.center,
                            style: TextStyle(color: muted, fontSize: 10, fontWeight: FontWeight.w700),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          SectionTitle('5. Yayın tarihi ve saatleri'),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _pickDate(true),
                  icon: const Icon(Icons.event_outlined),
                  label: Text(_start == null ? 'Başlangıç: hemen' : 'Başlangıç: ${dmy(_start!)}'),
                ),
              ),
              if (_start != null)
                IconButton(onPressed: () => setState(() => _start = null), icon: const Icon(Icons.close_rounded)),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _pickDate(false),
                  icon: const Icon(Icons.event_busy_outlined),
                  label: Text(_end == null ? 'Bitiş: süresiz' : 'Bitiş: ${dmy(_end!)}'),
                ),
              ),
              if (_end != null)
                IconButton(onPressed: () => setState(() => _end = null), icon: const Icon(Icons.close_rounded)),
            ],
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Geri sayım rozeti', style: TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text(
              _end == null
                  ? 'Önce bitiş tarihi seçin. Son 7 günde "Bitmesine 3 gün" gibi kırmızı rozet çıkar.'
                  : 'Son 7 günde görselin köşesinde "Bitmesine 3 gün", son gün "Bitmesine 5 saat" yazar.',
            ),
            value: _countdown && _end != null,
            onChanged: _end == null ? null : (v) => setState(() => _countdown = v),
          ),
          const SizedBox(height: 4),
          Text(
            'Haftanın günleri',
            style: TextStyle(fontWeight: FontWeight.w700, color: muted),
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              FilterChip(
                label: const Text('Her gün'),
                selected: _weekdays.isEmpty,
                onSelected: (_) => setState(_weekdays.clear),
              ),
              for (var d = 1; d <= 7; d++)
                FilterChip(
                  label: Text(_dayNames[d - 1]),
                  selected: _weekdays.contains(d),
                  onSelected: (v) => setState(() => v ? _weekdays.add(d) : _weekdays.remove(d)),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            _hours.start == 0 && _hours.end == 24
                ? 'Saat: gün boyu'
                : 'Saat: ${_hours.start.round().toString().padLeft(2, '0')}:00 – ${_hours.end.round().toString().padLeft(2, '0')}:00 arası',
            style: TextStyle(fontWeight: FontWeight.w700, color: muted),
          ),
          RangeSlider(
            values: _hours,
            min: 0,
            max: 24,
            divisions: 24,
            labels: RangeLabels('${_hours.start.round()}:00', '${_hours.end.round()}:00'),
            onChanged: (v) {
              if (v.end - v.start >= 1) setState(() => _hours = v);
            },
          ),
          Text(
            'Örn. okul saatleri için 08:00 – 17:00. Saat, kullanıcının telefonundaki saattir.',
            style: TextStyle(color: muted, fontSize: 12),
          ),
          SectionTitle('6. Hedef kitle'),
          Text('Hiçbiri seçilmezse herkes görür.', style: TextStyle(color: muted, fontSize: 12.5)),
          const SizedBox(height: 8),
          Text(
            'Uygulama dili',
            style: TextStyle(fontWeight: FontWeight.w700, color: muted),
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              for (final l in AppLanguage.all)
                FilterChip(
                  label: Text('${l.flag} ${l.name}'),
                  selected: _langs.contains(l.code),
                  onSelected: (v) => setState(() => v ? _langs.add(l.code) : _langs.remove(l.code)),
                ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _countries,
            textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(
              labelText: 'Ülkeler (isteğe bağlı)',
              hintText: 'TR, AZ, DE',
              helperText: 'İki harfli ülke kodlarını virgülle yazın. Boşsa tüm ülkeler.',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Kurum türü',
            style: TextStyle(fontWeight: FontWeight.w700, color: muted),
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              for (final e in _instNames.entries)
                FilterChip(
                  label: Text(e.value),
                  selected: _insts.contains(e.key),
                  onSelected: (v) => setState(() => v ? _insts.add(e.key) : _insts.remove(e.key)),
                ),
            ],
          ),
          SectionTitle('7. Sıklık ve öncelik'),
          Text(
            _dailyCap == 0 ? 'Günlük sınır: yok' : 'Bir kullanıcı günde en çok $_dailyCap kez görür',
            style: TextStyle(fontWeight: FontWeight.w700, color: muted),
          ),
          Slider(
            value: _dailyCap.toDouble(),
            min: 0,
            max: 20,
            divisions: 20,
            label: _dailyCap == 0 ? 'Sınırsız' : '$_dailyCap',
            onChanged: (v) => setState(() => _dailyCap = v.round()),
          ),
          Text(
            'Öncelik (sık görünme)',
            style: TextStyle(fontWeight: FontWeight.w700, color: muted),
          ),
          const SizedBox(height: 6),
          SegmentedButton<int>(
            showSelectedIcon: false,
            segments: [for (var w = 1; w <= 5; w++) ButtonSegment(value: w, label: Text('$w'))],
            selected: {_weight},
            onSelectionChanged: (v) => setState(() => _weight = v.first),
          ),
          const SizedBox(height: 4),
          Text(
            'Aynı alanda birden çok reklam varsa öncelik 3 olan, 1 olana göre 3 kat sık çıkar.',
            style: TextStyle(color: muted, fontSize: 12),
          ),
          if (_type == AdType.image) ...[
            const SizedBox(height: 12),
            Text(
              'Birden çok reklam varsa bu görsel $_seconds saniye görünür',
              style: TextStyle(color: muted, fontSize: 12.5),
            ),
            Slider(
              value: _seconds.toDouble(),
              min: 3,
              max: 30,
              divisions: 27,
              label: '$_seconds sn',
              onChanged: (v) => setState(() => _seconds = v.round()),
            ),
          ],
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Yayında', style: TextStyle(fontWeight: FontWeight.w700)),
            subtitle: const Text('Kapalıysa listede kalır ama gösterilmez'),
            value: _active,
            onChanged: (v) => setState(() => _active = v),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Taslak', style: TextStyle(fontWeight: FontWeight.w700)),
            subtitle: const Text('Yalnızca sizde kalır, "yayınla"ya bassanız da kullanıcılara gitmez'),
            value: _draft,
            onChanged: (v) => setState(() => _draft = v),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            onPressed: _loading ? null : _devicePreview,
            icon: const Icon(Icons.devices_rounded),
            label: const Text('Telefon, tablet ve bilgisayarda önizle'),
          ),
          const SizedBox(height: 10),
          FilledButton.icon(
            style: _whiteOnGreen.merge(FilledButton.styleFrom(minimumSize: const Size.fromHeight(50))),
            onPressed: _loading ? null : _save,
            icon: const Icon(Icons.check_rounded),
            label: const Text('Kaydet'),
          ),
          const SizedBox(height: 6),
          Text(
            'Kaydettikten sonra listede "Değişiklikleri yayınla"ya basmayı unutmayın.',
            textAlign: TextAlign.center,
            style: TextStyle(color: muted, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

/// Gizli hareketten (Ayarlar'da logoya 4 sn içinde 5 dokunuş) sonra açılır:
/// PIN yoksa oluşturulur, varsa sorulur; doğruysa Reklam yönetimi açılır.
/// Gizli yönetici hareketi: [child]'a 4 saniye içinde 5 dokunuş/tıklama
/// Reklam yönetimi PIN ekranını açar. Görünür bir iz bırakmaz.
class SecretAdminTap extends StatefulWidget {
  final Widget child;
  const SecretAdminTap({super.key, required this.child});

  @override
  State<SecretAdminTap> createState() => _SecretAdminTapState();
}

class _SecretAdminTapState extends State<SecretAdminTap> {
  final _taps = <DateTime>[];

  void _tap() {
    final now = DateTime.now();
    _taps
      ..removeWhere((t) => now.difference(t) > const Duration(seconds: 4))
      ..add(now);
    if (_taps.length >= 5) {
      _taps.clear();
      openAdminGate(context);
    }
  }

  @override
  Widget build(BuildContext context) =>
      GestureDetector(behavior: HitTestBehavior.opaque, onTap: _tap, child: widget.child);
}

Future<void> openAdminGate(BuildContext context) async {
  final admin = AdAdmin.instance;
  await admin.load();
  if (!context.mounted) return;
  final ok = await showDialog<bool>(context: context, builder: (_) => const _PinDialog());
  if (ok == true && context.mounted) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AdAdminScreen()));
  }
}

class _PinDialog extends StatefulWidget {
  const _PinDialog();

  @override
  State<_PinDialog> createState() => _PinDialogState();
}

class _PinDialogState extends State<_PinDialog> {
  final _admin = AdAdmin.instance;
  final _a = TextEditingController();
  final _b = TextEditingController();
  late bool _create = !_admin.hasPin;
  bool _forgot = false;
  bool _busy = false;
  String? _error;

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (_forgot) {
        if (await _admin.resetPinWithToken(_a.text)) {
          _a.clear();
          setState(() {
            _forgot = false;
            _create = true;
          });
        } else {
          setState(() => _error = 'Anahtar kayıtlı yayın anahtarıyla eşleşmedi.');
        }
        return;
      }
      if (_create) {
        if (!AdAdmin.validPin(_a.text)) {
          setState(() => _error = 'Kod 6 ile 12 rakam arasında olmalı.');
          return;
        }
        if (_a.text != _b.text) {
          setState(() => _error = 'İki kod aynı değil.');
          return;
        }
        await _admin.setPin(_a.text);
        if (mounted) Navigator.pop(context, true);
        return;
      }
      final wait = _admin.lockSeconds;
      if (wait > 0) {
        setState(() => _error = 'Çok fazla yanlış deneme. $wait saniye sonra tekrar deneyin.');
        return;
      }
      if (await _admin.checkPin(_a.text)) {
        if (mounted) Navigator.pop(context, true);
      } else {
        _a.clear();
        final w = _admin.lockSeconds;
        setState(() => _error = w > 0 ? 'Çok fazla yanlış deneme. $w saniye bekleyin.' : 'Kod yanlış.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = _forgot
        ? 'Kodu sıfırla'
        : _create
        ? 'Yönetici kodu oluştur'
        : 'Yönetici girişi';
    return AlertDialog(
      icon: const Icon(Icons.lock_outline_rounded),
      title: Text(title),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_forgot) ...[
              if (_admin.token.isNotEmpty) ...[
                const Text(
                  'Kodunuzu güvenlik için kimse göremez. Sıfırlamak için Reklam yönetiminde kayıtlı GitHub yayın '
                  'anahtarınızı yapıştırın. Eşleşirse yeni kod belirlersiniz.',
                  style: TextStyle(fontSize: 13.5),
                ),
                const SizedBox(height: 12),
                SecretField(controller: _a, label: 'Yayın anahtarı (github_pat_…)'),
                const SizedBox(height: 6),
                const Text(
                  'Anahtarınız da yoksa uygulamayı silip yeniden kurun; kod sıfırlanır, yayındaki reklamlar silinmez.',
                  style: TextStyle(fontSize: 12.5),
                ),
              ] else
                const Text(
                  'Bu cihazda henüz yayın anahtarı kayıtlı değil, yani buradan reklam yayınlanamaz. '
                  'Sıfırla\'ya dokunup yeni bir kod belirleyin. Taslak reklamlarınız korunur.',
                  style: TextStyle(fontSize: 13.5),
                ),
            ] else ...[
              if (_create)
                const Padding(
                  padding: EdgeInsets.only(bottom: 12),
                  child: Text(
                    'Yalnızca sizin bileceğiniz 6–12 rakamlı bir kod belirleyin. Kod bu cihazda şifrelenmiş olarak saklanır.',
                    style: TextStyle(fontSize: 13.5),
                  ),
                ),
              SecretField(
                controller: _a,
                autofocus: true,
                number: true,
                label: 'Kod',
                onSubmitted: _create ? null : (_) => _submit(),
              ),
              if (_create) ...[
                const SizedBox(height: 10),
                SecretField(controller: _b, number: true, label: 'Kodu tekrar girin', onSubmitted: (_) => _submit()),
              ],
            ],
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(
                  _error!,
                  style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.w600),
                ),
              ),
            if (!_create && !_forgot)
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton(
                  onPressed: () => setState(() {
                    _forgot = true;
                    _error = null;
                    _a.clear();
                  }),
                  child: const Text('Kodumu unuttum'),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Vazgeç')),
        FilledButton(
          onPressed: _busy ? null : _submit,
          child: _busy
              ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : Text(
                  _forgot
                      ? 'Sıfırla'
                      : _create
                      ? 'Oluştur ve gir'
                      : 'Gir',
                ),
        ),
      ],
    );
  }
}

/// Gizli alan (kod, anahtar): göz düğmesiyle gösterilir/gizlenir.
class SecretField extends StatefulWidget {
  final TextEditingController controller;
  final String label;
  final bool number;
  final bool autofocus;
  final ValueChanged<String>? onSubmitted;
  const SecretField({
    super.key,
    required this.controller,
    required this.label,
    this.number = false,
    this.autofocus = false,
    this.onSubmitted,
  });

  @override
  State<SecretField> createState() => _SecretFieldState();
}

class _SecretFieldState extends State<SecretField> {
  bool _show = false;

  @override
  Widget build(BuildContext context) => TextField(
    controller: widget.controller,
    autofocus: widget.autofocus,
    obscureText: !_show,
    autocorrect: false,
    enableSuggestions: false,
    keyboardType: widget.number ? TextInputType.number : TextInputType.visiblePassword,
    maxLength: widget.number ? 12 : null,
    onSubmitted: widget.onSubmitted,
    decoration: InputDecoration(
      labelText: widget.label,
      border: const OutlineInputBorder(),
      counterText: '',
      suffixIcon: IconButton(
        tooltip: _show ? 'Gizle' : 'Göster',
        icon: Icon(_show ? Icons.visibility_off_outlined : Icons.visibility_outlined),
        onPressed: () => setState(() => _show = !_show),
      ),
    ),
  );
}
