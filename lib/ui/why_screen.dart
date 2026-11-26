import 'package:material_ui/material_ui.dart';

import '../core/pro.dart';
import '../l10n/l10n.dart';
import 'new_exam_screen.dart';
import 'pro_screen.dart';
import 'rate_share.dart';
import 'section_icons.dart';
import 'theme.dart';
import 'widgets.dart';

/// Karşılaştırma tablosunda bir hücrenin durumu.
enum Has { yes, part, no }

/// "Neden Netice?" karşılaştırma satırı: özellik ve dört sütunun durumu
/// (Netice, yabancı optik uygulamaları, yayınevi uygulamaları, kurumsal
/// okuma programları). Kaynak: Kasım 2026 rakip karşılaştırma raporu.
class WhyRow {
  final String feature;
  final List<Has> cells;
  const WhyRow(this.feature, this.cells);
}

List<WhyRow> whyRows() => [
  WhyRow(tr('Telefon kamerasıyla okuma'), const [Has.yes, Has.yes, Has.yes, Has.part]),
  WhyRow(tr('Okuma sınırı yok, okuma ücretsiz'), const [Has.yes, Has.no, Has.yes, Has.no]),
  WhyRow(tr('Kendi formunuzu yazdırma'), const [Has.yes, Has.yes, Has.no, Has.yes]),
  WhyRow(tr('Başka firma ve yayınevi formlarını okuma'), const [Has.yes, Has.no, Has.no, Has.part]),
  WhyRow(tr('Hesap açmadan kullanım'), const [Has.yes, Has.no, Has.no, Has.no]),
  WhyRow(tr('İnternetsiz çalışma'), const [Has.yes, Has.yes, Has.part, Has.part]),
  WhyRow(tr('A–H kitapçık türleri'), const [Has.yes, Has.part, Has.no, Has.part]),
  WhyRow(tr('Soru bankası ve kitapçık hazırlama'), const [Has.yes, Has.no, Has.no, Has.no]),
  WhyRow(tr('Yapay zekâ ile ders notundan soru'), const [Has.yes, Has.no, Has.no, Has.no]),
  WhyRow(tr('Madde analizi ve grafikler'), const [Has.yes, Has.yes, Has.no, Has.yes]),
  WhyRow(tr('Kurum türüne göre resmi rapor'), const [Has.yes, Has.no, Has.no, Has.no]),
  WhyRow(tr('Ülkeye göre not sistemi'), const [Has.yes, Has.no, Has.no, Has.part]),
  WhyRow(tr('Karneyi velilere toplu gönderme'), const [Has.yes, Has.no, Has.no, Has.no]),
  WhyRow(tr('Kişiye özel tekrar testi'), const [Has.yes, Has.no, Has.no, Has.no]),
  WhyRow(tr('Telefon ve bilgisayar birlikte'), const [Has.yes, Has.part, Has.no, Has.part]),
  WhyRow(tr('15 dil'), const [Has.yes, Has.part, Has.no, Has.no]),
];

/// Netice'yi seçmek için öne çıkan nedenler (simge, başlık, açıklama).
List<(IconData, Color, Color, String, String)> whyReasons() => [
  (
    Icons.all_inclusive_rounded,
    const Color(0xFFFB7185),
    const Color(0xFFBE123C),
    tr('Bir uygulama, bütün sınav süreci'),
    tr('Soru bankası, kitapçık, optik form, okuma, analiz ve karne bir arada. Başka program gerekmez.'),
  ),
  (
    Icons.document_scanner_rounded,
    const Color(0xFF34D399),
    const Color(0xFF047857),
    tr('Saniyeler içinde okuma'),
    tr('Telefonla seri okuma, bilgisayarda PDF ile toplu okuma. Okuma her zaman ücretsiz ve sınırsız.'),
  ),
  (
    Icons.account_balance_rounded,
    const Color(0xFFF59E0B),
    const Color(0xFFB45309),
    tr('Her kurumun resmi diliyle'),
    tr('Okul, polis akademisi, askerî okul, üniversite, kurs: raporlar kurumunuzun başlığı ve imza alanıyla çıkar.',
    ),
  ),
  (
    Icons.lock_rounded,
    const Color(0xFF8391E0),
    const Color(0xFF0F1B3D),
    tr('Veriniz sizde kalır'),
    tr('Hesap açmadan, internet olmadan çalışır. Öğrenci bilgileri cihazınızdan çıkmaz.'),
  ),
  (
    Icons.auto_awesome_rounded,
    const Color(0xFFA78BFA),
    const Color(0xFF6D28D9),
    tr('Yapay zekâ yanınızda'),
    tr('Kendi ders notunuzdan dakikalar içinde soru üretin, her öğrenciye kendi yanlışlarından tekrar testi hazırlayın.',
    ),
  ),
  (
    Icons.translate_rounded,
    const Color(0xFF22D3EE),
    const Color(0xFF0E7490),
    tr('15 dil, her ülkenin not sistemi'),
    tr('Türkçeden Korecye 15 dilde çalışır; notları ülkenizin sistemine göre verir.'),
  ),
  (
    Icons.family_restroom_rounded,
    const Color(0xFFF472B6),
    const Color(0xFFBE185D),
    tr('Veliye tek dokunuşla'),
    tr('Karneyi ve çalışması gereken konuları velilere toplu gönderin.'),
  ),
  (
    Icons.devices_rounded,
    const Color(0xFF60A5FA),
    const Color(0xFF1D4ED8),
    tr('Telefon ve bilgisayar birlikte'),
    tr('iPhone, Android, Windows ve Mac. Aynı Wi-Fi ağında internetsiz aktarım.'),
  ),
];

/// Kısa, akılda kalan sloganlar.
List<String> whySlogans() => [
  tr('Bir uygulama. Bütün sınav süreci.'),
  tr('İnternet yok mu? Sorun değil.'),
  tr('Veriniz sizde kalır.'),
  tr('Her kurumun resmi diliyle.'),
  tr('Okumak ücretsiz, sınır yok.'),
];

/// "Neden Netice?" ekranı: nedenler, benzer uygulamalarla karşılaştırma,
/// fiyat ve sloganlar. Telefonda tek sütun, geniş ekranda iki sütun.
class WhyNeticeScreen extends StatelessWidget {
  const WhyNeticeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    final wide = w >= 900;
    final pad = wide ? 28.0 : 16.0;
    return Scaffold(
      appBar: AppBar(title: Text(tr('Neden Netice?'))),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1100),
            child: ListView(
              padding: EdgeInsets.fromLTRB(pad, 8, pad, 32),
              children: [
                const _WhyHero(),
                SectionTitle(tr('Öne çıkan 8 neden')),
                _ReasonGrid(columns: w >= 1100 ? 4 : (w >= 640 ? 2 : 1)),
                SectionTitle(tr('Benzer uygulamalarla karşılaştırma')),
                const _CompareTable(),
                const SizedBox(height: 12),
                const _OwnFormCallout(),
                if (!ProService.salesDisabled) ...[SectionTitle(tr('Fiyat karşılaştırması')), const _PriceCard()],
                const SizedBox(height: 20),
                const _SloganBand(),
                const SizedBox(height: 20),
                const _Actions(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _WhyHero extends StatelessWidget {
  const _WhyHero();

  @override
  Widget build(BuildContext context) {
    final stats = [
      ('15', tr('dil')),
      ('8', tr('kitapçık türü')),
      ('4', tr('platform')),
      ('0', tr('hesap, internet gerekmez')),
    ];
    return HeroPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const AppLogo(size: 52),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  tr('Neden Netice?'),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Text(
            tr('Kâğıttan sonuca, saniyeler içinde.'),
            style: const TextStyle(color: Color(0xFF6EE7B7), fontSize: 20, fontWeight: FontWeight.w800, height: 1.25),
          ),
          const SizedBox(height: 8),
          Text(
            tr('Soru yazmaktan veliye karneye kadar bütün sınav süreci tek uygulamada. Benzer uygulamalar bu işin yalnız bir parçasını yapar.',
            ),
            style: TextStyle(color: Colors.white.withValues(alpha: 0.78), fontSize: 14, height: 1.45),
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final (n, label) in stats)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.09),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        n,
                        style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(width: 8),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 140),
                        child: Text(
                          label,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.8),
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ReasonGrid extends StatelessWidget {
  final int columns;
  const _ReasonGrid({required this.columns});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final muted = t.colorScheme.onSurface.withValues(alpha: 0.68);
    final reasons = whyReasons();
    Widget card((IconData, Color, Color, String, String) r) => Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            GlossyIcon(r.$1, r.$2, r.$3, size: 46),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(r.$4, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5)),
                  const SizedBox(height: 4),
                  Text(r.$5, style: TextStyle(color: muted, fontSize: 13.5, height: 1.4)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    final rows = <Widget>[];
    for (var i = 0; i < reasons.length; i += columns) {
      final chunk = reasons.skip(i).take(columns).toList();
      rows.add(
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var j = 0; j < columns; j++) ...[
                if (j > 0) const SizedBox(width: 10),
                Expanded(child: j < chunk.length ? card(chunk[j]) : const SizedBox()),
              ],
            ],
          ),
        ),
      );
      rows.add(const SizedBox(height: 10));
    }
    return Column(children: rows);
  }
}

/// Netice ve üç benzer uygulama grubunu yan yana gösteren tablo.
class _CompareTable extends StatelessWidget {
  const _CompareTable();

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final dark = t.brightness == Brightness.dark;
    final muted = t.colorScheme.onSurface.withValues(alpha: 0.65);
    final narrow = MediaQuery.sizeOf(context).width < 640;
    final colW = narrow ? 54.0 : 120.0;
    final heads = [
      tr('Netice'),
      tr('Yabancı optik uygulamaları'),
      tr('Yayınevi uygulamaları'),
      tr('Kurumsal okuma programları'),
    ];
    final short = [tr('Netice'), tr('Yabancı'), tr('Yayınevi'), tr('Kurumsal')];
    final neticeBg = NColors.emerald.withValues(alpha: dark ? 0.16 : 0.09);

    Widget mark(Has h, {bool netice = false}) => switch (h) {
      Has.yes => Container(
        width: 26,
        height: 26,
        decoration: BoxDecoration(
          color: netice ? NColors.buttonBg(dark) : NColors.emerald.withValues(alpha: 0.85),
          shape: BoxShape.circle,
        ),
        child: const Icon(Icons.check_rounded, size: 17, color: NColors.onGreen),
      ),
      Has.part => Container(
        width: 26,
        height: 26,
        decoration: BoxDecoration(color: NColors.amber.withValues(alpha: 0.22), shape: BoxShape.circle),
        child: Icon(Icons.remove_rounded, size: 17, color: NColors.on(context, const Color(0xFFB7791F))),
      ),
      Has.no => Container(
        width: 26,
        height: 26,
        decoration: BoxDecoration(color: t.colorScheme.onSurface.withValues(alpha: 0.07), shape: BoxShape.circle),
        child: Icon(Icons.close_rounded, size: 16, color: t.colorScheme.onSurface.withValues(alpha: 0.4)),
      ),
    };

    Widget cell(Widget child, int i) => Container(
      width: colW,
      color: i == 0 ? neticeBg : null,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: child,
    );

    final rows = whyRows();
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
                    child: Align(
                      alignment: AlignmentDirectional.bottomStart,
                      child: Text(
                        tr('Özellik'),
                        style: TextStyle(color: muted, fontWeight: FontWeight.w700, fontSize: 12.5),
                      ),
                    ),
                  ),
                ),
                for (var i = 0; i < 4; i++)
                  Container(
                    width: colW,
                    padding: const EdgeInsets.fromLTRB(4, 12, 4, 10),
                    decoration: i == 0 ? BoxDecoration(gradient: dark ? nightEmeraldGradient : emeraldGradient) : null,
                    alignment: Alignment.bottomCenter,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (i == 0) const AppLogo(size: 22),
                        if (i == 0) const SizedBox(height: 4),
                        if (narrow)
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              short[i],
                              maxLines: 1,
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w800,
                                color: i == 0 ? NColors.onGreen : muted,
                              ),
                            ),
                          )
                        else
                          Text(
                            heads[i],
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: narrow ? 10.5 : 12,
                              fontWeight: FontWeight.w800,
                              color: i == 0 ? NColors.onGreen : muted,
                              height: 1.2,
                            ),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          for (var r = 0; r < rows.length; r++)
            Container(
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: t.dividerColor.withValues(alpha: 0.5))),
              ),
              child: IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(14, 9, 6, 9),
                        child: Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: Text(
                            rows[r].feature,
                            style: TextStyle(fontSize: narrow ? 12.5 : 14, fontWeight: FontWeight.w600, height: 1.3),
                          ),
                        ),
                      ),
                    ),
                    for (var i = 0; i < 4; i++) cell(mark(rows[r].cells[i], netice: i == 0), i),
                  ],
                ),
              ),
            ),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: t.dividerColor.withValues(alpha: 0.5))),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 14,
                  runSpacing: 6,
                  children: [
                    for (final (h, label) in [(Has.yes, tr('Var')), (Has.part, tr('Kısmen')), (Has.no, tr('Yok'))])
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Transform.scale(scale: 0.75, child: mark(h)),
                          const SizedBox(width: 4),
                          Text(label, style: TextStyle(color: muted, fontSize: 12.5)),
                        ],
                      ),
                  ],
                ),
                if (narrow) ...[
                  const SizedBox(height: 8),
                  for (var i = 1; i < 4; i++)
                    Text('${short[i]}: ${heads[i]}', style: TextStyle(color: muted, fontSize: 12, height: 1.4)),
                ],
                const SizedBox(height: 8),
                Text(
                  tr('Karşılaştırma, Kasım 2026\'da benzer uygulamaların mağaza ve ürün sayfalarındaki bilgilere dayanır. Yayınevi uygulamaları yalnız kendi formlarını okur.',
                  ),
                  style: TextStyle(color: muted, fontSize: 12, height: 1.4),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PriceCard extends StatelessWidget {
  const _PriceCard();

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final muted = t.colorScheme.onSurface.withValues(alpha: 0.68);
    final plans = ProService.fallbackPlans;
    final yearly = plans.first;
    final items = [
      (tr('Netice'), tr('Okuma ücretsiz · Pro {0}', [yearly.price]), yearly.note, true),
      (
        tr('Yabancı optik uygulamaları'),
        tr('Ücretsiz sürümde ayda 100 kâğıt sınırı'),
        tr('Soru bankası, karne ve resmi rapor yok'),
        false,
      ),
      (tr('Yayınevi uygulamaları'), tr('Ücretsiz'), tr('Yalnız o yayınevinin formunu okur'), false),
      (
        tr('Kurumsal okuma programları'),
        tr('Yılda binlerce dolar'),
        tr('Okul başına lisans, kurulum ücreti ayrı'),
        false,
      ),
    ];
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (final (name, price, note, mine) in items)
            Container(
              decoration: BoxDecoration(
                color: mine ? NColors.emerald.withValues(alpha: 0.09) : null,
                border: mine ? null : Border(top: BorderSide(color: t.dividerColor.withValues(alpha: 0.5))),
              ),
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: Row(
                children: [
                  if (mine) const AppLogo(size: 34) else Icon(Icons.storefront_rounded, color: muted, size: 28),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          style: TextStyle(
                            fontWeight: mine ? FontWeight.w800 : FontWeight.w600,
                            color: mine ? null : muted,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          price,
                          style: TextStyle(fontWeight: FontWeight.w800, fontSize: mine ? 16 : 14),
                        ),
                        Text(note, style: TextStyle(color: muted, fontSize: 12.5)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _SloganBand extends StatelessWidget {
  const _SloganBand();

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: dark ? nightEmeraldGradient : emeraldGradient,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(color: NColors.emerald.withValues(alpha: 0.35), blurRadius: 22, offset: const Offset(0, 10)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            tr('Kâğıttan sonuca, saniyeler içinde.'),
            style: const TextStyle(color: NColors.onGreen, fontSize: 21, fontWeight: FontWeight.w800, height: 1.25),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final s in whySlogans())
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(30),
                  ),
                  child: Text(
                    s,
                    style: const TextStyle(color: NColors.onGreen, fontWeight: FontWeight.w700, fontSize: 13),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Actions extends StatelessWidget {
  const _Actions();

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 10,
    runSpacing: 10,
    alignment: WrapAlignment.center,
    children: [
      FilledButton.icon(
        onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const NewExamScreen())),
        icon: const Icon(Icons.add_rounded),
        label: Text(tr('Hemen bir sınav başlat')),
      ),
      if (!ProService.salesDisabled)
        OutlinedButton.icon(
          onPressed: () =>
              Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ProScreen(), fullscreenDialog: true)),
          icon: const Icon(Icons.diamond_outlined),
          label: Text(tr('Netice Pro\'yu incele')),
        ),
      OutlinedButton.icon(
        onPressed: () => shareApp(context),
        icon: const Icon(Icons.ios_share_rounded),
        label: Text(tr('Meslektaşına öner')),
      ),
    ],
  );
}

/// Panoda gösterilen kısa "Neden Netice?" kartı.
class WhyNeticeBanner extends StatelessWidget {
  const WhyNeticeBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        leading: const SectionIcon(Section.why, size: 42),
        title: Text(tr('Neden Netice?'), style: const TextStyle(fontWeight: FontWeight.w800)),
        subtitle: Text(
          tr('Benzer uygulamalarla özellik ve fiyat karşılaştırması'),
          style: TextStyle(color: t.colorScheme.onSurface.withValues(alpha: 0.65)),
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const WhyNeticeScreen())),
      ),
    );
  }
}

/// Yayınevi uygulamalarına karşı ana mesaj.
class _OwnFormCallout extends StatelessWidget {
  const _OwnFormCallout();

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: NColors.emerald.withValues(alpha: t.brightness == Brightness.dark ? 0.14 : 0.08),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: NColors.emerald.withValues(alpha: 0.35)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const GlossyIcon(Icons.assignment_turned_in_rounded, Color(0xFF34D399), Color(0xFF047857), size: 40),
        const SizedBox(width: 14),
        Expanded(
          child: Text(
            tr('Her yayınevinin formunu ayrı uygulamayla okumayın; kendi sınavınızı, kendi formunuzla okuyun.'),
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5, height: 1.35),
          ),
        ),
      ]),
    );
  }
}
