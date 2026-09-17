import 'package:flutter/material.dart';

import '../models.dart';
import '../services/market_api.dart';
import '../state.dart';
import 'common.dart';
import 'globe_page.dart';
import 'index_detail_page.dart';

/// 大盘页：涨跌分布 + A股指数 + 全球指数。
class MarketPage extends StatefulWidget {
  const MarketPage({super.key});

  @override
  State<MarketPage> createState() => _MarketPageState();
}

class _MarketPageState extends State<MarketPage> {
  @override
  void initState() {
    super.initState();
    _loadTrends();
  }

  Future<void> _loadTrends({bool force = false}) async {
    final app = AppState.shared;
    // A股 + 港股指数加载分时迷你图（全球指数为跨时区行情，不加载）。
    for (final (secid, _) in [...MarketApi.aIndices, ...MarketApi.hkIndices]) {
      await app.loadIndexTrend(secid, force: force);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = AppState.shared;
    return Scaffold(
      body: ListenableBuilder(
        listenable: app,
        builder: (context, _) {
          return RefreshIndicator(
            onRefresh: () async {
              await app.refreshMarket();
              await _loadTrends(force: true);
            },
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.only(bottom: kFloatingNavPadding),
              children: [
                LargeTitleBar(
                  title: '大盘行情',
                  actions: [
                    IconButton(
                      icon: const Icon(Icons.refresh),
                      tooltip: '刷新',
                      onPressed: () {
                        app.refreshMarket();
                        _loadTrends(force: true);
                      },
                    ),
                  ],
                ),
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 2, 16, 4),
                  child: _GlobeSection(),
                ),
                const SizedBox(height: 10),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: _BreadthCard(breadth: app.breadth),
                ),
                const _SectionTitle('A股指数'),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: _IndexGrid(
                    secids: [for (final e in MarketApi.aIndices) e.$1],
                    group: 'A股',
                    onTap: _openDetail,
                  ),
                ),
                const _SectionTitle('港股指数'),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: _IndexGrid(
                    secids: [for (final e in MarketApi.hkIndices) e.$1],
                    group: '港股',
                    onTap: _openDetail,
                  ),
                ),
                const _SectionTitle('全球指数'),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: _IndexGrid(
                    secids: [for (final e in MarketApi.globalIndices) e.$1],
                    group: '全球',
                    onTap: _openDetail,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _openDetail(String secid, String group) {
    final app = AppState.shared;
    final q = app.indexQuotes[secid];
    if (q == null) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => IndexDetailPage(
          secid: secid,
          name: q.name,
          group: group,
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 16, 7),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: scheme.outline,
          letterSpacing: -0.1,
        ),
      ),
    );
  }
}

/// 涨跌分布卡。
class _BreadthCard extends StatelessWidget {
  const _BreadthCard({required this.breadth});

  final MarketBreadth? breadth;

  @override
  Widget build(BuildContext context) {
    final app = AppState.shared;
    final scheme = Theme.of(context).colorScheme;
    final b = breadth;
    return InfoCard(
      child: b == null
          ? SizedBox(
              height: 40,
              child: Center(
                child: Text('涨跌分布获取中…',
                    style: TextStyle(fontSize: 12.5, color: scheme.outline)),
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text('市场涨跌分布',
                        style: TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w600)),
                    const Spacer(),
                    Text(
                      app.marketUpdatedAt == null
                          ? ''
                          : '${app.marketUpdatedAt!.hour.toString().padLeft(2, '0')}:'
                              '${app.marketUpdatedAt!.minute.toString().padLeft(2, '0')}',
                      style: TextStyle(fontSize: 11, color: scheme.outline),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    _Num('上涨', b.up, upDownColor(1, context)),
                    _Num('平盘', b.flat, scheme.outline),
                    _Num('下跌', b.down, upDownColor(-1, context)),
                  ],
                ),
                const SizedBox(height: 10),
                // 比例条
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: SizedBox(
                    height: 8,
                    child: Row(
                      children: [
                        Expanded(
                          flex: b.up,
                          child: ColoredBox(
                              color: upDownColor(1, context)),
                        ),
                        Expanded(
                          flex: b.flat,
                          child: ColoredBox(
                              color: scheme.outlineVariant),
                        ),
                        Expanded(
                          flex: b.down,
                          child: ColoredBox(
                              color: upDownColor(-1, context)),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

class _Num extends StatelessWidget {
  const _Num(this.label, this.value, this.color);

  final String label;
  final int value;
  final Color color;

  @override
  Widget build(BuildContext context) => Expanded(
        child: Column(
          children: [
            Text('$value',
                style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color: color,
                    fontFeatures: const [FontFeature.tabularFigures()])),
            Text(label,
                style: TextStyle(
                    fontSize: 11,
                    color: Theme.of(context).colorScheme.outline)),
          ],
        ),
      );
}

/// 指数卡片网格。
class _IndexGrid extends StatelessWidget {
  const _IndexGrid({
    required this.secids,
    required this.group,
    required this.onTap,
  });

  final List<String> secids;
  final String group;
  final void Function(String, String) onTap;

  @override
  Widget build(BuildContext context) {
    final app = AppState.shared;
    final list =
        secids.map((s) => app.indexQuotes[s]).whereType<IndexQuote>().toList();
    if (list.isEmpty) {
      return InfoCard(
        child: SizedBox(
          height: 44,
          child: Center(
            child: Text('行情加载中…',
                style: TextStyle(
                    fontSize: 12.5,
                    color: Theme.of(context).colorScheme.outline)),
          ),
        ),
      );
    }
    return LayoutBuilder(
      builder: (context, c) {
        // 每行至少 3 个；Web 宽屏随窗口加宽增加列数（每卡理想宽度约 160）。
        final cols = (c.maxWidth / 160).floor().clamp(3, 8);
        final cardW = (c.maxWidth - 10 * (cols - 1)) / cols;
        final compact = cardW < 150; // 窄卡切换为竖排紧凑布局
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: list.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: cols,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: compact ? 1.05 : 1.6,
          ),
          itemBuilder: (context, i) => _IndexCard(
            q: list[i],
            trend: app.indexTrends[list[i].secid] ?? const [],
            compact: compact,
            onTap: () => onTap(list[i].secid, group),
          ),
        );
      },
    );
  }
}

class _IndexCard extends StatelessWidget {
  const _IndexCard({
    required this.q,
    required this.trend,
    required this.onTap,
    this.compact = false,
  });

  final IndexQuote q;
  final List<TrendPoint> trend;
  final VoidCallback onTap;

  /// 窄卡（移动端 3 列）：竖排紧凑布局，不放迷你走势。
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = upDownColor(q.pct, context);
    // App Store 风格：纯白卡片 + 彩色涨跌幅数字（不再整盒染色）。
    final decoration = BoxDecoration(
      color: scheme.surface,
      borderRadius: BorderRadius.circular(14),
    );

    final nameText = Text(q.name,
        style: TextStyle(
            fontSize: compact ? 12.5 : 13,
            fontWeight: FontWeight.w600,
            color: scheme.onSurface),
        maxLines: 1,
        overflow: TextOverflow.ellipsis);
    final priceText = Text(fmtPrice(q.price),
        style: TextStyle(
            fontSize: compact ? 17 : 19,
            fontWeight: FontWeight.w600,
            color: scheme.onSurface,
            height: 1.15,
            letterSpacing: -0.3,
            fontFeatures: const [FontFeature.tabularFigures()]));
    final pctTextWidget = PctText(q.pct, fontSize: compact ? 13 : 14.5);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: EdgeInsets.symmetric(
            horizontal: compact ? 10 : 13, vertical: compact ? 9 : 12),
        decoration: decoration,
        child: compact
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  nameText,
                  const SizedBox(height: 2),
                  priceText,
                  const SizedBox(height: 2),
                  pctTextWidget,
                ],
              )
            : Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        nameText,
                        const SizedBox(height: 3),
                        priceText,
                        const SizedBox(height: 3),
                        pctTextWidget,
                      ],
                    ),
                  ),
                  Sparkline(
                    values: [for (final p in trend) p.value],
                    color: color,
                  ),
                ],
              ),
      ),
    );
  }
}

/// 3D 全球市场子模块：嵌入大盘页顶部，可缩放旋转、显示国家边界，
/// 点击国家查看该国常用指数。
class _GlobeSection extends StatelessWidget {
  const _GlobeSection();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.public, size: 17, color: scheme.primary),
            const SizedBox(width: 6),
            const Text('3D 全球市场',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
            const Spacer(),
            Text('旋转 · 缩放 · 点击国家',
                style: TextStyle(fontSize: 11, color: scheme.outline)),
          ],
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 430,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: const GlobeView(),
          ),
        ),
      ],
    );
  }
}
