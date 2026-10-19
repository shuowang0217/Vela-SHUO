import 'package:flutter/material.dart';

/// Responsive subscription gallery. Unlike Wrap (which independently sizes
/// every card), a Table stretches both cards in a desktop row to the natural
/// height of the taller one. A longer '每 15 分钟' metadata wrap must not
/// leave the active airport looking smaller than the neighboring airport.
///
/// There is deliberately no special width, scale or large-font treatment for
/// the active airport: the selected card uses exactly the same geometry.
class VelaAirportCardLayout extends StatelessWidget {
  const VelaAirportCardLayout({
    super.key,
    required this.cards,
    this.gap = 12,
    this.minCardHeight = 180,
  });

  final List<Widget> cards;
  final double gap;
  final double minCardHeight;

  Widget _cell(Widget child) => ConstrainedBox(
    constraints: BoxConstraints(minHeight: minCardHeight),
    child: child,
  );

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      if (cards.isEmpty) return const SizedBox.shrink();
      if (constraints.maxWidth < 680) {
        // On a phone, use one full-width column and identical minimum heights.
        // Text scaling / wrapped metadata can still grow the card as needed.
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < cards.length; i++) ...[
              _cell(cards[i]),
              if (i + 1 < cards.length) SizedBox(height: gap),
            ],
          ],
        );
      }

      // TableRow's fill alignment gives both cards identical outer height,
      // determined by the tallest intrinsic card; no hard maximum or
      // clipping, even when labels wrap or accessibility text grows.
      return Table(
        defaultVerticalAlignment: TableCellVerticalAlignment.fill,
        columnWidths: {
          0: const FlexColumnWidth(),
          1: FixedColumnWidth(gap),
          2: const FlexColumnWidth(),
        },
        children: [
          for (var i = 0; i < cards.length; i += 2) ...[
            if (i > 0)
              TableRow(children: [
                SizedBox(height: gap),
                SizedBox(height: gap),
                SizedBox(height: gap),
              ]),
            TableRow(children: [
              _cell(cards[i]),
              SizedBox(width: gap),
              i + 1 < cards.length
                  ? _cell(cards[i + 1])
                  : const SizedBox.shrink(),
            ]),
          ],
        ],
      );
    },
  );
}
