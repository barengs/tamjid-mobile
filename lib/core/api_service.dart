import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/student_account.dart';
import '../models/koperasi_config.dart';
import '../models/user.dart';

class ApiService {
  static final ApiService _instance = ApiService._internal();
  factory ApiService() => _instance;
  ApiService._internal();

  static const String defaultBaseUrl = 'https://bank.tamjid.or.id';
  static const String defaultApiKey = 'koperasi-secret-2026';

  Dio _dio = Dio();
  String _baseUrl = defaultBaseUrl;
  String _apiKey = defaultApiKey;
  String? _token;
  User? _currentUser;

  /// Counter antrian transaksi yang sedang ditunda di Kasir POS (live & real)
  final ValueNotifier<int> pendingCount = ValueNotifier<int>(0);

  String get baseUrl => _baseUrl;
  String get apiKey => _apiKey;
  String? get token => _token;
  User? get currentUser => _currentUser;
  bool get isLoggedIn =>
      _currentUser != null && _token != null && _token!.isNotEmpty;

  static String normalizeBaseUrl(String url) {
    var trimmed = url.trim();
    while (trimmed.endsWith('/')) {
      trimmed = trimmed.substring(0, trimmed.length - 1);
    }
    if (trimmed.endsWith('/api')) {
      trimmed = trimmed.substring(0, trimmed.length - 4);
    }
    while (trimmed.endsWith('/')) {
      trimmed = trimmed.substring(0, trimmed.length - 1);
    }
    return trimmed.isEmpty ? defaultBaseUrl : trimmed;
  }

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final savedUrl = prefs.getString('base_url');
    if (savedUrl == null ||
        savedUrl.contains('127.0.0.1') ||
        savedUrl.contains('localhost') ||
        savedUrl.contains('10.0.2.2')) {
      _baseUrl = defaultBaseUrl;
      await prefs.setString('base_url', defaultBaseUrl);
    } else {
      _baseUrl = normalizeBaseUrl(savedUrl);
    }
    final savedKey = prefs.getString('api_key');
    _apiKey = (savedKey != null && savedKey.trim().isNotEmpty)
        ? savedKey.trim()
        : defaultApiKey;
    _token = prefs.getString('auth_token');

    final userJson = prefs.getString('auth_user');
    if (userJson != null) {
      try {
        _currentUser = User.fromJson(jsonDecode(userJson));
      } catch (_) {
        _currentUser = null;
      }
    }
    _setupDio();
  }

  Future<void> updateConfig({
    required String baseUrl,
    required String apiKey,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    _baseUrl = normalizeBaseUrl(baseUrl);
    _apiKey = apiKey.trim().isEmpty ? defaultApiKey : apiKey.trim();
    await prefs.setString('base_url', _baseUrl);
    await prefs.setString('api_key', _apiKey);
    _setupDio();
  }

  void _setupDio() {
    _dio = Dio(
      BaseOptions(
        baseUrl: _baseUrl,
        connectTimeout: const Duration(seconds: 30),
        receiveTimeout: const Duration(seconds: 30),
        headers: {
          'Accept': 'application/json',
          'Content-Type': 'application/json',
          if (_apiKey.isNotEmpty) 'X-Koperasi-Key': _apiKey,
          if (_token != null && _token!.isNotEmpty)
            'Authorization': 'Bearer $_token',
        },
      ),
    );
  }

  Future<User> login({required String email, required String password}) async {
    try {
      final res = await _dio.post(
        '/api/auth/login',
        data: {'email': email.trim(), 'password': password},
      );

      if (res.data['status'] == 'success') {
        _token = res.data['access_token']?.toString();
        final userRaw = res.data['user'];
        if (userRaw is! Map<String, dynamic>) {
          throw Exception('Data profil user tidak ditemukan dari server.');
        }
        _currentUser = User.fromJson(userRaw);

        final prefs = await SharedPreferences.getInstance();
        if (_token != null) await prefs.setString('auth_token', _token!);
        await prefs.setString('auth_user', jsonEncode(_currentUser!.toJson()));

        _setupDio();
        return _currentUser!;
      }
      throw Exception(res.data['message'] ?? 'Login gagal.');
    } on DioException catch (e) {
      throw _parseDioError(e);
    }
  }

  Future<void> logout() async {
    try {
      if (_token != null) {
        await _dio.post('/api/auth/logout');
      }
    } catch (_) {}

    _token = null;
    _currentUser = null;

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('auth_token');
    await prefs.remove('auth_user');

    _setupDio();
  }

  Future<KoperasiConfig> getConfig() async {
    try {
      final res = await _dio.get('/api/koperasi/config');
      if (res.data['status'] == 'success') {
        return KoperasiConfig.fromJson(res.data['data']);
      }
      throw Exception(res.data['message'] ?? 'Gagal mengambil konfigurasi.');
    } on DioException catch (e) {
      throw _parseDioError(e);
    }
  }

  Future<StudentAccount> checkAccount(
    String identifier, {
    String outletType = 'koperasi',
  }) async {
    try {
      final res = await _dio.get(
        '/api/koperasi/check/$identifier',
        queryParameters: {'outlet_type': outletType},
      );
      if (res.data['status'] == 'success') {
        return StudentAccount.fromJson(res.data['data']);
      }
      throw Exception(res.data['message'] ?? 'Santri tidak ditemukan.');
    } on DioException catch (e) {
      throw _parseDioError(e);
    }
  }

  Future<Map<String, dynamic>> debit({
    required String identifier,
    required double amount,
    String outletType = 'koperasi',
    String? mealSession,
    String? description,
    String? note,
  }) async {
    try {
      final res = await _dio.post(
        '/api/koperasi/debit',
        data: {
          'identifier': identifier,
          'amount': amount,
          'outlet_type': outletType,
          'cashier_name': _currentUser?.name,
          'user_id': _currentUser?.id,
          'meal_session': ?mealSession,
          'item_description': ?description,
          'cashier_note': ?note,
        },
      );

      if (res.data['status'] == 'success') {
        return res.data['data'] as Map<String, dynamic>;
      }
      throw Exception(res.data['message'] ?? 'Gagal memproses transaksi.');
    } on DioException catch (e) {
      throw _parseDioError(e);
    }
  }

  Future<Map<String, dynamic>> getTransactions({
    String? outletType,
    String? date,
    int page = 1,
  }) async {
    try {
      final res = await _dio.get(
        '/api/koperasi/transactions',
        queryParameters: {
          'outlet_type': ?outletType,
          'date': ?date,
          'page': page,
          'per_page': 20,
        },
      );
      return res.data;
    } on DioException catch (e) {
      throw _parseDioError(e);
    }
  }

  Future<Map<String, dynamic>> cashWithdrawal({
    required String accountNumber,
    required double amount,
    String? description,
  }) async {
    try {
      final res = await _dio.post(
        '/api/main/transaction/cash-withdrawal',
        data: {
          'account_number': accountNumber,
          'amount': amount,
          'description': description ?? 'Tarik Tunai Mobile Teller',
        },
      );

      if (res.data['status'] == 'success') {
        return res.data['data'] as Map<String, dynamic>;
      }
      throw Exception(res.data['message'] ?? 'Penarikan tunai gagal diproses.');
    } on DioException catch (e) {
      throw _parseDioError(e);
    }
  }

  Future<Map<String, dynamic>> getDashboard() async {
    try {
      final res = await _dio.get('/api/koperasi/dashboard');
      if (res.data['status'] == 'success') {
        return res.data['data'] as Map<String, dynamic>;
      }
      throw Exception(res.data['message'] ?? 'Gagal mengambil data dashboard.');
    } on DioException catch (e) {
      throw _parseDioError(e);
    }
  }

  String _parseDioError(DioException e) {
    if (e.response != null && e.response?.data != null) {
      final data = e.response?.data;
      if (data is Map && data.containsKey('message')) {
        return data['message'].toString();
      }
    }
    if (e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.receiveTimeout) {
      return 'Koneksi ke server Bank Santri timeout. Periksa jaringan Anda.';
    }
    if (e.type == DioExceptionType.connectionError) {
      return 'Tidak dapat terhubung ke server Bank Santri pada $_baseUrl.';
    }
    return e.message ?? 'Terjadi kesalahan sistem.';
  }
}
