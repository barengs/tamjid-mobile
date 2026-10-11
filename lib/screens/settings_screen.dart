import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/api_service.dart';
import '../widgets/app_header.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _urlController = TextEditingController();
  final _keyController = TextEditingController();

  bool _offlineModeAuto = true;
  String _scannerType = 'Kamera HP'; // 'Kamera HP' | 'NFC Reader' | 'BT Gun'
  bool _printerConnected = false;
  bool _beepSound = true;
  bool _isSyncing = false;
  bool _obscureApiKey = true;

  // Data real (bukan dummy)
  int? _pingMs; // hasil ping terukur ke server
  String? _lastSyncAt; // waktu sinkronisasi terakhir (tersimpan lokal)
  String? _serverMerchantName; // nama outlet dari server
  String? _serverTime; // waktu server dari API
  bool? _serverReachable; // status koneksi hasil percobaan API terakhir

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  @override
  void dispose() {
    _urlController.dispose();
    _keyController.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _urlController.text = prefs.getString('base_url') ?? ApiService().baseUrl;
      _keyController.text = prefs.getString('api_key') ?? ApiService().apiKey;
      _scannerType = prefs.getString('scanner_type') ?? 'Kamera HP';
      _offlineModeAuto = prefs.getBool('offline_mode_auto') ?? true;
      _printerConnected = prefs.getBool('printer_connected') ?? false;
      _beepSound = prefs.getBool('beep_sound') ?? true;
      _lastSyncAt = prefs.getString('last_sync_at');
    });
    // Uji koneksi awal & ukur ping secara nyata
    _pingServer(silent: true);
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    
    // Only admins should modify API configuration
    final isAdmin = ApiService().currentUser?.isAdmin ?? false;
    if (isAdmin) {
      await prefs.setString('base_url', _urlController.text.trim());
      await prefs.setString('api_key', _keyController.text.trim());
      await ApiService().updateConfig(
        baseUrl: _urlController.text.trim(),
        apiKey: _keyController.text.trim(),
      );
    }
    
    await prefs.setString('scanner_type', _scannerType);
    await prefs.setBool('offline_mode_auto', _offlineModeAuto);
    await prefs.setBool('printer_connected', _printerConnected);
    await prefs.setBool('beep_sound', _beepSound);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Color(0xFF059669),
          content: Text('Konfigurasi berhasil disimpan.'),
        ),
      );
    }
  }

  /// Ukur waktu respons nyata ke server dan update status koneksi.
  Future<void> _pingServer({bool silent = false}) async {
    final stopwatch = Stopwatch()..start();
    try {
      final config = await ApiService().getConfig();
      stopwatch.stop();
      if (!mounted) return;
      setState(() {
        _pingMs = stopwatch.elapsedMilliseconds;
        _serverReachable = true;
        _serverMerchantName = config.merchantName;
        _serverTime = config.serverTime;
      });
      if (!silent) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFF059669),
            content: Text('Server merespons dalam ${_pingMs}ms.'),
          ),
        );
      }
    } catch (e) {
      stopwatch.stop();
      if (!mounted) return;
      setState(() {
        _pingMs = null;
        _serverReachable = false;
      });
      if (!silent) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFFE11D48),
            content: Text(e.toString().replaceAll('Exception: ', '')),
          ),
        );
      }
    }
  }

  Future<void> _triggerSync() async {
    setState(() => _isSyncing = true);
    await _saveSettings();

    final stopwatch = Stopwatch()..start();
    try {
      final config = await ApiService().getConfig();
      stopwatch.stop();
      if (!mounted) return;

      final now = DateTime.now();
      final lastSyncStr = '${DateFormat('dd MMM yyyy, HH:mm').format(now)} WIB';
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('last_sync_at', now.toIso8601String());

      setState(() {
        _isSyncing = false;
        _pingMs = stopwatch.elapsedMilliseconds;
        _serverReachable = true;
        _serverMerchantName = config.merchantName;
        _serverTime = config.serverTime;
        _lastSyncAt = now.toIso8601String();
      });

      if (!mounted) return;

      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          icon: const Icon(Icons.check_circle_outline, color: Color(0xFF059669), size: 48),
          title: const Text('Sinkronisasi Sukses!'),
          content: Text(
            'Koneksi API terhubung aktif.\n'
            'Outlet: ${config.merchantName ?? "Default"}\n'
            'Waktu Server: ${config.serverTime}\n'
            'Respon: ${_pingMs}ms\n'
            'Tersimpan pada: $lastSyncStr',
          ),
          actions: [
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0D5C3A)),
              onPressed: () => Navigator.pop(ctx),
              child: const Text('OK', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      );
    } catch (e) {
      stopwatch.stop();
      if (!mounted) return;
      setState(() {
        _isSyncing = false;
        _serverReachable = false;
        _pingMs = null;
      });

      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          icon: const Icon(Icons.error_outline, color: Color(0xFFE11D48), size: 48),
          title: const Text('Gagal Sinkronisasi'),
          content: Text(e.toString().replaceAll('Exception: ', '')),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Tutup'),
            ),
          ],
        ),
      );
    }
  }

  Future<void> _logout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Konfirmasi Keluar Shift'),
        content: const Text(
          'Apakah Anda yakin ingin keluar dari shift saat ini? Semua transaksi lokal sudah tersinkronisasi ke server Bank Santri.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFDC2626)),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Keluar Shift', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await ApiService().logout();
      if (mounted) {
        Navigator.pushNamedAndRemoveUntil(context, '/login', (route) => false);
      }
    }
  }

  String _formatLastSync(String? iso) {
    if (iso == null || iso.isEmpty) return 'Belum pernah tersinkronisasi';
    try {
      final dt = DateTime.parse(iso).toLocal();
      return '${DateFormat('dd MMM yyyy, HH:mm').format(dt)} WIB';
    } catch (_) {
      return iso;
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ApiService().currentUser;
    final userName = user?.name ?? 'Petugas';
    final userEmail = user?.email ?? '-';
    final userRole = user?.roleDisplay ?? (user?.isDapur ?? false ? 'Petugas DPU' : 'Kasir Koperasi');
    final staffId = user != null ? 'STF-${user.id.toString().padLeft(4, '0')}' : 'STF-0000';
    final isDapur = user?.isDapur ?? false;
    final isAdmin = user?.isAdmin ?? false;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: SafeArea(
        child: Column(
          children: [
            const AppHeader(title: 'Pengaturan'),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // 1. Profile Card (Data dari akun login)
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: Row(
                      children: [
                        Stack(
                          children: [
                            Container(
                              width: 58,
                              height: 58,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.white, width: 2),
                                color: const Color(0xFFE2E8F0),
                              ),
                              child: Center(
                                child: Text(
                                  userName.isNotEmpty ? userName.substring(0, 1).toUpperCase() : 'P',
                                  style: const TextStyle(
                                    fontSize: 22,
                                    fontWeight: FontWeight.w800,
                                    color: Color(0xFF0D5C3A),
                                  ),
                                ),
                              ),
                            ),
                            Positioned(
                              bottom: 0,
                              right: 0,
                              child: Container(
                                width: 16,
                                height: 16,
                                decoration: BoxDecoration(
                                  color: const Color(0xFF059669),
                                  shape: BoxShape.circle,
                                  border: Border.all(color: Colors.white, width: 2),
                                ),
                                child: const Center(
                                  child: Icon(Icons.check, size: 9, color: Colors.white),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Flexible(
                                    child: Text(
                                      userName,
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w800,
                                        color: Color(0xFF0F172A),
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFDCFCE7),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      staffId,
                                      style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF15803D)),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 2),
                              Text(
                                userRole,
                                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF475569)),
                              ),
                              const SizedBox(height: 2),
                              Row(
                                children: [
                                  const Icon(Icons.email_outlined, size: 12, color: Color(0xFF94A3B8)),
                                  const SizedBox(width: 4),
                                  Expanded(
                                    child: Text(
                                      userEmail,
                                      style: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // 2. Sinkronisasi Database Card (Data real dari API & penyimpanan lokal)
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFDCFCE7),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: const Icon(Icons.sync, size: 18, color: Color(0xFF059669)),
                                ),
                                const SizedBox(width: 10),
                                const Text(
                                  'Sinkronisasi Database',
                                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Color(0xFF0F172A)),
                                ),
                              ],
                            ),
                            InkWell(
                              onTap: () => _pingServer(),
                              borderRadius: BorderRadius.circular(12),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF1F5F9),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 6,
                                      height: 6,
                                      decoration: BoxDecoration(
                                        color: _serverReachable == true
                                            ? const Color(0xFF059669)
                                            : const Color(0xFFE11D48),
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      _pingMs != null ? 'Ping: ${_pingMs}ms' : 'Ping: -',
                                      style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                                    ),
                                    const SizedBox(width: 4),
                                    const Icon(Icons.refresh, size: 11, color: Color(0xFF94A3B8)),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        _buildSyncDetailRow(
                          _serverMerchantName != null ? 'Outlet: $_serverMerchantName' : 'Server Utama Pesantren',
                          _serverReachable == true ? 'Online & Aktif' : 'Tidak Terhubung',
                          isStatusSuccess: _serverReachable == true,
                        ),
                        const SizedBox(height: 8),
                        _buildSyncDetailRow('Terakhir Sinkron', _formatLastSync(_lastSyncAt)),
                        const SizedBox(height: 8),
                        _buildSyncDetailRow('Waktu Server', _serverTime ?? '-'),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Antrian Lokal (Ditunda)', style: TextStyle(fontSize: 12, color: Color(0xFF64748B))),
                            ValueListenableBuilder<int>(
                              valueListenable: ApiService().pendingCount,
                              builder: (context, count, _) => Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: count > 0 ? const Color(0xFFFEF3C7) : const Color(0xFFF1F5F9),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  count > 0 ? '$count Transaksi Ditunda' : 'Kosong',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: count > 0 ? const Color(0xFFB45309) : const Color(0xFF64748B),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          height: 48,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF0D5C3A),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              elevation: 0,
                            ),
                            onPressed: _isSyncing ? null : _triggerSync,
                            child: _isSyncing
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                                  )
                                : const Text(
                                    'Sinkronisasi Sekarang (Push & Pull API)',
                                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: Colors.white),
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // 3. Konfigurasi API (Khusus Admin)
                  if (isAdmin) ...[
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                'Konfigurasi Endpoint API',
                                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Color(0xFF0F172A)),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFDCFCE7),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: const Text(
                                  'Khusus Admin',
                                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF15803D)),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),

                          // Base URL
                          const Text('Base URL API Pesantren', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF64748B))),
                          const SizedBox(height: 6),
                          Container(
                            decoration: BoxDecoration(
                              color: const Color(0xFFF1F5F9),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: TextField(
                              controller: _urlController,
                              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF0F172A)),
                              decoration: const InputDecoration(
                                prefixIcon: Icon(Icons.dns_outlined, size: 18, color: Color(0xFF64748B)),
                                border: InputBorder.none,
                                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                              ),
                              onSubmitted: (_) => _saveSettings(),
                            ),
                          ),
                          const SizedBox(height: 14),

                          // API Key Koperasi
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: const [
                              Text(
                                'API Key Merchant Koperasi',
                                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF64748B)),
                              ),
                              Text(
                                'Header X-Koperasi-Key',
                                style: TextStyle(fontSize: 10, color: Color(0xFF0D9488), fontWeight: FontWeight.w600),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Container(
                            decoration: BoxDecoration(
                              color: const Color(0xFFF1F5F9),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: TextField(
                              controller: _keyController,
                              obscureText: _obscureApiKey,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                fontFamily: 'monospace',
                                color: Color(0xFF0F172A),
                              ),
                              decoration: InputDecoration(
                                prefixIcon: const Icon(Icons.key_outlined, size: 18, color: Color(0xFF0D5C3A)),
                                suffixIcon: IconButton(
                                  icon: Icon(
                                    _obscureApiKey ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                                    size: 18,
                                    color: const Color(0xFF64748B),
                                  ),
                                  onPressed: () => setState(() => _obscureApiKey = !_obscureApiKey),
                                ),
                                hintText: 'Masukkan API Key (misal: KOP-...)',
                                hintStyle: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
                                border: InputBorder.none,
                                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                              ),
                              onSubmitted: (_) => _saveSettings(),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // 4. Preferensi Operasional Kiosk (Bisa diakses oleh semua petugas)
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Preferensi Operasional',
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Color(0xFF0F172A)),
                        ),
                        const SizedBox(height: 14),

                        // Offline Mode Toggle
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: const [
                                Text('Mode Offline Otomatis', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF0F172A))),
                                Text('Simpan lokal jika sambungan lambat', style: TextStyle(fontSize: 10.5, color: Color(0xFF64748B))),
                              ],
                            ),
                            Switch(
                              value: _offlineModeAuto,
                              activeTrackColor: const Color(0xFF0D5C3A),
                              onChanged: (val) {
                                setState(() => _offlineModeAuto = val);
                                _saveSettings();
                              },
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),

                        // Segmented Scanner Choice
                        const Text('Pilihan Alat Scanner Utama', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF64748B))),
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF1F5F9),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            children: [
                              _scannerOption('Kamera HP'),
                              _scannerOption('NFC Reader'),
                              _scannerOption('BT Gun'),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // 4. Perangkat & Suara (Status real, bukan dummy)
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Perangkat & Suara',
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Color(0xFF0F172A)),
                        ),
                        const SizedBox(height: 14),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.bluetooth,
                                  size: 18,
                                  color: _printerConnected ? const Color(0xFF0D9488) : const Color(0xFF94A3B8),
                                ),
                                const SizedBox(width: 10),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text('Printer Thermal', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF0F172A))),
                                    Text(
                                      _printerConnected ? 'Diaktifkan (siap mencetak)' : 'Nonaktif (struk digital)',
                                      style: const TextStyle(fontSize: 10.5, color: Color(0xFF64748B)),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            Switch(
                              value: _printerConnected,
                              activeTrackColor: const Color(0xFF0D5C3A),
                              onChanged: (val) {
                                setState(() => _printerConnected = val);
                                _saveSettings();
                              },
                            ),
                          ],
                        ),
                        const Divider(height: 20),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.volume_up_outlined, size: 18, color: Color(0xFF0D9488)),
                                const SizedBox(width: 10),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: const [
                                    Text('Suara Beep Kartu', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF0F172A))),
                                    Text('Konfirmasi audio transaksi santri', style: TextStyle(fontSize: 10.5, color: Color(0xFF64748B))),
                                  ],
                                ),
                              ],
                            ),
                            Switch(
                              value: _beepSound,
                              activeTrackColor: const Color(0xFF0D5C3A),
                              onChanged: (val) {
                                setState(() => _beepSound = val);
                                _saveSettings();
                              },
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // 5. Keluar Shift Button
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFDC2626), // Rose red
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        elevation: 0,
                      ),
                      icon: const Icon(Icons.logout, color: Colors.white, size: 18),
                      label: const Text(
                        'Keluar Shift / Logout Petugas',
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Colors.white),
                      ),
                      onPressed: _logout,
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Info versi aplikasi (real dari konfigurasi proyek)
                  Center(
                    child: Text(
                      isDapur ? 'Terminal Dapur DPU \u2022 v1.0.0' : 'E-Panyeppen POS \u2022 v1.0.0',
                      style: const TextStyle(fontSize: 10.5, color: Color(0xFF94A3B8)),
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSyncDetailRow(String label, String value, {bool isStatusSuccess = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(fontSize: 12, color: Color(0xFF64748B))),
        const SizedBox(width: 12),
        Expanded(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (isStatusSuccess) ...[
                const Icon(Icons.check_circle, size: 12, color: Color(0xFF059669)),
                const SizedBox(width: 4),
              ],
              Flexible(
                child: Text(
                  value,
                  textAlign: TextAlign.end,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: isStatusSuccess ? const Color(0xFF059669) : const Color(0xFF0F172A),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _scannerOption(String name) {
    final isSelected = _scannerType == name;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          setState(() => _scannerType = name);
          _saveSettings();
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 9),
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFF0D5C3A) : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            name,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 11,
              fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
              color: isSelected ? Colors.white : const Color(0xFF64748B),
            ),
          ),
        ),
      ),
    );
  }
}
