import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../core/api_service.dart';
import '../core/app_theme.dart';
import '../core/num_parser.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  bool _isLoading = true;
  List<dynamic> _transactions = [];
  double _todayTotal = 0;
  int _todayCount = 0;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    setState(() => _isLoading = true);
    try {
      final res = await ApiService().getTransactions();
      if (mounted) {
        setState(() {
          _transactions = res['data']['data'] as List<dynamic>? ?? [];
          _todayTotal = toD(res['summary']?['today_total_amount']);
          _todayCount = res['summary']?['today_count'] ?? 0;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _formatCurrency(double val) {
    return NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0).format(val);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Riwayat Transaksi Kasir'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loadHistory),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppTheme.emerald500))
          : RefreshIndicator(
              onRefresh: _loadHistory,
              color: AppTheme.emerald500,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // Summary Card
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [AppTheme.slate800, AppTheme.slate900],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(color: AppTheme.slate700),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('TOTAL TRANSAKSI HARI INI', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.slate400, letterSpacing: 0.8)),
                            const SizedBox(height: 6),
                            Text(
                              _formatCurrency(_todayTotal),
                              style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: AppTheme.emerald400),
                            ),
                          ],
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          decoration: BoxDecoration(
                            color: AppTheme.slate700.withValues(alpha: 0.5),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Text(
                            '$_todayCount Transaksi',
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),
                  const Text('Daftar Transaksi Terbaru', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white)),
                  const SizedBox(height: 10),

                  if (_transactions.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(40),
                      alignment: Alignment.center,
                      child: const Text('Belum ada transaksi hari ini.', style: TextStyle(color: AppTheme.slate400)),
                    )
                  else
                    ..._transactions.map((trx) {
                      final amount = toD(trx['amount']);
                      final isDapur = trx['outlet_name']?.toString().contains('Dapur') ?? false;

                      return Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: AppTheme.slate800,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: AppTheme.slate700),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: isDapur ? AppTheme.indigo500.withValues(alpha: 0.2) : AppTheme.emerald500.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Icon(
                                isDapur ? Icons.restaurant : Icons.shopping_bag_outlined,
                                color: isDapur ? AppTheme.indigo400 : AppTheme.emerald400,
                                size: 22,
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    trx['account']?['customer_name'] ?? trx['account_number'] ?? 'Santri',
                                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '${trx['outlet_name']} • ${trx['created_at']?.toString().substring(11, 16) ?? ""}',
                                    style: const TextStyle(fontSize: 12, color: AppTheme.slate400),
                                  ),
                                ],
                              ),
                            ),
                            Text(
                              _formatCurrency(amount),
                              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: Colors.white),
                            ),
                          ],
                        ),
                      );
                    }),
                ],
              ),
            ),
    );
  }
}
