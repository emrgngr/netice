import 'dart:io';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:share_plus/share_plus.dart';

import '../core/legal.dart';
import '../core/referral.dart';
import '../l10n/l10n.dart';
import '../main.dart';
import 'theme.dart';
import 'widgets.dart';

/// Arkadaşını davet et: kendi davet kodunu paylaşma, arkadaşın kodunu girme
/// (%15 indirim) ve arkadaştan gelen teşekkür kodunu girme (1 ay ek Pro).
/// Hesap ve internet gerekmez.
class InviteScreen extends StatefulWidget {
  const InviteScreen({super.key});

  @override
  State<InviteScreen> createState() => _InviteScreenState();
}

class _InviteScreenState extends State<InviteScreen> {
  final _invite = TextEditingController();
  final _thanks = TextEditingController();
  String? _inviteError;
  String? _thanksError;

  @override
  void dispose() {
    _invite.dispose();
    _thanks.dispose();
    super.dispose();
  }

  Future<void> _share(String text) async {
    final box = context.findRenderObject() as RenderBox?;
    final origin = box == null ? null : box.localToGlobal(Offset.zero) & box.size;
    if (Platform.isAndroid || Platform.isIOS) {
      await SharePlus.instance.share(ShareParams(text: text, sharePositionOrigin: origin));
    } else {
      await Clipboard.setData(ClipboardData(text: text));
      if (mounted) toast(context, tr('Kopyalandı. İstediğiniz yere yapıştırabilirsiniz.'));
    }
  }

  void _applyInvite() {
    final err = StoreScope.of(context).applyInvite(_invite.text);
    setState(() => _inviteError = err);
    if (err == null) {
      _invite.clear();
      toast(context, tr('Davet kodu uygulandı. Yıllık abonelik %15 indirimli.'));
    }
  }

  void _redeemThanks() {
    final store = StoreScope.of(context);
    final err = store.redeemThanks(_thanks.text);
    setState(() => _thanksError = err);
    if (err == null) {
      _thanks.clear();
      toast(context, tr('Teşekkürler! 1 ay ek Pro eklendi: {0} tarihine kadar.', [L10n.date(store.bonusProUntil!)]));
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final t = Theme.of(context);
    final muted = t.colorScheme.onSurface.withValues(alpha: 0.6);
    final code = store.myInviteCode;
    final shareText = tr(
      'Optik kâğıtları Netice ile telefondan okuyorum. Netice Pro\'ya geçerken davet kodumu girersen yıllık abonelik %15 indirimli: {0}\n{1}',
      [code, playStoreUrl],
    );
    return Scaffold(
      appBar: AppBar(title: Text(tr('Arkadaşını davet et'))),
      body: Watermark(
        child: ListView(
          padding: EdgeInsets.fromLTRB(20, 8, 20, 40 + MediaQuery.paddingOf(context).bottom),
          children: [
            // Kendi davet kodu.
            Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const IconBadge(Icons.card_giftcard_rounded, color: Color(0xFFD4A24C)),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            tr('Davet et, 1 ay Pro kazan'),
                            style: t.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      tr(
                        'Kodunuzu öğretmen arkadaşlarınıza gönderin. Arkadaşınız yıllık Pro\'yu %15 indirimle alır; size gönderdiği teşekkür kodunu girince siz de 1 ay ek Pro kazanırsınız.',
                      ),
                      style: TextStyle(color: muted),
                    ),
                    const SizedBox(height: 14),
                    Center(
                      child: SelectableText(code, style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w900, letterSpacing: 3)),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        alignment: WrapAlignment.center,
                        children: [
                          FilledButton.icon(
                            onPressed: () => _share(shareText),
                            icon: const Icon(Icons.share_rounded),
                            label: Text(tr('Kodumu paylaş')),
                          ),
                          OutlinedButton.icon(
                            onPressed: () async {
                              await Clipboard.setData(ClipboardData(text: code));
                              if (context.mounted) toast(context, tr('Davet kodu kopyalandı.'));
                            },
                            icon: const Icon(Icons.copy_rounded),
                            label: Text(tr('Kopyala')),
                          ),
                        ],
                      ),
                    ),
                    if (store.redeemedThanks.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Text(
                        tr('{0} arkadaşınız katıldı. Ek Pro: {1} tarihine kadar.', [
                          store.redeemedThanks.length,
                          L10n.date(store.bonusProUntil!),
                        ]),
                        style: const TextStyle(color: NColors.emerald, fontWeight: FontWeight.w700),
                      ),
                    ],
                  ],
                ),
              ),
            ),

            // İndirimli aboneliği aldıktan sonra: davet edene teşekkür kodu.
            if (store.thanksCode != null) ...[
              SectionTitle(tr('Davet edene teşekkür kodunuz')),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(tr('Bu kodu sizi davet eden kişiye gönderin; o da 1 ay ek Pro kazansın.'), style: TextStyle(color: muted)),
                      const SizedBox(height: 10),
                      SelectableText(store.thanksCode!, style: const TextStyle(fontWeight: FontWeight.w800, letterSpacing: 1.2)),
                      const SizedBox(height: 10),
                      FilledButton.icon(
                        onPressed: () => _share(
                          tr(
                            'Davetin için teşekkürler! Netice\'de Profil > Arkadaşını davet et bölümüne bu teşekkür kodunu gir, 1 ay ek Pro kazan: {0}',
                            [store.thanksCode!],
                          ),
                        ),
                        icon: const Icon(Icons.send_rounded),
                        label: Text(tr('Teşekkür kodunu gönder')),
                      ),
                    ],
                  ),
                ),
              ),
            ],

            // Arkadaşın davet kodu.
            if (!store.hasSubscription && store.thanksCode == null) ...[
              SectionTitle(tr('Davet kodunuz mu var?')),
              if (store.appliedInvite != null)
                Card(
                  child: ListTile(
                    leading: const IconBadge(Icons.local_offer_outlined, color: NColors.emerald),
                    title: Text(
                      tr('Davet kodu uygulandı: {0}', [store.appliedInvite!]),
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    subtitle: Text(tr('Yıllık abonelik ilk yıl %15 indirimli. Pro ekranından alabilirsiniz.')),
                    trailing: IconButton(tooltip: tr('Kaldır'), onPressed: store.clearInvite, icon: const Icon(Icons.close_rounded)),
                  ),
                )
              else ...[
                Text(
                  tr('Sizi davet eden öğretmenin kodunu girin; yıllık abonelik ilk yıl %15 indirimli olur.'),
                  style: TextStyle(color: muted),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _invite,
                  textCapitalization: TextCapitalization.characters,
                  decoration: InputDecoration(labelText: tr('Davet kodu'), hintText: 'ABCD-EFGH', errorText: _inviteError),
                  onSubmitted: (_) => _applyInvite(),
                ),
                const SizedBox(height: 10),
                FilledButton(onPressed: _applyInvite, child: Text(tr('Uygula'))),
              ],
            ],

            // Arkadaştan gelen teşekkür kodu.
            SectionTitle(tr('Teşekkür kodu mu geldi?')),
            Text(
              tr(
                'Davet ettiğiniz arkadaşınız Pro\'ya geçince size bir teşekkür kodu gönderir. Buraya girin, 1 ay ek Pro kazanın (en fazla {0} ay).',
                [Referral.maxRewards],
              ),
              style: TextStyle(color: muted),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _thanks,
              textCapitalization: TextCapitalization.characters,
              decoration: InputDecoration(labelText: tr('Teşekkür kodu'), hintText: 'TSK-…', errorText: _thanksError),
              onSubmitted: (_) => _redeemThanks(),
            ),
            const SizedBox(height: 10),
            OutlinedButton(onPressed: _redeemThanks, child: Text(tr('Ek Pro\'yu al'))),
            const SizedBox(height: 18),
            Text(
              tr(
                'Kodlar internetsiz çalışır; hesap açmanız gerekmez ve hiçbir bilginiz dışarı gönderilmez. İndirim yalnızca yıllık aboneliğin ilk yılında geçerlidir. Ek Pro süresi kodu girdiğiniz gün başlar.',
              ),
              style: TextStyle(color: muted, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}
