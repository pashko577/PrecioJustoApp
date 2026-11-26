import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/shell.dart';
import '../../app/theme.dart';
import '../../core/search_normalizer.dart';
import '../../models/models.dart';
import '../../services/catalog_repository.dart';
import '../../ui/brand.dart';
import '../../ui/common.dart';
import '../tracking/tracking_actions.dart';
import 'home_screen.dart' show productGridDelegate;
import 'product_row.dart';
import 'recent.dart';

enum _Sort { price, stores }

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
    setState(() {}); // muestra u oculta el botón de borrar
  }

  void _submit(String value) {
    _timer?.cancel();
    if (mounted) setState(() => _query = value.trim());
  }

  void _useSuggestion(String value) {
    _controller.text = value;
    _submit(value);
    FocusScope.of(context).unfocus();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Buscar', style: theme.textTheme.headlineMedium),
                  const SizedBox(height: 12),
                  TextField(
                    key: const Key('search-field'),
                    controller: _controller,
                    autofocus: widget.initialQuery.isEmpty,
                    textInputAction: TextInputAction.search,
                    onChanged: _onChanged,
                    onSubmitted: (v) {
                      _submit(v);
                      ref.read(recentQueriesProvider.notifier).add(v);
                    },
                    style: const TextStyle(fontSize: 16),
                    decoration: InputDecoration(
                      hintText: 'Producto, marca o código de barras',
                      hintStyle: const TextStyle(color: AppColors.muted, fontSize: 15),
                      prefixIcon: const Icon(Icons.search, color: AppColors.ink),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(AppRadius.md),
                        borderSide: const BorderSide(color: AppColors.ink, width: 1.5),
                      ),
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
                ],
              ),
            ),
            Expanded(
              child: _query.isEmpty
                  ? _Suggestions(onPick: _useSuggestion)
                  : _SearchBody(
                      query: _query,
                      onOpen: () => ref.read(recentQueriesProvider.notifier).add(_query),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Suggestions extends ConsumerWidget {
  const _Suggestions({required this.onPick});

  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recent = ref.watch(recentQueriesProvider);
    final theme = Theme.of(context);
    Widget chips(List<String> items, {IconData? icon}) => Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final t in items)
              ActionChip(
                avatar: icon == null ? null : Icon(icon, size: 16, color: AppColors.ink),
                label: Text(t),
                backgroundColor: AppColors.sky,
                side: BorderSide.none,
                onPressed: () => onPick(t),
              ),
          ],
        );

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, navBarClearance),
      children: [
        if (recent.isNotEmpty) ...[
          Row(
            children: [
              Expanded(child: Text('Buscaste', style: theme.textTheme.labelLarge?.copyWith(color: AppColors.muted))),
              TextButton(onPressed: () => ref.read(recentQueriesProvider.notifier).clear(), child: const Text('Borrar')),
            ],
          ),
          chips(recent, icon: Icons.history),
          const SizedBox(height: 20),
        ],
        Text('Lo más buscado', style: theme.textTheme.labelLarge?.copyWith(color: AppColors.muted)),
        const SizedBox(height: 10),
        chips(popularSearches),
        const SizedBox(height: 28),
        Panel(
          child: Row(
            children: [
              const Icon(Icons.qr_code_2, color: AppColors.ink, size: 32),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  '¿Tienes la caja a la mano? Escribe el código de barras (los 13 números) y te mostramos ese producto exacto.',
                  style: theme.textTheme.bodySmall?.copyWith(color: AppColors.ink, fontSize: 13),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SearchBody extends ConsumerStatefulWidget {
  const _SearchBody({required this.query, required this.onOpen});

  final String query;
  final VoidCallback onOpen;

  @override
  ConsumerState<_SearchBody> createState() => _SearchBodyState();
}

class _SearchBodyState extends ConsumerState<_SearchBody> {
  _Sort _sort = _Sort.price;
  final Set<String> _stores = {};

  @override
  void didUpdateWidget(_SearchBody old) {
    super.didUpdateWidget(old);
    if (old.query != widget.query) _stores.clear();
  }

  @override
  Widget build(BuildContext context) {
    final parsed = SearchQuery.parse(widget.query);
    if (parsed.isEmpty) {
      return const EmptyState(
        icon: Icons.search,
        title: 'Escribe un poco más',
        body: 'Usa al menos 2 letras. Ejemplos: «kingston nv3», «rtx 4060», «lavadora lg» o un código de barras.',
      );
    }

    final results = ref.watch(searchResultsProvider(widget.query));
    final stores = ref.watch(storesProvider).value ?? const <String, StoreInfo>{};

    return results.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => EmptyState(
        icon: Icons.cloud_off_outlined,
        title: 'No se pudo buscar',
        body: 'Revisa tu conexión e inténtalo de nuevo.\n\n$e',
        action: FilledButton(
          onPressed: () => ref.invalidate(searchResultsProvider(widget.query)),
          child: const Text('Reintentar'),
        ),
      ),
      data: (items) {
        if (items.isEmpty) {
          return EmptyState(
            icon: Icons.search_off,
            title: 'No encontramos «${widget.query}»',
            body: 'Revisa la ortografía o prueba solo con la marca y el modelo, por ejemplo «Teros 2417».',
          );
        }
        // «Más barato en»: tiendas que tienen el mejor precio de algún resultado.
        final bestStores = {for (final p in items) if (p.summary.minPriceStoreCode != null) p.summary.minPriceStoreCode!};
        var shown = _stores.isEmpty ? items : items.where((p) => _stores.contains(p.summary.minPriceStoreCode)).toList();
        if (_sort == _Sort.stores) {
          shown = [...shown]..sort((a, b) => b.summary.storeCount.compareTo(a.summary.storeCount));
        }

        return CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: _ChipRow(children: [
                for (final (sort, label) in [(_Sort.price, 'Menor precio'), (_Sort.stores, 'Más tiendas')])
                  ChoiceChip(label: Text(label), selected: _sort == sort, onSelected: (_) => setState(() => _sort = sort)),
              ]),
            ),
            if (bestStores.length > 1)
              SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.fromLTRB(16, 6, 16, 0),
                      child: Text('Más barato en', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.muted)),
                    ),
                    _ChipRow(children: [
                      for (final code in bestStores)
                        FilterChip(
                          avatar: StoreBadge(code: code, name: stores[code]?.name ?? '', size: 20),
                          label: Text(stores[code]?.name ?? code),
                          selected: _stores.contains(code),
                          onSelected: (on) => setState(() => on ? _stores.add(code) : _stores.remove(code)),
                        ),
                    ]),
                  ],
                ),
              ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: Text(
                  '${shown.length} ${shown.length == 1 ? 'resultado' : 'resultados'}',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(color: AppColors.muted),
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              sliver: SliverGrid.builder(
                gridDelegate: productGridDelegate,
                itemCount: shown.length,
                itemBuilder: (_, i) => ProductCard(
                  product: shown[i],
                  onOpen: widget.onOpen,
                  favorite: FavoriteIconButton(product: shown[i]),
                ),
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: navBarClearance)),
          ],
        );
      },
    );
  }
}

class _ChipRow extends StatelessWidget {
  const _ChipRow({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 52,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          itemCount: children.length,
          separatorBuilder: (_, _) => const SizedBox(width: 8),
          itemBuilder: (_, i) => children[i],
        ),
      );
}
