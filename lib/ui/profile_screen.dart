import 'package:material_ui/material_ui.dart';
import '../core/pro.dart';
import '../core/store.dart';

import '../main.dart';
import 'account_card.dart';
import 'admin_panel_screen.dart';
import 'common_exam_ui.dart';
import 'invite_screen.dart';
import 'lan_sync_screen.dart';
import 'license_screen.dart';
import 'pro_screen.dart';
import 'school_screen.dart';
import 'service_cards.dart';
import 'download_links.dart';
import 'section_icons.dart';
import 'theme.dart';
import 'why_screen.dart';
import 'widgets.dart';
import '../l10n/l10n.dart';
import '../core/ads.dart';
import 'ad_slot.dart';
import 'sample_reports_screen.dart';

/// Profil sekmesi: öğretmen kimliği, Netice Pro durumu, Google hesabı ve
/// yedek, okul bilgileri tek yerde.
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final school = store.school;
    final email = store.googleEmail;
    final name = [store.googleName, school.teacher]
        .whereType<String>()
        .map((s) => s.trim())
        .firstWhere((s) => s.isNotEmpty, orElse: () => tr('Öğretmen'));

    final hero = HeroPanel(
          child: Row(children: [
            Container(
              width: 64,
              height: 64,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: emeraldGradient,
                border: Border.all(color: Colors.white.withValues(alpha: 0.5), width: 2),
              ),
              child: Text(name.characters.first.toUpperCase(),
                  style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w800)),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Flexible(
                    child: Text(name,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
                  ),
                  if (store.isPro) ...[const SizedBox(width: 8), const ProBadge()],
                ]),
                const SizedBox(height: 4),
                Text(email ?? tr('Google hesabı bağlı değil'),
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 13)),
                if (!school.isEmpty) ...[
                  const SizedBox(height: 2),
                  Text(school.name,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.55), fontSize: 12.5)),
                ],
              ]),
            ),
          ]),
        );
    final proSub = store.hasLicense
        ? tr('Kurum lisansıyla etkin: {0}', [store.license!.institution])
        : store.hasSubscription
            ? tr('Aboneliğiniz etkin. Teşekkürler!')
            : store.subscriptionOnOtherDevice
            ? tr('Pro başka bir cihazda açık · buraya almak için dokunun')
            : store.inTrial
                ? tr('Ücretsiz deneme: {0} gün kaldı', [store.trialDaysLeft])
                : tr('Dönem raporu, karne, veliye gönderme ve daha fazlası');
    void push(Widget w, {bool dialog = false}) =>
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => w, fullscreenDialog: dialog));
    if (wideLayout(context)) {
      return Scaffold(
        appBar: AppBar(title: Text(tr('Profil'))),
        body: LayoutBuilder(builder: (context, c) {
          final cols = serviceColumns(c.maxWidth - 32);
          return ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 40), children: [
            hero,
            const AdSlot.card(AdPage.profile, padding: EdgeInsets.only(top: 14)),
            SectionTitle(tr('Netice Pro ve kurum')),
            ServiceGrid(columns: cols, children: [
              ServiceCard(section: Section.pro, title: tr('Netice Pro'), subtitle: proSub, hero: true,
                  onTap: () => push(const ProScreen(), dialog: true)),
              if (!ProService.salesDisabled)
                ServiceCard(icon: Icons.card_giftcard_rounded, color: NColors.deepEmerald, title: tr('Arkadaşını davet et'),
                    subtitle: tr('Arkadaşınıza %15 indirim, size 1 ay ek Pro'), onTap: () => push(const InviteScreen())),
              ServiceCard(section: Section.why, title: tr('Neden Netice?'),
                  subtitle: tr('Benzer uygulamalarla özellik ve fiyat karşılaştırması'), onTap: () => push(const WhyNeticeScreen())),
              ServiceCard(section: Section.samples, title: tr('Örnek raporlar'),
                  subtitle: tr('Netice\'nin hazırladığı tüm raporları örnekleriyle görün'), onTap: () => push(const SampleReportsScreen())),
              ServiceCard(section: Section.school, title: tr('Kurum bilgileri'),
                  subtitle: school.isEmpty ? tr('Raporlarda resmi başlık için girin') : school.name,
                  onTap: () => push(const SchoolScreen())),
              ServiceCard(icon: Icons.apartment_rounded, color: const Color(0xFFB7791F), title: tr('Kurum lisansı'),
                  subtitle: store.hasLicense
                      ? tr('{0} · {1} gün kaldı', [store.license!.institution, store.license!.daysLeft(DateTime.now())])
                      : tr('Kurum kodunu girin ya da kurumunuz için bilgi alın'),
                  onTap: () => push(const LicenseScreen())),
              ServiceCard(icon: Icons.dashboard_customize_rounded, color: const Color(0xFF4F46E5), title: tr('Yönetici paneli'),
                  subtitle: tr('Tüm şubeler, ortak sınavlar ve destek gereken öğrenciler'),
                  onTap: () => AdminPanelScreen.open(context)),
              ServiceCard(icon: Icons.move_to_inbox_rounded, color: const Color(0xFF0369A1), title: tr('Ortak sınav dosyası aç'),
                  subtitle: tr('Başka öğretmenden gelen sınav veya sonuç dosyası'), onTap: () => importNeticeFile(context)),
              ServiceCard(icon: Icons.wifi_rounded, color: const Color(0xFF0E7490), title: tr('Wi-Fi ile ortak sınav al'),
                  subtitle: tr('Aynı ağdaki öğretmenden, internetsiz ve dosyasız'), onTap: () => openLanSync(context)),
            ]),
            SectionTitle(tr('Netice\'yi indirin')),
            const RoundedPanel(child: DownloadLinksPanel()),
            SectionTitle(tr('Hesap')),
            const RoundedPanel(child: AccountCard()),
          ]);
        }),
      );
    }
    return Scaffold(
      appBar: AppBar(title: Text(tr('Profil'))),
      body: ListView(padding: EdgeInsets.fromLTRB(16, 8, 16, 40 + MediaQuery.paddingOf(context).bottom), children: [
        hero,
        const AdSlot.card(AdPage.profile, padding: EdgeInsets.only(top: 14)),
        SectionTitle(tr('Netice Pro')),
        Card(
          clipBehavior: Clip.antiAlias,
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            leading: const IconBadge(Icons.workspace_premium_rounded, color: Color(0xFFD4A24C)),
            title: Text(tr('Netice Pro'), style: const TextStyle(fontWeight: FontWeight.w800)),
            subtitle: Text(store.hasLicense
                ? tr('Kurum lisansıyla etkin: {0}', [store.license!.institution])
                : store.hasSubscription
                ? tr('Aboneliğiniz etkin. Teşekkürler!')
                : store.subscriptionOnOtherDevice
                ? tr('Pro başka bir cihazda açık · buraya almak için dokunun')
                : store.hasBonusPro
                ? tr('Davet ödülü Pro: {0} tarihine kadar', [L10n.date(store.bonusProUntil!)])
                : store.hasTermPass
                ? tr('Sınav dönemi paketi: {0} tarihine kadar', [L10n.date(store.termPassUntil!)])
                : store.inTrial
                    ? tr('Ücretsiz deneme: {0} gün kaldı', [store.trialDaysLeft])
                    : AppStore.proFreeOnThisPlatform
                        ? tr('Bilgisayar sürümünde Pro özellikleri şimdilik açık')
                        : tr('Dönem raporu, karne, veliye gönderme ve daha fazlası')),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ProScreen(), fullscreenDialog: true)),
          ),
        ),
        if (!ProService.salesDisabled) const SizedBox(height: 10),
        if (!ProService.salesDisabled)
        Card(
          clipBehavior: Clip.antiAlias,
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            leading: const IconBadge(Icons.card_giftcard_rounded, color: NColors.emerald),
            title: Text(tr('Arkadaşını davet et'), style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text(tr('Arkadaşınıza %15 indirim, size 1 ay ek Pro')),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const InviteScreen())),
          ),
        ),
        const SizedBox(height: 10),
        const WhyNeticeBanner(),
        const SizedBox(height: 10),
        const SampleReportsCard(),
        SectionTitle(tr('Netice\'yi indirin')),
        const RoundedPanel(child: DownloadLinksPanel()),
        SectionTitle(tr('Hesap')),
        const AccountCard(),
        SectionTitle(tr('Kurum')),
        Card(
          clipBehavior: Clip.antiAlias,
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            leading: IconBadge(Icons.account_balance_outlined, color: school.isEmpty ? NColors.amber : NColors.emerald),
            title: Text(tr('Kurum bilgileri'), style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text(school.isEmpty ? tr('Raporlarda resmi başlık için girin') : school.name),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SchoolScreen())),
          ),
        ),
        const SizedBox(height: 10),
        Card(
          clipBehavior: Clip.antiAlias,
          child: Column(children: [
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              leading: IconBadge(Icons.apartment_rounded, color: store.hasLicense ? NColors.emerald : const Color(0xFFD4A24C)),
              title: Text(tr('Kurum lisansı'), style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text(store.hasLicense
                  ? tr('{0} · {1} gün kaldı', [store.license!.institution, store.license!.daysLeft(DateTime.now())])
                  : tr('Kurum kodunu girin ya da kurumunuz için bilgi alın')),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const LicenseScreen())),
            ),
            const Divider(height: 1),
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              leading: const IconBadge(Icons.dashboard_customize_outlined),
              title: Text(tr('Yönetici paneli'), style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text(tr('Tüm şubeler, ortak sınavlar ve destek gereken öğrenciler')),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => AdminPanelScreen.open(context),
            ),
            const Divider(height: 1),
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              leading: const IconBadge(Icons.move_to_inbox_outlined),
              title: Text(tr('Ortak sınav dosyası aç'), style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text(tr('Başka öğretmenden gelen sınav veya sonuç dosyası')),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => importNeticeFile(context),
            ),
            const Divider(height: 1),
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              leading: const IconBadge(Icons.wifi_rounded),
              title: Text(tr('Wi-Fi ile ortak sınav al'), style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text(tr('Aynı ağdaki öğretmenden, internetsiz ve dosyasız')),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => openLanSync(context),
            ),
          ]),
        ),
      ]),
    );
  }
}
