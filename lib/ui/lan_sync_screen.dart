import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../core/common_exam.dart';
import '../core/lan_sync.dart';
import '../core/models.dart';
import '../core/pro.dart';
import '../l10n/l10n.dart';
import '../main.dart';
import 'common_exam_ui.dart';
import 'pro_screen.dart';
import 'theme.dart';
import 'widgets.dart';

/// Wi-Fi eşitleme ekranını açar. [examId] verilirse o ortak sınav için
/// toplayıcı olunabilir ya da o şubenin sonuçları gönderilebilir; verilmezse
/// yalnızca ağdaki öğretmenden ortak sınav alınır.
Future<void> openLanSync(BuildContext context, {String? examId}) async {
  if (!await requirePro(context, ProFeature.lanSync) || !context.mounted) return;
  await Navigator.of(context).push(MaterialPageRoute(builder: (_) => LanSyncScreen(examId: examId)));
}

class LanSyncScreen extends StatefulWidget {
  final String? examId;
  const LanSyncScreen({super.key, this.examId});

  @override
  State<LanSyncScreen> createState() => _LanSyncScreenState();
}

class _LanSyncScreenState extends State<LanSyncScreen> {
  LanHost? _host;
  List<String> _addresses = const [];
  final _log = <String>[];

  bool _searching = false;
  final _peers = <LanPeer>[];
  String? _status;

  @override
  void dispose() {
    _host?.stop();
    super.dispose();
  }

  // ———————————————————————————— Toplayıcı

  Future<void> _startHost(Exam exam) async {
    final store = StoreScope.of(context);
    final e = makeCommon(store, exam);
    final host = LanHost(
      commonId: e.commonId!,
      teacher: store.school.teacher.trim(),
      examName: e.name,
      examText: () => exportCommonExam(store, store.examById(e.id) ?? e),
      onResults: (text, from) {
        final r = importCommonResults(store, text);
        final line = tr('{0}: {1} kâğıt alındı{2}', [r.className, r.sheets, from.isEmpty ? '' : ' · $from']);
        if (mounted) setState(() => _log.insert(0, line));
        return line;
      },
    );
    try {
      await host.start();
    } catch (e) {
      if (mounted) toast(context, tr('Ağ bağlantısı açılamadı: {0}', [e]));
      return;
    }
    final addrs = await LanHost.localAddresses();
    if (!mounted) {
      await host.stop();
      return;
    }
    setState(() {
      _host = host;
      _addresses = addrs;
    });
  }

  Future<void> _stopHost() async {
    await _host?.stop();
    if (mounted) setState(() => _host = null);
  }

  // ———————————————————————————— Gönderen

  Future<void> _search() async {
    setState(() {
      _searching = true;
      _peers.clear();
      _status = null;
    });
    await LanClient.discover(onFound: (p) {
      if (mounted && !_peers.contains(p)) setState(() => _peers.add(p));
    });
    if (mounted) setState(() => _searching = false);
  }

  Future<void> _manual() async {
    final c = TextEditingController();
    final addr = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Adresi elle yaz')),
        content: TextField(
          controller: c,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(labelText: tr('Toplayıcı cihazın adresi'), hintText: '192.168.1.20'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('Vazgeç'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, c.text.trim()), child: Text(tr('Bağlan'))),
        ],
      ),
    );
    if (addr == null || addr.isEmpty || !mounted) return;
    final parts = addr.split(':');
    final p = await LanClient.hello(parts.first, parts.length > 1 ? int.tryParse(parts[1]) ?? lanPort : lanPort,
        timeout: const Duration(seconds: 3));
    if (!mounted) return;
    if (p == null) return toast(context, tr('Bu adreste toplayıcı bulunamadı. İki cihaz aynı Wi-Fi\'da mı?'));
    setState(() {
      if (!_peers.contains(p)) _peers.add(p);
    });
    await _connect(p);
  }

  Future<String?> _askPin(LanPeer p) {
    final c = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Eşleşme kodu')),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(tr('{0} cihazının ekranındaki 4 haneli kodu yazın.', [p.teacher.isEmpty ? p.address : p.teacher])),
          const SizedBox(height: 12),
          TextField(
            controller: c,
            autofocus: true,
            maxLength: 4,
            keyboardType: TextInputType.number,
            style: const TextStyle(fontSize: 28, letterSpacing: 8, fontWeight: FontWeight.w800),
            textAlign: TextAlign.center,
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('Vazgeç'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, c.text.trim()), child: Text(tr('Tamam'))),
        ],
      ),
    );
  }

  String _error(Object e) => switch (e is LanException ? e.message : '') {
        'pin' => tr('Kod yanlış. Toplayıcı cihazdaki kodu yeniden yazın.'),
        'exam' => tr('Bu sonuçlar toplayıcıdaki ortak sınava ait değil.'),
        _ => tr('Bağlantı kurulamadı: {0}', [e]),
      };

  Future<void> _connect(LanPeer p) async {
    final store = StoreScope.of(context);
    final exam = widget.examId == null ? null : store.examById(widget.examId!);
    final pin = await _askPin(p);
    if (pin == null || pin.isEmpty || !mounted) return;
    setState(() => _status = tr('Bağlanılıyor…'));
    try {
      if (exam != null && store.sheetsOf(exam.id).isNotEmpty) {
        final text = exportCommonResults(store, exam);
        final summary = await LanClient.sendResults(p, pin, text, from: store.school.teacher.trim());
        if (!mounted) return;
        setState(() => _status = tr('Gönderildi. Toplayıcı: {0}', [summary]));
      } else {
        final text = await LanClient.fetchExam(p, pin);
        if (!mounted) return;
        setState(() => _status = null);
        await importNeticeText(context, text);
      }
    } catch (e) {
      if (mounted) setState(() => _status = _error(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final exam = widget.examId == null ? null : store.examById(widget.examId!);
    final t = Theme.of(context);
    final muted = t.colorScheme.onSurface.withValues(alpha: 0.6);
    final host = _host;
    final scanned = exam != null && store.sheetsOf(exam.id).isNotEmpty;

    return Scaffold(
      appBar: AppBar(title: Text(tr('Wi-Fi ile eşitle'))),
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 32), children: [
          Text(
            tr('Aynı Wi-Fi ağındaki öğretmenler ortak sınavı ve sonuçları internet, hesap ya da dosya göndermeden paylaşır. Bir cihaz toplayıcı olur, diğerleri ona bağlanır.'),
            style: TextStyle(color: muted),
          ),
          if (exam != null) ...[
            SectionTitle(tr('Bu cihaz toplasın')),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: host == null
                    ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(tr('"{0}" sınavının diğer şubelerdeki sonuçları bu cihazda birleşsin.', [exam.name])),
                        const SizedBox(height: 12),
                        FilledButton.icon(
                          onPressed: () => _startHost(exam),
                          icon: const Icon(Icons.wifi_tethering_rounded),
                          label: Text(tr('Toplamaya başla')),
                        ),
                      ])
                    : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          const Icon(Icons.wifi_tethering_rounded, color: NColors.emerald),
                          const SizedBox(width: 8),
                          Expanded(child: Text(tr('Toplanıyor · ekranı açık tutun'), style: const TextStyle(fontWeight: FontWeight.w700))),
                        ]),
                        const SizedBox(height: 14),
                        Center(
                          child: Column(children: [
                            Text(tr('EŞLEŞME KODU'), style: TextStyle(fontSize: 11, letterSpacing: 1.2, color: muted, fontWeight: FontWeight.w700)),
                            Text(host.pin,
                                style: const TextStyle(fontSize: 44, fontWeight: FontWeight.w800, letterSpacing: 10, fontFeatures: tabular)),
                            if (_addresses.isNotEmpty)
                              Text(tr('Adres: {0}', [_addresses.map((a) => host.port == lanPort ? a : '$a:${host.port}').join(' · ')]),
                                  style: TextStyle(color: muted)),
                          ]),
                        ),
                        const SizedBox(height: 10),
                        Text(tr('Diğer öğretmenler: Ortak sınav › Wi-Fi ile eşitle › Ara, sonra bu kodu yazar.'), style: TextStyle(color: muted)),
                        if (_log.isNotEmpty) ...[
                          const Divider(height: 24),
                          for (final l in _log)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 4),
                              child: Row(children: [
                                const Icon(Icons.check_circle_rounded, size: 18, color: NColors.emerald),
                                const SizedBox(width: 6),
                                Expanded(child: Text(l)),
                              ]),
                            ),
                        ],
                        const SizedBox(height: 10),
                        OutlinedButton.icon(onPressed: _stopHost, icon: const Icon(Icons.stop_rounded), label: Text(tr('Durdur'))),
                      ]),
              ),
            ),
          ],
          SectionTitle(exam == null
              ? tr('Ağdaki öğretmenden sınav al')
              : (scanned ? tr('Bu şubenin sonuçlarını gönder') : tr('Ağdaki öğretmenden sınav al'))),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text(scanned
                    ? tr('{0} şubesinin {1} kâğıdı, toplayıcı öğretmene gönderilir. Kâğıt fotoğrafları ve veli telefonları gönderilmez.',
                        [exam.className, store.sheetsOf(exam.id).length])
                    : tr('Toplayıcı öğretmenin ortak sınavı (cevap anahtarı, kitapçıklar, puanlama) bu cihaza eklenir.')),
                const SizedBox(height: 12),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  FilledButton.icon(
                    onPressed: _searching || host != null ? null : _search,
                    icon: _searching
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.wifi_find_rounded),
                    label: Text(_searching ? tr('Aranıyor…') : tr('Ara')),
                  ),
                  OutlinedButton.icon(
                    onPressed: host != null ? null : _manual,
                    icon: const Icon(Icons.keyboard_alt_outlined),
                    label: Text(tr('Adresi elle yaz')),
                  ),
                ]),
                if (_peers.isNotEmpty) const SizedBox(height: 8),
                for (final p in _peers)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const IconBadge(Icons.phone_android_rounded),
                    title: Text(p.teacher.isEmpty ? tr('Netice cihazı') : p.teacher, style: const TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: Text('${p.exam} · ${p.address}'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _connect(p),
                  ),
                if (!_searching && _peers.isEmpty && _status == null)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Text(tr('Toplayıcı cihazda "Toplamaya başla"ya dokunulmuş olmalı ve iki cihaz aynı Wi-Fi\'a bağlı olmalı.'),
                        style: TextStyle(color: muted, fontSize: 12.5)),
                  ),
                if (_status != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Text(_status!, style: const TextStyle(fontWeight: FontWeight.w700)),
                  ),
              ]),
            ),
          ),
        ]),
      ),
    );
  }
}
