
import '../core/api_service.dart';
import '../core/num_parser.dart';

class StudentProfile {
  final String? nis;
  final String? name;
  final String? photoUrl;
  final String? className;
  final String? hostel;

  StudentProfile({
    this.nis,
    this.name,
    this.photoUrl,
    this.className,
    this.hostel,
  });

  factory StudentProfile.fromJson(Map<String, dynamic> json, {String? fallbackPhotoUrl, String? defaultNis}) {
    String? photo = json['photo_url']?.toString() ?? json['photo']?.toString() ?? fallbackPhotoUrl;
    final nis = json['nis']?.toString() ?? defaultNis;

    // Jika path berupa path relatif (misal: 'students/photos/...'), arahkan ke endpoint foto bank santri
    if (photo != null && photo.isNotEmpty && !photo.startsWith('http')) {
      final base = ApiService().baseUrl;
      photo = '$base/api/koperasi/student-photo/${nis ?? ''}';
    }

    final currentClass = json['current_class'] is Map<String, dynamic> ? json['current_class'] : null;
    final hostelObj = json['hostel'] is Map<String, dynamic> ? json['hostel'] : null;

    return StudentProfile(
      nis: nis,
      name: json['name']?.toString() ?? json['first_name']?.toString(),
      photoUrl: photo,
      className: currentClass?['class_name']?.toString() ??
          json['class']?['name']?.toString() ??
          json['class_name']?.toString(),
      hostel: hostelObj?['name']?.toString() ?? json['hostel_name']?.toString(),
    );
  }
}

class KitchenStatus {
  final Map<String, dynamic>? activeSession;
  final bool isSessionOpen;
  final bool alreadyTapped;
  final String? lastTapTime;
  final double suggestedPrice;
  final bool canClaim;

  KitchenStatus({
    this.activeSession,
    required this.isSessionOpen,
    required this.alreadyTapped,
    this.lastTapTime,
    required this.suggestedPrice,
    required this.canClaim,
  });

  factory KitchenStatus.fromJson(Map<String, dynamic> json) {
    return KitchenStatus(
      activeSession: json['active_session'] as Map<String, dynamic>?,
      isSessionOpen: json['is_session_open'] ?? false,
      alreadyTapped: json['already_tapped'] ?? false,
      lastTapTime: json['last_tap_time']?.toString(),
      suggestedPrice: toD(json['suggested_price']),
      canClaim: json['can_claim'] ?? false,
    );
  }
}

class StudentAccount {
  final String accountNumber;
  final String? cardNumber;
  final String customerName;
  final double balance;
  final String balanceFormatted;
  final double minimumBalance;
  final double withdrawableBalance;
  final double dailyLimit;
  final double spentToday;
  final double? remainingDailyLimit;
  final String? photoUrl;
  final StudentProfile? student;
  final KitchenStatus? kitchenStatus;

  StudentAccount({
    required this.accountNumber,
    this.cardNumber,
    required this.customerName,
    this.photoUrl,
    required this.balance,
    required this.balanceFormatted,
    required this.minimumBalance,
    required this.withdrawableBalance,
    required this.dailyLimit,
    required this.spentToday,
    this.remainingDailyLimit,
    this.student,
    this.kitchenStatus,
  });

  factory StudentAccount.fromJson(Map<String, dynamic> json) {
    final accNo = json['account_number']?.toString() ?? '';
    final rootPhoto = json['photo_url']?.toString();

    StudentProfile? studentProfile;
    if (json['student'] != null && json['student'] is Map<String, dynamic>) {
      studentProfile = StudentProfile.fromJson(
        json['student'] as Map<String, dynamic>,
        fallbackPhotoUrl: rootPhoto,
        defaultNis: accNo,
      );
    }

    String? finalPhoto = studentProfile?.photoUrl ?? rootPhoto;
    if ((finalPhoto == null || finalPhoto.isEmpty) && accNo.isNotEmpty) {
      finalPhoto = '${ApiService().baseUrl}/api/koperasi/student-photo/$accNo';
    }

    return StudentAccount(
      accountNumber: accNo,
      cardNumber: json['card_number']?.toString(),
      customerName: json['customer_name']?.toString() ?? 'Santri',
      photoUrl: finalPhoto,
      balance: toD(json['balance']),
      balanceFormatted: json['balance_formatted']?.toString() ?? 'Rp 0',
      minimumBalance: toD(json['minimum_balance']),
      withdrawableBalance: toD(json['withdrawable_balance']),
      dailyLimit: toD(json['daily_limit']),
      spentToday: toD(json['spent_today']),
      remainingDailyLimit: json['remaining_daily_limit'] != null
          ? toD(json['remaining_daily_limit'])
          : null,
      student: studentProfile,
      kitchenStatus: json['kitchen_status'] != null
          ? KitchenStatus.fromJson(json['kitchen_status'])
          : null,
    );
  }
}
