/// 数据模型定义。
library;

/// 用户自选的基金（含本地持仓配置）。
class FundItem {
  FundItem({
    required this.code,
    required this.name,
    this.type = '',
    this.amount = 0,
    this.costAmount = 0,
    this.pinned = false,
    this.group = '',
    this.firstBuy = 0,
  });

  /// 基金代码，如 005827。
  String code;

  /// 基金简称。
  String name;

  /// 基金类型描述，如「指数型-股票」。
  String type;

  /// 持有金额（元，以昨日市值计），0 表示未配置。
  double amount;

  /// 买入成本总金额（元），0 表示未配置。
  double costAmount;

  /// 是否置顶。
  bool pinned;

  /// 分组/渠道，如「支付宝」「天天基金」；空表示未分组。
  String group;

  /// 首次买入/录入持仓时间（毫秒时间戳），0 表示未知（用于持有天数）。
  int firstBuy;

  /// 持有天数（按自然日），未录入持仓返回 0。
  int get holdingDays {
    if (firstBuy <= 0) return 0;
    final start = DateTime.fromMillisecondsSinceEpoch(firstBuy);
    final now = DateTime.now();
    final a = DateTime(start.year, start.month, start.day);
    final b = DateTime(now.year, now.month, now.day);
    return b.difference(a).inDays + 1;
  }

  FundItem copyWith({
    String? code,
    String? name,
    String? type,
    double? amount,
    double? costAmount,
    bool? pinned,
    String? group,
    int? firstBuy,
  }) =>
      FundItem(
        code: code ?? this.code,
        name: name ?? this.name,
        type: type ?? this.type,
        amount: amount ?? this.amount,
        costAmount: costAmount ?? this.costAmount,
        pinned: pinned ?? this.pinned,
        group: group ?? this.group,
        firstBuy: firstBuy ?? this.firstBuy,
      );

  Map<String, dynamic> toJson() => {
        'code': code,
        'name': name,
        'type': type,
        'amount': amount,
        'costAmount': costAmount,
        'pinned': pinned,
        'group': group,
        'firstBuy': firstBuy,
      };

  factory FundItem.fromJson(Map<String, dynamic> j) => FundItem(
        code: (j['code'] ?? '') as String,
        name: (j['name'] ?? '') as String,
        type: (j['type'] ?? '') as String,
        amount: (j['amount'] as num?)?.toDouble() ?? _legacyMoney(j),
        costAmount: (j['costAmount'] as num?)?.toDouble() ?? _legacyMoney(j),
        pinned: (j['pinned'] ?? false) as bool,
        group: (j['group'] ?? '') as String,
        firstBuy: (j['firstBuy'] as num?)?.toInt() ?? 0,
      );

  /// 旧版数据兼容：原字段为持有份额(份) × 成本单价(元/份)，换算为金额。
  static double _legacyMoney(Map<String, dynamic> j) {
    final shares = (j['shares'] as num?)?.toDouble() ?? 0;
    final cost = (j['cost'] as num?)?.toDouble() ?? 0;
    return shares > 0 && cost > 0 ? shares * cost : 0;
  }
}

/// 交易记录：加仓/减仓。
class TradeRecord {
  TradeRecord({
    required this.code,
    required this.time,
    required this.buy,
    required this.amount,
  });

  /// 基金代码。
  String code;

  /// 交易时间（毫秒时间戳）。
  int time;

  /// true 加仓 / false 减仓。
  bool buy;

  /// 交易金额（元）。
  double amount;

  Map<String, dynamic> toJson() =>
      {'code': code, 'time': time, 'buy': buy, 'amount': amount};

  factory TradeRecord.fromJson(Map<String, dynamic> j) => TradeRecord(
        code: (j['code'] ?? '') as String,
        time: (j['time'] as num?)?.toInt() ?? 0,
        buy: (j['buy'] ?? true) as bool,
        amount: (j['amount'] as num?)?.toDouble() ?? 0,
      );
}

/// 基金公司返回的最新净值信息。
class FundNavInfo {
  FundNavInfo({
    required this.code,
    required this.name,
    required this.nav,
    required this.accNav,
    required this.navDate,
    required this.navPct,
  });

  final String code;
  final String name;

  /// 单位净值（昨日收盘）。
  final double nav;

  /// 累计净值。
  final double accNav;

  /// 净值日期 YYYY-MM-DD。
  final String navDate;

  /// 昨日涨跌幅 %。
  final double navPct;
}

/// 重仓股。
class FundHolding {
  FundHolding({
    required this.code,
    required this.name,
    required this.weight,
    required this.market,
    required this.industry,
  });

  /// 股票代码，如 600519 / 00700。
  final String code;

  /// 股票简称。
  final String name;

  /// 占净值比例 %。
  final double weight;

  /// 东财市场号：0/1 沪深、116 港股、105/106/107 美股。
  final String market;

  /// 所属行业。
  final String industry;

  /// 实时涨跌幅 %（行情刷新后填充）。
  double livePct = double.nan;

  /// 较上期变化：新进 / 增加 / 减少 / 持平（对比上一季度重仓，空=未知）。
  String changeTag = '';
}

/// 一只基金的完整估值状态。
class FundQuote {
  FundQuote({
    required this.code,
    this.nav = 0,
    this.accNav = 0,
    this.navDate = '',
    this.navPct = 0,
    this.estPct = double.nan,
    this.estNav = 0,
    this.holdings = const [],
    this.stockPosition = 0,
    this.holdingsUpdated = 0,
    this.reportDate = '',
  });

  final String code;

  /// 昨日单位净值。
  double nav;
  double accNav;
  String navDate;

  /// 昨日涨跌幅 %。
  double navPct;

  /// 自算实时估值涨跌幅 %，NaN 表示无法估算。
  double estPct;

  /// 自算实时估值净值。
  double estNav;

  /// 重仓股列表。
  List<FundHolding> holdings;

  /// 最新股票仓位 %。
  double stockPosition;

  /// 持仓数据更新时间戳（毫秒）。
  int holdingsUpdated;

  /// 重仓股披露报告期，如 2026-06-30（与股票仓位同一季报周期）。
  String reportDate;

  /// 估值是否有效。
  bool get hasEst => !estPct.isNaN;
}

/// 分时点（估值采样或行情分时）。
class TrendPoint {
  const TrendPoint(this.label, this.value);

  /// 时间标签，如 09:30。
  final String label;

  /// 数值（估值涨跌幅或价格）。
  final double value;
}

/// 每日规模序列（估算口径）。
///
/// - 场内基金（ETF/LOF）：流通份额 × 每日收盘价（实时规模用总市值）；
/// - 场外基金：最新披露份额规模 × 每日单位净值（份额按季度，期间申赎未计入）。
class FundDailyScale {
  const FundDailyScale({
    required this.isEtf,
    required this.series,
    required this.latest,
    this.todayChg = double.nan,
    required this.shareYi,
  });

  /// 是否场内基金。
  final bool isEtf;

  /// 每日规模（亿），时间正序：(日期 yyyy-MM-dd, 规模亿)。
  final List<(String, double)> series;

  /// 最新规模（亿）。
  final double latest;

  /// 今日规模变化（亿，较上一交易日）。
  final double todayChg;

  /// 份额（亿份）。
  final double shareYi;
}

/// 自算估值分时缓冲。
class EstBuffer {
  final List<TrendPoint> points = [];

  void add(String label, double pct) {
    if (points.isNotEmpty && points.last.label == label) {
      points[points.length - 1] = TrendPoint(label, pct);
      return;
    }
    points.add(TrendPoint(label, pct));
    if (points.length > 300) points.removeAt(0);
  }
}

/// 指数行情。
class IndexQuote {
  const IndexQuote({
    required this.secid,
    required this.name,
    this.price = 0,
    this.pct = 0,
    this.change = 0,
    this.trend = const [],
  });

  final String secid;
  final String name;
  final double price;
  final double pct;
  final double change;

  /// 分时走势（可能为空）。
  final List<TrendPoint> trend;

  IndexQuote copyWith({double? price, double? pct, double? change, List<TrendPoint>? trend}) =>
      IndexQuote(
        secid: secid,
        name: name,
        price: price ?? this.price,
        pct: pct ?? this.pct,
        change: change ?? this.change,
        trend: trend ?? this.trend,
      );
}

/// 板块（行业/概念）行情。
class Sector {
  const Sector({
    required this.code,
    required this.name,
    required this.pct,
    required this.turnover,
    required this.netInflow,
    required this.upCount,
    required this.downCount,
    required this.leadStock,
    required this.leadStockPct,
  });

  /// 板块代码，如 BK1296。
  final String code;
  final String name;

  /// 涨跌幅 %。
  final double pct;

  /// 换手率 %。
  final double turnover;

  /// 主力净流入（元）。
  final double netInflow;

  /// 上涨家数。
  final int upCount;

  /// 下跌家数。
  final int downCount;

  /// 领涨股。
  final String leadStock;
  final double leadStockPct;
}

/// 板块成分股实时行情。
class SectorMember {
  const SectorMember({
    required this.code,
    required this.name,
    required this.price,
    required this.pct,
    this.turnover = 0,
    this.netInflow = 0,
  });

  final String code;
  final String name;

  /// 最新价。
  final double price;

  /// 涨跌幅 %。
  final double pct;

  /// 换手率 %。
  final double turnover;

  /// 主力净流入（元）。
  final double netInflow;
}

/// 涨跌分布（全市场）。
class MarketBreadth {
  const MarketBreadth({
    required this.up,
    required this.down,
    required this.flat,
    required this.buckets,
  });

  final int up;
  final int down;
  final int flat;

  /// 涨跌幅分布桶：key 为区间（正涨负跌），value 为家数。
  final List<MapEntry<int, int>> buckets;
}

/// 基金搜索结果。
class FundSearchHit {
  const FundSearchHit({
    required this.code,
    required this.name,
    required this.type,
    required this.company,
    required this.manager,
  });

  final String code;
  final String name;
  final String type;
  final String company;
  final String manager;
}

/// 全市场基金排行条目（按最新披露净值日增长率预排序）。
class FundRankItem {
  FundRankItem({
    required this.code,
    required this.name,
    required this.navDate,
    required this.nav,
    required this.pct,
  });

  final String code;
  final String name;

  /// 净值日期 YYYY-MM-DD。
  final String navDate;

  /// 单位净值。
  final double nav;

  /// 净值日增长率 %。
  final double pct;

  /// 自算实时估值涨跌幅 %，NaN 表示不可用（非股票持仓基金）。
  double estPct = double.nan;

  /// 排序依据：优先实时估值，不可用时退回净值日涨幅。
  double get livePct => estPct.isNaN ? pct : estPct;
}

/// 全市场基金涨跌分布统计。
class FundRankStats {
  const FundRankStats({
    required this.total,
    required this.up,
    required this.flat,
    required this.down,
    required this.avg,
    required this.median,
  });

  final int total;
  final int up;
  final int flat;
  final int down;

  /// 全市场平均涨幅 %。
  final double avg;

  /// 中位数涨幅 %。
  final double median;
}

/// 基金详情页数据（来自 pingzhongdata）。
class FundDetail {
  FundDetail({
    required this.name,
    required this.code,
    required this.managerName,
    required this.managerWorkTime,
    required this.managerSize,
    required this.managerStar,
    this.navTrend = const [],
    this.positionRatio = 0,
    this.reportDate = '',
    this.syl1m = '',
    this.syl3m = '',
    this.syl6m = '',
    this.syl1y = '',
    this.rate = '',
    this.sourceRate = '',
    this.minsg = '',
    this.holderInst = -1,
    this.holderPersonal = -1,
    this.holderReport = '',
    this.scales = const [],
    this.industries = const [],
    this.bonds = const [],
    this.fullName = '',
    this.setupDate = '',
    this.shareScale = '',
    this.custodian = '',
    this.radar = const [],
    this.radarAvr = '',
    this.rankNum = 0,
    this.rankTotal = 0,
    this.rankPct = -1,
    this.volat = -1,
    this.maxDrawdown = -1,
    this.sharpe = double.nan,
    this.alloc = const [],
    this.buyback = const [],
    this.positions = const [],
  });

  final String name;
  final String code;

  /// 基金经理。
  final String managerName;
  final String managerWorkTime;
  final String managerSize;
  final int managerStar;

  /// 历史净值走势 [时间戳ms, 单位净值]。
  final List<List<double>> navTrend;

  /// 最新股票仓位 %。
  final double positionRatio;

  /// 重仓股/仓位披露报告期，如 2026-06-30。
  final String reportDate;

  /// 阶段收益率（近1月/3月/6月/1年，字符串便于显示 --）。
  final String syl1m;
  final String syl3m;
  final String syl6m;
  final String syl1y;

  /// 申购费率 / 原费率 / 最低申购金额。
  final String rate;
  final String sourceRate;
  final String minsg;

  /// 持有人结构（最近披露期）：机构 / 个人占比 %，-1 表示无数据。
  final double holderInst;
  final double holderPersonal;
  final String holderReport;

  /// 资产规模变动（新→旧）：(报告期, 亿元)。
  final List<(String, double)> scales;

  /// 最新行业配置：(行业名, 占净值比 %)。
  final List<(String, double)> industries;

  /// 业绩评价（标题, 内容）已并入能力评分卡，不再单独存储。

  /// 重仓债券：(名称, 占净值比 %)。
  final List<(String, double)> bonds;

  /// 概况补充（f10 基本信息）：基金全称 / 成立日期 / 份额规模 / 托管人。
  final String fullName;
  final String setupDate;
  final String shareScale;
  final String custodian;

  /// 能力评分雷达：(维度名, 得分 0~100)。
  final List<(String, double)> radar;

  /// 能力评分综合分（字符串便于显示 --）。
  final String radarAvr;

  /// 同类排名：最新排名 / 同类总数 / 最新百分位 %（越小越靠前，-1 无数据）。
  final int rankNum;
  final int rankTotal;
  final double rankPct;

  /// 特色数据（自算）：年化波动率 % / 最大回撤 %（-1 无数据）/ 夏普比率。
  final double volat;
  final double maxDrawdown;
  final double sharpe;

  /// 资产配置趋势（新→旧）：(报告期, 股票%, 债券%, 现金%)。
  final List<(String, double, double, double)> alloc;

  /// 申赎与份额（新→旧）：(报告期, 申购亿份, 赎回亿份, 总份额亿份)。
  final List<(String, double, double, double)> buyback;

  /// 股票仓位历史（新→旧）：(报告期, 仓位 %)。
  final List<(String, double)> positions;
}

/// 基金档案（f10 页面懒加载）：概况补充 + 分红配送 + 经理变动。
class FundProfile {
  const FundProfile({
    this.fullName = '',
    this.setupDate = '',
    this.assetScale = '',
    this.shareScale = '',
    this.custodian = '',
    this.company = '',
    this.shareYi = 0,
    this.dividends = const [],
    this.mgrChanges = const [],
  });

  /// 概况补充：基金全称 / 成立日期 / 资产规模 / 份额规模 / 托管人 / 管理人（公司）。
  final String fullName;
  final String setupDate;
  final String assetScale;
  final String shareScale;
  final String custodian;
  final String company;

  /// 份额规模数值（亿份，由 shareScale 解析；0 表示未披露）。
  final double shareYi;

  /// 分红记录（新→旧）：(年份, 权益登记日, 除息日, 每10份分红, 发放日)。
  final List<(String, String, String, String, String)> dividends;

  /// 经理变动（新→旧）：(起始期, 截止期, 基金经理, 任职期间, 任职回报)。
  final List<(String, String, String, String, String)> mgrChanges;
}
