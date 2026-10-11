
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

  factory StudentProfile.fromJson(Map<String, dynamic> json) {
    return StudentProfile(
      nis: json['nis']?.toString(),
      name: json['name']?.toString() ?? json['first_name']?.toString(),
      photoUrl: json['photo']?.toString() ?? json['photo_url']?.toString(),
      className: json['class']?['name']?.toString() ?? json['class_name']?.toString(),
      hostel: json['hostel']?['name']?.toString() ?? json['hostel_name']?.toString(),
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
      suggestedPrice: (json['suggested_price'] ?? 0).toDouble(),
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
  final StudentProfile? student;
  final KitchenStatus? kitchenStatus;

  StudentAccount({
    required this.accountNumber,
    this.cardNumber,
    required this.customerName,
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
    return StudentAccount(
      accountNumber: json['account_number']?.toString() ?? '',
      cardNumber: json['card_number']?.toString(),
      customerName: json['customer_name']?.toString() ?? 'Santri',
      balance: (json['balance'] ?? 0).toDouble(),
      balanceFormatted: json['balance_formatted']?.toString() ?? 'Rp 0',
      minimumBalance: (json['minimum_balance'] ?? 0).toDouble(),
      withdrawableBalance: (json['withdrawable_balance'] ?? 0).toDouble(),
      dailyLimit: (json['daily_limit'] ?? 0).toDouble(),
      spentToday: (json['spent_today'] ?? 0).toDouble(),
      remainingDailyLimit: json['remaining_daily_limit'] != null
          ? (json['remaining_daily_limit']).toDouble()
          : null,
      student: json['student'] != null
          ? StudentProfile.fromJson(json['student'])
          : null,
      kitchenStatus: json['kitchen_status'] != null
          ? KitchenStatus.fromJson(json['kitchen_status'])
          : null,
    );
  }
}
