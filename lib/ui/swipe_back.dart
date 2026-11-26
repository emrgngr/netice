import 'package:cupertino_ui/cupertino_ui.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/gestures.dart';
import 'package:material_ui/material_ui.dart';

/// Telefonda sayfanın herhangi bir yerinden soldan sağa kaydırınca bir önceki
/// sayfaya dönülür. Sayfa parmağı izleyerek kayar; genişliğin yaklaşık %40ından fazla çekilirse ya
/// da hızlıca kaydırılırsa önceki sayfa açılır, yoksa sayfa yerine döner.
///
/// Görünüm iOS tarzı kayan geçiştir (parmağı izlemeye en uygun olanı). Sayfa
/// içinde yatay kayan bir öğe (sekme, kaydırma çubuğu, yatay liste) varsa
/// onun hareketi önceliklidir. İlk sayfada, tam ekran pencerelerde ve
/// "kaydedilmemiş değişiklik" uyarısı olan sayfalarda kaydırma çalışmaz.
class SwipeBackPageTransitionsBuilder extends PageTransitionsBuilder {
  const SwipeBackPageTransitionsBuilder();

  static const _inner = CupertinoPageTransitionsBuilder();

  @override
  Duration get transitionDuration => _inner.transitionDuration;

  @override
  DelegatedTransitionBuilder? get delegatedTransition => _inner.delegatedTransition;

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return _inner.buildTransitions<T>(
      route,
      context,
      animation,
      secondaryAnimation,
      SwipeBackDetector(route: route, child: child),
    );
  }
}

/// Sayfanın tamamında soldan sağa kaydırmayı yakalayıp sayfayı geri alır.
class SwipeBackDetector extends StatefulWidget {
  final PageRoute<dynamic> route;
  final Widget child;
  const SwipeBackDetector({super.key, required this.route, required this.child});

  @override
  State<SwipeBackDetector> createState() => _SwipeBackDetectorState();
}

class _SwipeBackDetectorState extends State<SwipeBackDetector> {
  late final HorizontalDragGestureRecognizer _recognizer;
  bool _dragging = false;
  double _value = 1;

  @override
  void initState() {
    super.initState();
    _recognizer = HorizontalDragGestureRecognizer(debugOwner: this)
      ..onStart = _start
      ..onUpdate = _update
      ..onEnd = _end
      ..onCancel = _cancel;
  }

  @override
  void dispose() {
    if (_dragging) {
      _dragging = false;
      widget.route.handleCancelBackGesture();
    }
    _recognizer.dispose();
    super.dispose();
  }

  bool get _enabled {
    final r = widget.route;
    return r.isCurrent && !r.fullscreenDialog && r.popGestureEnabled && !r.popGestureInProgress;
  }

  void _down(PointerDownEvent e) {
    if (_enabled) _recognizer.addPointer(e);
  }

  /// Sağdan sola yazılan dillerde (Arapça) hareket yönü tersine döner.
  double get _dir => Directionality.of(context) == TextDirection.rtl ? -1 : 1;

  double get _width => context.size?.width ?? 1;

  void _start(DragStartDetails d) {
    if (!_enabled) return;
    _dragging = true;
    _value = 1;
    widget.route.handleStartBackGesture(progress: 1);
  }

  void _update(DragUpdateDetails d) {
    if (!_dragging) return;
    _value = (_value - _dir * d.primaryDelta! / _width).clamp(0.0, 1.0);
    widget.route.handleUpdateBackGestureProgress(progress: _value);
  }

  void _end(DragEndDetails d) {
    if (!_dragging) return;
    _dragging = false;
    final speed = _dir * d.velocity.pixelsPerSecond.dx / _width;
    final bool back;
    if (speed.abs() >= 1) {
      back = speed > 0;
    } else {
      back = _value < 0.6;
    }
    if (back) {
      widget.route.handleCommitBackGesture();
    } else {
      widget.route.handleCancelBackGesture();
    }
  }

  void _cancel() {
    if (!_dragging) return;
    _dragging = false;
    widget.route.handleCancelBackGesture();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: _down,
      behavior: HitTestBehavior.translucent,
      child: widget.child,
    );
  }
}
