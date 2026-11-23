import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/search_normalizer.dart';
import '../../services/catalog_repository.dart';
import 'product_row.dart';

/// Búsqueda de productos por nombre, marca, modelo o código de barras (RF-02).
class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key, this.initialQuery = ''});

  final String initialQuery;

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  static const debounce = Duration(milliseconds: 350);

  late final _controller = TextEditingController(text: widget.initialQuery);
  Timer? _timer;
  late String _query = widget.initialQuery.trim();

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  /// Espera a que el usuario deje de escribir para no gastar lecturas en cada letra.
  void _onChanged(String value) {
    _timer?.cancel();
    _timer = Timer(debounce, () => _submit(value));
  }

  void _submit(String value) {
    _timer?.cancel();
    if (mounted) setState(() => _query = value.trim());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: TextField(
          key: const Key('search-field'),
          controller: _controller,
          autofocus: widget.initialQuery.isEmpty,
          textInputAction: TextInputAction.search,
          onChanged: _onChanged,
          onSubmitted: _submit,
          decoration: InputDecoration(
            hintText: 'Producto, marca o código de barras',
            border: InputBorder.none,
            suffixIcon: _controller.text.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Borrar',
                    icon: const Icon(Icons.close),
                    onPressed: () {
                      _controller.clear();
                      _submit('');
                    },
                  ),
          ),
        ),
      ),
      body: _SearchBody(query: _query),
    );
  }
}

class _SearchBody extends ConsumerWidget {
  const _SearchBody({required this.query});

  final String query;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final parsed = SearchQuery.parse(query);
    if (parsed.isEmpty) {
      return const _Message(
        icon: Icons.search,
        title: 'Busca en el catálogo',
        body: 'Escribe al menos 2 letras. Ejemplos: "kingston nv3", "rtx 4060", "lavadora lg" '
            'o un código de barras.',
      );
    }

    final results = ref.watch(searchResultsProvider(query));
    return results.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => _Message(icon: Icons.error_outline, title: 'No se pudo buscar', body: '$e'),
      data: (items) => items.isEmpty
          ? _Message(
              icon: Icons.search_off,
              title: 'Sin resultados para "$query"',
              body: 'Revisa la ortografía o prueba con menos palabras (por ejemplo, solo la marca y el modelo).',
            )
          : ListView.separated(
              itemCount: items.length + 1,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, i) => i == 0
                  ? Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                      child: Text(
                        '${items.length} ${items.length == 1 ? 'resultado' : 'resultados'}',
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                    )
                  : ProductRow(product: items[i - 1]),
            ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.icon, required this.title, required this.body});

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 56, color: Theme.of(context).hintColor),
            const SizedBox(height: 12),
            Text(title, style: Theme.of(context).textTheme.titleMedium, textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(body, textAlign: TextAlign.center),
          ]),
        ),
      );
}
