import 'package:material_ui/material_ui.dart';

import '../core/models.dart';
import '../main.dart';
import '../core/pro.dart';
import '../core/titles.dart';
import '../core/letterheads.dart';
import 'pro_screen.dart';
import 'service_cards.dart';
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
    'subject', 'groupLabel', 'localUnit', 'units',
  ];
  final _c = <String, TextEditingController>{};
  InstitutionType _type = InstitutionType.school;
  bool _turkish = true;
  bool _local = true;
  bool _official = true;
  String _system = 'tr';
  String _font = 'netice';
  double _hSize = 10.5, _sSize = 9.5;
  bool _hBold = true, _hItalic = false, _hUnder = false;
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
      'localUnit': s.localUnit ?? SchoolInfo.defaultLocalUnit,
      'units': s.units.join('\n'),
    };
    for (final k in _keys) {
      _c[k] = TextEditingController(text: values[k])..addListener(() => setState(() {}));
    }
    _type = s.type;
    _turkish = s.turkishStyle;
    _local = s.localChain;
    _official = s.officialHeader;
    _system = s.titleSystem ?? (_turkish ? 'tr' : TitleSystem.defaultCode());
    _font = s.fontFamily;
    _hSize = s.headerSize;
    _sSize = s.signSize;
    _hBold = s.headerBold;
    _hItalic = s.headerItalic;
    _hUnder = s.headerUnderline;
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
        parent: _v('parent'),
        localHeader: _local == _type.defaultLocalChain ? null : _local,
        localUnit: _v('localUnit') == SchoolInfo.defaultLocalUnit ? null : _v('localUnit'),
        units: [for (final u in _c['units']!.text.split('\n')) if (u.trim().isNotEmpty) u.trim()],
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
        titleSystem: _system,
        fontFamily: _font,
        headerSize: _hSize,
        signSize: _sSize,
        headerBold: _hBold,
        headerItalic: _hItalic,
        headerUnderline: _hUnder,
        officialHeader: _official,
      );

  void _save() {
    StoreScope.of(context).setSchool(_info);
    toast(context, tr('Kurum bilgileri kaydedildi. Bundan sonraki tüm raporlarda kullanılacak.'));
    Navigator.of(context).pop();
  }

  Widget _field(String key, String label, String hint, IconData icon, {String? helper, VoidCallback? pick, String? pickTip}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextField(
          controller: _c[key],
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(
            labelText: label,
            hintText: hint,
            helperText: helper,
            helperMaxLines: 3,
            prefixIcon: Icon(icon),
            suffixIcon: pick == null
                ? null
                : IconButton(tooltip: pickTip ?? tr('Listeden seç'), icon: const Icon(Icons.format_list_bulleted_rounded), onPressed: pick),
          ),
        ),
      );

  TitleSystem get _titles => TitleSystem.byCode(_system);

  /// Gruplu seçenek listesi; seçileni döndürür. Listede olmayan unvan elle yazılabilir.
  Future<String?> _choose(String title, List<(String, List<String>)> groups) => showModalBottomSheet<String>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (ctx) => DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.7,
          maxChildSize: 0.95,
          builder: (ctx, scroll) => ListView(controller: scroll, padding: const EdgeInsets.fromLTRB(20, 0, 20, 32), children: [
            Text(title, style: Theme.of(ctx).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text(tr('{0} · Listede yoksa alana kendiniz yazabilirsiniz.', [_titles.countryName]),
                style: TextStyle(color: Theme.of(ctx).colorScheme.onSurface.withValues(alpha: 0.6))),
            for (final g in groups)
              if (g.$2.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.only(top: 18, bottom: 8),
                  child: Text(g.$1.toUpperCase(),
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 1.1)),
                ),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final v in g.$2)
                    ActionChip(
                      label: Text(v),
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity: VisualDensity.compact,
                      onPressed: () => Navigator.of(ctx).pop(v),
                    ),
                ]),
              ],
          ]),
        ),
      );

  /// Ad alanına unvan/rütbe ekler; varsa eski unvanı değiştirir.
  Future<void> _pickPrefix(String key) async {
    final groups = _titles.prefixes(_type);
    final v = await _choose(tr('Unvan veya rütbe'), groups);
    if (v == null) return;
    final known = [for (final g in groups) ...g.$2]..sort((a, b) => b.length.compareTo(a.length));
    var name = _c[key]!.text.trim();
    for (final k in known) {
      if (name.startsWith('$k ')) {
        name = name.substring(k.length).trim();
        break;
      }
    }
    _c[key]!.text = name.isEmpty ? '$v ' : '$v $name';
  }

  Future<void> _pickRole(String key, {required bool head}) async {
    final v = await _choose(head ? tr('Amirin görevi') : tr('Öğretmenin görevi'), _titles.roles(_type, head: head));
    if (v != null) _c[key]!.text = v;
  }

  Future<void> _pickGroup() async {
    final v = await _choose(tr('Grupların adı'), [(tr('Seçenekler'), groupLabelOptions(_type))]);
    if (v != null) _c['groupLabel']!.text = v;
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final muted = t.colorScheme.onSurface.withValues(alpha: 0.6);
    final info = _info;
    final school = _type == InstitutionType.school;
    final now = DateTime.now();
    final fam = switch (_font) { 'times' => 'ReportSerif', 'arial' => 'ReportSans', _ => null };
    final paper = TextStyle(color: Colors.black, fontSize: 12, height: 1.35, fontFamily: fam);
    final head = paper.copyWith(
      fontSize: _hSize * 1.1,
      fontWeight: _hBold ? FontWeight.w700 : FontWeight.w400,
      fontStyle: _hItalic ? FontStyle.italic : FontStyle.normal,
      decoration: _hUnder ? TextDecoration.underline : null,
    );
    return Scaffold(
      appBar: AppBar(title: Text(tr('Kurum bilgileri')), actions: [
        Padding(
          padding: const EdgeInsets.only(right: 8),
          child: FilledButton(onPressed: _save, child: Text(tr('Kaydet'))),
        ),
      ]),
      body: Watermark(
        child: SectionedList(padding: EdgeInsets.fromLTRB(20, 8, 20, 40 + MediaQuery.paddingOf(context).bottom), children: [
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
            onChanged: (v) => setState(() {
              _type = v ?? _type;
              _local = _type.defaultLocalChain;
            }),
          ),
          const SizedBox(height: 12),
          if (_turkish) ..._hierarchy(info, head) else ...[
            _field('parent', tr('Bağlı olduğu kurum'), _type.parentHint, Icons.account_tree_outlined,
                helper: tr('Başlıkta kurum adının üstünde yer alır')),
            _unitsField(),
            _field('name', school ? tr('Okul adı') : tr('Kurum adı'), _type.nameHint, Icons.account_balance_outlined),
            _field('province', tr('İl / eyalet'), tr('Örn. Ankara'), Icons.location_city_outlined),
            _field('district', tr('Şehir / ilçe'), tr('Örn. Çankaya'), Icons.map_outlined),
            _field('country', tr('Ülke'), tr('Örn. Almanya'), Icons.public_rounded),
          ],
          SectionTitle(tr('İmza ve unvanlar')),
          DropdownButtonFormField<String>(
            initialValue: _system,
            isExpanded: true,
            decoration: InputDecoration(
              labelText: tr('Unvan listeleri'),
              helperText: tr('Hangi ülkenin akademik unvan, rütbe ve görev adları listelensin'),
              helperMaxLines: 2,
              prefixIcon: const Icon(Icons.public_rounded),
            ),
            items: [
              for (final ts in TitleSystem.all)
                DropdownMenuItem(value: ts.code, child: Text(ts.countryName, overflow: TextOverflow.ellipsis)),
            ],
            onChanged: (v) => setState(() => _system = v ?? _system),
          ),
          const SizedBox(height: 12),
          _field('principal', tr('Kurum amiri'), tr('Ad Soyad (rütbe/unvan yazabilirsiniz)'), Icons.person_outline,
              pick: () => _pickPrefix('principal'), pickTip: tr('Unvan veya rütbe ekle')),
          _field('headTitle', tr('Amirin görevi'), _type.defaultHeadTitle, Icons.workspace_premium_outlined,
              helper: tr('Boş bırakılırsa: {0}', [_type.defaultHeadTitle]), pick: () => _pickRole('headTitle', head: true)),
          _field('teacher', tr('Öğretmen / eğitici'), tr('Ad Soyad'), Icons.badge_outlined,
              pick: () => _pickPrefix('teacher'), pickTip: tr('Unvan veya rütbe ekle')),
          _field('instructorTitle', tr('Öğretmenin görevi'), _type.defaultInstructorTitle, Icons.school_outlined,
              helper: tr('Boş bırakılırsa: {0}', [_type.defaultInstructorTitle]),
              pick: () => _pickRole('instructorTitle', head: false)),
          _field('subject', tr('Ders / branş'), tr('Örn. Fizik'), Icons.menu_book_outlined),
          _field('groupLabel', tr('Grupların adı'), _type.defaultGroupLabel, Icons.groups_outlined,
              helper: tr('Sınıf, şube, bölük, takım, grup… Boş bırakılırsa: {0}', [_type.defaultGroupLabel]), pick: _pickGroup),
          Card(
            child: Column(children: [
              SwitchListTile(
                value: _turkish,
                onChanged: (v) => setState(() {
                  _turkish = v;
                  if (v) {
                    _system = 'tr';
                  } else if (_system == 'tr') {
                    _system = TitleSystem.defaultCode() == 'tr' ? 'en' : TitleSystem.defaultCode();
                  }
                }),
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
          SectionTitle(tr('Yazı stili')),
          _styleCard(),
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
                          for (final line in info.letterhead) Text(line, textAlign: TextAlign.center, style: head),
                          const SizedBox(height: 8),
                          Text(
                            tr('{0} EĞİTİM-ÖĞRETİM YILI {1}{2}', [
                              SchoolInfo.academicYear(now),
                              info.classLine(school ? '9-A' : '1'),
                              info.subject.isEmpty ? '' : tr(' {0} DERSİ', [SchoolInfo.upper(info.subject)])
                            ]),
                            textAlign: TextAlign.center,
                            style: paper.copyWith(fontSize: (_hSize - 1) * 1.1, fontStyle: head.fontStyle),
                          ),
                          Text(tr('SINAV ANALİZ RAPORU'), textAlign: TextAlign.center, style: head),
                          const Divider(color: Colors.black, height: 20),
                          const SizedBox(height: 40),
                          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, crossAxisAlignment: CrossAxisAlignment.end, children: [
                            Flexible(child: _sig(paper, info.teacher, info.instructorRole)),
                            const SizedBox(width: 12),
                            Flexible(
                              child: Column(children: [
                                Text('UYGUNDUR', style: paper.copyWith(fontWeight: FontWeight.w700, fontSize: (_sSize - 0.5) * 1.1)),
                                Text(dmy(now), style: paper.copyWith(fontWeight: FontWeight.w700, fontSize: (_sSize - 0.5) * 1.1)),
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

  Widget _unitsField() => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextField(
          controller: _c['units'],
          textCapitalization: TextCapitalization.words,
          minLines: 1,
          maxLines: 4,
          decoration: InputDecoration(
            labelText: tr('Ara birimler (isteğe bağlı)'),
            hintText: tr('Her satıra bir birim, üstten alta'),
            helperText: tr('Üst kurum ile kurumunuz arasındaki birimler: fakülte, daire başkanlığı, komutanlık…'),
            helperMaxLines: 3,
            prefixIcon: const Icon(Icons.subdirectory_arrow_right_rounded),
          ),
        ),
      );

  /// Türkiye resmi yazı başlığı hiyerarşisi: Valilik / Kaymakamlık ya da üst
  /// kurum, müdürlük, ara birimler ve kurumun kendisi.
  List<Widget> _hierarchy(SchoolInfo info, TextStyle head) {
    final school = _type == InstitutionType.school;
    final muted = Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6);
    return [
      Card(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Icon(Icons.gavel_rounded, size: 20),
              const SizedBox(width: 8),
              Expanded(child: Text(tr('Resmi başlık sırası'), style: const TextStyle(fontWeight: FontWeight.w800))),
              TextButton.icon(onPressed: _pickPreset, icon: const Icon(Icons.auto_awesome_rounded, size: 18), label: Text(tr('Hazır örnek'))),
            ]),
            Text(
                tr('Resmî Yazışma Yönetmeliğine göre: 1. satır T.C., 2. satır idarenin adı (büyük harf), altında birimler sırayla (ilk harfleri büyük).'),
                style: TextStyle(fontSize: 12.5, color: muted)),
            const SizedBox(height: 8),
            SegmentedButton<bool>(
              segments: [
                ButtonSegment(value: true, label: Text(tr('Valilik / Kaymakamlık')), icon: const Icon(Icons.location_city_rounded)),
                ButtonSegment(value: false, label: Text(tr('Bakanlık / üst kurum')), icon: const Icon(Icons.account_tree_rounded)),
              ],
              selected: {_local},
              showSelectedIcon: false,
              onSelectionChanged: (v) => setState(() => _local = v.first),
            ),
            const SizedBox(height: 14),
            if (_local) ...[
              _field('province', tr('İl'), tr('Örn. Ankara'), Icons.location_city_outlined),
              _field('district', tr('İlçe'), tr('Örn. Çankaya (il merkezindeyse "Merkez" ya da boş)'), Icons.map_outlined,
                  helper: tr('İlçe yazılırsa "... KAYMAKAMLIĞI" ve "İlçe ...", boşsa "... VALİLİĞİ" ve "İl ..." yazılır.')),
              _field('localUnit', tr('Bağlı müdürlük'), SchoolInfo.defaultLocalUnit, Icons.apartment_rounded,
                  helper: tr('Başına il ya da ilçe kendiliğinden eklenir. Satır istemiyorsanız boş bırakın.'),
                  pick: _pickLocalUnit),
            ] else
              _field('parent', tr('Üst kurum (2. satır)'), _type.parentHint, Icons.account_tree_outlined,
                  helper: tr('Bakanlık, rektörlük, başkanlık… Başlıkta büyük harfle yazılır.')),
            _unitsField(),
            _field('name', school ? tr('Okul adı') : tr('Kurum adı'), _type.nameHint, Icons.account_balance_outlined,
                helper: school ? tr('Sonuna "Müdürlüğü" kendiliğinden eklenir.') : null),
            if (!info.isEmpty) ...[
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.black12)),
                child: Column(children: [for (final line in info.letterhead) Text(line, textAlign: TextAlign.center, style: head)]),
              ),
            ],
          ]),
        ),
      ),
      const SizedBox(height: 12),
    ];
  }

  Future<void> _pickPreset() async {
    final list = HeaderPreset.of(_type);
    final p = await showModalBottomSheet<HeaderPreset>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: ListView(shrinkWrap: true, padding: const EdgeInsets.fromLTRB(8, 0, 8, 16), children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: Text(tr('Hazır başlık örnekleri'), style: Theme.of(ctx).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
          ),
          for (final h in list)
            ListTile(
              title: Text(h.label, style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text([
                'T.C.',
                if (h.local) tr('VALİLİK / KAYMAKAMLIK') else SchoolInfo.upper(h.parent),
                if (h.local && h.localUnit.isNotEmpty) tr('İl / İlçe {0}', [h.localUnit]),
                ...h.units,
                h.name,
              ].where((e) => e.isNotEmpty).join('\n')),
              isThreeLine: true,
              onTap: () => Navigator.of(ctx).pop(h),
            ),
        ]),
      ),
    );
    if (p == null) return;
    setState(() {
      _local = p.local;
      _c['localUnit']!.text = p.localUnit;
      _c['parent']!.text = p.parent;
      _c['units']!.text = p.units.join('\n');
      _c['name']!.text = p.name;
    });
    if (mounted) toast(context, tr('Örnek dolduruldu. Adları kendi kurumunuza göre düzeltin.'));
  }

  Future<void> _pickLocalUnit() async {
    final v = await _choose(tr('Bağlı müdürlük'), [(tr('Valilik / Kaymakamlık birimleri'), HeaderPreset.localUnits)]);
    if (v != null) _c['localUnit']!.text = v;
  }

  Widget _sig(TextStyle s, String name, String role) => Column(children: [
        Text(name.isEmpty ? '................' : name,
            textAlign: TextAlign.center, style: s.copyWith(fontWeight: FontWeight.w700, fontSize: _sSize * 1.1)),
        Text(role, textAlign: TextAlign.center, style: s.copyWith(fontSize: (_sSize - 1) * 1.1)),
      ]);

  Widget _styleCard() {
    Widget size(String label, double v, double min, double max, ValueChanged<double> on) => Row(children: [
          Expanded(child: Text(label)),
          IconButton(
              tooltip: tr('Küçült'),
              onPressed: v <= min ? null : () => setState(() => on(v - 0.5)),
              icon: const Icon(Icons.remove_circle_outline)),
          SizedBox(
              width: 56,
              child: Text(tr('{0} pt', [v % 1 == 0 ? v.toInt() : v]),
                  textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w800))),
          IconButton(
              tooltip: tr('Büyült'),
              onPressed: v >= max ? null : () => setState(() => on(v + 0.5)),
              icon: const Icon(Icons.add_circle_outline)),
        ]);
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: DropdownButtonFormField<String>(
              initialValue: _font,
              isExpanded: true,
              decoration: InputDecoration(labelText: tr('Yazı tipi'), prefixIcon: const Icon(Icons.font_download_outlined)),
              items: [
                for (final f in SchoolInfo.fontFamilies)
                  DropdownMenuItem(
                    value: f,
                    child: Text(SchoolInfo.fontLabel(f),
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontFamily: switch (f) { 'times' => 'ReportSerif', 'arial' => 'ReportSans', _ => null })),
                  ),
              ],
              onChanged: (v) => setState(() => _font = v ?? _font),
            ),
          ),
          const SizedBox(height: 8),
          size(tr('Başlık puntosu'), _hSize, 8, 16, (v) => _hSize = v),
          size(tr('İmza puntosu'), _sSize, 7, 14, (v) => _sSize = v),
          const SizedBox(height: 4),
          Text(tr('Başlık karakteri')),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            FilterChip(
                selected: _hBold,
                label: Text(tr('Kalın'), style: const TextStyle(fontWeight: FontWeight.w800)),
                onSelected: (v) => setState(() => _hBold = v)),
            FilterChip(
                selected: _hItalic,
                label: Text(tr('İtalik'), style: const TextStyle(fontStyle: FontStyle.italic)),
                onSelected: (v) => setState(() => _hItalic = v)),
            FilterChip(
                selected: _hUnder,
                label: Text(tr('Altı çizili'), style: const TextStyle(decoration: TextDecoration.underline)),
                onSelected: (v) => setState(() => _hUnder = v)),
          ]),
          if (L10n.rtl || const ['zh', 'ja', 'ko', 'hi'].contains(L10n.code)) ...[
            const SizedBox(height: 8),
            Text(tr('Arapça, Çince, Japonca, Korece ve Hintçe harfler her yazı tipinde uygun Noto yazı tipiyle basılır.'),
                style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6))),
          ],
        ]),
      ),
    );
  }
}
