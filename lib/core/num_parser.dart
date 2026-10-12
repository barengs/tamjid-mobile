/// Utilitas parsing numerik untuk data JSON dari API bank-santri.
///
/// Karena field `decimal` di Laravel (`Transaction.amount`, `Account.balance`,
/// `Product.minimum_balance`) memakai cast `decimal:2` yang menghasilkan String
/// saat di-serialize (contoh: "10000.00"), memanggil `.toDouble()` / `.toInt()`
/// langsung pada value `dynamic` dari JSON di Dart akan melempar
/// `NoSuchMethodError` jika value ternyata `String`.
///
/// Gunakan [toD] dan [toI] di seluruh file layar/model untuk menghindari
/// crash tersebut.
library;

/// Konversi value JSON (num | String | null | lainnya) ke [double] dengan aman.
///
/// Contoh:
/// ```dart
/// final balance = toD(json['balance']);
/// final amount  = toD(json['amount'], fallback: 0.0);
/// ```
double toD(dynamic value, {double fallback = 0.0}) {
  if (value == null) return fallback;
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value) ?? fallback;
  return fallback;
}

/// Konversi value JSON (num | String | null | lainnya) ke [int] dengan aman.
///
/// Contoh:
/// ```dart
/// final count = toI(json['today_count']);
/// final price = toI(json['price'], fallback: 0);
/// ```
int toI(dynamic value, {int fallback = 0}) {
  if (value == null) return fallback;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value) ?? double.tryParse(value)?.toInt() ?? fallback;
  return fallback;
}
