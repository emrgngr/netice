import 'package:material_ui/material_ui.dart';

import 'bank/bank_store.dart';
import 'core/ad_admin.dart';
import 'core/ads.dart';
import 'core/cloud.dart';
import 'core/pro.dart';
import 'core/store.dart';
import 'core/updates.dart';
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
    BankStore.instance.load();
    if (store.language != null) store.setLanguage(store.language);
    CloudService.instance.attach(store);
    ProService.instance.attach(store);
    AdAdmin.instance.load();
    AdService.instance.refresh();
    UpdateService.instance.check();
  });
}

class NeticeApp extends StatelessWidget {
  /// Açılış animasyonu yalnızca ilk açılışta oynar. Veri her değiştiğinde
  /// uygulama yeniden çizildiği için aynı açılış ekranı nesnesi saklanır;
  /// aksi hâlde ilk değişiklikte animasyon yarıda kesilip ana sayfa açılıyordu.
  static Widget? _splashScreen;

  final AppStore store;

  /// Açılış animasyonu gösterilsin mi (testlerde kapatılır).
  final bool splash;
  const NeticeApp({super.key, required this.store, this.splash = true});

  Widget _home() {
    if (!splash || SplashScreen.played) return const HomeScreen();
    return _splashScreen ??= const SplashScreen(next: HomeScreen());
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
          themeMode: switch (store.themeMode) {
            'light' => ThemeMode.light,
            'dark' => ThemeMode.dark,
            _ => ThemeMode.system,
          },
          themeAnimationDuration: const Duration(milliseconds: 350),
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
