import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../core/api_service.dart';
import '../models/student_account.dart';
import '../widgets/app_header.dart';
import '../widgets/student_avatar.dart';

/// Formatter pemisah ribuan (1.500.000) untuk input nominal.
class ThousandsSeparatorInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (newValue.text.isEmpty) {
      return newValue.copyWith(text: '');
    }
    String cleanText = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (cleanText.isEmpty) {
      return newValue.copyWith(text: '');
    }
    while (cleanText.length > 1 && cleanText.startsWith('0')) {
      cleanText = cleanText.substring(1);
    }
    final number = int.tryParse(cleanText) ?? 0;
    final formatted = NumberFormat('#,###', 'id_ID').format(number);
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}

/// Model transaksi yang ditunda (hold) di perangkat kasir.
class PendingTransaction {
  final StudentAccount account;
  final double amount;
  final String category;
  final String time;

  PendingTransaction({
    required this.account,
    required this.amount,
    required this.category,
    required this.time,
  });
}

class KoperasiPosScreen extends StatefulWidget {
  const KoperasiPosScreen({super.key});

  @override
  State<KoperasiPosScreen> createState() => _KoperasiPosScreenState();
}

class _KoperasiPosScreenState extends State<KoperasiPosScreen> {
  bool _isLoading = false;
  bool _printReceipt = true;
  String _category = 'Snack';
  StudentAccount? _detectedAccount;
  final List<PendingTransaction> _pendingTxns = [];

  final TextEditingController _rfidController = TextEditingController();
  final FocusNode _cardFocusNode = FocusNode();
  final TextEditingController _amountController = TextEditingController();
  final FocusNode _amountFocusNode = FocusNode();

  double get _amount {
    final clean = _amountController.text.replaceAll(RegExp(r'[^0-9]'), '');
    return double.tryParse(clean) ?? 0.0;
  }

  @override
  void initState() {
    super.initState();
    _amountFocusNode.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _rfidController.dispose();
    _cardFocusNode.dispose();
    _amountController.dispose();
    _amountFocusNode.dispose();
    super.dispose();
  }

  String _formatCurrency(double val) {
    return NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0).format(val);
  }

  void _resetAmount() {
    _amountController.clear();
    setState(() {});
  }

  void _addQuickAmount(int val) {
    setState(() {
      final current = _amount.toInt();
      final updated = current + val;
      final formatted = NumberFormat('#,###', 'id_ID').format(updated);
      _amountController.text = formatted;
      _amountController.selection = TextSelection.collapsed(offset: formatted.length);
    });
  }

  /// Tunda transaksi aktif ke antrian pending agar bisa melayani transaksi lain.
  void _holdTransaction() {
    final account = _detectedAccount;
    if (account == null || _amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Color(0xFFE11D48),
          content: Text('Tidak ada transaksi aktif untuk ditunda.'),
        ),
      );
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _pendingTxns.insert(
        0,
        PendingTransaction(
          account: account,
          amount: _amount,
          category: _category,
          time: DateFormat('HH:mm').format(DateTime.now()),
        ),
      );
      ApiService().pendingCount.value = _pendingTxns.length;
      _amountController.clear();
      _rfidController.clear();
      _detectedAccount = null;
      _category = 'Snack';
    });
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: const Color(0xFFD97706),
        content: Text(
          'Transaksi ${account.customerName} ditunda (${_pendingTxns.length} antrian).',
        ),
      ),
    );
  }

  /// Batalkan transaksi aktif tanpa memanggil pembayaran (debit).
  Future<void> _cancelActiveTransaction() async {
    final account = _detectedAccount;
    if (account == null && _amount <= 0) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        icon: const Icon(Icons.cancel_outlined, color: Color(0xFFE11D48), size: 48),
        title: const Text('Batalkan Transaksi?'),
        content: Text(
          account == null
              ? 'Nominal yang diisi akan dihapus.'
              : 'Transaksi ${account.customerName} senilai ${_formatCurrency(_amount)} akan dibatalkan tanpa pembayaran.',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 13, color: Color(0xFF64748B)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Kembali', style: TextStyle(color: Color(0xFF64748B))),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFE11D48)),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Ya, Batalkan', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    FocusScope.of(context).unfocus();
    setState(() {
      _detectedAccount = null;
      _rfidController.clear();
      _amountController.clear();
      _category = 'Snack';
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        backgroundColor: Color(0xFF64748B),
        content: Text('Transaksi dibatalkan.'),
      ),
    );
  }

  /// Lanjutkan transaksi yang ditunda kembali ke layar aktif.
  void _resumePending(int index) {
    if (index < 0 || index >= _pendingTxns.length) return;
    if (_detectedAccount != null || _amount > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Color(0xFFD97706),
          content: Text('Selesaikan atau tunda transaksi aktif terlebih dahulu.'),
        ),
      );
      return;
    }
    final txn = _pendingTxns.removeAt(index);
    ApiService().pendingCount.value = _pendingTxns.length;
    setState(() {
      _detectedAccount = txn.account;
      _rfidController.text = txn.account.accountNumber;
      _amountController.text = NumberFormat('#,###', 'id_ID').format(txn.amount.toInt());
      _category = txn.category;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: const Color(0xFF0D5C3A),
        content: Text('Transaksi ${txn.account.customerName} dilanjutkan.'),
      ),
    );
  }

  /// Hapus permanen satu item dari antrian pending (dengan konfirmasi).
  Future<void> _removePending(int index) async {
    if (index < 0 || index >= _pendingTxns.length) return;
    final txn = _pendingTxns[index];
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Hapus dari Antrian?'),
        content: Text(
          'Transaksi ${txn.account.customerName} senilai ${_formatCurrency(txn.amount)} akan dihapus dari antrian pending.',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 13, color: Color(0xFF64748B)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Kembali', style: TextStyle(color: Color(0xFF64748B))),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFE11D48)),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Hapus', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _pendingTxns.removeAt(index);
      ApiService().pendingCount.value = _pendingTxns.length;
    });
  }

  /// Tampilkan BottomSheet untuk melihat dan mengelola daftar transaksi ditunda.
  void _showPendingBottomSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) => Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.7,
          ),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              Container(
                width: 44,
                height: 4,
                decoration: BoxDecoration(color: const Color(0xFFE2E8F0), borderRadius: BorderRadius.circular(2)),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 12, 18, 8),
                child: Row(
                  children: [
                    const Icon(Icons.schedule, size: 18, color: Color(0xFFD97706)),
                    const SizedBox(width: 8),
                    const Text(
                      'Antrian Transaksi Ditunda',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1.5),
                      decoration: BoxDecoration(
                        color: const Color(0xFFD97706),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '${_pendingTxns.length}',
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                    ),
                    const Spacer(),
                    if (_pendingTxns.isNotEmpty)
                      TextButton(
                        onPressed: () {
                          Navigator.pop(ctx);
                          setState(() {
                            _pendingTxns.clear();
                            ApiService().pendingCount.value = 0;
                          });
                        },
                        child: const Text('Kosongkan', style: TextStyle(fontSize: 12, color: Color(0xFFE11D48), fontWeight: FontWeight.bold)),
                      ),
                  ],
                ),
              ),
              const Divider(height: 1),
              if (_pendingTxns.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 40),
                  child: Text('Tidak ada transaksi yang ditunda.', style: TextStyle(color: Color(0xFF94A3B8))),
                )
              else
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    padding: const EdgeInsets.all(16),
                    itemCount: _pendingTxns.length,
                    itemBuilder: (context, i) {
                      final txn = _pendingTxns[i];
                      return Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFFBEB),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: const Color(0xFFFDE68A)),
                        ),
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                          leading: CircleAvatar(
                            backgroundColor: const Color(0xFFF59E0B),
                            foregroundColor: Colors.white,
                            child: Text(
                              txn.account.customerName.isNotEmpty ? txn.account.customerName[0].toUpperCase() : 'S',
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ),
                          title: Text(
                            txn.account.customerName,
                            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5),
                          ),
                          subtitle: Text(
                            'NIS ${txn.account.accountNumber} • ${txn.category} • ${txn.time} WIB',
                            style: const TextStyle(fontSize: 11, color: Color(0xFF78350F)),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                _formatCurrency(txn.amount),
                                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: Color(0xFF92400E)),
                              ),
                              const SizedBox(width: 6),
                              IconButton(
                                icon: const Icon(Icons.close, size: 18, color: Color(0xFF94A3B8)),
                                onPressed: () {
                                  _removePending(i);
                                  setModalState(() {});
                                  if (_pendingTxns.isEmpty) Navigator.pop(ctx);
                                },
                              ),
                            ],
                          ),
                          onTap: () {
                            Navigator.pop(ctx);
                            _resumePending(i);
                          },
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _detectCard(String identifier) async {
    setState(() => _isLoading = true);
    try {
      final account = await ApiService().checkAccount(identifier, outletType: 'koperasi');
      if (!mounted) return;
      setState(() {
        _detectedAccount = account;
        _isLoading = false;
        _rfidController.text = account.accountNumber;
      });
      _cardFocusNode.unfocus();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _amountFocusNode.requestFocus();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFFE11D48),
          content: Text(e.toString().replaceAll('Exception: ', '')),
        ),
      );
    }
  }

  void _openScanner() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _ScannerModal(
        onScanned: (code) {
          Navigator.pop(ctx);
          _detectCard(code);
        },
      ),
    );
  }

  Future<void> _processPayment() async {
    if (_detectedAccount == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Color(0xFFE11D48),
          content: Text('Silakan tap / scan kartu santri terlebih dahulu.'),
        ),
      );
      return;
    }
    if (_amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Color(0xFFE11D48),
          content: Text('Nominal belanja belum diisi.'),
        ),
      );
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() => _isLoading = true);
    try {
      final res = await ApiService().debit(
        identifier: _detectedAccount!.accountNumber,
        amount: _amount,
        outletType: 'koperasi',
        description: 'Belanja $_category',
      );

      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _amountController.clear();
        _rfidController.clear();
        _detectedAccount = null;
      });

      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          icon: const Icon(Icons.check_circle_outline, color: Color(0xFF059669), size: 54),
          title: const Text('Pembayaran Berhasil!'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _formatCurrency((res['amount'] ?? 0).toDouble()),
                style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFF0D5C3A)),
              ),
              const SizedBox(height: 8),
              Text('Ref: ${res['reference_number']}', style: const TextStyle(fontSize: 12, color: Color(0xFF64748B))),
              const SizedBox(height: 4),
              Text('Sisa Saldo: ${res['balance_formatted'] ?? ''}', style: const TextStyle(fontSize: 13)),
              if (_printReceipt) ...[
                const SizedBox(height: 12),
                const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.print_outlined, size: 16, color: Color(0xFF059669)),
                    SizedBox(width: 6),
                    Text('Struk thermal tercetak otomatis', style: TextStyle(fontSize: 12, color: Color(0xFF059669))),
                  ],
                ),
              ],
            ],
          ),
          actions: [
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0D5C3A)),
              onPressed: () => Navigator.pop(ctx),
              child: const Text('SELESAI (OK)', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFFE11D48),
          content: Text(e.toString().replaceAll('Exception: ', '')),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final account = _detectedAccount;
    final double balanceAfter = (account?.balance ?? 0) - _amount;
    final bool isBalanceEnough = account == null ? true : balanceAfter >= account.minimumBalance;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: Column(
          children: [
            const AppHeader(title: 'Koperasi'),

            // Pill Banner Transaksi Ditunda (Compact, membuka BottomSheet)
            if (_pendingTxns.isNotEmpty)
              InkWell(
                onTap: _showPendingBottomSheet,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                  margin: const EdgeInsets.fromLTRB(14, 6, 14, 0),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFFBEB),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFFDE68A)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.schedule, size: 15, color: Color(0xFFD97706)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${_pendingTxns.length} Transaksi Ditunda • Ketuk untuk melanjutkan',
                          style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: Color(0xFF92400E)),
                        ),
                      ),
                      const Icon(Icons.chevron_right, size: 16, color: Color(0xFFD97706)),
                    ],
                  ),
                ),
              ),

            // Konten Tengah (Flexible, compact single-view)
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator(color: Color(0xFF059669)))
                  : SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // 1. Identifikasi Kartu Santri (Compact)
                          if (account != null)
                            _buildDetectedCard(account, isBalanceEnough)
                          else
                            _buildCardInput(),
                          const SizedBox(height: 10),

                          // 2. Total Belanja POS (Editable via keyboard bawaan)
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                'TOTAL BELANJA POS',
                                style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w900, color: Color(0xFF64748B), letterSpacing: 0.6),
                              ),
                              TextButton.icon(
                                style: TextButton.styleFrom(
                                  foregroundColor: const Color(0xFF64748B),
                                  padding: const EdgeInsets.symmetric(horizontal: 6),
                                  minimumSize: Size.zero,
                                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                ),
                                icon: const Icon(Icons.refresh, size: 13),
                                label: const Text('Reset', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                                onPressed: _resetAmount,
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: _amountFocusNode.hasFocus ? const Color(0xFF0D5C3A) : const Color(0xFFE2E8F0),
                                width: _amountFocusNode.hasFocus ? 1.5 : 1,
                              ),
                            ),
                            child: Row(
                              children: [
                                const Text(
                                  'Rp ',
                                  style: TextStyle(
                                    fontSize: 26,
                                    fontWeight: FontWeight.w900,
                                    color: Color(0xFF0D5C3A),
                                  ),
                                ),
                                Expanded(
                                  child: TextField(
                                    controller: _amountController,
                                    focusNode: _amountFocusNode,
                                    keyboardType: TextInputType.number,
                                    inputFormatters: [
                                      FilteringTextInputFormatter.digitsOnly,
                                      ThousandsSeparatorInputFormatter(),
                                    ],
                                    style: const TextStyle(
                                      fontSize: 28,
                                      fontWeight: FontWeight.w900,
                                      color: Color(0xFF0F172A),
                                      letterSpacing: -0.5,
                                    ),
                                    decoration: const InputDecoration(
                                      hintText: '0',
                                      hintStyle: TextStyle(
                                        fontSize: 28,
                                        fontWeight: FontWeight.w900,
                                        color: Color(0xFFCBD5E1),
                                      ),
                                      border: InputBorder.none,
                                      isDense: true,
                                      contentPadding: EdgeInsets.zero,
                                    ),
                                    onChanged: (_) => setState(() {}),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 10),

                          // 3. Kategori Transaksi (Compact)
                          const Text('Kategori Transaksi', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF334155))),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              _buildCategoryChip('Snack', Icons.cookie_outlined),
                              const SizedBox(width: 6),
                              _buildCategoryChip('Alat Tulis', Icons.edit_outlined),
                              const SizedBox(width: 6),
                              _buildCategoryChip('Kitab', Icons.menu_book_outlined),
                            ],
                          ),
                          const SizedBox(height: 10),

                          // 4. Tambah Cepat (+) (Compact)
                          const Text('Tambah Cepat (+)', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF334155))),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              _buildQuickChip('+5K', 5000),
                              const SizedBox(width: 6),
                              _buildQuickChip('+10K', 10000),
                              const SizedBox(width: 6),
                              _buildQuickChip('+20K', 20000),
                              const SizedBox(width: 6),
                              _buildQuickChip('+50K', 50000),
                            ],
                          ),
                        ],
                      ),
                    ),
            ),

            // Bottom Action Bar: FIXED & PERMANEN TERLIHAT (Tidak tersembunyi ke bawah)
            _buildBottomCheckoutBar(account, balanceAfter, isBalanceEnough),
          ],
        ),
      ),
    );
  }

  /// Kartu identitas santri ketika sudah terdeteksi (Compact).
  Widget _buildDetectedCard(StudentAccount account, bool isBalanceEnough) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF0D5C3A).withValues(alpha: 0.3), width: 1.5),
      ),
      child: Row(
        children: [
          Stack(
            children: [
              StudentAvatar(account: account, radius: 22),
              Positioned(
                bottom: 0,
                right: 0,
                child: Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: const Color(0xFF059669),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 1.5),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        account.customerName,
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Color(0xFF0F172A)),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 5),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        color: const Color(0xFFDCFCE7),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text('Aktif', style: TextStyle(fontSize: 8.5, fontWeight: FontWeight.bold, color: Color(0xFF15803D))),
                    ),
                  ],
                ),
                const SizedBox(height: 1),
                Text(
                  'NIS: ${account.accountNumber} • Saldo: ${_formatCurrency(account.balance)}',
                  style: const TextStyle(fontSize: 10.5, color: Color(0xFF64748B), fontWeight: FontWeight.w500),
                  overflow: TextOverflow.ellipsis,
                ),
                // Info Limit Harian Belanja Koperasi (Tiered berdasarkan saldo)
                if (account.dailyLimit > 0) ...[
                  const SizedBox(height: 5),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFFBEB),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: const Color(0xFFFDE68A)),
                    ),
                    child: Text(
                      'Maks belanja hari ini: ${_formatCurrency(account.dailyLimit)}'
                      '${account.remainingDailyLimit != null ? ' • Sisa: ${_formatCurrency(account.remainingDailyLimit!)}' : ''}',
                      style: const TextStyle(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF92400E),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ] else ...[
                  const SizedBox(height: 5),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEF2F2),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: const Color(0xFFFECACA)),
                    ),
                    child: const Text(
                      'Belanja harian tidak tersedia (saldo < Rp 10.000)',
                      style: TextStyle(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFFB91C1C),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ],
            ),
          ),
          OutlinedButton(
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              side: const BorderSide(color: Color(0xFFE2E8F0)),
              foregroundColor: const Color(0xFF64748B),
              minimumSize: Size.zero,
            ),
            onPressed: () {
              setState(() {
                _detectedAccount = null;
                _rfidController.clear();
              });
              _amountFocusNode.unfocus();
            },
            child: const Text('Ganti', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  /// Area input inline: ketuk NIS manual + tombol Cari + tombol Scan (Compact).
  Widget _buildCardInput() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: const [
                  Icon(Icons.credit_card_outlined, size: 16, color: Color(0xFF0D5C3A)),
                  SizedBox(width: 6),
                  Text('Identifikasi Santri', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF1E293B))),
                ],
              ),
              const Text('RFID / Barcode / NIS', style: TextStyle(fontSize: 9.5, color: Color(0xFF94A3B8))),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Container(
                  height: 42,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: _cardFocusNode.hasFocus ? const Color(0xFF0D5C3A) : const Color(0xFFCBD5E1)),
                  ),
                  child: TextField(
                    controller: _rfidController,
                    focusNode: _cardFocusNode,
                    textInputAction: TextInputAction.search,
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                    decoration: InputDecoration(
                      hintText: 'Ketik NIS / Tap Kartu...',
                      hintStyle: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8), fontWeight: FontWeight.normal),
                      prefixIcon: const Icon(Icons.search, size: 18, color: Color(0xFF64748B)),
                      suffixIcon: _rfidController.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, size: 16, color: Color(0xFF94A3B8)),
                              onPressed: () {
                                _rfidController.clear();
                                setState(() {});
                              },
                            )
                          : null,
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                    onChanged: (_) => setState(() {}),
                    onSubmitted: (val) {
                      if (val.trim().isNotEmpty) _detectCard(val.trim());
                    },
                  ),
                ),
              ),
              const SizedBox(width: 6),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFF1F5F9),
                  foregroundColor: const Color(0xFF0F172A),
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  minimumSize: const Size(0, 42),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                    side: const BorderSide(color: Color(0xFFCBD5E1)),
                  ),
                ),
                onPressed: () {
                  final val = _rfidController.text.trim();
                  if (val.isNotEmpty) _detectCard(val);
                },
                child: const Text('Cari', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
              ),
              const SizedBox(width: 6),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0D5C3A),
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  minimumSize: const Size(0, 42),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                icon: const Icon(Icons.qr_code_scanner, size: 16, color: Colors.white),
                label: const Text('Scan', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white)),
                onPressed: _openScanner,
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Bottom Checkout Bar: PINNED PERMANEN DI BAWAH (Tidak akan tersembunyi ke bawah).
  Widget _buildBottomCheckoutBar(StudentAccount? account, double balanceAfter, bool isBalanceEnough) {
    final hasActive = account != null || _amount > 0;

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 10),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Colors.grey.shade200, width: 1)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, -3),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Baris 1: Ringkasan Saldo Akhir & Toggle Struk Thermal
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.account_balance_wallet_outlined,
                      size: 14,
                      color: account == null ? const Color(0xFF94A3B8) : const Color(0xFF0D5C3A),
                    ),
                    const SizedBox(width: 4),
                    const Text('Sisa Saldo: ', style: TextStyle(fontSize: 11.5, color: Color(0xFF64748B))),
                    Text(
                      account == null ? '—' : _formatCurrency(balanceAfter),
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800,
                        color: account == null
                            ? const Color(0xFF64748B)
                            : (isBalanceEnough ? const Color(0xFF0D5C3A) : const Color(0xFFE11D48)),
                      ),
                    ),
                    if (account != null) ...[
                      const SizedBox(width: 5),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                          color: isBalanceEnough ? const Color(0xFFDCFCE7) : const Color(0xFFFFE4E6),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          isBalanceEnough ? 'Cukup' : 'Kurang',
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                            color: isBalanceEnough ? const Color(0xFF15803D) : const Color(0xFFE11D48),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                // Toggle Cetak Struk mini
                InkWell(
                  onTap: () => setState(() => _printReceipt = !_printReceipt),
                  borderRadius: BorderRadius.circular(6),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                    child: Row(
                      children: [
                        Icon(
                          Icons.print_outlined,
                          size: 14,
                          color: _printReceipt ? const Color(0xFF0D5C3A) : const Color(0xFF94A3B8),
                        ),
                        const SizedBox(width: 3),
                        Text(
                          'Struk',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: _printReceipt ? const Color(0xFF0D5C3A) : const Color(0xFF94A3B8),
                          ),
                        ),
                        const SizedBox(width: 4),
                        Container(
                          width: 7,
                          height: 7,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: _printReceipt ? const Color(0xFF059669) : const Color(0xFFCBD5E1),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // Baris 2: Tombol Aksi [Batal] [Tunda] [BAYAR SEKARANG]
            Row(
              children: [
                if (hasActive) ...[
                  // Tombol Batalkan Transaksi
                  InkWell(
                    onTap: _cancelActiveTransaction,
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      height: 44,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFEF2F2),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFFFECACA)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: const [
                          Icon(Icons.close_rounded, size: 16, color: Color(0xFFE11D48)),
                          SizedBox(width: 3),
                          Text('Batal', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: Color(0xFFE11D48))),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),

                  // Tombol Tunda (Hold)
                  InkWell(
                    onTap: _holdTransaction,
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      height: 44,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFFBEB),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFFFDE68A)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: const [
                          Icon(Icons.pause_circle_outline, size: 16, color: Color(0xFFD97706)),
                          SizedBox(width: 3),
                          Text('Tunda', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: Color(0xFFD97706))),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                ],

                // Tombol Proses Bayar Utama
                Expanded(
                  child: SizedBox(
                    height: 44,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0D5C3A),
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      onPressed: _processPayment,
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.point_of_sale, size: 18, color: Colors.white),
                          SizedBox(width: 6),
                          Text(
                            'BAYAR SEKARANG',
                            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900, letterSpacing: 0.3),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCategoryChip(String label, IconData icon) {
    final isSelected = _category == label;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _category = label),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFF0D5C3A) : Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isSelected ? const Color(0xFF0D5C3A) : const Color(0xFFE2E8F0),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 13,
                color: isSelected ? const Color(0xFF86EFAC) : const Color(0xFF64748B),
              ),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                  color: isSelected ? Colors.white : const Color(0xFF475569),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildQuickChip(String label, int value) {
    return Expanded(
      child: GestureDetector(
        onTap: () => _addQuickAmount(value),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xFFF1F5F9),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Color(0xFF0D5C3A)),
          ),
        ),
      ),
    );
  }
}

class _ScannerModal extends StatefulWidget {
  final Function(String) onScanned;

  const _ScannerModal({required this.onScanned});

  @override
  State<_ScannerModal> createState() => _ScannerModalState();
}

class _ScannerModalState extends State<_ScannerModal> {
  bool _hasScanned = false;
  final MobileScannerController _controller = MobileScannerController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.75,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 12),
          Container(
            width: 48,
            height: 4,
            decoration: BoxDecoration(color: const Color(0xFFE2E8F0), borderRadius: BorderRadius.circular(2)),
          ),
          const SizedBox(height: 16),
          const Text(
            'Arahkan Kartu Santri ke Kamera',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: MobileScanner(
                controller: _controller,
                onDetect: (capture) {
                  if (_hasScanned) return;
                  final barcodes = capture.barcodes;
                  for (final barcode in barcodes) {
                    if (barcode.rawValue != null) {
                      _hasScanned = true;
                      _controller.stop(); // Hentikan kamera segera agar tidak leak
                      widget.onScanned(barcode.rawValue!);
                      break;
                    }
                  }
                },
              ),
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }
}
