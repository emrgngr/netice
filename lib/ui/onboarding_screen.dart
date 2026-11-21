import 'package:material_ui/material_ui.dart';

import '../main.dart';
import 'illustrations.dart';
import 'school_screen.dart';
import 'theme.dart';
import 'widgets.dart';
import '../l10n/l10n.dart';

/// İlk açılış rehberi: Netice'yi dört adımda tanıtır.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _Step {
  final IllustrationKind icon;
  final String title;
  final String body;
  final List<String> points;
  const _Step(this.icon, this.title, this.body, this.points);
}

List<_Step> get _steps => [
  _Step(IllustrationKind.welcome, tr('Netice\'ye hoş geldiniz'),
      tr('Optik kâğıtları telefonunuzla okutun; puanlar, analizler ve raporlar kendiliğinden hazırlansın.'), [
    tr('İnternet gerekmez, veriler yalnızca bu cihazda kalır'),
    tr('Üçüncü taraf reklam yok, sizi izleyen reklam ağı yok'),
    tr('Bir kâğıt ortalama 2 saniyede okunur'),
    tr('Emin olunamayan işaretler size sorulur, sessizce karar verilmez'),
  ]),
  _Step(IllustrationKind.school, tr('1. Kurum bilgileri'),
      tr('Okul, üniversite, polis ya da askerî eğitim kurumu: kurum türünü seçin, adını ve imza sahiplerini bir kez girin. Tüm raporlar resmi yazı başlığıyla çıkar.'), [
    tr('Kurumunuza uygun resmi başlık, her ülke için'),
    tr('Öğretmen ve kurum amiri imza alanı'),
    tr('İstediğiniz zaman Ayarlar\'dan değiştirebilirsiniz'),
  ]),
  _Step(IllustrationKind.students, tr('2. Sınıflarınızı aktarın'),
      tr('Sınıflar sekmesinden e-Okul\'dan aldığınız Excel listesini seçin. Tüm şubeler tek dosyadan ayrılır.'), [
    tr('Gerekli sütunlar: Okul No, Adı, Soyadı, Sınıf'),
    tr('Tek tek öğrenci de ekleyebilirsiniz'),
    tr('Örnek sınıf ve sınavla hemen deneyebilirsiniz'),
  ]),
  _Step(IllustrationKind.scan, tr('3. Sınav, form, okut'),
      tr('Yeni sınav oluşturun, cevap anahtarını girin, Form yazdır ile isimli formları basın ve Okut\'a dokunun.'), [
    tr('Kâğıtları art arda kameraya gösterin, okuma kendiliğinden olur'),
    tr('Sonuçlar, madde analizi ve karneler anında hazır'),
    tr('Her PDF önce önizlenir, sonra yazdırılır veya paylaşılır'),
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
                  child: Text(tr('Atla'), style: TextStyle(color: Colors.white70)),
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
                          label: Text(tr('Kurum bilgilerini şimdi gir')),
                        ),
                      ),
                    ),
                  GlowButton(
                    label: last ? tr('Başla') : tr('Devam'),
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
          if (first) ...[
            Row(children: [
              AppLogo(size: 40),
              SizedBox(width: 10),
              Text(tr('Netice'), style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800)),
            ]),
            const SizedBox(height: 8),
          ],
          Center(child: Illustration(kind: step.icon, size: 190, onDark: true)),
          const SizedBox(height: 20),
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
