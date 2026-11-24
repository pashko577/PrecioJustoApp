import '../models/models.dart';

/// Un punto del historial: el precio pasó a [priceCents] en el momento [at] (RN-07).
/// El motor solo guarda puntos cuando cambia el precio, la disponibilidad o el envío, así que
/// entre dos puntos el precio se mantuvo constante (función escalonada).
class PricePoint {
  const PricePoint({required this.at, required this.priceCents, required this.availability});

  final DateTime at;
  final int priceCents;
  final Availability availability;

  bool get isAvailable => availability == Availability.available;
}

/// Historial de una oferta (una publicación de una tienda).
class OfferHistory {
  OfferHistory({required this.offer, required List<PricePoint> points})
      : points = [...points]..sort((a, b) => a.at.compareTo(b.at));

  final StoreOffer offer;
  final List<PricePoint> points;

  /// Precio vigente en el instante [t] (`null` si aún no había datos o no estaba disponible).
  int? priceAt(DateTime t) {
    PricePoint? current;
    for (final p in points) {
      if (p.at.isAfter(t)) break;
      current = p;
    }
    return current != null && current.isAvailable ? current.priceCents : null;
  }
}

/// Convierte los documentos `history/{YYYY-MM}` (`points: [{t, p, a, s}]`) en puntos.
List<PricePoint> parseHistoryPoints(List<Map<String, dynamic>> monthDocs, DateTime Function(Object?) toDate) {
  final result = <PricePoint>[];
  for (final doc in monthDocs) {
    for (final raw in (doc['points'] as List? ?? const [])) {
      final m = Map<String, dynamic>.from(raw as Map);
      final price = (m['p'] as num?)?.toInt();
      if (price == null || price <= 0) continue;
      result.add(PricePoint(
        at: toDate(m['t']),
        priceCents: price,
        availability: parseAvailability(m['a'] as String?),
      ));
    }
  }
  result.sort((a, b) => a.at.compareTo(b.at));
  return result;
}

/// Agrega el estado vigente de la oferta (precio desde `lastChangedAt`) si el historial no lo
/// tiene: una publicación nueva no guarda historial hasta su primer cambio de precio.
List<PricePoint> withCurrentState(List<PricePoint> points, StoreOffer offer) {
  final since = offer.lastChangedAt;
  if (since == null || offer.priceCents <= 0 || points.any((p) => p.at.isAtSameMomentAs(since))) return points;
  return [
    ...points,
    PricePoint(at: since, priceCents: offer.priceCents, availability: offer.availability),
  ]..sort((a, b) => a.at.compareTo(b.at));
}

/// Meses (`YYYY-MM`) que cubren el periodo de [days] días hasta [now].
List<String> monthsCovering(DateTime now, int days) {
  final from = now.subtract(Duration(days: days));
  final months = <String>[];
  var cursor = DateTime.utc(from.year, from.month);
  final last = DateTime.utc(now.year, now.month);
  while (!cursor.isAfter(last)) {
    months.add('${cursor.year}-${cursor.month.toString().padLeft(2, '0')}');
    cursor = DateTime.utc(cursor.year, cursor.month + 1);
  }
  return months;
}

/// Estadísticas del periodo sobre el MEJOR precio disponible en cada momento (RF-05).
class HistoryStats {
  const HistoryStats({
    required this.from,
    required this.to,
    required this.firstObservation,
    this.currentCents,
    this.minCents,
    this.minAt,
    this.maxCents,
    this.averageCents,
    this.changes = 0,
  });

  final DateTime from;
  final DateTime to;

  /// Primera observación de CompraMejor para este producto (el historial empieza ahí).
  final DateTime? firstObservation;
  final int? currentCents;
  final int? minCents;
  final DateTime? minAt;
  final int? maxCents;

  /// Promedio ponderado por tiempo: un precio que duró 20 días pesa más que uno de 2 horas.
  final int? averageCents;

  /// Cantidad de cambios de precio registrados en el periodo.
  final int changes;

  bool get hasData => minCents != null;

  /// Hay historial suficiente para comparar (al menos un día observado y algún cambio o 7 días).
  bool get isMeaningful =>
      hasData && firstObservation != null && to.difference(firstObservation!).inHours >= 24;

  /// Variación del precio actual frente al promedio, en porcentaje (negativo = más barato).
  double? get currentVsAveragePercent {
    if (currentCents == null || averageCents == null || averageCents == 0) return null;
    return (currentCents! - averageCents!) * 100 / averageCents!;
  }

  bool get currentIsLowest => currentCents != null && minCents != null && currentCents! <= minCents!;
}

/// Calcula las estadísticas del mejor precio entre todas las ofertas en `[now - days, now]`.
HistoryStats computeHistoryStats(List<OfferHistory> histories, {required DateTime now, required int days}) {
  final from = now.subtract(Duration(days: days));
  final allPoints = [for (final h in histories) ...h.points];
  final first = allPoints.isEmpty ? null : allPoints.map((p) => p.at).reduce((a, b) => a.isBefore(b) ? a : b);

  // Instantes donde puede cambiar el mejor precio: inicio del periodo y cada punto dentro de él.
  final instants = <DateTime>{
    if (first != null) (first.isAfter(from) ? first : from),
    for (final p in allPoints)
      if (p.at.isAfter(from) && !p.at.isAfter(now)) p.at,
  }.toList()
    ..sort();

  int? best(DateTime t) {
    int? result;
    for (final h in histories) {
      final price = h.priceAt(t);
      if (price != null && (result == null || price < result)) result = price;
    }
    return result;
  }

  int? minCents, maxCents;
  DateTime? minAt;
  var weighted = 0.0;
  var totalSeconds = 0;
  var changes = 0;
  int? previous;
  for (var i = 0; i < instants.length; i++) {
    final t = instants[i];
    final price = best(t);
    final end = i + 1 < instants.length ? instants[i + 1] : now;
    if (price == null) {
      previous = null;
      continue;
    }
    if (previous != null && previous != price) changes++;
    previous = price;
    if (minCents == null || price < minCents) {
      minCents = price;
      minAt = t;
    }
    if (maxCents == null || price > maxCents) maxCents = price;
    final seconds = end.difference(t).inSeconds;
    if (seconds > 0) {
      weighted += price * seconds;
      totalSeconds += seconds;
    }
  }

  return HistoryStats(
    from: from,
    to: now,
    firstObservation: first,
    currentCents: best(now),
    minCents: minCents,
    minAt: minAt,
    maxCents: maxCents,
    averageCents: totalSeconds > 0 ? (weighted / totalSeconds).round() : minCents,
    changes: changes,
  );
}

/// Orden fijo de colores por tienda: el color sigue a la tienda en todos los productos,
/// nunca a su posición en la lista. Nuevas tiendas se agregan AL FINAL (no reordenar).
/// (WONG se retiró de la lista antes de activarse: nunca se mostró con color.)
const storeColorOrder = ['COOLBOX', 'PLAZAVEA', 'OECHSLE', 'PROMART', 'EFE', 'LACURACAO'];

/// Asigna un color (índice 0-based) a cada tienda de un gráfico, sin repetir:
/// - las tiendas conocidas conservan SIEMPRE su color fijo (el color sigue a la tienda);
/// - las desconocidas toman los colores libres en orden alfabético (estable entre productos);
/// - si no alcanzan los colores, el resto comparte el último ("Otras"); con 6 colores y
///   4–5 tiendas activas no ocurre.
Map<String, int> assignStoreColors(Iterable<String> storeCodes, {int slots = 6}) {
  final codes = storeCodes.toSet();
  final result = <String, int>{};
  for (final code in codes) {
    final i = storeColorOrder.indexOf(code);
    if (i >= 0 && i < slots) result[code] = i;
  }
  final free = [for (var i = 0; i < slots; i++) if (!result.values.contains(i)) i];
  final unknown = codes.where((c) => !result.containsKey(c)).toList()..sort();
  for (var k = 0; k < unknown.length; k++) {
    result[unknown[k]] = k < free.length ? free[k] : slots - 1;
  }
  return result;
}
