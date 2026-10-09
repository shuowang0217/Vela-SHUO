import 'package:flutter/material.dart';
import 'package:vela_shuo/src/settings/settings_controller.dart';

const _ice = Color(0xFF668EAD);

class VelaShuoApp extends StatelessWidget {
  const VelaShuoApp({super.key, required this.settings});

  final SettingsController settings;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: settings,
    builder: (context, _) => MaterialApp(
      title: 'Vela-SHUO',
      debugShowCheckedModeBanner: false,
      themeMode: settings.themeMode,
      theme: _theme(Brightness.light),
      darkTheme: _theme(Brightness.dark),
      home: _Shell(settings: settings),
    ),
  );
}

ThemeData _theme(Brightness brightness) {
  final scheme = ColorScheme.fromSeed(seedColor: _ice, brightness: brightness);
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: scheme.surface,
    cardTheme: CardThemeData(
      elevation: 0,
      color: scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
    ),
  );
}

class _Shell extends StatefulWidget {
  const _Shell({required this.settings});
  final SettingsController settings;

  @override
  State<_Shell> createState() => _ShellState();
}

class _ShellState extends State<_Shell> {
  int _index = 0;

  static const _tabs = [
    (icon: Icons.space_dashboard_outlined, active: Icons.space_dashboard, label: '概览'),
    (icon: Icons.dns_outlined, active: Icons.dns, label: '节点'),
    (icon: Icons.auto_awesome_outlined, active: Icons.auto_awesome, label: '智能'),
    (icon: Icons.tune_outlined, active: Icons.tune, label: '设置'),
  ];

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, limits) {
      final wide = limits.maxWidth >= 740;
      return Scaffold(
        body: Row(
          children: [
            if (wide)
              NavigationRail(
                selectedIndex: _index,
                extended: limits.maxWidth >= 1100,
                onDestinationSelected: (value) => setState(() => _index = value),
                leading: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 22),
                  child: Icon(Icons.blur_on, size: 36),
                ),
                destinations: [
                  for (final tab in _tabs)
                    NavigationRailDestination(
                      icon: Icon(tab.icon),
                      selectedIcon: Icon(tab.active),
                      label: Text(tab.label),
                    ),
                ],
              ),
            Expanded(
              child: SafeArea(
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: wide ? 34 : 17,
                    vertical: wide ? 26 : 14,
                  ),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1080),
                      child: _page(),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        bottomNavigationBar: wide
            ? null
            : NavigationBar(
                selectedIndex: _index,
                onDestinationSelected: (value) => setState(() => _index = value),
                destinations: [
                  for (final tab in _tabs)
                    NavigationDestination(
                      icon: Icon(tab.icon),
                      selectedIcon: Icon(tab.active),
                      label: tab.label,
                    ),
                ],
              ),
      );
    },
  );

  Widget _page() => switch (_index) {
    1 => const _NodesPage(),
    2 => const _SmartPage(),
    3 => _SettingsPage(settings: widget.settings),
    _ => const _OverviewPage(),
  };
}

class _Heading extends StatelessWidget {
  const _Heading(this.title, this.description);
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(title, style: Theme.of(context).textTheme.headlineMedium),
      const SizedBox(height: 6),
      Text(description, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
    ],
  );
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.icon, required this.title, required this.detail});
  final IconData icon;
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) => Card(
    child: ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      leading: Icon(icon, color: Theme.of(context).colorScheme.primary),
      title: Text(title),
      subtitle: Text(detail),
    ),
  );
}

class _OverviewPage extends StatelessWidget {
  const _OverviewPage();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      children: [
        const Row(
          children: [
            Icon(Icons.blur_on, size: 42),
            SizedBox(width: 12),
            Expanded(child: _Heading('Vela-SHUO', 'Connect smarter · by SHUO')),
          ],
        ),
        const SizedBox(height: 26),
        Card(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 38),
            child: Column(
              children: [
                CircleAvatar(
                  backgroundColor: theme.colorScheme.surfaceContainerHighest,
                  radius: 46,
                  child: Icon(Icons.power_settings_new, size: 42, color: theme.colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: 20),
                Text('尚未连接', style: theme.textTheme.headlineSmall),
                const SizedBox(height: 8),
                Text('连接功能将在 v0.2 开放', style: TextStyle(color: theme.colorScheme.onSurfaceVariant)),
                const SizedBox(height: 22),
                FilledButton.icon(
                  onPressed: null,
                  icon: Icon(Icons.lock_outline),
                  label: Text('连接功能尚未开放'),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        const _InfoCard(
          icon: Icons.shield_outlined,
          title: '连接状态 · 未启用',
          detail: '当前是原创界面测试版。尚未集成代理内核、VPN 或网络测速。',
        ),
        const _InfoCard(
          icon: Icons.auto_awesome_outlined,
          title: '智能优选 · 待接入',
          detail: '后续版本将实现真实测速与自动优选，不显示虚构数据。',
        ),
      ],
    );
  }
}

class _NodesPage extends StatelessWidget {
  const _NodesPage();

  @override
  Widget build(BuildContext context) => ListView(
    children: const [
      _Heading('节点', '清晰管理每一次连接'),
      SizedBox(height: 20),
      _InfoCard(
        icon: Icons.dns_outlined,
        title: '还没有节点',
        detail: '订阅导入、节点列表和真实连接将在 v0.2 开放。',
      ),
    ],
  );
}

class _SmartPage extends StatelessWidget {
  const _SmartPage();

  @override
  Widget build(BuildContext context) => ListView(
    children: const [
      _Heading('智能', '更聪明，但始终由你掌控'),
      SizedBox(height: 20),
      _InfoCard(
        icon: Icons.auto_awesome_outlined,
        title: 'SHUO Smart Engine',
        detail: '规划支持稳定优先、多次采样、测速预算、故障恢复及切换保护。',
      ),
      _InfoCard(
        icon: Icons.verified_user_outlined,
        title: '只显示真实结果',
        detail: '接入真实网络内核以后，才会显示可验证的节点分数和测速数据。',
      ),
    ],
  );
}

class _SettingsPage extends StatelessWidget {
  const _SettingsPage({required this.settings});
  final SettingsController settings;

  @override
  Widget build(BuildContext context) => ListView(
    children: [
      const _Heading('设置', '个性化你的 Vela-SHUO'),
      const SizedBox(height: 20),
      Card(
        child: Column(
          children: [
            ListTile(
              leading: const Icon(Icons.color_lens_outlined),
              title: const Text('外观主题'),
              subtitle: const Text('设置自动保存，重启后仍然生效'),
              trailing: DropdownButton<ThemeMode>(
                value: settings.themeMode,
                onChanged: (v) {
                  if (v != null) settings.setThemeMode(v);
                },
                items: const [
                  DropdownMenuItem(value: ThemeMode.system, child: Text('跟随系统')),
                  DropdownMenuItem(value: ThemeMode.light, child: Text('浅色')),
                  DropdownMenuItem(value: ThemeMode.dark, child: Text('深色')),
                ],
              ),
            ),
            const Divider(height: 1),
            const ListTile(
              leading: Icon(Icons.info_outline),
              title: Text('Vela-SHUO v0.1.0'),
              subtitle: Text('原创独立客户端 · 基础框架预览'),
            ),
          ],
        ),
      ),
      const SizedBox(height: 12),
      const _InfoCard(
        icon: Icons.security_outlined,
        title: '隐私与安全',
        detail: '当前版本不申请 VPN 权限，不上传遥测，也不会在后台运行代理服务。',
      ),
    ],
  );
}
