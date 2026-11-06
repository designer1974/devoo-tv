import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:media_kit/media_kit.dart';

import 'data.dart';
import 'hidden.dart';
import 'shell.dart';
import 'ui.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized(); // lettore video
  ErrorWidget.builder = (_) => const SizedBox.shrink(); // un errore in un riquadro non chiude l'app
  try {
    await Favorites.i.init().timeout(const Duration(seconds: 4));
    await Hidden.i.init().timeout(const Duration(seconds: 4));
  } catch (_) {}
  runApp(const DevooTvApp());
}

class DevooTvApp extends StatelessWidget {
  const DevooTvApp({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.fromSeed(
      seedColor: yellow,
      brightness: Brightness.dark,
      primary: yellow,
      onPrimary: navy,
      surface: navy2,
    );
    final theme = ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      scaffoldBackgroundColor: navy,
      snackBarTheme: const SnackBarThemeData(
        backgroundColor: yellow,
        contentTextStyle: TextStyle(color: navy, fontWeight: FontWeight.w700, fontSize: 15),
      ),
    );
    return MaterialApp(
      title: 'Devoo TV',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.dark,
      theme: theme,
      darkTheme: theme,
      locale: const Locale('it'),
      supportedLocales: const [Locale('it'), Locale('en'), Locale('fr'), Locale('ar')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: const AppShell(),
    );
  }
}
