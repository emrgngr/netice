import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../core/store.dart';
import '../l10n/l10n.dart';

/// Okuma melodileri: anahtar, kullanıcıya görünen ad ve ses dosyası.
const scanMelodies = <String>['kristal', 'marimba', 'yumusak'];

String scanMelodyName(String key) => switch (key) {
  'marimba' => tr('Marimba'),
  'yumusak' => tr('Yumuşak'),
  _ => tr('Kristal'),
};

/// Kâğıt okununca verilen onay: seçilen kısa melodi ve hafif titreşim.
/// Ayarlar > Ses bölümünden melodi seçilir; ses ve titreşim ayrı ayrı
/// açılıp kapatılabilir.
class ScanFeedback {
  static AudioPlayer? _player;
  static String? _loaded;

  static String _asset(String key) => 'sounds/okuma_${scanMelodies.contains(key) ? key : 'kristal'}.mp3';

  /// Okutma ekranı açılırken çağrılır: ilk okumada gecikme olmasın.
  static Future<void> warmUp([String melody = 'kristal']) async {
    if (_loaded == melody) return;
    try {
      final p = _player ??= AudioPlayer();
      await p.setReleaseMode(ReleaseMode.stop);
      await p.setPlayerMode(PlayerMode.lowLatency);
      await p.setSource(AssetSource(_asset(melody)));
      await p.setVolume(0.7);
      _loaded = melody;
    } catch (_) {}
  }

  /// Melodiyi çalar (ayarlarda önizleme için de kullanılır).
  static Future<void> play(String melody) async {
    try {
      if (_loaded != melody) await warmUp(melody);
      final p = _player;
      if (p == null) return;
      await p.stop();
      await p.resume();
    } catch (_) {
      SystemSound.play(SystemSoundType.click);
    }
  }

  /// Başarılı okuma: hafif titreşim + melodi (ayarlara göre).
  static Future<void> success(AppStore store) async {
    if (store.scanVibrate) HapticFeedback.lightImpact();
    if (store.scanSound) await play(store.scanMelody);
  }

  /// Aynı kâğıt yeniden okutuldu: yalnız çok hafif bir titreşim.
  static void duplicate(AppStore store) {
    if (store.scanVibrate) HapticFeedback.selectionClick();
  }

  /// Ayarlarda titreşim açılınca örnek titreşim.
  static void vibrateSample() => HapticFeedback.lightImpact();

  /// Kâğıt okunamadı: belirgin bir titreşim.
  static void failed(AppStore store) {
    if (store.scanVibrate) HapticFeedback.heavyImpact();
  }
}

/// Başarılı okumada ekranın kenarlarında yeşil bir parlama ve ortada
/// beliren onay işareti. [pulse] her arttığında bir kez oynar.
class SuccessFlash extends StatefulWidget {
  final ValueListenable<int> pulse;
  final Widget child;
  const SuccessFlash({super.key, required this.pulse, required this.child});

  @override
  State<SuccessFlash> createState() => _SuccessFlashState();
}

class _SuccessFlashState extends State<SuccessFlash> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 750));

  @override
  void initState() {
    super.initState();
    widget.pulse.addListener(_play);
  }

  void _play() => _c.forward(from: 0);

  @override
  void dispose() {
    widget.pulse.removeListener(_play);
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.passthrough,
      children: [
        widget.child,
        Positioned.fill(
          child: IgnorePointer(
            child: AnimatedBuilder(
              animation: _c,
              builder: (context, _) {
                if (!_c.isAnimating) return const SizedBox.shrink();
                final v = _c.value;
                // Hızlı yükselir, yavaşça söner.
                final a = v < 0.2 ? v / 0.2 : 1 - (v - 0.2) / 0.8;
                final scale = 0.6 + 0.4 * Curves.easeOutBack.transform((v / 0.4).clamp(0, 1));
                return Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.9 * a), width: 6),
                    gradient: RadialGradient(
                      colors: [
                        const Color(0xFF10B981).withValues(alpha: 0.0),
                        const Color(0xFF10B981).withValues(alpha: 0.22 * a),
                      ],
                      radius: 1.1,
                    ),
                  ),
                  alignment: Alignment.center,
                  child: Opacity(
                    opacity: a.clamp(0, 1),
                    child: Transform.scale(
                      scale: scale,
                      child: Container(
                        width: 92,
                        height: 92,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: const LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [Color(0xFF34D399), Color(0xFF059669)],
                          ),
                          boxShadow: [BoxShadow(color: const Color(0xFF10B981).withValues(alpha: 0.5), blurRadius: 30)],
                        ),
                        child: const Icon(Icons.check_rounded, color: Colors.white, size: 56),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}
