import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Lista corta de valores recientes (lo último primero, sin repetidos).
class RecentList extends Notifier<List<String>> {
  RecentList(this.max);

  final int max;

  @override
  List<String> build() => const [];

  void add(String value) {
    final v = value.trim();
    if (v.isEmpty) return;
    state = [v, ...state.where((x) => x.toLowerCase() != v.toLowerCase())].take(max).toList();
  }

  void clear() => state = const [];
}

/// Productos que el usuario abrió en esta sesión (para «Vistos recientemente»).
/// Vive en memoria: no gasta lecturas ni escrituras de Firestore.
final recentProductsProvider = NotifierProvider<RecentList, List<String>>(() => RecentList(10));

/// Búsquedas que llevaron a abrir un producto.
final recentQueriesProvider = NotifierProvider<RecentList, List<String>>(() => RecentList(6));

/// Sugerencias fijas cuando el buscador está vacío.
const popularSearches = ['Monitor 144 Hz', 'Refrigeradora', 'Audífonos bluetooth', 'Laptop i5', 'SSD 1 TB'];
