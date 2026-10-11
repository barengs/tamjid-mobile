
class MealSession {
  final String id;
  final String name;
  final String startTime;
  final String endTime;
  final double price;
  final bool isActive;

  MealSession({
    required this.id,
    required this.name,
    required this.startTime,
    required this.endTime,
    required this.price,
    required this.isActive,
  });

  factory MealSession.fromJson(Map<String, dynamic> json) {
    return MealSession(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      startTime: json['start_time']?.toString() ?? '',
      endTime: json['end_time']?.toString() ?? '',
      price: (json['price'] ?? 0).toDouble(),
      isActive: json['is_active'] ?? true,
    );
  }
}

class KoperasiConfig {
  final String? merchantName;
  final String serverTime;
  final String serverHour;
  final bool preventDoubleTap;
  final MealSession? activeSession;
  final bool isSessionOpen;
  final List<MealSession> sessions;

  KoperasiConfig({
    this.merchantName,
    required this.serverTime,
    required this.serverHour,
    required this.preventDoubleTap,
    this.activeSession,
    required this.isSessionOpen,
    required this.sessions,
  });

  factory KoperasiConfig.fromJson(Map<String, dynamic> json) {
    final dapurRules = json['dapur_rules'] as Map<String, dynamic>? ?? {};
    final sessionsList = (dapurRules['sessions'] as List<dynamic>? ?? [])
        .map((s) => MealSession.fromJson(s as Map<String, dynamic>))
        .toList();

    return KoperasiConfig(
      merchantName: json['merchant']?['name']?.toString(),
      serverTime: json['server_time']?.toString() ?? '',
      serverHour: json['server_hour']?.toString() ?? '',
      preventDoubleTap: dapurRules['prevent_double_tap'] ?? true,
      activeSession: dapurRules['active_session'] != null
          ? MealSession.fromJson(dapurRules['active_session'])
          : null,
      isSessionOpen: dapurRules['is_session_open'] ?? false,
      sessions: sessionsList,
    );
  }
}
