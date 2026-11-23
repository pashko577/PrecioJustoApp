/// Normalización de búsqueda. DEBE coincidir con `scraping-engine/app/normalizers/text.py`:
/// el motor guarda `searchTokens` con esa versión y la app busca con esta.
/// Ambas se prueban con `shared/test_vectors/search_normalization.json`.
library;

const stopwords = {'de', 'del', 'la', 'el', 'los', 'las', 'y', 'con', 'para', 'en'};
const minWordLength = 2;

final _unitRe = RegExp(r'(\d+(?:[.,]\d+)?)\s*(tb|gb|mb|ghz|mhz|hz|w)\b', caseSensitive: false);
final _invalidChars = RegExp(r'[^a-z0-9.+\- ]');
final _spaces = RegExp(r'\s+');

const _accents = {
  'à': 'a', 'á': 'a', 'â': 'a', 'ã': 'a', 'ä': 'a', 'å': 'a',
  'è': 'e', 'é': 'e', 'ê': 'e', 'ë': 'e',
  'ì': 'i', 'í': 'i', 'î': 'i', 'ï': 'i',
  'ò': 'o', 'ó': 'o', 'ô': 'o', 'õ': 'o', 'ö': 'o',
  'ù': 'u', 'ú': 'u', 'û': 'u', 'ü': 'u',
  'ý': 'y', 'ÿ': 'y', 'ñ': 'n', 'ç': 'c',
};

String _stripAccents(String text) {
  final buffer = StringBuffer();
  for (final rune in text.runes) {
    final char = String.fromCharCode(rune);
    buffer.write(_accents[char] ?? char);
  }
  return buffer.toString();
}

String _trimTrailing(String text, String char) {
  var end = text.length;
  while (end > 0 && text[end - 1] == char) {
    end--;
  }
  return text.substring(0, end);
}

String _normalizeUnits(String text) => text.replaceAllMapped(_unitRe, (m) {
      var number = m.group(1)!.replaceAll(',', '.');
      final unit = m.group(2)!.toLowerCase();
      if (unit == 'gb' && !number.contains('.')) {
        final value = int.parse(number);
        if (value >= 1000 && value % 1000 == 0) return '${value ~/ 1000}tb';
      }
      if (number.contains('.')) number = _trimTrailing(_trimTrailing(number, '0'), '.');
      return '$number$unit';
    });

/// Minúsculas, sin tildes, unidades unificadas ("1000 GB" -> "1tb") y espacios simples.
String normalizeText(String? text) {
  var result = _stripAccents((text ?? '').toLowerCase());
  result = _normalizeUnits(result);
  result = result.replaceAll(_invalidChars, ' ');
  return result.replaceAll(_spaces, ' ').trim();
}

/// Palabras normalizadas, únicas y ordenadas (equivale a `word_tokens` en Python).
List<String> wordTokens(String? text) {
  final tokens = <String>{};
  for (var token in normalizeText(text).split(' ')) {
    token = _stripEdges(token);
    if (token.length >= minWordLength && !stopwords.contains(token)) tokens.add(token);
  }
  return tokens.toList()..sort();
}

String _stripEdges(String token) {
  var start = 0, end = token.length;
  while (start < end && (token[start] == '.' || token[start] == '-')) {
    start++;
  }
  while (end > start && (token[end - 1] == '.' || token[end - 1] == '-')) {
    end--;
  }
  return token.substring(start, end);
}

/// Valida el dígito verificador GTIN (módulo 10, pesos 3 y 1 desde la derecha).
bool gtinCheckDigitOk(String code) {
  final digits = code.split('').map(int.parse).toList();
  final check = digits.removeLast();
  var total = 0;
  for (var i = 0; i < digits.length; i++) {
    total += digits[digits.length - 1 - i] * (i.isEven ? 3 : 1);
  }
  return (10 - total % 10) % 10 == check;
}

/// Forma canónica de un código de barras, igual que `canonical_gtin` en Python
/// (`scraping-engine/app/normalizers/identifiers.py`): UPC de 12 dígitos y EAN de 13 del
/// mismo producto dan el mismo resultado. Devuelve `null` si el código no es válido.
String? canonicalGtin(String raw) {
  final code = raw.replaceAll(RegExp(r'[\s-]'), '');
  if (!RegExp(r'^\d+$').hasMatch(code) || ![8, 12, 13, 14].contains(code.length)) return null;
  if (!gtinCheckDigitOk(code)) return null;
  if (code.length == 14) return code.startsWith('0') ? code.substring(1) : code;
  return code.padLeft(13, '0');
}

/// Consulta interpretada: palabras o código de barras (EAN/GTIN/UPC de 8 a 14 dígitos).
class SearchQuery {
  const SearchQuery({this.words = const [], this.barcode});

  final List<String> words;
  final String? barcode;

  bool get isEmpty => words.isEmpty && barcode == null;

  /// Palabra que se envía a Firestore (`array-contains`): la más larga es la más selectiva.
  String? get keyWord {
    if (words.isEmpty) return null;
    return words.reduce((a, b) => b.length > a.length ? b : a);
  }

  factory SearchQuery.parse(String raw) {
    final compact = raw.replaceAll(RegExp(r'[\s-]'), '');
    if (RegExp(r'^\d{8,14}$').hasMatch(compact)) {
      // Código con forma de GTIN: se busca en forma canónica. Si el dígito verificador no
      // cuadra, igual se trata como código (sin resultados) en vez de buscarlo como palabra.
      return SearchQuery(barcode: canonicalGtin(compact) ?? compact);
    }
    return SearchQuery(words: wordTokens(raw));
  }

  /// Todas las palabras deben estar en el producto. Se acepta prefijo para la última
  /// palabra que se está escribiendo (por ejemplo, "kingston nv").
  bool matches(List<String> productTokens) =>
      words.every((w) => productTokens.contains(w) || productTokens.any((t) => t.startsWith(w)));
}
