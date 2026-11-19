import 'package:material_ui/material_ui.dart';

import '../core/cloud.dart';
import '../main.dart';
import 'pro_screen.dart';
import '../core/pro.dart';
import 'theme.dart';
import 'widgets.dart';
import '../l10n/l10n.dart';

/// Ayarların başındaki hesap kartı: Google ile giriş ve Drive yedeği.
class AccountCard extends StatefulWidget {
  const AccountCard({super.key});
  @override
  State<AccountCard> createState() => _AccountCardState();
}

class _AccountCardState extends State<AccountCard> {
  bool _busy = false;

  Future<void> _run(Future<void> Function() job, {String? ok}) async {
    setState(() => _busy = true);
    try {
      await job();
      if (mounted && ok != null) toast(context, ok);
    } on _Cancelled {
      // Kullanıcı vazgeçti.
    } catch (e) {
      if (mounted) toast(context, tr('İşlem tamamlanamadı: {0}', [_friendly(e)]));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _friendly(Object e) {
    final s = '$e';
    // Credential Manager yapılandırma hatalarını da "canceled" diye bildirir;
    // ayrıntısı varsa gösterilir ki sorun anlaşılsın.
    if (s.contains('GoogleSignInExceptionCode.canceled')) {
      final m = RegExp(r'canceled, (.*?)(, null)?\)$').firstMatch(s);
      final d = m?.group(1);
      return d == null || d == 'null' || d.isEmpty ? tr('giriş iptal edildi.') : '${tr('giriş iptal edildi.')} ($d)';
    }
    if (s.contains('canceled') || s.contains('cancel')) return tr('giriş iptal edildi.');
    if (s.contains('SocketException') || s.contains('Failed host')) return tr('internet bağlantısı yok.');
    return s.length > 200 ? '${s.substring(0, 200)}…' : s;
  }

  String _ago(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 1) return tr('az önce');
    if (d.inHours < 1) return tr('{0} dk önce', [d.inMinutes]);
    if (d.inDays < 1) return tr('{0} sa önce', [d.inHours]);
    return tr('{0} gün önce', [d.inDays]);
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final t = Theme.of(context);
    final muted = t.colorScheme.onSurface.withValues(alpha: 0.6);
    final cloud = CloudService.instance;

    if (!CloudConfig.platformSupported) {
      return Card(
        child: ListTile(
          leading: const IconBadge(Icons.cloud_off_outlined, color: NColors.gray),
          title: Text(tr('Google hesabı'), style: TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text(tr('Google ile giriş ve Drive yedeği telefon uygulamasında. Bilgisayarda "Yedeği dosyaya kaydet / geri yükle" ile taşıyabilirsiniz.')),
        ),
      );
    }
    if (!CloudConfig.configured) {
      return Card(
        child: ListTile(
          leading: IconBadge(Icons.cloud_outlined, color: NColors.amber),
          title: Text(tr('Google ile giriş'), style: TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text(tr('Yakında: Google hesabınızla girip verilerinizi kendi Google Drive\'ınıza yedekleyebileceksiniz.')),
        ),
      );
    }

    final signedIn = store.googleEmail != null;
    if (!signedIn) {
      return Card(
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const IconBadge(Icons.account_circle_outlined, color: NColors.emerald),
              const SizedBox(width: 12),
              Expanded(
                child: Text(tr('Google hesabınızla giriş yapın'),
                    style: t.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
              ),
            ]),
            const SizedBox(height: 8),
            Text(
              tr('Verileriniz yine bu cihazda kalır. Giriş yaparsanız her gün kendi Google Drive\'ınıza gizli bir yedek alınır; telefon değişse de sınıflarınız ve sınavlarınız kaybolmaz.'),
              style: TextStyle(color: muted, height: 1.4),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: NColors.ink,
                    side: BorderSide(color: t.colorScheme.outlineVariant)),
                onPressed: _busy
                    ? null
                    : () => _run(() async {
                          if (!await requirePro(context, ProFeature.cloudBackup)) throw _Cancelled();
                          await cloud.signIn(store);
                          // İlk girişte Drive'da yedek varsa sor, yoksa hemen yedekle.
                          final info = await cloud.latest();
                          if (!mounted) return;
                          if (info != null && store.sheets.length + store.exams.length <= 2) {
                            final yes = await _askRestore(info);
                            if (yes == true) {
                              await cloud.restore(store);
                              return;
                            }
                          }
                          await cloud.backup(store);
                        }, ok: tr('Giriş yapıldı. Verileriniz Google Drive\'a yedeklendi.')),
                icon: _busy
                    ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const _GoogleG(),
                label: Text(tr('Google ile giriş yap')),
              ),
            ),
          ]),
        ),
      );
    }

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(children: [
        ListTile(
          contentPadding: const EdgeInsets.fromLTRB(16, 8, 8, 4),
          leading: CircleAvatar(
            backgroundColor: NColors.emerald.withValues(alpha: 0.18),
            child: Text((store.googleName ?? store.googleEmail ?? '?').characters.first.toUpperCase(),
                style: const TextStyle(fontWeight: FontWeight.w800, color: NColors.emerald)),
          ),
          title: Text(store.googleName ?? tr('Google hesabı'), style: const TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text(store.googleEmail!),
          trailing: TextButton(
            onPressed: _busy ? null : () => _run(() => cloud.signOut(store), ok: tr('Çıkış yapıldı.')),
            child: Text(tr('Çıkış')),
          ),
        ),
        const Divider(height: 1),
        ListTile(
          leading: Icon(store.lastCloudBackup == null ? Icons.cloud_queue_rounded : Icons.cloud_done_rounded,
              color: NColors.emerald),
          title: Text(tr('Google Drive yedeği')),
          subtitle: Text(store.lastCloudBackup == null ? tr('Henüz yedek alınmadı') : tr('Son yedek: {0}', [_ago(store.lastCloudBackup!)])),
          trailing: _busy
              ? const SizedBox.square(dimension: 22, child: CircularProgressIndicator(strokeWidth: 2))
              : TextButton(
                  onPressed: () => _run(() => cloud.backup(store), ok: tr('Google Drive\'a yedeklendi.')),
                  child: Text(tr('Şimdi yedekle')),
                ),
        ),
        SwitchListTile(
          value: store.cloudAuto,
          onChanged: store.setCloudAuto,
          title: Text(tr('Her gün otomatik yedekle')),
          subtitle: Text(tr('İnternet varken, günde bir kez arka planda')),
        ),
        ListTile(
          leading: const Icon(Icons.cloud_download_outlined),
          title: Text(tr('Drive\'daki yedeği geri yükle')),
          subtitle: Text(tr('Yeni telefona geçtiğinizde kullanın')),
          onTap: _busy
              ? null
              : () => _run(() async {
                    final info = await cloud.latest();
                    if (info == null) throw tr('Drive\'da yedek bulunamadı.');
                    if (await _askRestore(info) != true) throw _Cancelled();
                    await cloud.restore(store);
                  }, ok: tr('Yedek geri yüklendi.')),
        ),
        ListTile(
          leading: const Icon(Icons.cloud_off_rounded, color: NColors.coral),
          title: Text(tr('Drive\'daki yedeği sil')),
          subtitle: Text(tr('Yedek, Google hesabınızdan kalıcı olarak kaldırılır')),
          onTap: _busy
              ? null
              : () => _run(() async {
                    final ok = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: Text(tr('Drive yedeği silinsin mi?')),
                        content: Text(tr('Google Drive\'daki Netice yedeği kalıcı olarak silinir. Bu cihazdaki verilere dokunulmaz. Otomatik Drive yedeği açıksa ertesi gün yeniden yedek alınır.')),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Vazgeç'))),
                          FilledButton(
                              style: FilledButton.styleFrom(backgroundColor: NColors.coral),
                              onPressed: () => Navigator.pop(ctx, true),
                              child: Text(tr('Sil'))),
                        ],
                      ),
                    );
                    if (ok != true) throw _Cancelled();
                    if (!await cloud.deleteBackup(store)) throw tr('Drive\'da silinecek yedek yok.');
                  }, ok: tr('Drive yedeği silindi.')),
        ),
      ]),
    );
  }

  Future<bool?> _askRestore(CloudBackupInfo info) => showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(tr('Drive\'daki yedek yüklensin mi?')),
          content: Text(tr('{0}yedek bulundu. Bu cihazdaki verilerin yerine geçer; mevcut hâlin bir kopyası önce otomatik yedeklere eklenir.', [info.modified == null ? '' : tr('{0} tarihli ', ['${dmy(info.modified!.toLocal())} ${hm(info.modified!.toLocal())}'])])),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Vazgeç'))),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Geri yükle'))),
          ],
        ),
      );
}

/// Google "G" işareti (dört renkli).
class _GoogleG extends StatelessWidget {
  const _GoogleG();
  @override
  Widget build(BuildContext context) => SizedBox.square(dimension: 20, child: CustomPaint(painter: _GPainter()));
}

class _GPainter extends CustomPainter {
  @override
  void paint(Canvas c, Size s) {
    final r = Rect.fromLTWH(s.width * 0.1, s.height * 0.1, s.width * 0.8, s.height * 0.8);
    final w = s.width * 0.18;
    Paint p(Color col) => Paint()
      ..color = col
      ..style = PaintingStyle.stroke
      ..strokeWidth = w;
    const d = 3.14159265 / 180;
    c.drawArc(r, -40 * d, -100 * d, false, p(const Color(0xFFEA4335)));
    c.drawArc(r, -140 * d, -90 * d, false, p(const Color(0xFFFBBC05)));
    c.drawArc(r, -230 * d, -90 * d, false, p(const Color(0xFF34A853)));
    c.drawArc(r, -320 * d, -40 * d, false, p(const Color(0xFF4285F4)));
    c.drawRect(Rect.fromLTWH(s.width * 0.5, s.height * 0.5 - w / 2, s.width * 0.4, w), Paint()..color = const Color(0xFF4285F4));
  }

  @override
  bool shouldRepaint(_GPainter o) => false;
}

class _Cancelled implements Exception {}
