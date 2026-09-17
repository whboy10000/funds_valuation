import 'package:flutter/material.dart';

import '../models.dart';
import '../services/market_api.dart';
import '../state.dart';
import 'common.dart';

/// 板块页：行业 / 概念实时涨幅排行。
class SectorsPage extends StatefulWidget {
  const SectorsPage({super.key});

  @override
  State<SectorsPage> createState() => _SectorsPageState();
}

class _SectorsPageState extends State<SectorsPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tab = TabController(length: 2, vsync: this)
    ..addListener(_onTabChanged);
  final _search = TextEditingController();
  List<Sector> _list = [];
  bool _asc = false;

  void _onTabChanged() {
    _load();
    setState(() {});
  }

  void _onSearch() => setState(() {});

  @override
  void initState() {
    super.initState();
    _search.addListener(_onSearch);
    _load();
  }

  @override
  void dispose() {
    _tab.removeListener(_onTabChanged);
    _search.removeListener(_onSearch);
    _search.dispose();
    _tab.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final list =
        await AppState.shared.sectors(_tab.index == 0 ? 2 : 3);
    if (mounted) setState(() => _list = list);
  }

  Future<void> _refresh() async {
    final list = await AppState.shared
        .sectors(_tab.index == 0 ? 2 : 3, force: true);
    if (mounted) setState(() => _list = list);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final kw = _search.text.trim();
    var list =
        _list.where((s) => kw.isEmpty || s.name.contains(kw)).toList();
    if (_asc) {
      list = [...list]..sort((a, b) => a.pct.compareTo(b.pct));
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('板块行情'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: '刷新',
            onPressed: _refresh,
          ),
        ],
        bottom: TabBar(
          controller: _tab,
          tabs: const [Tab(text: '行业板块'), Tab(text: '概念板块')],
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: TextField(
              controller: _search,
              decoration: InputDecoration(
                hintText: '筛选板块名称',
                prefixIcon: const Icon(Icons.filter_alt_outlined, size: 20),
                isDense: true,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),
          // 排序控制行：涨幅正序 / 倒序切换（行业与概念均生效）。
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 8, 0),
            child: Row(
              children: [
                Text('共 ${list.length} 个',
                    style: TextStyle(fontSize: 11.5, color: scheme.outline)),
                const Spacer(),
                TextButton.icon(
                  onPressed: () => setState(() => _asc = !_asc),
                  icon: Icon(_asc ? Icons.arrow_upward : Icons.arrow_downward,
                      size: 16),
                  label: Text(_asc ? '涨幅正序（跌幅最多在前）' : '涨幅倒序（涨幅最多在前）',
                      style: const TextStyle(fontSize: 12)),
                ),
              ],
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _refresh,
              child: list.isEmpty
                  ? ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: const [
                        SizedBox(height: 120),
                        EmptyView(
                          icon: Icons.grid_view_outlined,
                          title: '暂无板块数据',
                          subtitle: '下拉刷新或点击右上角刷新按钮',
                        ),
                      ],
                    )
                  : ListView.builder(
                      physics: const AlwaysScrollableScrollPhysics(),
                      itemCount: list.length,
                      itemBuilder: (context, i) => _SectorTile(s: list[i]),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectorTile extends StatelessWidget {
  const _SectorTile({required this.s});

  final Sector s;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => SectorDetailPage(code: s.code, name: s.name),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(s.name,
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 3),
                  Text(
                    '领涨 ${s.leadStock} ${pctText(s.leadStockPct)}'
                    ' · 换手 ${s.turnover.toStringAsFixed(2)}%'
                    ' · 净流入 ${fmtMoney(s.netInflow)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 11.5,
                        color: scheme.outline,
                        fontFeatures: const [FontFeature.tabularFigures()]),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                PctText(s.pct, fontSize: 17),
                const SizedBox(height: 2),
                Text(
                  '涨${s.upCount}/跌${s.downCount}',
                  style: TextStyle(
                      fontSize: 11,
                      color: scheme.outline,
                      fontFeatures: const [FontFeature.tabularFigures()]),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 板块分时详情。
class SectorDetailPage extends StatefulWidget {
  const SectorDetailPage({super.key, required this.code, required this.name});

  /// 板块代码，如 BK1296。
  final String code;
  final String name;

  @override
  State<SectorDetailPage> createState() => _SectorDetailPageState();
}

class _SectorDetailPageState extends State<SectorDetailPage> {
  List<TrendPoint> _points = [];
  double _preClose = 0;
  bool _loading = true;
  List<SectorMember> _members = [];
  bool _membersLoading = true;
  bool _membersAsc = false;

  @override
  void initState() {
    super.initState();
    _load();
    _loadMembers();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final r = await MarketApi.trend('90.${widget.code}');
      if (!mounted) return;
      setState(() {
        _points = r.points;
        _preClose = r.preClose;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadMembers({bool force = false}) async {
    setState(() => _membersLoading = true);
    try {
      final list =
          await AppState.shared.sectorMembers(widget.code, force: force);
      if (mounted) setState(() => _members = list);
    } catch (_) {
      if (mounted) setState(() => _members = const []);
    } finally {
      if (mounted) setState(() => _membersLoading = false);
    }
  }

  Future<void> _refreshAll() async {
    _load();
    await _loadMembers(force: true);
  }

  @override
  Widget build(BuildContext context) {
    final pct = _preClose > 0 && _points.isNotEmpty
        ? (_points.last.value - _preClose) / _preClose * 100
        : double.nan;
    final members = [..._members]
      ..sort((a, b) => _membersAsc ? a.pct.compareTo(b.pct) : b.pct.compareTo(a.pct));
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.name, style: const TextStyle(fontSize: 17)),
        actions: [
          IconButton(
            tooltip: _membersAsc ? '成分股按涨幅降序' : '成分股按涨幅升序',
            icon: const Icon(Icons.swap_vert),
            onPressed: () => setState(() => _membersAsc = !_membersAsc),
          ),
          IconButton(icon: const Icon(Icons.refresh), onPressed: _refreshAll),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          InfoCard(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _points.isEmpty ? '--' : fmtPrice(_points.last.value),
                  style: TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.w800,
                      color: upDownColor(pct, context),
                      fontFeatures: const [FontFeature.tabularFigures()]),
                ),
                const SizedBox(height: 4),
                PctText(pct, fontSize: 16),
              ],
            ),
          ),
          const SizedBox(height: 12),
          InfoCard(
            child: _loading
                ? const SizedBox(
                    height: 220,
                    child: Center(child: CircularProgressIndicator()))
                : TrendChart(points: _points, base: _preClose, height: 240),
          ),
          const SizedBox(height: 12),
          InfoCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text('成分股（${_members.length}）',
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w700)),
                    const Spacer(),
                    Text(
                      _membersAsc ? '涨幅升序' : '涨幅降序',
                      style: TextStyle(fontSize: 11, color: scheme.outline),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                if (_membersLoading && _members.isEmpty)
                  const SizedBox(
                      height: 120,
                      child: Center(child: CircularProgressIndicator()))
                else if (members.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Center(
                      child: Text('暂无成分股数据',
                          style:
                              TextStyle(fontSize: 12.5, color: scheme.outline)),
                    ),
                  )
                else
                  ...members.map((m) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(m.name,
                                      style: const TextStyle(
                                          fontSize: 13.5,
                                          fontWeight: FontWeight.w600)),
                                  Text(m.code,
                                      style: TextStyle(
                                          fontSize: 11,
                                          color: scheme.outline,
                                          fontFeatures: const [
                                            FontFeature.tabularFigures()
                                          ])),
                                ],
                              ),
                            ),
                            const SizedBox(width: 10),
                            Text(
                              fmtPrice(m.price),
                              style: const TextStyle(
                                  fontSize: 13.5,
                                  fontFeatures: [FontFeature.tabularFigures()]),
                            ),
                            const SizedBox(width: 12),
                            SizedBox(
                              width: 68,
                              child: PctText(m.pct, fontSize: 13.5),
                            ),
                          ],
                        ),
                      )),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
