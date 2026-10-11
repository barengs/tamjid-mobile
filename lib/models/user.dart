class User {
  final int id;
  final String name;
  final String email;
  final String? role;
  final List<String> roles;

  User({
    required this.id,
    required this.name,
    required this.email,
    this.role,
    this.roles = const [],
  });

  bool get isDapur {
    final r = (role ?? '').toLowerCase();
    if (r.contains('dpu') || r.contains('dapur')) return true;
    return roles.any((x) => x.toLowerCase().contains('dpu') || x.toLowerCase().contains('dapur'));
  }

  bool get isTeller {
    final r = (role ?? '').toLowerCase();
    if (r.contains('teller') || r.contains('bank')) return true;
    return roles.any((x) => x.toLowerCase().contains('teller') || x.toLowerCase().contains('bank'));
  }

  bool get isKoperasi => !isDapur && !isTeller;

  bool get isAdmin {
    final r = (role ?? '').toLowerCase();
    if (r.contains('admin') || r.contains('super')) return true;
    return roles.any((x) => x.toLowerCase().contains('admin') || x.toLowerCase().contains('super'));
  }

  String get roleDisplay {
    if (isTeller) return 'Staff Teller Bank Santri';
    if (isDapur) return 'Petugas Dapur Umum (DPU)';
    return 'Kasir Koperasi Santri';
  }

  factory User.fromJson(Map<String, dynamic> json) {
    final rolesList = (json['roles'] as List<dynamic>?)
            ?.map((e) => e.toString())
            .toList() ??
        [];
    return User(
      id: json['id'] is int ? json['id'] : int.tryParse(json['id'].toString()) ?? 0,
      name: json['name']?.toString() ?? '',
      email: json['email']?.toString() ?? '',
      role: json['role']?.toString(),
      roles: rolesList,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'email': email,
    'role': role,
    'roles': roles,
  };
}
