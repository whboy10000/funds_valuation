import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models.dart';
import '../services/fund_api.dart';
import '../state.dart';
import 'common.dart';
import 'fund_detail_page.dart';

/// 常用分组预设。
const kGroupPresets = ['支付宝', '天天基金', '京东金融', '同花顺爱理财', '微信理财'];

/// 加仓/减仓弹层（估值页与详情页共用）。
void showTradeSheet(BuildContext context, FundItem f, bool buy) {
  final amountCtrl = TextEditingController();
  final messenger = ScaffoldMessenger.of(context);
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${buy ? '加仓' : '减仓'} · ${f.name}',
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
            ),
            if (!buy && f.amount > 0)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('当前持有 ${fmtMoney(f.amount)}元',
                    style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(ctx).colorScheme.outline)),
              ),
            const SizedBox(height: 14),
            TextField(
              controller: amountCtrl,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: '金额（元）',
                prefixText: '¥ ',
                suffixIcon: buy
                    ? IconButton(
                        tooltip: '快速输入 1000',
                        icon: const Icon(Icons.bolt_outlined, size: 20),
                        onPressed: () => amountCtrl.text = '1000',
                      )
                    : IconButton(
                        tooltip: '清仓',
                        icon: const Icon(Icons.clear_all, size: 20),
                        onPressed: () =>
                            amountCtrl.text = f.amount.toStringAsFixed(2),
                      ),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () async {
                  final a = double.tryParse(amountCtrl.text.trim()) ?? 0;
                  final err =
                      await AppState.shared.addTrade(f.code, buy, a);
                  if (!ctx.mounted) return;
                  Navigator.pop(ctx);
                  if (err != null) {
                    messenger.showSnackBar(SnackBar(content: Text(err)));
                  } else {
                    messenger.showSnackBar(SnackBar(
                        content: Text('${buy ? '已加仓' : '已减仓'} ${fmtMoney(a)}元')));
                  }
                },
                child: Text(buy ? '确认加仓' : '确认减仓'),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// 交易记录列表（估值页与详情页共用）。
void showTradeRecords(BuildContext context, FundItem f) {
  showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    showDragHandle: true,
    builder: (ctx) {
      final records = AppState.shared.tradesOf(f.code);
      return SafeArea(
        child: Container(
          constraints: BoxConstraints(
              maxHeight: MediaQuery.of(ctx).size.height * 0.6),
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('交易记录 · ${f.name}',
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              if (records.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 28),
                  child: Center(
                    child: Text('暂无交易记录',
                        style: TextStyle(
                            fontSize: 13,
                            color: Theme.of(ctx).colorScheme.outline)),
                  ),
                )
              else
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      for (final t in records)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                          leading: Icon(
                            t.buy
                                ? Icons.add_circle_outline
                                : Icons.remove_circle_outline,
                            size: 20,
                            color: upDownColor(t.buy ? 1 : -1, ctx),
                          ),
                          title: Text(
                            '${t.buy ? '加仓' : '减仓'} ${fmtMoney(t.amount)}元',
                            style: const TextStyle(fontSize: 14),
                          ),
                          subtitle: Text(fmtTradeTime(t.time),
                              style: TextStyle(
                                  fontSize: 11.5,
                                  color: Theme.of(ctx).colorScheme.outline)),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      );
    },
  );
}

String fmtTradeTime(int ms) {
  final t = DateTime.fromMillisecondsSinceEpoch(ms);
  String two(int v) => v.toString().padLeft(2, '0');
  return '${t.year}-${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}';
}

/// 估值主页：自选基金列表 + 收益汇总 + 分组标签 + 搜索添加。
class FundsPage extends StatefulWidget {
  const FundsPage({super.key});

  @override
  State<FundsPage> createState() => _FundsPageState();
}

class _FundsPageState extends State<FundsPage> {
  /// 当前选中的分组标签，'' 表示全部。
  String _group = '';

  @override
  Widget build(BuildContext context) {
    final app = AppState.shared;
    return Scaffold(
      body: ListenableBuilder(
        listenable: app,
        builder: (context, _) => _buildList(context, app),
      ),
    );
  }

  /// App Store 式大标题栏：排序 / 刷新 / 搜索添加。
  Widget _titleBar(BuildContext context, AppState app) => LargeTitleBar(
        title: '基金估值',
        actions: [
          const _SortMenuButton(),
          IconButton(
            tooltip: '手动刷新',
            icon: const Icon(Icons.refresh),
            onPressed: () => app.refreshFunds(),
          ),
          Padding(
            padding: const EdgeInsets.only(left: 2, right: 4),
            child: FilledButton.tonalIcon(
              onPressed: () => _openSearch(context),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('添加基金'),
              style: FilledButton.styleFrom(
                minimumSize: const Size(0, 34),
                padding: const EdgeInsets.symmetric(horizontal: 14),
                textStyle: const TextStyle(
                    fontSize: 13.5, fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ],
      );

  Widget _buildList(BuildContext context, AppState app) {
    final all = app.sortedFunds;
    if (all.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: kFloatingNavPadding),
        children: [
          _titleBar(context, app),
          const _EmptyFunds(),
        ],
      );
    }

    // 分组标签：全部 + 已用分组（存在未分组基金时追加「未分组」）。
    final hasUngrouped = all.any((f) => f.group.isEmpty);
    final tabs = <String>['', ...app.groups, if (hasUngrouped) '未分组'];
    // 选中的分组可能已被删除，回退到全部。
    final selected = tabs.contains(_group) ? _group : '';
    final list = selected.isEmpty
        ? all
        : all
            .where((f) => (f.group.isEmpty ? '未分组' : f.group) == selected)
            .toList();

    final totalAmount =
        all.fold<double>(0, (v, f) => v + (f.amount > 0 ? f.amount : 0));

    final children = <Widget>[
      const _SummaryHeader(),
      _GroupTabs(
        tabs: tabs,
        selected: selected,
        onSelected: (g) => setState(() => _group = g),
      ),
      _AllocationCard(funds: list, groupName: selected),
    ];
    // 选中具体分组时显示组内今日收益小计（iOS 分区标题样式）。
    if (selected.isNotEmpty) {
      children.add(_GroupHeader(name: selected, funds: list));
    }
    children.add(
      GroupedCard(
        margin: const EdgeInsets.fromLTRB(16, 2, 16, 18),
        children: [
          for (final f in list)
            _FundTile(
              f: f,
              ratio: totalAmount > 0 && f.amount > 0 ? f.amount / totalAmount : 0,
            ),
        ],
      ),
    );

    return RefreshIndicator(
      onRefresh: () => app.refreshFunds(),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: kFloatingNavPadding - 18),
        children: [_titleBar(context, app), ...children],
      ),
    );
  }

  void _openSearch(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => const _AddFundSheet(),
    );
  }
}

/// 资产占比饼图：各基金估值市值占总资产的比例（跟随当前分组）。
class _AllocationCard extends StatelessWidget {
  const _AllocationCard({required this.funds, required this.groupName});

  final List<FundItem> funds;
  final String groupName; // '' = 全部

  static const _palette = <Color>[
    Color(0xFF5B8DEF), Color(0xFF34C77B), Color(0xFFF5A623),
    Color(0xFFE5484D), Color(0xFF9B59B6), Color(0xFF00BCD4),
    Color(0xFFFF7043), Color(0xFF7E57C2),
  ];

  @override
  Widget build(BuildContext context) {
    final app = AppState.shared;
    final scheme = Theme.of(context).colorScheme;
    // 各基金估值市值（估值不可用时按持有金额）。
    final segs = <(String, double, Color)>[];
    for (final f in funds) {
      if (f.amount <= 0) continue;
      final q = app.quoteOf(f.code);
      final mv = f.amount * (1 + ((q?.hasEst ?? false) ? q!.estPct : 0) / 100);
      if (mv <= 0) continue;
      segs.add((f.name, mv, _palette[segs.length % _palette.length]));
    }
    if (segs.isEmpty) return const SizedBox.shrink();
    segs.sort((a, b) => b.$2.compareTo(a.$2));
    final total = segs.fold<double>(0, (a, b) => a + b.$2);

    // 超过 7 只合并为「其他」。
    var shown = segs;
    Color otherColor = const Color(0xFF9E9E9E);
    if (segs.length > 7) {
      final rest = segs.sublist(7);
      final restV = rest.fold<double>(0, (a, b) => a + b.$2);
      shown = [...segs.sublist(0, 7), ('其他 ${rest.length}只', restV, otherColor)];
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 6),
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              groupName.isEmpty ? '资产占比' : '资产占比 · $groupName',
              style:
                  const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                SizedBox(
                  width: 128,
                  height: 128,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      CustomPaint(
                        size: const Size(128, 128),
                        painter: _PiePainter(
                          segs: [
                            for (final (_, v, c) in shown) (v, c)
                          ],
                          holeColor: scheme.surfaceContainerLow,
                        ),
                      ),
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('总资产',
                              style: TextStyle(
                                  fontSize: 10.5, color: scheme.outline)),
                          Text(fmtMoney(total),
                              style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  fontFeatures: const [
                                    FontFeature.tabularFigures()
                                  ])),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Wrap(
                    spacing: 10,
                    runSpacing: 6,
                    children: [
                      for (final (name, v, c) in shown)
                        SizedBox(
                          width: 150,
                          child: Row(
                            children: [
                              Container(
                                width: 9,
                                height: 9,
                                decoration:
                                    BoxDecoration(color: c, shape: BoxShape.circle),
                              ),
                              const SizedBox(width: 5),
                              Expanded(
                                child: Text(name,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 11.5)),
                              ),
                              Text(
                                '${(v / total * 100).toStringAsFixed(1)}%',
                                style: TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w600,
                                    color: scheme.onSurfaceVariant,
                                    fontFeatures: const [
                                      FontFeature.tabularFigures()
                                    ]),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 环形饼图画笔（扇区间留白隙）。
class _PiePainter extends CustomPainter {
  _PiePainter({required this.segs, required this.holeColor});

  final List<(double, Color)> segs;
  final Color holeColor; // 卡片背景色（内孔/扇区间隙）

  @override
  void paint(Canvas canvas, Size size) {
    final total = segs.fold<double>(0, (a, b) => a + b.$1);
    if (total <= 0) return;
    final rect = Rect.fromCircle(
        center: Offset(size.width / 2, size.height / 2),
        radius: size.width / 2 - 2);
    final center = rect.center;
    var start = -math.pi / 2;
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = holeColor;
    if (segs.length == 1) {
      canvas.drawCircle(center, rect.width / 2, Paint()..color = segs.first.$2);
      canvas.drawCircle(center, rect.width / 2, stroke);
    } else {
      for (final (v, c) in segs) {
        final sweep = v / total * 2 * math.pi;
        final path = Path()
          ..moveTo(center.dx, center.dy)
          ..arcTo(rect, start, sweep, false)
          ..close();
        canvas.drawPath(path, Paint()..color = c);
        canvas.drawPath(path, stroke);
        start += sweep;
      }
    }
    // 内孔（露出中心总额）。
    canvas.drawCircle(center, rect.width / 2 * 0.55, Paint()..color = holeColor);
  }

  @override
  bool shouldRepaint(_PiePainter old) =>
      old.segs != segs || old.holeColor != holeColor;
}

/// 分组横向标签栏（点击切换到该分组下的基金列表）。
class _GroupTabs extends StatelessWidget {
  const _GroupTabs({
    required this.tabs,
    required this.selected,
    required this.onSelected,
  });

  final List<String> tabs;
  final String selected;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 7, 16, 7),
        children: [
          for (final g in tabs)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(
                  g.isEmpty ? '全部' : g,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight:
                        selected == g ? FontWeight.w600 : FontWeight.w500),
                ),
                selected: selected == g,
                visualDensity: VisualDensity.compact,
                onSelected: (_) => onSelected(g),
              ),
            ),
        ],
      ),
    );
  }
}

/// 排序菜单按钮。
class _SortMenuButton extends StatelessWidget {
  const _SortMenuButton();

  static const _items = <(int, String)>[
    (0, '自定义（置顶优先）'),
    (1, '估值涨幅 从高到低'),
    (2, '估值涨幅 从低到高'),
    (3, '持仓市值 从高到低'),
    (4, '按基金名称'),
  ];

  @override
  Widget build(BuildContext context) {
    final app = AppState.shared;
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) => PopupMenuButton<int>(
        tooltip: '排序',
        icon: const Icon(Icons.sort),
        onSelected: (v) => app.setSortMode(v),
        itemBuilder: (_) => [
          for (final (v, label) in _items)
            PopupMenuItem(
              value: v,
              child: Row(
                children: [
                  SizedBox(
                    width: 24,
                    child: app.sortMode == v
                        ? const Icon(Icons.check, size: 18)
                        : null,
                  ),
                  Expanded(child: Text(label, style: const TextStyle(fontSize: 14))),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// 分组标题（含组内今日收益小计）。
class _GroupHeader extends StatelessWidget {
  const _GroupHeader({required this.name, required this.funds});

  final String name;
  final List<FundItem> funds;

  @override
  Widget build(BuildContext context) {
    final app = AppState.shared;
    var today = 0.0;
    var hasEst = false;
    for (final f in funds) {
      final q = app.quoteOf(f.code);
      if (q == null || f.amount <= 0 || !q.hasEst) continue;
      today += f.amount * q.estPct / 100;
      hasEst = true;
    }
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 10, 20, 5),
      child: Row(
        children: [
          Text(name,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: scheme.outline)),
          Text('  ${funds.length}只',
              style: TextStyle(fontSize: 11.5, color: scheme.outline)),
          const Spacer(),
          Text(
            hasEst ? '今日 ${fmtMoney(today)}' : '',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: hasEst ? upDownColor(today, context) : scheme.outline,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

/// 空状态 + 热门基金快速添加。
class _EmptyFunds extends StatelessWidget {
  const _EmptyFunds();

  static const _hot = [
    ('005827', '易方达蓝筹精选混合'),
    ('161725', '招商中证白酒指数(LOF)A'),
    ('110022', '易方达消费行业股票'),
    ('012414', '招商中证白酒指数(LOF)C'),
    ('519674', '银河创新成长混合A'),
    ('003096', '中欧医疗健康混合C'),
  ];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 60),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const EmptyView(
            icon: Icons.savings_outlined,
            title: '还没有自选基金',
            subtitle: '搜索基金代码或名称添加，\n实时估值将基于重仓股行情自动计算。',
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                for (final (code, name) in _hot)
                  ActionChip(
                    label: Text(name, style: const TextStyle(fontSize: 12)),
                    onPressed: () async {
                      final hit = await _ensureHit(code, name);
                      if (hit != null && context.mounted) {
                        _openPositionSetup(context, hit);
                      }
                    },
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<FundSearchHit?> _ensureHit(String code, String name) async {
    try {
      final navs = await FundApi.navInfo([code]);
      final nav = navs[code];
      return FundSearchHit(
        code: code,
        name: nav?.name ?? name,
        type: '',
        company: '',
        manager: '',
      );
    } catch (_) {
      return FundSearchHit(
          code: code, name: name, type: '', company: '', manager: '');
    }
  }
}

/// 打开持仓录入弹层（添加基金第二步）。
void _openPositionSetup(BuildContext context, FundSearchHit hit) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (ctx) => Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
      child: _PositionSetupSheet(hit: hit),
    ),
  );
}

/// 顶部收益汇总：账户资产 + 当日收益（渐变方向色大卡）+ 大盘摘要条。
class _SummaryHeader extends StatelessWidget {
  const _SummaryHeader();

  @override
  Widget build(BuildContext context) {
    final app = AppState.shared;
    final s = app.summary();
    final scheme = Theme.of(context).colorScheme;
    final updated = app.fundsUpdatedAt;
    final showPnl = s.hasToday;
    final deep = showPnl ? upDownColorDeep(s.todayPnl, context) : scheme.outline;
    // 今日收益占比（相对昨日资产）。
    final base = s.marketValue - s.todayPnl;
    final todayPct = (showPnl && base > 0) ? s.todayPnl / base * 100 : double.nan;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
      child: Container(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('账户资产',
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: scheme.outline)),
                      const SizedBox(height: 3),
                      Text(
                        s.any ? fmtMoney(s.marketValue) : '--',
                        style: TextStyle(
                            fontSize: 29,
                            fontWeight: FontWeight.w600,
                            color: scheme.onSurface,
                            height: 1.2,
                            letterSpacing: -0.6,
                            fontFeatures: const [
                              FontFeature.tabularFigures()
                            ]),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('当日收益',
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: scheme.outline)),
                    const SizedBox(height: 3),
                    Text(
                      showPnl
                          ? '${s.todayPnl >= 0 ? '+' : ''}${fmtMoney(s.todayPnl)}'
                          : '--',
                      style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w600,
                          color: deep,
                          height: 1.25,
                          letterSpacing: -0.3,
                          fontFeatures: const [FontFeature.tabularFigures()]),
                    ),
                    Text(
                      todayPct.isNaN ? '' : pctText(todayPct),
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: deep,
                          fontFeatures: const [FontFeature.tabularFigures()]),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              '更新于 ${updated == null ? '--:--:--' : _hhmmss(updated)}'
              '${app.refreshSecs > 0 ? ' · 每${app.refreshSecs}s自动刷新' : ''}',
              style: TextStyle(fontSize: 11, color: scheme.outline),
            ),
            if (app.fundsError != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(app.fundsError!,
                    style: TextStyle(fontSize: 11, color: scheme.error)),
              ),
          ],
        ),
      ),
    );
  }

  static String _hhmmss(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:${t.second.toString().padLeft(2, '0')}';
}

/// 基金条目。
class _FundTile extends StatelessWidget {
  const _FundTile({required this.f, this.ratio = 0});

  final FundItem f;

  /// 占持仓总额的比例（0~1），0 表示未录入金额不显示占比条。
  final double ratio;

  @override
  Widget build(BuildContext context) {
    final app = AppState.shared;
    final q = app.quoteOf(f.code);
    final scheme = Theme.of(context).colorScheme;
    final est = q?.hasEst ?? false;
    final sec = app.relatedSector(f.code);
    final hasHoldings = f.amount > 0;
    final todayPnl = (est && hasHoldings) ? f.amount * q!.estPct / 100 : 0.0;
    final totalPnl = hasHoldings && f.costAmount > 0
        ? f.amount * (1 + (est ? q!.estPct : 0) / 100) - f.costAmount
        : 0.0;
    final totalPct = f.costAmount > 0 ? totalPnl / f.costAmount * 100 : double.nan;

    return InkWell(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => FundDetailPage(code: f.code)),
      ),
      onLongPress: () => _showActions(context),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      if (f.pinned)
                        Padding(
                          padding: const EdgeInsets.only(right: 4),
                          child: Icon(Icons.push_pin,
                              size: 13, color: scheme.primary),
                        ),
                      Flexible(
                        child: Text(
                          f.name,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 15.5, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 6,
                    runSpacing: 3,
                    children: [
                      if (f.type.isNotEmpty)
                        _chip(context, f.type, scheme.surfaceContainerHighest),
                      if (sec != null)
                        _chip(
                            context,
                            '${sec.$1}${sec.$2.isNaN ? '' : ' ${pctText(sec.$2)}'}',
                            sec.$2.isNaN
                                ? scheme.surfaceContainerHighest
                                : upDownTint(sec.$2, context),
                            color: sec.$2.isNaN
                                ? scheme.onSurfaceVariant
                                : upDownColorDeep(sec.$2, context)),
                      if (hasHoldings && f.holdingDays > 0)
                        _chip(context, '持有${f.holdingDays}天',
                            scheme.surfaceContainerHighest),
                    ],
                  ),
                  if (hasHoldings) ...[
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 14,
                      runSpacing: 4,
                      children: [
                        _mini(context, '持有', fmtMoney(f.amount),
                            scheme.onSurfaceVariant),
                        if (est) ...[
                          _mini(context, '当日', fmtMoney(todayPnl),
                              upDownColor(todayPnl, context)),
                          _mini(context, '持仓收益', fmtMoney(totalPnl),
                              upDownColor(totalPnl, context)),
                          if (!totalPct.isNaN)
                            _mini(context, '收益率', pctText(totalPct),
                                upDownColor(totalPct, context)),
                        ],
                      ],
                    ),
                  ],
                  if (ratio > 0)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(2),
                        child: LinearProgressIndicator(
                          value: ratio.clamp(0.0, 1.0),
                          minHeight: 4,
                          backgroundColor: scheme.surfaceContainerHighest,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                PctText(est ? q!.estPct : double.nan, fontSize: 19),
                const SizedBox(height: 3),
                Text(
                  est ? '估 ${q!.estNav.toStringAsFixed(4)}' : '估值不可用',
                  style: TextStyle(
                      fontSize: 12,
                      color: est ? scheme.onSurfaceVariant : scheme.outline,
                      fontFeatures: const [FontFeature.tabularFigures()]),
                ),
                if (hasHoldings && est)
                  Container(
                    margin: const EdgeInsets.only(top: 5),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 9, vertical: 3.5),
                    decoration: BoxDecoration(
                      color: upDownTint(todayPnl, context),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '${todayPnl >= 0 ? '+' : ''}${fmtMoney(todayPnl)}',
                      style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: upDownColorDeep(todayPnl, context),
                          fontFeatures: const [
                            FontFeature.tabularFigures()
                          ]),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _chip(BuildContext context, String text, Color bg,
          {Color? color}) =>
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
        decoration: BoxDecoration(
            color: bg, borderRadius: BorderRadius.circular(6)),
        child: Text(text,
            style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
                color: color ?? Theme.of(context).colorScheme.onSurfaceVariant,
                fontFeatures: const [FontFeature.tabularFigures()])),
      );

  Widget _mini(BuildContext context, String label, String value, Color color) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: color,
                  fontFeatures: const [FontFeature.tabularFigures()])),
          Text(label,
              style: TextStyle(
                  fontSize: 10, color: Theme.of(context).colorScheme.outline)),
        ],
      );

  void _showActions(BuildContext context) {
    final app = AppState.shared;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.push_pin_outlined),
              title: Text(f.pinned ? '取消置顶' : '置顶'),
              onTap: () {
                Navigator.pop(ctx);
                app.togglePin(f.code);
              },
            ),
            ListTile(
              leading: const Icon(Icons.add_circle_outline),
              title: const Text('加仓'),
              onTap: () {
                Navigator.pop(ctx);
                showTradeSheet(context, f, true);
              },
            ),
            ListTile(
              leading: const Icon(Icons.remove_circle_outline),
              title: const Text('减仓'),
              onTap: () {
                Navigator.pop(ctx);
                showTradeSheet(context, f, false);
              },
            ),
            ListTile(
              leading: const Icon(Icons.receipt_long_outlined),
              title: const Text('交易记录'),
              onTap: () {
                Navigator.pop(ctx);
                showTradeRecords(context, f);
              },
            ),
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('编辑持仓（金额/成本）'),
              onTap: () {
                Navigator.pop(ctx);
                _editPosition(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.folder_copy_outlined),
              title: const Text('移动分组'),
              onTap: () {
                Navigator.pop(ctx);
                _moveGroup(context);
              },
            ),
            ListTile(
              leading: Icon(Icons.delete_outline, color: Theme.of(ctx).colorScheme.error),
              title: Text('删除自选', style: TextStyle(color: Theme.of(ctx).colorScheme.error)),
              onTap: () {
                Navigator.pop(ctx);
                app.removeFund(f.code);
              },
            ),
          ],
          ),
        ),
      ),
    );
  }

  void _editPosition(BuildContext context) {
    final amountCtrl = TextEditingController(
        text: f.amount > 0 ? f.amount.toStringAsFixed(2) : '');
    final daysCtrl = TextEditingController(
        text: f.firstBuy > 0 ? '${f.holdingDays}' : '');
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
                decoration: const InputDecoration(
                  labelText: '持有金额（元）',
                  hintText: '留空表示不跟踪收益',
                ),
              ),
              TextField(
                controller: daysCtrl,
                keyboardType: const TextInputType.numberWithOptions(),
                decoration: InputDecoration(
                  labelText: '持有天数（天）',
                  hintText: f.firstBuy > 0 ? '当前 ${f.holdingDays} 天，留空不变' : '留空自动从今天起算',
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
              final amount = double.tryParse(amountCtrl.text.trim()) ?? 0;
              final days = int.tryParse(daysCtrl.text.trim());
              final pnl = double.tryParse(pnlCtrl.text.trim());
              // 成本不直接录入：保留原值，填了持有收益时按市值反推覆盖。
              AppState.shared.updatePosition(f.code, amount, f.costAmount,
                  days: days, pnl: pnl);
              Navigator.pop(ctx);
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }

  void _moveGroup(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => _GroupPickerDialog(
        current: f.group,
        onSaved: (g) => AppState.shared.setGroup(f.code, g),
      ),
    );
  }
}

/// 分组选择对话框（预设 + 已有分组 + 自定义输入）。
class _GroupPickerDialog extends StatefulWidget {
  const _GroupPickerDialog({required this.current, required this.onSaved});

  final String current;
  final ValueChanged<String> onSaved;

  @override
  State<_GroupPickerDialog> createState() => _GroupPickerDialogState();
}

class _GroupPickerDialogState extends State<_GroupPickerDialog> {
  late final TextEditingController _ctrl =
      TextEditingController(text: widget.current);
  late String _selected = widget.current;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = AppState.shared;
    final options = <String>[
      ...kGroupPresets,
      ...app.groups.where((g) => !kGroupPresets.contains(g)),
    ];
    return AlertDialog(
      title: const Text('选择分组'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 0,
              children: [
                for (final g in options)
                  ChoiceChip(
                    label: Text(g, style: const TextStyle(fontSize: 12.5)),
                    selected: _selected == g,
                    onSelected: (_) => setState(() {
                      _selected = g;
                      _ctrl.text = g;
                    }),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _ctrl,
              decoration: const InputDecoration(
                labelText: '分组名称',
                hintText: '可直接输入新分组，留空为未分组',
                isDense: true,
              ),
              onChanged: (v) => setState(() => _selected = v),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
        FilledButton(
          onPressed: () {
            widget.onSaved(_ctrl.text.trim());
            Navigator.pop(context);
          },
          child: const Text('保存'),
        ),
      ],
    );
  }
}

/// 搜索添加弹层。
class _AddFundSheet extends StatefulWidget {
  const _AddFundSheet();

  @override
  State<_AddFundSheet> createState() => _AddFundSheetState();
}

class _AddFundSheetState extends State<_AddFundSheet> {
  final _ctrl = TextEditingController();
  Timer? _debounce;
  List<FundSearchHit> _hits = [];
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _ctrl.addListener(_onChanged);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  void _onChanged() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), _doSearch);
  }

  Future<void> _doSearch() async {
    final kw = _ctrl.text.trim();
    if (kw.isEmpty) {
      setState(() {
        _hits = [];
        _error = null;
        _loading = false;
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final hits = await FundApi.search(kw);
      if (!mounted) return;
      setState(() {
        _hits = hits;
        _loading = false;
        if (hits.isEmpty) _error = '未找到相关基金';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '搜索失败，请检查网络';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = AppState.shared;
    return Padding(
      padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.7,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
              child: TextField(
                controller: _ctrl,
                autofocus: true,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: '基金代码 / 名称 / 拼音',
                  prefixIcon: const Icon(Icons.search, size: 21),
                  suffixIcon: IconButton(
                    tooltip: '取消',
                    icon: const Icon(Icons.keyboard_arrow_down_rounded,
                        size: 26),
                    onPressed: () => Navigator.pop(context),
                  ),
                  filled: true,
                  fillColor:
                      Theme.of(context).colorScheme.surfaceContainerHigh,
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 15),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide.none,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(24),
                child: CircularProgressIndicator(),
              )
            else if (_error != null)
              Padding(
                padding: const EdgeInsets.all(24),
                child: Text(_error!,
                    style: TextStyle(color: Theme.of(context).colorScheme.outline)),
              )
            else
              Expanded(
                child: ListenableBuilder(
                  listenable: app,
                  builder: (context, _) => ListView.builder(
                    itemCount: _hits.length,
                    itemBuilder: (context, i) {
                      final h = _hits[i];
                      final added = app.funds.any((f) => f.code == h.code);
                      return ListTile(
                        title: Text(h.name,
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: Text(
                          '${h.code}${h.type.isEmpty ? '' : ' · ${h.type}'}'
                          '${h.manager.isEmpty ? '' : ' · ${h.manager}'}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: added
                            ? const Icon(Icons.check, color: Colors.grey)
                            : const Icon(Icons.add_circle_outline),
                        onTap: added
                            ? null
                            : () => _openPositionSetup(context, h),
                      );
                    },
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// 添加基金第二步：录入持有金额/成本与分组。
class _PositionSetupSheet extends StatefulWidget {
  const _PositionSetupSheet({required this.hit});

  final FundSearchHit hit;

  @override
  State<_PositionSetupSheet> createState() => _PositionSetupSheetState();
}

class _PositionSetupSheetState extends State<_PositionSetupSheet> {
  final _amountCtrl = TextEditingController();
  final _costCtrl = TextEditingController();
  final _groupCtrl = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _amountCtrl.dispose();
    _costCtrl.dispose();
    _groupCtrl.dispose();
    super.dispose();
  }

  Future<void> _save(bool withPosition) async {
    if (_saving) return;
    _saving = true;
    final app = AppState.shared;
    // 已输入的持有金额/成本始终生效，避免点「跳过」时丢失录入。
    await app.addFund(
      widget.hit,
      amount: double.tryParse(_amountCtrl.text.trim()) ?? 0,
      costAmount: double.tryParse(_costCtrl.text.trim()) ?? 0,
      group: _groupCtrl.text.trim(),
    );
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    Navigator.pop(context); // 持仓录入
    Navigator.pop(context); // 搜索
    messenger.showSnackBar(
      SnackBar(
        content: Text('已添加 ${widget.hit.name}'),
        duration: const Duration(milliseconds: 800),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final app = AppState.shared;
    final options = <String>[
      ...kGroupPresets,
      ...app.groups.where((g) => !kGroupPresets.contains(g)),
    ];
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 2, 20, 14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${widget.hit.name}（${widget.hit.code}）',
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 2),
            Text('录入持有金额与买入成本，可随时在长按菜单中修改',
                style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.outline)),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _amountCtrl,
                    autofocus: true,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: '持有金额（元）',
                      hintText: '如 5000',
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _costCtrl,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: '买入成本（元）',
                      hintText: '选填，如 4800',
                      isDense: true,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text('分组（可选）',
                style: TextStyle(
                    fontSize: 12.5, color: Theme.of(context).colorScheme.outline)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 0,
              children: [
                for (final g in options)
                  ChoiceChip(
                    label: Text(g, style: const TextStyle(fontSize: 12.5)),
                    selected: _groupCtrl.text == g,
                    onSelected: (_) =>
                        setState(() => _groupCtrl.text = g),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _groupCtrl,
              decoration: const InputDecoration(
                labelText: '自定义分组',
                hintText: '如 支付宝 / 天天基金 / 新分组',
                isDense: true,
              ),
            ),
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => _save(false),
                  child: const Text('跳过，直接添加'),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: () => _save(true),
                  icon: const Icon(Icons.check, size: 18),
                  label: const Text('保存并添加'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
