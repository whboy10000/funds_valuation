import '../models.dart';
import 'market_api.dart';

/// 自研实时估值引擎。
///
/// 官方盘中估值已下线，这里用「重仓股权重 × 实时行情」计算：
///
///   估算涨幅 = 股票仓位 × Σ(重仓股占比ᵢ × 该股实时涨跌幅ᵢ) / Σ(重仓股占比ᵢ)
///
/// - 未披露股票仓位时按满仓估算（指数基金误差较小）。
/// - 行情缺失的持仓（停牌/跨市场收盘）自动从分母剔除。
/// - 无股票持仓（债券/货币/QDII 无行情）返回 null。
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

  /// 混合估值模型（市值法）：
  ///
  ///   估算涨幅 = [Σ(重仓股权重ᵢ × 实时涨幅ᵢ) + 剩余仓位 × 板块拟合涨幅] / 100
  ///
  /// 即「重仓股市值 + 非重仓拟合市值 + 现金（无涨幅）」三部分相加：
  ///
  /// - 重仓股部分：前十大重仓按权重 × 实时行情（Mark-to-Market）；
  /// - 非重仓/长尾部分：剩余仓位 = 股票仓位 − 重仓股权重和，
  ///   用基金第一大行业板块的实时涨幅做收益拟合；
  /// - 现金部分：无涨幅贡献（分母为总资产 100）。
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
