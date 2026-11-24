import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/legal.dart';
import '../core/pro.dart';
import '../core/school_package.dart';
import '../l10n/l10n.dart';
import '../main.dart';
import 'license_screen.dart';
import 'theme.dart';
import 'widgets.dart';

/// Okul / zümre paketi: öğretmen sayısına göre indirimli fiyat ve teklif isteği.
class SchoolOfferScreen extends StatefulWidget {
  const SchoolOfferScreen({super.key});

  static Future<void> open(BuildContext context) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SchoolOfferScreen()));

  @override
  State<SchoolOfferScreen> createState() => _SchoolOfferScreenState();
}

class _SchoolOfferScreenState extends State<SchoolOfferScreen> {
  final _school = TextEditingController();
  final _city = TextEditingController();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  int _teachers = 10;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_school.text.isEmpty && _city.text.isEmpty) {
      final s = StoreScope.of(context).school;
      _school.text = s.name;
      _city.text = [s.district, s.province].where((x) => x.trim().isNotEmpty).join(' / ');
      _name.text = s.teacher;
    }
  }

  @override
  void dispose() {
    for (final c in [_school, _city, _name, _phone]) {
      c.dispose();
    }
    super.dispose();
  }

  String get _yearly => ProService.yearlyPriceText();

  static String _line(String label, String value) => '$label: $value';

  String _mailBody() {
    final custom = _teachers >= SchoolPackage.customFrom;
    return [
      tr('Merhaba, okulumuz için Netice okul paketi teklifi rica ediyoruz.'),
      '',
      _line(tr('Kurum'), _school.text.trim()),
      _line(tr('İl / ilçe'), _city.text.trim()),
      _line(tr('Öğretmen sayısı'), '$_teachers'),
      _line(tr('Yetkili'), _name.text.trim()),
      _line(tr('Telefon'), _phone.text.trim()),
      '',
      if (custom)
        tr('Öğretmen sayımız fazla olduğu için özel teklif bekliyoruz.')
      else
        tr('Uygulamada görünen fiyat: öğretmen başı {0}, toplam {1} (%{2} indirim).', [
          SchoolPackage.perTeacherText(_yearly, _teachers),
          SchoolPackage.totalText(_yearly, _teachers),
          (SchoolPackage.discountFor(_teachers) * 100).round(),
        ]),
    ].join('\n');
  }

  Future<void> _send() async {
    if (_school.text.trim().isEmpty) {
      toast(context, tr('Kurum adını yazın.'));
      return;
    }
    final body = _mailBody();
    final uri = SchoolPackage.offerMail(subject: tr('Netice okul paketi teklifi: {0}', [_school.text.trim()]), body: body);
    var ok = false;
    try {
      ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {}
    if (!mounted) return;
    if (!ok) {
      await Clipboard.setData(ClipboardData(text: body));
      if (!mounted) return;
      toast(context, tr('E-posta uygulaması açılamadı. Teklif metni kopyalandı; {0} adresine gönderebilirsiniz.', [contactEmail]));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final muted = t.colorScheme.onSurface.withValues(alpha: 0.6);
    final custom = _teachers >= SchoolPackage.customFrom;
    final pct = (SchoolPackage.discountFor(_teachers) * 100).round();
    return Scaffold(
      appBar: AppBar(title: Text(tr('Okul / zümre paketi'))),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: FilledButton.icon(
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
            onPressed: _send,
            icon: const Icon(Icons.mail_outline_rounded),
            label: Text(tr('Okulunuza teklif isteyin')),
          ),
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 32), children: [
            Text(
              tr('Aynı okuldan {0} ve daha fazla öğretmen birlikte alırsa her öğretmene Pro indirimli olur. Ödeme okul adına tek faturayla yapılır, öğretmenler uygulamaya kurum kodunu girer.',
                  [SchoolPackage.minTeachers]),
              style: TextStyle(color: muted),
            ),
            SectionTitle(tr('Fiyatlar')),
            Card(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Column(children: [
                  for (var i = 0; i < SchoolPackage.tiers.length; i++)
                    _TierRow(
                      label: i + 1 < SchoolPackage.tiers.length
                          ? tr('{0}–{1} öğretmen', [SchoolPackage.tiers[i].minTeachers, SchoolPackage.tiers[i + 1].minTeachers - 1])
                          : tr('{0}–{1} öğretmen', [SchoolPackage.tiers[i].minTeachers, SchoolPackage.customFrom - 1]),
                      discount: tr('%{0} indirim', [(SchoolPackage.tiers[i].discount * 100).round()]),
                      price: tr('öğretmen başı {0}', [SchoolPackage.perTeacherText(_yearly, SchoolPackage.tiers[i].minTeachers)]),
                    ),
                  _TierRow(
                    label: tr('{0} ve üzeri', [SchoolPackage.customFrom]),
                    discount: '',
                    price: tr('Özel teklif'),
                  ),
                ]),
              ),
            ),
            SectionTitle(tr('Okulunuz')),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  TextField(controller: _school, decoration: InputDecoration(labelText: tr('Kurum adı'))),
                  const SizedBox(height: 10),
                  TextField(controller: _city, decoration: InputDecoration(labelText: tr('İl / ilçe'))),
                  const SizedBox(height: 10),
                  TextField(controller: _name, decoration: InputDecoration(labelText: tr('Yetkili adı soyadı'))),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _phone,
                    keyboardType: TextInputType.phone,
                    decoration: InputDecoration(labelText: tr('Telefon (isteğe bağlı)')),
                  ),
                  const SizedBox(height: 16),
                  Row(children: [
                    Expanded(child: Text(tr('Öğretmen sayısı'), style: const TextStyle(fontWeight: FontWeight.w700))),
                    IconButton.outlined(
                      onPressed: _teachers > SchoolPackage.minTeachers ? () => setState(() => _teachers--) : null,
                      icon: const Icon(Icons.remove_rounded),
                    ),
                    SizedBox(
                      width: 56,
                      child: Text('$_teachers', textAlign: TextAlign.center, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                    ),
                    IconButton.outlined(
                      onPressed: _teachers < 500 ? () => setState(() => _teachers++) : null,
                      icon: const Icon(Icons.add_rounded),
                    ),
                  ]),
                  Slider(
                    min: SchoolPackage.minTeachers.toDouble(),
                    max: 100,
                    divisions: 100 - SchoolPackage.minTeachers,
                    value: _teachers.clamp(SchoolPackage.minTeachers, 100).toDouble(),
                    onChanged: (v) => setState(() => _teachers = v.round()),
                  ),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: NColors.emerald.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: custom
                        ? Text(tr('{0} öğretmen için size özel fiyat çıkaracağız.', [_teachers]),
                            style: const TextStyle(fontWeight: FontWeight.w700))
                        : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(tr('Öğretmen başı {0} · %{1} indirim', [SchoolPackage.perTeacherText(_yearly, _teachers), pct]),
                                style: const TextStyle(fontWeight: FontWeight.w700)),
                            const SizedBox(height: 4),
                            Text(tr('Toplam: {0} / yıl', [SchoolPackage.totalText(_yearly, _teachers)]),
                                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: NColors.emerald)),
                          ]),
                  ),
                ]),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              tr('"Okulunuza teklif isteyin" e-posta uygulamanızı açar; bilgileriniz yalnız bize gönderilir. Teklif onaylanınca okulunuza kurum kodu verilir.'),
              style: TextStyle(color: muted, fontSize: 13),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const LicenseScreen())),
                icon: const Icon(Icons.vpn_key_outlined),
                label: Text(tr('Kurum kodunuz var mı? Buradan girin')),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

class _TierRow extends StatelessWidget {
  final String label;
  final String discount;
  final String price;
  const _TierRow({required this.label, required this.discount, required this.price});

  @override
  Widget build(BuildContext context) => ListTile(
        dense: true,
        title: Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: discount.isEmpty ? null : Text(discount, style: const TextStyle(color: NColors.emerald, fontWeight: FontWeight.w600)),
        trailing: Text(price, style: const TextStyle(fontWeight: FontWeight.w700)),
      );
}
