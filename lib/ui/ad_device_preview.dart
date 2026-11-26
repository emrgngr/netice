import 'package:material_ui/material_ui.dart';

import '../core/ads.dart';
import 'ad_slot.dart';
import 'theme.dart';

enum PreviewDevice {
  phone('Telefon', Icons.smartphone_rounded, Size(390, 780)),
  tablet('Tablet', Icons.tablet_mac_rounded, Size(820, 1080)),
  desktop('Bilgisayar', Icons.desktop_windows_rounded, Size(1280, 760));

  final String label;
  final IconData icon;
  final Size size;
  const PreviewDevice(this.label, this.icon, this.size);
}

/// Reklamın telefonda, tablette ve bilgisayarda nasıl duracağını gösterir.
/// (Yönetici ekranı; metinler Türkçedir.)
class AdDevicePreviewScreen extends StatefulWidget {
  final Ad ad;
  final PreviewDevice initial;
  final bool initialDark;
  const AdDevicePreviewScreen({
    super.key,
    required this.ad,
    this.initial = PreviewDevice.phone,
    this.initialDark = false,
  });

  @override
  State<AdDevicePreviewScreen> createState() => _AdDevicePreviewScreenState();
}

class _AdDevicePreviewScreenState extends State<AdDevicePreviewScreen> {
  late PreviewDevice _device = widget.initial;
  late bool _dark = widget.initialDark;
  bool _b = false;

  @override
  Widget build(BuildContext context) {
    final ad = widget.ad;
    final muted = Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6);
    final files = adDisplayFiles(ad, dark: _dark, variantB: _b);
    return Scaffold(
      appBar: AppBar(title: const Text('Cihazlarda önizle')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: SegmentedButton<PreviewDevice>(
              showSelectedIcon: false,
              segments: [
                for (final d in PreviewDevice.values) ButtonSegment(value: d, icon: Icon(d.icon), label: Text(d.label)),
              ],
              selected: {_device},
              onSelectionChanged: (s) => setState(() => _device = s.first),
            ),
          ),
          Wrap(
            spacing: 8,
            alignment: WrapAlignment.center,
            children: [
              FilterChip(
                avatar: const Icon(Icons.dark_mode_outlined, size: 18),
                label: const Text('Gece modu'),
                selected: _dark,
                onSelected: (v) => setState(() => _dark = v),
              ),
              if (ad.hasAB)
                FilterChip(
                  avatar: const Icon(Icons.filter_2_outlined, size: 18),
                  label: const Text('B görseli'),
                  selected: _b,
                  onSelected: (v) => setState(() => _b = v),
                ),
            ],
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: files == null
                  ? Center(
                      child: Text('Önce görsel ya da video seçin.', style: TextStyle(color: muted)),
                    )
                  : FittedBox(
                      child: DeviceFrame(
                        device: _device,
                        dark: _dark,
                        child: MockPage(
                          device: _device,
                          dark: _dark,
                          ad: AdView(
                            key: ValueKey('${_device.name}$_dark$_b'),
                            ad: ad,
                            files: files,
                            banner: ad.format == AdFormat.banner,
                            showQr: _device == PreviewDevice.desktop,
                            onClose: () {},
                          ),
                          banner: ad.format == AdFormat.banner,
                        ),
                      ),
                    ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Text(
              _device == PreviewDevice.desktop
                  ? 'Bilgisayarda bağlantı varsa köşede QR kodu çıkar; kullanıcı telefonuyla okutup sayfayı açar.'
                  : 'Gerçek boyuta göre küçültülmüş görünüm.',
              textAlign: TextAlign.center,
              style: TextStyle(color: muted, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

/// Cihaz çerçevesi.
class DeviceFrame extends StatelessWidget {
  final PreviewDevice device;
  final bool dark;
  final Widget child;
  const DeviceFrame({super.key, required this.device, required this.dark, required this.child});

  @override
  Widget build(BuildContext context) {
    final s = device.size;
    final screen = MediaQuery(
      data: MediaQuery.of(context).copyWith(size: s, padding: EdgeInsets.zero, textScaler: TextScaler.noScaling),
      child: SizedBox.fromSize(size: s, child: child),
    );
    if (device == PreviewDevice.desktop) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: const Color(0xFF1B1F2A), borderRadius: BorderRadius.circular(18)),
            child: ClipRRect(borderRadius: BorderRadius.circular(6), child: screen),
          ),
          Container(width: 160, height: 70, color: const Color(0xFF2A2F3C)),
          Container(
            width: 380,
            height: 16,
            decoration: BoxDecoration(color: const Color(0xFF2A2F3C), borderRadius: BorderRadius.circular(8)),
          ),
        ],
      );
    }
    final phone = device == PreviewDevice.phone;
    return Container(
      padding: EdgeInsets.all(phone ? 14 : 22),
      decoration: BoxDecoration(
        color: const Color(0xFF1B1F2A),
        borderRadius: BorderRadius.circular(phone ? 54 : 40),
        boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 24, offset: Offset(0, 10))],
      ),
      child: ClipRRect(borderRadius: BorderRadius.circular(phone ? 42 : 22), child: screen),
    );
  }
}

/// Örnek uygulama sayfası (ana sayfa benzeri) ve içinde reklam.
class MockPage extends StatelessWidget {
  final PreviewDevice device;
  final bool dark;
  final Widget ad;
  final bool banner;
  const MockPage({super.key, required this.device, required this.dark, required this.ad, required this.banner});

  @override
  Widget build(BuildContext context) {
    final ad = ClipRRect(borderRadius: BorderRadius.circular(banner ? 10 : 18), child: this.ad);
    final bg = dark ? NColors.darkBg : NColors.ivory;
    final card = dark ? NColors.darkSurface : Colors.white;
    final line = dark ? Colors.white.withValues(alpha: 0.14) : NColors.ink.withValues(alpha: 0.09);
    final fg = dark ? NColors.nightInk : NColors.ink;

    Widget block(double h) => Container(
      height: h,
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(color: card, borderRadius: BorderRadius.circular(16)),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(width: 140, height: 12, color: line),
          const SizedBox(height: 10),
          Container(width: double.infinity, height: 9, color: line),
          const SizedBox(height: 7),
          Container(width: 200, height: 9, color: line),
        ],
      ),
    );

    final content = ListView(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      children: [
        block(96),
        if (!banner) ad,
        if (!banner) const SizedBox(height: 4),
        block(110),
        block(110),
        block(110),
      ],
    );

    final header = Container(
      height: device == PreviewDevice.desktop ? 56 : 92,
      padding: EdgeInsets.fromLTRB(18, device == PreviewDevice.desktop ? 0 : 36, 18, 0),
      color: bg,
      alignment: Alignment.centerLeft,
      child: Text(
        'Netice',
        style: TextStyle(color: fg, fontSize: 22, fontWeight: FontWeight.w900),
      ),
    );

    final body = Column(
      children: [
        header,
        Expanded(child: content),
        if (banner) Padding(padding: const EdgeInsets.fromLTRB(12, 6, 12, 8), child: ad),
        if (device != PreviewDevice.desktop)
          Container(
            height: 64,
            color: card,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                for (final i in [
                  Icons.home_rounded,
                  Icons.quiz_outlined,
                  Icons.bar_chart_rounded,
                  Icons.settings_outlined,
                ])
                  Icon(i, color: fg.withValues(alpha: 0.6)),
              ],
            ),
          ),
      ],
    );

    return Material(
      color: bg,
      child: device == PreviewDevice.desktop
          ? Row(
              children: [
                Container(
                  width: 230,
                  color: NColors.ink,
                  padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Netice',
                        style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900),
                      ),
                      const SizedBox(height: 24),
                      for (var i = 0; i < 7; i++)
                        Container(
                          margin: const EdgeInsets.only(bottom: 14),
                          height: 12,
                          width: 120 + (i % 3) * 20,
                          color: Colors.white.withValues(alpha: 0.18),
                        ),
                    ],
                  ),
                ),
                Expanded(
                  child: Center(
                    child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 760), child: body),
                  ),
                ),
              ],
            )
          : body,
    );
  }
}
