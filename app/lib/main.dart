import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'config/branding.dart';
import 'config/theme_controller.dart';
import 'services/storage.dart';
import 'ui/home_screen.dart';
import 'ui/login_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  await Branding.load();
  await ThemeController.load();
  final servers = await Storage.loadServers();
  runApp(MazeTvApp(startLoggedIn: servers.isNotEmpty));
}

class MazeTvApp extends StatelessWidget {
  final bool startLoggedIn;
  const MazeTvApp({super.key, required this.startLoggedIn});

  @override
  Widget build(BuildContext context) {
    final b = Branding.I;
    return ValueListenableBuilder<Color>(
      valueListenable: ThemeController.primaryColor,
      builder: (context, accent, _) => MaterialApp(
        title: b.appName,
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          brightness: Brightness.dark,
          colorScheme: ColorScheme.fromSeed(
            seedColor: accent,
            brightness: Brightness.dark,
            primary: accent,
          ),
          scaffoldBackgroundColor: const Color(0xFF0E0E10),
          // TV-safe defaults: big text, visible focus.
          textTheme: const TextTheme(bodyMedium: TextStyle(fontSize: 18)),
          listTileTheme: const ListTileThemeData(minVerticalPadding: 12),
          focusColor: accent.withOpacity(0.35),
        ),
        home: startLoggedIn ? const HomeScreen() : const LoginScreen(),
      ),
    );
  }
}
