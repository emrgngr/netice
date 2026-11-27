import 'package:material_ui/material_ui.dart';

import '../core/institution.dart';
import '../l10n/l10n.dart';
import '../main.dart';
import 'common_exam_ui.dart';
import 'compare_screen.dart';
import 'license_screen.dart';
import 'student_detail_screen.dart';
import 'service_cards.dart';
import 'theme.dart';
import 'widgets.dart';

/// Kurum yönetici paneli: tüm şubeler, ortak sınavlar ve destek gereken
/// öğrenciler tek ekranda. Veriler bu cihazda; diğer öğretmenlerin sonuçları
/// ortak sınav sonuç dosyalarıyla gelir.
class AdminPanelScreen extends StatelessWidget {
  const AdminPanelScreen({super.key});

  /// Panel açılabiliyorsa açar; değilse kurum lisansı ekranını gösterir.
  static Future<void> open(BuildContext context) {
    final store = StoreScope.of(context);
    return Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => store.canUseAdminPanel ? const AdminPanelScreen() : const LicenseScreen()));
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final t = Theme.of(context);
    final muted = t.colorScheme.onSurface.withValues(alpha: 0.6);
    final s = summarizeInstitution(store);
    final name = store.reportSchool.name.trim();
    String pct(double v) => L10n.percent(v.round());

    return Scaffold(
      appBar: AppBar(
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(tr('Yönetici paneli')),
          if (name.isNotEmpty) Text(name, style: t.textTheme.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis),
        ]),
        actions: [
          IconButton(
            tooltip: tr('Ortak sınav veya sonuç dosyası aç'),
            onPressed: () => importNeticeFile(context),
            icon: const Icon(Icons.move_to_inbox_outlined),
          ),
        ],
      ),
      body: Watermark(
        child: SectionedList(padding: EdgeInsets.fromLTRB(20, 8, 20, 40 + MediaQuery.paddingOf(context).bottom), children: [
          if (!store.isInstitutionAdmin)
            Card(
              color: NColors.amber.withValues(alpha: 0.12),
              child: ListTile(
                leading: const Icon(Icons.info_outline, color: NColors.amber),
                title: Text(tr('Tanıtım: yönetici paneli kurum lisansıyla kalıcı olarak açılır.')),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const LicenseScreen())),
              ),
            ),
          const SizedBox(height: 4),
          GridView(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 220, mainAxisExtent: 118, crossAxisSpacing: 12, mainAxisSpacing: 12),
            children: [
              StatCard(label: tr('Şube'), value: '${s.classes}', icon: Icons.groups_outlined),
              StatCard(label: tr('Öğrenci'), value: '${s.students}', icon: Icons.person_outline),
              StatCard(label: tr('Sınav'), value: '${s.exams}', icon: Icons.assignment_outlined),
              StatCard(label: tr('Okunan kâğıt'), value: '${s.sheets}', icon: Icons.document_scanner_outlined),
              StatCard(label: tr('Kurum ortalaması'), value: pct(s.meanPct), icon: Icons.insights_outlined),
              StatCard(
                  label: tr('Destek gereken'),
                  value: '${s.warnings.length}',
                  icon: Icons.support_outlined,
                  accent: s.warnings.isEmpty ? NColors.emerald : NColors.coral),
            ],
          ),
          SectionTitle(tr('Ortak sınavlar'),
              trailing: TextButton(
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const CompareScreen())),
                child: Text(tr('Şube karşılaştırması')),
              )),
          if (s.common.isEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                    tr('Henüz ortak sınav yok. Bir sınavı açın, menüden "Ortak sınav yap"ı seçin ve dosyayı diğer öğretmenlere gönderin. Gelen sonuç dosyalarını sağ üstteki düğmeyle ekleyin.'),
                    style: TextStyle(color: muted)),
              ),
            )
          else
            for (final c in s.common)
              Card(
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () => openCommonReport(context, c.commonId),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Expanded(child: Text(c.name, style: const TextStyle(fontWeight: FontWeight.w800))),
                        Text(tr('{0} şube · ort. {1}', [c.classes.length, pct(c.meanPct)]), style: TextStyle(color: muted)),
                      ]),
                      const SizedBox(height: 10),
                      for (final cl in c.classes)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Row(children: [
                            SizedBox(width: 70, child: Text(cl.$1, maxLines: 1, overflow: TextOverflow.ellipsis)),
                            Expanded(
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(4),
                                child: LinearProgressIndicator(
                                  value: (cl.$2 / 100).clamp(0, 1),
                                  minHeight: 8,
                                  color: cl.$2 >= c.meanPct ? NColors.emerald : NColors.navy(t.brightness == Brightness.dark),
                                  backgroundColor: t.colorScheme.onSurface.withValues(alpha: 0.08),
                                ),
                              ),
                            ),
                            SizedBox(width: 48, child: Text(pct(cl.$2), textAlign: TextAlign.end)),
                          ]),
                        ),
                      Text(tr('Dokunun: birleşik rapor (PDF)'), style: TextStyle(color: muted, fontSize: 12)),
                    ]),
                  ),
                ),
              ),
          SectionTitle(tr('Şubeler')),
          Card(
            clipBehavior: Clip.antiAlias,
            child: Column(children: [
              for (final c in s.byClass)
                ListTile(
                  title: Text(c.className, style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text(tr('{0} öğrenci · {1} sınav{2}',
                      [c.students, c.exams, c.warnings > 0 ? tr(' · {0} destek gereken', [c.warnings]) : ''])),
                  trailing: c.lastPct == null
                      ? null
                      : Row(mainAxisSize: MainAxisSize.min, children: [
                          if (c.trend != null && c.trend!.abs() >= 1)
                            Icon(c.trend! > 0 ? Icons.trending_up_rounded : Icons.trending_down_rounded,
                                color: c.trend! > 0 ? NColors.emerald : NColors.coral, size: 20),
                          const SizedBox(width: 6),
                          Text(pct(c.lastPct!), style: const TextStyle(fontWeight: FontWeight.w800)),
                        ]),
                ),
              if (s.byClass.isEmpty) ListTile(title: Text(tr('Henüz şube yok.'))),
            ]),
          ),
          if (s.warnings.isNotEmpty) ...[
            SectionTitle(tr('Destek gereken öğrenciler')),
            Card(
              clipBehavior: Clip.antiAlias,
              child: Column(children: [
                for (final w in s.warnings.take(15))
                  ListTile(
                    leading: const Icon(Icons.flag_outlined, color: NColors.coral),
                    title: Text('${w.student.fullName} · ${w.student.className}'),
                    subtitle: Text(w.reason),
                    trailing: Text(pct(w.lastPct)),
                    onTap: () => Navigator.of(context)
                        .push(MaterialPageRoute(builder: (_) => StudentDetailScreen(studentId: w.student.id))),
                  ),
              ]),
            ),
          ],
          const SizedBox(height: 12),
          Text(
              tr('Panel bu cihazdaki verilerden hazırlanır. Diğer öğretmenlerin sonuçları ortak sınav sonuç dosyalarıyla gelir; internet ve sunucu kullanılmaz.'),
              style: TextStyle(color: muted, fontSize: 12)),
        ]),
      ),
    );
  }
}
