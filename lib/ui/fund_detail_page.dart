import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models.dart';
import '../services/fund_api.dart';
import '../services/market_api.dart';
import '../state.dart';
import 'common.dart';
import 'funds_page.dart' show showTradeRecords, showTradeSheet;

/// 基金详情页。
class FundDetailPage extends StatefulWidget {
  const FundDetailPage({super.key, required this.code});

  final String code;

  @override
  State<FundDetailPage> createState() => _FundDetailPageState();
}

class _FundDetailPageState extends State<FundDetailPage> {
  FundDetail? _detail;
  bool _detailLoading = true;
  FundProfile? _profile; // f10 档案：概况补充/分红/经理变动
  FundDailyScale? _dailyScale; // 每日规模序列
  int? _range; // 净值区间天数，null=全部

  @override
  void initState() {
    super.initState();
    final app = AppState.shared;
    // 非自选基金（如从排行页进入）先补拉净值/重仓股/估值。
    app.ensureFund(widget.code);
    app.loadDetail(widget.code).then((d) {
      if (mounted) {
        setState(() {
          _detail = d;
          _detailLoading = false;
        });
        _loadDailyScale();
      }
    });
    app.refreshFundHoldingsLive(widget.code);
    // f10 档案懒加载（失败静默，卡片不显示）。
    FundApi.profile(widget.code).then((p) {
      if (mounted && p != null) {
        setState(() => _profile = p);
        _loadDailyScale();
      }
    }).catchError((_) {});
  }

  /// 计算每日规模：场内优先（份额×每日收盘价），场外用最新份额×每日净值。
  Future<void> _loadDailyScale() async {
    final d = _detail;
    if (d == null || _dailyScale != null || !mounted) return;
    final code = widget.code;
    // 场内探测：6 位且 5/1 开头，依次尝试沪/深市场（stock/get 单只接口，
    // ulist 批量对 ETF 份额返回错误值）；价格与份额均有值即场内。
    String? etfSecid;
    Quote? etfQuote;
    if (RegExp(r'^[51]\d{5}$').hasMatch(code)) {
      for (final mkt in const ['1', '0']) {
        try {
          final q = await MarketApi.etfInfo('$mkt.$code');
          if (q.price > 0 && q.share > 0) {
            etfSecid = '$mkt.$code';
            etfQuote = q;
            break;
          }
        } catch (_) {}
      }
    }
    try {
      final r = await FundApi.dailyScale(
        etfSecid: etfSecid,
        quote: etfQuote,
        shareYi: _profile?.shareYi ?? 0,
        navs: d.navTrend,
      );
      if (mounted && r != null) setState(() => _dailyScale = r);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final app = AppState.shared;
    final scheme = Theme.of(context).colorScheme;
    final f = app.funds.where((e) => e.code == widget.code).firstOrNull;

    return Scaffold(
      appBar: AppBar(
        title: Text(_detail?.name ?? f?.name ?? widget.code,
            style: const TextStyle(fontSize: 17)),
        actions: [
          IconButton(
            tooltip: f == null ? '加入自选' : '已在自选',
            icon: Icon(
              f == null ? Icons.add_circle_outline : Icons.check_circle_outline,
              color: f == null ? null : scheme.primary,
            ),
            onPressed: f == null
                ? () {
                    app.addFund(FundSearchHit(
                      code: widget.code,
                      name: (_detail?.name.isNotEmpty ?? false)
                          ? _detail!.name
                          : widget.code,
                      type: '',
                      company: '',
                      manager: '',
                    ));
                    ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('已加入自选')));
                  }
                : null,
          ),
          if (f != null)
            IconButton(
              tooltip: '持仓设置',
              icon: const Icon(Icons.account_balance_wallet_outlined),
              onPressed: () => _editPosition(context, f),
            ),
        ],
      ),
      body: ListenableBuilder(
        listenable: app,
        builder: (context, _) {
          final q2 = app.quoteOf(widget.code);
          return ListView(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 24),
            children: [
              _HeaderCard(q: q2, f: f),
              const SizedBox(height: 12),
              if (f != null) ...[
                _MyHoldingsCard(f: f),
                const SizedBox(height: 12),
              ],
              _EstTrendCard(code: widget.code),
              const SizedBox(height: 12),
              _NavTrendCard(
                detail: _detail,
                loading: _detailLoading,
                range: _range,
                onRange: (r) => setState(() => _range = r),
              ),
              const SizedBox(height: 12),
              if (_detail != null) ...[
                _InfoCard(detail: _detail!),
                const SizedBox(height: 12),
                if (_detail!.rate.isNotEmpty ||
                    _detail!.minsg.isNotEmpty ||
                    _detail!.scales.isNotEmpty ||
                    _detail!.holderInst >= 0 ||
                    (_profile?.fullName.isNotEmpty ?? false)) ...[
                  _ProfileCard(detail: _detail!, profile: _profile),
                  const SizedBox(height: 12),
                ],
                if (_dailyScale != null) ...[
                  _DailyScaleCard(scale: _dailyScale!),
                  const SizedBox(height: 12),
                ],
                if (_detail!.industries.isNotEmpty) ...[
                  _IndustriesCard(detail: _detail!),
                  const SizedBox(height: 12),
                ],
                if (_detail!.radar.isNotEmpty ||
                    _detail!.rankTotal > 0) ...[
                  _RatingCard(detail: _detail!),
                  const SizedBox(height: 12),
                ],
                if (_detail!.volat >= 0) ...[
                  _FeatureCard(detail: _detail!),
                  const SizedBox(height: 12),
                ],
                if (_detail!.alloc.isNotEmpty) ...[
                  _AllocCard(detail: _detail!),
                  const SizedBox(height: 12),
                ],
                if (_detail!.positions.length > 1) ...[
                  _PositionsCard(detail: _detail!),
                  const SizedBox(height: 12),
                ],
                if (_detail!.buyback.isNotEmpty) ...[
                  _BuybackCard(detail: _detail!),
                  const SizedBox(height: 12),
                ],
                if (_detail!.bonds.isNotEmpty) ...[
                  _BondsCard(detail: _detail!),
                  const SizedBox(height: 12),
                ],
                if ((_detail!.navTrend.length) > 5) ...[
                  _NavListCard(detail: _detail!),
                  const SizedBox(height: 12),
                ],
              ],
              if (_profile?.dividends.isNotEmpty ?? false) ...[
                _DividendsCard(profile: _profile!),
                const SizedBox(height: 12),
              ],
              if (_profile?.mgrChanges.isNotEmpty ?? false) ...[
                _MgrChangesCard(profile: _profile!),
                const SizedBox(height: 12),
              ],
              _HoldingsCard(
                q: q2,
                onRefresh: () => app.refreshFundHoldingsLive(widget.code),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// 头部估值卡。
class _HeaderCard extends StatelessWidget {
  const _HeaderCard({required this.q, required this.f});

  final FundQuote? q;
  final dynamic f; // FundItem?

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final has = q != null && q!.hasEst;
    final pct = has ? q!.estPct : double.nan;
    return InfoCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                pctText(pct),
                style: TextStyle(
                  fontSize: 34,
                  fontWeight: FontWeight.w800,
                  color: upDownColor(pct, context),
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              const Spacer(),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    has ? '估算净值 ${q!.estNav.toStringAsFixed(4)}' : '暂无估值',
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    q == null ? '' : '昨收净值 ${q!.nav.toStringAsFixed(4)}'
                    '（${pctText(q!.navPct)}）',
                    style: TextStyle(
                        fontSize: 12,
                        color: scheme.outline,
                        fontFeatures: const [FontFeature.tabularFigures()]),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            has
                ? '自研估值 = 重仓股权重 × 实时行情${q!.stockPosition > 0 ? ' × 仓位${q!.stockPosition.toStringAsFixed(1)}%' : ''}'
                : '该基金无股票持仓或行情不可用，暂不能估值',
            style: TextStyle(fontSize: 11.5, color: scheme.outline),
          ),
        ],
      ),
    );
  }
}

/// 我的持仓卡：金额/收益/收益率/持有天数/关联板块 + 加减仓入口。
class _MyHoldingsCard extends StatelessWidget {
  const _MyHoldingsCard({required this.f});

  final FundItem f;

  @override
  Widget build(BuildContext context) {
    final app = AppState.shared;
    final q = app.quoteOf(f.code);
    final scheme = Theme.of(context).colorScheme;
    final est = q?.hasEst ?? false;
    final mv = f.amount * (1 + (est ? q!.estPct : 0) / 100);
    final todayPnl = est ? f.amount * q!.estPct / 100 : 0.0;
    final totalPnl = f.costAmount > 0 ? mv - f.costAmount : 0.0;
    final totalPct =
        f.costAmount > 0 ? totalPnl / f.costAmount * 100 : double.nan;
    final sec = app.relatedSector(f.code);
    String sign(double v) => v >= 0 ? '+' : '';
    return InfoCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('我的持仓',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
              const Spacer(),
              if (f.holdingDays > 0)
                Text('持有 ${f.holdingDays} 天',
                    style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: scheme.primary)),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _cell(context, '持有金额', fmtMoney(f.amount), scheme.onSurface),
              _cell(
                  context,
                  '今日收益',
                  est ? '${sign(todayPnl)}${fmtMoney(todayPnl)}' : '--',
                  est ? upDownColor(todayPnl, context) : scheme.outline),
              _cell(
                  context,
                  '持仓收益',
                  f.costAmount > 0
                      ? '${sign(totalPnl)}${fmtMoney(totalPnl)}'
                      : '--',
                  f.costAmount > 0
                      ? upDownColor(totalPnl, context)
                      : scheme.outline),
              _cell(
                  context,
                  '收益率',
                  totalPct.isNaN ? '--' : pctText(totalPct),
                  totalPct.isNaN
                      ? scheme.outline
                      : upDownColor(totalPct, context)),
            ],
          ),
          if (sec != null) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Text('关联板块',
                    style: TextStyle(fontSize: 11.5, color: scheme.outline)),
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: sec.$2.isNaN
                        ? scheme.surfaceContainerHighest
                        : upDownTint(sec.$2, context),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '${sec.$1}${sec.$2.isNaN ? '' : '  ${pctText(sec.$2)}'}',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: sec.$2.isNaN
                            ? scheme.onSurfaceVariant
                            : upDownColorDeep(sec.$2, context)),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              OutlinedButton.icon(
                onPressed: () => showTradeSheet(context, f, true),
                icon: const Icon(Icons.add, size: 16),
                label: const Text('加仓'),
                style: OutlinedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  foregroundColor: upDownColor(1, context),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: f.amount > 0
                    ? () => showTradeSheet(context, f, false)
                    : null,
                icon: const Icon(Icons.remove, size: 16),
                label: const Text('减仓'),
                style: OutlinedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  foregroundColor: upDownColor(-1, context),
                ),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: () => showTradeRecords(context, f),
                child: const Text('交易记录'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _cell(BuildContext context, String label, String value, Color color) =>
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(value,
                style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: color,
                    fontFeatures: const [FontFeature.tabularFigures()])),
            const SizedBox(height: 2),
            Text(label,
                style: TextStyle(
                    fontSize: 10.5,
                    color: Theme.of(context).colorScheme.outline)),
          ],
        ),
      );
}

/// 分时估值图：聚合重仓股分时行情加权生成开盘至今的估值曲线。
class _EstTrendCard extends StatefulWidget {
  const _EstTrendCard({required this.code});

  final String code;

  @override
  State<_EstTrendCard> createState() => _EstTrendCardState();
}

class _EstTrendCardState extends State<_EstTrendCard> {
  bool _loading = false;
  bool _triedWhenHoldings = false;
  List<TrendPoint> _pts = const [];

  @override
  void initState() {
    super.initState();
    // 优先使用缓存，无缓存时才拉取。
    final cached = AppState.shared.estTrendCache[widget.code];
    if (cached == null || cached.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _load());
    } else {
      _pts = cached;
    }
  }

  Future<void> _load({bool force = false}) async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      final pts =
          await AppState.shared.loadEstTrend(widget.code, force: force);
      if (mounted) setState(() => _pts = pts);
    } catch (_) {
      if (mounted) setState(() => _pts = const []);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = AppState.shared;
    final scheme = Theme.of(context).colorScheme;
    final q = app.quoteOf(widget.code);

    // 持仓数据是异步加载的，待其就绪后再尝试一次。
    if (!_loading &&
        _pts.isEmpty &&
        !_triedWhenHoldings &&
        (q?.holdings.isNotEmpty ?? false)) {
      _triedWhenHoldings = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _load());
    }

    return InfoCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('分时估值走势',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '（按重仓股分时行情加权聚合，缓存3分钟）',
                  style: TextStyle(fontSize: 11, color: scheme.outline),
                ),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: '刷新',
                icon: _loading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.refresh, size: 18),
                onPressed: _loading ? null : () => _load(force: true),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (_loading && _pts.isEmpty)
            const SizedBox(
                height: 180,
                child: Center(child: CircularProgressIndicator()))
          else if (_pts.isEmpty)
            SizedBox(
              height: 180,
              child: Center(
                child: Text(
                  '暂无分时数据\n（非交易时段、重仓股行情不可用或仍在加载）',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12.5, color: scheme.outline),
                ),
              ),
            )
          else
            TrendChart(
              points: _pts,
              base: 0,
              isPct: true,
              height: 180,
            ),
        ],
      ),
    );
  }
}

/// 历史净值走势。
class _NavTrendCard extends StatelessWidget {
  const _NavTrendCard({
    required this.detail,
    required this.loading,
    required this.range,
    required this.onRange,
  });

  final FundDetail? detail;
  final bool loading;
  final int? range;
  final ValueChanged<int?> onRange;

  static const _ranges = <(String, int?)>[
    ('1月', 30),
    ('3月', 90),
    ('6月', 180),
    ('1年', 365),
    ('全部', null),
  ];

  @override
  Widget build(BuildContext context) {
    return InfoCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('历史净值走势${detail == null ? '' : '（${detail!.name}）'}',
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          if (loading)
            const SizedBox(
                height: 160,
                child: Center(child: CircularProgressIndicator()))
          else
            NavChart(data: detail?.navTrend ?? const [], rangeDays: range),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            children: [
              for (final (label, d) in _ranges)
                ChoiceChip(
                  label: Text(label, style: const TextStyle(fontSize: 12)),
                  selected: range == d,
                  visualDensity: VisualDensity.compact,
                  onSelected: (_) => onRange(d),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 基金信息（经理/仓位/阶段收益）。
class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.detail});

  final FundDetail detail;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InfoCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('基金信息',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          Row(
            children: [
              const Icon(Icons.person_outline, size: 18),
              const SizedBox(width: 6),
              Text(detail.managerName.isEmpty ? '--' : detail.managerName,
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(width: 8),
              starRow(detail.managerStar),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '任职 ${detail.managerWorkTime.isEmpty ? '--' : detail.managerWorkTime}'
            ' · 管理规模 ${detail.managerSize.isEmpty ? '--' : detail.managerSize}',
            style: TextStyle(fontSize: 12, color: scheme.outline),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 14,
            runSpacing: 6,
            children: [
              _SylChip('近1月', detail.syl1m),
              _SylChip('近3月', detail.syl3m),
              _SylChip('近6月', detail.syl6m),
              _SylChip('近1年', detail.syl1y),
              if (detail.positionRatio > 0)
                _SylChip('股票仓位', '${detail.positionRatio.toStringAsFixed(2)}%'),
            ],
          ),
        ],
      ),
    );
  }
}

class _SylChip extends StatelessWidget {
  const _SylChip(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final pctVal = double.tryParse(value);
    final color = pctVal == null
        ? scheme.onSurface
        : upDownColor(pctVal, context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: TextStyle(fontSize: 11, color: scheme.outline)),
        Text(
          value == '--' ? '--' : '$value%',
          style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: color,
              fontFeatures: const [FontFeature.tabularFigures()]),
        ),
      ],
    );
  }
}

/// 重仓股历史季度缓存（code → 季度列表，新→旧）。
final _histCache = <String, List<(String, Map<String, double>)>>{};

/// 重仓股（实时涨跌 + 较上期变化）。
class _HoldingsCard extends StatefulWidget {
  const _HoldingsCard({required this.q, required this.onRefresh});

  final FundQuote? q;
  final VoidCallback onRefresh;

  @override
  State<_HoldingsCard> createState() => _HoldingsCardState();
}

class _HoldingsCardState extends State<_HoldingsCard> {
  String? _prevLabel; // 上期季度标签，如 2026Q1

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    final code = widget.q?.code;
    if (code == null || code.isEmpty || _histCache.containsKey(code)) {
      _applyTags();
      return;
    }
    try {
      final hist = await FundApi.holdingsHistory(code);
      _histCache[code] = hist;
    } catch (_) {
      _histCache[code] = const [];
    }
    if (mounted) _applyTags();
  }

  /// 对比上期重仓：不在上期 → 新进；占比变化显示具体差值（±0.05% 内为持平）。
  void _applyTags() {
    final q = widget.q;
    final code = q?.code;
    if (code == null) return;
    final hist = _histCache[code] ?? const [];
    if (hist.isEmpty) return;
    Map<String, double> prev = const {};
    if (hist.length >= 2) {
      _prevLabel = hist[1].$1;
      prev = hist[1].$2;
    } else {
      _prevLabel = hist[0].$1;
    }
    for (final h in q!.holdings) {
      final old = prev[h.code];
      if (old == null) {
        h.changeTag = '新进';
      } else {
        final d = h.weight - old;
        h.changeTag = d > 0.05
            ? '+${d.toStringAsFixed(1)}%'
            : d < -0.05
                ? '-${d.abs().toStringAsFixed(1)}%'
                : '持平';
      }
    }
    if (mounted) setState(() {});
  }

  Color _tagColor(String tag, BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (tag == '新进') return scheme.tertiary;
    if (tag.startsWith('+')) return upDownColor(1, context);
    if (tag.startsWith('-')) return upDownColor(-1, context);
    return scheme.outline;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final q = widget.q;
    final hs = q?.holdings ?? const <FundHolding>[];
    final wSum = hs.fold<double>(0, (a, b) => a + b.weight);
    return InfoCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('前十大重仓股（合计 ${wSum.toStringAsFixed(2)}%）',
                  style:
                      const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
              const Spacer(),
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: '刷新行情',
                icon: const Icon(Icons.refresh, size: 18),
                onPressed: widget.onRefresh,
              ),
            ],
          ),
          if ((q?.reportDate ?? '').isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                '披露报告期 ${q!.reportDate}（每季度更新）'
                '${_prevLabel == null ? '' : ' · 较上期（$_prevLabel）'}',
                style: TextStyle(fontSize: 11.5, color: scheme.outline),
              ),
            ),
          if (hs.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Center(
                child: Text('暂无持仓数据',
                    style: TextStyle(fontSize: 13, color: scheme.outline)),
              ),
            )
          else ...[
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Row(
                children: [
                  _colLabel('股票名称', scheme.outline, alignEnd: false),
                  _colLabel('较上期', scheme.outline),
                  const SizedBox(width: 8),
                  _colLabel('持仓占比', scheme.outline, fixed: 52),
                  const SizedBox(width: 10),
                  _colLabel('涨幅', scheme.outline, fixed: 62),
                ],
              ),
            ),
            ...hs.map((h) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('${h.name}  ${h.code}',
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 13.5)),
                            if (h.industry.isNotEmpty)
                              Text(h.industry,
                                  style: TextStyle(
                                      fontSize: 11, color: scheme.outline)),
                          ],
                        ),
                      ),
                      SizedBox(
                        width: 48,
                        child: h.changeTag.isEmpty
                            ? const SizedBox.shrink()
                            : Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 4, vertical: 2),
                                decoration: BoxDecoration(
                                  color: _tagColor(h.changeTag, context)
                                      .withValues(
                                          alpha: h.changeTag == '新进'
                                              ? 0.22
                                              : 0.12),
                                  borderRadius: BorderRadius.circular(5),
                                  border: h.changeTag == '新进'
                                      ? Border.all(
                                          color: _tagColor(h.changeTag, context)
                                              .withValues(alpha: 0.6),
                                          width: 1)
                                      : null,
                                ),
                                child: Text(
                                  h.changeTag,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                      fontSize: 10.5,
                                      fontWeight: h.changeTag == '新进'
                                          ? FontWeight.w900
                                          : FontWeight.w700,
                                      color: _tagColor(h.changeTag, context)),
                                ),
                              ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 52,
                        child: Text(
                          '${h.weight.toStringAsFixed(2)}%',
                          textAlign: TextAlign.right,
                          style: const TextStyle(
                              fontSize: 12.5,
                              fontFeatures: [FontFeature.tabularFigures()]),
                        ),
                      ),
                      const SizedBox(width: 10),
                      SizedBox(
                        width: 62,
                        child: PctText(h.livePct, fontSize: 13),
                      ),
                    ],
                  ),
                )),
          ],
        ],
      ),
    );
  }

  /// 重仓股表头单元格：[fixed] 为 null 时 Expanded 居左，否则固定宽右对齐
  ///（「较上期」用 center 除外）。
  static Widget _colLabel(String text, Color color,
      {double? fixed, bool alignEnd = true}) {
    final style = TextStyle(
        fontSize: 11, fontWeight: FontWeight.w700, color: color);
    if (fixed != null) {
      return SizedBox(
          width: fixed.toDouble(),
          child:
              Text(text, textAlign: TextAlign.right, style: style));
    }
    if (!alignEnd) {
      return Expanded(child: Text(text, style: style));
    }
    return SizedBox(width: 48, child: Text(text, textAlign: TextAlign.center, style: style));
  }
}

/// 基金概况卡：费率 / 最低申购 / 规模变动 / 持有人结构 / 基本信息（f10）。
class _ProfileCard extends StatelessWidget {
  const _ProfileCard({required this.detail, required this.profile});

  final FundDetail detail;
  final FundProfile? profile;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    String fee(String v) =>
        v.isEmpty || v == '--' ? '--' : '$v%';
    final latestScale =
        detail.scales.isNotEmpty ? detail.scales.last : null;
    final hasHolder = detail.holderInst >= 0 && detail.holderPersonal >= 0;
    final p = profile;
    return InfoCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('基金概况',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
          if (p != null && (p.fullName.isNotEmpty || p.company.isNotEmpty)) ...[
            const SizedBox(height: 6),
            if (p.fullName.isNotEmpty)
              Text(p.fullName,
                  style: TextStyle(
                      fontSize: 12, color: scheme.onSurfaceVariant)),
            if (p.company.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  [p.company, p.setupDate, p.custodian]
                      .where((e) => e.isNotEmpty)
                      .join(' · '),
                  style: TextStyle(fontSize: 11.5, color: scheme.outline),
                ),
              ),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('申购费率',
                        style:
                            TextStyle(fontSize: 11, color: scheme.outline)),
                    Text(fee(detail.rate),
                        style: const TextStyle(
                            fontSize: 13.5, fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('原费率',
                        style:
                            TextStyle(fontSize: 11, color: scheme.outline)),
                    Text(fee(detail.sourceRate),
                        style: const TextStyle(
                            fontSize: 13.5, fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('最低申购',
                        style:
                            TextStyle(fontSize: 11, color: scheme.outline)),
                    Text(detail.minsg.isEmpty || detail.minsg == '--'
                        ? '--'
                        : '${detail.minsg}元',
                        style: const TextStyle(
                            fontSize: 13.5, fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
              if (latestScale != null)
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('最新规模',
                          style:
                              TextStyle(fontSize: 11, color: scheme.outline)),
                      Text('${latestScale.$2.toStringAsFixed(2)}亿',
                          style: const TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w700,
                              fontFeatures: [
                                FontFeature.tabularFigures()
                              ])),
                    ],
                  ),
                ),
            ],
          ),
          if (detail.scales.length > 1) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                for (final (label, v) in detail.scales)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text('$label  ${v.toStringAsFixed(1)}亿',
                        style: TextStyle(
                            fontSize: 11,
                            color: scheme.onSurfaceVariant,
                            fontFeatures: const [
                              FontFeature.tabularFigures()
                            ])),
                  ),
              ],
            ),
          ],
          if (hasHolder) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Text('持有人结构',
                    style: TextStyle(fontSize: 11.5, color: scheme.outline)),
                const Spacer(),
                Text('个人 ${detail.holderPersonal.toStringAsFixed(2)}%'
                    ' · 机构 ${detail.holderInst.toStringAsFixed(2)}%'
                    '（${detail.holderReport}）',
                    style: TextStyle(fontSize: 11.5, color: scheme.outline)),
              ],
            ),
            const SizedBox(height: 5),
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: SizedBox(
                height: 7,
                child: Row(
                  children: [
                    Expanded(
                      flex: detail.holderPersonal.clamp(1, 1000).toInt(),
                      child:
                          ColoredBox(color: scheme.primary),
                    ),
                    Expanded(
                      flex: detail.holderInst.clamp(1, 1000).toInt(),
                      child: ColoredBox(
                          color: scheme.primary.withValues(alpha: 0.35)),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// 行业配置卡（最近披露期，按占比降序）。
class _IndustriesCard extends StatelessWidget {
  const _IndustriesCard({required this.detail});

  final FundDetail detail;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final maxV = detail.industries
        .fold<double>(0, (a, b) => b.$2 > a ? b.$2 : a);
    return InfoCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('行业配置',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text('按占净值比例降序（最近披露期）',
              style: TextStyle(fontSize: 11, color: scheme.outline)),
          const SizedBox(height: 8),
          ...detail.industries.map((e) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: [
                    SizedBox(
                      width: 104,
                      child: Text(e.$1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12.5)),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(3),
                        child: LinearProgressIndicator(
                          value: maxV > 0 ? e.$2 / maxV : 0,
                          minHeight: 6,
                          backgroundColor:
                              scheme.surfaceContainerHighest,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 46,
                      child: Text('${e.$2.toStringAsFixed(2)}%',
                          textAlign: TextAlign.right,
                          style: const TextStyle(
                              fontSize: 12,
                              fontFeatures: [
                                FontFeature.tabularFigures()
                              ])),
                    ),
                  ],
                ),
              )),
        ],
      ),
    );
  }
}

/// 每日规模卡：份额 × 每日价格/净值的规模曲线（面积图）。
class _DailyScaleCard extends StatelessWidget {
  const _DailyScaleCard({required this.scale});

  final FundDailyScale scale;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final s = scale.series;
    final first = s.first.$1.replaceAll('-', '/'),
        last = s.last.$1.replaceAll('-', '/');
    final chg = scale.todayChg;
    return InfoCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                scale.isEtf ? '基金规模 · 每日' : '基金规模 · 每日估算',
                style: const TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w700),
              ),
              const Spacer(),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('${scale.latest.toStringAsFixed(2)} 亿',
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w800)),
                  if (!chg.isNaN)
                    Padding(
                      padding: const EdgeInsets.only(top: 1),
                      child: Row(
                        children: [
                          Text('今日',
                              style: TextStyle(
                                  fontSize: 10.5, color: scheme.outline)),
                          const SizedBox(width: 3),
                          Text(
                            '${chg >= 0 ? '+' : ''}${chg.toStringAsFixed(2)} 亿',
                            style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                                color: upDownColor(chg, context)),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            scale.isEtf
                ? '流通份额 × 每日收盘价（实时规模 = 最新总市值）'
                : '最新份额 ${scale.shareYi.toStringAsFixed(2)} 亿份 × 每日净值'
                    '（份额按季度披露，期间申赎未计入）',
            style: TextStyle(fontSize: 11, color: scheme.outline),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 110,
            width: double.infinity,
            child: CustomPaint(
              painter: _ScaleChartPainter(
                values: [for (final e in s) e.$2],
                up: chg.isNaN ? true : chg >= 0,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('$first ~ $last（${s.length} 个交易日）',
                  style: TextStyle(fontSize: 10.5, color: scheme.outline)),
            ],
          ),
        ],
      ),
    );
  }
}

/// 规模面积图：折线 + 渐变填充 + 最高/最低标注。
class _ScaleChartPainter extends CustomPainter {
  _ScaleChartPainter({required this.values, required this.up});

  final List<double> values;
  final bool up;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2) return;
    final minV = values.fold<double>(values.first, (a, b) => b < a ? b : a);
    final maxV = values.fold<double>(values.first, (a, b) => b > a ? b : a);
    final pad = (maxV - minV) * 0.1 + 1e-9;
    final lo = minV - pad, hi = maxV + pad;
    final w = size.width, h = size.height;
    Offset pt(int i) => Offset(
        w * i / (values.length - 1),
        h - (values[i] - lo) / (hi - lo) * h);
    final line = Path()..addPolygon([for (var i = 0; i < values.length; i++) pt(i)], false);
    final fill = Path.from(line)
      ..lineTo(w, h)
      ..lineTo(0, h)
      ..close;
    final color = up ? const Color(0xFFD64541) : const Color(0xFF2E9E4F);
    canvas.drawPath(
        fill,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [color.withValues(alpha: 0.28), color.withValues(alpha: 0.02)],
          ).createShader(Offset.zero & size));
    canvas.drawPath(
        line,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6
          ..isAntiAlias = true);
    // 最新值点。
    canvas.drawCircle(pt(values.length - 1), 2.6, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_ScaleChartPainter old) =>
      old.values.length != values.length || old.up != up;
}

/// 能力评分卡：五维评分横条 + 综合分 + 同类排名。
class _RatingCard extends StatelessWidget {
  const _RatingCard({required this.detail});

  final FundDetail detail;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InfoCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('基金评级 · 能力评分',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
              const Spacer(),
              if (detail.radarAvr != '--')
                Text('综合 ${detail.radarAvr}分',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: scheme.primary)),
            ],
          ),
          const SizedBox(height: 8),
          ...detail.radar.map((e) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: [
                    SizedBox(
                      width: 64,
                      child: Text(e.$1,
                          style: const TextStyle(fontSize: 12)),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(3),
                        child: LinearProgressIndicator(
                          value: (e.$2 / 100).clamp(0.0, 1.0),
                          minHeight: 7,
                          backgroundColor:
                              scheme.surfaceContainerHighest,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 34,
                      child: Text(
                        e.$2 <= 0 ? '--' : e.$2.toStringAsFixed(0),
                        textAlign: TextAlign.right,
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: e.$2 >= 60
                                ? scheme.primary
                                : scheme.onSurfaceVariant),
                      ),
                    ),
                  ],
                ),
              )),
          if (detail.rankTotal > 0) ...[
            const SizedBox(height: 8),
            Text(
              '同类排名 ${detail.rankNum}/${detail.rankTotal}'
              '${detail.rankPct >= 0
                  ? ' · 超越 ${(100 - detail.rankPct).toStringAsFixed(1)}% 同类'
                  : ''}（近1年收益排名）',
              style: TextStyle(fontSize: 11.5, color: scheme.outline),
            ),
          ],
        ],
      ),
    );
  }
}

/// 特色数据卡：年化波动率 / 最大回撤 / 夏普比率（近一年自算）。
class _FeatureCard extends StatelessWidget {
  const _FeatureCard({required this.detail});

  final FundDetail detail;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InfoCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('特色数据',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text('按近一年日净值计算 · 无风险利率 2%',
              style: TextStyle(fontSize: 11, color: scheme.outline)),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('年化波动率',
                        style: TextStyle(fontSize: 11, color: scheme.outline)),
                    Text('${detail.volat.toStringAsFixed(2)}%',
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('最大回撤',
                        style: TextStyle(fontSize: 11, color: scheme.outline)),
                    Text('-${detail.maxDrawdown.toStringAsFixed(2)}%',
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: upDownColor(-1, context))),
                  ],
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('夏普比率',
                        style: TextStyle(fontSize: 11, color: scheme.outline)),
                    Text(detail.sharpe.isNaN
                        ? '--'
                        : detail.sharpe.toStringAsFixed(2),
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: detail.sharpe.isNaN
                                ? scheme.onSurface
                                : detail.sharpe >= 1
                                    ? upDownColor(1, context)
                                    : scheme.onSurface)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 资产配置趋势卡：最近几期股票/债券/现金占净比堆叠条。
class _AllocCard extends StatelessWidget {
  const _AllocCard({required this.detail});

  final FundDetail detail;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InfoCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('资产配置趋势',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text('股 / 债 / 现金占净比（季度披露）',
              style: TextStyle(fontSize: 11, color: scheme.outline)),
          const SizedBox(height: 10),
          ...detail.alloc.reversed.map((e) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: [
                    SizedBox(
                      width: 76,
                      child: Text(e.$1,
                          style: TextStyle(
                              fontSize: 11,
                              color: scheme.outline,
                              fontFeatures: const [
                                FontFeature.tabularFigures()
                              ])),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(3),
                        child: SizedBox(
                          height: 8,
                          child: Row(
                            children: [
                              Expanded(
                                flex: math
                                    .max(e.$2.round(), 1),
                                child:
                                    ColoredBox(color: upDownColor(1, context)),
                              ),
                              Expanded(
                                flex: math.max(e.$3.round(), e.$3 > 0 ? 1 : 0),
                                child: ColoredBox(
                                    color: scheme.tertiary),
                              ),
                              Expanded(
                                flex: math.max(e.$4.round(), e.$4 > 0 ? 1 : 0),
                                child: ColoredBox(
                                    color: scheme.outline
                                        .withValues(alpha: 0.4)),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 108,
                      child: Text(
                        '股${e.$2.toStringAsFixed(1)}%'
                        '${e.$3 > 0 ? ' 债${e.$3.toStringAsFixed(1)}%' : ''}'
                        '${e.$4 > 0 ? ' 现${e.$4.toStringAsFixed(1)}%' : ''}',
                        textAlign: TextAlign.right,
                        style: TextStyle(
                            fontSize: 10.5,
                            color: scheme.onSurfaceVariant,
                            fontFeatures: const [
                              FontFeature.tabularFigures()
                            ]),
                      ),
                    ),
                  ],
                ),
              )),
        ],
      ),
    );
  }
}

/// 持仓变动趋势卡：股票仓位历史（迷你条形，新→旧）。
class _PositionsCard extends StatelessWidget {
  const _PositionsCard({required this.detail});

  final FundDetail detail;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final items = detail.positions.take(8).toList();
    final maxV = items.fold<double>(0, (a, b) => b.$2 > a ? b.$2 : a);
    return InfoCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('持仓变动趋势',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text('股票仓位占净值比（季度披露）',
              style: TextStyle(fontSize: 11, color: scheme.outline)),
          const SizedBox(height: 10),
          ...items.map((e) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: [
                    SizedBox(
                      width: 52,
                      child: Text(e.$1,
                          style: TextStyle(
                              fontSize: 11,
                              color: scheme.outline,
                              fontFeatures: const [
                                FontFeature.tabularFigures()
                              ])),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(3),
                        child: LinearProgressIndicator(
                          value: maxV > 0 ? e.$2 / maxV : 0,
                          minHeight: 7,
                          backgroundColor:
                              scheme.surfaceContainerHighest,
                          color: upDownColor(1, context)
                              .withValues(alpha: 0.75),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 48,
                      child: Text('${e.$2.toStringAsFixed(1)}%',
                          textAlign: TextAlign.right,
                          style: const TextStyle(
                              fontSize: 12,
                              fontFeatures: [
                                FontFeature.tabularFigures()
                              ])),
                    ),
                  ],
                ),
              )),
        ],
      ),
    );
  }
}

/// 申赎与份额卡：期间申购/赎回/总份额（季度）。
class _BuybackCard extends StatelessWidget {
  const _BuybackCard({required this.detail});

  final FundDetail detail;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InfoCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('申赎与份额',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text('期间申购/赎回（亿份）与期末总份额',
              style: TextStyle(fontSize: 11, color: scheme.outline)),
          const SizedBox(height: 8),
          ...detail.buyback.reversed.map((e) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: [
                    SizedBox(
                      width: 76,
                      child: Text(e.$1,
                          style: TextStyle(
                              fontSize: 11,
                              color: scheme.outline,
                              fontFeatures: const [
                                FontFeature.tabularFigures()
                              ])),
                    ),
                    Text('申 ${e.$2.toStringAsFixed(2)}',
                        style: TextStyle(
                            fontSize: 11.5,
                            color: upDownColor(1, context))),
                    const SizedBox(width: 10),
                    Text('赎 ${e.$3.toStringAsFixed(2)}',
                        style: TextStyle(
                            fontSize: 11.5,
                            color: upDownColor(-1, context))),
                    const Spacer(),
                    Text('总份额 ${e.$4.toStringAsFixed(2)}',
                        style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            fontFeatures: const [
                              FontFeature.tabularFigures()
                            ])),
                  ],
                ),
              )),
        ],
      ),
    );
  }
}

/// 历史净值速查表：最近 10 个交易日。
class _NavListCard extends StatelessWidget {
  const _NavListCard({required this.detail});

  final FundDetail detail;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final list = detail.navTrend.reversed.take(10).toList();
    return InfoCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('历史净值',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text('最近 ${list.length} 个交易日',
              style: TextStyle(fontSize: 11, color: scheme.outline)),
          const SizedBox(height: 8),
          Table(
            columnWidths: const {
              0: FlexColumnWidth(),
              1: FixedColumnWidth(84),
              2: FixedColumnWidth(72),
            },
            defaultVerticalAlignment: TableCellVerticalAlignment.middle,
            children: [
              TableRow(
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest
                      .withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(6),
                ),
                children: const [
                  Padding(
                      padding: EdgeInsets.symmetric(vertical: 5),
                      child: Text('日期', textAlign: TextAlign.center,
                          style: TextStyle(
                              fontSize: 11, fontWeight: FontWeight.w700))),
                  Padding(
                      padding: EdgeInsets.symmetric(vertical: 5),
                      child: Text('单位净值', textAlign: TextAlign.right,
                          style: TextStyle(
                              fontSize: 11, fontWeight: FontWeight.w700))),
                  Padding(
                      padding: EdgeInsets.symmetric(vertical: 5),
                      child: Text('日涨幅', textAlign: TextAlign.right,
                          style: TextStyle(
                              fontSize: 11, fontWeight: FontWeight.w700))),
                ],
              ),
              ...list.asMap().entries.map((me) {
            final i = me.key;
            final e = me.value;
            final d = DateTime.fromMillisecondsSinceEpoch(e[0].round());
            String two(int x) => x.toString().padLeft(2, '0');
            // list[i] 对应原数组倒数第 i+1 项；日涨幅 = 与前一项之比。
            final origin = detail.navTrend.length - 1 - i;
            double pct = double.nan;
            if (origin > 0) {
              pct = (e[1] / detail.navTrend[origin - 1][1] - 1) * 100;
            }
                return TableRow(
                  decoration: BoxDecoration(
                    border: Border(
                        bottom: BorderSide(
                            color: scheme.outlineVariant
                                .withValues(alpha: 0.4))),
                  ),
                  children: [
                    Padding(
                        padding: const EdgeInsets.symmetric(vertical: 5),
                        child: Text(
                            '${d.year}/${two(d.month)}/${two(d.day)}',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                fontSize: 11.5,
                                color: scheme.onSurfaceVariant))),
                    Padding(
                        padding: const EdgeInsets.symmetric(vertical: 5),
                        child: Text(e[1].toStringAsFixed(4),
                            textAlign: TextAlign.right,
                            style: const TextStyle(
                                fontSize: 12,
                                fontFeatures: [
                                  FontFeature.tabularFigures()
                                ]))),
                    Padding(
                        padding: const EdgeInsets.fromLTRB(0, 5, 4, 5),
                        child: PctText(pct, fontSize: 11.5)),
                  ],
                );
              }),
            ],
          ),
        ],
      ),
    );
  }
}

/// 分红配送卡。
class _DividendsCard extends StatelessWidget {
  const _DividendsCard({required this.profile});

  final FundProfile profile;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InfoCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('分红配送',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
              const Spacer(),
              Text('共 ${profile.dividends.length} 次（最近在前）',
                  style: TextStyle(fontSize: 11, color: scheme.outline)),
            ],
          ),
          const SizedBox(height: 8),
          ...profile.dividends.map((e) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: [
                    SizedBox(
                      width: 46,
                      child: Text(e.$1,
                          style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                              color: scheme.onSurfaceVariant)),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '登记 ${e.$2.isNotEmpty ? e.$2 : '--'} · 除息 ${e.$3}'
                        ' · 发放 ${e.$5.isNotEmpty ? e.$5 : '--'}',
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 11, color: scheme.outline),
                      ),
                    ),
                    Text(e.$4,
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: upDownColor(1, context))),
                  ],
                ),
              )),
        ],
      ),
    );
  }
}

/// 重大变动卡：基金经理变动记录。
class _MgrChangesCard extends StatelessWidget {
  const _MgrChangesCard({required this.profile});

  final FundProfile profile;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InfoCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('重大变动 · 经理变更',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          ...profile.mgrChanges.map((e) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text('${e.$1} ~ ${e.$2}',
                              style: TextStyle(
                                  fontSize: 11.5,
                                  color: scheme.outline,
                                  fontFeatures: const [
                                    FontFeature.tabularFigures()
                                  ])),
                        ),
                        Text(e.$5,
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                fontFeatures: const [
                                  FontFeature.tabularFigures()
                                ])),
                      ],
                    ),
                    const SizedBox(height: 1),
                    Text('${e.$3}（任职 ${e.$4}）',
                        style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600)),
                  ],
                ),
              )),
        ],
      ),
    );
  }
}

/// 重仓债券卡。
class _BondsCard extends StatelessWidget {
  const _BondsCard({required this.detail});

  final FundDetail detail;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InfoCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('重仓债券',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              for (final (name, v) in detail.bonds)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '$name${v > 0 ? '  ${v.toStringAsFixed(2)}%' : ''}',
                    style: TextStyle(
                        fontSize: 11.5,
                        color: scheme.onSurfaceVariant,
                        fontFeatures: const [FontFeature.tabularFigures()]),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

void _editPosition(BuildContext context, dynamic f) {
  final amountCtrl = TextEditingController(
      text: f.amount > 0 ? f.amount.toStringAsFixed(2) : '');
  final daysCtrl =
      TextEditingController(text: f.firstBuy > 0 ? '${f.holdingDays}' : '');
  final pnlCtrl = TextEditingController();
  showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('${f.name} 持仓设置'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: amountCtrl,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: '持有金额（元）'),
            ),
            TextField(
              controller: daysCtrl,
              keyboardType: const TextInputType.numberWithOptions(),
              decoration: InputDecoration(
                labelText: '持有天数（天）',
                hintText: f.firstBuy > 0
                    ? '当前 ${f.holdingDays} 天，留空不变'
                    : '留空自动从今天起算',
              ),
            ),
            TextField(
              controller: pnlCtrl,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: '持有收益（元）',
                hintText: '填写后按当前市值反推买入成本',
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
        FilledButton(
          onPressed: () {
            // 成本不直接录入：保留原值，填了持有收益时按市值反推覆盖。
            AppState.shared.updatePosition(f.code,
                double.tryParse(amountCtrl.text.trim()) ?? 0, f.costAmount,
                days: int.tryParse(daysCtrl.text.trim()),
                pnl: double.tryParse(pnlCtrl.text.trim()));
            Navigator.pop(ctx);
          },
          child: const Text('保存'),
        ),
      ],
    ),
  );
}
