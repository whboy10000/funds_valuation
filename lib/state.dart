import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'models.dart';
import 'services/estimator.dart';
import 'services/fund_api.dart';
import 'services/market_api.dart';
import 'services/store.dart';

/// 应用全局状态（ChangeNotifier 单例）。
class AppState extends ChangeNotifier {
  AppState._();

  static final AppState shared = AppState._();

  // ---------- 设置 ----------
  int refreshSecs = 15; // 0 = 关闭自动刷新
  bool redUp = true; // 红涨绿跌
  int themeMode = 0; // 0 系统 / 1 浅 / 2 深
  int sortMode = 0; // 0 自定义(置顶) / 1 估值涨幅降 / 2 升 / 3 市值降 / 4 名称

  // ---------- 自选基金 ----------
  final List<FundItem> funds = [];
  final Map<String, FundQuote> fundQuotes = {};
  final Map<String, EstBuffer> estBuffers = {};

  // ---------- 大盘 ----------
  final Map<String, IndexQuote> indexQuotes = {};
  final Map<String, List<TrendPoint>> indexTrends = {};
  final Map<String, int> indexTrendsAt = {};
  MarketBreadth? breadth;

  // ---------- 板块 ----------
  final Map<int, List<Sector>> _sectorCache = {};
  final Map<int, int> _sectorAt = {};
  final Map<String, List<SectorMember>> _memberCache = {};
  final Map<String, int> _memberAt = {};

  // ---------- 估值分时（聚合重仓股） ----------
  final Map<String, List<TrendPoint>> estTrendCache = {};
  final Map<String, int> _estTrendAt = {};
  final Set<String> _estTrendBusy = {};

  DateTime? fundsUpdatedAt;
  DateTime? marketUpdatedAt;
  String? fundsError;
  String? marketError;

  Timer? _timer;
  bool _fundsBusy = false;
  bool _marketBusy = false;

  /// 初始化：读取本地数据并启动。
  Future<void> init() async {
    funds.addAll(await Store.loadFunds());
    trades.addAll(await Store.loadTrades());
    refreshSecs = await Store.loadRefreshSecs();
    redUp = await Store.loadRedUp();
    themeMode = await Store.loadThemeMode();
    sortMode = await Store.loadSortMode();
    // 净值/估值与大盘行情并行拉取，缩短启动等待。
    await Future.wait([refreshFunds(), refreshMarket()]);
    unawaited(ensureSectorPcts());
    _restartTimer();
  }

  // ================= 交易记录 =================

  /// 全部交易记录（加仓/减仓），按时间倒序存取。
  final List<TradeRecord> trades = [];

  List<TradeRecord> tradesOf(String code) =>
      trades.where((t) => t.code == code).toList()
        ..sort((a, b) => b.time.compareTo(a.time));

  /// 加仓（buy=true）或减仓（buy=false）：
  /// - 加仓：持有金额与成本同步增加，首次交易记为持有起始日；
  /// - 减仓：按减仓比例同步缩减持有金额与成本（收益按比例落袋）。
  Future<String?> addTrade(String code, bool buy, double amount) async {
    if (amount <= 0) return '金额必须大于 0';
    final f = funds.where((e) => e.code == code).firstOrNull;
    if (f == null) return '自选中不存在该基金';
    if (!buy && f.amount <= 0) return '请先录入持仓后再减仓';
    if (!buy && amount > f.amount) return '减仓金额不能超过持有金额';
    if (buy) {
      f.amount += amount;
      f.costAmount += amount;
      if (f.firstBuy == 0) f.firstBuy = DateTime.now().millisecondsSinceEpoch;
    } else {
      final r = amount / f.amount;
      f.costAmount *= (1 - r);
      f.amount -= amount;
    }
    trades.add(TradeRecord(
      code: code,
      time: DateTime.now().millisecondsSinceEpoch,
      buy: buy,
      amount: amount,
    ));
    await _persistFunds();
    await Store.saveTrades(trades);
    notifyListeners();
    return null;
  }

  // ================= 关联板块 =================

  /// 行业板块实时涨幅（板块名 → 涨跌幅%），用于基金关联板块展示。
  final Map<String, double> sectorPcts = {};
  int _sectorPctsAt = 0;
  bool _sectorPctsBusy = false;

  /// 拉取行业板块涨幅（10 分钟缓存）。
  Future<void> ensureSectorPcts() async {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (_sectorPctsBusy || now - _sectorPctsAt < 10 * 60 * 1000) return;
    _sectorPctsBusy = true;
    try {
      final list = await MarketApi.sectors(type: 2);
      sectorPcts
        ..clear()
        ..addEntries([for (final s in list) MapEntry(s.name, s.pct)]);
      _sectorPctsAt = DateTime.now().millisecondsSinceEpoch;
      notifyListeners();
      // 板块数据晚于首次估值刷新时，补一次重算使剩余仓位拟合生效。
      if (fundsUpdatedAt != null) unawaited(refreshFunds());
    } catch (_) {
    } finally {
      _sectorPctsBusy = false;
    }
  }

  /// 基金关联行业板块（用于 V2 剩余占比拟合与关联板块展示）：
  /// 优先基金行业配置的主行业（覆盖长尾持仓），
  /// 无行业配置时回退到重仓股行业按权重聚合的第一大行业。
  (String, double)? relatedSector(String code) {
    final q = fundQuotes[code];
    if (q == null) return null;
    if (q.mainIndustry.trim().isNotEmpty) {
      final pct = _matchSectorPct(q.mainIndustry.trim());
      if (!pct.isNaN) return (q.mainIndustry.trim(), pct);
    }
    final byIndustry = <String, double>{};
    for (final h in q.holdings) {
      final ind = h.industry.trim();
      if (ind.isEmpty || h.weight <= 0) continue;
      byIndustry[ind] = (byIndustry[ind] ?? 0) + h.weight;
    }
    if (byIndustry.isEmpty) return null;
    final top = (byIndustry.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value)))
        .first;
    return (top.key, _matchSectorPct(top.key));
  }

  /// 行业名 → 行业板块实时涨幅：精确匹配，未命中时按包含关系模糊匹配
  /// （行业配置与东财板块命名略有差异，如「制造业」vs「中证制造」）。
  double _matchSectorPct(String name) {
    if (name.isEmpty) return double.nan;
    final exact = sectorPcts[name];
    if (exact != null) return exact;
    for (final e in sectorPcts.entries) {
      if (e.key.contains(name) || name.contains(e.key)) return e.value;
    }
    return double.nan;
  }

  // ================= 自选基金 =================

  Future<void> addFund(
    FundSearchHit hit, {
    double amount = 0,
    double costAmount = 0,
    String group = '',
  }) async {
    if (funds.any((f) => f.code == hit.code)) return;
    funds.add(FundItem(
      code: hit.code,
      name: hit.name,
      type: hit.type,
      amount: amount,
      costAmount: costAmount,
      group: group,
      firstBuy: amount > 0 ? DateTime.now().millisecondsSinceEpoch : 0,
    ));
    await _persistFunds();
    unawaited(refreshFunds());
    notifyListeners();
  }

  Future<void> removeFund(String code) async {
    funds.removeWhere((f) => f.code == code);
    fundQuotes.remove(code);
    estBuffers.remove(code);
    await _persistFunds();
    notifyListeners();
  }

  /// 更新持仓。[days] 手动指定持有天数（重置首次买入日）；
  /// [pnl] 手动指定持有收益（按当前市值反推买入成本），优先于 [costAmount]。
  Future<void> updatePosition(
      String code, double amount, double costAmount,
      {String? group, int? days, double? pnl}) async {
    for (final f in funds) {
      if (f.code == code) {
        f.amount = amount;
        if (pnl != null) {
          final q = quoteOf(code);
          final mv = amount * (1 + (q?.hasEst ?? false ? q!.estPct : 0) / 100);
          f.costAmount = (mv - pnl).clamp(0, double.maxFinite).toDouble();
        } else {
          f.costAmount = costAmount;
        }
        if (group != null) f.group = group;
        if (days != null && days > 0) {
          f.firstBuy =
              DateTime.now().millisecondsSinceEpoch - days * 86400000;
        } else if (f.firstBuy == 0 && amount > 0) {
          f.firstBuy = DateTime.now().millisecondsSinceEpoch;
        }
        break;
      }
    }
    await _persistFunds();
    notifyListeners();
  }

  Future<void> setGroup(String code, String group) async {
    for (final f in funds) {
      if (f.code == code) {
        f.group = group;
        break;
      }
    }
    await _persistFunds();
    notifyListeners();
  }

  Future<void> togglePin(String code) async {
    for (final f in funds) {
      if (f.code == code) {
        f.pinned = !f.pinned;
        break;
      }
    }
    await _persistFunds();
    notifyListeners();
  }

  Future<void> setSortMode(int v) async {
    sortMode = v;
    await Store.saveSortMode(v);
    notifyListeners();
  }

  /// 已使用的分组名（排除未分组）。
  List<String> get groups =>
      funds.map((f) => f.group).where((g) => g.isNotEmpty).toSet().toList()
        ..sort();

  /// 排序后的自选列表。
  List<FundItem> get sortedFunds {
    final list = [...funds];
    double estOf(FundItem f) {
      final q = fundQuotes[f.code];
      if (q == null) return double.nan;
      return q.hasEst ? q.estPct : double.nan;
    }

    double valueOf(FundItem f) {
      if (f.amount <= 0) return -1;
      final q = fundQuotes[f.code];
      final estPct = (q != null && q.hasEst) ? q.estPct : 0.0;
      return f.amount * (1 + estPct / 100);
    }

    int cmp(FundItem a, FundItem b) {
      // 置顶始终优先。
      if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
      switch (sortMode) {
        case 1:
        case 2:
          final va = estOf(a);
          final vb = estOf(b);
          // 无估值的固定排在最后。
          if (va.isNaN && vb.isNaN) return 0;
          if (va.isNaN) return 1;
          if (vb.isNaN) return -1;
          return sortMode == 1 ? vb.compareTo(va) : va.compareTo(vb);
        case 3:
          return valueOf(b).compareTo(valueOf(a));
        case 4:
          return a.name.compareTo(b.name);
        default:
          return 0;
      }
    }

    list.sort(cmp);
    return list;
  }

  FundQuote? quoteOf(String code) => fundQuotes[code];

  EstBuffer bufferOf(String code) => estBuffers.putIfAbsent(code, EstBuffer.new);

  /// 估值分时曲线：聚合重仓股分时行情按权重加权（含股票仓位因子），
  /// 生成开盘至今的完整曲线，缓存 3 分钟。
  Future<List<TrendPoint>> loadEstTrend(String code,
      {bool force = false}) async {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final cached = estTrendCache[code];
    if (!force &&
        _estTrendBusy.contains(code) == false &&
        cached != null &&
        cached.isNotEmpty &&
        nowMs - (_estTrendAt[code] ?? 0) < 3 * 60 * 1000) {
      return cached;
    }
    final q = fundQuotes[code];
    if (q == null || q.holdings.isEmpty || q.nav <= 0) {
      return cached ?? const [];
    }
    if (_estTrendBusy.contains(code)) return cached ?? const [];
    _estTrendBusy.add(code);
    try {
      // 逐个拉取重仓股分时（串行避免触发限频）。
      final series = <Map<String, double>>[];
      final weights = <double>[];
      for (final h in q.holdings) {
        try {
          final r = await MarketApi.trend('${h.market}.${h.code}');
          if (r.points.isEmpty || r.preClose <= 0) continue;
          final m = <String, double>{
            for (final p in r.points) p.label: (p.value / r.preClose - 1) * 100,
          };
          series.add(m);
          weights.add(h.weight);
        } catch (_) {}
      }
      if (series.isEmpty) return cached ?? const [];
      final factor = q.stockPosition > 0 ? q.stockPosition / 100 : 1.0;
      final pts = Estimator.aggregateTrend([
        for (var i = 0; i < series.length; i++)
          (weight: weights[i], series: series[i]),
      ], factor: factor);
      if (pts.isNotEmpty) {
        estTrendCache[code] = pts;
        _estTrendAt[code] = nowMs;
        notifyListeners();
      }
      return estTrendCache[code] ?? cached ?? const [];
    } finally {
      _estTrendBusy.remove(code);
    }
  }

  /// 持仓汇总：市值 / 今日估算收益 / 累计估算收益。
  ///
  /// 以「持有金额」为基准：
  /// - 持仓市值 = Σ 持有金额 × (1 + 估算涨幅%)，无估值时按持有金额计；
  /// - 今日估算收益 = Σ 持有金额 × 估算涨幅%；
  /// - 持仓收益 = 市值 - Σ 买入成本（未录入成本的忽略）。
  /// 任一基金录入了持有金额即显示汇总。
  ({double marketValue, double todayPnl, double totalPnl, double totalCost, bool any, bool hasToday})
      summary() {
    var mv = 0.0, today = 0.0, total = 0.0, cost = 0.0;
    var any = false, hasToday = false;
    for (final f in funds) {
      if (f.amount <= 0) continue;
      any = true;
      final q = fundQuotes[f.code];
      final estPct = (q != null && q.hasEst) ? q.estPct : 0.0;
      final mv1 = f.amount * (1 + estPct / 100);
      mv += mv1;
      if (q != null && q.hasEst) {
        today += f.amount * estPct / 100;
        hasToday = true;
      }
      if (f.costAmount > 0) {
        cost += f.costAmount;
        total += mv1 - f.costAmount;
      }
    }
    return (
      marketValue: mv,
      todayPnl: today,
      totalPnl: total,
      totalCost: cost,
      any: any,
      hasToday: hasToday
    );
  }

  /// 混合估值：重仓部分实时市值 + 剩余仓位按第一大行业板块涨幅拟合。
  double? _hybridEst(FundQuote q, Map<String, Quote> quotes) {
    final sec = relatedSector(q.code);
    final secPct = sec == null ? double.nan : sec.$2;
    return Estimator.computeHybrid(
        q.holdings, quotes, q.stockPosition, secPct);
  }

  /// 确保基金行情可用：非自选基金（如从排行页进入详情）临时补拉净值与重仓股，
  /// 数据仅存内存，不会加入自选列表。
  Future<void> ensureFund(String code) async {
    if (fundQuotes[code] != null) return;
    final q = FundQuote(code: code);
    fundQuotes[code] = q;
    notifyListeners();
    try {
      final navs = await FundApi.navInfo([code]);
      final nav = navs[code];
      if (nav != null) {
        q.nav = nav.nav;
        q.accNav = nav.accNav;
        q.navDate = nav.navDate;
        q.navPct = nav.navPct;
      }
    } catch (_) {}
    try {
      q.holdings = await FundApi.holdings(code);
      q.holdingsUpdated = DateTime.now().millisecondsSinceEpoch;
      final secids = [for (final h in q.holdings) '${h.market}.${h.code}'];
      if (secids.isNotEmpty) {
        final quotes = await MarketApi.quotes(secids);
        final pct = _hybridEst(q, quotes);
        q.estPct = pct ?? double.nan;
        q.estNav = q.hasEst ? Estimator.estNav(q.nav, q.estPct) : q.nav;
      }
    } catch (_) {}
    notifyListeners();
  }

  /// 刷新自选估值。
  Future<void> refreshFunds() async {
    if (_fundsBusy) return;
    _fundsBusy = true;
    fundsError = null;
    try {
      final codes = funds.map((f) => f.code).toList();
      if (codes.isNotEmpty) {
        // 1+2 并行：最新净值与 6 小时过期的重仓股同时拉取。
        final now = DateTime.now().millisecondsSinceEpoch;
        final needHoldings = funds
            .where((f) =>
                !fundQuotes.containsKey(f.code) ||
                now - fundQuotes[f.code]!.holdingsUpdated > 6 * 3600 * 1000)
            .map((f) => f.code)
            .toList();
        await Future.wait([
          // 净值。
          () async {
            try {
              final navs = await FundApi.navInfo(codes);
              for (final f in funds) {
                final nav = navs[f.code];
                if (nav == null) continue;
                f.name = f.name.isEmpty ? nav.name : f.name;
                final q = fundQuotes.putIfAbsent(
                    f.code, () => FundQuote(code: f.code));
                q.nav = nav.nav;
                q.accNav = nav.accNav;
                q.navDate = nav.navDate;
                q.navPct = nav.navPct;
              }
            } catch (e) {
              fundsError = '净值获取失败';
            }
          }(),
          // 重仓股。
          Future.wait(needHoldings.map((code) async {
            try {
              final hs = await FundApi.holdings(code);
              final q = fundQuotes.putIfAbsent(code, () => FundQuote(code: code));
              q.holdings = hs;
              q.holdingsUpdated = now;
            } catch (_) {}
          })),
        ]);

        // 3. 批量行情并计算估值。
        final secids = <String>{
          for (final q in fundQuotes.values)
            for (final h in q.holdings) '${h.market}.${h.code}',
        }.toList();
        Map<String, Quote> quotes = {};
        if (secids.isNotEmpty) {
          try {
            quotes = await MarketApi.quotes(secids);
          } catch (_) {
            fundsError ??= '行情获取失败';
          }
        }
        for (final q in fundQuotes.values) {
          // 盘中：混合估值（重仓实时 + 剩余仓位板块拟合 + 现金）；
          // 收盘后当日净值公布（navDate=今天）时直接用真实日涨幅。
          var pct = _hybridEst(q, quotes);
          if (pct == null && q.navDate == _todayYmd()) {
            pct = q.navPct;
          }
          q.estPct = pct ?? double.nan;
          q.estNav = q.hasEst ? Estimator.estNav(q.nav, q.estPct) : q.nav;
          if (q.hasEst) {
            bufferOf(q.code).add(_hhmm(), q.estPct);
          }
        }
        fundsUpdatedAt = DateTime.now();
      }
    } finally {
      _fundsBusy = false;
      notifyListeners();
    }
  }

  /// 拉取基金详情（pingzhongdata），回填股票仓位与主行业（V2 拟合用）。
  Future<FundDetail?> loadDetail(String code) async {
    try {
      final d = await FundApi.detail(code);
      if (d != null) {
        final q = fundQuotes[code];
        if (q != null) {
          q.reportDate = d.reportDate;
          var changed = false;
          // 主行业：行业配置（覆盖长尾持仓）第一大行业。
          if (d.industries.isNotEmpty) {
            final top = (d.industries.toList()
                  ..sort((a, b) => b.$2.compareTo(a.$2)))
                .first;
            if (top.$1.trim().isNotEmpty && q.mainIndustry != top.$1.trim()) {
              q.mainIndustry = top.$1.trim();
              changed = true;
            }
          }
          if (d.positionRatio > 0 && q.stockPosition != d.positionRatio) {
            q.stockPosition = d.positionRatio;
            changed = true;
          }
          // 仓位或主行业更新后重算一次估值。
          if (changed) {
            try {
              final secids = [
                for (final h in q.holdings) '${h.market}.${h.code}'
              ];
              if (secids.isNotEmpty) {
                final quotes = await MarketApi.quotes(secids);
                final pct = _hybridEst(q, quotes);
                q.estPct = pct ?? double.nan;
                q.estNav = q.hasEst ? Estimator.estNav(q.nav, q.estPct) : q.nav;
              }
            } catch (_) {}
          }
        }
        notifyListeners();
      }
      return d;
    } catch (_) {
      return null;
    }
  }

  /// 详情页实时刷新重仓股行情。
  Future<void> refreshFundHoldingsLive(String code) async {
    final q = fundQuotes[code];
    if (q == null || q.holdings.isEmpty) return;
    try {
      final secids = [for (final h in q.holdings) '${h.market}.${h.code}'];
      final quotes = await MarketApi.quotes(secids);
      final pct = _hybridEst(q, quotes);
      q.estPct = pct ?? double.nan;
      q.estNav = q.hasEst ? Estimator.estNav(q.nav, q.estPct) : q.nav;
      notifyListeners();
    } catch (_) {}
  }

  // ================= 大盘 =================

  Future<void> refreshMarket() async {
    if (_marketBusy) return;
    _marketBusy = true;
    marketError = null;
    try {
      final all = [
        ...MarketApi.aIndices,
        ...MarketApi.hkIndices,
        ...MarketApi.globalIndices,
      ];
      final secids = all.map((e) => e.$1).toList();
      try {
        var quotes = await MarketApi.quotes(secids);
        // 个别指数（如恒生科技）偶发被批量请求丢弃，单独补拉一次。
        final missing = [
          for (final s in secids)
            if (!quotes.containsKey(s)) s,
        ];
        if (missing.isNotEmpty) {
          try {
            quotes.addAll(await MarketApi.quotes(missing));
          } catch (_) {}
        }
        for (final (secid, name) in all) {
          final q = quotes[secid];
          if (q == null) continue;
          final old = indexQuotes[secid];
          indexQuotes[secid] = IndexQuote(
            secid: secid,
            name: name,
            price: q.price,
            pct: q.pct,
            change: q.change,
            trend: old?.trend ?? const [],
          );
        }
        marketUpdatedAt = DateTime.now();
      } catch (_) {
        marketError = '行情获取失败';
      }
      try {
        breadth = await MarketApi.breadth();
      } catch (_) {}
    } finally {
      _marketBusy = false;
      notifyListeners();
    }
  }

  /// 拉取指数分时（缓存 3 分钟）。
  Future<List<TrendPoint>> loadIndexTrend(String secid,
      {bool force = false}) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (!force &&
        indexTrends.containsKey(secid) &&
        now - (indexTrendsAt[secid] ?? 0) < 3 * 60 * 1000) {
      return indexTrends[secid]!;
    }
    try {
      final r = await MarketApi.trend(secid);
      indexTrends[secid] = r.points;
      indexTrendsAt[secid] = now;
      notifyListeners();
      return r.points;
    } catch (_) {
      return indexTrends[secid] ?? const [];
    }
  }

  // ================= 板块 =================

  /// 行业(2)/概念(3) 板块列表，缓存 60 秒。
  Future<List<Sector>> sectors(int type, {bool force = false}) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (!force &&
        _sectorCache.containsKey(type) &&
        now - (_sectorAt[type] ?? 0) < 60 * 1000) {
      return _sectorCache[type]!;
    }
    try {
      final list = await MarketApi.sectors(type: type);
      _sectorCache[type] = list;
      _sectorAt[type] = now;
      notifyListeners();
      return list;
    } catch (_) {
      return _sectorCache[type] ?? const [];
    }
  }

  /// 板块成分股，缓存 60 秒。
  Future<List<SectorMember>> sectorMembers(String bkCode,
      {bool force = false}) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (!force &&
        _memberCache.containsKey(bkCode) &&
        now - (_memberAt[bkCode] ?? 0) < 60 * 1000) {
      return _memberCache[bkCode]!;
    }
    try {
      final list = await MarketApi.sectorMembers(bkCode);
      _memberCache[bkCode] = list;
      _memberAt[bkCode] = now;
      notifyListeners();
      return list;
    } catch (_) {
      return _memberCache[bkCode] ?? const [];
    }
  }

  // ================= 定时与设置 =================

  Future<void> setRefreshSecs(int v) async {
    refreshSecs = v;
    await Store.saveRefreshSecs(v);
    _restartTimer();
    notifyListeners();
  }

  Future<void> setRedUp(bool v) async {
    redUp = v;
    await Store.saveRedUp(v);
    notifyListeners();
  }

  Future<void> setThemeMode(int v) async {
    themeMode = v;
    await Store.saveThemeMode(v);
    notifyListeners();
  }

  Future<void> clearAll() async {
    funds.clear();
    fundQuotes.clear();
    estBuffers.clear();
    await _persistFunds();
    notifyListeners();
  }

  // ================= 自选备份导入 / 导出 =================

  /// 导出自选备份为 JSON 字符串（含持仓配置与交易记录）。
  String exportFundsJson() {
    return const JsonEncoder.withIndent('  ').convert({
      'app': 'funds-valuation',
      'format': 1,
      'exportedAt': DateTime.now().toIso8601String(),
      'fundCount': funds.length,
      'funds': funds.map((e) => e.toJson()).toList(),
      'trades': trades.map((e) => e.toJson()).toList(),
    });
  }

  /// 解析并导入自选备份 JSON。
  /// - [replace]=true：覆盖现有全部自选与交易记录；
  /// - [replace]=false：合并，已存在的代码以备份内容为准，新代码追加。
  /// 兼容顶层直接为基金数组的简单格式。
  Future<ImportResult> importFundsJson(String raw,
      {required bool replace}) async {
    final dynamic decoded;
    try {
      decoded = jsonDecode(raw);
    } catch (_) {
      throw const FormatException('文件不是有效的 JSON');
    }

    final List rawFunds;
    final List rawTrades;
    if (decoded is Map) {
      final f = decoded['funds'];
      if (f is! List) {
        throw const FormatException('备份文件缺少 funds 列表');
      }
      rawFunds = f;
      rawTrades = decoded['trades'] is List ? decoded['trades'] as List : [];
    } else if (decoded is List) {
      rawFunds = decoded;
      rawTrades = const [];
    } else {
      throw const FormatException('备份文件格式不正确');
    }

    final incoming = <FundItem>[];
    var invalid = 0;
    for (final e in rawFunds) {
      if (e is! Map) {
        invalid++;
        continue;
      }
      try {
        final item = FundItem.fromJson(Map<String, dynamic>.from(e));
        if (item.code.trim().isEmpty || item.name.trim().isEmpty) {
          invalid++;
          continue;
        }
        incoming.add(item);
      } catch (_) {
        invalid++;
      }
    }
    if (incoming.isEmpty) {
      throw const FormatException('文件中没有可导入的有效基金');
    }

    var added = 0;
    var updated = 0;
    if (replace) {
      funds.clear();
      fundQuotes.clear();
      estBuffers.clear();
      trades.clear();
      funds.addAll(incoming);
      added = incoming.length;
    } else {
      final byCode = {for (final f in funds) f.code: f};
      for (final item in incoming) {
        final old = byCode[item.code];
        if (old == null) {
          funds.add(item);
          byCode[item.code] = item;
          added++;
        } else {
          final i = funds.indexOf(old);
          funds[i] = item;
          fundQuotes.remove(item.code);
          updated++;
        }
      }
    }

    // 交易记录：覆盖模式直接替换；合并模式按 (代码,时间,方向,金额) 去重，
    // 仅保留属于当前自选基金的记录。
    final incomingTrades = <TradeRecord>[];
    for (final e in rawTrades) {
      if (e is! Map) continue;
      try {
        incomingTrades
            .add(TradeRecord.fromJson(Map<String, dynamic>.from(e)));
      } catch (_) {}
    }
    final codes = funds.map((f) => f.code).toSet();
    if (replace) {
      trades
        ..clear()
        ..addAll(incomingTrades.where((t) => codes.contains(t.code)));
    } else {
      final exist = trades
          .map((t) => '${t.code}|${t.time}|${t.buy}|${t.amount}')
          .toSet();
      for (final t in incomingTrades) {
        if (!codes.contains(t.code)) continue;
        final key = '${t.code}|${t.time}|${t.buy}|${t.amount}';
        if (exist.add(key)) trades.add(t);
      }
    }

    await _persistFunds();
    await Store.saveTrades(trades);
    unawaited(refreshFunds());
    notifyListeners();
    return ImportResult(
      total: incoming.length,
      added: added,
      updated: updated,
      trades: incomingTrades.length,
      invalid: invalid,
      replaced: replace,
    );
  }

  void _restartTimer() {
    _timer?.cancel();
    if (refreshSecs <= 0) return;
    _timer = Timer.periodic(Duration(seconds: refreshSecs), (_) {
      unawaited(refreshFunds());
      unawaited(refreshMarket());
    });
  }

  Future<void> _persistFunds() => Store.saveFunds(funds);

  static String _hhmm() {
    final n = DateTime.now();
    return '${n.hour.toString().padLeft(2, '0')}:'
        '${n.minute.toString().padLeft(2, '0')}';
  }

  /// 今天 yyyy-MM-dd（与净值日期格式一致）。
  static String _todayYmd() {
    final n = DateTime.now();
    return '${n.year}-${n.month.toString().padLeft(2, '0')}-'
        '${n.day.toString().padLeft(2, '0')}';
  }
}
