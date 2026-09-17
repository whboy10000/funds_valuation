import 'package:flutter_test/flutter_test.dart';

import 'package:funds_valuation/models.dart';
import 'package:funds_valuation/services/estimator.dart';
import 'package:funds_valuation/services/fund_api.dart';
import 'package:funds_valuation/services/market_api.dart';

void main() {
  group('Estimator', () {
    test('按持仓权重加权计算估值', () {
      final holdings = [
        FundHolding(code: '600519', name: '贵州茅台', weight: 10, market: '1', industry: '食品饮料'),
        FundHolding(code: '00700', name: '腾讯控股', weight: 5, market: '116', industry: '传媒'),
      ];
      final quotes = {
        '1.600519': const Quote(price: 100, pct: 2, change: 2),
        '116.00700': const Quote(price: 400, pct: -1, change: -4),
      };
      // (10*2 + 5*-1) / 15 = 1.0；仓位 80% → 0.8
      final pct = Estimator.compute(holdings, quotes, 80);
      expect(pct, closeTo(0.8, 1e-9));
    });

    test('无持仓返回 null', () {
      expect(Estimator.compute([], const {}, 90), isNull);
    });

    test('行情缺失时从分母剔除', () {
      final holdings = [
        FundHolding(code: '600519', name: '贵州茅台', weight: 10, market: '1', industry: ''),
        FundHolding(code: 'AAPL', name: '苹果', weight: 10, market: '105', industry: ''),
      ];
      final quotes = {
        '1.600519': const Quote(price: 100, pct: 3, change: 3),
      };
      final pct = Estimator.compute(holdings, quotes, 100);
      expect(pct, closeTo(3, 1e-9));
    });

    test('混合估值：重仓实时 + 剩余板块拟合 + 现金', () {
      final hs = [
        FundHolding(code: '600519', name: '贵州茅台', weight: 30, market: '1', industry: '白酒'),
        FundHolding(code: '601318', name: '中国平安', weight: 20, market: '1', industry: '保险'),
      ];
      final quotes = {
        '1.600519': const Quote(price: 100, pct: 2, change: 2),
        '1.601318': const Quote(price: 50, pct: 4, change: 2),
      };
      // 仓位 80：重仓 50 → (30×2+20×4)/100 = 1.4；剩余 30×板块 1% = 0.3；现金 0。
      expect(Estimator.computeHybrid(hs, quotes, 80, 1.0), closeTo(1.7, 1e-9));
      // 无仓位披露：退化为重仓归一化 (30×2+20×4)/50 = 2.8。
      expect(Estimator.computeHybrid(hs, quotes, 0, 1.0), closeTo(2.8, 1e-9));
      // 板块数据未就绪：剩余部分贡献 0。
      expect(
          Estimator.computeHybrid(hs, quotes, 80, double.nan),
          closeTo(1.4, 1e-9));
      // 重仓权重超出仓位：剩余部分为 0。
      expect(Estimator.computeHybrid(hs, quotes, 40, 5.0), closeTo(1.4, 1e-9));
      // V2 现金剥离：仓位 50（现金 50 不参与），重仓 40 → (40×2+10×4)/100 = 1.2。
      final hs2 = [
        FundHolding(code: '600519', name: '贵州茅台', weight: 40, market: '1', industry: '白酒'),
      ];
      final quotes2 = {
        '1.600519': const Quote(price: 100, pct: 2, change: 2),
      };
      expect(Estimator.computeHybrid(hs2, quotes2, 50, 4.0), closeTo(1.2, 1e-9));
    });

    test('estNav 推算', () {
      expect(Estimator.estNav(1.0, 2.5), closeTo(1.025, 1e-9));
    });
  });

  group('FundQuote', () {
    test('NaN 表示无估值', () {
      final q = FundQuote(code: '000001', nav: 1.5);
      expect(q.hasEst, isFalse);
      q.estPct = 1.23;
      expect(q.hasEst, isTrue);
      expect(q.estNav, 0);
    });
  });

  group('Estimator.aggregateTrend', () {
    test('并集时间轴 + 前向填充 + 加权', () {
      final pts = Estimator.aggregateTrend([
        (
          weight: 10,
          series: {'09:30': 1.0, '09:31': 2.0, '09:32': 4.0}
        ),
        (weight: 10, series: {'09:30': 3.0}),
      ]);
      expect(pts.map((p) => p.label), ['09:30', '09:31', '09:32']);
      expect(pts[0].value, closeTo(2.0, 1e-9)); // (1+3)/2
      expect(pts[1].value, closeTo(2.5, 1e-9)); // (2+3)/2 前向填充
      expect(pts[2].value, closeTo(3.5, 1e-9)); // (4+3)/2
    });

    test('仓位因子', () {
      final pts = Estimator.aggregateTrend(
        [(weight: 1, series: {'09:30': 5.0})],
        factor: 0.8,
      );
      expect(pts.single.value, closeTo(4.0, 1e-9));
    });

    test('空输入返回空', () {
      expect(Estimator.aggregateTrend(const []), isEmpty);
    });
  });

  group('FundApi.parseRank', () {
    test('解析排行数据行', () {
      const body = 'var rankData = {datas:['
          '"001040,新华策略精选股票A,XHCLJXGPA,2026-09-16,3.9623,4.4003,6.99,7.57,'
          '10.48,-1.8,43.56,85.28,364.62,211.99,77.01,395.32,2015-03-31,1,244.4580,1.50%,0.15%,1,0.15%,1,115.04",'
          '"027611,富国中证工程机械主题ETF发起式联接C,FGZZGCJXZTETFFQSLJC,2026-09-16,'
          '0.9506,0.9506,-2.71,-6.58,-7.07,,,,,,,-4.94,2026-07-07,1,-4.94,,0.00%,,,,"],'
          'allRecords:20356,allNum:20356};';
      final items = FundApi.parseRankItems(FundApi.parseRankBody(body));
      expect(items.length, 2);
      expect(items[0].code, '001040');
      expect(items[0].name, '新华策略精选股票A');
      expect(items[0].pct, closeTo(6.99, 1e-9));
      expect(items[0].navDate, '2026-09-16');
      expect(items[1].pct, closeTo(-2.71, 1e-9));
    });

    test('空数据与无涨幅行被跳过', () {
      final items = FundApi.parseRankItems(FundApi.parseRankBody(
          'var rankData = {datas:["001040,某基金,XXX,2026-09-16,1,1,,,"]};'));
      expect(items, isEmpty);
      expect(FundApi.parseRankItems(FundApi.parseRankBody('bad')), isEmpty);
    });

    test('全市场涨跌分布聚合', () {
      const body = 'var rankData = {datas:['
          '"001,A,X,2026-09-16,1,1,2.5",'
          '"002,B,X,2026-09-16,1,1,-1.0",'
          '"003,C,X,2026-09-16,1,1,0.0",'
          '"004,D,X,2026-09-16,1,1,0.5"],allRecords:4};';
      final s = FundApi.parseRankStats(FundApi.parseRankBody(body) ?? const []);
      expect(s.total, 4);
      expect(s.up, 2);
      expect(s.down, 1);
      expect(s.flat, 1);
      expect(s.avg, closeTo((2.5 - 1.0 + 0.0 + 0.5) / 4, 1e-9));
      expect(s.median, closeTo(0.25, 1e-9));
    });
  });

  group('FundItem 持久化', () {
    test('amount/costAmount/group 字段往返', () {
      final f = FundItem(
          code: '005827',
          name: '易方达蓝筹精选混合',
          amount: 5000.5,
          costAmount: 4800,
          group: '支付宝');
      final back = FundItem.fromJson(f.toJson());
      expect(back.group, '支付宝');
      expect(back.amount, closeTo(5000.5, 1e-9));
      expect(back.costAmount, closeTo(4800, 1e-9));
    });

    test('旧数据份额+成本自动换算为金额', () {
      final back = FundItem.fromJson({
        'code': '005827',
        'name': '易方达蓝筹精选混合',
        'shares': 1200.55,
        'cost': 1.532,
      });
      expect(back.amount, closeTo(1200.55 * 1.532, 1e-6));
      expect(back.costAmount, closeTo(1200.55 * 1.532, 1e-6));
      expect(back.group, '');
    });

    test('旧数据无 group 字段兼容', () {
      final back =
          FundItem.fromJson({'code': '005827', 'name': '易方达蓝筹精选混合'});
      expect(back.group, '');
      expect(back.amount, 0);
      expect(back.costAmount, 0);
    });
  });
}
