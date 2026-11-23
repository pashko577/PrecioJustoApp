import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Lista corta de valores recientes (lo último primero, sin repetidos), guardada en el
/// celular. No usa Firestore: no gasta lecturas ni escrituras y no sale del dispositivo.
class RecentList extends Notifier<List<String>> {
  RecentList(this.storageKey, this.max);

  final String storageKey;
  final int max;

  @override
  List<String> build() {
    _load();
    return const [];
  }

  Future<void> _load() async {
    try {
      final saved = (await SharedPreferences.getInstance()).getStringList(storageKey) ?? const [];
      // Lo agregado mientras se cargaba va primero.
      state = _merge(state, saved);
    } catch (_) {
      // Sin almacenamiento disponible (pruebas, plataforma sin soporte): solo en memoria.
    }
  }

  List<String> _merge(List<String> first, List<String> rest) {
    final seen = <String>{};
    return [
      for (final v in [...first, ...rest])
        if (seen.add(v.toLowerCase())) v,
    ].take(max).toList();
  }

  void add(String value) {
    final v = value.trim();
    if (v.isEmpty) return;
    state = _merge([v], state);
    _save();
  }

  void clear() {
    state = const [];
    _save();
  }

  Future<void> _save() async {
    try {
      await (await SharedPreferences.getInstance()).setStringList(storageKey, state);
    } catch (_) {}
  }
}

/// Productos que el usuario abrió (para «Vistos recientemente»).
final recentProductsProvider = NotifierProvider<RecentList, List<String>>(() => RecentList('recent.products', 10));

/// Búsquedas que el usuario hizo.
final recentQueriesProvider = NotifierProvider<RecentList, List<String>>(() => RecentList('recent.queries', 6));

/// Sugerencias fijas cuando el buscador está vacío.
const popularSearches = ['Monitor 144 Hz', 'Refrigeradora', 'Audífonos bluetooth', 'Laptop i5', 'SSD 1 TB'];
