import 'package:compramejor/features/catalog/recent.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> settle() => Future<void>.delayed(Duration.zero);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('lo último va primero, sin repetidos y con tope', () async {
    SharedPreferences.setMockInitialValues({});
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final n = c.read(recentQueriesProvider.notifier);
    for (final q in ['teros', 'kingston', 'Teros', 'a', 'b', 'c', 'd', 'e']) {
      n.add(q);
    }
    expect(c.read(recentQueriesProvider), ['e', 'd', 'c', 'b', 'a', 'Teros']);
  });

  test('se conserva al cerrar y abrir la app', () async {
    SharedPreferences.setMockInitialValues({});
    final first = ProviderContainer();
    first.read(recentProductsProvider.notifier)
      ..add('p1')
      ..add('p2');
    await settle();
    first.dispose();

    final second = ProviderContainer(); // «nueva sesión»
    addTearDown(second.dispose);
    second.read(recentProductsProvider);
    await settle();
    expect(second.read(recentProductsProvider), ['p2', 'p1']);
  });

  test('borrar también lo quita del celular', () async {
    SharedPreferences.setMockInitialValues({'recent.queries': ['monitor']});
    final c = ProviderContainer();
    addTearDown(c.dispose);
    c.read(recentQueriesProvider);
    await settle();
    expect(c.read(recentQueriesProvider), ['monitor']);
    c.read(recentQueriesProvider.notifier).clear();
    await settle();
    expect((await SharedPreferences.getInstance()).getStringList('recent.queries'), isEmpty);
  });
}
