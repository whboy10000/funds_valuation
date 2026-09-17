import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'state.dart';
import 'ui/funds_page.dart';
import 'ui/market_page.dart';
import 'ui/rank_page.dart';
import 'ui/sectors_page.dart';
import 'ui/settings_page.dart';
import 'ui/theme.dart';

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
          theme: buildAppTheme(Brightness.light),
          darkTheme: buildAppTheme(Brightness.dark),
          builder: (context, child) {
            final brightness = Theme.of(context).brightness;
            return AnnotatedRegion<SystemUiOverlayStyle>(
              value: overlayStyleFor(brightness),
              child: ScrollConfiguration(
                behavior: const IosScrollBehavior(),
                child: child!,
              ),
            );
          },
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
    final scheme = Theme.of(context).colorScheme;
    if (wide) {
      return Scaffold(
        body: Row(
          children: [
            NavigationRail(
              selectedIndex: _index,
              onDestinationSelected: (i) => setState(() => _index = i),
              labelType: NavigationRailLabelType.all,
              leading: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Column(
                  children: [
                    const SizedBox(height: 6),
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [Color(0xFFE6221E), Color(0xFF8E0616)],
                        ),
                        borderRadius: BorderRadius.circular(10),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFFE6221E)
                                .withValues(alpha: 0.35),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: const Icon(Icons.trending_up,
                          color: Colors.white, size: 23),
                    ),
                  ],
                ),
              ),
              groupAlignment: -0.9,
              destinations: [
                for (final (icon, label) in _dests)
                  NavigationRailDestination(
                    icon: Icon(icon),
                    selectedIcon: Icon(icon, fill: 1),
                    label: Text(label),
                  ),
              ],
            ),
            VerticalDivider(width: 0.5, color: scheme.outlineVariant),
            Expanded(child: body),
          ],
        ),
      );
    }
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      body: body,
      extendBody: true,
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: scheme.surface,
              borderRadius: BorderRadius.circular(28),
              border: dark
                  ? Border.all(
                      width: 0.5,
                      color: scheme.outlineVariant.withValues(alpha: 0.6))
                  : null,
              boxShadow: [
                BoxShadow(
                  color: Colors.black
                      .withValues(alpha: dark ? 0.5 : 0.12),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(28),
              child: NavigationBar(
                backgroundColor: Colors.transparent,
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
            ),
          ),
        ),
      ),
    );
  }
}
