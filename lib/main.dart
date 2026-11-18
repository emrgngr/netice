import 'package:material_ui/material_ui.dart';

import 'core/cloud.dart';
import 'core/store.dart';
import 'ui/home_screen.dart';
import 'ui/splash_screen.dart';
import 'ui/theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final store = AppStore();
  runApp(NeticeApp(store: store));
  store.load().then((_) => CloudService.instance.attach(store));
}

class NeticeApp extends StatelessWidget {
  final AppStore store;

  /// Açılış animasyonu gösterilsin mi (testlerde kapatılır).
  final bool splash;
  const NeticeApp({super.key, required this.store, this.splash = true});

  @override
  Widget build(BuildContext context) {
    return StoreScope(
      store: store,
      child: MaterialApp(
        title: 'Netice',
        debugShowCheckedModeBanner: false,
        theme: NTheme.light(),
        darkTheme: NTheme.dark(),
        themeMode: ThemeMode.system,
        locale: const Locale('tr', 'TR'),
        supportedLocales: const [Locale('tr', 'TR'), Locale('en')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: splash ? const SplashScreen(next: HomeScreen()) : const HomeScreen(),
      ),
    );
  }
}

/// Uygulama verisine her ekrandan erişim.
class StoreScope extends InheritedNotifier<AppStore> {
  const StoreScope({super.key, required AppStore store, required super.child})
      : super(notifier: store);

  static AppStore of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<StoreScope>()!.notifier!;
}
