import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/legal.dart';
import '../core/license.dart';
import '../l10n/l10n.dart';
import '../main.dart';
import 'admin_panel_screen.dart';
import 'theme.dart';
import 'widgets.dart';

/// Kurum lisansı: kod girme, durum ve kurumlar için bilgi.
class LicenseScreen extends StatefulWidget {
  const LicenseScreen({super.key});

  @override
  State<LicenseScreen> createState() => _LicenseScreenState();
}

class _LicenseScreenState extends State<LicenseScreen> {
  final _code = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _activate() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final l = await InstitutionLicense.verify(_code.text);
    if (!mounted) return;
    setState(() => _busy = false);
    if (l == null) {
      setState(() => _error = tr('Kod geçersiz. Kodu eksiksiz yapıştırdığınızdan emin olun.'));
      return;
    }
    if (!l.activeAt(DateTime.now())) {
      setState(() => _error = tr('Bu kodun süresi {0} tarihinde doldu.', [L10n.date(l.until)]));
      return;
    }
    StoreScope.of(context).setLicense(l);
    _code.clear();
    toast(context, l.admin ? tr('Kurum lisansı etkin. Yönetici paneli açıldı.') : tr('Kurum lisansı etkin. Tüm Pro özellikleri açıldı.'));
  }

  Future<void> _paste() async {
    final d = await Clipboard.getData(Clipboard.kTextPlain);
    if (d?.text != null) setState(() => _code.text = d!.text!.trim());
  }

  Future<void> _remove() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Kurum lisansı kaldırılsın mı?')),
        content: Text(tr('Verileriniz silinmez; yalnızca lisansla açılan özellikler kilitlenir.')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Vazgeç'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Kaldır'))),
        ],
      ),
    );
    if (ok == true && mounted) StoreScope.of(context).setLicense(null);
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final t = Theme.of(context);
    final muted = t.colorScheme.onSurface.withValues(alpha: 0.6);
    final l = store.license;
    return Scaffold(
      appBar: AppBar(title: Text(tr('Kurum lisansı'))),
      body: Watermark(
        child: ListView(padding: EdgeInsets.fromLTRB(20, 8, 20, 40 + MediaQuery.paddingOf(context).bottom), children: [
          if (l != null)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    IconBadge(Icons.apartment_rounded, color: store.hasLicense ? NColors.emerald : NColors.coral),
                    const SizedBox(width: 12),
                    Expanded(child: Text(l.institution, style: t.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800))),
                  ]),
                  const SizedBox(height: 12),
                  Text(store.hasLicense
                      ? tr('Geçerlilik: {0} tarihine kadar ({1} gün)', [L10n.date(l.until), l.daysLeft(DateTime.now())])
                      : tr('Süresi {0} tarihinde doldu. Kurumunuzdan yeni kod isteyin.', [L10n.date(l.until)])),
                  Text(l.admin ? tr('Rol: kurum yöneticisi') : tr('Rol: öğretmen'), style: TextStyle(color: muted)),
                  if (l.seats > 0) Text(tr('Lisanstaki öğretmen sayısı: {0}', [l.seats]), style: TextStyle(color: muted)),
                  Text(tr('Raporlarda kurum adı lisanstan gelir.'), style: TextStyle(color: muted)),
                  const SizedBox(height: 12),
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    if (store.canUseAdminPanel)
                      FilledButton.icon(
                        onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AdminPanelScreen())),
                        icon: const Icon(Icons.dashboard_customize_outlined),
                        label: Text(tr('Yönetici paneli')),
                      ),
                    OutlinedButton(onPressed: _remove, child: Text(tr('Lisansı kaldır'))),
                  ]),
                ]),
              ),
            ),
          SectionTitle(l == null ? tr('Kurum kodunu girin') : tr('Yeni kod girin')),
          Text(tr('Kurumunuzun yöneticisinden aldığınız kodu yapıştırın. Kod internetsiz doğrulanır; hiçbir bilginiz dışarı gönderilmez.'),
              style: TextStyle(color: muted)),
          const SizedBox(height: 12),
          TextField(
            controller: _code,
            minLines: 2,
            maxLines: 4,
            decoration: InputDecoration(
              labelText: tr('Kurum kodu'),
              hintText: 'NTC1.…',
              errorText: _error,
              suffixIcon: IconButton(tooltip: tr('Yapıştır'), onPressed: _paste, icon: const Icon(Icons.content_paste_rounded)),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: _busy ? null : _activate,
            child: _busy
                ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : Text(tr('Etkinleştir')),
          ),
          SectionTitle(tr('Kurum lisansında neler var?')),
          for (final (icon, title, detail) in [
            (Icons.workspace_premium_outlined, tr('Tüm öğretmenlere Pro'), tr('Karne, dönem raporu, resmi başlık, veliye gönderme, grafikler')),
            (Icons.hub_outlined, tr('Ortak sınav'), tr('Zümre aynı sınavı tüm şubelerde okur; sonuçlar tek raporda birleşir')),
            (Icons.dashboard_customize_outlined, tr('Yönetici paneli'), tr('Müdür veya bölüm başkanı tüm şubeleri tek ekranda görür')),
            (Icons.account_balance_outlined, tr('Kurum adı sabit'), tr('Tüm raporlarda aynı resmi kurum adı')),
            (Icons.receipt_long_outlined, tr('Faturayla ödeme'), tr('Kurum adına yıllık fatura; kart gerekmez')),
          ])
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: IconBadge(icon),
              title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text(detail),
            ),
          const SizedBox(height: 8),
          if (contactEmail.isNotEmpty)
            OutlinedButton.icon(
            onPressed: () => launchUrl(
                Uri(
                  scheme: 'mailto',
                  path: contactEmail,
                  query: 'subject=${Uri.encodeComponent(tr('Netice kurum lisansı teklifi'))}',
                ),
                mode: LaunchMode.externalApplication),
            icon: const Icon(Icons.mail_outline_rounded),
            label: Text(tr('Kurumunuz için teklif isteyin')),
          ),
        ]),
      ),
    );
  }
}
