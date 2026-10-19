import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/services.dart';

/// Shortest visible blue-water passage through the actual illustrated ocean.
/// Grid data is generated from the final shipped oil image at build time.
/// Routes are decorative, never real-world maritime navigation instructions.
class VelaPaintedOceanRoute {
  VelaPaintedOceanRoute._();
  static final VelaPaintedOceanRoute instance = VelaPaintedOceanRoute._();
  static const int columns = 120;
  static const int rows = 68;
  static const double imageWidth = 1672;
  static const double imageHeight = 941;
  List<String> _cells = const [];
  Future<void>? _loading;
  final Map<String, List<Offset>> _cache = {};

  bool get ready => _cells.length == rows;

  Future<void> initialize() => _loading ??= _load();

  Future<void> _load() async {
    try {
      final text = await rootBundle.loadString('assets/oil/oil_sea_grid.txt');
      final cells = text.trim().split('\n');
      if (cells.length != rows ||
          cells.any((line) => line.length != columns ||
              !RegExp(r'^[01]+$').hasMatch(line))) {
        throw const FormatException('Invalid oil sea grid');
      }
      _cells = cells;
      _cache.clear();
    } catch (_) {
      // Never draw an unverified, potentially overland fallback route.
      _cells = const [];
      _loading = null;
    }
  }

  static int _wrap(int x) => (x % columns + columns) % columns;
  static int _id(int x, int y) => y * columns + _wrap(x);
  bool _water(int x, int y) => y >= 0 && y < rows &&
      _cells[y][_wrap(x)] == '1';
  static Offset _point(int id) => Offset(
      ((id % columns) + .5) * imageWidth / columns,
      ((id ~/ columns) + .5) * imageHeight / rows);

  int _nearest(Offset point) {
    final cx = _wrap((point.dx / imageWidth * columns).floor());
    final cy = (point.dy / imageHeight * rows).floor().clamp(0, rows - 1);
    var best = -1;
    var bestD = double.infinity;
    // Nearest painted seawater, never a city inland or a painted mountain.
    for (var y = 0; y < rows; y++) {
      for (var x = 0; x < columns; x++) {
        if (!_water(x, y)) continue;
        final center = _point(_id(x, y));
        final dx0 = (center.dx - point.dx).abs() % imageWidth;
        final dx = math.min(dx0, imageWidth - dx0);
        final dy = center.dy - point.dy;
        final distance = dx * dx + dy * dy;
        if (distance < bestD) {
          bestD = distance;
          best = _id(x, y);
        }
      }
    }
    // A missing sea within this distance means the location is unsupported.
    return bestD < 260 * 260 ? best : -1;
  }

  static double _estimate(int a, int b) {
    final ax = a % columns, bx = b % columns;
    final dx = (ax - bx).abs();
    return math.sqrt(math.pow(math.min(dx, columns - dx), 2) +
        math.pow(a ~/ columns - b ~/ columns, 2));
  }

  List<Offset> routePixels(Offset startPoint, Offset endPoint) {
    if (!ready) return const [];
    final start = _nearest(startPoint), end = _nearest(endPoint);
    if (start < 0 || end < 0) return const [];
    final key = '$start:$end';
    if (_cache.containsKey(key)) return _cache[key]!;
    final parents = List<int>.filled(columns * rows, -1);
    final scores = List<double>.filled(
        columns * rows, double.infinity);
    final closed = List<bool>.filled(columns * rows, false);
    final queue = _RouteHeap()
      ..push(start, _estimate(start, end));
    scores[start] = 0;
    const steps = <(int, int)>[
      (-1,0),(1,0),(0,-1),(0,1),
      (-1,-1),(-1,1),(1,-1),(1,1),
    ];
    while (queue.isNotEmpty) {
      final current = queue.pop();
      if (closed[current]) continue;
      closed[current] = true;
      if (current == end) break;
      final x = current % columns, y = current ~/ columns;
      for (final (dx, dy) in steps) {
        final yy = y + dy, xx = _wrap(x + dx);
        if (!_water(xx, yy)) continue;
        if (dx != 0 && dy != 0 &&
            (!_water(xx, y) || !_water(x, yy))) continue;
        final next = _id(xx, yy);
        if (closed[next]) continue;
        final score = scores[current] + (dx == 0 || dy == 0 ? 1 : math.sqrt2);
        if (score >= scores[next]) continue;
        scores[next] = score;
        parents[next] = current;
        queue.push(next, score + _estimate(next, end));
      }
    }
    if (start != end && parents[end] == -1) {
      _cache[key] = const [];
      return const [];
    }
    final ids = <int>[end];
    while (ids.last != start) {
      ids.add(parents[ids.last]);
    }
    // Keep sea-tested vertices: smoothing the polyline would cut coastlines.
    final route = ids.reversed.map(_point).toList(growable: false);
    _cache[key] = route;
    return route;
  }
}

class _RouteHeap {
  final List<(int, double)> _values = [];
  bool get isNotEmpty => _values.isNotEmpty;
  void push(int id, double priority) {
    var i = _values.length;
    _values.add((id, priority));
    while (i > 0) {
      final parent = (i - 1) ~/ 2;
      if (_values[parent].$2 <= priority) break;
      _values[i] = _values[parent];
      i = parent;
    }
    _values[i] = (id, priority);
  }

  int pop() {
    final root = _values.first.$1;
    final last = _values.removeLast();
    if (_values.isEmpty) return root;
    var i = 0;
    while (2 * i + 1 < _values.length) {
      var child = 2 * i + 1;
      if (child + 1 < _values.length &&
          _values[child + 1].$2 < _values[child].$2) {
        child++;
      }
      if (last.$2 <= _values[child].$2) break;
      _values[i] = _values[child];
      i = child;
    }
    _values[i] = last;
    return root;
  }
}
