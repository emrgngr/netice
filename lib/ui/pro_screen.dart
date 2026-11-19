import 'dart:async';
import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/legal.dart';
import '../core/pro.dart';
import '../main.dart';
import 'theme.dart';
import 'widgets.dart';

/// Pro özelliği gerekiyorsa tanıtım ekranını açar. Kullanıcı Pro ise ya da
/// satın alırsa true döner.
Future<bool> requirePro(BuildContext context, ProFeature feature) async {
  final store = StoreScope.of(context);
  if (store.isPro) return true;
  await Navigator.of(context).push(MaterialPageRoute(builder: (_) => ProScreen(feature: feature), fullscreenDialog: true));
  return store.isPro;
}

/// Kilitli bir özelliğin yanında gösterilen küçük "PRO" etiketi.
class ProBadge extends StatelessWidget {
  final bool onDark;
  const ProBadge({super.key, this.onDark = false});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [Color(0xFFE9C46A), Color(0xFFD4A24C)]),
          borderRadius: BorderRadius.circular(6),
        ),
        child: const Text('PRO',
            style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 0.8, color: NColors.ink)),
      );
}

/// Kilitli içerik yerine gösterilen kart.
class ProLocked extends StatelessWidget {
  final ProFeature feature;
  const ProLocked(this.feature, {super.key});

  @override
  Widget build(BuildContext context) => Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => requirePro(context, feature),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Row(children: [
              const IconBadge(Icons.lock_outline_rounded, color: Color(0xFFD4A24C)),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Flexible(child: Text(feature.title, style: const TextStyle(fontWeight: FontWeight.w800))),
                    const SizedBox(width: 8),
                    const ProBadge(),
                  ]),
                  const SizedBox(height: 2),
                  Text(feature.detail,
                      style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6), fontSize: 13)),
                ]),
              ),
              const Icon(Icons.chevron_right),
            ]),
          ),
        ),
      );
}

class ProScreen extends StatefulWidget {
  final ProFeature? feature;
  const ProScreen({super.key, this.feature});

  @override
  State<ProScreen> createState() => _ProScreenState();
}

class _ProScreenState extends State<ProScreen> {
  List<ProPlan> _plans = ProService.fallbackPlans;
  String _selected = proYearlyId;
  bool _busy = false;
  StreamSubscription<String>? _sub;

  @override
  void initState() {
    super.initState();
    ProService.instance.plans().then((p) {
      if (mounted) setState(() => _plans = p);
    });
    _sub = ProService.instance.events.listen((m) {
      if (!mounted) return;
      setState(() => _busy = false);
      toast(context, m);
      if (StoreScope.of(context).isPro) Navigator.of(context).maybePop();
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _buy() async {
    final plan = _plans.firstWhere((p) => p.id == _selected, orElse: () => _plans.first);
    setState(() => _busy = true);
    final err = await ProService.instance.buy(plan);
    if (!mounted) return;
    if (err != null) {
      setState(() => _busy = false);
      toast(context, err);
    }
  }

  Future<void> _restore() async {
    final err = await ProService.instance.restore();
    if (!mounted) return;
    toast(context, err ?? 'Satın alımlar kontrol ediliyor…');
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final f = widget.feature;
    return Scaffold(
      backgroundColor: const Color(0xFF070D22),
      body: Stack(children: [
        const Positioned.fill(child: _ProBackdrop()),
        SafeArea(
          child: ListView(padding: const EdgeInsets.fromLTRB(20, 4, 20, 28), children: [
            Align(
              alignment: Alignment.centerLeft,
              child: IconButton(
                onPressed: () => Navigator.of(context).maybePop(),
                icon: const Icon(Icons.close_rounded, color: Colors.white70),
                tooltip: 'Kapat',
              ),
            ),
            const SizedBox(height: 4),
            const Center(child: AppLogo(size: 64)),
            const SizedBox(height: 16),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: const [
              Text('Netice',
                  style: TextStyle(color: Colors.white, fontSize: 30, fontWeight: FontWeight.w800, letterSpacing: -0.6)),
              SizedBox(width: 10),
              _GoldPro(),
            ]),
            const SizedBox(height: 8),
            Text(
              f == null
                  ? 'Okumak her zaman ücretsiz. Pro ile raporlarınız tek dokunuşla hazır.'
                  : '"${f.title}" Netice Pro ile açılır. Okumak her zaman ücretsiz.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white.withValues(alpha: 0.72), fontSize: 14.5, height: 1.4),
            ),
            const SizedBox(height: 22),
            for (final x in ProFeature.values) _FeatureRow(x, highlight: x == f),
            const SizedBox(height: 18),
            if (store.inTrial && !store.hasSubscription)
              Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: Text('Ücretsiz denemenizde ${store.trialDaysLeft} gün kaldı. Deneme bitince yalnızca bu özellikler kilitlenir; verileriniz olduğu gibi kalır.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Color(0xFFE9C46A), fontWeight: FontWeight.w600, fontSize: 13)),
              ),
            if (store.hasSubscription)
              _ActiveCard(product: store.proProduct)
            else ...[
              for (final p in _plans)
                _PlanTile(
                  plan: p,
                  selected: p.id == _selected,
                  best: p.id == proYearlyId,
                  onTap: () => setState(() => _selected = p.id),
                ),
              const SizedBox(height: 14),
              SizedBox(
                height: 58,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: NColors.emerald,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                    textStyle: const TextStyle(fontFamily: 'PlusJakartaSans', fontSize: 17, fontWeight: FontWeight.w800),
                  ),
                  onPressed: _busy ? null : _buy,
                  child: _busy
                      ? const SizedBox.square(dimension: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
                      : const Text('Pro\'ya geç'),
                ),
              ),
              const SizedBox(height: 6),
              TextButton(
                onPressed: _restore,
                child: const Text('Satın alımları geri yükle', style: TextStyle(color: Colors.white70)),
              ),
            ],
            const SizedBox(height: 6),
            Text(
              '${Platform.isIOS ? 'Ödeme Apple Kimliğinizden' : 'Ödeme Google Play hesabınızdan'} alınır. Abonelik, dönem bitmeden en az 24 saat önce iptal edilmezse '
              'aynı süre ve fiyatla kendiliğinden yenilenir. ${Platform.isIOS ? 'Ayarlar > Apple Kimliği > Abonelikler' : 'Google Play > Abonelikler'} bölümünden '
              'istediğiniz zaman iptal edebilirsiniz; iptal edilen abonelik dönem sonuna kadar geçerlidir. '
              'Pro\'ya geçmek verilerinizin yerini değiştirmez: her şey yine bu cihazda kalır.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white.withValues(alpha: 0.45), fontSize: 11.5, height: 1.45),
            ),
            const SizedBox(height: 6),
            Wrap(alignment: WrapAlignment.center, children: [
              TextButton(
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => Scaffold(
                          appBar: AppBar(title: const Text('Gizlilik politikası')),
                          body: SingleChildScrollView(padding: const EdgeInsets.all(20), child: SelectableText(privacyPolicy)),
                        ))),
                child: const Text('Gizlilik politikası', style: TextStyle(color: Colors.white60, fontSize: 12)),
              ),
              TextButton(
                onPressed: () => launchUrl(Uri.parse(termsUrl), mode: LaunchMode.externalApplication),
                child: const Text('Kullanım koşulları', style: TextStyle(color: Colors.white60, fontSize: 12)),
              ),
            ]),
          ]),
        ),
      ]),
    );
  }
}

class _GoldPro extends StatelessWidget {
  const _GoldPro();
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [Color(0xFFF3D98B), Color(0xFFD4A24C)]),
          borderRadius: BorderRadius.circular(10),
          boxShadow: [BoxShadow(color: const Color(0xFFD4A24C).withValues(alpha: 0.45), blurRadius: 16)],
        ),
        child: const Text('PRO',
            style: TextStyle(color: NColors.ink, fontWeight: FontWeight.w900, fontSize: 16, letterSpacing: 1.2)),
      );
}

class _FeatureRow extends StatelessWidget {
  final ProFeature f;
  final bool highlight;
  const _FeatureRow(this.f, {this.highlight = false});

  static const _icons = {
    ProFeature.termReport: Icons.workspace_premium_outlined,
    ProFeature.studentCards: Icons.badge_outlined,
    ProFeature.parentShare: Icons.send_rounded,
    ProFeature.cloudBackup: Icons.cloud_done_outlined,
    ProFeature.advancedCharts: Icons.donut_large_rounded,
    ProFeature.officialHeader: Icons.account_balance_outlined,
  };

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: highlight ? 0.12 : 0.05),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: highlight ? const Color(0xFFE9C46A) : Colors.white.withValues(alpha: 0.08)),
        ),
        child: Row(children: [
          Icon(_icons[f], color: const Color(0xFF7BE0B4), size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(f.title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14.5)),
              Text(f.detail, style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 12.5)),
            ]),
          ),
        ]),
      );
}

class _PlanTile extends StatelessWidget {
  final ProPlan plan;
  final bool selected;
  final bool best;
  final VoidCallback onTap;
  const _PlanTile({required this.plan, required this.selected, required this.best, required this.onTap});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: selected ? NColors.emerald.withValues(alpha: 0.16) : Colors.white.withValues(alpha: 0.04),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: selected ? NColors.emerald : Colors.white.withValues(alpha: 0.12), width: selected ? 2 : 1),
            ),
            child: Row(children: [
              Icon(selected ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
                  color: selected ? NColors.emerald : Colors.white54),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Text(plan.title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16)),
                    if (best) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(color: const Color(0xFFE9C46A), borderRadius: BorderRadius.circular(6)),
                        child: const Text('%33 tasarruf',
                            style: TextStyle(color: NColors.ink, fontSize: 10.5, fontWeight: FontWeight.w900)),
                      ),
                    ],
                  ]),
                  Text(plan.note, style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 12.5)),
                ]),
              ),
              Text(plan.price, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15)),
            ]),
          ),
        ),
      );
}

class _ActiveCard extends StatelessWidget {
  final String? product;
  const _ActiveCard({this.product});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: NColors.emerald.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: NColors.emerald),
        ),
        child: Column(children: [
          const Icon(Icons.verified_rounded, color: NColors.emerald, size: 36),
          const SizedBox(height: 8),
          Text('Netice Pro etkin${product == proYearlyId ? ' · Yıllık' : product == proMonthlyId ? ' · Aylık' : ''}',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16)),
          const SizedBox(height: 10),
          OutlinedButton(
            style: OutlinedButton.styleFrom(foregroundColor: Colors.white, side: const BorderSide(color: Colors.white38)),
            onPressed: () => launchUrl(
                Uri.parse(Platform.isIOS
                    ? 'https://apps.apple.com/account/subscriptions'
                    : 'https://play.google.com/store/account/subscriptions?package=$androidPackage'),
                mode: LaunchMode.externalApplication),
            child: const Text('Aboneliği yönet'),
          ),
        ]),
      );
}

class _ProBackdrop extends StatelessWidget {
  const _ProBackdrop();
  @override
  Widget build(BuildContext context) => const DecoratedBox(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(0, -0.9),
            radius: 1.2,
            colors: [Color(0xFF1B2D63), Color(0xFF070D22)],
          ),
        ),
      );
}
