import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vela_shuo/src/home/maritime_route.dart';
import 'package:vela_shuo/src/home/world_atlas.dart';

void main() {
  test('Beijing to Tokyo painted route stays offshore via the Yellow Sea',
      () {
    const route=VelaMaritimeRoute(
      from: VelaMaritimeRoute.homePort,
      to: Offset(139.69,35.68));
    expect(route.oceanWaypoints.first.dx, greaterThan(117.5));
    expect(route.oceanWaypoints.last.dx, greaterThan(139.0));
    expect(route.oceanWaypoints.last.dy, lessThan(35.5));
    expect(route.oceanWaypoints.any((p) =>
        p.dx >= 124 && p.dx <= 127 && p.dy <= 35), isTrue);
    final controls=route.oceanWaypoints;
    for (var i=1;i<controls.length;i++) {
      expect(controls[i].dx, greaterThan(controls[i-1].dx));
    }
  });

  test('boat exactly follows continuous curved, screen-projected paint path',
      () {
    const camera=VelaWorldCamera(size: Size(1672,941),
      longitude: 116.4,latitude:39.9,oilIllustration:true);
    const route=VelaMaritimeRoute(
      from: VelaMaritimeRoute.homePort,
      to: Offset(139.69,35.68));
    final full=route.oceanPath(camera.projectArtwork);
    final metrics=full.computeMetrics().toList();
    expect(metrics.length,1);
    final metric=metrics.single;
    for (final t in [.05,.2,.5,.73,.95]) {
      final fromRender=metric.getTangentForOffset(metric.length*t);
      final slice=route.oceanPath(camera.projectArtwork,until:t);
      expect(fromRender,isNotNull);
      expect((slice.computeMetrics().first.length-metric.length*t).abs(),
          lessThan(1.2));
    }
    final source=File('lib/src/home/world_atlas.dart').readAsStringSync();
    expect(source,contains('final tangent = metric.getTangentForOffset('));
    expect(source,contains('final routePath = route.oceanPath(geoProject)'));
    expect(source,isNot(contains('canvas.drawCircle(boat, 25')));
  });

  test('original painted atlas blur is repaired before night render on CI',
      () {
    final script=File('scripts/repair_oil_background.py')
      .readAsStringSync();
    final workflow=File('.github/workflows/vela-host-flclash-core.yml')
      .readAsStringSync();
    expect(script,contains('cv2.inpaint('));
    expect(script,contains('oil_map_clean.webp'));
    expect('python3 scripts/repair_oil_background.py'.allMatches(workflow)
      .length,2);
    expect(workflow,contains('python scripts/repair_oil_background.py'));
    expect(workflow,contains('versionCode=\'48\' versionName=\'1.8.14\''));
  });
}
