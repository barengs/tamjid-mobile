import 'package:flutter/material.dart';
import 'core/api_service.dart';
import 'core/app_theme.dart';
import 'screens/login_screen.dart';
import 'screens/main_shell.dart';
import 'screens/history_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await ApiService().init();
  runApp(const KomprasiTamjidApp());
}

class KomprasiTamjidApp extends StatelessWidget {
  const KomprasiTamjidApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TamjidMart',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.light,
      initialRoute: '/',
      routes: {
        '/': (context) => const _HomeLauncher(),
        '/login': (context) => const LoginScreen(),
        '/dashboard': (context) => const MainShell(initialIndex: 0),
        '/pos': (context) => const MainShell(initialIndex: 1),
        '/teller': (context) => const MainShell(initialIndex: 1),
        '/settings': (context) => const MainShell(initialIndex: 2),
        '/history': (context) => const HistoryScreen(),
      },
    );
  }
}

class _HomeLauncher extends StatefulWidget {
  const _HomeLauncher();

  @override
  State<_HomeLauncher> createState() => _HomeLauncherState();
}

class _HomeLauncherState extends State<_HomeLauncher> {
  bool _checking = true;

  @override
  void initState() {
    super.initState();
    _checkAuth();
  }

  Future<void> _checkAuth() async {
    if (mounted) {
      setState(() {
        _checking = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_checking) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator(color: Color(0xFF0D5C3A))),
      );
    }

    // Modal argument for initial index if passed from login
    final args = ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
    final initialIndex = args?['initialIndex'] as int? ?? 0;

    // Untuk kebutuhan review & fleksibilitas pengembangan (hardcode / offline-ready):
    // Jika belum login, tampilkan layar Login resmi sesuai Mockup 1
    if (!ApiService().isLoggedIn) {
      return const LoginScreen();
    }

    return MainShell(initialIndex: initialIndex);
  }
}
