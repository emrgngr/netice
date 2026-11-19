import 'package:material_ui/material_ui.dart';

import '../core/models.dart';
import '../main.dart';
import '../core/pro.dart';
import 'pro_screen.dart';
import 'widgets.dart';
import '../l10n/l10n.dart';

/// Okul ve öğretmen bilgileri. Tüm PDF rapor ve listelerde resmi yazı
/// başlığı (T.C. / Kaymakamlık / Okul Müdürlüğü) ve imza alanı olarak kullanılır.
class SchoolScreen extends StatefulWidget {
  const SchoolScreen({super.key});

  @override
  State<SchoolScreen> createState() => _SchoolScreenState();
}

class _SchoolScreenState extends State<SchoolScreen> {
  final _c = <String, TextEditingController>{};
  bool _official = true;
  bool _loaded = false;

  static List<(String, String, String, IconData)> get _fields => [
    ('name', tr('Okul adı'), tr('Örn. Atatürk Anadolu Lisesi'), Icons.account_balance_outlined),
    ('province', tr('İl'), tr('Örn. Ankara'), Icons.location_city_outlined),
    ('district', tr('İlçe'), tr('Örn. Çankaya (il merkezindeyse "Merkez")'), Icons.map_outlined),
    ('principal', tr('Okul müdürü'), tr('Ad Soyad'), Icons.person_outline),
    ('teacher', tr('Ders öğretmeni'), tr('Ad Soyad'), Icons.badge_outlined),
    ('subject', tr('Ders / branş'), tr('Örn. Fizik'), Icons.menu_book_outlined),
  ];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loaded) return;
    _loaded = true;
    final s = StoreScope.of(context).school;
    final values = {
      'name': s.name,
      'province': s.province,
      'district': s.district,
      'principal': s.principal,
      'teacher': s.teacher,
      'subject': s.subject,
    };
    for (final f in _fields) {
      _c[f.$1] = TextEditingController(text: values[f.$1])..addListener(() => setState(() {}));
    }
    _official = s.officialHeader;
  }

  @override
  void dispose() {
    for (final c in _c.values) {
      c.dispose();
    }
    super.dispose();
  }

  SchoolInfo get _info => SchoolInfo(
        name: _c['name']!.text.trim(),
        province: _c['province']!.text.trim(),
        district: _c['district']!.text.trim(),
        principal: _c['principal']!.text.trim(),
        teacher: _c['teacher']!.text.trim(),
        subject: _c['subject']!.text.trim(),
        officialHeader: _official,
      );

  void _save() {
    StoreScope.of(context).setSchool(_info);
    toast(context, tr('Okul bilgileri kaydedildi. Bundan sonraki tüm raporlarda kullanılacak.'));
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final muted = t.colorScheme.onSurface.withValues(alpha: 0.6);
    final info = _info;
    final now = DateTime.now();
    const paper = TextStyle(color: Colors.black, fontSize: 12, height: 1.35);
    return Scaffold(
      appBar: AppBar(title: Text(tr('Okul bilgileri')), actions: [
        Padding(
          padding: const EdgeInsets.only(right: 8),
          child: FilledButton(onPressed: _save, child: Text(tr('Kaydet'))),
        ),
      ]),
      body: Watermark(
        child: ListView(padding: EdgeInsets.fromLTRB(20, 8, 20, 40 + MediaQuery.paddingOf(context).bottom), children: [
          Text(tr('Bu bilgiler sınav raporu, karne, e-Okul listesi, şube karşılaştırması ve optik formlarda başlık olarak yer alır. Boş bıraktığınız alanlar basılmaz.'),
              style: TextStyle(color: muted)),
          const SizedBox(height: 16),
          for (final f in _fields)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: TextField(
                controller: _c[f.$1],
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(
                  labelText: f.$2,
                  hintText: f.$3,
                  prefixIcon: Icon(f.$4),
                ),
              ),
            ),
          Card(
            child: SwitchListTile(
              value: _official,
              onChanged: (v) async {
                if (v && !await requirePro(context, ProFeature.officialHeader)) return;
                if (mounted) setState(() => _official = v);
              },
              title: Row(children: [
                Flexible(child: Text(tr('Resmi yazı başlığı ve imza alanı'), style: TextStyle(fontWeight: FontWeight.w700))),
                if (!StoreScope.of(context).isPro) ...[const SizedBox(width: 8), const ProBadge()],
              ]),
              subtitle: Text(tr('Kapalıysa raporlarda yalnızca okul adı küçük başlık olarak görünür.')),
            ),
          ),
          SectionTitle(tr('Önizleme')),
          Card(
            color: Colors.white,
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: info.isEmpty
                  ? Text(tr('Önizleme için okul adını yazın.'), style: TextStyle(color: Colors.black54))
                  : !info.official
                      ? Text(info.name, style: paper.copyWith(fontWeight: FontWeight.w800))
                      : Column(children: [
                          for (final line in info.letterhead)
                            Text(line, textAlign: TextAlign.center, style: paper.copyWith(fontWeight: FontWeight.w800)),
                          const SizedBox(height: 8),
                          Text(
                            tr('{0} EĞİTİM-ÖĞRETİM YILI 9-A SINIFI{1}', [SchoolInfo.academicYear(now), info.subject.isEmpty ? '' : tr(' {0} DERSİ', [SchoolInfo.upper(info.subject)])]),
                            textAlign: TextAlign.center,
                            style: paper.copyWith(fontSize: 11),
                          ),
                          Text(tr('SINAV ANALİZ RAPORU'), style: paper.copyWith(fontWeight: FontWeight.w800)),
                          const Divider(color: Colors.black, height: 20),
                          const SizedBox(height: 40),
                          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                            _sig(paper, info.teacher,
                                info.subject.isEmpty ? tr('Ders Öğretmeni') : tr('{0} Öğretmeni', [info.subject])),
                            Column(children: [
                              Text('UYGUNDUR', style: paper.copyWith(fontWeight: FontWeight.w800, fontSize: 11)),
                              Text(dmy(now), style: paper.copyWith(fontSize: 11)),
                              const SizedBox(height: 18),
                              _sig(paper, info.principal, tr('Okul Müdürü')),
                            ]),
                          ]),
                        ]),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _sig(TextStyle s, String name, String role) => Column(children: [
        Text(name.isEmpty ? '................' : name, style: s.copyWith(fontWeight: FontWeight.w800, fontSize: 11)),
        Text(role, style: s.copyWith(fontSize: 10)),
      ]);
}
