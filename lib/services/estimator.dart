import '../models.dart';
import 'market_api.dart';

/// 自研实时估值引擎 V2 —— 混合计算架构（行业板块拟合 + 现金剥离）。
///
/// 官方盘中估值已下线，估值涨幅由两部分实时计算：
///
///   估算涨幅% = [ Σ(重仓股占比ᵢ × 该股实时涨幅ᵢ)      ← 十大重仓（占总资金比）
///              + 剩余占比   × 主行业板块实时涨幅 ]     ← 长尾持仓按主行业拟合
///              / 100
///
/// - **重仓部分**：前十大重仓按「占净值比（= 占总资金比）× 实时行情」逐只市值化；
/// - **剩余部分**：剩余占比 = 股票仓位 − 重仓股权重和，
///   按基金主行业（行业配置第一大行业，覆盖长尾持仓）的板块实时涨幅拟合；
/// - **现金剥离**：现金占比 = 100 − 股票仓位，无涨幅贡献，不参与计算。
///
/// - 未披露股票仓位（≤ 0）时退化为重仓归一化（与 [compute] 一致）。
/// - 行情缺失的持仓（停牌/跨市场收盘）自动剔除。
/// - 无股票持仓（债券/货币/QDII 无行情）返回 null。
/// - 主行业板块涨幅为 NaN（板块数据未就绪）时剩余部分贡献 0。
class Estimator {
  /// 返回估算涨跌幅 %，无法估算返回 null。
  static double? compute(
    List<FundHolding> holdings,
    Map<String, Quote> quotes,
    double stockPosition,
  ) {
    if (holdings.isEmpty) return null;
    final factor = stockPosition > 0 ? stockPosition / 100.0 : 1.0;
    double wSum = 0, acc = 0;
    var quoted = 0;
    for (final h in holdings) {
      final q = quotes['${h.market}.${h.code}'];
      if (q == null || q.pct == 0 && q.price == 0) continue;
      wSum += h.weight;
      acc += h.weight * q.pct;
      quoted++;
      h.livePct = q.pct;
    }
    if (wSum <= 0 || quoted == 0) return null;
    return factor * acc / wSum;
  }

  /// 由昨收净值推算估值净值。
  static double estNav(double nav, double estPct) => nav * (1 + estPct / 100);

  /// V2 混合估值（市值法 + 现金剥离）：
  ///
  ///   估算涨幅 = [Σ(重仓股权重ᵢ × 实时涨幅ᵢ) + 剩余占比 × 主行业板块涨幅] / 100
  ///
  /// - 重仓部分：前十大重仓按占总资金比 × 实时行情（Mark-to-Market）；
  /// - 剩余部分：剩余占比 = 股票仓位 − 重仓股权重和，
  ///   按 [sectorPct]（基金主行业板块实时涨幅）拟合；
  /// - 现金部分：100 − 股票仓位，不参与计算（无涨幅贡献）。
  ///
  /// 未披露股票仓位（[stockPosition] ≤ 0）时退化为重仓归一化（与 [compute] 一致）；
  /// [sectorPct] 为 NaN（板块数据未就绪）时剩余部分贡献 0。
  static double? computeHybrid(
    List<FundHolding> holdings,
    Map<String, Quote> quotes,
    double stockPosition,
    double sectorPct,
  ) {
    if (holdings.isEmpty) return null;
    double acc = 0, wSum = 0;
    var quoted = 0;
    for (final h in holdings) {
      final q = quotes['${h.market}.${h.code}'];
      if (q == null || q.pct == 0 && q.price == 0) continue;
      acc += h.weight * q.pct;
      wSum += h.weight;
      quoted++;
      h.livePct = q.pct;
    }
    if (quoted == 0 || wSum <= 0) return null;
    final hasPos = stockPosition > 0 && stockPosition <= 100;
    if (!hasPos) return acc / wSum;
    final rest = (stockPosition - wSum).clamp(0.0, 100.0);
    final restPart = (sectorPct.isNaN || rest <= 0) ? 0.0 : rest * sectorPct;
    return (acc + restPart) / 100;
  }

  /// 聚合多只股票的「分钟标签 → 涨跌幅%」序列为加权估值分时曲线。
  ///
  /// - 时间轴取所有序列标签的并集（升序）；
  /// - 某股票在某分钟无行情时沿用其最近一次涨跌幅（前向填充）；
  /// - 每个时刻的有效权重 = 已有行情股票的权重和（仓位因子见 [factor]）。
  static List<TrendPoint> aggregateTrend(
    List<({double weight, Map<String, double> series})> inputs, {
    double factor = 1.0,
  }) {
    if (inputs.isEmpty) return const [];
    final labels =
        <String>{for (final e in inputs) ...e.series.keys}.toList()..sort();
    final last = List<double>.filled(inputs.length, double.nan);
    final pts = <TrendPoint>[];
    for (final label in labels) {
        var sum = 0.0, wEff = 0.0;
        for (var i = 0; i < inputs.length; i++) {
          final v = inputs[i].series[label];
          if (v != null) last[i] = v;
          if (!last[i].isNaN) {
            sum += last[i] * inputs[i].weight;
            wEff += inputs[i].weight;
          }
        }
      if (wEff <= 0) continue;
      pts.add(TrendPoint(label, factor * sum / wEff));
    }
    return pts;
  }
}
