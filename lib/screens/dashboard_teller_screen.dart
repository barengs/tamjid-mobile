import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../core/api_service.dart';
import '../widgets/app_header.dart';

class DashboardTellerScreen extends StatefulWidget {
  final VoidCallback onGoToWithdraw;

  const DashboardTellerScreen({super.key, required this.onGoToWithdraw});

  @override
  State<DashboardTellerScreen> createState() => _DashboardTellerScreenState();
}

class _DashboardTellerScreenState extends State<DashboardTellerScreen> {
  static const Color primaryBlue = Color(0xFF1E40AF);

  @override
  Widget build(BuildContext context) {
    final user = ApiService().currentUser;
    final staffName = user?.name ?? 'Staff Teller';
    String todayStr;
    try {
      todayStr = DateFormat('EEEE, dd MMMM yyyy', 'id_ID').format(DateTime.now());
    } catch (_) {
      final now = DateTime.now();
      todayStr = '${now.day}/${now.month}/${now.year}';
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: SafeArea(
        child: Column(
          children: [
            const AppHeader(title: 'Dashboard Teller'),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Banner Sambutan & Shift Teller
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF1E3A8A), Color(0xFF2563EB)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: primaryBlue.withValues(alpha: 0.25),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.shield_outlined, size: 14, color: Colors.white),
                                    SizedBox(width: 4),
                                    Text(
                                      'Bank Santri Mobile',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Text(
                                todayStr,
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.9),
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          Text(
                            'Selamat Bertugas, $staffName!',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Terminal mobile siap melayani penarikan tunai tabungan santri.',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.9),
                              fontSize: 12.5,
                            ),
                          ),
                          const SizedBox(height: 16),
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.white,
                              foregroundColor: primaryBlue,
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            ),
                            icon: const Icon(Icons.payments_rounded, size: 18),
                            label: const Text(
                              'Buka Layanan Tarik Tunai',
                              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
                            ),
                            onPressed: widget.onGoToWithdraw,
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 20),

                    // Fitur Utama
                    const Text(
                      'Layanan Cepat',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                    const SizedBox(height: 10),

                    Row(
                      children: [
                        Expanded(
                          child: _buildServiceCard(
                            icon: Icons.payments_rounded,
                            title: 'Tarik Tunai',
                            subtitle: 'Tap kartu & serahkan uang',
                            iconBg: const Color(0xFFDBEAFE),
                            iconColor: primaryBlue,
                            onTap: widget.onGoToWithdraw,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _buildServiceCard(
                            icon: Icons.qr_code_scanner_rounded,
                            title: 'Cek Saldo',
                            subtitle: 'Scan kartu santri',
                            iconBg: const Color(0xFFDCFCE7),
                            iconColor: const Color(0xFF16A34A),
                            onTap: widget.onGoToWithdraw,
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 20),

                    // Pedoman Operasional Teller
                    const Text(
                      'Ketentuan Operasional',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                    const SizedBox(height: 10),

                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: Column(
                        children: [
                          _buildGuidelineItem(
                            icon: Icons.verified_user_outlined,
                            title: 'Verifikasi Wajah Santri',
                            desc: 'Cocokkan foto santri di layar dengan santri yang hadir di hadapan teller.',
                          ),
                          const Divider(height: 18),
                          _buildGuidelineItem(
                            icon: Icons.all_inclusive,
                            title: 'Tanpa Batasan Limit Harian',
                            desc: 'Tarik tunai bebas batas harian. Pembatasan uang jajan hanya berlaku saat belanja di koperasi.',
                          ),
                          const Divider(height: 18),
                          _buildGuidelineItem(
                            icon: Icons.account_balance_wallet_outlined,
                            title: 'Saldo Mengendap Terjaga',
                            desc: 'Sistem otomatis memblokir penarikan jika sisa saldo melanggar saldo minimum rekening.',
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildServiceCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color iconBg,
    required Color iconColor,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: iconBg,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: iconColor, size: 22),
            ),
            const SizedBox(height: 10),
            Text(
              title,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 13.5,
                color: Color(0xFF0F172A),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: const TextStyle(
                fontSize: 11,
                color: Color(0xFF64748B),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGuidelineItem({
    required IconData icon,
    required String title,
    required String desc,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: const Color(0xFFF1F5F9),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 18, color: primaryBlue),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 12.5,
                  color: Color(0xFF0F172A),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                desc,
                style: const TextStyle(fontSize: 11.5, color: Color(0xFF64748B), height: 1.3),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
