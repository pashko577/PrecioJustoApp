import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:compramejor/core/search_normalizer.dart';

void main() {
  // `flutter test` se ejecuta desde mobile_app/; el archivo compartido está en la raíz del repo.
  final vectors = (jsonDecode(File('../shared/test_vectors/search_normalization.json').readAsStringSync())
      as Map<String, dynamic>)['cases'] as List<dynamic>;

  group('Paridad con Python (shared/test_vectors)', () {
    for (final raw in vectors) {
      final c = raw as Map<String, dynamic>;
      final input = c['input'] as String;
      test(input.isEmpty ? '<vacío>' : input, () {
        expect(normalizeText(input), c['normalized']);
        expect(wordTokens(input), List<String>.from(c['words'] as List));
      });
    }
  });

  group('SearchQuery', () {
    test('palabras y palabra clave más larga', () {
      final q = SearchQuery.parse('Kingston NV3 1000 GB');
      expect(q.words, ['1tb', 'kingston', 'nv3']);
      expect(q.keyWord, 'kingston');
      expect(q.barcode, isNull);
    });

    test('detecta códigos de barras de 8 a 14 dígitos', () {
      expect(SearchQuery.parse('2001234567893').barcode, '2001234567893');
      expect(SearchQuery.parse('2001 2345-67893').barcode, '2001234567893');
      expect(SearchQuery.parse('1234567').barcode, isNull); // 7 dígitos: no es código
      expect(SearchQuery.parse('4060').barcode, isNull);
    });

    test('código de barras canónico igual que en Python', () {
      expect(canonicalGtin('740617338515'), '0740617338515'); // UPC-A -> EAN-13
      expect(canonicalGtin('0740617338515'), '0740617338515');
      expect(canonicalGtin('00740617338515'), '0740617338515'); // GTIN-14
      expect(canonicalGtin('96385074'), '0000096385074'); // EAN-8
      expect(canonicalGtin('0740617340456'), isNull); // dígito verificador incorrecto
      expect(SearchQuery.parse('740617338515').barcode, '0740617338515');
    });

    test('consulta vacía o solo palabras vacías', () {
      expect(SearchQuery.parse('').isEmpty, isTrue);
      expect(SearchQuery.parse('  de la  ').isEmpty, isTrue);
      expect(SearchQuery.parse('a').isEmpty, isTrue);
    });

    test('todas las palabras deben coincidir; acepta prefijos', () {
      const tokens = ['1tb', 'kin', 'king', 'kingston', 'nv3', 'ssd'];
      expect(SearchQuery.parse('kingston 1tb').matches(tokens), isTrue);
      expect(SearchQuery.parse('kingston nv').matches(tokens), isTrue); // escribiendo "nv3"
      expect(SearchQuery.parse('kingston 2tb').matches(tokens), isFalse); // otra capacidad
      expect(SearchQuery.parse('samsung').matches(tokens), isFalse);
    });
  });
}
