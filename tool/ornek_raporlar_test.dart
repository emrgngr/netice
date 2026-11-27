// "Örnek raporlar" galerisinin PDF'leri (uygulamadaki galeriyle aynı liste):
//   flutter test tool/ornek_raporlar_test.dart --dart-define=LANGS=tr,en
// Çıktı: build/ornek-raporlar/<dil>/<ad>.pdf (ve soru_kitapcigi.docx, not_listesi.csv). Web sitesi görselleri için
// tool/site/ornek_raporlar.sh bu PDF'lerin ilk sayfalarını JPG'ye çevirir.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:netice/core/import_export.dart';
import 'package:netice/l10n/l10n.dart';
import 'package:netice/reports/booklet_docx.dart';
import 'package:netice/ui/sample_reports.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const langs = String.fromEnvironment('LANGS', defaultValue: 'tr');

  testWidgets('örnek raporlar', (t) async {
    final failed = <String>[];
    await t.runAsync(() async {
      for (final lang in langs.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty)) {
        L10n.use(lang);
        final d = SampleData.create();
        final dir = Directory('build/ornek-raporlar/$lang')..createSync(recursive: true);
        for (final r in SampleReport.values) {
          if (!r.available) continue;
          try {
            final bytes = await r.build(d);
            File('${dir.path}/${r.slug}.pdf').writeAsBytesSync(bytes);
          } catch (e) {
            failed.add('$lang/${r.slug}: ${'$e'.split('\n').first}');
          }
        }
        // Ek biçimler: soru kitapçığının Word hâli ve sınavın Excel not listesi.
        File('${dir.path}/soru_kitapcigi.docx')
            .writeAsBytesSync(buildBookletDocx(d.booklet, school: d.school, image: (_) => null));
        File('${dir.path}/not_listesi.csv').writeAsStringSync(resultsCsv(d.exam, d.results, d.byId));
        stdout.writeln('$lang: ${dir.listSync().length} dosya');
      }
      L10n.use('tr');
    });
    expect(failed, isEmpty, reason: failed.join('\n'));
  }, timeout: const Timeout(Duration(minutes: 20)));
}
