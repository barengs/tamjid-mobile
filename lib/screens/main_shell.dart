import 'package:flutter/material.dart';
import '../core/api_service.dart';
import 'dashboard_screen.dart';
import 'koperasi_pos_screen.dart';
import 'dapur_kiosk_screen.dart';
import 'teller_pos_screen.dart';
import 'settings_screen.dart';

class MainShell extends StatefulWidget {
  final int initialIndex;

  const MainShell({super.key, this.initialIndex = 0});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
  }

  void switchTab(int index) {
    setState(() {
      _currentIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    final user = ApiService().currentUser;
    final isDapur = user?.isDapur ?? false;
    final isTeller = user?.isTeller ?? false;

    // Center screen sesuai role
    Widget centerScreen;
    if (isTeller) {
      centerScreen = const TellerPosScreen();
    } else if (isDapur) {
      centerScreen = const DapurKioskScreen();
    } else {
      centerScreen = const KoperasiPosScreen();
    }

    final screens = [
      DashboardScreen(onNavigateTab: switchTab),
      centerScreen,
      const SettingsScreen(),
    ];

    final brandColor = isTeller
        ? const Color(0xFF1E40AF)
        : (isDapur ? const Color(0xFFD97706) : const Color(0xFF0D5C3A));

    // Build bottom navigation items dynamically
    final bottomNavItems = [
      const BottomNavigationBarItem(
        icon: Icon(Icons.dashboard_outlined),
        activeIcon: Icon(Icons.dashboard_rounded),
        label: 'Dashboard',
      ),
      if (isTeller)
        const BottomNavigationBarItem(
          icon: Icon(Icons.payments_outlined),
          activeIcon: Icon(Icons.payments_rounded),
          label: 'Tarik Tunai',
        )
      else if (isDapur)
        const BottomNavigationBarItem(
          icon: Icon(Icons.restaurant_outlined),
          activeIcon: Icon(Icons.restaurant_rounded),
          label: 'Tap Makan',
        )
      else
        const BottomNavigationBarItem(
          icon: Icon(Icons.point_of_sale_outlined),
          activeIcon: Icon(Icons.point_of_sale_rounded),
          label: 'Kasir POS',
        ),
      const BottomNavigationBarItem(
        icon: Icon(Icons.settings_outlined),
        activeIcon: Icon(Icons.settings_rounded),
        label: 'Pengaturan',
      ),
    ];

    // Ensure _currentIndex is within bounds if tabs change
    if (_currentIndex >= screens.length) {
      _currentIndex = 0;
    }

    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: screens,
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border(
            top: BorderSide(color: Colors.grey.shade200, width: 1),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 10,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: BottomNavigationBar(
          currentIndex: _currentIndex,
          onTap: (index) => setState(() => _currentIndex = index),
          backgroundColor: Colors.white,
          selectedItemColor: brandColor,
          unselectedItemColor: const Color(0xFF94A3B8), // slate 400
          selectedLabelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
          unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w500, fontSize: 11),
          type: BottomNavigationBarType.fixed,
          elevation: 0,
          items: bottomNavItems,
        ),
      ),
    );
  }
}
