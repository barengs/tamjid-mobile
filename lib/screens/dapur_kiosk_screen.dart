import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../core/api_service.dart';
import '../models/koperasi_config.dart';
import '../models/student_account.dart';
import '../widgets/app_header.dart';
import '../widgets/student_avatar.dart';

enum ScanFeedbackType { idle, success, alreadyTapped, error, outsideHours }

class DapurKioskScreen extends StatefulWidget {
  const DapurKioskScreen({super.key});

  @override
  State<DapurKioskScreen> createState() => _DapurKioskScreenState();
}

class _DapurKioskScreenState extends State<DapurKioskScreen> {
  KoperasiConfig? _config;
  bool _isLoading = true;
  bool _isProcessing = false;

  // Mode scan kamera
  bool _isCameraActive = true;
  bool _canScan = true;
  final MobileScannerController _scannerController = MobileScannerController(
    detectionSpeed: DetectionSpeed.normal,
    facing: CameraFacing.back,
  );

  // Manual input
  final TextEditingController _rfidController = TextEditingController();
  final FocusNode _cardFocusNode = FocusNode();

  // Scan feedback state
  ScanFeedbackType _feedbackType = ScanFeedbackType.idle;
  String _feedbackMessage = '';
  Timer? _autoResumeTimer;

  // Pengaturan
  bool _beepVibrate = true;
  bool _autoReset = true;

  // Real-time data dari backend (tanpa data dummy)
  List<Map<String, dynamic>> _recentTransactions = [];
  int _todayPortionsCount = 0;
  int _totalPortions = 0;

  @override
  void initState() {
    super.initState();
    _loadAllData();
  }

  @override
  void dispose() {
    _autoResumeTimer?.cancel();
    _rfidController.dispose();
    _cardFocusNode.dispose();
    _scannerController.dispose();
    super.dispose();
  }

  Future<void> _loadAllData() async {
    setState(() => _isLoading = true);
    try {
      final configFuture = ApiService().getConfig();
      final dashboardFuture = ApiService().getDashboard();

      final results = await Future.wait([configFuture, dashboardFuture]);
      final config = results[0] as KoperasiConfig;
      final dashboard = results[1] as Map<String, dynamic>;

      final stats = dashboard['stats'] as Map<String, dynamic>? ?? {};
      final recentRaw = dashboard['recent_transactions'] as List<dynamic>? ?? [];

      // Filter hanya transaksi dapur untuk recent list
      final dapurTxns = recentRaw
          .whereType<Map<String, dynamic>>()
          .where((t) => t['is_dapur'] == true || t['type'] == 'DPU')
          .toList();

      if (mounted) {
        setState(() {
          _config = config;
          _todayPortionsCount = (stats['dapur_count'] ?? 0) as int;
          _totalPortions = (stats['dapur_target'] ?? 620) as int;
          _recentTransactions = dapurTxns;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Gagal memuat data dapur: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  /// Memproses klaim jatah makan santri (via Barcode / RFID / NIS Manual)
  Future<void> _handleStudentTap(String identifier) async {
    if (_isProcessing) return;
    _autoResumeTimer?.cancel();

    final cleanId = identifier.trim();
    if (cleanId.isEmpty) return;

    final activeSession = _resolveActiveSession();
    if (activeSession == null) {
      _setFeedback(
        type: ScanFeedbackType.outsideHours,
        message: 'Di luar jam makan santri. Silakan periksa jadwal makan.',
      );
      return;
    }

    setState(() {
      _isProcessing = true;
      _canScan = false;
    });

    try {
      // 1. Debit hak makan santri via backend API
      await ApiService().debit(
        identifier: cleanId,
        amount: activeSession.price,
        outletType: 'dapur',
        mealSession: activeSession.id,
        description: 'Makan ${activeSession.name}',
      );

      // 2. Ambil data akun santri terbaru (termasuk saldo & profil)
      final account = await ApiService().checkAccount(cleanId, outletType: 'dapur');

      final mealPrice = activeSession.price;
      final remainingMeals = _calculateRemainingMeals(activeSession);
      final remainingBalance = (account.balance - mealPrice).clamp(0.0, double.infinity);

      if (_beepVibrate) {
        HapticFeedback.mediumImpact();
        SystemSound.play(SystemSoundType.click);
      }

      _setFeedback(
        type: ScanFeedbackType.success,
        message: 'SILAKAN AMBIL MAKAN',
      );

      // 3. Update realtime counter & daftar aktivitas terkini secara langsung
      if (mounted) {
        setState(() {
          _todayPortionsCount++;
          _recentTransactions.insert(0, {
            'account': account,
            'customer_name': account.customerName,
            'nis': account.accountNumber,
            'class_name': account.student?.className != null
                ? 'Kelas ${account.student!.className}'
                : 'NIS: ${account.accountNumber}',
            'hostel': account.student?.hostel,
            'balance_formatted': account.balanceFormatted,
            'remaining_balance_formatted': _formatCurrency(remainingBalance),
            'remaining_meals': remainingMeals,
            'meal_session_name': activeSession.name,
            'time': DateFormat('HH:mm').format(DateTime.now()),
            'is_new': true,
          });
          if (_recentTransactions.length > 20) {
            _recentTransactions.removeLast();
          }
          _rfidController.clear();
        });
      }
    } catch (e) {
      if (_beepVibrate) {
        HapticFeedback.heavyImpact();
      }
      final errorMsg = e.toString().replaceAll('Exception: ', '');
      if (errorMsg.toLowerCase().contains('sudah mengambil')) {
        _setFeedback(
          type: ScanFeedbackType.alreadyTapped,
          message: errorMsg,
        );
      } else {
        _setFeedback(
          type: ScanFeedbackType.error,
          message: errorMsg,
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }

  void _setFeedback({
    required ScanFeedbackType type,
    required String message,
  }) {
    setState(() {
      _feedbackType = type;
      _feedbackMessage = message;
    });

    // Otomatis kembali ke mode siap scan dalam 2.5 detik tanpa perlu tap tombol lagi
    if (_autoReset) {
      _autoResumeTimer = Timer(const Duration(milliseconds: 2500), () {
        if (mounted) {
          setState(() {
            _feedbackType = ScanFeedbackType.idle;
            _feedbackMessage = '';
            _canScan = true; // Siap memindai kartu santri berikutnya
          });
        }
      });
    }
  }

  String _formatCurrency(double val) {
    return NumberFormat.currency(
      locale: 'id_ID',
      symbol: 'Rp ',
      decimalDigits: 0,
    ).format(val);
  }

  /// Menghitung sisa jatah makan santri hari ini berdasarkan sesi aktif
  String _calculateRemainingMeals(MealSession? activeSession) {
    if (activeSession != null) {
      switch (activeSession.id.toLowerCase()) {
        case 'pagi':
          return '2x Sesi (Siang & Malam)';
        case 'siang':
          return '1x Sesi (Makan Malam)';
        case 'malam':
          return 'Lengkap (Semua Sesi Diambil)';
        default:
          return '1x Sesi Tersisa';
      }
    }
    final hour = DateTime.now().hour;
    if (hour < 9) return '3x Sesi (Pagi, Siang, Malam)';
    if (hour < 14) return '2x Sesi (Siang & Malam)';
    if (hour < 20) return '1x Sesi (Makan Malam)';
    return '0x Sesi (Jadwal Hari Ini Selesai)';
  }

  MealSession? _resolveActiveSession() {
    if (_config == null) return null;
    final nowTime = DateFormat('HH:mm').format(DateTime.now());
    for (final s in _config!.sessions) {
      if (s.isActive && nowTime.compareTo(s.startTime) >= 0 && nowTime.compareTo(s.endTime) <= 0) {
        return s;
      }
    }
    // Fallback hanya jika server tidak mengirim daftar sesi sama sekali
    if (_config!.sessions.isEmpty) {
      return _config!.isSessionOpen ? _config!.activeSession : null;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final activeSession = _resolveActiveSession();
    final sessionTitle = activeSession?.name ?? 'Sesi Makan Santri';
    final sessionTime = activeSession != null
        ? '${activeSession.startTime} - ${activeSession.endTime} WIB'
        : 'Sesuai Jadwal';

    final progress = _totalPortions > 0
        ? (_todayPortionsCount / _totalPortions).clamp(0.0, 1.0)
        : 0.0;
    final percentage = (progress * 100).round();
    final remaining = (_totalPortions - _todayPortionsCount).clamp(0, _totalPortions);

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: SafeArea(
        child: Column(
          children: [
            const AppHeader(title: 'Terminal DPU'),
            Expanded(
              child: _isLoading
                  ? const Center(
                      child: CircularProgressIndicator(color: Color(0xFF0D5C3A)),
                    )
                  : RefreshIndicator(
                      onRefresh: _loadAllData,
                      color: const Color(0xFF0D5C3A),
                      child: ListView(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        children: [
                          // 1. Status Sesi DPU & Progress Distribusi Real
                          _buildSessionProgressCard(
                            sessionTitle: sessionTitle,
                            sessionTime: sessionTime,
                            progress: progress,
                            percentage: percentage,
                            remaining: remaining,
                          ),
                          const SizedBox(height: 12),

                          // 2. Bar Input Manual / Scan (Mekanisme seperti Kasir Koperasi)
                          _buildCardInput(),
                          const SizedBox(height: 12),

                          // 3. Area Scan Kamera Inline ATAU Area Tempel Kartu (NFC)
                          if (_isCameraActive)
                            _buildCameraScanSection()
                          else
                            _buildNfcTapSection(),
                          const SizedBox(height: 14),

                          // 4. Alert Banner (Hanya muncul jika klaim ditolak atau error)
                          _buildAlertBanner(),

                          // 5. Pengaturan Kiosk (Beep & Auto-Reset)
                          _buildSettingsToggle(),
                          const SizedBox(height: 16),

                          // 6. Aktivitas Terkini (Real-time dari Database)
                          _buildRecentActivitySection(),
                          const SizedBox(height: 24),
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  /// Banner informasi sesi makan aktif dan kuota porsi
  Widget _buildSessionProgressCard({
    required String sessionTitle,
    required String sessionTime,
    required double progress,
    required int percentage,
    required int remaining,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: const Color(0xFF0D5C3A),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.soup_kitchen_outlined, color: Colors.white, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'DAPUR UMUM PESANTREN',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF0D5C3A),
                        letterSpacing: 0.6,
                      ),
                    ),
                    Text(
                      'Sesi $sessionTitle',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                decoration: BoxDecoration(
                  color: const Color(0xFFCCFBF1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.schedule, size: 12, color: Color(0xFF0F766E)),
                    const SizedBox(width: 4),
                    Text(
                      sessionTime,
                      style: const TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF0F766E),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Realisasi Distribusi Porsi',
                style: TextStyle(fontSize: 11.5, color: Color(0xFF64748B)),
              ),
              Text(
                '$_todayPortionsCount${_totalPortions > 0 ? " / $_totalPortions" : ""} Santri',
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF0F172A),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 7,
              backgroundColor: const Color(0xFFE2E8F0),
              valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF0D5C3A)),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _totalPortions > 0
                    ? 'Tersisa $remaining porsi'
                    : 'Terdistribusi $_todayPortionsCount porsi',
                style: const TextStyle(fontSize: 10.5, color: Color(0xFF64748B)),
              ),
              Text(
                '$percentage% Selesai',
                style: const TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF059669),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Mekanisme input santri persis seperti di Kasir Koperasi
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
                  Text(
                    'Identifikasi Santri',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF1E293B),
                    ),
                  ),
                ],
              ),
              const Text(
                'RFID / Barcode / NIS',
                style: TextStyle(fontSize: 9.5, color: Color(0xFF94A3B8)),
              ),
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
                    border: Border.all(
                      color: _cardFocusNode.hasFocus
                          ? const Color(0xFF0D5C3A)
                          : const Color(0xFFCBD5E1),
                    ),
                  ),
                  child: TextField(
                    controller: _rfidController,
                    focusNode: _cardFocusNode,
                    textInputAction: TextInputAction.search,
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                    decoration: InputDecoration(
                      hintText: 'Ketik NIS santri...',
                      hintStyle: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF94A3B8),
                        fontWeight: FontWeight.normal,
                      ),
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
                      if (val.trim().isNotEmpty) _handleStudentTap(val.trim());
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
                  if (val.isNotEmpty) _handleStudentTap(val);
                },
                child: const Text(
                  'Cari',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(width: 6),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: _isCameraActive
                      ? const Color(0xFF0F766E)
                      : const Color(0xFF0D5C3A),
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  minimumSize: const Size(0, 42),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                icon: Icon(
                  _isCameraActive ? Icons.camera_alt : Icons.qr_code_scanner,
                  size: 16,
                  color: Colors.white,
                ),
                label: Text(
                  _isCameraActive ? 'Kamera Aktif' : 'Scan',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                onPressed: () {
                  setState(() {
                    _isCameraActive = true;
                    _canScan = true;
                  });
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Fitur Scan Kamera Inline: Terus aktif & otomatis siap kembali setelah berhasil scan
  Widget _buildCameraScanSection() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          // Header Bar Kamera + Tombol Tutup Kamera (Ganti ke NFC)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            color: const Color(0xFF0F172A),
            child: Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: _canScan ? const Color(0xFF22C55E) : const Color(0xFFF59E0B),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  _isProcessing
                      ? 'Memproses Kartu...'
                      : _canScan
                          ? 'Arahkan Barcode / QR Kartu Santri'
                          : 'Selesai • Siap Kembali Sebentar Lagi...',
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
                const Spacer(),
                // Tombol Menutup Fitur Scan untuk beralih ke Tempel Kartu (NFC)
                TextButton.icon(
                  style: TextButton.styleFrom(
                    backgroundColor: Colors.white.withValues(alpha: 0.15),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  icon: const Icon(Icons.close, size: 14, color: Colors.white),
                  label: const Text(
                    'Tutup / NFC',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  onPressed: () {
                    setState(() {
                      _isCameraActive = false;
                      _canScan = false;
                    });
                  },
                ),
              ],
            ),
          ),

          // Viewport Kamera MobileScanner
          SizedBox(
            height: 220,
            width: double.infinity,
            child: Stack(
              alignment: Alignment.center,
              children: [
                MobileScanner(
                  controller: _scannerController,
                  onDetect: (capture) {
                    if (!_canScan || _isProcessing) return;
                    final barcodes = capture.barcodes;
                    for (final barcode in barcodes) {
                      final raw = barcode.rawValue;
                      if (raw != null && raw.trim().isNotEmpty) {
                        _handleStudentTap(raw.trim());
                        break;
                      }
                    }
                  },
                ),

                // Frame Viewfinder Overlay
                Container(
                  width: 220,
                  height: 140,
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: _canScan
                          ? const Color(0xFF34D399)
                          : const Color(0xFFF59E0B),
                      width: 2.2,
                    ),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Stack(
                    children: [
                      if (_isProcessing)
                        const Center(
                          child: CircularProgressIndicator(
                            color: Color(0xFF34D399),
                            strokeWidth: 3,
                          ),
                        ),
                    ],
                  ),
                ),

                // Hint Bawah
                Positioned(
                  bottom: 10,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.65),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: const [
                        Icon(Icons.qr_code, size: 12, color: Color(0xFFA7F3D0)),
                        SizedBox(width: 5),
                        Text(
                          'Deteksi Otomatis Siap',
                          style: TextStyle(
                            fontSize: 10.5,
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Fitur Tempel Kartu Santri (NFC) ketika mode scan kamera ditutup
  Widget _buildNfcTapSection() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 22),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0D5C3A), Color(0xFF115E59)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0D5C3A).withValues(alpha: 0.25),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              shape: BoxShape.circle,
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.3),
                width: 2,
              ),
            ),
            child: const Icon(Icons.sensors, color: Colors.white, size: 34),
          ),
          const SizedBox(height: 12),
          const Text(
            'Tempel Kartu Santri (NFC)',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w900,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Sentuhkan kartu RFID santri ke punggung perangkat',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 11.5,
              color: Color(0xFFA7F3D0),
              height: 1.3,
            ),
          ),
          const SizedBox(height: 14),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: Color(0xFF34D399), width: 1.4),
              backgroundColor: Colors.white.withValues(alpha: 0.12),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            icon: const Icon(Icons.camera_alt_outlined, color: Colors.white, size: 16),
            label: const Text(
              'Buka Scan Barcode Kamera',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
            onPressed: () {
              setState(() {
                _isCameraActive = true;
                _canScan = true;
              });
            },
          ),
        ],
      ),
    );
  }

  /// Banner Peringatan (Hanya muncul jika klaim ditolak / error)
  Widget _buildAlertBanner() {
    if (_feedbackType == ScanFeedbackType.alreadyTapped) {
      return Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFFEF2F2),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFFECACA), width: 1.5),
        ),
        child: Row(
          children: [
            const Icon(Icons.block, size: 20, color: Color(0xFFDC2626)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'KLAIM DITOLAK (KUOTA MAKAN TERCAPAI)',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFFB91C1C),
                      letterSpacing: 0.4,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _feedbackMessage.isNotEmpty
                        ? _feedbackMessage
                        : 'Santri sudah mengambil jatah makan pada sesi ini!',
                    style: const TextStyle(fontSize: 11, color: Color(0xFF991B1B)),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    if (_feedbackType == ScanFeedbackType.error || _feedbackType == ScanFeedbackType.outsideHours) {
      return Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFFFFBEB),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFFDE68A), width: 1.5),
        ),
        child: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: Color(0xFFD97706), size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                _feedbackMessage.isNotEmpty
                    ? _feedbackMessage
                    : 'Gagal memproses transaksi santri.',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF92400E),
                ),
              ),
            ),
          ],
        ),
      );
    }

    return const SizedBox.shrink();
  }

  /// Pengaturan Kiosk (Beep dan Auto-Reset)
  Widget _buildSettingsToggle() {
    return Row(
      children: [
        Expanded(
          child: _toggleTile(
            title: 'Beep & Getar',
            subtitle: 'Konfirmasi audio',
            value: _beepVibrate,
            onChanged: (val) => setState(() => _beepVibrate = val),
            icon: Icons.volume_up_outlined,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _toggleTile(
            title: 'Auto-Kembali Scan',
            subtitle: 'Jeda 2.8 detik',
            value: _autoReset,
            onChanged: (val) => setState(() => _autoReset = val),
            icon: Icons.restart_alt,
          ),
        ),
      ],
    );
  }

  Widget _toggleTile({
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: const Color(0xFF0D5C3A)),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF0F172A),
                  ),
                ),
                Text(
                  subtitle,
                  style: const TextStyle(fontSize: 9.5, color: Color(0xFF64748B)),
                ),
              ],
            ),
          ),
          Transform.scale(
            scale: 0.75,
            child: Switch(
              value: value,
              activeTrackColor: const Color(0xFF0D5C3A),
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }

  /// Daftar Aktivitas Terkini Real dari Backend
  Widget _buildRecentActivitySection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: const [
                Icon(Icons.history, size: 16, color: Color(0xFF0F172A)),
                SizedBox(width: 6),
                Text(
                  'Aktivitas Terkini (Hari Ini)',
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF0F172A),
                  ),
                ),
              ],
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0xFFDCFCE7),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Row(
                children: [
                  Icon(Icons.cloud_done, size: 11, color: Color(0xFF15803D)),
                  SizedBox(width: 4),
                  Text(
                    'Live Data',
                    style: TextStyle(
                      fontSize: 9.5,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF15803D),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),

        if (_recentTransactions.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Column(
              children: [
                Icon(Icons.inbox_outlined, size: 28, color: Colors.grey.shade400),
                const SizedBox(height: 6),
                const Text(
                  'Belum ada santri yang mengambil jatah makan hari ini',
                  style: TextStyle(fontSize: 11.5, color: Color(0xFF94A3B8)),
                ),
              ],
            ),
          )
        else
          ..._recentTransactions.asMap().entries.map((entry) {
            final index = entry.key;
            final t = entry.value;
            final isLatest = index == 0 && t['is_new'] == true;
            final account = t['account'] as StudentAccount?;
            final name = t['customer_name']?.toString() ?? 'Santri';
            final className = t['class_name']?.toString() ?? '-';
            final hostel = t['hostel']?.toString();
            final time = t['time']?.toString() ?? '-';
            final remainingMeals = t['remaining_meals']?.toString();
            final balanceFormatted = t['balance_formatted']?.toString();
            final remainingBalanceFormatted = t['remaining_balance_formatted']?.toString();

            // Jika item memiliki data santri lengkap (dari scan/tap yang baru)
            if (account != null) {
              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isLatest ? const Color(0xFFF0FDF4) : Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: isLatest ? const Color(0xFF86EFAC) : const Color(0xFFE2E8F0),
                    width: isLatest ? 1.5 : 1,
                  ),
                  boxShadow: isLatest
                      ? [
                          BoxShadow(
                            color: const Color(0xFF059669).withValues(alpha: 0.1),
                            blurRadius: 8,
                            offset: const Offset(0, 3),
                          ),
                        ]
                      : null,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header Santri
                    Row(
                      children: [
                        StudentAvatar(account: account, radius: 20),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Flexible(
                                    child: Text(
                                      name,
                                      style: const TextStyle(
                                        fontSize: 13.5,
                                        fontWeight: FontWeight.w900,
                                        color: Color(0xFF0F172A),
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  if (isLatest)
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFDCFCE7),
                                        borderRadius: BorderRadius.circular(5),
                                      ),
                                      child: const Text(
                                        'Terbaru',
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
                                '$className${hostel != null ? " • $hostel" : ""} • NIS: ${account.accountNumber}',
                                style: const TextStyle(fontSize: 10.5, color: Color(0xFF64748B)),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFFDCFCE7),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Text(
                                '1 Porsi',
                                style: TextStyle(
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF15803D),
                                ),
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              time,
                              style: const TextStyle(fontSize: 9.5, color: Color(0xFF94A3B8)),
                            ),
                          ],
                        ),
                      ],
                    ),

                    // Detail Sisa Jatah & Saldo Uang Makan Santri
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: Row(
                        children: [
                          // Sisa Jatah Makan Hari Ini
                          if (remainingMeals != null)
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: const [
                                      Icon(Icons.restaurant, size: 11, color: Color(0xFF0D5C3A)),
                                      SizedBox(width: 4),
                                      Text(
                                        'Sisa Jatah Hari Ini',
                                        style: TextStyle(
                                          fontSize: 9.5,
                                          color: Color(0xFF64748B),
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    remainingMeals,
                                    style: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w800,
                                      color: Color(0xFF0F172A),
                                    ),
                                  ),
                                ],
                              ),
                            ),

                          if (remainingMeals != null && balanceFormatted != null)
                            Container(
                              width: 1,
                              height: 26,
                              color: const Color(0xFFE2E8F0),
                              margin: const EdgeInsets.symmetric(horizontal: 8),
                            ),

                          // Saldo Uang Makan Santri
                          if (balanceFormatted != null)
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: const [
                                      Icon(Icons.account_balance_wallet, size: 11, color: Color(0xFF059669)),
                                      SizedBox(width: 4),
                                      Text(
                                        'Saldo Santri',
                                        style: TextStyle(
                                          fontSize: 9.5,
                                          color: Color(0xFF64748B),
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    remainingBalanceFormatted != null
                                        ? '$remainingBalanceFormatted ($balanceFormatted)'
                                        : balanceFormatted,
                                    style: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w900,
                                      color: Color(0xFF059669),
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            }

            // Item histori riil dari backend (sebelumnya)
            final initial = name.isNotEmpty ? name[0].toUpperCase() : 'S';
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFF1F5F9)),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 16,
                    backgroundColor: const Color(0xFFDCFCE7),
                    child: Text(
                      initial,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF0D5C3A),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF0F172A),
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          className,
                          style: const TextStyle(fontSize: 10.5, color: Color(0xFF64748B)),
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFFECFDF5),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text(
                          '1 Porsi',
                          style: TextStyle(
                            fontSize: 9.5,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF15803D),
                          ),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        time,
                        style: const TextStyle(fontSize: 9.5, color: Color(0xFF94A3B8)),
                      ),
                    ],
                  ),
                ],
              ),
            );
          }),
      ],
    );
  }
}
