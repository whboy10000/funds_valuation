import 'package:flutter/material.dart';

import 'state.dart';
import 'ui/funds_page.dart';
import 'ui/market_page.dart';
import 'ui/rank_page.dart';
import 'ui/sectors_page.dart';
import 'ui/settings_page.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const FundsValuationApp());
}

class FundsValuationApp extends StatefulWidget {
  const FundsValuationApp({super.key});

  @override
  State<FundsValuationApp> createState() => _FundsValuationAppState();
}

class _FundsValuationAppState extends State<FundsValuationApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    AppState.shared.init();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 后台暂停自动刷新，回前台立即刷新一次。
    if (state == AppLifecycleState.resumed) {
      AppState.shared.refreshFunds();
      AppState.shared.refreshMarket();
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppState.shared,
      builder: (context, _) {
        final mode = switch (AppState.shared.themeMode) {
          1 => ThemeMode.light,
          2 => ThemeMode.dark,
          _ => ThemeMode.system,
        };
        return MaterialApp(
          title: '基金实时估值',
          debugShowCheckedModeBanner: false,
          themeMode: mode,
          theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF2A5CAA)),
            useMaterial3: true,
          ),
          darkTheme: ThemeData(
            colorScheme:
                ColorScheme.fromSeed(seedColor: const Color(0xFF7BA5E8), brightness: Brightness.dark),
            useMaterial3: true,
          ),
          home: const HomePage(),
        );
      },
    );
  }
}

/// 自适应外壳：宽屏左侧导航栏，窄屏底部导航。
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _index = 0;

  static const _pages = [
    FundsPage(),
    MarketPage(),
    SectorsPage(),
    RankPage(),
    SettingsPage(),
  ];

  static const _dests = [
    (Icons.query_stats, '估值'),
    (Icons.candlestick_chart_outlined, '大盘'),
    (Icons.grid_view_outlined, '板块'),
    (Icons.leaderboard_outlined, '排行'),
    (Icons.settings_outlined, '设置'),
  ];

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.of(context).size.width >= 900;
    final body = IndexedStack(index: _index, children: _pages);
    if (wide) {
      return Scaffold(
        body: Row(
          children: [
            NavigationRail(
              selectedIndex: _index,
              onDestinationSelected: (i) => setState(() => _index = i),
              labelType: NavigationRailLabelType.all,
              leading: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Column(
                  children: [
                    const SizedBox(height: 6),
                    Icon(
                      Icons.savings_outlined,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ],
                ),
              ),
              destinations: [
                for (final (icon, label) in _dests)
                  NavigationRailDestination(
                    icon: Icon(icon),
                    selectedIcon: Icon(icon, fill: 1),
                    label: Text(label),
                  ),
              ],
            ),
            const VerticalDivider(width: 1),
            Expanded(child: body),
          ],
        ),
      );
    }
    return Scaffold(
      body: body,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: [
          for (final (icon, label) in _dests)
            NavigationDestination(
              icon: Icon(icon),
              selectedIcon: Icon(icon, fill: 1),
              label: label,
            ),
        ],
      ),
    );
  }
}
