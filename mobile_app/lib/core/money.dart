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

/// Convierte un precio escrito por el usuario a céntimos (`null` si no es válido).
/// Acepta "1199", "1199.9", "1,199.90", "S/ 999,50" (coma decimal si le siguen 1–2 dígitos).
int? parseSolesToCents(String raw) {
  var text = raw.replaceAll(RegExp(r'S/\.?', caseSensitive: false), '').replaceAll(RegExp(r'\s'), '');
  if (text.isEmpty || !RegExp(r'^[\d.,]+$').hasMatch(text)) return null;
  final lastDot = text.lastIndexOf('.'), lastComma = text.lastIndexOf(',');
  String? decimalSep;
  if (lastDot >= 0 && lastComma >= 0) {
    decimalSep = lastDot > lastComma ? '.' : ',';
  } else if (lastDot >= 0 || lastComma >= 0) {
    final sep = lastDot >= 0 ? '.' : ',';
    final parts = text.split(sep);
    if (parts.length == 2 && parts.last.isNotEmpty && parts.last.length <= 2) decimalSep = sep;
  }
  if (decimalSep != null) {
    final thousands = decimalSep == '.' ? ',' : '.';
    text = text.replaceAll(thousands, '').replaceAll(decimalSep, '.');
  } else {
    text = text.replaceAll(RegExp(r'[.,]'), '');
  }
  final parts = text.split('.');
  final units = int.tryParse(parts[0].isEmpty ? '0' : parts[0]);
  if (units == null) return null;
  final decimals = parts.length > 1 ? int.parse(parts[1].padRight(2, '0').substring(0, 2)) : 0;
  final cents = units * 100 + decimals;
  return cents > 0 ? cents : null;
}
