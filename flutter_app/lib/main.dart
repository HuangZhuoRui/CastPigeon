import 'package:flutter/material.dart';

import 'core/bridge/api_factory.dart';
import 'core/bridge/cast_pigeon_api.dart';
import 'core/theme/theme_controller.dart';
import 'ui/cast_pigeon_home.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final themeController = await ThemeController.create();
  runApp(
    CastPigeonApp(api: createCastPigeonApi(), themeController: themeController),
  );
}

class CastPigeonApp extends StatelessWidget {
  const CastPigeonApp({
    super.key,
    required this.api,
    required this.themeController,
  });

  final CastPigeonApi api;
  final ThemeController themeController;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: themeController,
      builder: (context, _) {
        return MaterialApp(
          title: '投鸽',
          debugShowCheckedModeBanner: false,
          themeMode: themeController.themeMode,
          theme: _buildTheme(Brightness.light),
          darkTheme: _buildTheme(Brightness.dark),
          home: CastPigeonHome(api: api, themeController: themeController),
        );
      },
    );
  }

  ThemeData _buildTheme(Brightness brightness) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: const Color(0xff156f5b),
      brightness: brightness,
    );
    final dark = brightness == Brightness.dark;
    return ThemeData(
      colorScheme: colorScheme,
      brightness: brightness,
      useMaterial3: true,
      scaffoldBackgroundColor: dark
          ? const Color(0xff101513)
          : const Color(0xfff7f8f8),
      dividerColor: dark ? const Color(0x1fffffff) : const Color(0x1426332f),
      cardTheme: CardThemeData(
        color: dark ? const Color(0xff18201d) : const Color(0xffeef3f1),
        surfaceTintColor: Colors.transparent,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: dark ? const Color(0xff18201d) : Colors.white,
        surfaceTintColor: Colors.transparent,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: dark
            ? const Color(0xff171f1c)
            : Colors.white.withValues(alpha: 0.92),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: dark ? const Color(0xff171f1c) : Colors.white,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }
}
