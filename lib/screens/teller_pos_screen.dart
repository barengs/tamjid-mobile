import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../core/api_service.dart';
import '../core/num_parser.dart';
import '../models/student_account.dart';
import '../widgets/app_header.dart';
import '../widgets/student_avatar.dart';

/// Formatter pemisah ribuan (1.500.000) untuk input nominal tarik tunai.
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

/// Model transaksi tarik tunai yang ditunda di perangkat mobile teller.
class PendingTellerWithdrawal {
  final StudentAccount account;
  final double amount;
  final String time;

  PendingTellerWithdrawal({
    required this.account,
    required this.amount,
    required this.time,
  });
}

class TellerPosScreen extends StatefulWidget {
  const TellerPosScreen({super.key});

  @override
  State<TellerPosScreen> createState() => _TellerPosScreenState();
}

class _TellerPosScreenState extends State<TellerPosScreen> {
  bool _isLoading = false;
  bool _printReceipt = true;
  StudentAccount? _detectedAccount;
  final List<PendingTellerWithdrawal> _pendingWithdrawals = [];

  final TextEditingController _rfidController = TextEditingController();
  final FocusNode _cardFocusNode = FocusNode();
  final TextEditingController _amountController = TextEditingController();
  final FocusNode _amountFocusNode = FocusNode();

  static const Color primaryBlue = Color(0xFF1E40AF); // Deep Royal Blue Bank

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
    return NumberFormat.currency(
      locale: 'id_ID',
      symbol: 'Rp ',
      decimalDigits: 0,
    ).format(val);
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
      _amountController.selection = TextSelection.collapsed(
        offset: formatted.length,
      );
    });
  }

  void _setExactAmount(double val) {
    setState(() {
      final formatted = NumberFormat('#,###', 'id_ID').format(val.toInt());
      _amountController.text = formatted;
      _amountController.selection = TextSelection.collapsed(
        offset: formatted.length,
      );
    });
  }

  /// Tunda transaksi aktif ke antrian pending teller.
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
      _pendingWithdrawals.insert(
        0,
        PendingTellerWithdrawal(
          account: account,
          amount: _amount,
          time: DateFormat('HH:mm').format(DateTime.now()),
        ),
      );
      ApiService().pendingCount.value = _pendingWithdrawals.length;
      _amountController.clear();
      _rfidController.clear();
      _detectedAccount = null;
    });
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: const Color(0xFFD97706),
        content: Text(
          'Tarik tunai ${account.customerName} ditunda (${_pendingWithdrawals.length} antrian).',
        ),
      ),
    );
  }

  /// Lanjutkan transaksi yang ditunda.
  void _resumePending(int index) {
    if (index < 0 || index >= _pendingWithdrawals.length) return;
    if (_detectedAccount != null || _amount > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Color(0xFFD97706),
          content: Text(
            'Selesaikan atau tunda transaksi aktif terlebih dahulu.',
          ),
        ),
      );
      return;
    }
    final txn = _pendingWithdrawals.removeAt(index);
    ApiService().pendingCount.value = _pendingWithdrawals.length;
    setState(() {
      _detectedAccount = txn.account;
      _rfidController.text = txn.account.accountNumber;
      _amountController.text = NumberFormat(
        '#,###',
        'id_ID',
      ).format(txn.amount.toInt());
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: primaryBlue,
        content: Text(
          'Transaksi tarik tunai ${txn.account.customerName} dilanjutkan.',
        ),
      ),
    );
  }

  /// Buka modal daftar penarikan ditunda.
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
                decoration: BoxDecoration(
                  color: const Color(0xFFE2E8F0),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 12, 18, 8),
                child: Row(
                  children: [
                    const Icon(
                      Icons.schedule,
                      size: 18,
                      color: Color(0xFFD97706),
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      'Antrian Tarik Tunai Ditunda',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 1.5,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFD97706),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '${_pendingWithdrawals.length}',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    const Spacer(),
                    if (_pendingWithdrawals.isNotEmpty)
                      TextButton(
                        onPressed: () {
                          Navigator.pop(ctx);
                          setState(() {
                            _pendingWithdrawals.clear();
                            ApiService().pendingCount.value = 0;
                          });
                        },
                        child: const Text(
                          'Kosongkan',
                          style: TextStyle(
                            fontSize: 12,
                            color: Color(0xFFE11D48),
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const Divider(height: 1),
              if (_pendingWithdrawals.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 40),
                  child: Text(
                    'Tidak ada transaksi tarik tunai yang ditunda.',
                    style: TextStyle(color: Color(0xFF94A3B8)),
                  ),
                )
              else
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    padding: const EdgeInsets.all(16),
                    itemCount: _pendingWithdrawals.length,
                    itemBuilder: (context, i) {
                      final txn = _pendingWithdrawals[i];
                      return Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEFF6FF),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: const Color(0xFFBFDBFE)),
                        ),
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 4,
                          ),
                          leading: CircleAvatar(
                            backgroundColor: primaryBlue,
                            foregroundColor: Colors.white,
                            child: Text(
                              txn.account.customerName.isNotEmpty
                                  ? txn.account.customerName[0].toUpperCase()
                                  : 'S',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          title: Text(
                            txn.account.customerName,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 13.5,
                            ),
                          ),
                          subtitle: Text(
                            'NIS ${txn.account.accountNumber} • ${txn.time} WIB',
                            style: const TextStyle(
                              fontSize: 11,
                              color: Color(0xFF1E3A8A),
                            ),
                          ),
                          trailing: Text(
                            _formatCurrency(txn.amount),
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w900,
                              color: primaryBlue,
                            ),
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

  /// Cari rekening santri berdasarkan NIS atau nomor kartu RFID.
  Future<void> _detectCard(String identifier) async {
    setState(() => _isLoading = true);
    try {
      final account = await ApiService().checkAccount(
        identifier,
        outletType: 'koperasi',
      );
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

  /// Eksekusi tarik tunai di backend bank santri.
  Future<void> _processWithdrawal() async {
    final account = _detectedAccount;
    if (account == null) {
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
          content: Text('Nominal penarikan tunai belum diisi.'),
        ),
      );
      return;
    }

    final double balanceAfter = account.balance - _amount;
    if (balanceAfter < account.minimumBalance) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFFE11D48),
          content: Text(
            'Saldo tidak mencukupi! Sisa saldo wajib minimal ${_formatCurrency(account.minimumBalance)}.',
          ),
        ),
      );
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() => _isLoading = true);

    try {
      final res = await ApiService().cashWithdrawal(
        accountNumber: account.accountNumber,
        amount: _amount,
        description: 'Tarik Tunai Mobile Teller',
      );

      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _amountController.clear();
        _rfidController.clear();
        _detectedAccount = null;
      });

      final txn = res['transaction'] as Map<String, dynamic>?;
      final refNumber =
          txn?['reference_number'] ?? txn?['transaction_number'] ?? '-';
      final double amountDone = toD(res['transaction']?['amount'], fallback: _amount);
      final double balanceAfterVal = toD(res['balance_after'], fallback: balanceAfter);

      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          icon: const Icon(
            Icons.check_circle_outline,
            color: primaryBlue,
            size: 54,
          ),
          title: const Text('Penarikan Tunai Berhasil!'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _formatCurrency(amountDone),
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: primaryBlue,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Santri: ${account.customerName}',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                'NIS: ${account.accountNumber}',
                style: const TextStyle(
                  fontSize: 11.5,
                  color: Color(0xFF64748B),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Ref: $refNumber',
                style: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
              ),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFEFF6FF),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'Sisa Saldo: ${_formatCurrency(balanceAfterVal)}',
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.bold,
                    color: primaryBlue,
                  ),
                ),
              ),
              if (_printReceipt) ...[
                const SizedBox(height: 12),
                const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.print_outlined, size: 16, color: primaryBlue),
                    SizedBox(width: 6),
                    Text(
                      'Struk penarikan tunai tercetak otomatis',
                      style: TextStyle(fontSize: 11.5, color: primaryBlue),
                    ),
                  ],
                ),
              ],
            ],
          ),
          actions: [
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: primaryBlue,
                minimumSize: const Size(double.infinity, 44),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              onPressed: () => Navigator.pop(ctx),
              child: const Text(
                'SELESAI (OK)',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
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
    final double maxWithdrawable = account != null
        ? (account.balance - account.minimumBalance).clamp(0.0, double.infinity)
        : 0.0;
    final double balanceAfter = (account?.balance ?? 0) - _amount;
    final bool isBalanceEnough = account == null
        ? true
        : balanceAfter >= account.minimumBalance;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: Column(
          children: [
            const AppHeader(title: 'Tarik Tunai'),

            // Pill Banner Transaksi Ditunda
            if (_pendingWithdrawals.isNotEmpty)
              InkWell(
                onTap: _showPendingBottomSheet,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 7,
                  ),
                  margin: const EdgeInsets.fromLTRB(14, 6, 14, 0),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEFF6FF),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFBFDBFE)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.schedule, size: 15, color: primaryBlue),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${_pendingWithdrawals.length} Tarik Tunai Ditunda • Ketuk untuk melanjutkan',
                          style: const TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.bold,
                            color: primaryBlue,
                          ),
                        ),
                      ),
                      const Icon(
                        Icons.chevron_right,
                        size: 16,
                        color: primaryBlue,
                      ),
                    ],
                  ),
                ),
              ),

            // Konten Tengah
            Expanded(
              child: _isLoading
                  ? const Center(
                      child: CircularProgressIndicator(color: primaryBlue),
                    )
                  : SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // 1. Identifikasi Kartu Santri
                          if (account != null)
                            _buildDetectedCard(account, maxWithdrawable)
                          else
                            _buildCardInput(),
                          const SizedBox(height: 10),

                          // 2. Input Nominal Tarik Tunai
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                'NOMINAL TARIK TUNAI',
                                style: TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w900,
                                  color: Color(0xFF64748B),
                                  letterSpacing: 0.6,
                                ),
                              ),
                              TextButton.icon(
                                style: TextButton.styleFrom(
                                  foregroundColor: const Color(0xFF64748B),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                  ),
                                  minimumSize: Size.zero,
                                  tapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                ),
                                icon: const Icon(Icons.refresh, size: 13),
                                label: const Text(
                                  'Reset',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                onPressed: _resetAmount,
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: _amountFocusNode.hasFocus
                                    ? primaryBlue
                                    : const Color(0xFFE2E8F0),
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
                                    color: primaryBlue,
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

                          // 3. Tambah Nominal Cepat (+)
                          const Text(
                            'Pilihan Nominal Cepat',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF334155),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              _buildQuickChip('+10K', 10000),
                              _buildQuickChip('+20K', 20000),
                              _buildQuickChip('+50K', 50000),
                              _buildQuickChip('+100K', 100000),
                              _buildQuickChip('+200K', 200000),
                              if (account != null && maxWithdrawable > 0)
                                ActionChip(
                                  backgroundColor: const Color(0xFFEFF6FF),
                                  side: const BorderSide(
                                    color: Color(0xFFBFDBFE),
                                  ),
                                  label: Text(
                                    'Semua (${_formatCurrency(maxWithdrawable)})',
                                    style: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: primaryBlue,
                                    ),
                                  ),
                                  onPressed: () =>
                                      _setExactAmount(maxWithdrawable),
                                ),
                            ],
                          ),
                          const SizedBox(height: 12),

                          // 4. Catatan Kebijakan Teller
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF1F5F9),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: const Color(0xFFE2E8F0),
                              ),
                            ),
                            child: const Row(
                              children: [
                                Icon(
                                  Icons.info_outline,
                                  size: 16,
                                  color: Color(0xFF64748B),
                                ),
                                SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'Tarik tunai teller tanpa batasan limit harian. Penarikan wajib menyisakan saldo mengendap.',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Color(0xFF475569),
                                      height: 1.3,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
            ),

            // Bottom Action Bar: FIXED & PERMANEN TERLIHAT
            _buildBottomBar(
              account,
              balanceAfter,
              isBalanceEnough,
              maxWithdrawable,
            ),
          ],
        ),
      ),
    );
  }

  /// Kartu identitas santri & informasi saldo perbankan
  Widget _buildDetectedCard(StudentAccount account, double maxWithdrawable) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: primaryBlue.withValues(alpha: 0.3),
          width: 1.5,
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              StudentAvatar(account: account, radius: 24),
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
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF0F172A),
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 5),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 5,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFDCFCE7),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            'Aktif',
                            style: TextStyle(
                              fontSize: 8.5,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF15803D),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 1),
                    Text(
                      'NIS: ${account.accountNumber}${account.student?.className != null ? ' • Kelas ${account.student!.className}' : ''}',
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF64748B),
                        fontWeight: FontWeight.w500,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
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
                child: const Text(
                  'Ganti',
                  style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Divider(height: 1),
          const SizedBox(height: 8),

          // Detail Saldo Perbankan
          Row(
            children: [
              Expanded(
                child: _buildSaldoBox(
                  'Saldo Total',
                  _formatCurrency(account.balance),
                  const Color(0xFF0F172A),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildSaldoBox(
                  'Saldo Minimum',
                  _formatCurrency(account.minimumBalance),
                  const Color(0xFF64748B),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildSaldoBox(
                  'Bisa Ditarik',
                  _formatCurrency(maxWithdrawable),
                  primaryBlue,
                  isBold: true,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSaldoBox(
    String label,
    String value,
    Color valueColor, {
    bool isBold = false,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 9.5,
              color: Color(0xFF64748B),
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: isBold ? FontWeight.w900 : FontWeight.w700,
              color: valueColor,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  /// Area input manual NIS + tombol Scan
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
          const Row(
            children: [
              Icon(Icons.credit_card, size: 16, color: primaryBlue),
              SizedBox(width: 6),
              Text(
                'Identifikasi Santri (NIS / Tap Kartu)',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF334155),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _rfidController,
                  focusNode: _cardFocusNode,
                  keyboardType: TextInputType.text,
                  decoration: InputDecoration(
                    hintText: 'Ketik NIS atau Tap Kartu RFID',
                    hintStyle: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF94A3B8),
                    ),
                    filled: true,
                    fillColor: const Color(0xFFF8FAFC),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                    ),
                    isDense: true,
                  ),
                  onSubmitted: (val) {
                    if (val.trim().isNotEmpty) _detectCard(val.trim());
                  },
                ),
              ),
              const SizedBox(width: 6),
              IconButton.filled(
                style: IconButton.styleFrom(
                  backgroundColor: primaryBlue,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                icon: const Icon(Icons.search, size: 20),
                onPressed: () {
                  final text = _rfidController.text.trim();
                  if (text.isNotEmpty) _detectCard(text);
                },
              ),
              const SizedBox(width: 4),
              IconButton.outlined(
                style: IconButton.styleFrom(
                  foregroundColor: primaryBlue,
                  side: const BorderSide(color: primaryBlue),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                icon: const Icon(Icons.qr_code_scanner, size: 20),
                onPressed: _openScanner,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildQuickChip(String label, int val) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => _addQuickAmount(val),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFFCBD5E1)),
        ),
        child: Text(
          label,
          style: const TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
            color: Color(0xFF1E293B),
          ),
        ),
      ),
    );
  }

  /// Bottom action bar permanen
  Widget _buildBottomBar(
    StudentAccount? account,
    double balanceAfter,
    bool isBalanceEnough,
    double maxWithdrawable,
  ) {
    final bool canSubmit = account != null && _amount > 0 && isBalanceEnough;

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Colors.grey.shade200)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Sisa saldo & toggle cetak struk
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              if (account != null)
                Text(
                  isBalanceEnough
                      ? 'Sisa Saldo: ${_formatCurrency(balanceAfter)}'
                      : 'Kurang saldo min ${_formatCurrency(account.minimumBalance)}',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.bold,
                    color: isBalanceEnough
                        ? const Color(0xFF0F172A)
                        : const Color(0xFFE11D48),
                  ),
                )
              else
                const Text(
                  'Siap melayani penarikan tunai',
                  style: TextStyle(fontSize: 11.5, color: Color(0xFF64748B)),
                ),
              Row(
                children: [
                  const Text(
                    'Cetak Struk',
                    style: TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                  ),
                  const SizedBox(width: 4),
                  SizedBox(
                    height: 22,
                    width: 28,
                    child: Switch(
                      value: _printReceipt,
                      activeThumbColor: primaryBlue,
                      activeTrackColor: primaryBlue.withValues(alpha: 0.3),
                      onChanged: (v) => setState(() => _printReceipt = v),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Tombol Aksi: Tunda & Eksekusi
          Row(
            children: [
              if (account != null && _amount > 0) ...[
                OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFD97706),
                    side: const BorderSide(color: Color(0xFFD97706)),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 12,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: _holdTransaction,
                  child: const Text(
                    'Tunda',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                  ),
                ),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: canSubmit
                        ? primaryBlue
                        : const Color(0xFFCBD5E1),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: canSubmit ? 2 : 0,
                  ),
                  icon: const Icon(Icons.payments_rounded, size: 20),
                  label: Text(
                    account == null
                        ? 'TAP KARTU TERLEBIH DAHULU'
                        : (_amount <= 0
                              ? 'MASUKKAN NOMINAL'
                              : (isBalanceEnough
                                    ? 'PROSES TARIK TUNAI (${_formatCurrency(_amount)})'
                                    : 'SALDO TIDAK MENCUKUPI')),
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                    ),
                  ),
                  onPressed: canSubmit ? _processWithdrawal : null,
                ),
              ),
            ],
          ),
        ],
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
            decoration: BoxDecoration(
              color: const Color(0xFFE2E8F0),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Arahkan Kartu Santri ke Kamera',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Color(0xFF0F172A),
            ),
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
                      _controller.stop();
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
