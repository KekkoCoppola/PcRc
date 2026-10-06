import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'screens/home_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // Set system navigation and status bar style
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Color(0xFF08090C),
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );

  runApp(const PcRcApp());
}

class PcRcApp extends StatelessWidget {
  const PcRcApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PcRc',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.dark,
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFF08090C),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF00E5FF),
          secondary: Color(0xFF10B981),
          surface: Color(0xFF0E1015),
          error: Color(0xFFEF4444),
          onPrimary: Colors.black,
          onSecondary: Colors.white,
          onSurface: Color(0xFFF1F5F9),
        ),
        cardTheme: CardThemeData(
          color: const Color(0xFF0E1015),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: Color(0xFF1F232E), width: 1),
          ),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          elevation: 0,
          scrolledUnderElevation: 0,
        ),
        snackBarTheme: SnackBarThemeData(
          backgroundColor: const Color(0xFF12141C),
          contentTextStyle: const TextStyle(
            color: Color(0xFFF1F5F9),
            fontWeight: FontWeight.w500,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: Color(0xFF262B38), width: 1),
          ),
          behavior: SnackBarBehavior.floating,
        ),
      ),
      home: const HomeScreen(),
    );
  }
}
