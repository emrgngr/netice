import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../bank/ai_questions.dart';
import '../core/campaigns.dart';
import '../core/legal.dart';
import '../core/pro.dart';
import '../core/referral.dart';
import '../main.dart';
import 'invite_screen.dart';
import 'license_screen.dart';
import 'school_offer_screen.dart';
import 'service_cards.dart';
import 'theme.dart';
import 'widgets.dart';
import '../l10n/l10n.dart';

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
  final Campaign? _campaign = ProService.campaign;
  late List<ProPlan> _plans = ProService.plansFor(DateTime.now(), invite: ProService.instance.inviteApplied);

  /// İndirimli kampanya yalnız mağazada gerçekten alınabiliyorsa gösterilir.
  bool get _campaignShown =>
      _campaign != null && (!_campaign.hasDiscount || ProService.instance.campaignDiscountLive);
  bool get _discountShown => _campaign != null && _campaign.hasDiscount && ProService.instance.campaignDiscountLive;
  late String _selected = _campaign?.highlightTermPass == true ? proTermPassId : proYearlyId;
  ProPlan _pack = ProService.aiPackFallback();
  bool _busy = false;
  bool _packBusy = false;
  StreamSubscription<String>? _sub;

  @override
  void initState() {
    super.initState();
    _loadPlans();
    AiUsage.instance.load().then((_) {
      if (mounted) setState(() {});
    });
    _sub = ProService.instance.events.listen((m) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _packBusy = false;
      });
      toast(context, m);
      if (StoreScope.of(context).isPro && widget.feature != ProFeature.aiQuestions) Navigator.of(context).maybePop();
    });
  }

  void _loadPlans() {
    ProService.instance.plans().then((p) {
      if (mounted) setState(() => _plans = p);
    });
    ProService.instance.aiPack().then((p) {
      if (mounted) setState(() => _pack = p);
    });
  }

  Future<void> _buyPack() async {
    setState(() => _packBusy = true);
    final err = await ProService.instance.buy(_pack);
    if (!mounted) return;
    setState(() => _packBusy = false);
    if (err != null) toast(context, err);
  }

  Future<void> _openInvite() async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const InviteScreen()));
    if (!mounted) return;
    setState(() => _plans = ProService.plansFor(DateTime.now(), invite: ProService.instance.inviteApplied));
    _loadPlans();
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
    toast(context, err ?? tr('Satın alımlar kontrol ediliyor…'));
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
          child: LayoutBuilder(builder: (context, box) {
          // Geniş ekranda içerik ortada en çok 1100 px; planlar ve hizmetler
          // ince uzun satırlar yerine yan yana kartlar olarak dizilir.
          final w = box.maxWidth;
          final wide = w >= 760;
          final side = w > 1140 ? (w - 1100) / 2 : 20.0;
          return ListView(padding: EdgeInsets.fromLTRB(side, 4, side, 28), children: [
            Align(
              alignment: Alignment.centerLeft,
              child: IconButton(
                onPressed: () => Navigator.of(context).maybePop(),
                icon: const Icon(Icons.close_rounded, color: Colors.white70),
                tooltip: tr('Kapat'),
              ),
            ),
            const SizedBox(height: 4),
            const Center(child: AppLogo(size: 64)),
            const SizedBox(height: 16),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Text(tr('Netice'),
                  style: TextStyle(color: Colors.white, fontSize: 30, fontWeight: FontWeight.w800, letterSpacing: -0.6)),
              SizedBox(width: 10),
              _GoldPro(),
            ]),
            const SizedBox(height: 8),
            Text(
              f == null
                  ? tr('Okumak her zaman ücretsiz. Pro ile raporlarınız tek dokunuşla hazır.')
                  : tr('"{0}" Netice Pro ile açılır. Okumak her zaman ücretsiz.', [f.title]),
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white.withValues(alpha: 0.72), fontSize: 14.5, height: 1.4),
            ),
            const SizedBox(height: 22),
            ServiceGrid(
              columns: w >= 1000 ? 3 : (w >= 640 ? 2 : 1),
              gap: 10,
              children: [for (final x in ProFeature.values) _FeatureRow(x, highlight: x == f)],
            ),
            const SizedBox(height: 10),
            const _TrustLine(),
            const SizedBox(height: 18),
            if (store.inTrial && !store.hasSubscription)
              Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: Text(tr('Ücretsiz denemenizde {0} gün kaldı. Deneme bitince yalnızca bu özellikler kilitlenir; verileriniz olduğu gibi kalır.', [store.trialDaysLeft]),
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Color(0xFFE9C46A), fontWeight: FontWeight.w600, fontSize: 13)),
              ),
            if (store.thanksCode != null && !ProService.salesDisabled)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _InviteCta(
                  title: tr('Davet edene teşekkür kodunuzu gönderin'),
                  detail: tr('Sizi davet eden öğretmen 1 ay ek Pro kazansın.'),
                  onTap: _openInvite,
                ),
              ),
            if (store.hasLicense)
              _LicenseActiveCard(store.license!.institution, store.license!.daysLeft(DateTime.now()))
            else if (store.hasSubscription)
              _ActiveCard(product: store.proProduct)
            else if (ProService.salesDisabled)
              const _SoonCard()
            else ...[
              if (store.hasTermPass)
                Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: Text(
                      tr('Sınav dönemi paketiniz {0} tarihine kadar geçerli. Yeni paket alırsanız süre bunun üzerine eklenir.',
                          [L10n.date(store.termPassUntil!)]),
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Color(0xFF7BE0B4), fontWeight: FontWeight.w600, fontSize: 13)),
                ),
              if (_campaignShown)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _CampaignBanner(_campaign!),
                ),
              if (_discountShown && Platform.isIOS)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(foregroundColor: Colors.white, side: const BorderSide(color: Colors.white38)),
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(text: _campaign.appStoreOfferCode));
                      await ProService.instance.redeemOfferCodeOnAppStore();
                    },
                    icon: const Icon(Icons.local_offer_outlined),
                    label: Text(tr('İndirimi App Store\'da kullan (kod: {0})', [_campaign!.appStoreOfferCode])),
                  ),
                ),
              if (ProService.instance.inviteApplied && !_discountShown)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(tr('Davet kodu uygulandı: {0} · yıllık abonelik ilk yıl %15 indirimli', [store.appliedInvite!]),
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Color(0xFF7BE0B4), fontWeight: FontWeight.w700, fontSize: 13)),
                ),
              if (ProService.instance.inviteApplied && Platform.isIOS && !_discountShown)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(foregroundColor: Colors.white, side: const BorderSide(color: Colors.white38)),
                    onPressed: () async {
                      await Clipboard.setData(const ClipboardData(text: Referral.appStoreOfferCode));
                      await ProService.instance.redeemInviteOnAppStore();
                    },
                    icon: const Icon(Icons.local_offer_outlined),
                    label: Text(tr('İndirimi App Store\'da kullan (kod: {0})', [Referral.appStoreOfferCode])),
                  ),
                ),
              if (wide)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: ServiceGrid(
                    columns: _plans.length.clamp(1, 3),
                    children: [
                      for (final p in _plans)
                        _PlanCard(
                          plan: p,
                          selected: p.id == _selected,
                          best: p.id == (_campaign?.highlightTermPass == true ? proTermPassId : proYearlyId),
                          onTap: () => setState(() => _selected = p.id),
                        ),
                    ],
                  ),
                )
              else
                for (final p in _plans)
                  _PlanTile(
                    plan: p,
                    selected: p.id == _selected,
                    best: p.id == (_campaign?.highlightTermPass == true ? proTermPassId : proYearlyId),
                    onTap: () => setState(() => _selected = p.id),
                  ),
              const _PriceLock(),
              const SizedBox(height: 14),
              Center(
                child: SizedBox(
                height: 58,
                width: wide ? 440 : double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: NColors.deepEmerald,
                    foregroundColor: Colors.white,
                    shape: const StadiumBorder(),
                    textStyle: const TextStyle(fontFamily: 'PlusJakartaSans', fontSize: 17, fontWeight: FontWeight.w800),
                  ),
                  onPressed: _busy ? null : _buy,
                  child: _busy
                      ? const SizedBox.square(dimension: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
                      : Text(tr('Pro\'ya geç')),
                ),
              ),
              ),
              const SizedBox(height: 6),
              TextButton(
                onPressed: _restore,
                child: Text(tr('Satın alımları geri yükle'), style: TextStyle(color: Colors.white70)),
              ),
            ],
            const SizedBox(height: 14),
            Builder(builder: (context) {
              final extras = <Widget>[
                if (!ProService.salesDisabled) _AiPackCard(plan: _pack, busy: _packBusy, onBuy: _buyPack, vertical: wide),
                if (store.thanksCode == null && !ProService.salesDisabled)
                  _InviteCta(
                    title: tr('Arkadaşını davet et'),
                    detail: store.appliedInvite == null && !store.hasSubscription
                        ? tr('Davet kodunuz varsa %15 indirim. Siz davet ederseniz her arkadaşınız için 1 ay ek Pro.')
                        : tr('Her arkadaşınız için 1 ay ek Pro kazanın.'),
                    onTap: _openInvite,
                    vertical: wide,
                  ),
                if (!ProService.salesDisabled)
                  _SchoolPackCta(onTap: () => SchoolOfferScreen.open(context), vertical: wide),
                _InstitutionCta(
                  vertical: wide,
                  onTap: () async {
                    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const LicenseScreen()));
                    if (context.mounted && StoreScope.of(context).isPro && widget.feature != null) {
                      Navigator.of(context).maybePop();
                    }
                    if (mounted) setState(() {});
                  },
                ),
              ];
              return ServiceGrid(
                columns: wide ? (extras.length == 3 || w >= 1060 && extras.length == 4 ? extras.length : 2) : 1,
                gap: wide ? 14 : 10,
                children: extras,
              );
            }),
            const SizedBox(height: 14),
            const SizedBox(height: 6),
            if (!ProService.salesDisabled)
            Text(
              tr('{0} alınır. Sınav dönemi paketi ve ek soru paketi tek seferliktir ve yenilenmez. Yıllık abonelik, dönem bitmeden en az 24 saat önce iptal edilmezse aynı süre ve fiyatla kendiliğinden yenilenir. {1} bölümünden istediğiniz zaman iptal edebilirsiniz; iptal edilen abonelik dönem sonuna kadar geçerlidir. Pro\'ya geçmek verilerinizin yerini değiştirmez: her şey yine bu cihazda kalır.', [Platform.isIOS || Platform.isMacOS ? tr('Ödeme Apple Kimliğinizden') : Platform.isWindows ? tr('Ödeme Microsoft hesabınızdan') : tr('Ödeme Google Play hesabınızdan'), Platform.isIOS || Platform.isMacOS ? tr('Ayarlar > Apple Kimliği > Abonelikler') : Platform.isWindows ? tr('Microsoft hesabı > Hizmetler ve abonelikler') : tr('Google Play > Abonelikler')]),
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white.withValues(alpha: 0.45), fontSize: 11.5, height: 1.45),
            ),
            const SizedBox(height: 6),
            Wrap(alignment: WrapAlignment.center, children: [
              TextButton(
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => Scaffold(
                          appBar: AppBar(title: Text(tr('Gizlilik politikası'))),
                          body: SingleChildScrollView(padding: const EdgeInsets.all(20), child: SelectableText(privacyPolicy)),
                        ))),
                child: Text(tr('Gizlilik politikası'), style: TextStyle(color: Colors.white60, fontSize: 12)),
              ),
              TextButton(
                onPressed: () => launchUrl(Uri.parse(termsUrl), mode: LaunchMode.externalApplication),
                child: Text(tr('Kullanım koşulları'), style: TextStyle(color: Colors.white60, fontSize: 12)),
              ),
            ]),
          ]);
          }),
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

/// Güven satırı: üçüncü taraf reklam ve izleme olmadığını vurgular.
class _TrustLine extends StatelessWidget {
  const _TrustLine();

  @override
  Widget build(BuildContext context) => Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        const Icon(Icons.verified_user_outlined, color: Color(0xFF7BE0B4), size: 16),
        const SizedBox(width: 8),
        Flexible(
          child: Text(tr('Üçüncü taraf reklam yok · Sizi izleyen reklam ağı yok · Verileriniz cihazınızda kalır'),
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 12, fontWeight: FontWeight.w600, height: 1.4)),
        ),
      ]);
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
    ProFeature.deviceSync: Icons.devices_rounded,
    ProFeature.gradeExport: Icons.school_outlined,
    ProFeature.advancedCharts: Icons.donut_large_rounded,
    ProFeature.detailedStats: Icons.query_stats_rounded,
    ProFeature.officialHeader: Icons.account_balance_outlined,
    ProFeature.commonExam: Icons.hub_outlined,
    ProFeature.denemeExam: Icons.view_column_outlined,
    ProFeature.adminPanel: Icons.dashboard_customize_outlined,
    ProFeature.bookletVariants: Icons.auto_stories_outlined,
    ProFeature.studyTips: Icons.lightbulb_outline_rounded,
    ProFeature.personalReview: Icons.assignment_ind_outlined,
    ProFeature.outcomeTracking: Icons.grid_on_rounded,
    ProFeature.wordExport: Icons.description_outlined,
    ProFeature.lanSync: Icons.wifi_rounded,
    ProFeature.bulkParent: Icons.forward_to_inbox_rounded,
    ProFeature.balancedBlueprint: Icons.table_chart_outlined,
    ProFeature.misconceptions: Icons.psychology_outlined,
    ProFeature.parentLanguage: Icons.translate_rounded,
    ProFeature.studyGroups: Icons.diversity_3_rounded,
    ProFeature.mastery: Icons.military_tech_outlined,
    ProFeature.rubrics: Icons.rule_rounded,
    ProFeature.makeupExam: Icons.content_copy_rounded,
    ProFeature.similarAnswers: Icons.compare_rounded,
    ProFeature.transferFile: Icons.drive_file_move_outline,
    ProFeature.aiQuestions: Icons.auto_awesome_outlined,
    ProFeature.noAds: Icons.block_rounded,
  };

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: highlight ? 0.12 : 0.05),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: highlight ? const Color(0xFFE9C46A) : Colors.white.withValues(alpha: 0.08)),
        ),
        child: Row(children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFF7BE0B4).withValues(alpha: 0.13),
            ),
            child: Icon(_icons[f], color: const Color(0xFF7BE0B4), size: 21),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
              Text(f.title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14.5)),
              Text(f.detail, style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 12.5)),
            ]),
          ),
        ]),
      );
}

/// Satış kapalı derlemede fiyat ve satın alma yerine gösterilir.
class _SoonCard extends StatelessWidget {
  const _SoonCard();

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white24),
        ),
        child: Column(children: [
          const Icon(Icons.schedule_rounded, color: Color(0xFFE9C46A), size: 30),
          const SizedBox(height: 8),
          Text(tr('Pro aboneliği yakında App Store\'da'),
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16)),
          const SizedBox(height: 6),
          Text(tr('Okuma, soru bankası ve temel raporlar ücretsizdir. Pro özellikleri bir sonraki güncellemeyle satın alınabilecek.'),
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white.withValues(alpha: 0.72), fontSize: 13.5, height: 1.4)),
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
                  Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                    Text(plan.title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16)),
                    if (best) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(color: const Color(0xFFE9C46A), borderRadius: BorderRadius.circular(6)),
                        child: Text(tr('Önerilen'),
                            style: const TextStyle(color: NColors.ink, fontSize: 10.5, fontWeight: FontWeight.w900)),
                      ),
                    ],
                  ]),
                  Text(plan.note, style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 12.5)),
                ]),
              ),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                if (plan.oldPrice != null)
                  Text(plan.oldPrice!,
                      style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.5),
                          fontSize: 12.5,
                          decoration: TextDecoration.lineThrough,
                          decorationColor: Colors.white54)),
                Text(plan.price, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15)),
              ]),
            ]),
          ),
        ),
      );
}

/// Geniş ekranda plan kartı: seçim düğmesi ve rozet üstte, büyük fiyat altta.
class _PlanCard extends StatelessWidget {
  final ProPlan plan;
  final bool selected;
  final bool best;
  final VoidCallback onTap;
  const _PlanCard({required this.plan, required this.selected, required this.best, required this.onTap});

  @override
  Widget build(BuildContext context) => InkWell(
        borderRadius: BorderRadius.circular(26),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            gradient: selected
                ? LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [NColors.emerald.withValues(alpha: 0.24), NColors.emerald.withValues(alpha: 0.08)],
                  )
                : null,
            color: selected ? null : Colors.white.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(26),
            border: Border.all(color: selected ? NColors.emerald : Colors.white.withValues(alpha: 0.12), width: selected ? 2 : 1),
            boxShadow: [
              if (selected) BoxShadow(color: NColors.emerald.withValues(alpha: 0.22), blurRadius: 28, offset: const Offset(0, 10)),
            ],
          ),
          child: Stack(children: [
            PositionedDirectional(
              top: -50,
              end: -50,
              child: Container(
                width: 140,
                height: 140,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: (selected ? NColors.emerald : Colors.white).withValues(alpha: selected ? 0.14 : 0.04),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Icon(selected ? Icons.check_circle_rounded : Icons.radio_button_off_rounded,
                      color: selected ? NColors.emerald : Colors.white54, size: 26),
                  const Spacer(),
                  if (best)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(color: const Color(0xFFE9C46A), borderRadius: BorderRadius.circular(99)),
                      child: Text(tr('Önerilen'),
                          style: const TextStyle(color: NColors.ink, fontSize: 11, fontWeight: FontWeight.w900)),
                    ),
                ]),
                const SizedBox(height: 16),
                Text(plan.title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 18, height: 1.2)),
                const SizedBox(height: 4),
                Text(plan.note, style: TextStyle(color: Colors.white.withValues(alpha: 0.62), fontSize: 13, height: 1.35)),
                const SizedBox(height: 18),
                const Spacer(),
                if (plan.oldPrice != null)
                  Text(plan.oldPrice!,
                      style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.5),
                          fontSize: 13,
                          decoration: TextDecoration.lineThrough,
                          decorationColor: Colors.white54)),
                Text(plan.price,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 26, letterSpacing: -0.4)),
              ]),
            ),
          ]),
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
          Text(
              tr('Netice Pro etkin{0}', [
                product == proAiYearlyId
                    ? tr(' · Pro + Yapay Zekâ')
                    : product == proYearlyId
                        ? tr(' · Yıllık')
                        : product == proMonthlyId
                            ? tr(' · Aylık')
                            : ''
              ]),
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16)),
          const SizedBox(height: 10),
          OutlinedButton(
            style: OutlinedButton.styleFrom(foregroundColor: Colors.white, side: const BorderSide(color: Colors.white38)),
            onPressed: () => launchUrl(
                Uri.parse(Platform.isIOS || Platform.isMacOS
                    ? 'https://apps.apple.com/account/subscriptions'
                    : 'https://play.google.com/store/account/subscriptions?package=$androidPackage'),
                mode: LaunchMode.externalApplication),
            child: Text(tr('Aboneliği yönet')),
          ),
        ]),
      );
}

/// Pro ekranındaki ek hizmet kartı (ek paket, davet, okul paketi, kurum).
/// [vertical] geniş ekranda kart biçimi: üstte yuvarlak simge, altta eylem.
/// Dar ekranda yatay, yuvarlatılmış bir kart olarak kalır.
class _ExtraCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String detail;
  final String? note;
  final Widget? action;
  final VoidCallback? onTap;
  final bool vertical;
  const _ExtraCard({
    required this.icon,
    required this.color,
    required this.title,
    required this.detail,
    this.note,
    this.action,
    this.onTap,
    this.vertical = false,
  });

  @override
  Widget build(BuildContext context) {
    final r = BorderRadius.circular(vertical ? 26 : 22);
    final badge = Container(
      width: vertical ? 50 : 42,
      height: vertical ? 50 : 42,
      decoration: BoxDecoration(shape: BoxShape.circle, color: color.withValues(alpha: 0.16)),
      child: Icon(icon, color: color, size: vertical ? 25 : 22),
    );
    final texts = <Widget>[
      Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15, height: 1.25)),
      const SizedBox(height: 3),
      Text(detail, style: TextStyle(color: Colors.white.withValues(alpha: 0.62), fontSize: 12.5, height: 1.4)),
      if (note != null) ...[
        const SizedBox(height: 4),
        Text(note!, style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 12)),
      ],
    ];
    final arrow = Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withValues(alpha: 0.08)),
      child: const Icon(Icons.arrow_forward_rounded, color: Colors.white, size: 17),
    );
    final act = action ?? arrow;
    return InkWell(
      borderRadius: r,
      onTap: onTap,
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          borderRadius: r,
          border: Border.all(color: color.withValues(alpha: 0.45)),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [color.withValues(alpha: 0.13), color.withValues(alpha: 0.03)],
          ),
        ),
        child: vertical
            ? Stack(children: [
                PositionedDirectional(
                  top: -44,
                  end: -44,
                  child: Container(
                    width: 120,
                    height: 120,
                    decoration: BoxDecoration(shape: BoxShape.circle, color: color.withValues(alpha: 0.10)),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    badge,
                    const SizedBox(height: 14),
                    ...texts,
                    const SizedBox(height: 14),
                    const Spacer(),
                    Align(alignment: AlignmentDirectional.centerEnd, child: act),
                  ]),
                ),
              ])
            : Padding(
                padding: const EdgeInsets.all(14),
                child: Row(children: [
                  badge,
                  const SizedBox(width: 12),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: texts)),
                  const SizedBox(width: 8),
                  act,
                ]),
              ),
      ),
    );
  }
}

/// "Arkadaşını davet et" çağrısı: davet ekranını açar.
class _InviteCta extends StatelessWidget {
  final String title;
  final String detail;
  final VoidCallback onTap;
  final bool vertical;
  const _InviteCta({required this.title, required this.detail, required this.onTap, this.vertical = false});

  @override
  Widget build(BuildContext context) => _ExtraCard(
        icon: Icons.card_giftcard_rounded,
        color: const Color(0xFF7BE0B4),
        title: title,
        detail: detail,
        onTap: onTap,
        vertical: vertical,
      );
}

/// "Okulunuz / kurumunuz için" çağrısı: kurum lisansı ekranını açar.
class _InstitutionCta extends StatelessWidget {
  final VoidCallback onTap;
  final bool vertical;
  const _InstitutionCta({required this.onTap, this.vertical = false});

  @override
  Widget build(BuildContext context) => _ExtraCard(
        icon: Icons.apartment_rounded,
        color: const Color(0xFFE9C46A),
        title: tr('Okulunuz veya kurumunuz için'),
        detail: tr('Kurum lisansıyla tüm öğretmenlere Pro, ortak sınav ve yönetici paneli. Kurum kodunuz varsa buradan girin.'),
        onTap: onTap,
        vertical: vertical,
      );
}

class _LicenseActiveCard extends StatelessWidget {
  final String institution;
  final int daysLeft;
  const _LicenseActiveCard(this.institution, this.daysLeft);

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: NColors.emerald.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: NColors.emerald),
        ),
        child: Column(children: [
          const Icon(Icons.apartment_rounded, color: NColors.emerald, size: 36),
          const SizedBox(height: 8),
          Text(tr('Kurum lisansı etkin · {0}', [institution]),
              textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16)),
          const SizedBox(height: 4),
          Text(tr('{0} gün kaldı', [daysLeft]), style: const TextStyle(color: Colors.white70)),
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

/// Kampanya şeridi: başlık, açıklama ve kalan gün.
class _CampaignBanner extends StatelessWidget {
  final Campaign c;
  const _CampaignBanner(this.c);

  @override
  Widget build(BuildContext context) {
    final left = c.daysLeft(DateTime.now());
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: Container(
          padding: const EdgeInsets.fromLTRB(10, 10, 22, 10),
          decoration: BoxDecoration(
            gradient: LinearGradient(
                colors: [const Color(0xFFE9C46A).withValues(alpha: 0.24), const Color(0xFF7BE0B4).withValues(alpha: 0.12)]),
            borderRadius: BorderRadius.circular(40),
            border: Border.all(color: const Color(0xFFE9C46A).withValues(alpha: 0.7)),
          ),
          child: Row(children: [
            Container(
              width: 52,
              height: 52,
              decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFFE9C46A)),
              child: const Icon(Icons.celebration_rounded, color: NColors.ink, size: 26),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(c.title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15)),
                Text(c.detail, style: TextStyle(color: Colors.white.withValues(alpha: 0.75), fontSize: 12.5)),
              ]),
            ),
            const SizedBox(width: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFFE9C46A).withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(99),
              ),
              child: Text(left <= 1 ? tr('Bugün son gün') : tr('Son {0} gün', [left]),
                  style: const TextStyle(color: Color(0xFFE9C46A), fontWeight: FontWeight.w800, fontSize: 12)),
            ),
          ]),
        ),
      ),
    );
  }
}

/// İlk yıl fiyat güvencesi notu.
class _PriceLock extends StatelessWidget {
  const _PriceLock();

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Icon(Icons.lock_clock_outlined, color: Color(0xFF7BE0B4), size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              tr('Fiyat güvencesi: abone olduğunuz fiyat, aboneliğiniz sürdükçe değişmez. Yeni abonelerin fiyatı her yıl artar.'),
              style: const TextStyle(color: Color(0xFF7BE0B4), fontSize: 12.5, fontWeight: FontWeight.w600, height: 1.35),
            ),
          ),
        ]),
      );
}

/// Ek soru paketi: aylık hak bitince kullanılan, süresi dolmayan soru hakkı.
class _AiPackCard extends StatelessWidget {
  final ProPlan plan;
  final bool busy;
  final VoidCallback onBuy;
  final bool vertical;
  const _AiPackCard({required this.plan, required this.busy, required this.onBuy, this.vertical = false});

  @override
  Widget build(BuildContext context) {
    final credits = AiUsage.instance.credits;
    return _ExtraCard(
      icon: Icons.auto_awesome_rounded,
      color: const Color(0xFFB79CFF),
      title: tr('Ek soru paketi · {0} soru', [aiPackSize]),
      detail: tr('Aylık yapay zekâ hakkınız bitince kullanılır, süresi dolmaz.'),
      note: credits > 0 ? tr('Kalan ek hak: {0} soru', [credits]) : null,
      vertical: vertical,
      action: FilledButton(
        style: FilledButton.styleFrom(
          backgroundColor: const Color(0xFF7C5CE0),
          foregroundColor: Colors.white,
          shape: const StadiumBorder(),
          padding: const EdgeInsets.symmetric(horizontal: 18),
        ),
        onPressed: busy ? null : onBuy,
        child: busy
            ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white))
            : Text(plan.price, style: const TextStyle(fontWeight: FontWeight.w800)),
      ),
    );
  }
}

/// Okul / zümre paketi çağrısı.
class _SchoolPackCta extends StatelessWidget {
  final VoidCallback onTap;
  final bool vertical;
  const _SchoolPackCta({required this.onTap, this.vertical = false});

  @override
  Widget build(BuildContext context) => _ExtraCard(
        icon: Icons.groups_rounded,
        color: const Color(0xFF5EC8E5),
        title: tr('Okul / zümre paketi'),
        detail: tr('5 ve daha fazla öğretmene %45\'e varan indirim. Okulunuza teklif isteyin.'),
        onTap: onTap,
        vertical: vertical,
      );
}
