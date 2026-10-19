import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vela_shuo/src/stellar/vela_airport_card_layout.dart';

void main() {
  testWidgets('two desktop airport cards use identical width and height',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 840,
          child: VelaAirportCardLayout(
            cards: [
              const SizedBox(key: Key('active_airport'), height: 138,
                child: ColoredBox(color: Colors.blue)),
              const SizedBox(key: Key('other_airport'), height: 174,
                child: ColoredBox(color: Colors.grey)),
            ],
          ),
        ),
      ),
    ));

    final first = tester.getSize(find.byKey(const Key('active_airport')));
    final second = tester.getSize(find.byKey(const Key('other_airport')));
    expect(first.width, second.width);
    expect(first.height, second.height);
    expect(first.height, greaterThanOrEqualTo(180));
    final a = tester.getTopLeft(find.byKey(const Key('active_airport')));
    final b = tester.getTopLeft(find.byKey(const Key('other_airport')));
    expect(a.dy, b.dy);
    expect(a.dx, lessThan(b.dx));
  });

  testWidgets('more metadata can grow both desktop cards equally',
      (tester) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(
      body: SizedBox(width: 820, child: VelaAirportCardLayout(
        cards: [
          const SizedBox(key: Key('short'), height: 140),
          const SizedBox(key: Key('long'), height: 230),
          const SizedBox(key: Key('third'), height: 140),
        ],
      )),
    )));

    final short = tester.getSize(find.byKey(const Key('short')));
    final long = tester.getSize(find.byKey(const Key('long')));
    final third = tester.getSize(find.byKey(const Key('third')));
    expect(short.height, long.height);
    expect(short.height, 230);
    expect(short.width, third.width);
    // An odd final airport stays in the left half instead of growing to
    // full desktop width.
    expect(tester.getTopLeft(find.byKey(const Key('third'))).dx,
        tester.getTopLeft(find.byKey(const Key('short'))).dx);
  });

  testWidgets('narrow phones use a consistent one-column minimum height',
      (tester) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(
      body: SizedBox(width: 350, child: VelaAirportCardLayout(
        cards: [
          const SizedBox(key: Key('first'), height: 110),
          const SizedBox(key: Key('second'), height: 160),
        ],
      )),
    )));
    final a = tester.getSize(find.byKey(const Key('first')));
    final b = tester.getSize(find.byKey(const Key('second')));
    expect(a.width, b.width);
    expect(a.height, b.height);
    expect(a.height, 180);
    expect(tester.getTopLeft(find.byKey(const Key('second'))).dy,
        greaterThan(tester.getTopLeft(find.byKey(const Key('first'))).dy));
  });
}
