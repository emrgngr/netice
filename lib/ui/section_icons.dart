import 'package:material_ui/material_ui.dart';

import '../l10n/l10n.dart';

/// Uygulamanın bölümleri. Her bölümün kendine ait simgesi ve renk geçişi
/// vardır; menülerde, kısayollarda ve kartlarda aynı "bölüm logosu" görünür.
/// Aynı set tanıtım videoları, kılavuz ve web sitesi için de
/// `tool/bolum_simgeleri_test.dart` ile PNG olarak dışa aktarılır.
enum Section {
  dashboard,
  exams,
  newExam,
  scan,
  review,
  classes,
  stats,
  compare,
  library,
  booklet,
  term,
  school,
  profile,
  settings,
  help,
  pro,
  why,
}

class SectionStyle {
  final IconData icon;
  final Color light;
  final Color deep;
  const SectionStyle(this.icon, this.light, this.deep);

  LinearGradient get gradient =>
      LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [light, deep]);
}

extension SectionInfo on Section {
  SectionStyle get style => switch (this) {
    Section.dashboard => const SectionStyle(Icons.space_dashboard_rounded, Color(0xFF8391E0), Color(0xFF4E5C99)),
    Section.exams => const SectionStyle(Icons.description_rounded, Color(0xFF60A5FA), Color(0xFF1D4ED8)),
    Section.newExam => const SectionStyle(Icons.add_rounded, Color(0xFF4ADE80), Color(0xFF15803D)),
    Section.scan => const SectionStyle(Icons.document_scanner_rounded, Color(0xFF34D399), Color(0xFF047857)),
    Section.review => const SectionStyle(Icons.fact_check_rounded, Color(0xFFFBBF24), Color(0xFFD97706)),
    Section.classes => const SectionStyle(Icons.groups_rounded, Color(0xFFA78BFA), Color(0xFF6D28D9)),
    Section.stats => const SectionStyle(Icons.query_stats_rounded, Color(0xFF22D3EE), Color(0xFF0E7490)),
    Section.compare => const SectionStyle(Icons.compare_arrows_rounded, Color(0xFF2DD4BF), Color(0xFF0F766E)),
    Section.library => const SectionStyle(Icons.local_library_rounded, Color(0xFFFB923C), Color(0xFFC2410C)),
    Section.booklet => const SectionStyle(Icons.menu_book_rounded, Color(0xFFFB7185), Color(0xFFBE123C)),
    Section.term => const SectionStyle(Icons.workspace_premium_rounded, Color(0xFF3B4C8C), Color(0xFF0F1B3D)),
    Section.school => const SectionStyle(Icons.account_balance_rounded, Color(0xFFF59E0B), Color(0xFFB45309)),
    Section.profile => const SectionStyle(Icons.person_rounded, Color(0xFFF472B6), Color(0xFFBE185D)),
    Section.settings => const SectionStyle(Icons.settings_rounded, Color(0xFF94A3B8), Color(0xFF475569)),
    Section.help => const SectionStyle(Icons.help_rounded, Color(0xFF38BDF8), Color(0xFF0369A1)),
    Section.pro => const SectionStyle(Icons.diamond_rounded, Color(0xFFF7D774), Color(0xFFD99A2B)),
    Section.why => const SectionStyle(Icons.emoji_events_rounded, Color(0xFF10B981), Color(0xFF0F1B3D)),
  };

  /// Bölümün kullanıcıya görünen adı.
  String get label => switch (this) {
    Section.dashboard => tr('Pano'),
    Section.exams => tr('Sınavlar'),
    Section.newExam => tr('Yeni sınav'),
    Section.scan => tr('Kâğıt okut'),
    Section.review => tr('Kontrol bekleyen'),
    Section.classes => tr('Sınıflar ve öğrenciler'),
    Section.stats => tr('Genel istatistik'),
    Section.compare => tr('Sınıf sınıf analiz'),
    Section.library => tr('Kütüphane'),
    Section.booklet => tr('Kitapçık hazırla'),
    Section.term => tr('Dönem raporu'),
    Section.school => tr('Kurum bilgileri'),
    Section.profile => tr('Profil'),
    Section.settings => tr('Ayarlar'),
    Section.help => tr('Yardım'),
    Section.pro => tr('Netice Pro'),
    Section.why => tr('Neden Netice?'),
  };
}

/// Bölüm logosu: renk geçişli yuvarlatılmış kare, üstte ince parlama ve
/// beyaz simge. Her temada aynı görünür (zemin her zaman renkli, simge beyaz).
/// Bölüm simgesiyle aynı tarzda, serbest simge ve renkli logo.
class GlossyIcon extends StatelessWidget {
  final IconData icon;
  final Color light;
  final Color deep;
  final double size;
  const GlossyIcon(this.icon, this.light, this.deep, {super.key, this.size = 40});

  @override
  Widget build(BuildContext context) => SectionIcon._custom(SectionStyle(icon, light, deep), size: size);
}

class SectionIcon extends StatelessWidget {
  final Section section;
  final double size;

  /// Seçili olmayan menü satırlarında biraz soluk görünür.
  final bool dim;
  final SectionStyle? _style;
  const SectionIcon(this.section, {super.key, this.size = 40, this.dim = false}) : _style = null;
  const SectionIcon._custom(SectionStyle style, {required this.size})
      : section = Section.why,
        dim = false,
        _style = style;

  @override
  Widget build(BuildContext context) {
    final s = _style ?? section.style;
    final r = BorderRadius.circular(size * 0.3);
    final fg = _style == null && section == Section.pro ? const Color(0xFF3A2800) : Colors.white;
    return Opacity(
      opacity: dim ? 0.82 : 1,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          gradient: s.gradient,
          borderRadius: r,
          boxShadow: size >= 36
              ? [
                  BoxShadow(
                    color: s.deep.withValues(alpha: 0.35),
                    blurRadius: size * 0.3,
                    offset: Offset(0, size * 0.1),
                  ),
                ]
              : null,
        ),
        child: Stack(
          children: [
            // Üst yarıda yumuşak parlama: düz renkten daha "değerli" görünür.
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: r,
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.center,
                    colors: [Colors.white.withValues(alpha: 0.28), Colors.white.withValues(alpha: 0)],
                  ),
                ),
              ),
            ),
            Center(
              child: Icon(s.icon, color: fg, size: size * 0.55),
            ),
          ],
        ),
      ),
    );
  }
}
