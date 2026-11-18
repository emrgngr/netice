import 'package:material_ui/material_ui.dart';

import '../main.dart';
import 'school_screen.dart';
import 'theme.dart';
import 'widgets.dart';

/// İlk açılış rehberi: Netice'yi dört adımda tanıtır.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _Step {
  final IconData icon;
  final String title;
  final String body;
  final List<String> points;
  const _Step(this.icon, this.title, this.body, this.points);
}

const _steps = [
  _Step(Icons.auto_awesome_rounded, 'Netice\'ye hoş geldiniz',
      'Optik kâğıtları telefonunuzla okutun; puanlar, analizler ve raporlar kendiliğinden hazırlansın.', [
    'İnternet gerekmez, veriler yalnızca bu cihazda kalır',
    'Bir kâğıt ortalama 2 saniyede okunur',
    'Emin olunamayan işaretler size sorulur, sessizce karar verilmez',
  ]),
  _Step(Icons.account_balance_outlined, '1. Okul bilgileri',
      'Okul adı, il/ilçe, müdür ve öğretmen adını bir kez girin. Tüm raporlar resmi yazı başlığıyla çıkar.', [
    'T.C. / Kaymakamlık / Okul Müdürlüğü başlığı',
    'Öğretmen ve müdür imza alanı',
    'İstediğiniz zaman Ayarlar\'dan değiştirebilirsiniz',
  ]),
  _Step(Icons.groups_outlined, '2. Sınıflarınızı aktarın',
      'Sınıflar sekmesinden e-Okul\'dan aldığınız Excel listesini seçin. Tüm şubeler tek dosyadan ayrılır.', [
    'Gerekli sütunlar: Okul No, Adı, Soyadı, Sınıf',
    'Tek tek öğrenci de ekleyebilirsiniz',
    'Örnek sınıf ve sınavla hemen deneyebilirsiniz',
  ]),
  _Step(Icons.document_scanner_outlined, '3. Sınav, form, okut',
      'Yeni sınav oluşturun, cevap anahtarını girin, Form yazdır ile isimli formları basın ve Okut\'a dokunun.', [
    'Kâğıtları art arda kameraya gösterin, okuma kendiliğinden olur',
    'Sonuçlar, madde analizi ve karneler anında hazır',
    'Her PDF önce önizlenir, sonra yazdırılır veya paylaşılır',
  ]),
];

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _page = PageController();
  int _i = 0;

  void _finish() {
    StoreScope.of(context).finishOnboarding();
    Navigator.of(context).pop();
  }

  @override
  void dispose() {
    _page.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final last = _i == _steps.length - 1;
    return Scaffold(
      backgroundColor: NColors.ink,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Column(children: [
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: _finish,
                  child: const Text('Atla', style: TextStyle(color: Colors.white70)),
                ),
              ),
              Expanded(
                child: PageView.builder(
                  controller: _page,
                  itemCount: _steps.length,
                  onPageChanged: (i) => setState(() => _i = i),
                  itemBuilder: (_, i) => _StepView(step: _steps[i], first: i == 0),
                ),
              ),
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                for (var i = 0; i < _steps.length; i++)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    width: i == _i ? 22 : 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: i == _i ? NColors.emerald : Colors.white24,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
              ]),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
                child: Column(children: [
                  if (_i == 1)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.white, side: const BorderSide(color: Colors.white38)),
                          onPressed: () =>
                              Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SchoolScreen())),
                          icon: const Icon(Icons.edit_outlined),
                          label: const Text('Okul bilgilerini şimdi gir'),
                        ),
                      ),
                    ),
                  GlowButton(
                    label: last ? 'Başla' : 'Devam',
                    icon: last ? Icons.check_rounded : Icons.arrow_forward_rounded,
                    height: 56,
                    onPressed: last
                        ? _finish
                        : () => _page.nextPage(duration: const Duration(milliseconds: 280), curve: Curves.easeOut),
                  ),
                ]),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

class _StepView extends StatelessWidget {
  final _Step step;
  final bool first;
  const _StepView({required this.step, required this.first});

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(28, 12, 28, 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (first)
            const AppLogo(size: 72)
          else
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: NColors.emerald.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(22),
              ),
              child: Icon(step.icon, color: NColors.emerald, size: 36),
            ),
          const SizedBox(height: 28),
          Text(step.title,
              style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w800, height: 1.15)),
          const SizedBox(height: 12),
          Text(step.body, style: const TextStyle(color: Colors.white70, fontSize: 16, height: 1.45)),
          const SizedBox(height: 24),
          for (final p in step.points)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Padding(
                  padding: EdgeInsets.only(top: 2),
                  child: Icon(Icons.check_circle_rounded, color: NColors.emerald, size: 20),
                ),
                const SizedBox(width: 10),
                Expanded(child: Text(p, style: const TextStyle(color: Colors.white, fontSize: 15, height: 1.35))),
              ]),
            ),
        ]),
      );
}
