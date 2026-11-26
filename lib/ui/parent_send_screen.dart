import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/models.dart';
import '../core/pro.dart';
import '../core/report.dart';
import '../core/scoring.dart';
import '../core/store.dart';
import '../l10n/l10n.dart';
import '../main.dart';
import 'exam_screen.dart';
import 'pro_screen.dart';
import 'theme.dart';
import 'widgets.dart';

/// Velilere toplu gönderim ekranını açar.
Future<void> openBulkParentSend(BuildContext context, Exam exam) async {
  final store = StoreScope.of(context);
  if (store.resultsOf(exam).where((r) => r.sheet.studentId != null).isEmpty) {
    return toast(context, tr('Göndermek için önce kâğıt okutun.'));
  }
  if (!await requirePro(context, ProFeature.bulkParent) || !context.mounted) return;
  await Navigator.of(context).push(MaterialPageRoute(builder: (_) => ParentSendScreen(examId: exam.id)));
}

/// Telefon numarasını WhatsApp bağlantısı için uluslararası biçime çevirir
/// (yalnız rakamlar, ülke koduyla). Türkiye'de 0 ile başlayan ya da 10
/// haneli 5xx numaralara 90 eklenir. Geçersizse null.
String? whatsappNumber(String phone, {String country = 'tr'}) {
  final raw = phone.trim();
  if (raw.isEmpty) return null;
  var d = raw.replaceAll(RegExp(r'\D'), '');
  if (raw.startsWith('+')) return d.length >= 8 ? d : null;
  if (d.startsWith('00')) return d.substring(2).length >= 8 ? d.substring(2) : null;
  if (country == 'tr') {
    if (d.length == 11 && d.startsWith('05')) d = '9$d';
    if (d.length == 10 && d.startsWith('5')) d = '90$d';
  }
  return d.length >= 8 ? d : null;
}

/// Bir sınavın karnelerini velilere sırayla gönderme ekranı: her öğrenci
/// için hazır mesajla paylaşım menüsü (PDF) ya da veli telefonu varsa
/// doğrudan WhatsApp sohbeti açılır. Gönderilenler işaretlenir.
class ParentSendScreen extends StatefulWidget {
  final String examId;
  const ParentSendScreen({super.key, required this.examId});

  @override
  State<ParentSendScreen> createState() => _ParentSendScreenState();
}

class _ParentSendScreenState extends State<ParentSendScreen> {
  bool _busy = false;

  Future<void> _sharePdf(Exam exam, Student st) async {
    setState(() => _busy = true);
    final store = StoreScope.of(context);
    final ok = await shareStudentCard(context, exam, st.id, askPro: false);
    if (!mounted) return;
    if (ok) store.markParentSent(exam.id, st.id);
    setState(() => _busy = false);
  }

  Future<void> _whatsapp(Exam exam, Student st, Result r, double mean) async {
    final store = StoreScope.of(context);
    final n = whatsappNumber(st.parentPhone, country: L10n.code);
    if (n == null) return toast(context, tr('Veli telefonu geçersiz. Öğrenciyi düzenleyip ülke koduyla yazın (ör. +90 532…).'));
    final text = inLanguageSync(st.parentLanguage, () => parentMessage(store, exam, st, r, mean, withSummary: true));
    final uri = Uri.parse('https://wa.me/$n?text=${Uri.encodeComponent(text)}');
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!mounted) return;
    if (ok) {
      store.markParentSent(exam.id, st.id);
    } else {
      toast(context, tr('WhatsApp açılamadı.'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final exam = store.examById(widget.examId);
    if (exam == null) return const Scaffold();
    final results = store.resultsOf(exam);
    final mean = ExamReport.build(exam, results).stats.mean;
    final rows = [
      for (final r in results)
        if (store.studentById[r.sheet.studentId] case final st?) (st, r),
    ]..sort((a, b) => alphaKey(a.$1.fullName).compareTo(alphaKey(b.$1.fullName)));
    final sent = rows.where((x) => store.parentSentFor(exam.id, x.$1.id)).length;
    final next = rows.where((x) => !store.parentSentFor(exam.id, x.$1.id)).firstOrNull;
    final phones = rows.where((x) => x.$1.parentPhone.trim().isNotEmpty).length;
    final t = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(tr('Velilere toplu gönder')),
          Text('${exam.name} · ${exam.className}', style: t.textTheme.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis),
        ]),
        actions: [
          if (sent > 0)
            IconButton(
              tooltip: tr('İşaretleri sıfırla'),
              icon: const Icon(Icons.restart_alt_rounded),
              onPressed: () {
                for (final x in rows) {
                  store.markParentSent(exam.id, x.$1.id, sent: false);
                }
              },
            ),
        ],
      ),
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 32), children: [
          HeroPanel(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(tr('{0} / {1} veliye gönderildi', [sent, rows.length]),
                  style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: rows.isEmpty ? 0 : sent / rows.length,
                  minHeight: 8,
                  color: NColors.emerald,
                  backgroundColor: Colors.white.withValues(alpha: 0.15),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                  tr('Sıradaki öğrencinin karnesi hazır mesajla açılır; WhatsApp\'ta veliyi seçip gönderin, sonra buraya dönün. Gönderilen işaretlenir, sıradakine geçilir.'),
                  style: const TextStyle(color: Colors.white70)),
              const SizedBox(height: 14),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                    backgroundColor: NColors.buttonBg(Theme.of(context).brightness == Brightness.dark),
                    foregroundColor: NColors.buttonFg(Theme.of(context).brightness == Brightness.dark)),
                onPressed: next == null || _busy ? null : () => _sharePdf(exam, next.$1),
                icon: _busy
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.send_rounded),
                label: Text(next == null ? tr('Hepsi gönderildi') : tr('Sıradaki: {0}', [next.$1.fullName])),
              ),
            ]),
          ),
          if (phones < rows.length)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Card(
                child: ListTile(
                  leading: const Icon(Icons.contact_phone_outlined),
                  title: Text(tr('{0} öğrencinin veli telefonu kayıtlı', [phones])),
                  subtitle: Text(tr('Telefonu kayıtlı velilere WhatsApp sohbeti doğrudan açılır. Telefonları Sınıflar ekranında öğrenciyi düzenleyerek ya da Excel listesine "Veli Telefonu" sütunu ekleyerek girebilirsiniz.')),
                ),
              ),
            ),
          SectionTitle(tr('Öğrenciler')),
          Card(
            clipBehavior: Clip.antiAlias,
            child: Column(children: [
              for (final (st, r) in rows)
                ListTile(
                  leading: IconButton(
                    tooltip: store.parentSentFor(exam.id, st.id) ? tr('Gönderildi') : tr('Gönderildi olarak işaretle'),
                    icon: Icon(
                      store.parentSentFor(exam.id, st.id) ? Icons.check_circle_rounded : Icons.radio_button_unchecked,
                      color: store.parentSentFor(exam.id, st.id) ? NColors.emerald : null,
                    ),
                    onPressed: () => store.markParentSent(exam.id, st.id, sent: !store.parentSentFor(exam.id, st.id)),
                  ),
                  title: Text(st.fullName, style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text([
                    '${tr('Puan')} ${fmt1(r.score)}',
                    if (st.parentPhone.trim().isNotEmpty) st.parentPhone.trim(),
                    if (st.parentLanguage.isNotEmpty && st.parentLanguage != L10n.code)
                      '${AppLanguage.byCode(st.parentLanguage).flag} ${AppLanguage.byCode(st.parentLanguage).name}',
                  ].join(' · ')),
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    if (st.parentPhone.trim().isNotEmpty)
                      IconButton(
                        tooltip: tr('WhatsApp\'ta mesaj olarak aç'),
                        icon: const Icon(Icons.chat_outlined),
                        onPressed: () => _whatsapp(exam, st, r, mean),
                      ),
                    IconButton(
                      tooltip: tr('Karneyi PDF olarak paylaş'),
                      icon: const Icon(Icons.picture_as_pdf_outlined),
                      onPressed: _busy ? null : () => _sharePdf(exam, st),
                    ),
                  ]),
                ),
            ]),
          ),
          const SizedBox(height: 12),
          Text(tr('Mesajlar sizin telefonunuzdan, sizin WhatsApp hesabınızdan gider. Netice hiçbir bilgiyi sunucuya göndermez.'),
              style: TextStyle(fontSize: 12, color: t.colorScheme.onSurface.withValues(alpha: 0.6))),
        ]),
      ),
    );
  }
}
