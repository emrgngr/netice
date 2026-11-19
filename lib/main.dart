import 'package:material_ui/material_ui.dart';

import 'core/cloud.dart';
import 'core/pro.dart';
import 'core/store.dart';
import 'l10n/l10n.dart';
import 'ui/home_screen.dart';
import 'ui/splash_screen.dart';
import 'ui/theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final store = AppStore();
  L10n.use(null);
  runApp(NeticeApp(store: store));
  store.load().then((_) {
    if (store.language != null) store.setLanguage(store.language);
    CloudService.instance.attach(store);
    ProService.instance.attach(store);
  });
}

class NeticeApp extends StatelessWidget {
  /// Açılış animasyonu yalnızca ilk açılışta (dil değişince yeniden oynamaz).
  static bool _splashShown = false;

  final AppStore store;

  /// Açılış animasyonu gösterilsin mi (testlerde kapatılır).
  final bool splash;
  const NeticeApp({super.key, required this.store, this.splash = true});

  Widget _home() {
    if (!splash || _splashShown) return const HomeScreen();
    _splashShown = true;
    return const SplashScreen(next: HomeScreen());
  }

  @override
  Widget build(BuildContext context) {
    return StoreScope(
      store: store,
      child: ListenableBuilder(
        listenable: store,
        builder: (context, _) => MaterialApp(
          key: ValueKey(L10n.code),
          title: 'Netice',
          debugShowCheckedModeBanner: false,
          theme: NTheme.light(),
          darkTheme: NTheme.dark(),
          themeMode: ThemeMode.system,
          locale: L10n.locale,
          supportedLocales: [for (final l in AppLanguage.all) Locale(l.code)],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          home: _home(),
        ),
      ),
    );
  }
}

/// Uygulama verisine her ekrandan erişim.
class StoreScope extends InheritedNotifier<AppStore> {
  const StoreScope({super.key, required AppStore store, required super.child}) : super(notifier: store);

  static AppStore of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<StoreScope>()!.notifier!;
}
