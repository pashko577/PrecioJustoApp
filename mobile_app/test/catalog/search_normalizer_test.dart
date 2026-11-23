import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:precio_justo/core/search_normalizer.dart';

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
      expect(SearchQuery.parse('0740617340456').barcode, '0740617340456');
      expect(SearchQuery.parse('0740 6173-40456').barcode, '0740617340456');
      expect(SearchQuery.parse('1234567').barcode, isNull); // 7 dígitos: no es código
      expect(SearchQuery.parse('4060').barcode, isNull);
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
