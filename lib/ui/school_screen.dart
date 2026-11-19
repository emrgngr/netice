import 'package:material_ui/material_ui.dart';

import '../core/models.dart';
import '../main.dart';
import '../core/pro.dart';
import 'pro_screen.dart';
import 'widgets.dart';
import '../l10n/l10n.dart';

/// Kurum ve eğitici bilgileri. Okul, üniversite, polis ve askerî eğitim
/// kurumları ile kurslar için; tüm PDF rapor ve listelerde resmi yazı başlığı
/// ve imza alanı olarak kullanılır.
class SchoolScreen extends StatefulWidget {
  const SchoolScreen({super.key});

  @override
  State<SchoolScreen> createState() => _SchoolScreenState();
}

class _SchoolScreenState extends State<SchoolScreen> {
  static const _keys = [
    'name', 'parent', 'province', 'district', 'country', 'principal', 'headTitle', 'teacher', 'instructorTitle',
    'subject', 'groupLabel',
  ];
  final _c = <String, TextEditingController>{};
  InstitutionType _type = InstitutionType.school;
  bool _turkish = true;
  bool _official = true;
  bool _loaded = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loaded) return;
    _loaded = true;
    final s = StoreScope.of(context).school;
    final values = {
      'name': s.name,
      'parent': s.parent,
      'province': s.province,
      'district': s.district,
      'country': s.country,
      'principal': s.principal,
      'headTitle': s.headTitle,
      'teacher': s.teacher,
      'instructorTitle': s.instructorTitle,
      'subject': s.subject,
      'groupLabel': s.groupLabel,
    };
    for (final k in _keys) {
      _c[k] = TextEditingController(text: values[k])..addListener(() => setState(() {}));
    }
    _type = s.type;
    _turkish = s.turkishStyle;
    _official = s.officialHeader;
  }

  @override
  void dispose() {
    for (final c in _c.values) {
      c.dispose();
    }
    super.dispose();
  }

  String _v(String k) => _c[k]!.text.trim();

  SchoolInfo get _info => SchoolInfo(
        type: _type,
        name: _v('name'),
        parent: _type == InstitutionType.school ? '' : _v('parent'),
        province: _v('province'),
        district: _v('district'),
        country: _v('country'),
        principal: _v('principal'),
        headTitle: _v('headTitle'),
        teacher: _v('teacher'),
        instructorTitle: _v('instructorTitle'),
        subject: _v('subject'),
        groupLabel: _v('groupLabel'),
        turkishFormat: _turkish,
        officialHeader: _official,
      );

  void _save() {
    StoreScope.of(context).setSchool(_info);
    toast(context, tr('Kurum bilgileri kaydedildi. Bundan sonraki tüm raporlarda kullanılacak.'));
    Navigator.of(context).pop();
  }

  Widget _field(String key, String label, String hint, IconData icon, {String? helper}) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextField(
          controller: _c[key],
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(
              labelText: label, hintText: hint, helperText: helper, helperMaxLines: 3, prefixIcon: Icon(icon)),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final muted = t.colorScheme.onSurface.withValues(alpha: 0.6);
    final info = _info;
    final school = _type == InstitutionType.school;
    final now = DateTime.now();
    const paper = TextStyle(color: Colors.black, fontSize: 12, height: 1.35);
    return Scaffold(
      appBar: AppBar(title: Text(tr('Kurum bilgileri')), actions: [
        Padding(
          padding: const EdgeInsets.only(right: 8),
          child: FilledButton(onPressed: _save, child: Text(tr('Kaydet'))),
        ),
      ]),
      body: Watermark(
        child: ListView(padding: EdgeInsets.fromLTRB(20, 8, 20, 40 + MediaQuery.paddingOf(context).bottom), children: [
          Text(tr('Bu bilgiler sınav raporu, karne, not listesi, grup karşılaştırması ve optik formlarda başlık olarak yer alır. Boş bıraktığınız alanlar basılmaz.'),
              style: TextStyle(color: muted)),
          const SizedBox(height: 16),
          DropdownButtonFormField<InstitutionType>(
            initialValue: _type,
            isExpanded: true,
            decoration: InputDecoration(labelText: tr('Kurum türü'), prefixIcon: const Icon(Icons.category_outlined)),
            items: [
              for (final k in InstitutionType.values)
                DropdownMenuItem(value: k, child: Text(k.label, overflow: TextOverflow.ellipsis)),
            ],
            onChanged: (v) => setState(() => _type = v ?? _type),
          ),
          const SizedBox(height: 12),
          if (!school)
            _field('parent', tr('Bağlı olduğu kurum'), _type.parentHint, Icons.account_tree_outlined,
                helper: tr('Başlıkta kurum adının üstünde yer alır')),
          _field('name', school ? tr('Okul adı') : tr('Kurum adı'), _type.nameHint, Icons.account_balance_outlined),
          if (school || !_turkish) ...[
            _field('province', school && _turkish ? tr('İl') : tr('İl / eyalet'), tr('Örn. Ankara'),
                Icons.location_city_outlined),
            _field('district', school && _turkish ? tr('İlçe') : tr('Şehir / ilçe'),
                school && _turkish ? tr('Örn. Çankaya (il merkezindeyse "Merkez")') : tr('Örn. Çankaya'), Icons.map_outlined),
          ],
          if (!_turkish) _field('country', tr('Ülke'), tr('Örn. Almanya'), Icons.public_rounded),
          SectionTitle(tr('İmza ve unvanlar')),
          _field('principal', tr('Kurum amiri'), tr('Ad Soyad (rütbe/unvan yazabilirsiniz)'), Icons.person_outline),
          _field('headTitle', tr('Amirin unvanı'), _type.defaultHeadTitle, Icons.workspace_premium_outlined,
              helper: tr('Boş bırakılırsa: {0}', [_type.defaultHeadTitle])),
          _field('teacher', tr('Öğretmen / eğitici'), tr('Ad Soyad'), Icons.badge_outlined),
          _field('instructorTitle', tr('Öğretmenin unvanı'), _type.defaultInstructorTitle, Icons.school_outlined,
              helper: tr('Boş bırakılırsa: {0}', [_type.defaultInstructorTitle])),
          _field('subject', tr('Ders / branş'), tr('Örn. Fizik'), Icons.menu_book_outlined),
          _field('groupLabel', tr('Grupların adı'), _type.defaultGroupLabel, Icons.groups_outlined,
              helper: tr('Sınıf, şube, bölük, takım, grup… Boş bırakılırsa: {0}', [_type.defaultGroupLabel])),
          Card(
            child: Column(children: [
              SwitchListTile(
                value: _turkish,
                onChanged: (v) => setState(() => _turkish = v),
                title: Text(tr('Türkiye resmi yazı biçimi'), style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text(tr('Başlık "T.C." ile başlar. Başka ülkelerde kapatın.')),
              ),
              SwitchListTile(
                value: _official,
                onChanged: (v) async {
                  if (v && !await requirePro(context, ProFeature.officialHeader)) return;
                  if (mounted) setState(() => _official = v);
                },
                title: Row(children: [
                  Flexible(child: Text(tr('Resmi yazı başlığı ve imza alanı'), style: const TextStyle(fontWeight: FontWeight.w700))),
                  if (!StoreScope.of(context).isPro) ...[const SizedBox(width: 8), const ProBadge()],
                ]),
                subtitle: Text(tr('Kapalıysa raporlarda yalnızca kurum adı küçük başlık olarak görünür.')),
              ),
            ]),
          ),
          SectionTitle(tr('Önizleme')),
          Card(
            color: Colors.white,
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: info.isEmpty
                  ? Text(tr('Önizleme için kurum adını yazın.'), style: const TextStyle(color: Colors.black54))
                  : !info.official
                      ? Text(info.name, style: paper.copyWith(fontWeight: FontWeight.w800))
                      : Column(children: [
                          for (final line in info.letterhead)
                            Text(line, textAlign: TextAlign.center, style: paper.copyWith(fontWeight: FontWeight.w800)),
                          const SizedBox(height: 8),
                          Text(
                            tr('{0} EĞİTİM-ÖĞRETİM YILI {1}{2}', [
                              SchoolInfo.academicYear(now),
                              info.classLine(school ? '9-A' : '1'),
                              info.subject.isEmpty ? '' : tr(' {0} DERSİ', [SchoolInfo.upper(info.subject)])
                            ]),
                            textAlign: TextAlign.center,
                            style: paper.copyWith(fontSize: 11),
                          ),
                          Text(tr('SINAV ANALİZ RAPORU'), style: paper.copyWith(fontWeight: FontWeight.w800)),
                          const Divider(color: Colors.black, height: 20),
                          const SizedBox(height: 40),
                          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, crossAxisAlignment: CrossAxisAlignment.end, children: [
                            Flexible(child: _sig(paper, info.teacher, info.instructorRole)),
                            const SizedBox(width: 12),
                            Flexible(
                              child: Column(children: [
                                Text('UYGUNDUR', style: paper.copyWith(fontWeight: FontWeight.w800, fontSize: 11)),
                                Text(dmy(now), style: paper.copyWith(fontSize: 11)),
                                const SizedBox(height: 18),
                                _sig(paper, info.principal, info.headRole),
                              ]),
                            ),
                          ]),
                        ]),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _sig(TextStyle s, String name, String role) => Column(children: [
        Text(name.isEmpty ? '................' : name,
            textAlign: TextAlign.center, style: s.copyWith(fontWeight: FontWeight.w800, fontSize: 11)),
        Text(role, textAlign: TextAlign.center, style: s.copyWith(fontSize: 10)),
      ]);
}
