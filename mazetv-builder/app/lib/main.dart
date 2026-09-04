import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'config/branding.dart';
import 'services/storage.dart';
import 'ui/home_screen.dart';
import 'ui/login_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  await Branding.load();
  final acct = await Storage.loadAccount();
  runApp(MazeTvApp(startLoggedIn: acct != null));
}

class MazeTvApp extends StatelessWidget {
  final bool startLoggedIn;
  const MazeTvApp({super.key, required this.startLoggedIn});

  @override
  Widget build(BuildContext context) {
    final b = Branding.I;
    return MaterialApp(
      title: b.appName,
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: b.primaryColor,
          brightness: Brightness.dark,
          primary: b.primaryColor,
        ),
        scaffoldBackgroundColor: const Color(0xFF0E0E10),
        // TV-safe defaults: big text, visible focus.
        textTheme: const TextTheme(bodyMedium: TextStyle(fontSize: 18)),
        listTileTheme: const ListTileThemeData(minVerticalPadding: 12),
        focusColor: b.primaryColor.withOpacity(0.35),
      ),
      home: startLoggedIn ? const HomeScreen() : const LoginScreen(),
    );
  }
}
