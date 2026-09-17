import 'package:flutter/material.dart';

import '../models.dart';
import '../services/fund_api.dart';
import '../services/market_api.dart';
import 'common.dart';
import 'fund_detail_page.dart';

/// 基金排行页：场内 / 场外双榜。
///
/// - 场内基金（ETF/LOF）：实时成交价涨跌幅排行（行情接口，非昨日净值口径）；
/// - 场外基金：最新披露净值日增长率排行（全市场剔除场内代码），
///   每次进入页面刷新缓存，支持涨幅/跌幅榜与主题关键词筛选（客户端过滤）。
class RankPage extends StatefulWidget {
  const RankPage({super.key});

  @override
  State<RankPage> createState() => _RankPageState();
}

class _RankPageState extends State<RankPage> {
  /// 主题筛选：（名称关键词, 显示名）。
  static const _themes = <(String, String)>[
    ('', '全部'),
    ('科技', '科技'),
    ('半导体', '半导体'),
    ('医药', '医药'),
    ('消费', '消费'),
    ('金融', '金融'),
    ('新能源', '新能源'),
    ('军工', '军工'),
    ('黄金', '黄金'),
    ('债', '债券'),
    ('港股', '港股'),
    ('纳指', '纳指'),
  ];

  /// 全市场涨跌分布统计缓存（避免重复拉取）。
  static FundRankStats? _statsCache;

  int _tab = 0; // 0 场内 / 1 场外
  bool _asc = false; // false 涨幅榜 / true 跌幅榜
  String _kw = ''; // 当前主题关键词（空=全部）

  final List<FundRankItem> _intradayAll = [];
  final List<FundRankItem> _otcAll = [];
  final Set<int> _loadedTabs = {};
  List<FundRankItem> _items = [];
  FundRankStats? _stats;
  bool _loading = false;
  String? _error;
  String? _statsError;

  @override
  void initState() {
    super.initState();
    _loadStats();
    _loadTab();
  }

  List<FundRankItem> get _source => _tab == 0 ? _intradayAll : _otcAll;

  Future<void> _loadTab() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      if (_tab == 0) {
        final all = await MarketApi.etfList();
        if (!mounted) return;
        _intradayAll
          ..clear()
          ..addAll(all);
      } else {
        // 场外 = 全市场剔除场内代码；场内列表尚未加载时先拉（做差集用）。
        if (_intradayAll.isEmpty && !_loadedTabs.contains(0)) {
          try {
            final all = await MarketApi.etfList();
            if (!mounted) return;
            _intradayAll
              ..clear()
              ..addAll(all);
            _loadedTabs.add(0);
          } catch (_) {} // 场内拉取失败时降级：场外榜不剔除。
        }
        final exclude = {for (final e in _intradayAll) e.code};
        final all = await FundApi.rankOtc(excludeCodes: exclude);
        if (!mounted) return;
        _otcAll
          ..clear()
          ..addAll(all);
      }
      _loadedTabs.add(_tab);
      setState(() {
        _loading = false;
        if (_source.isEmpty) _error = '暂无排行数据';
      });
      _applyFilter();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '排行获取失败，请检查网络';
      });
    }
  }

  /// 客户端过滤 + 排序（切换主题/涨跌榜/榜单不重新请求）。
  void _applyFilter() {
    final kw = _kw;
    final src = _source;
    final filtered = kw.isEmpty
        ? List<FundRankItem>.of(src)
        : [for (final e in src) if (e.name.contains(kw)) e];
    filtered.sort((a, b) =>
        _asc ? a.pct.compareTo(b.pct) : b.pct.compareTo(a.pct));
    if (!mounted) return;
    setState(() => _items = filtered);
  }

  void _switchTab(int tab) {
    if (_tab == tab) return;
    setState(() => _tab = tab);
    if (_loadedTabs.contains(tab)) {
      _applyFilter();
    } else {
      _loadTab();
    }
  }

  /// 全市场涨跌分布统计。
  Future<void> _loadStats() async {
    if (_statsCache != null) {
      setState(() => _stats = _statsCache);
      return;
    }
    try {
      final s = await FundApi.rankStats();
      _statsCache = s;
      if (mounted) setState(() => _stats = s);
    } catch (_) {
      if (mounted) setState(() => _statsError = '全市场统计加载失败');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('基金排行'),
        actions: [
          IconButton(
              icon: const Icon(Icons.refresh), tooltip: '刷新', onPressed: () {
            _loadTab();
            _loadStats();
          }),
        ],
      ),
      body: Column(
        children: [
          _StatsCard(
            stats: _stats,
            error: _statsError,
            onRetry: _loadStats,
          ),
          // 场内 / 场外榜单切换。
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: SizedBox(
              width: double.infinity,
              child: SegmentedButton<int>(
                segments: const [
                  ButtonSegment(
                    value: 0,
                    icon: Icon(Icons.candlestick_chart, size: 17),
                    label: Text('场内基金'),
                  ),
                  ButtonSegment(
                    value: 1,
                    icon: Icon(Icons.account_balance, size: 17),
                    label: Text('场外基金'),
                  ),
                ],
                selected: {_tab},
                showSelectedIcon: false,
                style: ButtonStyle(
                  visualDensity: VisualDensity.compact,
                  textStyle: WidgetStatePropertyAll(TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).colorScheme.onSurface)),
                ),
                onSelectionChanged: (sel) => _switchTab(sel.first),
              ),
            ),
          ),
          // 涨跌榜切换 + 类型筛选：单行横滑，避免窄屏堆叠。
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              children: [
                ChoiceChip(
                  label: const Text('涨幅榜'),
                  avatar: Icon(Icons.trending_up,
                      size: 16, color: upDownColor(1, context)),
                  selected: !_asc,
                  visualDensity: VisualDensity.compact,
                  onSelected: (_) {
                    if (!_asc) return;
                    setState(() => _asc = false);
                    _applyFilter();
                  },
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  label: const Text('跌幅榜'),
                  avatar: Icon(Icons.trending_down,
                      size: 16, color: upDownColor(-1, context)),
                  selected: _asc,
                  visualDensity: VisualDensity.compact,
                  onSelected: (_) {
                    if (_asc) return;
                    setState(() => _asc = true);
                    _applyFilter();
                  },
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 4),
                  child: VerticalDivider(width: 1),
                ),
                const SizedBox(width: 4),
                for (final (kw, label) in _themes)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(label, style: const TextStyle(fontSize: 12.5)),
                      selected: _kw == kw,
                      visualDensity: VisualDensity.compact,
                      onSelected: (_) {
                        if (_kw == kw) return;
                        setState(() => _kw = kw);
                        _applyFilter();
                      },
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        children: [
                          const SizedBox(height: 120),
                          EmptyView(
                            icon: Icons.leaderboard_outlined,
                            title: _error!,
                            subtitle: '下拉刷新或点击右上角刷新按钮',
                          ),
                        ],
                      )
                    : RefreshIndicator(
                        onRefresh: _loadTab,
                        child: ListView.builder(
                          physics: const AlwaysScrollableScrollPhysics(),
                          itemCount: _items.length,
                          itemBuilder: (context, i) =>
                              _RankTile(index: i, item: _items[i]),
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}

/// 全市场涨跌分布统计卡。
class _StatsCard extends StatelessWidget {
  const _StatsCard({required this.stats, required this.error, required this.onRetry});

  final FundRankStats? stats;
  final String? error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final s = stats;
    return InfoCard(
      child: s == null
          ? Row(
              children: [
                Text(error ?? '全市场涨跌分布获取中…',
                    style: TextStyle(fontSize: 12.5, color: scheme.outline)),
                const Spacer(),
                if (error != null)
                  TextButton(onPressed: onRetry, child: const Text('重试')),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text('全市场涨跌分布',
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                    const SizedBox(width: 6),
                    Text('共 ${s.total} 只',
                        style: TextStyle(fontSize: 11, color: scheme.outline)),
                    const Spacer(),
                    Text('均值 ${pctText(s.avg)}',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: upDownColor(s.avg, context),
                            fontFeatures: const [FontFeature.tabularFigures()])),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    _Num('上涨', s.up, upDownColor(1, context)),
                    _Num('平盘', s.flat, scheme.outline),
                    _Num('下跌', s.down, upDownColor(-1, context)),
                  ],
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: SizedBox(
                    height: 7,
                    child: Row(
                      children: [
                        Expanded(flex: s.up, child: ColoredBox(color: upDownColor(1, context))),
                        Expanded(
                          flex: s.flat == 0 ? 0 : 1,
                          child: ColoredBox(color: scheme.outlineVariant),
                        ),
                        Expanded(flex: s.down, child: ColoredBox(color: upDownColor(-1, context))),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '场内按实时成交价 · 场外按最新披露净值日涨跌幅',
                  style: TextStyle(fontSize: 10.5, color: scheme.outline),
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
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
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

class _RankTile extends StatelessWidget {
  const _RankTile({required this.index, required this.item});

  final int index;
  final FundRankItem item;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final rank = index + 1;
    final rankColor = switch (rank) {
      1 => const Color(0xFFE5A400),
      2 => const Color(0xFF9AA7B5),
      3 => const Color(0xFFB87A50),
      _ => scheme.outline,
    };
    // 场内基金 navDate 为空：实时成交价口径；场外为净值日涨跌幅口径。
    final realtime = item.navDate.isEmpty;
    return InkWell(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => FundDetailPage(code: item.code)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        child: Row(
          children: [
            SizedBox(
              width: 30,
              child: Text(
                '$rank',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: rankColor,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 14.5, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(
                    realtime
                        ? '${item.code} · 实时价 ${fmtPrice(item.nav)}'
                        : '${item.code} · ${item.navDate} 净值 ${fmtPrice(item.nav)}',
                    style: TextStyle(
                        fontSize: 11.5,
                        color: scheme.outline,
                        fontFeatures: const [FontFeature.tabularFigures()]),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            PctText(item.pct, fontSize: 16),
          ],
        ),
      ),
    );
  }
}
