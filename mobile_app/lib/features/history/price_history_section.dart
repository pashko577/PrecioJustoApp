import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../core/money.dart';
import '../../core/offer_rules.dart';
import '../../core/price_history.dart';
import '../../services/catalog_repository.dart';

/// Paleta categórica de referencia (validada: CVD y visión normal en pares adyacentes, modo claro).
/// El orden es fijo y el color sigue a la tienda (`storeColorSlot`), nunca a su posición.
const seriesColors = [
  Color(0xFF2A78D6), // azul
  Color(0xFFEB6834), // naranja
  Color(0xFF1BAF7A), // aqua
  Color(0xFFEDA100), // amarillo
  Color(0xFFE87BA4), // magenta
  Color(0xFF008300), // verde
];
const _surface = AppColors.surface;
const _gridline = AppColors.line;
const _inkPrimary = AppColors.ink;
const _inkSecondary = AppColors.muted;
const _inkMuted = Color(0xFF8A93A8);

/// Colores de las tiendas presentes en un gráfico (sin repetir; ver `assignStoreColors`).
Map<String, Color> colorsForStores(Iterable<String> storeCodes) => {
  for (final e in assignStoreColors(
    storeCodes,
    slots: seriesColors.length,
  ).entries)
    e.key: seriesColors[e.value],
};

String _date(DateTime d) {
  final l = d.toLocal();
  return '${l.day.toString().padLeft(2, '0')}/${l.month.toString().padLeft(2, '0')}';
}

String _dateTime(DateTime d) {
  final l = d.toLocal();
  return '${_date(d)}/${l.year} ${l.hour.toString().padLeft(2, '0')}:${l.minute.toString().padLeft(2, '0')}';
}

/// Historial de precios de un producto (RF-05): cifras clave, gráfico escalonado y tabla.
class PriceHistorySection extends ConsumerStatefulWidget {
  const PriceHistorySection({super.key, required this.productId});

  final String productId;

  @override
  ConsumerState<PriceHistorySection> createState() =>
      _PriceHistorySectionState();
}

class _PriceHistorySectionState extends ConsumerState<PriceHistorySection> {
  int _days = 30;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final history = ref.watch(historyProvider((widget.productId, _days)));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Historial de precios',
                style: theme.textTheme.titleMedium?.copyWith(fontSize: 17),
              ),
            ),
            SegmentedButton<int>(
              segments: const [
                ButtonSegment(value: 30, label: Text('30 días')),
                ButtonSegment(value: 90, label: Text('90 días')),
              ],
              selected: {_days},
              showSelectedIcon: false,
              onSelectionChanged: (s) => setState(() => _days = s.first),
            ),
          ],
        ),
        const SizedBox(height: 8),
        history.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (e, _) => Text('No se pudo cargar el historial: $e'),
          data: (histories) => _HistoryBody(histories: histories, days: _days),
        ),
      ],
    );
  }
}

class _HistoryBody extends StatelessWidget {
  const _HistoryBody({required this.histories, required this.days});

  final List<OfferHistory> histories;
  final int days;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now().toUtc();
    final stats = computeHistoryStats(histories, now: now, days: days);
    final withData = histories.where((h) => h.points.isNotEmpty).toList();
    final colors = colorsForStores(withData.map((h) => h.offer.storeCode));

    if (!stats.hasData) {
      return const _Notice(
        'Todavía no hay observaciones de precio para este producto.',
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Headline(stats: stats, days: days),
        const SizedBox(height: 12),
        _StatTiles(stats: stats),
        const SizedBox(height: 16),
        if (!stats.isMeaningful)
          _Notice(
            'Empezamos a registrar este producto el ${_date(stats.firstObservation!)}. '
            'El gráfico se completará a medida que pasen los días.',
          )
        else ...[
          SizedBox(
            height: 220,
            child: _HistoryChart(
              histories: withData,
              from: stats.from,
              now: now,
              colors: colors,
            ),
          ),
          const SizedBox(height: 8),
          _Legend(histories: withData, now: now, colors: colors),
        ],
        _DataTable(histories: withData, from: stats.from),
        const SizedBox(height: 4),
        Text(
          'Precios observados por CompraMejor desde el ${_date(stats.firstObservation!)}. '
          'No necesariamente incluyen todos los precios que existieron en las tiendas.',
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: _inkSecondary),
        ),
      ],
    );
  }
}

/// Mensaje principal: cómo está el precio actual frente al periodo.
class _Headline extends StatelessWidget {
  const _Headline({required this.stats, required this.days});

  final HistoryStats stats;
  final int days;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pct = stats.currentVsAveragePercent;
    if (!stats.isMeaningful || stats.currentCents == null || pct == null) {
      return const SizedBox.shrink();
    }

    final String text;
    final IconData icon;
    if (stats.currentIsLowest && stats.changes > 0) {
      icon = Icons.trending_down;
      text = 'Es el precio más bajo observado en los últimos $days días.';
    } else if (pct <= -3) {
      icon = Icons.trending_down;
      text =
          'El mejor precio actual está ${pct.abs().toStringAsFixed(0)} % por debajo del promedio de $days días.';
    } else if (pct >= 3) {
      icon = Icons.trending_up;
      text =
          'El mejor precio actual está ${pct.toStringAsFixed(0)} % por encima del promedio de $days días.';
    } else {
      icon = Icons.trending_flat;
      text =
          'El precio se mantiene cerca del promedio de los últimos $days días.';
    }
    return Row(
      children: [
        Icon(icon, size: 20, color: icon == Icons.trending_down ? AppColors.tealInk : _inkPrimary),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            key: const Key('history-headline'),
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: icon == Icons.trending_down ? AppColors.tealInk : _inkPrimary,
            ),
          ),
        ),
      ],
    );
  }
}

class _StatTiles extends StatelessWidget {
  const _StatTiles({required this.stats});

  final HistoryStats stats;

  @override
  Widget build(BuildContext context) {
    String money(int? c) => c == null ? '—' : formatCents(c);
    return LayoutBuilder(
      builder: (context, constraints) => Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final tile in <_Tile>[
            _Tile(label: 'Mejor precio hoy', value: money(stats.currentCents)),
            _Tile(
              label: 'Mínimo',
              value: money(stats.minCents),
              detail: stats.minAt == null ? null : 'el ${_date(stats.minAt!)}',
            ),
            _Tile(label: 'Máximo', value: money(stats.maxCents)),
            _Tile(
              label: 'Promedio',
              value: money(stats.averageCents),
              detail: 'ponderado por tiempo',
            ),
          ])
            SizedBox(width: (constraints.maxWidth - 8) / 2, child: tile),
        ],
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.label, required this.value, this.detail});

  final String label;
  final String value;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: _surface,
        border: Border.all(color: _gridline),
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(color: _inkSecondary),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: theme.textTheme.titleMedium?.copyWith(
              color: _inkPrimary,
              fontWeight: FontWeight.bold,
            ),
          ),
          if (detail != null)
            Text(
              detail!,
              style: theme.textTheme.labelSmall?.copyWith(color: _inkMuted),
            ),
        ],
      ),
    );
  }
}

/// Serie escalonada de una oferta dentro del periodo (se corta donde no hubo stock).
List<FlSpot> seriesSpots(OfferHistory h, DateTime from, DateTime now) {
  double x(DateTime t) => t.difference(from).inMinutes / 60.0;
  final spots = <FlSpot>[];
  void add(DateTime t, int? cents) {
    if (cents == null) {
      if (spots.isNotEmpty && spots.last != FlSpot.nullSpot) {
        spots.add(FlSpot.nullSpot);
      }
    } else {
      spots.add(FlSpot(x(t), cents / 100));
    }
  }

  final firstAt = h.points.first.at;
  final start = firstAt.isAfter(from) ? firstAt : from;
  add(start, h.priceAt(start));
  for (final p in h.points.where(
    (p) => p.at.isAfter(start) && !p.at.isAfter(now),
  )) {
    add(p.at, p.isAvailable ? p.priceCents : null);
  }
  add(now, h.priceAt(now)); // el último precio se extiende hasta hoy
  while (spots.isNotEmpty && spots.last == FlSpot.nullSpot) {
    spots.removeLast();
  }
  return spots;
}

class _HistoryChart extends StatelessWidget {
  const _HistoryChart({
    required this.histories,
    required this.from,
    required this.now,
    required this.colors,
  });

  final List<OfferHistory> histories;
  final DateTime from;
  final DateTime now;
  final Map<String, Color> colors;

  @override
  Widget build(BuildContext context) {
    final series = [for (final h in histories) (h, seriesSpots(h, from, now))];
    final values = [
      for (final s in series)
        ...s.$2.where((p) => p != FlSpot.nullSpot).map((p) => p.y),
    ];
    if (values.isEmpty) {
      return const _Notice('Sin precios disponibles en este periodo.');
    }
    final minY = values.reduce(math.min), maxY = values.reduce(math.max);
    final pad = math.max((maxY - minY) * 0.15, maxY * 0.02);
    final maxX = now.difference(from).inMinutes / 60.0;
    const labelStyle = TextStyle(color: _inkMuted, fontSize: 11);

    return Semantics(
      label:
          'Gráfico del historial de precios por tienda. Los datos están en la tabla "Ver datos del gráfico".',
      child: LineChart(
        LineChartData(
          minX: 0,
          maxX: maxX,
          minY: math.max(0, minY - pad),
          maxY: maxY + pad,
          clipData: const FlClipData.all(),
          borderData: FlBorderData(show: false),
          gridData: FlGridData(
            drawVerticalLine: false,
            getDrawingHorizontalLine: (_) =>
                const FlLine(color: _gridline, strokeWidth: 1),
          ),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(),
            rightTitles: const AxisTitles(),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 56,
                getTitlesWidget: (v, meta) => v == meta.min || v == meta.max
                    ? const SizedBox.shrink()
                    : Text(
                        formatCents((v * 100).round()).replaceAll('.00', ''),
                        style: labelStyle,
                      ),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 24,
                interval: math.max(24, (maxX / 4).roundToDouble()),
                getTitlesWidget: (v, meta) => Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    _date(from.add(Duration(minutes: (v * 60).round()))),
                    style: labelStyle,
                  ),
                ),
              ),
            ),
          ),
          lineTouchData: LineTouchData(
            getTouchedSpotIndicator: (bar, indexes) => [
              for (final _ in indexes)
                const TouchedSpotIndicatorData(
                  FlLine(color: _inkMuted, strokeWidth: 1),
                  FlDotData(show: false),
                ),
            ],
            touchTooltipData: LineTouchTooltipData(
              getTooltipColor: (_) => _inkPrimary,
              fitInsideHorizontally: true,
              fitInsideVertically: true,
              getTooltipItems: (spots) => [
                for (final s in spots)
                  LineTooltipItem(
                    '${series[s.barIndex].$1.offer.storeName}: ${formatCents((s.y * 100).round())}',
                    const TextStyle(color: Colors.white, fontSize: 12),
                  ),
              ],
            ),
          ),
          lineBarsData: [
            for (final (h, spots) in series)
              LineChartBarData(
                spots: spots,
                isStepLineChart: true,
                color: colors[h.offer.storeCode],
                barWidth: 2,
                isStrokeCapRound: true,
                isStrokeJoinRound: true,
                dotData: FlDotData(
                  // Solo el punto final (precio de hoy): 8 px con anillo del color de fondo.
                  checkToShowDot: (spot, bar) => spot == bar.spots.last,
                  getDotPainter: (spot, percent, bar, index) =>
                      FlDotCirclePainter(
                        radius: 4,
                        color: bar.color ?? _inkPrimary,
                        strokeWidth: 2,
                        strokeColor: _surface,
                      ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Leyenda: siempre presente con 2+ series; el texto usa tinta, el color va en la muestra.
class _Legend extends StatelessWidget {
  const _Legend({
    required this.histories,
    required this.now,
    required this.colors,
  });

  final List<OfferHistory> histories;
  final DateTime now;
  final Map<String, Color> colors;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Wrap(
      spacing: 16,
      runSpacing: 6,
      children: [
        for (final h in histories)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(width: 16, height: 3, color: colors[h.offer.storeCode]),
              const SizedBox(width: 6),
              Text(
                '${h.offer.storeName}${isThirdPartySeller(h.offer) ? ' (${h.offer.sellerName})' : ''}'
                '${h.priceAt(now) != null ? ' · ${formatCents(h.priceAt(now)!)}' : ' · sin stock'}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: _inkSecondary,
                ),
              ),
            ],
          ),
      ],
    );
  }
}

/// Vista de tabla (accesibilidad): todas las observaciones del periodo.
class _DataTable extends StatelessWidget {
  const _DataTable({required this.histories, required this.from});

  final List<OfferHistory> histories;
  final DateTime from;

  @override
  Widget build(BuildContext context) {
    final rows = [
      for (final h in histories)
        for (final p in h.points.where((p) => p.at.isAfter(from))) (h, p),
    ]..sort((a, b) => b.$2.at.compareTo(a.$2.at));
    final theme = Theme.of(context);
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      title: Text(
        'Ver datos del gráfico (${rows.length})',
        style: theme.textTheme.bodyMedium,
      ),
      children: [
        for (final (h, p) in rows.take(100))
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                SizedBox(
                  width: 120,
                  child: Text(
                    _dateTime(p.at),
                    style: theme.textTheme.bodySmall,
                  ),
                ),
                Expanded(
                  child: Text(
                    h.offer.storeName,
                    style: theme.textTheme.bodySmall,
                  ),
                ),
                Text(
                  p.isAvailable ? formatCents(p.priceCents) : 'Sin stock',
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Row(
      children: [
        const Icon(Icons.info_outline, size: 18, color: _inkSecondary),
        const SizedBox(width: 8),
        Expanded(
          child: Text(text, style: Theme.of(context).textTheme.bodyMedium),
        ),
      ],
    ),
  );
}
