import 'package:flutter/material.dart';

import 'vela_subscription_controller.dart';

/// Shared UI for Windows and Android node search/favorite filtering.
/// The surrounding page owns the node tiles, so selected index remains the
/// unmodified index in the validated subscription.
class VelaNodeFilterPanel extends StatefulWidget {
  const VelaNodeFilterPanel({
    super.key,
    required this.controller,
    required this.builder,
    this.order,
  });

  final VelaSubscriptionController controller;
  final List<int>? order;
  final Widget Function(BuildContext, List<int>) builder;

  @override
  State<VelaNodeFilterPanel> createState() => _VelaNodeFilterPanelState();
}

class _VelaNodeFilterPanelState extends State<VelaNodeFilterPanel> {
  final TextEditingController _search = TextEditingController();
  bool _favoritesOnly = false;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.controller,
    builder: (context, _) {
      final indices = widget.controller.visibleNodeIndices(
        query: _search.text,
        favoritesOnly: _favoritesOnly,
        order: widget.order,
      );
      final theme = Theme.of(context);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            key: const ValueKey('node_search_input'),
            controller: _search,
            maxLength: 80,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              isDense: true,
              hintText: '搜索节点名称或协议',
              prefixIcon: const Icon(Icons.search_rounded),
              border: const OutlineInputBorder(),
              counterText: '',
              suffixIcon: _search.text.isEmpty ? null : IconButton(
                key: const ValueKey('node_search_clear'),
                tooltip: '清除搜索',
                onPressed: () {
                  _search.clear();
                  setState(() {});
                },
                icon: const Icon(Icons.close_rounded),
              ),
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 9),
          Wrap(
            spacing: 12,
            runSpacing: 3,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              FilterChip(
                key: const ValueKey('node_favorites_only'),
                label: Text('仅收藏 (${widget.controller.favoriteCount})'),
                selected: _favoritesOnly,
                onSelected: (selected) =>
                    setState(() => _favoritesOnly = selected),
                avatar: const Icon(Icons.star_rounded, size: 17),
              ),
              Text('显示 ${indices.length} / ${widget.controller.nodes.length} 个节点',
                style: theme.textTheme.bodySmall),
            ],
          ),
          const SizedBox(height: 8),
          if (indices.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 18),
              child: Text('没有匹配的节点，可清除搜索或关闭「仅收藏」'),
            )
          else
            widget.builder(context, indices),
        ],
      );
    },
  );
}
