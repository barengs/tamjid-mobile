import 'package:flutter/material.dart';
import '../core/api_service.dart';
import 'dashboard_koperasi_screen.dart';
import 'dashboard_dpu_screen.dart';
import 'dashboard_teller_screen.dart';

/// Router Dashboard: menampilkan dashboard spesifik sesuai role merchant / bank
/// - staff_teller   -> Dashboard Teller (layanan tarik tunai, cek saldo bank)
/// - petugas_dpu     -> Dashboard DPU (realisasi porsi, menu, log distribusi)
/// - kasir_koperasi  -> Dashboard Koperasi (omzet POS, kas laci, struk)
class DashboardScreen extends StatelessWidget {
  final Function(int) onNavigateTab;

  const DashboardScreen({super.key, required this.onNavigateTab});

  @override
  Widget build(BuildContext context) {
    final user = ApiService().currentUser;

    if (user != null && user.isTeller) {
      return DashboardTellerScreen(onGoToWithdraw: () => onNavigateTab(1));
    }
    if (user != null && user.isDapur) {
      return DashboardDpuScreen(onGoToTap: () => onNavigateTab(1));
    }
    return DashboardKoperasiScreen(onGoToPos: () => onNavigateTab(1));
  }
}
