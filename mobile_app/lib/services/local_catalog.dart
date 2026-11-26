import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show compute, debugPrint;
import 'package:path_provider/path_provider.dart';

import '../core/search_normalizer.dart';
import '../models/models.dart';

/// Catálogo público completo en el celular (`catalog.json`, ver `app/export/catalog.py`).
///
/// Navegar, buscar y comparar se hace en memoria: 0 lecturas de Firestore por usuario. El archivo
/// lo publica el motor en GitHub Pages después de cada actualización de precios.
class LocalCatalog {
  LocalCatalog._({
    required this.generatedAt,
    required this.categories,
    required this.stores,
    required Map<String, Product> products,
    required Map<String, List<StoreOffer>> offersByProduct,
  }) : _products = products,
       _offersByProduct = offersByProduct, // ignore: prefer_initializing_formals
       _active = products.values.where((p) => p.status == 'ACTIVE').toList()..sort(_bySortPrice),
       _tokens = {
         for (final p in products.values)
           if (p.status == 'ACTIVE') p.id: wordTokens('${p.name} ${p.brand} ${p.model ?? ''}').toSet(),
       };

  final DateTime generatedAt;
  final List<Category> categories;
  final Map<String, StoreInfo> stores;
  final Map<String, Product> _products;
  final Map<String, List<StoreOffer>> _offersByProduct;

  /// Productos activos en el mismo orden que la consulta de Firestore (`summary.sortPriceCents`).
  final List<Product> _active;
  final Map<String, Set<String>> _tokens;

  static const formatVersion = 1;

  /// Interpreta el JSON publicado. Lanza `FormatException` si no es de este formato.
  factory LocalCatalog.fromJson(Map<String, dynamic> json) {
    if (json['version'] != formatVersion) {
      throw FormatException('Formato de catálogo no soportado: ${json['version']}');
    }
    List<Map<String, dynamic>> list(String key) =>
        [for (final e in (json[key] as List? ?? const [])) (e as Map).cast<String, dynamic>()];

    final offers = <String, List<StoreOffer>>{};
    final storesByProduct = <String, Set<String>>{};
    for (final o in list('offers')) {
      final pid = o['productId'] as String;
      offers.putIfAbsent(pid, () => []).add(StoreOffer.fromCatalog(o));
      storesByProduct.putIfAbsent(pid, () => {}).add(o['storeCode'] as String? ?? '');
    }
    // Tiendas distintas por producto: el catálogo trae todas las publicaciones, así que se cuentan
    // aquí (también para productos cuyo resumen aún no trae `storeCount`).
    Product product(Map<String, dynamic> p) {
      final stores = storesByProduct[p['id']];
      if (stores == null) return Product.fromCatalog(p);
      final summary = {...?(p['summary'] as Map?)?.cast<String, dynamic>(), 'storeCount': stores.length};
      return Product.fromCatalog({...p, 'summary': summary});
    }
    return LocalCatalog._(
      generatedAt: DateTime.tryParse(json['generatedAt'] as String? ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0),
      categories: list('categories').map(Category.fromCatalog).toList()..sort((a, b) => a.order.compareTo(b.order)),
      stores: {for (final s in list('stores')) s['code'] as String: StoreInfo.fromCatalog(s)},
      products: {for (final p in list('products')) p['id'] as String: product(p)},
      offersByProduct: offers,
    );
  }

  /// Mismo valor que `NO_PRICE_SORT_VALUE` del motor: sin precio verificado, al final.
  static const _noPrice = 1 << 53;

  static int _bySortPrice(Product a, Product b) {
    final pa = a.summary.minPriceCents ?? _noPrice, pb = b.summary.minPriceCents ?? _noPrice;
    return pa != pb ? pa.compareTo(pb) : a.id.compareTo(b.id);
  }

  int get productCount => _active.length;

  /// Página del listado. El cursor es la posición en la lista ordenada.
  ({List<Product> items, int next, bool hasMore}) page({List<String>? categorySlugs, int offset = 0, int limit = 20}) {
    final slugs = categorySlugs == null || categorySlugs.isEmpty ? null : categorySlugs.toSet();
    final source = slugs == null ? _active : _active.where((p) => slugs.contains(p.categorySlug)).toList();
    final end = (offset + limit).clamp(0, source.length);
    final start = offset.clamp(0, end);
    return (items: source.sublist(start, end), next: end, hasMore: end < source.length);
  }

  /// Búsqueda por palabras (con prefijo, igual que en línea) o por código de barras.
  List<Product> search(SearchQuery query, {int limit = 100}) {
    if (query.isEmpty) return const [];
    final Iterable<Product> found;
    if (query.barcode != null) {
      found = _active.where((p) => p.identifiers.entries.any((e) =>
          e.key != 'MPN' && e.value.any((code) => (canonicalGtin(code) ?? code) == query.barcode)));
    } else {
      // Igual que SearchQuery.matches, sin copiar las palabras de cada producto en cada búsqueda.
      bool matches(Set<String> tokens) =>
          query.words.every((w) => tokens.contains(w) || tokens.any((t) => t.startsWith(w)));
      found = _active.where((p) => matches(_tokens[p.id]!));
    }
    return found.take(limit).toList();
  }

  /// Bajadas de precio de mayor a menor (banner de Inicio).
  List<Product> priceDrops({int limit = 8}) {
    final drops = _active.where((p) => (p.summary.priceDropPercent ?? 0) > 0).toList()
      ..sort((a, b) => b.summary.priceDropPercent!.compareTo(a.summary.priceDropPercent!));
    return drops.take(limit).toList();
  }

  /// Producto por id (también los unificados, para redirigir). `null` si no está en el archivo.
  Product? product(String id) => _products[id];

  List<StoreOffer> offers(String productId) => _offersByProduct[productId] ?? const [];
}

/// Descarga, guarda y entrega el catálogo local.
///
/// - Al abrir la app se usa la copia guardada (instantáneo, también sin internet).
/// - Si tiene más de [maxAge], se pide una nueva en segundo plano (con `If-None-Match`: si no
///   cambió, el servidor responde 304 sin volver a enviarla).
/// - Sin copia guardada se espera la descarga; si falla, la app usa Firestore como respaldo.
class CatalogCache {
  CatalogCache({
    Uri? url,
    this.maxAge = const Duration(hours: 2),
    Future<Directory> Function()? directory,
    HttpClient Function()? httpClient,
  }) : url = url ?? Uri.parse(defaultCatalogUrl),
       _directory = directory ?? getApplicationSupportDirectory,
       _httpClient = httpClient ?? HttpClient.new;

  /// URL del catálogo; se puede cambiar con `--dart-define=CATALOG_URL=...`.
  static const defaultCatalogUrl = String.fromEnvironment(
    'CATALOG_URL',
    defaultValue: 'https://pashko577.github.io/PrecioJustoApp/catalog.json',
  );

  final Uri url;
  final Duration maxAge;
  final Future<Directory> Function() _directory;
  final HttpClient Function() _httpClient;

  LocalCatalog? _catalog;
  DateTime? _checkedAt;
  Future<LocalCatalog?>? _loading;
  Future<void>? _refreshing;

  /// Catálogo disponible (o `null` si no hay ni copia ni descarga posible).
  Future<LocalCatalog?> get() {
    final current = _catalog;
    if (current != null) {
      _refreshIfStale();
      return Future.value(current);
    }
    return _loading ??= _loadFirst().whenComplete(() => _loading = null);
  }

  Future<File> _file(String name) async => File('${(await _directory()).path}/$name');

  Future<LocalCatalog?> _loadFirst() async {
    try {
      final file = await _file('catalog.json');
      if (await file.exists()) {
        _catalog = await _parse(await file.readAsString());
        _checkedAt = (await file.lastModified()).toUtc();
        _refreshIfStale();
        return _catalog;
      }
    } catch (e) {
      debugPrint('Catálogo guardado ilegible: $e');
    }
    await _download();
    return _catalog;
  }

  void _refreshIfStale() {
    final checked = _checkedAt;
    if (checked != null && DateTime.now().toUtc().difference(checked) < maxAge) return;
    _refreshing ??= _download().whenComplete(() => _refreshing = null);
  }

  /// Fuerza una descarga (por ejemplo, al deslizar para actualizar).
  Future<void> refresh() => _refreshing ??= _download().whenComplete(() => _refreshing = null);

  Future<void> _download() async {
    final client = _httpClient()..connectionTimeout = const Duration(seconds: 10);
    try {
      final etagFile = await _file('catalog.etag');
      final request = await client.getUrl(url);
      request.headers.set(HttpHeaders.acceptEncodingHeader, 'gzip');
      if (_catalog != null && await etagFile.exists()) {
        request.headers.set(HttpHeaders.ifNoneMatchHeader, await etagFile.readAsString());
      }
      final response = await request.close().timeout(const Duration(seconds: 30));
      _checkedAt = DateTime.now().toUtc();
      if (response.statusCode == HttpStatus.notModified) {
        await response.drain<void>();
        return;
      }
      if (response.statusCode != HttpStatus.ok) {
        await response.drain<void>();
        debugPrint('Catálogo: HTTP ${response.statusCode}');
        return;
      }
      final body = await response.transform(utf8.decoder).join();
      final catalog = await _parse(body);
      // Se guarda solo si se pudo interpretar (nunca se reemplaza una copia buena por una dañada).
      await (await _file('catalog.json')).writeAsString(body, flush: true);
      final etag = response.headers.value(HttpHeaders.etagHeader);
      if (etag != null) await etagFile.writeAsString(etag);
      _catalog = catalog;
    } catch (e) {
      debugPrint('Catálogo: no se pudo descargar ($e)');
    } finally {
      client.close();
    }
  }

  /// Interpretar varios MB de JSON fuera del hilo de la interfaz.
  static Future<LocalCatalog> _parse(String body) =>
      compute((String raw) => LocalCatalog.fromJson(jsonDecode(raw) as Map<String, dynamic>), body);
}
