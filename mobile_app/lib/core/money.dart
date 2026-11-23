/// Formato de montos. Los precios se guardan en céntimos (enteros) y nunca en double.
///
/// `formatCents(124990)` -> `"S/ 1,249.90"`
String formatCents(int cents, {String currency = 'PEN'}) {
  final symbol = currency == 'PEN' ? 'S/' : currency;
  final negative = cents < 0;
  final abs = cents.abs();
  final units = (abs ~/ 100).toString();
  final decimals = (abs % 100).toString().padLeft(2, '0');

  final grouped = StringBuffer();
  for (var i = 0; i < units.length; i++) {
    if (i > 0 && (units.length - i) % 3 == 0) grouped.write(',');
    grouped.write(units[i]);
  }
  return '${negative ? '-' : ''}$symbol $grouped.$decimals';
}

/// Variación porcentual entre dos precios (por ejemplo, -7.7 si bajó).
double percentChange(int fromCents, int toCents) {
  if (fromCents == 0) return 0;
  return (toCents - fromCents) * 100 / fromCents;
}
