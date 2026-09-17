import 'package:flutter/material.dart';

import '../models.dart';
import '../services/index_info.dart';
import '../services/market_api.dart';
import 'common.dart';

/// 指数详情页：实时指标、区间表现、分时 / 日 K 走势与指数档案介绍。
class IndexDetailPage extends StatefulWidget {
  const IndexDetailPage({
    super.key,
    required this.secid,
    required this.name,
    required this.group,
  });

  final String secid;
  final String name;

  /// 宽基 / 风格 / 行业 / 港股。
  final String group;

  @override
  State<IndexDetailPage> createState() => _IndexDetailPageState();
}

class _IndexDetailPageState extends State<IndexDetailPage> {
  IndexQuoteDetail? _q;
  List<TrendPoint> _trend = [];
  double _preClose = 0;
  List<IndexKline> _kline = [];
  String? _error;
  bool _loading = true;
  int _rangeDays = 250;

  bool get _isHK => widget.group == '港股';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    // 详情为主数据（失败整体重试）；日 K 与分时为辅助数据，失败时降级为空。
    final emptyTrend = (points: <TrendPoint>[], preClose: 0.0);
    try {
      final results = await Future.wait<Object?>([
        MarketApi.indexQuoteDetail(widget.secid),
        MarketApi.indexKline(widget.secid)
            .catchError((Object e) => <IndexKline>[]),
        MarketApi.trend(widget.secid).catchError((Object e) => emptyTrend),
      ]);
      if (!mounted) return;
      final detail = results[0] as IndexQuoteDetail;
      final ks = results[1] as List<IndexKline>;
      final t = results[2] as ({List<TrendPoint> points, double preClose});
      setState(() {
        _q = detail;
        _kline = ks;
        _trend = t.points;
        _preClose = t.preClose;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e'.replaceFirst('Exception: ', '');
        _loading = false;
      });
    }
  }

  // ---------- 区间收益 ----------

  double? _periodReturn(int sessions) {
    if (_kline.length < sessions + 1) return null;
    final past = _kline[_kline.length - 1 - sessions].close;
    if (past <= 0) return null;
    return (_kline.last.close / past - 1) * 100;
  }

  double? get _ytdReturn {
    final year = _kline.isNotEmpty ? _kline.last.date.substring(0, 4) : '';
    for (final k in _kline) {
      if (k.date.startsWith('$year-')) {
        if (k.close <= 0) return null;
        return (_kline.last.close / k.close - 1) * 100;
      }
    }
    return null;
  }

  /// 以日 K 计算的近一年高低点（比接口 f174/f175 对港股更可靠）。
  ({double high, double low})? get _yearHL {
    if (_kline.isEmpty) return null;
    final seg = _kline.length > 244 ? _kline.sublist(_kline.length - 244) : _kline;
    var h = seg.first.high, l = seg.first.low;
    for (final k in seg) {
      if (k.high > h) h = k.high;
      if (k.low < l) l = k.low;
    }
    return (high: h, low: l);
  }

  // ---------- 单位格式化 ----------

  /// A 股指数成交量单位为手；港股指数为股。
  String _fmtVolume(double v) {
    if (v <= 0) return '--';
    if (_isHK) {
      return v >= 1e8
          ? '${(v / 1e8).toStringAsFixed(2)} 亿股'
          : '${(v / 1e4).toStringAsFixed(0)} 万股';
    }
    return v >= 1e8
        ? '${(v / 1e8).toStringAsFixed(2)} 亿手'
        : '${(v / 1e4).toStringAsFixed(0)} 万手';
  }

  String _fmtAmount(double v) {
    if (v <= 0) return '--';
    final cur = _isHK ? '港元' : '元';
    if (v >= 1e12) return '${(v / 1e12).toStringAsFixed(2)} 万亿$cur';
    return '${(v / 1e8).toStringAsFixed(2)} 亿$cur';
  }

  String _fmtMv(double v) {
    if (v <= 0) return '--';
    if (v >= 1e12) return '${(v / 1e12).toStringAsFixed(2)} 万亿元';
    return '${(v / 1e8).toStringAsFixed(0)} 亿元';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.name, style: const TextStyle(fontSize: 17)),
        actions: [
          IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: '刷新',
              onPressed: _loading ? null : _load),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: [
                    const SizedBox(height: 120),
                    EmptyView(
                      icon: Icons.show_chart,
                      title: _error!,
                      subtitle: '点击右上角刷新重试',
                    ),
                  ],
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 6, 16, 28),
                    children: [
                      _buildHeader(scheme),
                      const SizedBox(height: 12),
                      _buildMetrics(scheme),
                      const SizedBox(height: 12),
                      _buildPeriodReturns(scheme),
                      const SizedBox(height: 12),
                      _buildTrendCard(scheme),
                      const SizedBox(height: 12),
                      _buildKlineCard(scheme),
                      const SizedBox(height: 12),
                      _buildIntro(scheme),
                    ],
                  ),
                ),
    );
  }

  Widget _buildHeader(ColorScheme scheme) {
    final q = _q!;
    final pct = q.pct;
    final time = q.quoteTimeMs > 0
        ? DateTime.fromMillisecondsSinceEpoch(q.quoteTimeMs * 1000)
        : null;
    final hhmm = time == null
        ? ''
        : '${time.year}-${time.month.toString().padLeft(2, '0')}-'
            '${time.day.toString().padLeft(2, '0')} '
            '${time.hour.toString().padLeft(2, '0')}:'
            '${time.minute.toString().padLeft(2, '0')}';
    return InfoCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: scheme.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(5),
                ),
                child: Text(widget.group,
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: scheme.primary)),
              ),
              const SizedBox(width: 8),
              Text(q.code.isNotEmpty ? q.code : widget.secid,
                  style: TextStyle(fontSize: 12, color: scheme.outline)),
              const Spacer(),
              if (hhmm.isNotEmpty)
                Text(hhmm,
                    style:
                        TextStyle(fontSize: 11, color: scheme.outline)),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            fmtPrice(q.price),
            style: TextStyle(
              fontSize: 33,
              fontWeight: FontWeight.w600,
              color: upDownColor(pct, context),
              letterSpacing: -0.8,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Text(
                '${pct > 0 ? '+' : ''}${q.change.toStringAsFixed(2)}',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: upDownColor(pct, context),
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(width: 10),
              PctText(pct, fontSize: 15),
            ],
          ),
        ],
      ),
    );
  }

  /// 实时行情指标网格。
  Widget _buildMetrics(ColorScheme scheme) {
    final q = _q!;
    final hl = _yearHL;
    final distHigh = hl != null && hl.high > 0
        ? (q.price / hl.high - 1) * 100
        : double.nan;
    final distLow = hl != null && hl.low > 0
        ? (q.price / hl.low - 1) * 100
        : double.nan;
    final items = <(String, String, Color?)>[
      ('今开', q.open > 0 ? fmtPrice(q.open) : '--',
          _vsColor(q.open, q.preClose)),
      ('昨收', q.preClose > 0 ? fmtPrice(q.preClose) : '--', null),
      ('最高', q.high > 0 ? fmtPrice(q.high) : '--',
          _vsColor(q.high, q.preClose)),
      ('最低', q.low > 0 ? fmtPrice(q.low) : '--',
          _vsColor(q.low, q.preClose)),
      ('振幅', q.amplitude > 0 ? '${q.amplitude.toStringAsFixed(2)}%' : '--', null),
      ('成交量', _fmtVolume(q.volume), null),
      ('成交额', _fmtAmount(q.amount), null),
      if (q.turnoverRate > 0) ('换手率', '${q.turnoverRate.toStringAsFixed(2)}%', null),
      if (q.volumeRatio > 0) ('量比', q.volumeRatio.toStringAsFixed(2), null),
      if (q.totalMv > 0) ('成分总市值', _fmtMv(q.totalMv), null),
      if (q.floatMv > 0) ('流通市值', _fmtMv(q.floatMv), null),
      if (hl != null) ('近一年最高', fmtPrice(hl.high), null),
      if (hl != null) ('距年高', pctText(distHigh), upDownColor(distHigh, context)),
      if (hl != null) ('近一年最低', fmtPrice(hl.low), null),
      if (hl != null) ('距年低', pctText(distLow), upDownColor(distLow, context)),
    ];
    return InfoCard(
      padding: const EdgeInsets.fromLTRB(4, 12, 4, 12),
      child: Column(
        children: [
          _cardTitle(scheme, Icons.grid_view_outlined, '行情指标'),
          LayoutBuilder(
            builder: (context, constraints) {
              // 单元格高度固定约 62px，按实际宽度反算比例，宽屏下不拉高格子。
              const spacing = 10.0;
              final cellW =
                  (constraints.maxWidth - spacing * 2) / 3;
              return GridView.count(
                crossAxisCount: 3,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: spacing,
                crossAxisSpacing: spacing,
                childAspectRatio: cellW / 62,
                children: [
                  for (final (label, value, color) in items)
                    _MetricCell(
                        label: label, value: value, valueColor: color),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Color? _vsColor(double v, double base) {
    if (v <= 0 || base <= 0 || (v - base).abs() < 0.005) return null;
    return upDownColor(v > base ? 1 : -1, context);
  }

  /// 区间涨跌幅。
  Widget _buildPeriodReturns(ColorScheme scheme) {
    final specs = <(String, double?)>[
      ('近5日', _periodReturn(5)),
      ('近20日', _periodReturn(20)),
      ('近60日', _periodReturn(60)),
      ('近120日', _periodReturn(120)),
      ('今年以来', _ytdReturn),
      ('近1年', _kline.length > 244 ? _periodReturn(243) : _periodReturn(_kline.length - 1)),
    ];
    return InfoCard(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _cardTitle(scheme, Icons.date_range_outlined, '区间涨跌幅'),
          const SizedBox(height: 8),
          Row(
            children: [
              for (var i = 0; i < specs.length; i++) ...[
                Expanded(
                  child: Column(
                    children: [
                      Text(specs[i].$2 == null
                          ? '--'
                          : pctText(specs[i].$2!)),
                      const SizedBox(height: 4),
                      Text(specs[i].$1,
                          style: TextStyle(
                              fontSize: 11, color: scheme.outline)),
                    ],
                  ),
                ),
                if (i < specs.length - 1)
                  Container(width: 1, height: 26, color: scheme.outlineVariant),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTrendCard(ColorScheme scheme) {
    return InfoCard(
      padding: const EdgeInsets.fromLTRB(8, 12, 8, 12),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: _cardTitle(scheme, Icons.timeline, '当日分时'),
          ),
          const SizedBox(height: 6),
          _trend.length < 2
              ? SizedBox(
                  height: 200,
                  child: Center(
                    child: Text('分时数据暂不可用',
                        style:
                            TextStyle(color: scheme.outline, fontSize: 13)),
                  ),
                )
              : TrendChart(
                  points: _trend,
                  base: _preClose > 0 ? _preClose : _q!.preClose,
                  height: 220,
                ),
        ],
      ),
    );
  }

  Widget _buildKlineCard(ColorScheme scheme) {
    final data = [
      for (final k in _kline)
        [
          DateTime.parse(k.date).millisecondsSinceEpoch.toDouble(),
          k.close,
        ]
    ];
    return InfoCard(
      padding: const EdgeInsets.fromLTRB(8, 12, 8, 12),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: [
                _cardTitle(scheme, Icons.candlestick_chart_outlined, '日 K 走势'),
                const Spacer(),
                for (final (label, days) in const [
                  ('1月', 30),
                  ('3月', 90),
                  ('6月', 180),
                  ('1年', 250),
                ])
                  Padding(
                    padding: const EdgeInsets.only(left: 6),
                    child: ChoiceChip(
                      label: Text(label, style: const TextStyle(fontSize: 11.5)),
                      selected: _rangeDays == days,
                      visualDensity: VisualDensity.compact,
                      onSelected: (_) => setState(() => _rangeDays = days),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          data.length < 2
              ? SizedBox(
                  height: 200,
                  child: Center(
                    child: Text('日 K 数据暂不可用',
                        style:
                            TextStyle(color: scheme.outline, fontSize: 13)),
                  ),
                )
              : NavChart(data: data, rangeDays: _rangeDays, height: 220),
        ],
      ),
    );
  }

  Widget _buildIntro(ColorScheme scheme) {
    final info = IndexInfoLib.of(widget.secid, widget.group);
    return InfoCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _cardTitle(scheme, Icons.subject, '指数介绍'),
          const SizedBox(height: 8),
          Text(info.fullName,
              style:
                  const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w600)),
          const SizedBox(height: 10),
          _InfoRow(icon: Icons.apartment_outlined, label: '发布机构', value: info.publisher),
          _InfoRow(icon: Icons.format_list_numbered, label: '样本构成', value: info.constituents),
          _InfoRow(icon: Icons.flag_outlined, label: '基日基点', value: info.baseInfo),
          const SizedBox(height: 10),
          Text(info.summary,
              style: const TextStyle(fontSize: 13, height: 1.7)),
          if (info.tags.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 7,
              runSpacing: 7,
              children: [
                for (final t in info.tags)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                    decoration: BoxDecoration(
                      color: scheme.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Text(t,
                        style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: scheme.primary)),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '指数仅反映成分股整体价格变动，不可直接买卖；'
              '跟踪基金存在跟踪误差与管理费用，历史业绩不代表未来表现，不构成投资建议。',
              style: TextStyle(
                  fontSize: 11.5,
                  height: 1.55,
                  color: scheme.outline),
            ),
          ),
        ],
      ),
    );
  }

  Widget _cardTitle(ColorScheme scheme, IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, size: 16, color: scheme.primary),
        const SizedBox(width: 6),
        Text(text,
            style:
                const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
      ],
    );
  }
}

class _MetricCell extends StatelessWidget {
  const _MetricCell({required this.label, required this.value, this.valueColor});

  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 8),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              maxLines: 1,
              style: TextStyle(fontSize: 11, color: scheme.outline)),
          const SizedBox(height: 3),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              maxLines: 1,
              softWrap: false,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: valueColor ?? scheme.onSurface,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow(
      {required this.icon, required this.label, required this.value});

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 14, color: scheme.outline),
          const SizedBox(width: 6),
          SizedBox(
            width: 62,
            child: Text(label,
                style: TextStyle(fontSize: 12, color: scheme.outline)),
          ),
          Expanded(
            child: Text(value,
                style: const TextStyle(
                    fontSize: 12.5, fontWeight: FontWeight.w600, height: 1.4)),
          ),
        ],
      ),
    );
  }
}
