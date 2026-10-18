import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/services.dart';

/// Illustrative ocean-only routing against the bundled Natural Earth land
/// polygons. Never used for real-world navigation.
class VelaOceanGrid {
  VelaOceanGrid._();
  static final VelaOceanGrid instance = VelaOceanGrid._();
  static const double step = 1.5;
  static const int columns = 240, rows = 120;
  List<List<Offset>> _land = const [];
  final Map<int, bool> _water = {};
  final Map<String, List<Offset>> _routes = {};
  Future<void>? _loading;
  bool get ready => _land.isNotEmpty;

  Future<void> initialize() => _loading ??= _load();

  Future<void> _load() async {
    try {
      final input = jsonDecode(await rootBundle.loadString(
          'assets/maps/world_110m.json')) as List<dynamic>;
      _land = input.map((ring) => (ring as List<dynamic>).map((pair) {
        final p = pair as List<dynamic>;
        return Offset((p[0] as num).toDouble(), (p[1] as num).toDouble());
      }).toList(growable: false)).where((p) => p.length >= 3)
          .toList(growable: false);
      _water.clear();
      _routes.clear();
    } catch (_) {
      _land = const [];
      _loading = null;
    }
  }

  static double _wrap(double longitude) =>
      (longitude + 540) % 360 - 180;
  static double _delta(double a, double b) => _wrap(b - a);
  static int _index(int x, int y) => y * columns + (x + columns) % columns;
  static Offset _geo(int id) => Offset(
      (id % columns + .5) * step - 180,
      90 - (id ~/ columns + .5) * step);

  bool _containsLand(Offset p) {
    for (final poly in _land) {
      // Ray casting in equirectangular geographic coordinates.
      var inside = false;
      for (var i = 0, j = poly.length - 1; i < poly.length; j = i++) {
        final a = poly[i], b = poly[j];
        if ((a.dy > p.dy) != (b.dy > p.dy) &&
            p.dx < (b.dx - a.dx) * (p.dy - a.dy) /
                (b.dy - a.dy) + a.dx) {
          inside = !inside;
        }
      }
      if (inside) return true;
    }
    return false;
  }

  bool _isWater(int id) {
    return _water.putIfAbsent(id, () {
      final p = _geo(id);
      if (p.dy.abs() > 83) return false;
      return !_containsLand(p);
    });
  }

  int _closestWater(Offset geo) {
    final xx = (((_wrap(geo.dx) + 180) / step).floor()) % columns;
    final yy = ((90 - geo.dy) / step).floor().clamp(0, rows - 1);
    var best = -1;
    var bestDistance = double.infinity;
    // Coastal departure/arrival is *never* painted across inland terrain.
    // The nearest sea cell is used for inland destinations.
    for (var radius = 0; radius < math.max(columns ~/ 2, rows); radius++) {
      for (var dy = -radius; dy <= radius; dy++) {
        final y = yy + dy;
        if (y < 0 || y >= rows) continue;
        for (var dx = -radius; dx <= radius; dx++) {
          if (math.max(dx.abs(), dy.abs()) != radius) continue;
          final id = _index(xx + dx, y);
          if (!_isWater(id)) continue;
          final p = _geo(id);
          final ddx = _delta(geo.dx, p.dx) *
              math.cos(geo.dy * math.pi / 180).abs().clamp(.15, 1.0);
          final distance = ddx * ddx + math.pow(geo.dy - p.dy, 2);
          if (distance < bestDistance) {
            best = id;
            bestDistance = distance.toDouble();
          }
        }
      }
      if (best >= 0 && radius * radius > bestDistance + 4) break;
    }
    return best;
  }

  double _heuristic(int a, int b) {
    final p = _geo(a), q = _geo(b);
    final dx = _delta(p.dx, q.dx) *
        math.cos((p.dy + q.dy) * math.pi / 360).abs().clamp(.2, 1.0);
    return math.sqrt(dx * dx + math.pow(p.dy - q.dy, 2));
  }

  /// A* through sea cells, crossing the date line but not continental land.
  List<Offset> route(Offset from, Offset to) {
    if (!ready) return const [];
    final key = '${from.dx.toStringAsFixed(2)},${from.dy.toStringAsFixed(2)}'
        ':${to.dx.toStringAsFixed(2)},${to.dy.toStringAsFixed(2)}';
    final cached = _routes[key];
    if (cached != null) return cached;
    final start = _closestWater(from), goal = _closestWater(to);
    if (start < 0 || goal < 0) return const [];
    final g = <int, double>{start: 0};
    final parent = <int, int>{};
    final closed = <int>{};
    final heap = _OceanHeap()..add(start, _heuristic(start, goal));
    const directions = <List<int>>[
      [-1,0], [1,0], [0,-1], [0,1],
      [-1,-1], [-1,1], [1,-1], [1,1],
    ];
    while (heap.isNotEmpty) {
      final current = heap.remove();
      if (!closed.add(current)) continue;
      if (current == goal) break;
      final x = current % columns, y = current ~/ columns;
      for (final d in directions) {
        final ny = y + d[1];
        if (ny < 0 || ny >= rows) continue;
        final nx = (x + d[0] + columns) % columns;
        final next = _index(nx, ny);
        if (!_isWater(next) || closed.contains(next)) continue;
        // Do not slip between two touching land cells at a diagonal.
        if (d[0] != 0 && d[1] != 0 &&
            (!_isWater(_index(nx, y)) ||
             !_isWater(_index(x, ny)))) continue;
        final latitude = _geo(current).dy * math.pi / 180;
        final cost = math.sqrt(math.pow(d[0] * math.cos(latitude), 2) +
            d[1] * d[1].toDouble()) * step;
        final tentative = g[current]! + cost;
        if (tentative >= (g[next] ?? double.infinity)) {
          continue;
        }
        g[next] = tentative;
        parent[next] = current;
        heap.add(next, tentative + _heuristic(next, goal));
      }
    }
    if (start != goal && !parent.containsKey(goal)) return const [];
    final path = <int>[goal];
    while (path.last != start) {
      path.add(parent[path.last]!);
    }
    final result = path.reversed.map(_geo).toList();
    // Keep the actual gridded ocean corridor. Aggressive curve fitting can
    // otherwise cut corners through peninsulas and coastal islands.
    _routes[key] = result;
    return result;
  }
}

class _OceanEntry {
  const _OceanEntry(this.index, this.score);
  final int index;
  final double score;
}

class _OceanHeap {
  final List<_OceanEntry> _data = [];
  bool get isNotEmpty => _data.isNotEmpty;
  void add(int index, double score) {
    final value = _OceanEntry(index, score);
    var pos = _data.length;
    _data.add(value);
    while (pos > 0) {
      final parent = (pos - 1) ~/ 2;
      if (_data[parent].score <= score) break;
      _data[pos] = _data[parent];
      pos = parent;
    }
    _data[pos] = value;
  }
  int remove() {
    final first = _data.first.index;
    final last = _data.removeLast();
    if (_data.isEmpty) return first;
    var pos = 0;
    while (pos * 2 + 1 < _data.length) {
      var child = pos * 2 + 1;
      if (child + 1 < _data.length &&
          _data[child + 1].score < _data[child].score) child++;
      if (last.score <= _data[child].score) {
        break;
      }
      _data[pos] = _data[child];
      pos = child;
    }
    _data[pos] = last;
    return first;
  }
}
