import 'package:material_ui/material_ui.dart';

import '../core/ad_admin.dart';
import '../core/ads.dart';
import 'ad_admin_screen.dart';
import 'theme.dart';
import 'widgets.dart';

String _n(int v) {
  final s = v.toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write('.');
    b.write(s[i]);
  }
  return b.toString();
}

String _pct(double r) => '%${(r * 100).toStringAsFixed(r >= 0.1 ? 1 : 2).replaceAll('.', ',')}';

/// Reklam istatistikleri: kimliksiz sayaçtan görülme, tıklama, tıklama oranı
/// ve A/B testi sonucu. (Yönetici ekranı; metinler Türkçedir.)
class AdStatsScreen extends StatefulWidget {
  /// Testler ve önizleme için hazır veri.
  final Map<String, AdStats>? initial;
  const AdStatsScreen({super.key, this.initial});

  @override
  State<AdStatsScreen> createState() => _AdStatsScreenState();
}

class _AdStatsScreenState extends State<AdStatsScreen> {
  final _admin = AdAdmin.instance;
  int _days = 30;
  Map<String, AdStats>? _stats;
  String? _error;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _stats = widget.initial;
    if (_stats == null) _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final (stats, err) = await _admin.fetchStats(_days);
    if (!mounted) return;
    setState(() {
      _loading = false;
      _stats = stats ?? _stats;
      _error = err;
    });
  }

  void _keep(Ad ad, {required bool b}) {
    _admin.upsert(b ? ad.copyWith(media: ad.mediaB, mediaB: '') : ad.copyWith(mediaB: ''));
    toast(context, 'Kaydedildi. Kullanıcılara gitmesi için "Değişiklikleri yayınla"ya basın.');
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6);
    final stats = _stats ?? const {};
    final ads = _admin.drafts.where((a) => !a.draft).toList();
    final known = {for (final a in ads) a.id};
    final total = stats.values.fold(const AdCounts(), (s, e) => s + e.total);
    final rows = [for (final a in ads) (a, stats[a.id] ?? const AdStats())]
      ..sort((x, y) => y.$2.total.views.compareTo(x.$2.total.views));
    final gone = stats.entries.where((e) => !known.contains(e.key)).fold(const AdCounts(), (s, e) => s + e.value.total);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Reklam istatistikleri'),
        actions: [
          IconButton(tooltip: 'Yenile', onPressed: _loading ? null : _load, icon: const Icon(Icons.refresh_rounded)),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            SegmentedButton<int>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: 1, label: Text('Bugün')),
                ButtonSegment(value: 7, label: Text('7 gün')),
                ButtonSegment(value: 30, label: Text('30 gün')),
                ButtonSegment(value: 90, label: Text('90 gün')),
              ],
              selected: {_days},
              onSelectionChanged: (s) {
                _days = s.first;
                _load();
              },
            ),
            const SizedBox(height: 12),
            if (_loading) const LinearProgressIndicator(),
            if (_error != null)
              Card(
                color: NColors.amber.withValues(alpha: 0.18),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline_rounded, color: NColors.amber),
                      const SizedBox(width: 10),
                      Expanded(child: Text(_error!)),
                    ],
                  ),
                ),
              ),
            Row(
              children: [
                Expanded(
                  child: _Tile(label: 'Görülme', value: _n(total.views)),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _Tile(label: 'Tıklama', value: _n(total.clicks)),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _Tile(label: 'Tıklama oranı', value: _pct(total.rate)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Sayılar kimliksizdir: her reklamın günlük toplamı tutulur, kimin gördüğü bilinmez. '
              'Pro kullanıcılar reklam görmediği için sayılmaz. Yeni sayılar birkaç dakika gecikmeyle gelir.',
              style: TextStyle(color: muted, fontSize: 12),
            ),
            SectionTitle('Reklamlar'),
            if (rows.isEmpty) Text('Yayında reklam yok.', style: TextStyle(color: muted)),
            for (final (a, s) in rows) _AdCard(ad: a, stats: s, days: _days, onKeep: _keep),
            if (gone.views > 0)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  'Silinmiş reklamlar: ${_n(gone.views)} görülme, ${_n(gone.clicks)} tıklama',
                  style: TextStyle(color: muted, fontSize: 12.5),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  final String label;
  final String value;
  const _Tile({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.65);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: muted, fontSize: 12),
            ),
            const SizedBox(height: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
            ),
          ],
        ),
      ),
    );
  }
}

class _AdCard extends StatelessWidget {
  final Ad ad;
  final AdStats stats;
  final int days;
  final void Function(Ad ad, {required bool b}) onKeep;
  const _AdCard({required this.ad, required this.stats, required this.days, required this.onKeep});

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6);
    final t = stats.total;
    final ab = ad.hasAB || stats.b.views > 0;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: SizedBox(width: 72, height: 40.5, child: AdThumb(ad: ad)),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    ad.name.isEmpty ? 'Adsız reklam' : ad.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                _metric('Görülme', _n(t.views), muted),
                _metric('Tıklama', _n(t.clicks), muted),
                _metric('Oran', _pct(t.rate), muted),
              ],
            ),
            if (days > 1 && stats.daily.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text('Günlük görülme', style: TextStyle(color: muted, fontSize: 11.5)),
              const SizedBox(height: 4),
              SizedBox(
                height: 44,
                child: _DailyBars(daily: stats.daily, days: days),
              ),
            ],
            if (ab) ...[
              const Divider(height: 22),
              const Text('A/B testi', style: TextStyle(fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              _abRow('A', stats.a, muted),
              _abRow('B', stats.b, muted),
              const SizedBox(height: 6),
              _verdict(context, muted),
            ],
          ],
        ),
      ),
    );
  }

  Widget _metric(String label, String value, Color muted) => Expanded(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(color: muted, fontSize: 11.5)),
        Text(value, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
      ],
    ),
  );

  Widget _abRow(String name, AdCounts c, Color muted) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(
      children: [
        SizedBox(
          width: 22,
          child: Text(name, style: const TextStyle(fontWeight: FontWeight.w900)),
        ),
        Expanded(
          child: Text(
            '${_n(c.views)} görülme · ${_n(c.clicks)} tıklama',
            style: TextStyle(color: muted, fontSize: 12.5),
          ),
        ),
        Text(_pct(c.rate), style: const TextStyle(fontWeight: FontWeight.w800)),
      ],
    ),
  );

  Widget _verdict(BuildContext context, Color muted) {
    final v = abVerdict(stats.a, stats.b);
    final green = FilledButton.styleFrom(backgroundColor: NColors.nightEmerald, foregroundColor: Colors.white);
    return switch (v) {
      AbVerdict.needMoreData => Text(
        'Karar için iki görsel de en az 100 kez görülmeli '
        '(şimdi A ${_n(stats.a.views)}, B ${_n(stats.b.views)}).',
        style: TextStyle(color: muted, fontSize: 12.5),
      ),
      AbVerdict.noDifference => Text(
        'İki görsel arasında belirgin fark yok. Teste devam edebilirsiniz.',
        style: TextStyle(color: muted, fontSize: 12.5),
      ),
      AbVerdict.aWins || AbVerdict.bWins => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.emoji_events_rounded, color: NColors.amber, size: 20),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '${v == AbVerdict.bWins ? 'B' : 'A'} görseli daha çok tıklanıyor (%95 güvenle).',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          if (ad.hasAB) ...[
            const SizedBox(height: 6),
            FilledButton.icon(
              style: green,
              onPressed: () => onKeep(ad, b: v == AbVerdict.bWins),
              icon: const Icon(Icons.check_rounded),
              label: Text('${v == AbVerdict.bWins ? 'B' : 'A'} görselini kalıcı yap'),
            ),
          ],
        ],
      ),
    };
  }
}

/// Tek seri günlük görülme çubukları (son [days] gün, en çok 30 çubuk).
class _DailyBars extends StatelessWidget {
  final Map<String, AdCounts> daily;
  final int days;
  const _DailyBars({required this.daily, required this.days});

  @override
  Widget build(BuildContext context) {
    final n = days.clamp(1, 30);
    final today = DateTime.now().toUtc();
    final values = [
      for (var i = n - 1; i >= 0; i--)
        daily[today.subtract(Duration(days: i)).toIso8601String().substring(0, 10)]?.views ?? 0,
    ];
    final dark = Theme.of(context).brightness == Brightness.dark;
    return CustomPaint(
      size: Size.infinite,
      painter: _BarsPainter(values, bar: NColors.navy(dark), base: Theme.of(context).colorScheme.outlineVariant),
    );
  }
}

class _BarsPainter extends CustomPainter {
  final List<int> values;
  final Color bar;
  final Color base;
  _BarsPainter(this.values, {required this.bar, required this.base});

  @override
  void paint(Canvas canvas, Size size) {
    final top = values.fold(0, (a, b) => a > b ? a : b);
    const gap = 2.0;
    final w = (size.width - gap * (values.length - 1)) / values.length;
    final p = Paint()..color = bar;
    for (var i = 0; i < values.length; i++) {
      if (top == 0 || values[i] == 0) continue;
      final h = (size.height - 1) * values[i] / top;
      final x = i * (w + gap);
      final r = (w / 2).clamp(0.0, 4.0);
      canvas.drawRRect(
        RRect.fromRectAndCorners(
          Rect.fromLTWH(x, size.height - 1 - h, w, h),
          topLeft: Radius.circular(r),
          topRight: Radius.circular(r),
        ),
        p,
      );
    }
    canvas.drawLine(Offset(0, size.height - 0.5), Offset(size.width, size.height - 0.5), Paint()..color = base);
  }

  @override
  bool shouldRepaint(_BarsPainter old) => old.values != values || old.bar != bar;
}
